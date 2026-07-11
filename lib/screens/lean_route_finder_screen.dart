import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_loading_policy.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/route_difficulty_profile.dart';
import '../ui/route_quality_profile.dart';
import '../ui/winding_experience.dart';
import '../widgets/map_widget.dart';
import 'lean_route_detail_screen.dart';

enum _RouteLens { all, nearby, sweeper, tight, flow, loop }

enum _RouteMapMode { wide, balanced, close }

const _routeFinderDefaultVisibleRoutes = 32;

enum RouteFinderStateKind {
  temporaryLocationDenied,
  permanentlyLocationDenied,
  emptyRoutes,
  loadFailed,
  cachedRoutes,
}

const _routeRegionPresets = [
  _RouteRegion(
    'montreal',
    'Montreal',
    '45.5017, -73.5673',
    LatLng(45.5017, -73.5673),
  ),
  _RouteRegion(
    'toronto',
    'Toronto',
    '43.6532, -79.3832',
    LatLng(43.6532, -79.3832),
  ),
  _RouteRegion(
    'vancouver',
    'Vancouver',
    '49.2827, -123.1207',
    LatLng(49.2827, -123.1207),
  ),
  _RouteRegion(
    'calgary',
    'Calgary',
    '51.0447, -114.0719',
    LatLng(51.0447, -114.0719),
  ),
];

class LeanRouteFinderScreen extends StatefulWidget {
  const LeanRouteFinderScreen({super.key});

  @override
  State<LeanRouteFinderScreen> createState() => _LeanRouteFinderScreenState();
}

class _LeanRouteFinderScreenState extends State<LeanRouteFinderScreen> {
  int _recenterSignal = 0;
  int _fitRoutesSignal = 0;
  bool _visibleLimitChanged = false;
  _RouteLens _lens = _RouteLens.all;
  LatLng? _mapCenterPoint;
  String? _localStatusMessage;
  double _mapZoom = 11.0;
  bool _curveRoadView = false;
  bool _coverageRequestInProgress = false;
  DriveBudget _driveBudget = DriveBudget.any;
  String? _selectedRegionKey;
  LatLng? _coverageRequestPoint;

  @override
  void initState() {
    super.initState();
    unawaited(_searchCurrentLocation());
  }

  Future<void> _searchHere() async {
    final point = _mapCenterPoint ?? await _resolveSearchPoint();
    if (!mounted || point == null) return;
    await _fetchAtPoint(point, forceRefresh: true, regionKey: null);
  }

  Future<void> _searchCurrentLocation() async {
    final point = await _resolveSearchPoint();
    if (!mounted || point == null) return;
    await _fetchAtPoint(point, regionKey: null);
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

  Future<void> _fetchAtPoint(
    LatLng point, {
    bool forceRefresh = false,
    String? regionKey,
  }) async {
    final settings = context.read<SettingsService>();
    final routes = context.read<RouteService>();
    routes.filterStrength = settings.routeFilterStrength;
    if (routes.visibleRouteLimit < _routeFinderDefaultVisibleRoutes) {
      routes.visibleRouteLimit = _routeFinderDefaultVisibleRoutes;
    }
    if (!isPointInsideRouteCoverage(point)) {
      setState(() {
        _lens = _RouteLens.all;
        _localStatusMessage = null;
        _selectedRegionKey = regionKey;
        _mapCenterPoint = point;
        _mapZoom = 11.0;
        _coverageRequestPoint = point;
      });
      return;
    }
    await routes.prefetchRouteField(
      point.lat,
      point.lng,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _lens = _RouteLens.all;
      _fitRoutesSignal++;
      _localStatusMessage = null;
      _selectedRegionKey = regionKey;
      _coverageRequestPoint = null;
      if (regionKey != null) {
        _mapCenterPoint = point;
        _mapZoom = 11.0;
      }
    });
  }

  Future<void> _requestCoverageNotification(RegionRequestGrid grid) async {
    if (_coverageRequestInProgress) return;
    final settings = context.read<SettingsService>();
    if (settings.hasRequestedRegion(grid.gridKey)) return;
    setState(() => _coverageRequestInProgress = true);
    try {
      final recorded = await context
          .read<SupabaseService>()
          .recordRegionRequest(
            grid,
            locale: appLanguageStorageValue(settings.appLanguage),
          );
      if (!recorded) {
        throw StateError('region request was not recorded');
      }
      await settings.markRegionRequested(grid.gridKey);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppCopy.t(
              settings.appLanguage,
              ko: '알림 신청을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.',
              en: 'Could not save the notification request. Try again shortly.',
              fr: 'Impossible d’enregistrer la demande d’alerte. Réessayez bientôt.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _coverageRequestInProgress = false);
      }
    }
  }

  Future<void> _selectRegionPreset() async {
    final language = context.read<SettingsService>().appLanguage;
    final current = _routeRegionPresets.indexWhere(
      (region) => region.key == _selectedRegionKey,
    );
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteOptionSheet(
        title: AppCopy.t(
          language,
          ko: '지역 프리셋',
          en: 'Region presets',
          fr: 'Régions',
        ),
        selectedValue: current,
        options: [
          for (var i = 0; i < _routeRegionPresets.length; i++)
            _RouteOption(
              i,
              _routeRegionPresets[i].title,
              _routeRegionPresets[i].subtitle,
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    await _selectRegionPresetValue(selected);
  }

  Future<void> _selectRegionPresetValue(int selected) async {
    final region = _routeRegionPresets[selected];
    await _fetchAtPoint(
      region.point,
      forceRefresh: true,
      regionKey: region.key,
    );
  }

  Future<void> _applyVisibleLimit(int selected) async {
    final service = context.read<RouteService>();
    final current = service.visibleRouteLimit;
    if (selected == current) return;

    await service.changeVisibleRouteLimit(selected, 0, 0);
    if (!mounted) return;
    setState(
      () => _visibleLimitChanged = selected != _routeFinderDefaultVisibleRoutes,
    );
    _resetVisibleSelection();
  }

  Future<void> _openRouteFilters(List<RevvRoute> routes) async {
    final service = context.read<RouteService>();
    final settings = context.read<SettingsService>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteFilterSheet(
        routes: routes,
        lens: _lens,
        filterStrength: service.filterStrength,
        visibleLimit: service.visibleRouteLimit,
        selectedRegionKey: _selectedRegionKey,
        curveRoadView: _curveRoadView,
        busy: service.isLoading,
        language: settings.appLanguage,
        onLensChanged: _setLens,
        onStrengthChanged: _applyFilterStrength,
        onVisibleLimitChanged: _applyVisibleLimit,
        onRegionChanged: _selectRegionPresetValue,
        onCurveRoadViewChanged: (value) =>
            setState(() => _curveRoadView = value),
      ),
    );
  }

  Future<void> _applyFilterStrength(RouteFilterStrength strength) async {
    final settings = context.read<SettingsService>();
    final service = context.read<RouteService>();
    await settings.setRouteFilterStrength(strength);
    await service.changeFilterStrength(strength, 0, 0);
    if (!mounted) return;
    _resetVisibleSelection();
  }

  void _resetVisibleSelection() {
    setState(() {
      _lens = _RouteLens.all;
      _fitRoutesSignal++;
    });
  }

  void _setLens(_RouteLens lens) {
    setState(() {
      _lens = lens;
      _fitRoutesSignal++;
    });
  }

  void _setDriveBudget(DriveBudget budget) {
    setState(() {
      _driveBudget = budget;
      _fitRoutesSignal++;
    });
  }

  int _fitDifficultySignal(int routeFieldGeneration) {
    return (Object.hash(_fitRoutesSignal, routeFieldGeneration) & 0x3fffffff) +
        1;
  }

  Future<void> _openRouteList(List<RevvRoute> routes) async {
    if (routes.isEmpty) return;
    final language = context.read<SettingsService>().appLanguage;
    final selectedRouteId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteListSheet(routes: routes, language: language),
    );
    if (!mounted || selectedRouteId == null) return;
    final currentRoutes = _visibleRoutesFor(
      context.read<RouteService>().routes,
    );
    final selected = currentRoutes
        .where((route) => route.id == selectedRouteId)
        .firstOrNull;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppCopy.t(
              language,
              ko: '루트 목록이 갱신됐어요. 다시 골라 주세요.',
              en: 'The route list changed. Choose a route again.',
              fr: 'La liste a changé. Choisissez à nouveau.',
            ),
          ),
        ),
      );
      return;
    }
    context.read<RouteService>().selectRoute(selected);
    _showRouteDetails(selected);
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

  Future<void> _openLocationSettings() async {
    await openAppSettings();
  }

  void _selectRouteFromMap(String routeId) {
    final service = context.read<RouteService>();
    final visibleRoutes = _visibleRoutesFor(service.routes);
    final index = visibleRoutes.indexWhere((route) => route.id == routeId);
    if (index >= 0) {
      final route = visibleRoutes[index];
      service.selectRoute(route);
      _showRouteDetails(route);
      return;
    }

    final visualIndex = service.mapVisualRoutes.indexWhere(
      (route) => route.id == routeId,
    );
    if (visualIndex < 0) return;
    final route = service.mapVisualRoutes[visualIndex];
    service.selectRoute(route);
    _showRouteDetails(route);
  }

  List<RevvRoute> _visibleRoutesFor(List<RevvRoute> routes) {
    final lensRoutes = _rankRoutes(_filterRoutes(routes, _lens));
    return routesForDriveBudget(lensRoutes, budget: _driveBudget);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RouteService>();
    final location = context.watch<LocationService>();
    final routes = service.routes;
    final lensRoutes = _rankRoutes(_filterRoutes(routes, _lens));
    final visibleRoutes = routesForDriveBudget(
      lensRoutes,
      budget: _driveBudget,
    );
    final mapSourceRoutes = visibleRoutes;
    final mapDisplayRoutes = _routesForViewport(
      mapSourceRoutes.isNotEmpty ? mapSourceRoutes : visibleRoutes,
      _mapCenterPoint,
      _mapZoom,
    );
    final filterEmpty =
        routes.isNotEmpty && lensRoutes.isEmpty && visibleRoutes.isEmpty;
    final budgetEmpty =
        routes.isNotEmpty &&
        lensRoutes.isNotEmpty &&
        visibleRoutes.isEmpty &&
        _driveBudget != DriveBudget.any;
    final canBroadenStrength =
        service.lastCloudCandidateCount > 0 &&
        service.lastFilteredRouteCount == 0 &&
        service.filterStrength != RouteFilterStrength.broad;
    final language = context.watch<SettingsService>().appLanguage;
    final settings = context.watch<SettingsService>();
    final coverageGrid = _coverageRequestPoint == null
        ? null
        : regionRequestGridFor(_coverageRequestPoint!);
    final coverageRequested =
        coverageGrid != null &&
        settings.hasRequestedRegion(coverageGrid.gridKey);
    final localStatus = _localizedInlineStatus(_localStatusMessage, language);
    final cacheStatus = service.routeFieldFromCache
        ? _cacheInlineStatus(visibleRoutes.length, language)
        : null;
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
        : budgetEmpty
        ? AppCopy.t(
            language,
            ko: '이 분량에 맞는 루트가 아직 없어요.',
            en: 'No routes match this duration yet.',
            fr: 'Aucune route ne correspond à cette durée.',
          )
        : filterEmpty
        ? AppCopy.t(
            language,
            ko: '${_lensLabel(_lens, language)} 후보가 없어요. 전체로 돌아가세요.',
            en: 'No ${_lensLabel(_lens, language)} picks. Go back to All.',
            fr: 'Aucune option ${_lensLabel(_lens, language)}. Revenez à Tout.',
          )
        : localStatus ?? cacheStatus ?? serviceStatus;
    final stateKind = _routeFinderStateKind(
      location: location,
      service: service,
      visibleRoutes: visibleRoutes,
      filterEmpty: filterEmpty || budgetEmpty,
    );
    final activeFilterCount = _activeFilterCount(
      lens: _lens,
      filterStrength: service.filterStrength,
      visibleLimitChanged: _visibleLimitChanged,
      selectedRegionKey: _selectedRegionKey,
      curveRoadView: _curveRoadView,
    );
    final emptyTitle = budgetEmpty
        ? AppCopy.t(
            language,
            ko: '이 분량에 맞는 루트가 아직 없어요',
            en: 'No routes for this duration yet',
            fr: 'Aucune route pour cette durée',
          )
        : filterEmpty
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
    final emptyBody = budgetEmpty
        ? AppCopy.t(
            language,
            ko: '다른 분량을 고르거나 반경/지역을 바꿔 더 많은 후보를 확인해 보세요.',
            en: 'Choose another duration or change the radius/region to compare more picks.',
            fr: 'Choisissez une autre durée ou changez le rayon/la région pour comparer plus d’options.',
          )
        : filterEmpty
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
                candidatePolylines: const [],
                curveHeatmapPolylines: const [],
                difficultyLines: _difficultyLines(mapDisplayRoutes, null),
                fitDifficultySignal: _fitDifficultySignal(
                  service.routeFieldGeneration,
                ),
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
                      busy: service.isLoading,
                      activeFilterCount: activeFilterCount,
                      onBack: () => Navigator.pop(context),
                      onSearch: _searchHere,
                      onList: visibleRoutes.isEmpty
                          ? null
                          : () => unawaited(_openRouteList(visibleRoutes)),
                      onFilters: () => _openRouteFilters(routes),
                      onRecenter: () => setState(() => _recenterSignal++),
                    ),
                    const SizedBox(height: 8),
                    DriveBudgetChoiceStrip(
                      budget: _driveBudget,
                      routes: lensRoutes,
                      onChanged: _setDriveBudget,
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
            if (coverageGrid != null || visibleRoutes.isEmpty)
              Positioned(
                left: 14,
                right: 14,
                bottom: MediaQuery.paddingOf(context).bottom + 14,
                child: coverageGrid != null
                    ? RouteCoverageBoundaryCard(
                        language: language,
                        requested: coverageRequested,
                        requesting: _coverageRequestInProgress,
                        onRequest: () =>
                            _requestCoverageNotification(coverageGrid),
                        onBrowseMontreal: _selectRegionPreset,
                      )
                    : _LeanEmptyTicket(
                        title: stateKind != null
                            ? routeFinderStateTitle(stateKind, language)
                            : emptyTitle,
                        body: stateKind != null
                            ? routeFinderStateBody(stateKind, language)
                            : emptyBody,
                        actionIcon: stateKind != null
                            ? routeFinderStateActionIcon(stateKind)
                            : budgetEmpty
                            ? Icons.schedule_rounded
                            : filterEmpty
                            ? Icons.layers_rounded
                            : canBroadenStrength
                            ? Icons.tune_rounded
                            : Icons.refresh_rounded,
                        actionLabel: stateKind != null
                            ? routeFinderStateActionLabel(stateKind, language)
                            : budgetEmpty
                            ? AppCopy.t(
                                language,
                                ko: '전체 분량',
                                en: 'Any duration',
                                fr: 'Toute durée',
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
                        onAction: stateKind != null
                            ? switch (stateKind) {
                                RouteFinderStateKind.temporaryLocationDenied =>
                                  _searchCurrentLocation,
                                RouteFinderStateKind
                                    .permanentlyLocationDenied =>
                                  _openLocationSettings,
                                RouteFinderStateKind.emptyRoutes =>
                                  _selectRegionPreset,
                                RouteFinderStateKind.loadFailed => _searchHere,
                                RouteFinderStateKind.cachedRoutes =>
                                  _searchHere,
                              }
                            : budgetEmpty
                            ? () => _setDriveBudget(DriveBudget.any)
                            : filterEmpty
                            ? () => _setLens(_RouteLens.all)
                            : canBroadenStrength
                            ? () => _applyFilterStrength(
                                RouteFilterStrength.broad,
                              )
                            : _searchHere,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class RouteFinderStateCard extends StatelessWidget {
  final RouteFinderStateKind kind;
  final AppLanguage language;
  final VoidCallback onAction;

  const RouteFinderStateCard({
    super.key,
    required this.kind,
    required this.language,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _LeanEmptyTicket(
      title: routeFinderStateTitle(kind, language),
      body: routeFinderStateBody(kind, language),
      actionLabel: routeFinderStateActionLabel(kind, language),
      actionIcon: routeFinderStateActionIcon(kind),
      onAction: onAction,
    );
  }
}

class RouteCoverageBoundaryCard extends StatelessWidget {
  final AppLanguage language;
  final bool requested;
  final bool requesting;
  final VoidCallback onRequest;
  final VoidCallback onBrowseMontreal;

  const RouteCoverageBoundaryCard({
    super.key,
    required this.language,
    required this.requested,
    required this.requesting,
    required this.onRequest,
    required this.onBrowseMontreal,
  });

  @override
  Widget build(BuildContext context) {
    final canRequest = !requested && !requesting;
    return _LeanGlass(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.public_rounded,
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
                      coverageBoundaryTitle(language),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 14,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      coverageBoundaryBody(language),
                      maxLines: 3,
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
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _LeanTextButton(
                label: requested
                    ? coverageBoundaryDoneLabel(language)
                    : requesting
                    ? coverageBoundarySavingLabel(language)
                    : coverageBoundaryRequestLabel(language),
                icon: requested
                    ? Icons.check_circle_rounded
                    : Icons.notifications_active_rounded,
                onTap: canRequest ? onRequest : null,
              ),
              _LeanTextButton(
                label: AppCopy.t(
                  language,
                  ko: '몬트리올 보기',
                  en: 'View Montreal',
                  fr: 'Voir Montréal',
                ),
                icon: Icons.route_rounded,
                onTap: onBrowseMontreal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeanRouteTopBar extends StatelessWidget {
  final bool busy;
  final int activeFilterCount;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback? onList;
  final VoidCallback onFilters;
  final VoidCallback onRecenter;

  const _LeanRouteTopBar({
    required this.busy,
    required this.activeFilterCount,
    required this.onBack,
    required this.onSearch,
    required this.onList,
    required this.onFilters,
    required this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return _LeanGlass(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: Row(
        children: [
          _LeanCircleButton(
            icon: Icons.arrow_back_rounded,
            tooltip: AppCopy.t(language, ko: '뒤로', en: 'Back', fr: 'Retour'),
            onTap: onBack,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _LeanSearchButton(
              label: AppCopy.t(
                language,
                ko: '여기 검색',
                en: 'Search here',
                fr: 'Ici',
              ),
              onTap: busy ? null : onSearch,
            ),
          ),
          const SizedBox(width: 6),
          _LeanCircleButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: AppCopy.t(
              language,
              ko: '루트 목록',
              en: 'Route list',
              fr: 'Liste des routes',
            ),
            onTap: onList,
          ),
          const SizedBox(width: 6),
          _LeanFilterButton(
            key: const Key('route-finder-filter-button'),
            activeCount: activeFilterCount,
            tooltip: AppCopy.t(
              language,
              ko: '필터',
              en: 'Filters',
              fr: 'Filtres',
            ),
            onTap: onFilters,
          ),
          const SizedBox(width: 6),
          _LeanCircleButton(
            icon: Icons.gps_fixed_rounded,
            tooltip: AppCopy.t(
              language,
              ko: '내 위치',
              en: 'My location',
              fr: 'Ma position',
            ),
            onTap: onRecenter,
          ),
        ],
      ),
    );
  }
}

class _RouteListSheet extends StatelessWidget {
  final List<RevvRoute> routes;
  final AppLanguage language;

  const _RouteListSheet({required this.routes, required this.language});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppCopy.t(
                              language,
                              ko: '루트 선택',
                              en: 'Choose a route',
                              fr: 'Choisir une route',
                            ),
                            style: AppText.body(
                              size: 22,
                              weight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            AppCopy.t(
                              language,
                              ko: '선택 가능한 루트 ${routes.length}개',
                              en: '${routes.length} routes available',
                              fr: '${routes.length} routes disponibles',
                            ),
                            style: AppText.body(
                              size: 12,
                              weight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _LeanCircleButton(
                      icon: Icons.close_rounded,
                      tooltip: AppCopy.cancel(language),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: AppColors.outlineVariant.withValues(alpha: 0.24),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 12,
                  ),
                  itemCount: routes.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 72,
                    color: AppColors.outlineVariant.withValues(alpha: 0.18),
                  ),
                  itemBuilder: (context, index) {
                    final route = routes[index];
                    final profile = RouteDifficultyProfile.fromRoute(route);
                    return InkWell(
                      onTap: () => Navigator.pop(context, route.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 13, 14, 13),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Color(profile.colorArgb),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    routeDisplayName(route, language: language),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body(
                                      size: 15,
                                      weight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _routeListMeta(route, language),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.mono(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textHint,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.outlineVariant.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _RouteFilterSheet extends StatefulWidget {
  final List<RevvRoute> routes;
  final _RouteLens lens;
  final RouteFilterStrength filterStrength;
  final int visibleLimit;
  final String? selectedRegionKey;
  final bool curveRoadView;
  final bool busy;
  final AppLanguage language;
  final ValueChanged<_RouteLens> onLensChanged;
  final Future<void> Function(RouteFilterStrength strength) onStrengthChanged;
  final Future<void> Function(int limit) onVisibleLimitChanged;
  final Future<void> Function(int index) onRegionChanged;
  final ValueChanged<bool> onCurveRoadViewChanged;

  const _RouteFilterSheet({
    required this.routes,
    required this.lens,
    required this.filterStrength,
    required this.visibleLimit,
    required this.selectedRegionKey,
    required this.curveRoadView,
    required this.busy,
    required this.language,
    required this.onLensChanged,
    required this.onStrengthChanged,
    required this.onVisibleLimitChanged,
    required this.onRegionChanged,
    required this.onCurveRoadViewChanged,
  });

  @override
  State<_RouteFilterSheet> createState() => _RouteFilterSheetState();
}

class _RouteFilterSheetState extends State<_RouteFilterSheet> {
  late _RouteLens _lens = widget.lens;
  late RouteFilterStrength _filterStrength = widget.filterStrength;
  late int _visibleLimit = widget.visibleLimit;
  late String? _selectedRegionKey = widget.selectedRegionKey;
  late bool _curveRoadView = widget.curveRoadView;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: _LeanGlass(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppCopy.t(
                            language,
                            ko: '필터',
                            en: 'Filters',
                            fr: 'Filtres',
                          ),
                          style: AppText.body(
                            size: 18,
                            weight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _LeanCircleButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FilterSectionLabel(
                    label: AppCopy.t(
                      language,
                      ko: '렌즈',
                      en: 'Lens',
                      fr: 'Lentille',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final lens in _RouteLens.values)
                        _LensChip(
                          label: _lensLabel(lens, language),
                          count: _filterRoutes(widget.routes, lens).length,
                          selected: _lens == lens,
                          onTap: _filterRoutes(widget.routes, lens).isEmpty
                              ? null
                              : () {
                                  widget.onLensChanged(lens);
                                  setState(() => _lens = lens);
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _FilterSectionLabel(
                    label: AppCopy.t(
                      language,
                      ko: '탐색 강도',
                      en: 'Filter strength',
                      fr: 'Force du filtre',
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final strength in RouteFilterStrength.values)
                    _RouteStrengthTile(
                      strength: strength,
                      selected: strength == _filterStrength,
                      language: language,
                      onTap: widget.busy
                          ? null
                          : () async {
                              await widget.onStrengthChanged(strength);
                              if (!mounted) return;
                              setState(() => _filterStrength = strength);
                            },
                    ),
                  const SizedBox(height: 10),
                  _FilterSectionLabel(
                    label: AppCopy.t(
                      language,
                      ko: '표시 개수',
                      en: 'Visible picks',
                      fr: 'Options visibles',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final limit in const [8, 16, 24, 32])
                        _FilterChoiceChip(
                          label: AppCopy.t(
                            language,
                            ko: '$limit개',
                            en: '$limit',
                            fr: '$limit',
                          ),
                          selected: _visibleLimit == limit,
                          onTap: widget.busy
                              ? null
                              : () async {
                                  await widget.onVisibleLimitChanged(limit);
                                  if (!mounted) return;
                                  setState(() => _visibleLimit = limit);
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _FilterSectionLabel(
                    label: AppCopy.t(
                      language,
                      ko: '지역 프리셋',
                      en: 'Region presets',
                      fr: 'Régions',
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _routeRegionPresets.length; i++)
                    _RouteOptionTile(
                      option: _RouteOption(
                        i,
                        _routeRegionPresets[i].title,
                        _routeRegionPresets[i].subtitle,
                      ),
                      selected:
                          _routeRegionPresets[i].key == _selectedRegionKey,
                      enabled: !widget.busy,
                      onTap: () async {
                        await widget.onRegionChanged(i);
                        if (!mounted) return;
                        setState(
                          () => _selectedRegionKey = _routeRegionPresets[i].key,
                        );
                      },
                    ),
                  const SizedBox(height: 4),
                  _CurveRoadSwitchTile(
                    value: _curveRoadView,
                    language: language,
                    onChanged: (value) {
                      widget.onCurveRoadViewChanged(value);
                      setState(() => _curveRoadView = value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
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

class _RouteRegion {
  final String key;
  final String title;
  final String subtitle;
  final LatLng point;

  const _RouteRegion(this.key, this.title, this.subtitle, this.point);
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
  final bool enabled;
  final VoidCallback? onTap;

  const _RouteOptionTile({
    required this.option,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? onTap ?? () => Navigator.pop(context, option.value)
          : null,
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
              color: !enabled
                  ? AppColors.textHint
                  : selected
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
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: AppText.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: enabled
                          ? AppColors.textSecondary
                          : AppColors.textHint,
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

class _RouteStrengthTile extends StatelessWidget {
  final RouteFilterStrength strength;
  final bool selected;
  final AppLanguage language;
  final VoidCallback? onTap;

  const _RouteStrengthTile({
    required this.strength,
    required this.selected,
    required this.language,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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

class DriveBudgetChoiceStrip extends StatelessWidget {
  final DriveBudget budget;
  final List<RevvRoute> routes;
  final ValueChanged<DriveBudget> onChanged;

  const DriveBudgetChoiceStrip({
    super.key,
    required this.budget,
    required this.routes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final item in DriveBudget.values) ...[
              _BudgetChip(
                label: driveBudgetLabel(item, language),
                selected: budget == item,
                onTap: () => onChanged(item),
              ),
              if (item != DriveBudget.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class DriveBudgetEmptyCard extends StatelessWidget {
  final AppLanguage language;
  final VoidCallback onAction;

  const DriveBudgetEmptyCard({
    super.key,
    required this.language,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _LeanEmptyTicket(
      title: AppCopy.t(
        language,
        ko: '이 분량에 맞는 루트가 아직 없어요',
        en: 'No routes for this duration yet',
        fr: 'Aucune route pour cette durée',
      ),
      body: AppCopy.t(
        language,
        ko: '다른 분량을 고르거나 반경/지역을 바꿔 더 많은 후보를 확인해 보세요.',
        en: 'Choose another duration or change the radius/region to compare more picks.',
        fr: 'Choisissez une autre durée ou changez le rayon/la région pour comparer plus d’options.',
      ),
      actionLabel: AppCopy.t(
        language,
        ko: '전체 분량',
        en: 'Any duration',
        fr: 'Toute durée',
      ),
      actionIcon: Icons.schedule_rounded,
      onAction: onAction,
    );
  }
}

class _BudgetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BudgetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? AppColors.primaryContainer
        : AppColors.ink.withValues(alpha: 0.87);
    final foreground = selected ? AppColors.onPrimary : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: background,
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
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
        : AppColors.ink.withValues(alpha: 0.87);
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
            _HeatDot(color: AppColors.cyan),
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
            _HeatDot(color: AppColors.orange),
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
            _HeatDot(color: AppColors.danger),
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

class _LeanCircleButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;

  const _LeanCircleButton({
    required this.icon,
    this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
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

class _LeanSearchButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _LeanSearchButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primaryContainer
              : AppColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: enabled
                ? AppColors.primaryContainer.withValues(alpha: 0.82)
                : AppColors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.travel_explore_rounded,
              size: 16,
              color: enabled ? AppColors.onPrimary : AppColors.textHint,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w900,
                  color: enabled ? AppColors.onPrimary : AppColors.textHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeanFilterButton extends StatelessWidget {
  final int activeCount;
  final String tooltip;
  final VoidCallback? onTap;

  const _LeanFilterButton({
    super.key,
    required this.activeCount,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _LeanCircleButton(
          icon: Icons.tune_rounded,
          tooltip: tooltip,
          onTap: onTap,
        ),
        if (activeCount > 0)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              key: const Key('route-finder-filter-badge'),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.primaryContainer
                    : AppColors.textHint,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.ink, width: 1.5),
              ),
              child: Text(
                '$activeCount',
                style: AppText.mono(
                  size: 10,
                  weight: FontWeight.w900,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  final String label;
  const _FilterSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppText.technicalLabel(
        size: 11,
        color: AppColors.primaryContainer,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _FilterChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _FilterChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryContainer
              : AppColors.surface.withValues(alpha: enabled ? 0.72 : 0.38),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer.withValues(alpha: 0.82)
                : AppColors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: AppText.body(
            size: 12,
            weight: FontWeight.w900,
            color: !enabled
                ? AppColors.textHint
                : selected
                ? AppColors.onPrimary
                : AppColors.primaryContainer,
          ),
        ),
      ),
    );
  }
}

class _CurveRoadSwitchTile extends StatelessWidget {
  final bool value;
  final AppLanguage language;
  final ValueChanged<bool> onChanged;

  const _CurveRoadSwitchTile({
    required this.value,
    required this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primaryContainer,
      title: Text(
        AppCopy.t(
          language,
          ko: '커브길 히트맵',
          en: 'Curve road heatmap',
          fr: 'Carte des virages',
        ),
        style: AppText.body(
          size: 14,
          weight: FontWeight.w900,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        AppCopy.t(
          language,
          ko: '켜면 지도 위에 커브 밀도 범례를 표시합니다.',
          en: 'Shows the curve-density legend on the map.',
          fr: 'Affiche la légende de densité des virages.',
        ),
        style: AppText.body(
          size: 12,
          weight: FontWeight.w700,
          color: AppColors.textSecondary,
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
        color: AppColors.ink.withValues(alpha: 0.91),
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

int _activeFilterCount({
  required _RouteLens lens,
  required RouteFilterStrength filterStrength,
  required bool visibleLimitChanged,
  required String? selectedRegionKey,
  required bool curveRoadView,
}) {
  var count = 0;
  if (lens != _RouteLens.all) count++;
  if (filterStrength != RouteFilterStrength.balanced) count++;
  if (visibleLimitChanged) count++;
  if (selectedRegionKey != null) count++;
  if (curveRoadView) count++;
  return count;
}

String driveBudgetLabel(DriveBudget budget, AppLanguage language) {
  return switch (budget) {
    DriveBudget.any => AppCopy.t(language, ko: '전체', en: 'Any', fr: 'Tout'),
    DriveBudget.short => AppCopy.t(
      language,
      ko: '~30분',
      en: '~30 min',
      fr: '~30 min',
    ),
    DriveBudget.medium => AppCopy.t(
      language,
      ko: '~1시간',
      en: '~1 hour',
      fr: '~1 h',
    ),
    DriveBudget.long => AppCopy.t(language, ko: '2시간+', en: '2h+', fr: '2 h+'),
  };
}

String _routeListMeta(RevvRoute route, AppLanguage language) {
  final minutes = estimatedDriveMinutes(route);
  final distance = route.distanceFromUser >= 10
      ? route.distanceFromUser.round().toString()
      : route.distanceFromUser.toStringAsFixed(1);
  return AppCopy.t(
    language,
    ko: '~$minutes분 · 시작점까지 ${distance}km',
    en: '~$minutes min · $distance km to start',
    fr: '~$minutes min · départ à $distance km',
  );
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

RouteFinderStateKind? _routeFinderStateKind({
  required LocationService location,
  required RouteService service,
  required List<RevvRoute> visibleRoutes,
  required bool filterEmpty,
}) {
  final locationBlocked =
      !location.hasPermission && !location.hasBestKnownLocation;
  if (locationBlocked) {
    return location.permissionStatus.isPermanentlyDenied
        ? RouteFinderStateKind.permanentlyLocationDenied
        : RouteFinderStateKind.temporaryLocationDenied;
  }
  if (filterEmpty) return null;
  if (service.routeFieldFromCache && visibleRoutes.isNotEmpty) {
    return RouteFinderStateKind.cachedRoutes;
  }
  if (service.routeDataStatusTitle == '루트 로드 실패' ||
      service.errorMessage == '루트를 불러오지 못했어요') {
    return RouteFinderStateKind.loadFailed;
  }
  if (visibleRoutes.isEmpty &&
      (service.routeDataStatusTitle == '루트 후보 없음' ||
          service.routeDataStatusTitle == '커브길 없음' ||
          service.errorMessage == '주변 커브길을 찾지 못했어요' ||
          service.errorMessage == '주변 루트를 찾지 못했어요')) {
    return RouteFinderStateKind.emptyRoutes;
  }
  return null;
}

String routeFinderStateTitle(RouteFinderStateKind kind, AppLanguage language) {
  return switch (kind) {
    RouteFinderStateKind.temporaryLocationDenied => AppCopy.t(
      language,
      ko: '위치 권한이 꺼져 있어요',
      en: 'Location permission is off',
      fr: 'La position est désactivée',
    ),
    RouteFinderStateKind.permanentlyLocationDenied => AppCopy.t(
      language,
      ko: '설정에서 위치 권한을 켜주세요',
      en: 'Turn on location in Settings',
      fr: 'Activez la position dans Réglages',
    ),
    RouteFinderStateKind.emptyRoutes => AppCopy.t(
      language,
      ko: '이 반경엔 아직 발견된 루트가 없어요',
      en: 'No routes found in this radius yet',
      fr: 'Aucune route trouvée dans ce rayon',
    ),
    RouteFinderStateKind.loadFailed => AppCopy.t(
      language,
      ko: '루트를 불러오지 못했어요',
      en: 'Could not load routes',
      fr: 'Impossible de charger les routes',
    ),
    RouteFinderStateKind.cachedRoutes => AppCopy.t(
      language,
      ko: '저장된 루트를 먼저 보여드려요',
      en: 'Showing saved routes first',
      fr: 'Affichage des routes enregistrées',
    ),
  };
}

String routeFinderStateBody(RouteFinderStateKind kind, AppLanguage language) {
  return switch (kind) {
    RouteFinderStateKind.temporaryLocationDenied => AppCopy.t(
      language,
      ko: '근처 루트를 찾으려면 위치 권한을 허용하거나 지역 프리셋을 선택하세요.',
      en: 'Allow location to find nearby routes, or choose a region preset.',
      fr: 'Autorisez la position ou choisissez une région.',
    ),
    RouteFinderStateKind.permanentlyLocationDenied => AppCopy.t(
      language,
      ko: '권한이 차단되어 앱 안에서 다시 묻기 어렵습니다. 설정에서 위치를 허용하거나 지역 프리셋을 선택하세요.',
      en: 'Permission is blocked. Open Settings to allow location, or choose a region preset.',
      fr: 'Autorisation bloquée. Ouvrez Réglages ou choisissez une région.',
    ),
    RouteFinderStateKind.emptyRoutes => AppCopy.t(
      language,
      ko: '반경을 넓히거나 지역 프리셋으로 다른 도시를 살펴보세요.',
      en: 'Broaden the radius or use a region preset to check another city.',
      fr: 'Élargissez le rayon ou choisissez une autre région.',
    ),
    RouteFinderStateKind.loadFailed => AppCopy.t(
      language,
      ko: '연결 상태가 안정되면 다시 시도해 주세요. 저장된 루트가 있으면 먼저 보여드릴게요.',
      en: 'Try again when the connection is stable. Saved routes will be shown first when available.',
      fr: 'Réessayez avec une connexion stable. Les routes enregistrées s’affichent si possible.',
    ),
    RouteFinderStateKind.cachedRoutes => AppCopy.t(
      language,
      ko: '최신 데이터 연결이 실패해 마지막으로 저장된 커브길을 사용 중입니다.',
      en: 'Fresh route data failed to load, so the last saved curvy roads are in use.',
      fr: 'Les données récentes ont échoué; les routes enregistrées sont utilisées.',
    ),
  };
}

String coverageBoundaryTitle(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '지금은 몬트리올 일대의 루트를 제공해요',
    en: 'Routes are available around Montreal right now',
    fr: 'Les routes sont disponibles autour de Montréal pour l’instant',
  );
}

String coverageBoundaryBody(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '이 지역은 준비 중이에요. 지역 프리셋에서 몬트리올 루트를 먼저 구경할 수 있어요.',
    en: 'This area is in preparation. Use region presets to preview Montreal routes first.',
    fr: 'Cette région est en préparation. Utilisez les régions pour voir les routes de Montréal.',
  );
}

String coverageBoundaryRequestLabel(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '우리 지역 알림 받기',
    en: 'Notify me here',
    fr: 'M’aviser ici',
  );
}

String coverageBoundarySavingLabel(AppLanguage language) {
  return AppCopy.t(language, ko: '신청 중', en: 'Saving', fr: 'Enregistrement');
}

String coverageBoundaryDoneLabel(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '알림 신청됨',
    en: 'Notification requested',
    fr: 'Alerte enregistrée',
  );
}

String routeFinderStateActionLabel(
  RouteFinderStateKind kind,
  AppLanguage language,
) {
  return switch (kind) {
    RouteFinderStateKind.temporaryLocationDenied => AppCopy.t(
      language,
      ko: '위치 다시 허용',
      en: 'Allow location',
      fr: 'Autoriser',
    ),
    RouteFinderStateKind.permanentlyLocationDenied => AppCopy.openSettings(
      language,
    ),
    RouteFinderStateKind.emptyRoutes => AppCopy.t(
      language,
      ko: '지역 프리셋',
      en: 'Region presets',
      fr: 'Régions',
    ),
    RouteFinderStateKind.loadFailed => AppCopy.t(
      language,
      ko: '다시 찾기',
      en: 'Retry',
      fr: 'Réessayer',
    ),
    RouteFinderStateKind.cachedRoutes => AppCopy.t(
      language,
      ko: '추천 보기',
      en: 'Show picks',
      fr: 'Voir options',
    ),
  };
}

IconData routeFinderStateActionIcon(RouteFinderStateKind kind) {
  return switch (kind) {
    RouteFinderStateKind.temporaryLocationDenied => Icons.my_location_rounded,
    RouteFinderStateKind.permanentlyLocationDenied => Icons.settings_rounded,
    RouteFinderStateKind.emptyRoutes => Icons.public_rounded,
    RouteFinderStateKind.loadFailed => Icons.refresh_rounded,
    RouteFinderStateKind.cachedRoutes => Icons.route_rounded,
  };
}

String _cacheInlineStatus(int count, AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '선택할 수 있는 저장 루트 $count개를 표시하고 있어요.',
    en: 'Showing $count saved routes to choose from.',
    fr: '$count routes enregistrées affichées.',
  );
}

String _emptyRouteBody(RouteService service, AppLanguage language) {
  final base =
      _localizedRouteStatusBody(service, language) ??
      AppCopy.t(
        language,
        ko: '현재 위치와 연결 상태를 확인한 뒤 다시 시도해 주세요.',
        en: 'Check location and connection, then try again.',
        fr: 'Vérifiez la position et la connexion, puis réessayez.',
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
  if (raw.contains('루트 데이터를 연결') || raw.contains('클라우드 설정')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Route data connection needed.',
      fr: 'Connexion aux données requise.',
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
    '루트 데이터 연결 필요' => AppCopy.t(
      language,
      ko: raw,
      en: 'Route data connection needed',
      fr: 'Connexion aux données requise',
    ),
    '클라우드 설정 없음' => AppCopy.t(
      language,
      ko: raw,
      en: 'Route data connection needed',
      fr: 'Connexion aux données requise',
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
  if (raw.contains('루트 데이터 연결') || raw.contains('클라우드')) {
    return AppCopy.t(
      language,
      ko: raw,
      en: 'Check the route data connection, then try again.',
      fr: 'Vérifiez la connexion aux données, puis réessayez.',
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
