import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_loading_policy.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_difficulty_profile.dart';
import '../ui/route_map_display_policy.dart';
import '../ui/route_quality_profile.dart';
import '../ui/winding_experience.dart';
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
  String? _localStatusMessage;
  double _mapZoom = 11.0;
  bool _curveRoadView = false;
  bool _hasUserSelectedRoute = false;
  RevvRoute? _selectedRouteOverride;

  @override
  void initState() {
    super.initState();
    unawaited(_searchCurrentLocation());
  }

  Future<void> _searchHere() async {
    final point = _mapCenterPoint ?? await _resolveSearchPoint();
    if (!mounted || point == null) return;
    await _fetchAtPoint(point, forceRefresh: true);
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
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _localStatusMessage = point == null
          ? AppCopy.t(
              language,
              ko: '현재 위치를 확인하지 못했어요.',
              en: 'Could not read current location.',
              fr: 'Impossible de lire la position actuelle.',
            )
          : null;
    });
    return point;
  }

  Future<void> _fetchAtPoint(LatLng point, {bool forceRefresh = false}) async {
    final settings = context.read<SettingsService>();
    final routes = context.read<RouteService>();
    routes.filterStrength = settings.routeFilterStrength;
    if (routes.visibleRouteLimit < 32) {
      routes.visibleRouteLimit = 32;
    }
    await routes.prefetchRouteField(
      point.lat,
      point.lng,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _lens = _RouteLens.all;
      _selectedIndex = 0;
      _hasUserSelectedRoute = false;
      _selectedRouteOverride = null;
      _localStatusMessage = null;
    });
  }

  Future<void> _selectVisibleLimit() async {
    final service = context.read<RouteService>();
    final language = context.read<SettingsService>().appLanguage;
    final current = service.visibleRouteLimit;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteOptionSheet(
        title: AppCopy.t(
          language,
          ko: '표시 개수',
          en: 'Visible picks',
          fr: 'Options visibles',
        ),
        selectedValue: current,
        options: [
          _RouteOption(
            8,
            AppCopy.t(language, ko: '8개', en: '8', fr: '8'),
            AppCopy.t(
              language,
              ko: '지도와 티켓을 가장 깔끔하게 유지합니다.',
              en: 'Keeps map and ticket clean.',
              fr: 'Garde la carte et le ticket lisibles.',
            ),
          ),
          _RouteOption(
            16,
            AppCopy.t(language, ko: '16개', en: '16', fr: '16'),
            AppCopy.t(
              language,
              ko: '기본 탐색 개수입니다.',
              en: 'Default exploration count.',
              fr: 'Nombre par défaut.',
            ),
          ),
          _RouteOption(
            24,
            AppCopy.t(language, ko: '24개', en: '24', fr: '24'),
            AppCopy.t(
              language,
              ko: '더 많은 후보를 비교합니다.',
              en: 'Compare more candidates.',
              fr: 'Comparer plus d’options.',
            ),
          ),
          _RouteOption(
            32,
            AppCopy.t(language, ko: '32개', en: '32', fr: '32'),
            AppCopy.t(
              language,
              ko: '최대한 넓게 훑어봅니다.',
              en: 'Scan as broadly as possible.',
              fr: 'Balayer le plus largement possible.',
            ),
          ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == current) return;

    await service.changeVisibleRouteLimit(selected, 0, 0);
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
    final service = context.read<RouteService>();
    await settings.setRouteFilterStrength(strength);
    await service.changeFilterStrength(strength, 0, 0);
    if (!mounted) return;
    _resetVisibleSelection(service.routes);
  }

  void _resetVisibleSelection(List<RevvRoute> routes) {
    setState(() {
      _lens = _RouteLens.all;
      _selectedIndex = 0;
      _hasUserSelectedRoute = false;
      _selectedRouteOverride = null;
    });
  }

  void _selectIndex(List<RevvRoute> routes, int nextIndex) {
    if (routes.isEmpty) return;
    final clamped = nextIndex.clamp(0, routes.length - 1);
    setState(() {
      _selectedIndex = clamped;
      _hasUserSelectedRoute = true;
      _selectedRouteOverride = null;
    });
    context.read<RouteService>().selectRoute(routes[clamped]);
  }

  void _setLens(_RouteLens lens) {
    setState(() {
      _lens = lens;
      _selectedIndex = 0;
      _hasUserSelectedRoute = false;
      _selectedRouteOverride = null;
    });
  }

  Future<void> _startDrive(RevvRoute route) async {
    final startChoice = await showCopilotStartSheet(context, route: route);
    if (!mounted || startChoice == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(
          route: route,
          simulated: startChoice == CopilotStartChoice.simulate,
        ),
      ),
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

  void _handleRouteLineTap(String routeId) {
    _selectRouteFromMap(routeId);
  }

  void _selectRouteFromMap(String routeId) {
    final service = context.read<RouteService>();
    final visibleRoutes = _rankRoutes(_filterRoutes(service.routes, _lens));
    final index = visibleRoutes.indexWhere((route) => route.id == routeId);
    if (index >= 0) {
      _selectIndex(visibleRoutes, index);
      return;
    }

    final visualIndex = service.mapVisualRoutes.indexWhere(
      (route) => route.id == routeId,
    );
    if (visualIndex < 0) return;
    final route = service.mapVisualRoutes[visualIndex];
    setState(() {
      _hasUserSelectedRoute = true;
      _selectedRouteOverride = route;
      _selectedIndex = 0;
    });
    service.selectRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RouteService>();
    final routes = service.routes;
    final visibleRoutes = _rankRoutes(_filterRoutes(routes, _lens));
    final mapDisplayRoutes = _routesForViewport(
      routeFinderMapDisplayRoutes(
        mapVisualRoutes: service.mapVisualRoutes,
        visibleRoutes: visibleRoutes,
      ),
      _mapCenterPoint,
      _mapZoom,
    );
    final effectiveIndex = visibleRoutes.isEmpty
        ? 0
        : _selectedIndex.clamp(0, visibleRoutes.length - 1);
    final selected = !_hasUserSelectedRoute
        ? null
        : _selectedRouteOverride ??
              (visibleRoutes.isEmpty ? null : visibleRoutes[effectiveIndex]);
    final filterEmpty = routes.isNotEmpty && visibleRoutes.isEmpty;
    final canBroadenStrength =
        service.lastCloudCandidateCount > 0 &&
        service.lastFilteredRouteCount == 0 &&
        service.filterStrength != RouteFilterStrength.broad;
    final language = context.watch<SettingsService>().appLanguage;
    final localStatus = _localizedInlineStatus(_localStatusMessage, language);
    final serviceStatus = _localizedInlineStatus(
      service.errorMessage ??
          service.routeSuggestionMessage ??
          service.backgroundStatusMessage,
      language,
    );
    final status = service.isLoading
        ? AppCopy.t(
            language,
            ko: '루트 찾는 중',
            en: 'Finding routes',
            fr: 'Recherche de routes',
          )
        : filterEmpty
        ? AppCopy.t(
            language,
            ko: '${_lensLabel(_lens, language)} 후보가 없어요. 전체로 돌아가세요.',
            en: 'No ${_lensLabel(_lens, language)} picks. Go back to All.',
            fr: 'Aucune option ${_lensLabel(_lens, language)}. Revenez à Tout.',
          )
        : localStatus ?? serviceStatus;
    final emptyTitle = filterEmpty
        ? AppCopy.t(
            language,
            ko: '${_lensLabel(_lens, language)} 후보 없음',
            en: 'No ${_lensLabel(_lens, language)} picks',
            fr: 'Aucune option ${_lensLabel(_lens, language)}',
          )
        : localStatus ??
              _localizedRouteStatusTitle(service, language) ??
              AppCopy.t(
                language,
                ko: '지도에서 루트를 불러오지 못했어요.',
                en: 'Could not load routes on the map.',
                fr: 'Impossible de charger les routes sur la carte.',
              );
    final emptyBody = filterEmpty
        ? AppCopy.t(
            language,
            ko: '전체 ${routes.length}개 중 이 필터에 맞는 루트가 없어요. 전체 후보로 다시 비교해 보세요.',
            en: 'No routes match this filter out of ${routes.length}. Compare all picks again.',
            fr: 'Aucune route sur ${routes.length} ne correspond. Comparez toutes les options.',
          )
        : _emptyRouteBody(service, language);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: MapWidget(
                routePolyline: selected?.nodes,
                candidatePolylines: const [],
                curveHeatmapPolylines: const [],
                difficultyLines: _difficultyLines(mapDisplayRoutes, selected),
                strongCurveFieldHeatmap: _curveRoadView,
                routeFocusMode: false,
                recenterSignal: _recenterSignal,
                onCameraViewportChanged: _handleCameraViewportChanged,
                onRouteLineTap: _handleRouteLineTap,
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
                      visibleLimit: service.visibleRouteLimit,
                      filterStrength: service.filterStrength,
                      onBack: () => Navigator.pop(context),
                      onSearch: _searchHere,
                      onLimit: _selectVisibleLimit,
                      onStrength: _selectFilterStrength,
                      curveRoadView: _curveRoadView,
                      onCurveRoadView: () =>
                          setState(() => _curveRoadView = !_curveRoadView),
                      onRecenter: () => setState(() => _recenterSignal++),
                    ),
                    const SizedBox(height: 8),
                    _RouteLensStrip(
                      lens: _lens,
                      routes: routes,
                      onChanged: _setLens,
                    ),
                    const SizedBox(height: 8),
                    if (_curveRoadView) const _CurveHeatLegend(),
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
                      title: visibleRoutes.isNotEmpty
                          ? AppCopy.t(
                              language,
                              ko: '지도에서 커브길을 눌러 선택',
                              en: 'Tap a curvy road on the map',
                              fr: 'Touchez une route sinueuse',
                            )
                          : emptyTitle,
                      body: visibleRoutes.isNotEmpty
                          ? AppCopy.t(
                              language,
                              ko: '노랑은 완만, 주황은 와인딩, 빨강은 타이트 구간이에요. 원하는 길을 탭하면 상세 카드가 열립니다.',
                              en: 'Yellow is gentle, orange is winding, red is tight. Tap a road to open its card.',
                              fr: 'Jaune doux, orange sinueux, rouge serré. Touchez une route pour ouvrir sa carte.',
                            )
                          : emptyBody,
                      actionIcon: visibleRoutes.isNotEmpty
                          ? Icons.route_rounded
                          : filterEmpty
                          ? Icons.layers_rounded
                          : canBroadenStrength
                          ? Icons.tune_rounded
                          : Icons.refresh_rounded,
                      actionLabel: visibleRoutes.isNotEmpty
                          ? AppCopy.t(
                              language,
                              ko: '추천 보기',
                              en: 'Show picks',
                              fr: 'Voir options',
                            )
                          : filterEmpty
                          ? AppCopy.t(
                              language,
                              ko: '전체로 보기',
                              en: 'Show all',
                              fr: 'Tout voir',
                            )
                          : canBroadenStrength
                          ? AppCopy.t(
                              language,
                              ko: '넓게 보기',
                              en: 'Broaden',
                              fr: 'Élargir',
                            )
                          : AppCopy.t(
                              language,
                              ko: '다시 찾기',
                              en: 'Retry',
                              fr: 'Réessayer',
                            ),
                      onAction: visibleRoutes.isNotEmpty
                          ? () => _selectIndex(visibleRoutes, 0)
                          : filterEmpty
                          ? () => _setLens(_RouteLens.all)
                          : canBroadenStrength
                          ? () =>
                                _applyFilterStrength(RouteFilterStrength.broad)
                          : _searchHere,
                    )
                  : _LeanRouteTicket(
                      route: selected,
                      index: effectiveIndex,
                      total: _selectedRouteOverride == null
                          ? visibleRoutes.length
                          : service.mapVisualRoutes.length,
                      onPrev:
                          _selectedRouteOverride == null && effectiveIndex > 0
                          ? () =>
                                _selectIndex(visibleRoutes, effectiveIndex - 1)
                          : null,
                      onNext:
                          _selectedRouteOverride == null &&
                              effectiveIndex < visibleRoutes.length - 1
                          ? () =>
                                _selectIndex(visibleRoutes, effectiveIndex + 1)
                          : null,
                      onGo: () => unawaited(_startDrive(selected)),
                      onDetails: () => _showRouteDetails(selected),
                      mapSelected: _selectedRouteOverride != null,
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
  final int visibleLimit;
  final RouteFilterStrength filterStrength;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onLimit;
  final VoidCallback onStrength;
  final bool curveRoadView;
  final VoidCallback onCurveRoadView;
  final VoidCallback onRecenter;

  const _LeanRouteTopBar({
    required this.count,
    required this.busy,
    required this.visibleLimit,
    required this.filterStrength,
    required this.onBack,
    required this.onSearch,
    required this.onLimit,
    required this.onStrength,
    required this.curveRoadView,
    required this.onCurveRoadView,
    required this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return _LeanGlass(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: Row(
        children: [
          _LeanCircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  if (busy) ...[
                    _LeanInfoPill(
                      label: AppCopy.t(
                        language,
                        ko: '탐색 중',
                        en: 'Searching',
                        fr: 'Recherche',
                      ),
                      icon: Icons.sync_rounded,
                      busy: true,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _LeanMiniButton(
                    label: _strengthLabel(filterStrength, language),
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
                    label: AppCopy.t(
                      language,
                      ko: '이 지역',
                      en: 'This area',
                      fr: 'Cette zone',
                    ),
                    icon: Icons.travel_explore_rounded,
                    onTap: busy ? null : onSearch,
                  ),
                  const SizedBox(width: 6),
                  _LeanMiniButton(
                    label: curveRoadView
                        ? AppCopy.t(
                            language,
                            ko: '커브 ON',
                            en: 'Curves ON',
                            fr: 'Virages ON',
                          )
                        : AppCopy.t(
                            language,
                            ko: '커브길',
                            en: 'Curves',
                            fr: 'Virages',
                          ),
                    icon: Icons.timeline_rounded,
                    onTap: onCurveRoadView,
                    selected: curveRoadView,
                  ),
                ],
              ),
            ),
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
    final language = context.watch<SettingsService>().appLanguage;
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
                AppCopy.t(
                  language,
                  ko: '필터 강도',
                  en: 'Filter strength',
                  fr: 'Force du filtre',
                ),
                style: AppText.body(
                  size: 18,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppCopy.t(
                  language,
                  ko: '후보가 너무 적으면 넓게, 너무 잡다하면 정밀로 조절하세요.',
                  en: 'Use Broad for more options, Precise for cleaner picks.',
                  fr: 'Large pour plus d’options, Précis pour filtrer.',
                ),
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
                  language: language,
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
  final AppLanguage language;

  const _RouteStrengthTile({
    required this.strength,
    required this.selected,
    required this.language,
  });

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
                    _strengthLabel(strength, language),
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _strengthDescription(strength, language),
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
  final bool mapSelected;

  const _LeanRouteTicket({
    required this.route,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onGo,
    required this.onDetails,
    this.mapSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final profile = RouteQualityProfile.fromRoute(route, language: language);
    final windingProfile = WindingExperienceProfile.fromRoute(route);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
      language: language,
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
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4EB),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkered top stripe
            SizedBox(
              height: 8,
              width: double.infinity,
              child: CustomPaint(
                painter: _CheckeredTicketPainter(
                  tileSize: 8,
                  lightColor: const Color(0xFFF8F4EB),
                  darkColor: AppColors.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RouteQualityBadge(
                        score: windingProfile.score,
                        label: windingProfile.title,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mapSelected
                                  ? AppCopy.t(
                                      language,
                                      ko: '지도에서 선택한 커브길',
                                      en: 'Map-picked curve road',
                                      fr: 'Route choisie sur carte',
                                    )
                                  : '${AppCopy.t(language, ko: '후보', en: 'Pick', fr: 'Option')} ${index + 1} / $total',
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
                              style: AppText.label(
                                size: 18,
                                weight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${windingProfile.rhythm} · ${briefing.primaryAdvice}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.mono(
                                size: 11,
                                weight: FontWeight.w700,
                                color: AppColors.stone,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LeanCircleButton(
                        icon: Icons.info_outline_rounded,
                        onTap: onDetails,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final metric in windingProfile.metrics) ...[
                        Expanded(
                          child: _Metric(label: metric.label, value: metric.value),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _Metric(
                          label: AppCopy.t(
                            language,
                            ko: '시작점',
                            en: 'Start',
                            fr: 'Départ',
                          ),
                          value: route.distanceFromUserDisplay,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _LeanCircleButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: onPrev,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryContainer,
                              foregroundColor: AppColors.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: onGo,
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: Text(
                              AppCopy.t(
                                language,
                                ko: '주행 시작',
                                en: 'Start drive',
                                fr: 'Démarrer',
                              ),
                              style: AppText.label(
                                size: 14,
                                weight: FontWeight.w800,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _LeanCircleButton(
                        icon: Icons.chevron_right_rounded,
                        onTap: onNext,
                      ),
                    ],
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

class _RouteQualityBadge extends StatelessWidget {
  final int score;
  final String label;

  const _RouteQualityBadge({required this.score, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$score',
            style: AppText.mono(
              size: 19,
              weight: FontWeight.w900,
              color: AppColors.onPrimary,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 9,
              weight: FontWeight.w900,
              color: AppColors.onPrimary.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeanEmptyTicket extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  const _LeanEmptyTicket({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionIcon,
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
            icon: actionIcon,
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
            label: _lensLabel(
              item,
              context.watch<SettingsService>().appLanguage,
            ),
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
    final language = context.watch<SettingsService>().appLanguage;
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
            const _HeatDot(color: Color(0xFF37E7FF)),
            const SizedBox(width: 5),
            Text(
              AppCopy.t(language, ko: '와인딩', en: 'Winding', fr: 'Sinueux'),
              style: AppText.body(
                size: 10,
                weight: FontWeight.w900,
                color: AppColors.primaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            const _HeatDot(color: Color(0xFFFFB020)),
            const SizedBox(width: 5),
            Text(
              AppCopy.t(
                language,
                ko: '중간 커브',
                en: 'Medium curves',
                fr: 'Virages moyens',
              ),
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
              AppCopy.t(
                language,
                ko: '급커브 밀집',
                en: 'Tight cluster',
                fr: 'Virages serrés',
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.creamMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.ink.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(
              size: 8,
              weight: FontWeight.w700,
              color: AppColors.stone,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
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

class _LeanInfoPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;

  const _LeanInfoPill({
    required this.label,
    required this.icon,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.28),
        ),
      ),
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
            Icon(icon, size: 15, color: AppColors.primaryContainer),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: AppText.body(
              size: 11,
              weight: FontWeight.w900,
              color: AppColors.primaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeanMiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;

  const _LeanMiniButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
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
          color: selected
              ? AppColors.primaryContainer
              : AppColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer.withValues(alpha: 0.82)
                : AppColors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? AppColors.onPrimary
                  : enabled
                  ? AppColors.primaryContainer
                  : AppColors.textHint,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: AppText.body(
                size: 11,
                weight: FontWeight.w900,
                color: selected
                    ? AppColors.onPrimary
                    : enabled
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

String _lensLabel(_RouteLens lens, AppLanguage language) {
  return switch (lens) {
    _RouteLens.all => AppCopy.t(language, ko: '전체', en: 'All', fr: 'Tout'),
    _RouteLens.nearby => AppCopy.t(
      language,
      ko: '근처',
      en: 'Nearby',
      fr: 'Proche',
    ),
    _RouteLens.sweeper => AppCopy.t(
      language,
      ko: '스위퍼',
      en: 'Sweepers',
      fr: 'Grandes courbes',
    ),
    _RouteLens.tight => AppCopy.t(
      language,
      ko: '타이트',
      en: 'Tight',
      fr: 'Serré',
    ),
    _RouteLens.flow => AppCopy.t(language, ko: '흐름', en: 'Flow', fr: 'Rythme'),
    _RouteLens.loop => AppCopy.t(language, ko: '루프', en: 'Loop', fr: 'Boucle'),
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

List<RevvRoute> _rankRoutes(List<RevvRoute> routes) {
  return rankWindingRoutes(
    routes,
  ).map((ranked) => ranked.route).toList(growable: false);
}

List<RevvRoute> _routesForViewport(
  List<RevvRoute> routes,
  LatLng? center,
  double zoom,
) {
  if (routes.length <= 1) return routes;
  final mode = _mapModeForZoom(zoom);
  if (center == null || mode == _RouteMapMode.wide) {
    return routes.take(650).toList(growable: false);
  }

  final radiusKm = switch (mode) {
    _RouteMapMode.wide => 180.0,
    _RouteMapMode.balanced => 95.0,
    _RouteMapMode.close => 35.0,
  };
  final limit = switch (mode) {
    _RouteMapMode.wide => 650,
    _RouteMapMode.balanced => 420,
    _RouteMapMode.close => 220,
  };

  final scored =
      routes
          .map(
            (route) => (
              route: route,
              distance: RevvRoute.haversineKm(center, route.centerPoint),
            ),
          )
          .where((item) => item.distance <= radiusKm)
          .toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));

  if (scored.length < 24) {
    scored
      ..clear()
      ..addAll(
        routes.map(
          (route) => (
            route: route,
            distance: RevvRoute.haversineKm(center, route.centerPoint),
          ),
        ),
      )
      ..sort((a, b) => a.distance.compareTo(b.distance));
  }

  return scored.take(limit).map((item) => item.route).toList(growable: false);
}

List<RouteDifficultyLine> _difficultyLines(
  List<RevvRoute> routes,
  RevvRoute? selected,
) {
  final selectedId = selected?.id;
  return routes
      .where((route) => route.id != selectedId && route.nodes.length > 1)
      .map((route) {
        final profile = RouteDifficultyProfile.fromRoute(route);
        return RouteDifficultyLine(
          routeId: route.id,
          points: route.nodes,
          colorArgb: profile.colorArgb,
          width: profile.lineWidth,
          opacity: profile.opacity,
        );
      })
      .toList(growable: false);
}

_RouteMapMode _mapModeForZoom(double zoom) {
  if (zoom < 10.5) return _RouteMapMode.wide;
  if (zoom < 13.5) return _RouteMapMode.balanced;
  return _RouteMapMode.close;
}

String _emptyRouteBody(RouteService service, AppLanguage language) {
  final base =
      _localizedRouteStatusBody(service, language) ??
      AppCopy.t(
        language,
        ko: '현재 위치와 클라우드 연결 상태를 확인한 뒤 다시 시도해 주세요.',
        en: 'Check location and cloud connection, then try again.',
        fr: 'Vérifiez la position et le cloud, puis réessayez.',
      );
  if (service.lastCloudCandidateCount == 0 &&
      service.lastFilteredRouteCount == 0) {
    return base;
  }
  return AppCopy.t(
    language,
    ko: '$base · 원본 ${service.lastCloudCandidateCount}개 / 필터 ${service.lastFilteredRouteCount}개 / 추천 ${service.lastUsableCloudRouteCount}개',
    en: '$base · raw ${service.lastCloudCandidateCount} / filtered ${service.lastFilteredRouteCount} / picks ${service.lastUsableCloudRouteCount}',
    fr: '$base · brut ${service.lastCloudCandidateCount} / filtré ${service.lastFilteredRouteCount} / choix ${service.lastUsableCloudRouteCount}',
  );
}

String? _localizedInlineStatus(String? raw, AppLanguage language) {
  if (raw == null || raw.isEmpty) return raw;
  if (language == AppLanguage.korean) return raw;
  if (raw.contains('후보가 적어요') && raw.contains('필터')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Few picks. Try the broad filter.',
      fr: 'Peu d’options. Essayez le filtre large.',
    );
  }
  if (raw.contains('후보가 적어요')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Few picks. Move the map and reload this area.',
      fr: 'Peu d’options. Déplacez la carte et rechargez la zone.',
    );
  }
  if (raw.contains('클라우드 설정')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Cloud setup needed.',
      fr: 'Configuration cloud requise.',
    );
  }
  if (raw.contains('네트워크')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Check your network connection.',
      fr: 'Vérifiez la connexion réseau.',
    );
  }
  if (raw.contains('위치')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Location permission or signal is needed.',
      fr: 'Position ou autorisation requise.',
    );
  }
  if (raw.contains('커브길') || raw.contains('루트')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Loading route field.',
      fr: 'Chargement des routes.',
    );
  }
  return raw;
}

String? _localizedRouteStatusTitle(RouteService service, AppLanguage language) {
  final raw = service.routeDataStatusTitle;
  if (raw == null || raw.isEmpty) return raw;
  if (language == AppLanguage.korean) return raw;
  return switch (raw) {
    '루트 후보 없음' => AppCopy.t(
      language,
      ko: raw,
      en: 'No route picks',
      fr: 'Aucune option',
    ),
    '추천 후보 갱신' => AppCopy.t(
      language,
      ko: raw,
      en: 'Picks refreshed',
      fr: 'Options actualisées',
    ),
    '커브길 필드 로딩 중' => AppCopy.t(
      language,
      ko: raw,
      en: 'Loading curve field',
      fr: 'Chargement des routes',
    ),
    '캐시 사용 중' => AppCopy.t(
      language,
      ko: raw,
      en: 'Using cached routes',
      fr: 'Routes en cache',
    ),
    '루트 탐색 중' => AppCopy.t(
      language,
      ko: raw,
      en: 'Finding routes',
      fr: 'Recherche de routes',
    ),
    '클라우드 설정 없음' => AppCopy.t(
      language,
      ko: raw,
      en: 'Cloud not configured',
      fr: 'Cloud non configuré',
    ),
    '루트 로드 실패' => AppCopy.t(
      language,
      ko: raw,
      en: 'Route load failed',
      fr: 'Échec du chargement',
    ),
    '루트 준비 완료' => AppCopy.t(
      language,
      ko: raw,
      en: 'Routes ready',
      fr: 'Routes prêtes',
    ),
    '커브길 없음' => AppCopy.t(
      language,
      ko: raw,
      en: 'No curve roads',
      fr: 'Aucune route sinueuse',
    ),
    '캐시 유지 중' => AppCopy.t(
      language,
      ko: raw,
      en: 'Keeping cached routes',
      fr: 'Cache conservé',
    ),
    '커브길 준비 완료' => AppCopy.t(
      language,
      ko: raw,
      en: 'Curve field ready',
      fr: 'Routes prêtes',
    ),
    _ => _localizedInlineStatus(raw, language),
  };
}

String? _localizedRouteStatusBody(RouteService service, AppLanguage language) {
  final raw = service.routeDataStatusBody;
  if (raw == null || raw.isEmpty) return raw;
  if (language == AppLanguage.korean) return raw;
  final rawCount = service.lastCloudCandidateCount;
  final filtered = service.lastFilteredRouteCount;
  final picks = service.lastUsableCloudRouteCount;
  final mapCount = service.mapVisualRoutes.length;
  if (raw.contains('Supabase URL') || raw.contains('클라우드')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Check Supabase URL and anon key.',
      fr: 'Vérifiez l’URL Supabase et la clé anon.',
    );
  }
  if (raw.contains('네트워크') || raw.contains('요청이 실패')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'The cloud request failed. Check connection and retry.',
      fr: 'La requête cloud a échoué. Vérifiez la connexion.',
    );
  }
  if (raw.contains('지도 영역')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Move the map and reload this area.',
      fr: 'Déplacez la carte et rechargez la zone.',
    );
  }
  if (raw.contains('캐시')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Showing cached curve roads while fresh data loads.',
      fr: 'Affichage du cache pendant le chargement.',
    );
  }
  return AppCopy.t(
    language,
    ko: raw,
    en: 'Raw $rawCount / filtered $filtered / picks $picks. Showing $mapCount curve roads on the map.',
    fr: 'Brut $rawCount / filtré $filtered / options $picks. $mapCount routes sur la carte.',
  );
}

String _strengthLabel(RouteFilterStrength strength, AppLanguage language) {
  return switch (strength) {
    RouteFilterStrength.precise => AppCopy.t(
      language,
      ko: '정밀',
      en: 'Precise',
      fr: 'Précis',
    ),
    RouteFilterStrength.balanced => AppCopy.t(
      language,
      ko: '균형',
      en: 'Balanced',
      fr: 'Équilibré',
    ),
    RouteFilterStrength.broad => AppCopy.t(
      language,
      ko: '넓게',
      en: 'Broad',
      fr: 'Large',
    ),
  };
}

String _strengthDescription(
  RouteFilterStrength strength,
  AppLanguage language,
) {
  return switch (strength) {
    RouteFilterStrength.precise => AppCopy.t(
      language,
      ko: '품질 높은 와인딩 후보만 봅니다.',
      en: 'Only show high-confidence winding picks.',
      fr: 'N’affiche que les options sinueuses fiables.',
    ),
    RouteFilterStrength.balanced => AppCopy.t(
      language,
      ko: '품질과 후보 수를 균형 있게 봅니다.',
      en: 'Balance route quality with candidate count.',
      fr: 'Équilibre qualité et nombre d’options.',
    ),
    RouteFilterStrength.broad => AppCopy.t(
      language,
      ko: '안전 최저선은 유지하고 더 다양한 후보를 봅니다.',
      en: 'Keep hard safety filters while showing more variety.',
      fr: 'Garde les filtres de sécurité et montre plus de variété.',
    ),
  };
}

class _CheckeredTicketPainter extends CustomPainter {
  final double tileSize;
  final Color lightColor;
  final Color darkColor;

  const _CheckeredTicketPainter({
    required this.tileSize,
    required this.lightColor,
    required this.darkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()..color = lightColor;
    final paintDark = Paint()..color = darkColor;
    final cols = (size.width / tileSize).ceil() + 1;
    final rows = (size.height / tileSize).ceil() + 1;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(col * tileSize, row * tileSize, tileSize, tileSize),
          isLight ? paintLight : paintDark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckeredTicketPainter old) =>
      old.tileSize != tileSize ||
      old.lightColor != lightColor ||
      old.darkColor != darkColor;
}
