import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_loading_policy.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_quality_profile.dart';
import '../widgets/copilot_start_sheet.dart';
import '../widgets/map_widget.dart';
import 'lean_drive_screen.dart';
import 'lean_route_detail_screen.dart';

enum _RouteLens { all, nearby, sweeper, tight, flow, loop }

enum _RouteMapMode { wide, balanced, close }

class LeanRouteFinderScreen extends StatefulWidget {
  const LeanRouteFinderScreen({super.key});

  @override
  State<LeanRouteFinderScreen> createState() => _LeanRouteFinderScreenState();
}

class _LeanRouteFinderScreenState extends State<LeanRouteFinderScreen> {
  int _selectedIndex = 0;
  int _recenterSignal = 0;
  _RouteLens _lens = _RouteLens.all;
  LatLng? _mapCenterPoint;
  LatLng? _lastSearchPoint;
  String? _localStatusMessage;
  double _mapZoom = 11.0;

  @override
  void initState() {
    super.initState();
    unawaited(_searchCurrentLocation());
  }

  Future<void> _searchHere() async {
    final point = _mapCenterPoint ?? await _resolveSearchPoint();
    if (!mounted || point == null) return;
    await _fetchAtPoint(point);
  }

  Future<void> _searchCurrentLocation() async {
    final point = await _resolveSearchPoint();
    if (!mounted || point == null) return;
    await _fetchAtPoint(point);
  }

  Future<LatLng?> _resolveSearchPoint() async {
    final location = context.read<LocationService>();
    await location.requestPermission();
    if (!mounted) return null;
    if (!location.hasPermission && !location.hasBestKnownLocation) {
      setState(() => _localStatusMessage = location.lastFailureReason);
      return null;
    }
    await location.startTracking();
    final point = await location.ensureLiveLocation();
    if (!mounted) return point;
    setState(() {
      _localStatusMessage = point == null ? '현재 위치를 확인하지 못했어요.' : null;
    });
    return point;
  }

  Future<void> _fetchAtPoint(LatLng point) async {
    _lastSearchPoint = point;
    final settings = context.read<SettingsService>();
    final routes = context.read<RouteService>();
    routes.searchRadiusKm = settings.searchRadiusKm;
    routes.filterStrength = settings.routeFilterStrength;
    final recommendedLimit = _recommendedVisibleLimitForRadius(
      settings.searchRadiusKm,
    );
    if (routes.visibleRouteLimit < recommendedLimit) {
      routes.visibleRouteLimit = recommendedLimit;
    }
    await routes.fetchRoutes(point.lat, point.lng);
    if (!mounted) return;
    setState(() {
      _lens = _RouteLens.all;
      _selectedIndex = 0;
      _localStatusMessage = null;
    });
    final first = routes.routes.isNotEmpty ? routes.routes.first : null;
    if (first != null) routes.selectRoute(first);
  }

  Future<void> _selectRadius() async {
    final current = context.read<SettingsService>().searchRadiusKm;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteOptionSheet(
        title: '검색 반경',
        selectedValue: current,
        options: const [
          _RouteOption(30, '30km 근처', '바로 주변 후보만 빠르게 봅니다.'),
          _RouteOption(50, '50km 균형', '기본 추천 범위입니다.'),
          _RouteOption(100, '100km 넓게', '후보가 적을 때 넓혀 봅니다.'),
          _RouteOption(160, '160km 당일치기', '반나절 코스까지 탐색합니다.'),
          _RouteOption(220, '220km 원정', '멀리 있는 와인딩까지 봅니다.'),
        ],
      ),
    );
    if (!mounted || selected == null || selected == current) return;

    await context.read<SettingsService>().setSearchRadius(selected);
    final point =
        _mapCenterPoint ?? _lastSearchPoint ?? await _resolveSearchPoint();
    if (!mounted || point == null) return;
    _lastSearchPoint = point;
    final routes = context.read<RouteService>();
    final recommendedLimit = _recommendedVisibleLimitForRadius(selected);
    if (routes.visibleRouteLimit < recommendedLimit) {
      routes.visibleRouteLimit = recommendedLimit;
    }
    await routes.changeRadius(selected, point.lat, point.lng);
    if (!mounted) return;
    _resetVisibleSelection(routes.routes);
  }

  int _recommendedVisibleLimitForRadius(int radiusKm) {
    if (radiusKm >= 160) return 32;
    if (radiusKm >= 100) return 24;
    return 16;
  }

  Future<void> _selectVisibleLimit() async {
    final service = context.read<RouteService>();
    final current = service.visibleRouteLimit;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteOptionSheet(
        title: '표시 개수',
        selectedValue: current,
        options: const [
          _RouteOption(8, '8개', '지도와 티켓을 가장 깔끔하게 유지합니다.'),
          _RouteOption(16, '16개', '기본 탐색 개수입니다.'),
          _RouteOption(24, '24개', '더 많은 후보를 비교합니다.'),
          _RouteOption(32, '32개', '최대한 넓게 훑어봅니다.'),
        ],
      ),
    );
    if (!mounted || selected == null || selected == current) return;

    final point =
        _mapCenterPoint ?? _lastSearchPoint ?? await _resolveSearchPoint();
    if (!mounted || point == null) return;
    _lastSearchPoint = point;
    await service.changeVisibleRouteLimit(selected, point.lat, point.lng);
    if (!mounted) return;
    _resetVisibleSelection(service.routes);
  }

  Future<void> _selectFilterStrength() async {
    final settings = context.read<SettingsService>();
    final current = settings.routeFilterStrength;
    final selected = await showModalBottomSheet<RouteFilterStrength>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteStrengthSheet(selectedValue: current),
    );
    if (!mounted || selected == null || selected == current) return;
    await _applyFilterStrength(selected);
  }

  Future<void> _applyFilterStrength(RouteFilterStrength strength) async {
    final settings = context.read<SettingsService>();
    await settings.setRouteFilterStrength(strength);
    final point =
        _mapCenterPoint ?? _lastSearchPoint ?? await _resolveSearchPoint();
    if (!mounted || point == null) return;
    _lastSearchPoint = point;
    final service = context.read<RouteService>();
    await service.changeFilterStrength(strength, point.lat, point.lng);
    if (!mounted) return;
    _resetVisibleSelection(service.routes);
  }

  void _resetVisibleSelection(List<RevvRoute> routes) {
    setState(() {
      _lens = _RouteLens.all;
      _selectedIndex = 0;
    });
    if (routes.isNotEmpty) {
      context.read<RouteService>().selectRoute(routes.first);
    }
  }

  void _selectIndex(List<RevvRoute> routes, int nextIndex) {
    if (routes.isEmpty) return;
    final clamped = nextIndex.clamp(0, routes.length - 1);
    setState(() => _selectedIndex = clamped);
    context.read<RouteService>().selectRoute(routes[clamped]);
  }

  void _setLens(_RouteLens lens) {
    final visibleRoutes = _filterRoutes(
      context.read<RouteService>().routes,
      lens,
    );
    setState(() {
      _lens = lens;
      _selectedIndex = 0;
    });
    if (visibleRoutes.isNotEmpty) {
      context.read<RouteService>().selectRoute(visibleRoutes.first);
    }
  }

  Future<void> _startDrive(RevvRoute route) async {
    final shouldStart = await showCopilotStartSheet(context, route: route);
    if (!mounted || shouldStart != true) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeanDriveScreen(route: route)),
    );
  }

  void _showRouteDetails(RevvRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeanRouteDetailScreen(route: route)),
    );
  }

  void _handleCameraViewportChanged(RouteMapViewport viewport) {
    final previous = _mapCenterPoint;
    final previousMode = _mapModeForZoom(_mapZoom);
    final nextMode = _mapModeForZoom(viewport.zoom);
    final shouldRefreshMarkers =
        previous == null ||
        RevvRoute.haversineKm(previous, viewport.center) >= 4.0 ||
        previousMode != nextMode;
    _mapCenterPoint = viewport.center;
    _mapZoom = viewport.zoom;
    if (shouldRefreshMarkers && mounted) {
      setState(() {});
    }
  }

  void _handleCandidateMarkerTap(String routeId) {
    final visibleRoutes = _filterRoutes(
      context.read<RouteService>().routes,
      _lens,
    );
    final index = visibleRoutes.indexWhere((route) => route.id == routeId);
    if (index < 0) return;
    _selectIndex(visibleRoutes, index);
    _showMarkerRouteSheet(visibleRoutes[index], index, visibleRoutes.length);
  }

  void _showMarkerRouteSheet(RevvRoute route, int index, int total) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MarkerRouteSheet(
        route: route,
        index: index,
        total: total,
        onDetails: () {
          Navigator.pop(sheetContext);
          _showRouteDetails(route);
        },
        onGo: () {
          Navigator.pop(sheetContext);
          unawaited(_startDrive(route));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RouteService>();
    final settings = context.watch<SettingsService>();
    final routes = service.routes;
    final visibleRoutes = _filterRoutes(routes, _lens);
    final effectiveIndex = visibleRoutes.isEmpty
        ? 0
        : _selectedIndex.clamp(0, visibleRoutes.length - 1);
    final selected = visibleRoutes.isEmpty
        ? null
        : visibleRoutes[effectiveIndex];
    final mapMode = _mapModeForZoom(_mapZoom);
    final filterEmpty = routes.isNotEmpty && visibleRoutes.isEmpty;
    final canBroadenStrength =
        service.lastCloudCandidateCount > 0 &&
        service.lastFilteredRouteCount == 0 &&
        service.filterStrength != RouteFilterStrength.broad;
    final status = service.isLoading
        ? '루트 찾는 중'
        : filterEmpty
        ? '${_lensLabel(_lens)} 후보가 없어요. 전체로 돌아가세요.'
        : _localStatusMessage ??
              service.errorMessage ??
              service.routeSuggestionMessage ??
              service.backgroundStatusMessage;
    final emptyTitle = filterEmpty
        ? '${_lensLabel(_lens)} 후보 없음'
        : _localStatusMessage ??
              service.routeDataStatusTitle ??
              '지도에서 루트를 불러오지 못했어요.';
    final emptyBody = filterEmpty
        ? '전체 ${routes.length}개 중 이 필터에 맞는 루트가 없어요. 전체 후보로 다시 비교해 보세요.'
        : _emptyRouteBody(service);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: MapWidget(
                routePolyline: selected?.nodes,
                candidatePolylines: _candidatePolylines(
                  visibleRoutes,
                  selected,
                  mapMode,
                ),
                curveHeatmapPolylines: _curveHeatmapPolylines(
                  visibleRoutes,
                  mapMode,
                ),
                candidateMarkers: _candidateMarkers(
                  visibleRoutes,
                  selected,
                  _mapCenterPoint,
                  _markerLimitForMapMode(mapMode),
                ),
                routeFocusMode: false,
                recenterSignal: _recenterSignal,
                onCameraViewportChanged: _handleCameraViewportChanged,
                onCandidateMarkerTap: _handleCandidateMarkerTap,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LeanRouteTopBar(
                      count: visibleRoutes.length,
                      busy: service.isLoading,
                      radiusKm: settings.searchRadiusKm,
                      visibleLimit: service.visibleRouteLimit,
                      filterStrength: service.filterStrength,
                      onBack: () => Navigator.pop(context),
                      onSearch: _searchHere,
                      onRadius: _selectRadius,
                      onLimit: _selectVisibleLimit,
                      onStrength: _selectFilterStrength,
                      onRecenter: () => setState(() => _recenterSignal++),
                    ),
                    const SizedBox(height: 8),
                    _RouteLensStrip(
                      lens: _lens,
                      routes: routes,
                      onChanged: _setLens,
                    ),
                    const SizedBox(height: 8),
                    const _CurveHeatLegend(),
                  ],
                ),
              ),
            ),
            if (status != null && status.isNotEmpty)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 124,
                left: 24,
                right: 24,
                child: _LeanToast(message: status, busy: service.isLoading),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: MediaQuery.paddingOf(context).bottom + 14,
              child: selected == null
                  ? _LeanEmptyTicket(
                      title: emptyTitle,
                      body: emptyBody,
                      actionLabel: filterEmpty
                          ? '전체로 보기'
                          : canBroadenStrength
                          ? '넓게 보기'
                          : '다시 찾기',
                      onAction: filterEmpty
                          ? () => _setLens(_RouteLens.all)
                          : canBroadenStrength
                          ? () =>
                                _applyFilterStrength(RouteFilterStrength.broad)
                          : _searchHere,
                    )
                  : _LeanRouteTicket(
                      route: selected,
                      index: effectiveIndex,
                      total: visibleRoutes.length,
                      onPrev: effectiveIndex > 0
                          ? () =>
                                _selectIndex(visibleRoutes, effectiveIndex - 1)
                          : null,
                      onNext: effectiveIndex < visibleRoutes.length - 1
                          ? () =>
                                _selectIndex(visibleRoutes, effectiveIndex + 1)
                          : null,
                      onGo: () => unawaited(_startDrive(selected)),
                      onDetails: () => _showRouteDetails(selected),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeanRouteTopBar extends StatelessWidget {
  final int count;
  final bool busy;
  final int radiusKm;
  final int visibleLimit;
  final RouteFilterStrength filterStrength;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onRadius;
  final VoidCallback onLimit;
  final VoidCallback onStrength;
  final VoidCallback onRecenter;

  const _LeanRouteTopBar({
    required this.count,
    required this.busy,
    required this.radiusKm,
    required this.visibleLimit,
    required this.filterStrength,
    required this.onBack,
    required this.onSearch,
    required this.onRadius,
    required this.onLimit,
    required this.onStrength,
    required this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    return _LeanGlass(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _LeanCircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy ? '루트 탐색 중' : '루트 $count',
              style: AppText.body(
                size: 16,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _LeanMiniButton(
            label: '${radiusKm}km',
            icon: Icons.radar_rounded,
            onTap: busy ? null : onRadius,
          ),
          const SizedBox(width: 6),
          _LeanMiniButton(
            label: routeFilterStrengthLabel(filterStrength),
            icon: Icons.tune_rounded,
            onTap: busy ? null : onStrength,
          ),
          const SizedBox(width: 6),
          _LeanMiniButton(
            label: '$visibleLimit',
            icon: Icons.view_week_rounded,
            onTap: busy ? null : onLimit,
          ),
          const SizedBox(width: 6),
          _LeanMiniButton(
            label: '이 지역',
            icon: Icons.travel_explore_rounded,
            onTap: busy ? null : onSearch,
          ),
          const SizedBox(width: 6),
          _LeanCircleButton(icon: Icons.gps_fixed_rounded, onTap: onRecenter),
        ],
      ),
    );
  }
}

class _RouteOption {
  final int value;
  final String title;
  final String subtitle;

  const _RouteOption(this.value, this.title, this.subtitle);
}

class _RouteOptionSheet extends StatelessWidget {
  final String title;
  final int selectedValue;
  final List<_RouteOption> options;

  const _RouteOptionSheet({
    required this.title,
    required this.selectedValue,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: _LeanGlass(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.body(
                  size: 18,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in options)
                _RouteOptionTile(
                  option: option,
                  selected: option.value == selectedValue,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteOptionTile extends StatelessWidget {
  final _RouteOption option;
  final bool selected;

  const _RouteOptionTile({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, option.value),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryContainer.withValues(alpha: 0.16)
              : AppColors.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer.withValues(alpha: 0.62)
                : AppColors.outlineVariant.withValues(alpha: 0.26),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? AppColors.primaryContainer
                  : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: AppText.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStrengthSheet extends StatelessWidget {
  final RouteFilterStrength selectedValue;

  const _RouteStrengthSheet({required this.selectedValue});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: _LeanGlass(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '필터 강도',
                style: AppText.body(
                  size: 18,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '후보가 너무 적으면 넓게, 너무 잡다하면 정밀로 조절하세요.',
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              for (final strength in RouteFilterStrength.values)
                _RouteStrengthTile(
                  strength: strength,
                  selected: strength == selectedValue,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteStrengthTile extends StatelessWidget {
  final RouteFilterStrength strength;
  final bool selected;

  const _RouteStrengthTile({required this.strength, required this.selected});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, strength),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryContainer.withValues(alpha: 0.16)
              : AppColors.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer.withValues(alpha: 0.62)
                : AppColors.outlineVariant.withValues(alpha: 0.26),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? AppColors.primaryContainer
                  : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routeFilterStrengthLabel(strength),
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    routeFilterStrengthDescription(strength),
                    style: AppText.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeanRouteTicket extends StatelessWidget {
  final RevvRoute route;
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onGo;
  final VoidCallback onDetails;

  const _LeanRouteTicket({
    required this.route,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onGo,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final profile = RouteQualityProfile.fromRoute(route);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
    );
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final dx = details.primaryVelocity ?? 0;
        if (dx < -160) {
          onNext?.call();
        } else if (dx > 160) {
          onPrev?.call();
        }
      },
      child: _LeanGlass(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _LeanCircleButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: onPrev,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '후보 ${index + 1} / $total · ${profile.typeLabel} · ${route.distanceFromUserDisplay}',
                        style: AppText.technicalLabel(
                          size: 10,
                          color: AppColors.primaryContainer,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        route.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 18,
                          weight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        briefing.primaryAdvice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 11,
                          weight: FontWeight.w800,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _LeanCircleButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: onNext,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        for (final metric in profile.quickMetrics.take(4)) ...[
                          _Metric(label: metric.label, value: metric.value),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                _LeanCircleButton(
                  icon: Icons.info_outline_rounded,
                  onTap: onDetails,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: onGo,
                    child: Text(
                      '주행 시작',
                      style: AppText.body(
                        size: 14,
                        weight: FontWeight.w900,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerRouteSheet extends StatelessWidget {
  final RevvRoute route;
  final int index;
  final int total;
  final VoidCallback onDetails;
  final VoidCallback onGo;

  const _MarkerRouteSheet({
    required this.route,
    required this.index,
    required this.total,
    required this.onDetails,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final profile = RouteQualityProfile.fromRoute(route);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: _LeanGlass(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primaryContainer.withValues(
                          alpha: 0.42,
                        ),
                      ),
                    ),
                    child: Text(
                      '후보 ${index + 1} / $total · ${profile.typeLabel}',
                      style: AppText.technicalLabel(
                        size: 10,
                        color: AppColors.primaryContainer,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                route.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 22,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                briefing.primaryAdvice,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final metric in profile.quickMetrics.take(5))
                    _Metric(label: metric.label, value: metric.value),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDetails,
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('자세히 보기'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryContainer,
                        side: BorderSide(
                          color: AppColors.primaryContainer.withValues(
                            alpha: 0.44,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: AppText.body(
                          size: 13,
                          weight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onGo,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('주행 시작'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: AppText.body(
                          size: 13,
                          weight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeanEmptyTicket extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _LeanEmptyTicket({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _LeanGlass(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(
            Icons.route_outlined,
            color: AppColors.primaryContainer,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 14,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LeanTextButton(
            label: actionLabel,
            icon: actionLabel == '전체로 보기'
                ? Icons.layers_rounded
                : actionLabel == '넓게 보기'
                ? Icons.tune_rounded
                : Icons.refresh_rounded,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

class _LeanToast extends StatelessWidget {
  final String message;
  final bool busy;

  const _LeanToast({required this.message, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _LeanGlass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.primaryContainer,
                ),
              )
            else
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.primaryContainer,
                size: 16,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteLensStrip extends StatelessWidget {
  final _RouteLens lens;
  final List<RevvRoute> routes;
  final ValueChanged<_RouteLens> onChanged;

  const _RouteLensStrip({
    required this.lens,
    required this.routes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = _RouteLens.values;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final count = _filterRoutes(routes, item).length;
          return _LensChip(
            label: _lensLabel(item),
            count: count,
            selected: lens == item,
            onTap: count == 0 ? null : () => onChanged(item),
          );
        },
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  const _LensChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final background = selected
        ? AppColors.primaryContainer
        : const Color(0xDD101316);
    final foreground = disabled
        ? AppColors.textHint.withValues(alpha: 0.55)
        : selected
        ? AppColors.onPrimary
        : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: disabled ? background.withValues(alpha: 0.58) : background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer
                : AppColors.outlineVariant.withValues(alpha: 0.36),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primaryContainer.withValues(alpha: 0.28),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Text(
          '$label $count',
          style: AppText.body(
            size: 12,
            weight: FontWeight.w900,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _CurveHeatLegend extends StatelessWidget {
  const _CurveHeatLegend();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bg.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _HeatDot(color: Color(0xFFFFB020)),
            const SizedBox(width: 5),
            Text(
              '중간 커브',
              style: AppText.body(
                size: 10,
                weight: FontWeight.w900,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            const _HeatDot(color: Color(0xFFFF3B30)),
            const SizedBox(width: 5),
            Text(
              '급커브 밀집',
              style: AppText.body(
                size: 10,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatDot extends StatelessWidget {
  final Color color;

  const _HeatDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.65), blurRadius: 8),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: AppText.body(
          size: 11,
          weight: FontWeight.w900,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _LeanCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _LeanCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: onTap == null ? AppColors.textHint : AppColors.textPrimary,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _LeanTextButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _LeanTextButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryContainer,
        textStyle: AppText.body(size: 12, weight: FontWeight.w900),
      ),
    );
  }
}

class _LeanMiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _LeanMiniButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled ? AppColors.primaryContainer : AppColors.textHint,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppText.body(
                size: 11,
                weight: FontWeight.w900,
                color: enabled
                    ? AppColors.primaryContainer
                    : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeanGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _LeanGlass({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

String _lensLabel(_RouteLens lens) {
  return switch (lens) {
    _RouteLens.all => '전체',
    _RouteLens.nearby => '근처',
    _RouteLens.sweeper => '스위퍼',
    _RouteLens.tight => '타이트',
    _RouteLens.flow => '흐름',
    _RouteLens.loop => '루프',
  };
}

List<RevvRoute> _filterRoutes(List<RevvRoute> routes, _RouteLens lens) {
  bool hasTag(RevvRoute route, RouteQualityTag tag) =>
      RouteQualityProfile.fromRoute(route).hasTag(tag);

  return switch (lens) {
    _RouteLens.all => routes,
    _RouteLens.nearby =>
      routes.where((route) => hasTag(route, RouteQualityTag.nearby)).toList(),
    _RouteLens.sweeper =>
      routes.where((route) => hasTag(route, RouteQualityTag.sweeper)).toList(),
    _RouteLens.tight =>
      routes.where((route) => hasTag(route, RouteQualityTag.tight)).toList(),
    _RouteLens.flow =>
      routes.where((route) => hasTag(route, RouteQualityTag.flow)).toList(),
    _RouteLens.loop =>
      routes.where((route) => hasTag(route, RouteQualityTag.loop)).toList(),
  };
}

List<List<LatLng>> _candidatePolylines(
  List<RevvRoute> routes,
  RevvRoute? selected,
  _RouteMapMode mode,
) {
  final selectedId = selected?.id;
  final limit = switch (mode) {
    _RouteMapMode.wide => 2,
    _RouteMapMode.balanced => 5,
    _RouteMapMode.close => 5,
  };
  return routes
      .where((route) => route.id != selectedId && route.nodes.length > 1)
      .take(limit)
      .map((route) => route.nodes)
      .toList(growable: false);
}

List<List<LatLng>> _curveHeatmapPolylines(
  List<RevvRoute> routes,
  _RouteMapMode mode,
) {
  final limit = switch (mode) {
    _RouteMapMode.wide => 32,
    _RouteMapMode.balanced => 24,
    _RouteMapMode.close => 12,
  };
  return routes
      .where((route) => route.nodes.length > 2)
      .take(limit)
      .map((route) => route.nodes)
      .toList(growable: false);
}

List<RouteCandidateMarker> _candidateMarkers(
  List<RevvRoute> routes,
  RevvRoute? selected,
  LatLng? mapCenter,
  int maxMarkers,
) {
  final selectedId = selected?.id;
  final markers = <RouteCandidateMarker>[];
  for (var i = 0; i < routes.length && markers.length < maxMarkers; i++) {
    final route = routes[i];
    if (route.id == selectedId) continue;
    markers.add(
      RouteCandidateMarker(
        routeId: route.id,
        index: i,
        point: _markerPointForRoute(route, mapCenter, markers.length),
      ),
    );
  }
  return markers;
}

LatLng _markerPointForRoute(RevvRoute route, LatLng? focus, int ordinal) {
  final nodes = route.nodes;
  if (nodes.isEmpty) return route.centerPoint;
  if (nodes.length == 1) return nodes.first;

  if (focus == null) {
    final fraction = 0.28 + (ordinal % 6) * 0.10;
    final index = (fraction * (nodes.length - 1)).round();
    return nodes[index.clamp(0, nodes.length - 1).toInt()];
  }

  final stride = math.max(1, nodes.length ~/ 90);
  var bestIndex = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < nodes.length; i += stride) {
    final distance = RevvRoute.haversineKm(focus, nodes[i]);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
    }
  }

  // 같은 시야 중심에 여러 후보가 몰릴 때 숫자 마커가 겹치지 않도록
  // 루트 위에서 살짝 다른 지점으로 분산한다.
  final offsetStep = math.max(1, nodes.length ~/ 54);
  final offset = ((ordinal % 7) - 3) * offsetStep;
  final distributedIndex = (bestIndex + offset)
      .clamp(0, nodes.length - 1)
      .toInt();
  return nodes[distributedIndex];
}

_RouteMapMode _mapModeForZoom(double zoom) {
  if (zoom < 10.5) return _RouteMapMode.wide;
  if (zoom < 13.5) return _RouteMapMode.balanced;
  return _RouteMapMode.close;
}

int _markerLimitForMapMode(_RouteMapMode mode) {
  return switch (mode) {
    _RouteMapMode.wide => 16,
    _RouteMapMode.balanced => 12,
    _RouteMapMode.close => 8,
  };
}

String _emptyRouteBody(RouteService service) {
  final base =
      service.routeDataStatusBody ?? '현재 위치와 클라우드 연결 상태를 확인한 뒤 다시 시도해 주세요.';
  if (service.lastCloudCandidateCount == 0 &&
      service.lastFilteredRouteCount == 0) {
    return base;
  }
  return '$base · 원본 ${service.lastCloudCandidateCount}개 / 필터 ${service.lastFilteredRouteCount}개 / 표시 ${service.lastUsableCloudRouteCount}개';
}
