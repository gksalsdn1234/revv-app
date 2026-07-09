import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import '../services/drive_planner_service.dart';
import '../services/external_nav.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../services/recommendation_log_service.dart';
import '../services/route_loading_policy.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_difficulty_profile.dart';
import '../ui/route_quality_profile.dart';
import '../ui/winding_experience.dart';
import '../widgets/copilot_start_sheet.dart';
import '../widgets/journey_sheet.dart';
import '../widgets/map_widget.dart';
import '../widgets/place_search_sheet.dart';
import '../widgets/revv_ui.dart';
import 'lean_drive_screen.dart';
import 'lean_route_detail_screen.dart';

enum _RouteLens { all, nearby, sweeper, tight, flow, loop }

enum _RouteMapMode { wide, balanced, close }

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
  final DrivePlannerService? planner;
  final PlaceSearchService? placeSearch;
  final RecommendationLogService? recommendationLogService;

  const LeanRouteFinderScreen({
    super.key,
    this.planner,
    this.placeSearch,
    this.recommendationLogService,
  });

  @override
  State<LeanRouteFinderScreen> createState() => _LeanRouteFinderScreenState();
}

class _LeanRouteFinderScreenState extends State<LeanRouteFinderScreen> {
  int _selectedIndex = 0;
  int _recenterSignal = 0;
  int _mapFocusSignal = 0;
  _RouteLens _lens = _RouteLens.all;
  LatLng? _mapCenterPoint;
  String? _localStatusMessage;
  double _mapZoom = 11.0;
  final bool _curveRoadView = false;
  bool _hasUserSelectedRoute = false;
  bool _coverageRequestInProgress = false;
  DriveBudget _driveBudget = DriveBudget.any;
  bool _loopOnly = false;
  RevvRoute? _selectedRouteOverride;
  String? _selectedRegionKey;
  LatLng? _coverageRequestPoint;
  final Map<String, RevvRoute> _chainSelection = {};
  late final DrivePlannerService _planner =
      widget.planner ?? DrivePlannerService();
  late final PlaceSearchService _placeSearch =
      widget.placeSearch ?? PlaceSearchService();
  late final RecommendationLogService _recommendationLog =
      widget.recommendationLogService ?? RecommendationLogService();
  final DraggableScrollableController _journeySheetController =
      DraggableScrollableController();
  LatLng? _destination;
  String? _destinationName;
  LatLng? _journeyOrigin;
  List<DrivePlanOption>? _options;
  List<FreeRoamOption>? _freeRoamOptions;
  DrivePlanOptionKind _selectedKind = DrivePlanOptionKind.standard;
  int _selectedFreeRoamIndex = 0;
  bool _planning = false;
  String? _journeyMode;
  String? _lastShownSignature;

  bool get _chainMode => _chainSelection.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_searchCurrentLocation());
  }

  @override
  void dispose() {
    _journeySheetController.dispose();
    super.dispose();
  }

  DrivePlan? get _plan {
    final freeOptions = _freeRoamOptions;
    if (_journeyMode == 'free' &&
        freeOptions != null &&
        freeOptions.isNotEmpty) {
      final index = _selectedFreeRoamIndex
          .clamp(0, freeOptions.length - 1)
          .toInt();
      return freeOptions[index].plan;
    }
    final options = _options;
    if (options == null || options.isEmpty) return null;
    return options
        .firstWhere(
          (option) => option.kind == _selectedKind,
          orElse: () => options.first,
        )
        .plan;
  }

  LatLng? get _planDestination {
    if (_journeyMode == 'free') return _journeyOrigin;
    return _destination ?? _plan?.waypoints.last;
  }

  List<List<LatLng>> get _transitPolylines =>
      _planPolylines(DrivePlanLegKind.transit);

  List<List<LatLng>> get _windingPolylines =>
      _planPolylines(DrivePlanLegKind.winding);

  List<PlanMapMarker> get _planMarkers {
    final plan = _plan;
    final origin = _journeyOrigin;
    final destination = _planDestination;
    if (plan == null || origin == null || destination == null) return const [];
    return buildJourneyPlanMapMarkers(
      origin: origin,
      destination: destination,
      plan: plan,
    );
  }

  List<List<LatLng>> _planPolylines(DrivePlanLegKind kind) {
    final plan = _plan;
    if (plan == null) return const [];
    return [
      for (final leg in plan.legs)
        if (leg.kind == kind && leg.nodes.isNotEmpty) leg.nodes,
    ];
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
    if (routes.visibleRouteLimit < 32) {
      routes.visibleRouteLimit = 32;
    }
    if (!isPointInsideRouteCoverage(point)) {
      setState(() {
        _lens = _RouteLens.all;
        _selectedIndex = 0;
        _hasUserSelectedRoute = false;
        _selectedRouteOverride = null;
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
      _selectedIndex = 0;
      _hasUserSelectedRoute = false;
      _selectedRouteOverride = null;
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

  Future<void> _openDestinationSearch() async {
    final language = context.read<SettingsService>().appLanguage;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaceSearchSheet(
        language: language,
        service: _placeSearch,
        proximity: _mapCenterPoint ?? _routeRegionPresets.first.point,
        selected: _destination,
        allowMapPin: false,
      ),
    );
    if (!mounted || result is! PlaceResult) return;
    setState(() {
      _destination = result.point;
      _destinationName = result.name;
      _mapCenterPoint = result.point;
      _mapFocusSignal++;
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
      _selectedKind = DrivePlanOptionKind.standard;
      _selectedFreeRoamIndex = 0;
    });
    await _fetchAtPoint(result.point, forceRefresh: true, regionKey: null);
    if (!mounted) return;
    unawaited(_buildDestinationJourney());
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _destinationName = null;
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
      _selectedKind = DrivePlanOptionKind.standard;
      _selectedFreeRoamIndex = 0;
    });
  }

  Future<void> _buildDestinationJourney() async {
    final destination = _destination;
    if (destination == null || _planning) return;
    final origin = await _resolveSearchPoint();
    if (!mounted || origin == null) return;
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _journeyOrigin = origin;
      _journeyMode = 'destination';
      _options = null;
      _freeRoamOptions = null;
      _localStatusMessage = null;
    });
    try {
      final options = await _planner.buildPlanOptions(
        DrivePlanRequest(
          origin: origin,
          destination: destination,
          windingBudgetMinutes: _budgetMinutes(_driveBudget),
        ),
      );
      if (!mounted) return;
      setState(() {
        _options = options.isEmpty ? null : options;
        _selectedKind = DrivePlanOptionKind.standard;
        _localStatusMessage = options.isEmpty
            ? AppCopy.t(
                language,
                ko: '이 조건으로 여정을 만들지 못했어요.',
                en: 'Could not build a plan for this route.',
                fr: 'Impossible de créer ce trajet.',
              )
            : null;
      });
      if (options.isNotEmpty) {
        unawaited(_logShownOnce(mode: 'destination', options: options));
        _snapSheetOpen();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localStatusMessage = AppCopy.t(
          language,
          ko: '여정 계산이 오래 걸려 중단했어요. 다시 시도해 주세요.',
          en: 'Planning took too long. Try again.',
          fr: 'Le calcul a pris trop de temps. Réessayez.',
        );
      });
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _buildFreeRoamJourney() async {
    if (_planning) return;
    final origin = await _resolveSearchPoint();
    if (!mounted || origin == null) return;
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _journeyOrigin = origin;
      _journeyMode = 'free';
      _options = null;
      _freeRoamOptions = null;
      _selectedFreeRoamIndex = 0;
      _localStatusMessage = null;
    });
    try {
      final options = await _planner.buildFreeRoamOptions(
        origin: origin,
        totalBudgetMinutes: _budgetMinutes(_driveBudget),
      );
      if (!mounted) return;
      setState(() {
        _freeRoamOptions = options.isEmpty ? null : options;
        _localStatusMessage = options.isEmpty
            ? AppCopy.t(
                language,
                ko: '이 시간 안에 추천 루프를 만들지 못했어요.',
                en: 'Could not build a loop for this time.',
                fr: 'Impossible de créer une boucle pour cette durée.',
              )
            : null;
      });
      if (options.isNotEmpty) {
        unawaited(_logShownOnce(mode: 'free', freeRoamOptions: options));
        _snapSheetOpen();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localStatusMessage = AppCopy.t(
          language,
          ko: '여정 계산이 오래 걸려 중단했어요. 다시 시도해 주세요.',
          en: 'Planning took too long. Try again.',
          fr: 'Le calcul a pris trop de temps. Réessayez.',
        );
      });
    } finally {
      if (mounted) setState(() => _planning = false);
    }
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
      _mapCenterPoint = routes[clamped].centerPoint;
      _mapFocusSignal++;
    });
    context.read<RouteService>().selectRoute(routes[clamped]);
  }

  void _selectRouteFromList(List<RevvRoute> routes, RevvRoute route) {
    final index = routes.indexWhere((candidate) => candidate.id == route.id);
    if (index >= 0) {
      _selectIndex(routes, index);
      return;
    }
    setState(() {
      _hasUserSelectedRoute = true;
      _selectedRouteOverride = route;
      _mapCenterPoint = route.centerPoint;
      _mapFocusSignal++;
    });
    context.read<RouteService>().selectRoute(route);
  }

  void _toggleChainRoute(RevvRoute route) {
    setState(() {
      if (_chainSelection.containsKey(route.id)) {
        _chainSelection.remove(route.id);
      } else {
        _chainSelection[route.id] = route;
      }
    });
  }

  void _clearChainSelection() {
    setState(_chainSelection.clear);
  }

  int get _selectedOptionBudget {
    final freeOptions = _freeRoamOptions;
    if (_journeyMode == 'free' &&
        freeOptions != null &&
        freeOptions.isNotEmpty) {
      final index = _selectedFreeRoamIndex
          .clamp(0, freeOptions.length - 1)
          .toInt();
      return freeOptions[index].budgetMinutes;
    }
    final options = _options;
    if (options == null || options.isEmpty) return _budgetMinutes(_driveBudget);
    return options
        .firstWhere(
          (option) => option.kind == _selectedKind,
          orElse: () => options.first,
        )
        .budgetMinutes;
  }

  RevvRoute? get _firstWindingRoute {
    final plan = _plan;
    if (plan == null) return null;
    for (final leg in plan.legs) {
      if (leg.kind == DrivePlanLegKind.winding && leg.route != null) {
        return leg.route;
      }
    }
    return null;
  }

  Future<void> _startChainDrive() async {
    if (_chainSelection.length < 2) return;
    final origin = await _resolveSearchPoint();
    if (!mounted || origin == null) return;
    final selectedRoutes = _chainSelection.values.toList();
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _journeyOrigin = origin;
      _journeyMode = 'chain';
      _options = null;
      _freeRoamOptions = null;
      _localStatusMessage = null;
    });
    DrivePlan plan;
    try {
      plan = await _planner.buildPlanFromRoutes(
        origin: origin,
        routes: selectedRoutes,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _planning = false;
        _localStatusMessage = AppCopy.t(
          language,
          ko: '선택한 루트로 여정을 만들지 못했어요.',
          en: 'Could not build a plan from selected routes.',
          fr: 'Impossible de créer un trajet avec ces routes.',
        );
      });
      return;
    }
    if (!mounted) return;
    final option = DrivePlanOption(
      kind: DrivePlanOptionKind.standard,
      budgetMinutes: plan.windingMinutes,
      plan: plan,
    );
    setState(() {
      _planning = false;
      _destination = plan.waypoints.last;
      _destinationName = AppCopy.t(
        language,
        ko: '선택 루트 끝점',
        en: 'Selected route end',
        fr: 'Fin des routes choisies',
      );
      _options = [option];
      _selectedKind = DrivePlanOptionKind.standard;
    });
    unawaited(_logShownOnce(mode: 'chain', options: [option]));
    _snapSheetOpen();
  }

  Future<void> _logShownOnce({
    required String mode,
    List<DrivePlanOption>? options,
    List<FreeRoamOption>? freeRoamOptions,
  }) async {
    final origin = _journeyOrigin;
    final budgetMinutes = mode == 'chain'
        ? (options ?? const <DrivePlanOption>[]).first.budgetMinutes
        : _budgetMinutes(_driveBudget);
    final signature =
        '$mode:${_destination?.lat}:${_destination?.lng}:$budgetMinutes';
    if (_lastShownSignature == signature) return;
    _lastShownSignature = signature;
    await _recommendationLog.logShown(
      mode: mode,
      routeIds: mode == 'free'
          ? _freeRoamRouteIds(freeRoamOptions ?? const <FreeRoamOption>[])
          : _windingRouteIds(options ?? const <DrivePlanOption>[]),
      origin: origin,
      budgetMinutes: budgetMinutes,
    );
  }

  Future<void> _startFirstWinding() async {
    final route = _firstWindingRoute;
    final origin = _journeyOrigin;
    if (route == null) return;
    final startChoice = await showCopilotStartSheet(context, route: route);
    if (!mounted || startChoice == null) return;
    unawaited(
      _recommendationLog.logChosen(
        mode: _journeyMode ?? 'destination',
        routeId: route.id,
        optionKind: _journeyMode == 'free' ? 'free' : _selectedKind.key,
        origin: origin,
        budgetMinutes: _selectedOptionBudget,
      ),
    );
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

  Future<void> _openExternalNavigation() async {
    final plan = _plan;
    final origin = _journeyOrigin;
    final destination = _planDestination;
    if (plan == null || origin == null || destination == null) return;
    final language = context.read<SettingsService>().appLanguage;
    final waypoints = selectHandoffWaypoints(legs: plan.legs);
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': googleMapsCoord(origin),
      'destination': googleMapsCoord(destination),
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map(googleMapsCoord).join('|'),
      'travelmode': 'driving',
    });
    final appUri = buildGoogleMapsAppUri(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );
    var launched = false;
    try {
      launched = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(
          webUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      launched = false;
    }
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
    );
  }

  void _backToList() {
    setState(() {
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
      _selectedFreeRoamIndex = 0;
      _selectedKind = DrivePlanOptionKind.standard;
    });
  }

  void _snapSheetOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_journeySheetController.isAttached ||
          _journeySheetController.size >= 0.42) {
        return;
      }
      unawaited(
        _journeySheetController.animateTo(
          0.42,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _setLens(_RouteLens lens) {
    setState(() {
      _lens = lens;
      _selectedIndex = 0;
      _hasUserSelectedRoute = false;
      _selectedRouteOverride = null;
    });
  }

  void _setDriveBudget(DriveBudget budget) {
    setState(() {
      _driveBudget = budget;
      _selectedIndex = 0;
      _hasUserSelectedRoute = false;
      _selectedRouteOverride = null;
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
    });
  }

  void _setLoopOnly(bool value) {
    setState(() {
      _loopOnly = value;
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

  Future<void> _openLocationSettings() async {
    await openAppSettings();
  }

  void _selectRouteFromMap(String routeId) {
    final service = context.read<RouteService>();
    final visibleRoutes = _visibleRoutesFor(service.routes);
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

  List<RevvRoute> _visibleRoutesFor(List<RevvRoute> routes) {
    final loopRoutes = _loopOnly
        ? routes.where((route) => route.isLoop).toList()
        : routes;
    final lensRoutes = _rankRoutes(_filterRoutes(loopRoutes, _lens));
    return routesForDriveBudget(lensRoutes, budget: _driveBudget);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RouteService>();
    final location = context.watch<LocationService>();
    final routes = service.routes;
    final loopFilteredRoutes = _loopOnly
        ? routes.where((route) => route.isLoop).toList()
        : routes;
    final lensRoutes = _rankRoutes(_filterRoutes(loopFilteredRoutes, _lens));
    final visibleRoutes = routesForDriveBudget(
      lensRoutes,
      budget: _driveBudget,
    );
    final mapSourceRoutes = _driveBudget == DriveBudget.any
        ? service.mapVisualRoutes
        : visibleRoutes;
    final mapDisplayRoutes = _routesForViewport(
      mapSourceRoutes.isNotEmpty ? mapSourceRoutes : visibleRoutes,
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
    final plan = _plan;
    final showingJourney = _journeyMode != null && plan != null;
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
        ? _cacheInlineStatus(service, language)
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
                navPolylines: showingJourney ? _transitPolylines : null,
                routePolyline: showingJourney ? null : selected?.nodes,
                routePolylines: showingJourney ? _windingPolylines : null,
                curveHeatmap: !showingJourney,
                planMarkers: showingJourney ? _planMarkers : null,
                candidatePolylines: showingJourney
                    ? const []
                    : [
                        for (final route in mapDisplayRoutes)
                          if (route.id != selected?.id) route.nodes,
                      ],
                curveHeatmapPolylines: const [],
                difficultyLines: showingJourney
                    ? const []
                    : _difficultyLines(mapDisplayRoutes, selected),
                strongCurveFieldHeatmap: _curveRoadView,
                routeFocusMode: false,
                recenterSignal: _recenterSignal,
                cameraTarget: _mapCenterPoint,
                cameraTargetSignal: _mapFocusSignal,
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
                      onBack: () => Navigator.pop(context),
                      destinationName: _destinationName,
                      onDestination: _openDestinationSearch,
                      onClearDestination: _destination == null
                          ? null
                          : _clearDestination,
                      onRecenter: () => setState(() => _recenterSignal++),
                    ),
                    const SizedBox(height: 8),
                    FinderFilterStrip(
                      budget: _driveBudget,
                      loopOnly: _loopOnly,
                      onChanged: _setDriveBudget,
                      onLoopOnlyChanged: _setLoopOnly,
                    ),
                    if (_chainMode) ...[
                      const SizedBox(height: 8),
                      _RouteChainBar(
                        language: language,
                        count: _chainSelection.length,
                        totalDistanceKm: _chainSelection.values.fold<double>(
                          0,
                          (total, route) => total + route.distanceKm,
                        ),
                        onCancel: _clearChainSelection,
                        onChain: _chainSelection.length >= 2
                            ? () => unawaited(_startChainDrive())
                            : null,
                      ),
                    ],
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
            Positioned.fill(
              child: coverageGrid != null
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          MediaQuery.paddingOf(context).bottom + 14,
                        ),
                        child: RouteCoverageBoundaryCard(
                          language: language,
                          requested: coverageRequested,
                          requesting: _coverageRequestInProgress,
                          onRequest: () =>
                              _requestCoverageNotification(coverageGrid),
                          onBrowseMontreal: _selectRegionPreset,
                        ),
                      ),
                    )
                  : showingJourney
                  ? JourneySheet(
                      controller: _journeySheetController,
                      language: language,
                      destinationName: _destinationName,
                      options: _options,
                      freeRoamOptions: _freeRoamOptions,
                      plan: plan,
                      recommended: null,
                      arriveBy: null,
                      selectedKind: _selectedKind,
                      selectedFreeRoamIndex: _selectedFreeRoamIndex,
                      selectedOptionBudget: _selectedOptionBudget,
                      canStart: _firstWindingRoute != null,
                      onBack: _backToList,
                      onSearchDestination: _openDestinationSearch,
                      onSelectedOption: (kind) =>
                          setState(() => _selectedKind = kind),
                      onSelectedFreeRoam: (index) =>
                          setState(() => _selectedFreeRoamIndex = index),
                      onStart: _startFirstWinding,
                      onNavigate: _openExternalNavigation,
                    )
                  : _FinderRoutesSheet(
                      language: language,
                      routes: visibleRoutes,
                      destinationName: _destinationName,
                      planning: _planning,
                      emptyTitle: stateKind != null
                          ? routeFinderStateTitle(stateKind, language)
                          : emptyTitle,
                      emptyBody: stateKind != null
                          ? routeFinderStateBody(stateKind, language)
                          : emptyBody,
                      onEmptyAction: stateKind != null
                          ? switch (stateKind) {
                              RouteFinderStateKind.temporaryLocationDenied =>
                                _searchCurrentLocation,
                              RouteFinderStateKind.permanentlyLocationDenied =>
                                _openLocationSettings,
                              RouteFinderStateKind.emptyRoutes =>
                                _selectRegionPreset,
                              RouteFinderStateKind.loadFailed => _searchHere,
                              RouteFinderStateKind.cachedRoutes => _searchHere,
                            }
                          : budgetEmpty
                          ? () => _setDriveBudget(DriveBudget.any)
                          : filterEmpty
                          ? () => _setLens(_RouteLens.all)
                          : canBroadenStrength
                          ? () =>
                                _applyFilterStrength(RouteFilterStrength.broad)
                          : _searchHere,
                      onFreeRoam: _destination == null
                          ? () => unawaited(_buildFreeRoamJourney())
                          : null,
                      selectedRouteId: selected?.id,
                      chainSelection: _chainSelection,
                      onRouteTap: (route) {
                        _selectRouteFromList(visibleRoutes, route);
                      },
                      onToggleChain: _toggleChainRoute,
                      onGo: (route) => unawaited(_startDrive(route)),
                      onDetails: _showRouteDetails,
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

class _FinderRoutesSheet extends StatelessWidget {
  final AppLanguage language;
  final List<RevvRoute> routes;
  final String? destinationName;
  final bool planning;
  final String emptyTitle;
  final String emptyBody;
  final VoidCallback onEmptyAction;
  final VoidCallback? onFreeRoam;
  final String? selectedRouteId;
  final Map<String, RevvRoute> chainSelection;
  final ValueChanged<RevvRoute> onRouteTap;
  final ValueChanged<RevvRoute> onToggleChain;
  final ValueChanged<RevvRoute> onGo;
  final ValueChanged<RevvRoute> onDetails;

  const _FinderRoutesSheet({
    required this.language,
    required this.routes,
    required this.destinationName,
    required this.planning,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onEmptyAction,
    required this.onFreeRoam,
    required this.selectedRouteId,
    required this.chainSelection,
    required this.onRouteTap,
    required this.onToggleChain,
    required this.onGo,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.18,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.18, 0.42, 0.85],
      builder: (context, scrollController) {
        return RevvGlassCard(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          padding: EdgeInsets.zero,
          radius: 18,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              const _SheetHandle(),
              Text(
                _finderSummary(routes, destinationName, language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 14,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              if (planning)
                JourneyPlanningCard(language: language, framed: false)
              else if (routes.isEmpty)
                _LeanEmptyTicket(
                  title: emptyTitle,
                  body: emptyBody,
                  actionLabel: AppCopy.t(
                    language,
                    ko: '다시 찾기',
                    en: 'Retry',
                    fr: 'Réessayer',
                  ),
                  actionIcon: Icons.refresh_rounded,
                  onAction: onEmptyAction,
                )
              else ...[
                if (onFreeRoam != null) ...[
                  OutlinedButton.icon(
                    key: const Key('finder-free-roam-button'),
                    onPressed: onFreeRoam,
                    icon: const Icon(Icons.explore_rounded, size: 18),
                    label: Text(
                      AppCopy.t(
                        language,
                        ko: '그냥 추천',
                        en: 'Surprise me',
                        fr: 'Suggestion',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(
                        color: AppColors.outline.withValues(alpha: 0.28),
                      ),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final route in routes) ...[
                  GestureDetector(
                    onTap: () => onRouteTap(route),
                    child: _LeanRouteTicket(
                      route: route,
                      index: routes.indexOf(route),
                      total: routes.length,
                      onPrev: null,
                      onNext: null,
                      onGo: () => onGo(route),
                      onDetails: () => onDetails(route),
                      mapSelected: route.id == selectedRouteId,
                      chainMode: false,
                      chainCount: chainSelection.length,
                      chainSelected: chainSelection.containsKey(route.id),
                      onToggleChain: () => onToggleChain(route),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.outlineVariant.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _LeanRouteTopBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onBack;
  final String? destinationName;
  final VoidCallback onDestination;
  final VoidCallback? onClearDestination;
  final VoidCallback onRecenter;

  const _LeanRouteTopBar({
    required this.busy,
    required this.onBack,
    required this.destinationName,
    required this.onDestination,
    required this.onClearDestination,
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
            child: _DestinationPill(
              label:
                  destinationName ??
                  AppCopy.t(
                    language,
                    ko: '목적지 또는 지역',
                    en: 'Destination or area',
                    fr: 'Destination ou région',
                  ),
              empty: destinationName == null,
              onTap: busy ? null : onDestination,
              onClear: onClearDestination,
            ),
          ),
          const SizedBox(width: 6),
          _LeanCircleButton(icon: Icons.gps_fixed_rounded, onTap: onRecenter),
        ],
      ),
    );
  }
}

class _DestinationPill extends StatelessWidget {
  final String label;
  final bool empty;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const _DestinationPill({
    required this.label,
    required this.empty,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 40,
        padding: const EdgeInsets.only(left: 11, right: 5),
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
          children: [
            Icon(
              Icons.search_rounded,
              size: 16,
              color: enabled ? AppColors.onPrimary : AppColors.textHint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w900,
                  color: empty
                      ? AppColors.onPrimary.withValues(alpha: 0.84)
                      : AppColors.onPrimary,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: AppCopy.cancel(
                  context.watch<SettingsService>().appLanguage,
                ),
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 17),
                color: AppColors.onPrimary,
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteChainBar extends StatelessWidget {
  final AppLanguage language;
  final int count;
  final double totalDistanceKm;
  final VoidCallback onCancel;
  final VoidCallback? onChain;

  const _RouteChainBar({
    required this.language,
    required this.count,
    required this.totalDistanceKm,
    required this.onCancel,
    required this.onChain,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _chainSummaryLabel(count, totalDistanceKm, language),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      size: 13,
                      weight: FontWeight.w900,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onChain,
                  icon: const Icon(Icons.route_rounded, size: 17),
                  label: Text(
                    onChain == null
                        ? _chainPickMoreLabel(language)
                        : _chainDriveLabel(language),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: onChain == null
                        ? AppColors.onPrimary.withValues(alpha: 0.58)
                        : AppColors.onPrimary,
                    textStyle: AppText.body(size: 12, weight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: AppCopy.cancel(language),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 19),
                  color: AppColors.onPrimary,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _chainBrowseHint(language),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.mono(
                size: 10,
                weight: FontWeight.w800,
                color: AppColors.onPrimary.withValues(alpha: 0.82),
              ),
            ),
          ],
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

class _LeanRouteTicket extends StatelessWidget {
  final RevvRoute route;
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onGo;
  final VoidCallback onDetails;
  final bool mapSelected;
  final bool chainMode;
  final int chainCount;
  final bool chainSelected;
  final VoidCallback onToggleChain;

  const _LeanRouteTicket({
    required this.route,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onGo,
    required this.onDetails,
    this.mapSelected = false,
    this.chainMode = false,
    this.chainCount = 0,
    this.chainSelected = false,
    required this.onToggleChain,
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
      onTap: chainMode ? onToggleChain : null,
      onLongPress: onToggleChain,
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
          color: AppColors.creamRaised,
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
                  lightColor: AppColors.creamRaised,
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
                              routeDisplayName(route, language: language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(
                                size: 18,
                                weight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            RouteDurationMeta(route: route, language: language),
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
                      if (chainMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            chainSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: chainSelected
                                ? AppColors.primaryContainer
                                : AppColors.stone,
                            size: 24,
                          ),
                        ),
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
                          child: _Metric(
                            label: metric.label,
                            value: metric.value,
                          ),
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
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      key: const Key('chain-toggle-button'),
                      onPressed: onToggleChain,
                      icon: Icon(
                        chainSelected
                            ? Icons.check_rounded
                            : Icons.add_road_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _chainToggleLabel(
                          language: language,
                          selected: chainSelected,
                          count: chainCount,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: chainSelected
                            ? AppColors.redSoft
                            : AppColors.surface.withValues(alpha: 0.72),
                        foregroundColor: AppColors.primaryContainer,
                        side: BorderSide(
                          color: AppColors.primaryContainer.withValues(
                            alpha: chainSelected ? 0.62 : 0.34,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: AppText.body(
                          size: 12,
                          weight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                            ),
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

class RouteDurationMeta extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const RouteDurationMeta({
    super.key,
    required this.route,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final segments = routeChainSegmentCount(route);
    final segmentLabel = segments > 1
        ? AppCopy.t(
            language,
            ko: '$segments개 코스 연결',
            en: '$segments linked routes',
            fr: '$segments routes reliées',
          )
        : AppCopy.t(
            language,
            ko: '단일 코스',
            en: 'Single route',
            fr: 'Route seule',
          );
    return Text(
      '${driveMinutesLabel(route, language)} · $segmentLabel',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.mono(
        size: 10,
        weight: FontWeight.w800,
        color: AppColors.primaryContainer,
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

class FinderFilterStrip extends StatelessWidget {
  final DriveBudget budget;
  final bool loopOnly;
  final ValueChanged<DriveBudget> onChanged;
  final ValueChanged<bool> onLoopOnlyChanged;

  const FinderFilterStrip({
    super.key,
    required this.budget,
    required this.loopOnly,
    required this.onChanged,
    required this.onLoopOnlyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final item in const [
            DriveBudget.short,
            DriveBudget.medium,
            DriveBudget.long,
          ]) ...[
            _BudgetChip(
              label: driveBudgetLabel(item, language),
              selected: budget == item,
              onTap: () => onChanged(item),
            ),
            const SizedBox(width: 8),
          ],
          _BudgetChip(
            label: AppCopy.t(
              language,
              ko: '루프만',
              en: 'Loops only',
              fr: 'Boucles',
            ),
            selected: loopOnly,
            onTap: () => onLoopOnlyChanged(!loopOnly),
          ),
        ],
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
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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

int _budgetMinutes(DriveBudget budget) {
  return switch (budget) {
    DriveBudget.any => 60,
    DriveBudget.short => 30,
    DriveBudget.medium => 60,
    DriveBudget.long => 120,
  };
}

String _finderSummary(
  List<RevvRoute> routes,
  String? destinationName,
  AppLanguage language,
) {
  final top = routes.isEmpty
      ? AppCopy.t(language, ko: '없음', en: 'none', fr: 'aucune')
      : routeDisplayName(routes.first, language: language);
  if (destinationName != null) {
    return AppCopy.t(
      language,
      ko: '$destinationName까지 루트 ${routes.length}개',
      en: '${routes.length} routes to $destinationName',
      fr: '${routes.length} routes vers $destinationName',
    );
  }
  return AppCopy.t(
    language,
    ko: '근처 루트 ${routes.length}개 · 오늘 추천: $top',
    en: '${routes.length} nearby routes · Today: $top',
    fr: '${routes.length} routes proches · Aujourd’hui : $top',
  );
}

List<String> _windingRouteIds(Iterable<DrivePlanOption> options) {
  final routeIds = <String>{};
  for (final option in options) {
    for (final leg in option.plan.legs) {
      if (leg.kind == DrivePlanLegKind.winding) {
        final id = leg.route?.id;
        if (id != null && id.isNotEmpty) routeIds.add(id);
      }
    }
  }
  return routeIds.toList();
}

List<String> _freeRoamRouteIds(Iterable<FreeRoamOption> options) {
  final routeIds = <String>{};
  for (final option in options) {
    for (final leg in option.plan.legs) {
      if (leg.kind == DrivePlanLegKind.winding) {
        final id = leg.route?.id;
        if (id != null && id.isNotEmpty) routeIds.add(id);
      }
    }
  }
  return routeIds.toList();
}

String driveMinutesLabel(RevvRoute route, AppLanguage language) {
  final minutes = estimatedDriveMinutes(route);
  return AppCopy.t(
    language,
    ko: '~$minutes분',
    en: '~$minutes min',
    fr: '~$minutes min',
  );
}

int routeChainSegmentCount(RevvRoute route) {
  if (!route.id.startsWith('combo:')) return 1;
  final count = route.id.split(':').where((part) => part.isNotEmpty).length - 1;
  return count.clamp(1, 3).toInt();
}

List<String> routeChainSegmentNames(RevvRoute route) {
  if (routeChainSegmentCount(route) <= 1) return const [];
  return route.name
      .split(' + ')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
}

String _chainDriveLabel(AppLanguage language) {
  return AppCopy.t(language, ko: '이어달리기', en: 'Chain drive', fr: 'Enchaîner');
}

String _chainPickMoreLabel(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '1개 더 고르세요',
    en: 'Pick one more',
    fr: 'Encore un',
  );
}

String _chainBrowseHint(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '◀▶로 다른 루트를 보고 추가하세요',
    en: 'Browse ◀▶ and add more',
    fr: 'Parcourez ◀▶ et ajoutez',
  );
}

String _chainSummaryLabel(
  int count,
  double totalDistanceKm,
  AppLanguage language,
) {
  return AppCopy.t(
    language,
    ko: '$count개 루트 · 총 ~${totalDistanceKm.round()}km',
    en: '$count routes · ~${totalDistanceKm.round()}km total',
    fr: '$count routes · ~${totalDistanceKm.round()}km au total',
  );
}

String _chainToggleLabel({
  required AppLanguage language,
  required bool selected,
  required int count,
}) {
  if (selected) {
    return AppCopy.t(
      language,
      ko: '추가됨 $count',
      en: 'Added $count',
      fr: 'Ajouté $count',
    );
  }
  return AppCopy.t(language, ko: '이어달리기 추가', en: 'Add to chain', fr: 'Ajouter');
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

String _cacheInlineStatus(RouteService service, AppLanguage language) {
  final count = service.mapVisualRoutes.length;
  return AppCopy.t(
    language,
    ko: '저장된 커브길 $count개를 먼저 표시하고 있어요.',
    en: 'Showing $count saved curvy roads first.',
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
