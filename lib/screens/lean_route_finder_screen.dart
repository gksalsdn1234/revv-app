import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/exploration_cell.dart';
import '../models/revv_route.dart';
import '../services/drive_planner_service.dart';
import '../services/drive_plan_navigation.dart';
import '../services/external_nav.dart';
import '../services/exploration_service.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../services/recommendation_log_service.dart';
import '../services/driven_routes_service.dart';
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
import '../widgets/copilot_start_sheet.dart';
import '../widgets/journey_sheet.dart';
import '../widgets/map_widget.dart';
import '../widgets/place_search_sheet.dart';
import '../widgets/revv_ui.dart';
import '../widgets/route_new_badge.dart';
import 'lean_drive_screen.dart';
import 'lean_route_detail_screen.dart';

enum _RouteLens { all, nearby, sweeper, tight, flow, loop }

enum _RouteMapMode { wide, balanced, close }

const bool _explorationFogEnabled = bool.fromEnvironment(
  'REVV_EXPLORATION_FOG',
);
const int _maxChainRoutes = 6;

List<ExplorationCell> buildExplorationFogCells(
  List<RevvRoute> routes,
  Set<String> exploredCellIds, {
  int limit = 800,
}) {
  if (limit <= 0) return const [];
  final cells = <String, ExplorationCell>{};
  for (final route in routes) {
    if (route.nodes.length < 2) continue;
    for (final id in ExplorationGrid.cellsForPath(route.nodes)) {
      if (exploredCellIds.contains(id) || cells.containsKey(id)) continue;
      cells[id] = ExplorationCell(
        id: id,
        bounds: ExplorationGrid.decodeBounds(id),
      );
      if (cells.length == limit) return cells.values.toList(growable: false);
    }
  }
  return cells.values.toList(growable: false);
}

class RouteClusterBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const RouteClusterBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  bool contains(LatLng point) {
    return point.lat >= south &&
        point.lat <= north &&
        point.lng >= west &&
        point.lng <= east;
  }
}

class RegionRouteCluster {
  final String id;
  final String name;
  final List<RevvRoute> routes;
  final LatLng center;
  final RouteClusterBounds bounds;

  const RegionRouteCluster({
    required this.id,
    required this.name,
    required this.routes,
    required this.center,
    required this.bounds,
  });

  RevvRoute get representative => routes.first;
}

List<RegionRouteCluster> buildRouteClusters(List<RevvRoute> routes) {
  final grouped = <String, List<RevvRoute>>{};
  for (final route in routes) {
    grouped.putIfAbsent(_routeClusterKey(route), () => []).add(route);
  }
  final clusters = grouped.entries.map((entry) {
    final ranked = _rankRoutesByFun(entry.value);
    final bounds = _boundsForRoutes(ranked);
    return RegionRouteCluster(
      id: entry.key,
      name: routeDisplayName(ranked.first),
      routes: ranked,
      center: bounds.center,
      bounds: bounds,
    );
  }).toList();
  clusters.sort((a, b) => b.routes.length.compareTo(a.routes.length));
  return clusters;
}

List<RevvRoute> todayRecommendedRoutes(
  List<RegionRouteCluster> clusters, {
  Set<String> exclude = const {},
}) {
  final rankedClusters = [...clusters]
    ..sort(
      (a, b) => _routeFunScore(
        b.representative,
      ).compareTo(_routeFunScore(a.representative)),
    );
  // 탐험 잔고: 이미 달린 대표 루트는 뒤로 — 전부 달렸으면 원래 순서 유지
  final fresh = rankedClusters
      .where((cluster) => !exclude.contains(cluster.representative.id))
      .toList();
  final driven = rankedClusters
      .where((cluster) => exclude.contains(cluster.representative.id))
      .toList();
  return [
    ...fresh,
    ...driven,
  ].take(3).map((cluster) => cluster.representative).toList(growable: false);
}

/// 정복 지도 잔광: 보이는 클러스터에서 달린 루트의 coarse 노드 (상한 30개).
List<List<LatLng>> _drivenGlowPolylines(
  List<RegionRouteCluster> clusters,
  DrivenRoutesService driven,
) {
  final parts = <List<LatLng>>[];
  for (final cluster in clusters) {
    for (final route in cluster.routes) {
      if (parts.length >= 30) return parts;
      if (driven.isDriven(route.id) && route.nodes.length >= 2) {
        parts.add(route.nodes);
      }
    }
  }
  return parts;
}

List<RegionRouteCluster> visibleRouteClusters(
  List<RegionRouteCluster> clusters,
  RouteClusterBounds bounds,
) {
  return clusters
      .where((cluster) => bounds.contains(cluster.center))
      .toList(growable: false);
}

String _routeClusterKey(RevvRoute route) {
  final geohash = route.geohash4.trim();
  if (geohash.isNotEmpty) return geohash;
  return '${route.centerPoint.lat.toStringAsFixed(1)},${route.centerPoint.lng.toStringAsFixed(1)}';
}

List<RevvRoute> _rankRoutesByFun(List<RevvRoute> routes) {
  return [...routes]
    ..sort((a, b) => _routeFunScore(b).compareTo(_routeFunScore(a)));
}

double _routeFunScore(RevvRoute route) {
  if (route.funScore > 0) return route.funScore;
  if (route.routeRankScore > 0) return route.routeRankScore;
  return route.windingScore;
}

RouteClusterBounds _boundsForRoutes(List<RevvRoute> routes) {
  var south = routes.first.centerPoint.lat;
  var north = routes.first.centerPoint.lat;
  var west = routes.first.centerPoint.lng;
  var east = routes.first.centerPoint.lng;
  for (final route in routes) {
    final point = route.centerPoint;
    if (point.lat < south) south = point.lat;
    if (point.lat > north) north = point.lat;
    if (point.lng < west) west = point.lng;
    if (point.lng > east) east = point.lng;
  }
  return RouteClusterBounds(south: south, west: west, north: north, east: east);
}

enum RouteFinderStateKind {
  temporaryLocationDenied,
  permanentlyLocationDenied,
  emptyRoutes,
  loadFailed,
  cachedRoutes,
}

/// 카메라가 마지막 검색 중심에서 이만큼 벗어나면 "이 지역에서 찾기"를 띄운다.
const double searchAreaOfferThresholdKm = 30.0;

bool shouldOfferSearchArea(LatLng? lastSearchCenter, LatLng? cameraCenter) {
  if (lastSearchCenter == null || cameraCenter == null) return false;
  return RevvRoute.haversineKm(lastSearchCenter, cameraCenter) >=
      searchAreaOfferThresholdKm;
}

class LeanRouteFinderScreen extends StatefulWidget {
  final DrivePlannerService? planner;
  final PlaceSearchService? placeSearch;
  final RecommendationLogService? recommendationLogService;
  final String? initialRouteId;
  final bool showBackButton;

  const LeanRouteFinderScreen({
    super.key,
    this.planner,
    this.placeSearch,
    this.recommendationLogService,
    this.initialRouteId,
    this.showBackButton = true,
  });

  @override
  State<LeanRouteFinderScreen> createState() => _LeanRouteFinderScreenState();
}

class _LeanRouteFinderScreenState extends State<LeanRouteFinderScreen> {
  int _recenterSignal = 0;
  int _mapFocusSignal = 0;
  List<LatLng> _mapFocusPoints = const [];
  double _mapFocusMaxZoom = 14.0;
  bool _programmaticFieldFocusPending = false;
  _RouteLens _lens = _RouteLens.all;
  LatLng? _mapCenterPoint;
  LatLng? _lastSearchCenter;
  bool _searchAreaShown = false;
  String? _localStatusMessage;
  double _mapZoom = 11.0;
  final bool _curveRoadView = false;
  bool _coverageRequestInProgress = false;
  DriveBudget _driveBudget = DriveBudget.any;
  LatLng? _coverageRequestPoint;
  RevvRoute? _previewRoute;
  final Map<String, RevvRoute> _chainSelection = {};
  List<RevvRoute> _plannedChainRoutes = const [];
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
  int _destinationPlanGeneration = 0;
  String? _journeyMode;
  String? _lastShownSignature;
  bool _initialRouteFocused = false;
  Timer? _cameraDebounce;
  int? _mapTapPointer;
  Offset? _mapTapOrigin;
  bool _mapTapMoved = false;
  bool _routeListOpen = false;

  bool get _chainMode => _chainSelection.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_searchCurrentLocation());
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
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
    await _fetchAtPoint(point, forceRefresh: true);
  }

  Future<void> _searchThisArea() async {
    setState(() {
      _destinationName = null;
      _searchAreaShown = false;
    });
    await _searchHere();
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

  Future<void> _fetchAtPoint(
    LatLng point, {
    bool forceRefresh = false,
    int? destinationGeneration,
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
        _localStatusMessage = null;
        _mapCenterPoint = point;
        _mapZoom = 11.0;
        _coverageRequestPoint = point;
        _lastSearchCenter = point;
        _searchAreaShown = false;
      });
      return;
    }
    await routes.prefetchRouteField(
      point.lat,
      point.lng,
      forceRefresh: forceRefresh,
    );
    if (!mounted ||
        (destinationGeneration != null &&
            destinationGeneration != _destinationPlanGeneration)) {
      return;
    }
    setState(() {
      _lens = _RouteLens.all;
      _localStatusMessage = null;
      _coverageRequestPoint = null;
      _lastSearchCenter = point;
      _searchAreaShown = false;
    });
    unawaited(routes.prefetchRouteOverview(point));
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

  Future<void> _openDestinationSearch() async {
    _dismissRoutePreview();
    setState(() {
      _destinationPlanGeneration++;
      _planning = false;
    });
    final language = context.read<SettingsService>().appLanguage;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaceSearchSheet(
        language: language,
        service: _placeSearch,
        proximity:
            _mapCenterPoint ??
            _lastSearchCenter ??
            const LatLng(45.5017, -73.5673),
        allowMapPin: false,
      ),
    );
    if (!mounted || result is! PlaceResult) return;
    final browseArea = result.isArea;
    late final int selectionGeneration;
    setState(() {
      selectionGeneration = ++_destinationPlanGeneration;
      _planning = false;
      _destination = browseArea ? null : result.point;
      _destinationName = result.name;
      _mapCenterPoint = result.point;
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
      _selectedKind = DrivePlanOptionKind.standard;
      _selectedFreeRoamIndex = 0;
    });
    await _fetchAtPoint(
      result.point,
      forceRefresh: true,
      destinationGeneration: selectionGeneration,
    );
    if (!mounted ||
        selectionGeneration != _destinationPlanGeneration ||
        !_sameDestination(
          result.point,
          browseArea ? _mapCenterPoint : _destination,
        )) {
      return;
    }
    final fieldRoutes = context.read<RouteService>().mapVisualRoutes.where(
      (route) =>
          RevvRoute.haversineKm(result.point, route.centerPoint) <=
          RouteService.routeFieldRadiusKm,
    );
    setState(() {
      _mapCenterPoint = result.point;
      _mapZoom = routeOverviewZoomThreshold;
      _mapFocusPoints = [
        result.point,
        for (final route in fieldRoutes) route.centerPoint,
      ];
      _mapFocusMaxZoom = 10.0;
      _programmaticFieldFocusPending = true;
      _mapFocusSignal++;
    });
    if (!browseArea) {
      unawaited(_buildDestinationJourney());
    }
  }

  void _clearDestination() {
    setState(() {
      _destinationPlanGeneration++;
      _planning = false;
      _destination = null;
      _destinationName = null;
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
      _selectedKind = DrivePlanOptionKind.standard;
      _selectedFreeRoamIndex = 0;
      if (_mapFocusPoints.isNotEmpty) {
        _mapCenterPoint = _lastSearchCenter;
        _mapFocusMaxZoom = 10.0;
        _programmaticFieldFocusPending = true;
        _mapFocusSignal++;
      }
    });
  }

  Future<void> _buildDestinationJourney() async {
    final destination = _destination;
    if (destination == null) return;
    final generation = ++_destinationPlanGeneration;
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _journeyMode = 'destination';
      _options = null;
      _freeRoamOptions = null;
      _localStatusMessage = null;
    });
    try {
      final origin = await _resolveSearchPoint();
      if (!mounted ||
          origin == null ||
          generation != _destinationPlanGeneration ||
          !_sameDestination(destination, _destination)) {
        return;
      }
      setState(() => _journeyOrigin = origin);
      final options = await _planner.buildPlanOptions(
        DrivePlanRequest(
          origin: origin,
          destination: destination,
          windingBudgetMinutes: _budgetMinutes(_driveBudget),
        ),
      );
      if (!mounted ||
          generation != _destinationPlanGeneration ||
          !_sameDestination(destination, _destination)) {
        return;
      }
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
    } on TimeoutException {
      if (!mounted || generation != _destinationPlanGeneration) return;
      setState(() {
        _localStatusMessage = AppCopy.t(
          language,
          ko: '여정 계산이 오래 걸려 중단했어요. 다시 시도해 주세요.',
          en: 'Planning took too long. Try again.',
          fr: 'Le calcul a pris trop de temps. Réessayez.',
        );
      });
    } catch (_) {
      if (!mounted || generation != _destinationPlanGeneration) return;
      setState(() {
        _localStatusMessage = AppCopy.t(
          language,
          ko: '여정을 불러오지 못했어요. 네트워크를 확인해 주세요.',
          en: 'Could not load the journey. Check your network connection.',
          fr: 'Impossible de charger le trajet. Vérifiez votre connexion réseau.',
        );
      });
    } finally {
      if (mounted && generation == _destinationPlanGeneration) {
        setState(() => _planning = false);
      }
    }
  }

  bool _sameDestination(LatLng expected, LatLng? current) =>
      current != null &&
      expected.lat == current.lat &&
      expected.lng == current.lng;

  Future<void> _buildFreeRoamJourney() async {
    if (_planning) return;
    _dismissRoutePreview();
    if (_chainSelection.isNotEmpty) setState(_chainSelection.clear);
    final generation = ++_destinationPlanGeneration;
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _journeyMode = 'free';
      _options = null;
      _freeRoamOptions = null;
      _selectedFreeRoamIndex = 0;
      _localStatusMessage = null;
    });
    try {
      final origin = await _resolveSearchPoint();
      if (!mounted ||
          origin == null ||
          generation != _destinationPlanGeneration) {
        return;
      }
      setState(() => _journeyOrigin = origin);
      final options = await _planner.buildFreeRoamOptions(
        origin: origin,
        totalBudgetMinutes: _budgetMinutes(_driveBudget),
      );
      if (!mounted || generation != _destinationPlanGeneration) return;
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
    } on TimeoutException {
      if (!mounted || generation != _destinationPlanGeneration) return;
      setState(() {
        _localStatusMessage = AppCopy.t(
          language,
          ko: '여정 계산이 오래 걸려 중단했어요. 다시 시도해 주세요.',
          en: 'Planning took too long. Try again.',
          fr: 'Le calcul a pris trop de temps. Réessayez.',
        );
      });
    } catch (_) {
      if (!mounted || generation != _destinationPlanGeneration) return;
      setState(() {
        _localStatusMessage = AppCopy.t(
          language,
          ko: '여정을 불러오지 못했어요. 네트워크를 확인해 주세요.',
          en: 'Could not load the journey. Check your network connection.',
          fr: 'Impossible de charger le trajet. Vérifiez votre connexion réseau.',
        );
      });
    } finally {
      if (mounted && generation == _destinationPlanGeneration) {
        setState(() => _planning = false);
      }
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
    });
  }

  void _selectIndex(List<RevvRoute> routes, int nextIndex) {
    if (routes.isEmpty) return;
    final clamped = nextIndex.clamp(0, routes.length - 1);
    setState(() {
      _mapCenterPoint = routes[clamped].centerPoint;
      _mapFocusPoints = const [];
      _mapFocusMaxZoom = 14.0;
      _mapFocusSignal++;
    });
    context.read<RouteService>().selectRoute(routes[clamped]);
  }

  void _focusInitialRoute(List<RevvRoute> routes) {
    final routeId = widget.initialRouteId;
    if (_initialRouteFocused || routeId == null || routes.isEmpty) return;
    final index = routes.indexWhere((route) => route.id == routeId);
    if (index < 0) return;
    _initialRouteFocused = true;
    _selectIndex(routes, index);
  }

  void _toggleChainRoute(RevvRoute route) {
    if (_planning) return;
    if (!_chainSelection.containsKey(route.id) &&
        _chainSelection.length >= _maxChainRoutes) {
      final language = context.read<SettingsService>().appLanguage;
      setState(() => _localStatusMessage = _chainLimitLabel(language));
      return;
    }
    setState(() {
      if (_chainSelection.containsKey(route.id)) {
        _chainSelection.remove(route.id);
      } else {
        _chainSelection[route.id] = route;
      }
    });
  }

  void _clearChainSelection() {
    if (_planning) return;
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
    if (_planning || _chainSelection.length < 2) return;
    _dismissRoutePreview();
    final generation = ++_destinationPlanGeneration;
    final selectedRoutes = _chainSelection.values.toList();
    final firstRoute = selectedRoutes.first;
    final fallbackOrigin = firstRoute.nodes.isEmpty
        ? firstRoute.centerPoint
        : firstRoute.nodes.first;
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _journeyMode = 'chain';
      _options = null;
      _freeRoamOptions = null;
      _plannedChainRoutes = const [];
      _localStatusMessage = null;
    });
    final location = context.read<LocationService>();
    final origin =
        await location.ensureLiveLocation(
          timeout: const Duration(seconds: 3),
        ) ??
        location.bestKnownLatLng ??
        fallbackOrigin;
    if (!mounted || generation != _destinationPlanGeneration) return;
    setState(() => _journeyOrigin = origin);
    DrivePlan plan;
    try {
      plan = await _planner.buildPlanFromRoutes(
        origin: origin,
        routes: selectedRoutes,
      );
    } catch (_) {
      if (!mounted || generation != _destinationPlanGeneration) return;
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
    if (!mounted || generation != _destinationPlanGeneration) return;
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
      _plannedChainRoutes = List.unmodifiable(selectedRoutes);
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

  void _startSelectedChain() {
    final plan = _plan;
    final selectedRoutes = _plannedChainRoutes;
    if (plan == null ||
        plan.usesApproximateTransit ||
        selectedRoutes.length < 2) {
      return;
    }
    final language = context.read<SettingsService>().appLanguage;
    final route = buildDrivePlanRoute(
      plan: plan,
      windingRoutes: selectedRoutes,
      name: AppCopy.t(
        language,
        ko: '루트 체인 · ${selectedRoutes.length}개',
        en: 'Route chain · ${selectedRoutes.length}',
        fr: 'Chaîne de routes · ${selectedRoutes.length}',
      ),
    );
    unawaited(
      _recommendationLog.logChosen(
        mode: 'chain',
        routeId: selectedRoutes.first.id,
        optionKind: _selectedKind.key,
        origin: _journeyOrigin,
        budgetMinutes: _selectedOptionBudget,
      ),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(route: route, drivePlan: plan),
      ),
    );
  }

  Future<void> _openExternalNavigation() async {
    final plan = _plan;
    final origin = _journeyOrigin;
    final destination = _planDestination;
    if (plan == null || origin == null || destination == null) return;
    final language = context.read<SettingsService>().appLanguage;
    final waypoints = selectHandoffWaypoints(
      legs: plan.legs,
      origin: origin,
      destination: destination,
    );
    final mapsUri = buildGoogleMapsDirectionsUri(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );
    final launched = await launchExternalNavigationWithFallback(
      primaryUri: mapsUri,
      launcher: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
    );
  }

  void _backToList() {
    final clearChainDestination = _journeyMode == 'chain';
    setState(() {
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
      _plannedChainRoutes = const [];
      _selectedFreeRoamIndex = 0;
      _selectedKind = DrivePlanOptionKind.standard;
      if (clearChainDestination) {
        _destination = null;
        _destinationName = null;
      }
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
    });
  }

  void _setDriveBudget(DriveBudget budget) {
    setState(() {
      _driveBudget = budget;
      _journeyMode = null;
      _options = null;
      _freeRoamOptions = null;
    });
  }

  void _showRouteDetails(RevvRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeanRouteDetailScreen(route: route)),
    );
  }

  void _showRoutePreview(RevvRoute route) {
    setState(() {
      _previewRoute = route;
      _mapCenterPoint = route.centerPoint;
      _mapFocusPoints = const [];
      _mapFocusMaxZoom = 14.0;
      _mapFocusSignal++;
      _searchAreaShown = false;
    });
    context.read<RouteService>().selectRoute(route);
  }

  Future<void> _startPreviewDrive(RevvRoute route) async {
    final startChoice = await showCopilotStartSheet(context, route: route);
    if (!mounted || startChoice == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(
          route: route,
          simulated: startChoice == CopilotStartChoice.simulate,
        ),
      ),
    );
  }

  void _dismissRoutePreview() {
    if (_previewRoute == null) return;
    setState(() => _previewRoute = null);
    context.read<RouteService>().deselectRoute();
  }

  void _handleMapPointerDown(PointerDownEvent event) {
    if (_previewRoute == null || _mapTapPointer != null) return;
    _mapTapPointer = event.pointer;
    _mapTapOrigin = event.position;
    _mapTapMoved = false;
  }

  void _handleMapPointerMove(PointerMoveEvent event) {
    if (event.pointer != _mapTapPointer || _mapTapOrigin == null) return;
    if ((event.position - _mapTapOrigin!).distance > 8) _mapTapMoved = true;
  }

  void _handleMapPointerUp(PointerUpEvent event) {
    if (event.pointer != _mapTapPointer) return;
    final shouldDismiss = !_mapTapMoved;
    _mapTapPointer = null;
    _mapTapOrigin = null;
    _mapTapMoved = false;
    if (shouldDismiss) _dismissRoutePreview();
  }

  void _handleMapPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _mapTapPointer) return;
    _mapTapPointer = null;
    _mapTapOrigin = null;
    _mapTapMoved = false;
  }

  Future<void> _openRouteList(
    List<RevvRoute> routes,
    AppLanguage language,
    Set<String> drivenIds,
  ) async {
    setState(() => _routeListOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _RouteListSheet(
        routes: routes,
        language: language,
        drivenIds: drivenIds,
        chainSelection: _chainSelection,
        onRouteTap: (route) {
          Navigator.pop(sheetContext);
          _showRoutePreview(route);
        },
        onToggleChain: _toggleChainRoute,
        onClearChain: _clearChainSelection,
        onStartChain: () {
          Navigator.pop(sheetContext);
          unawaited(_startChainDrive());
        },
        onFreeRoam: () {
          Navigator.pop(sheetContext);
          unawaited(_buildFreeRoamJourney());
        },
      ),
    );
    if (mounted) setState(() => _routeListOpen = false);
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
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final center = _mapCenterPoint;
      final routeService = context.read<RouteService>();
      if (isRouteOverviewZoom(_mapZoom) && center != null) {
        unawaited(routeService.prefetchRouteOverview(center));
      }
      final suppressSearchArea = _programmaticFieldFocusPending;
      if (suppressSearchArea) {
        _programmaticFieldFocusPending = false;
        _lastSearchCenter = center;
      }
      final offerSearchArea =
          !suppressSearchArea &&
          _destination == null &&
          _previewRoute == null &&
          shouldOfferSearchArea(_lastSearchCenter, _mapCenterPoint);
      if (shouldRefreshMarkers || offerSearchArea != _searchAreaShown) {
        setState(() => _searchAreaShown = offerSearchArea);
      }
    });
  }

  void _handleRouteLineTap(String routeId) {
    final service = context.read<RouteService>();
    for (final route in [...service.routes, ...service.mapVisualRoutes]) {
      if (route.id == routeId) {
        if (_destination == null && _journeyMode == null) {
          _showRoutePreview(route);
        } else {
          _showRouteDetails(route);
        }
        return;
      }
    }
  }

  Future<void> _openLocationSettings() async {
    await openAppSettings();
  }

  RouteClusterBounds _clusterBoundsForViewport(LatLng? center, double zoom) {
    if (center == null || zoom < 9.5) {
      return const RouteClusterBounds(
        south: -90,
        west: -180,
        north: 90,
        east: 180,
      );
    }
    final radiusKm = switch (_mapModeForZoom(zoom)) {
      _RouteMapMode.wide => 180.0,
      _RouteMapMode.balanced => 95.0,
      _RouteMapMode.close => 35.0,
    };
    final latDelta = radiusKm / 111.32;
    final lngDelta =
        radiusKm /
        (111.32 * math.cos(center.lat * math.pi / 180).abs().clamp(0.1, 1.0));
    return RouteClusterBounds(
      south: center.lat - latDelta,
      west: center.lng - lngDelta,
      north: center.lat + latDelta,
      east: center.lng + lngDelta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RouteService>();
    final location = context.watch<LocationService>();
    final routes = service.routes;
    final loopFilteredRoutes = routes;
    final lensRoutes = _rankRoutes(_filterRoutes(loopFilteredRoutes, _lens));
    final visibleRoutes = routesForDriveBudget(
      lensRoutes,
      budget: _driveBudget,
    );
    if (!_initialRouteFocused && widget.initialRouteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusInitialRoute(visibleRoutes);
      });
    }
    final mapSourceRoutes = _driveBudget == DriveBudget.any
        ? service.mapVisualRoutes
        : visibleRoutes;
    final noDestination = _destination == null;
    final clusterPoolSource = service.mapVisualRoutes.isNotEmpty
        ? service.mapVisualRoutes
        : routes;
    final clusterPool = routesForDriveBudget(
      _rankRoutes(_filterRoutes(clusterPoolSource, _lens)),
      budget: _driveBudget,
    );
    final clusters = buildRouteClusters(clusterPool);
    final clusterBounds = _clusterBoundsForViewport(_mapCenterPoint, _mapZoom);
    final drivenService = context.watch<DrivenRoutesService>();
    final visibleClusters = visibleRouteClusters(clusters, clusterBounds);
    final mapDisplayRoutes = _routesForViewport(
      mapSourceRoutes.isNotEmpty ? mapSourceRoutes : visibleRoutes,
      _mapCenterPoint,
      _mapZoom,
    );
    ExplorationService? exploration;
    if (_explorationFogEnabled) {
      try {
        exploration = context.watch<ExplorationService>();
      } on ProviderNotFoundException {
        exploration = null;
      }
    }
    final plan = _plan;
    final showingJourney = _journeyMode != null && plan != null;
    final explorationFogCells =
        exploration != null &&
            !showingJourney &&
            !service.isLoading &&
            _coverageRequestPoint == null
        ? buildExplorationFogCells(
            mapDisplayRoutes,
            exploration.exploredCellIds,
          )
        : const <ExplorationCell>[];
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
    final newRouteCount = mapDisplayRoutes
        .where((route) => route.isNewlyGeneratedAt(DateTime.now()))
        .length;
    final settings = context.watch<SettingsService>();
    final coverageGrid = _coverageRequestPoint == null
        ? null
        : regionRequestGridFor(_coverageRequestPoint!);
    final coverageRequested =
        coverageGrid != null &&
        settings.hasRequestedRegion(coverageGrid.gridKey);
    final localStatus = _localStatusMessage;
    final cacheStatus = service.routeFieldFromCache && service.isLoading
        ? _cacheInlineStatus(service, language)
        : null;
    final serviceStatus =
        _routeStatusNeedsAttention(service.routeDataStatusTitle)
        ? routeFinderStatusBodyFor(service.routeDataStatusTitle, language)
        : null;
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
    final showStatusToast =
        status != null &&
        status.isNotEmpty &&
        (visibleRoutes.isNotEmpty || coverageGrid != null || showingJourney);
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
            const Positioned.fill(child: _FinderColdStartBackground()),
            Positioned.fill(
              child: Listener(
                key: const Key('route-map-interaction-surface'),
                behavior: HitTestBehavior.translucent,
                onPointerDown: showingJourney ? null : _handleMapPointerDown,
                onPointerMove: showingJourney ? null : _handleMapPointerMove,
                onPointerUp: showingJourney ? null : _handleMapPointerUp,
                onPointerCancel: showingJourney
                    ? null
                    : _handleMapPointerCancel,
                child: MapWidget(
                  navPolylines: showingJourney ? _transitPolylines : null,
                  routePolyline: showingJourney ? null : _previewRoute?.nodes,
                  routePolylines: showingJourney ? _windingPolylines : null,
                  curveHeatmap: !showingJourney,
                  planMarkers: showingJourney ? _planMarkers : null,
                  clusterMarkers: const [],
                  candidatePolylines: showingJourney
                      ? const []
                      : [for (final route in mapDisplayRoutes) route.nodes],
                  drivenPolylines: showingJourney
                      ? null
                      : _drivenGlowPolylines(visibleClusters, drivenService),
                  curveHeatmapPolylines: const [],
                  difficultyLines: showingJourney
                      ? const []
                      : _difficultyLines(mapDisplayRoutes, null),
                  explorationFogCells: explorationFogCells,
                  strongCurveFieldHeatmap: _curveRoadView,
                  routeFocusMode: false,
                  recenterSignal: _recenterSignal,
                  cameraTarget: _mapCenterPoint,
                  cameraTargetSignal: _mapFocusSignal,
                  cameraTargetPoints: _mapFocusPoints,
                  cameraTargetMaxZoom: _mapFocusMaxZoom,
                  onCameraViewportChanged: _handleCameraViewportChanged,
                  onRouteLineTap: _handleRouteLineTap,
                  onMapTap: _dismissRoutePreview,
                ),
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
                      onBack: widget.showBackButton
                          ? () => Navigator.pop(context)
                          : null,
                      destinationName: _destinationName,
                      onDestination: _openDestinationSearch,
                      onClearDestination: _destinationName == null
                          ? null
                          : _clearDestination,
                      onRecenter: () => setState(() => _recenterSignal++),
                    ),
                    if (!showingJourney && newRouteCount > 0) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: NewRouteMapLegend(
                          count: newRouteCount,
                          language: language,
                        ),
                      ),
                    ],
                    // 필터 스트립 제거 (민우 2026-07-10): 지도는 셀렉터에만
                    // 집중한다. 예산은 여정 시트의 옵션 칩이 담당.
                    if (!showingJourney && _searchAreaShown) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _SearchAreaPill(
                          key: const ValueKey('finder-search-area-button'),
                          language: language,
                          onTap: () => unawaited(_searchThisArea()),
                        ),
                      ),
                    ],
                    if (_chainMode && !_routeListOpen && !showingJourney) ...[
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
            if (showStatusToast)
              Positioned(
                top:
                    MediaQuery.paddingOf(context).top +
                    (_chainMode && !_routeListOpen && !showingJourney
                        ? 202 + (_searchAreaShown ? 52 : 0)
                        : 124),
                left: 24,
                right: 24,
                child: KeyedSubtree(
                  key: const Key('finder-status-toast'),
                  child: _LeanToast(message: status, busy: service.isLoading),
                ),
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
                          onBrowseMontreal: _searchHere,
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
                      chainMode: _journeyMode == 'chain',
                      canStart:
                          _firstWindingRoute != null &&
                          (_journeyMode != 'chain' ||
                              !plan.usesApproximateTransit),
                      onBack: _backToList,
                      onSearchDestination: _openDestinationSearch,
                      onSelectedOption: (kind) =>
                          setState(() => _selectedKind = kind),
                      onSelectedFreeRoam: (index) =>
                          setState(() => _selectedFreeRoamIndex = index),
                      onStart: _journeyMode == 'chain'
                          ? _startSelectedChain
                          : _startFirstWinding,
                      onNavigate: _openExternalNavigation,
                    )
                  : noDestination
                  ? visibleRoutes.isEmpty
                        ? Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                14,
                                0,
                                14,
                                MediaQuery.paddingOf(context).bottom + 14,
                              ),
                              child: _LeanEmptyTicket(
                                title: stateKind == null
                                    ? emptyTitle
                                    : routeFinderStateTitle(
                                        stateKind,
                                        language,
                                      ),
                                body: stateKind == null
                                    ? emptyBody
                                    : routeFinderStateBody(stateKind, language),
                                actionLabel: stateKind == null
                                    ? AppCopy.t(
                                        language,
                                        ko: '다시 찾기',
                                        en: 'Retry',
                                        fr: 'Réessayer',
                                      )
                                    : routeFinderStateActionLabel(
                                        stateKind,
                                        language,
                                      ),
                                actionIcon: stateKind == null
                                    ? Icons.refresh_rounded
                                    : routeFinderStateActionIcon(stateKind),
                                onAction: stateKind == null
                                    ? _searchHere
                                    : switch (stateKind) {
                                        RouteFinderStateKind
                                            .temporaryLocationDenied =>
                                          _searchCurrentLocation,
                                        RouteFinderStateKind
                                            .permanentlyLocationDenied =>
                                          _openLocationSettings,
                                        RouteFinderStateKind.emptyRoutes =>
                                          _searchHere,
                                        RouteFinderStateKind.loadFailed =>
                                          _searchHere,
                                        RouteFinderStateKind.cachedRoutes =>
                                          _searchHere,
                                      },
                              ),
                            ),
                          )
                        : _previewRoute != null
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    MediaQuery.paddingOf(context).bottom + 18,
                              ),
                              child: FilledButton.icon(
                                key: const Key('route-list-button'),
                                onPressed: () => _openRouteList(
                                  visibleRoutes,
                                  language,
                                  drivenService.drivenRouteIds,
                                ),
                                icon: const Icon(
                                  Icons.format_list_bulleted_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  AppCopy.t(
                                    language,
                                    ko: '루트 목록',
                                    en: 'Routes',
                                    fr: 'Routes',
                                  ),
                                ),
                              ),
                            ),
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
                      emptyActionLabel: stateKind != null
                          ? routeFinderStateActionLabel(stateKind, language)
                          : AppCopy.t(
                              language,
                              ko: '다시 찾기',
                              en: 'Retry',
                              fr: 'Réessayer',
                            ),
                      emptyActionIcon: stateKind != null
                          ? routeFinderStateActionIcon(stateKind)
                          : Icons.refresh_rounded,
                      onEmptyAction: stateKind != null
                          ? switch (stateKind) {
                              RouteFinderStateKind.temporaryLocationDenied =>
                                _searchCurrentLocation,
                              RouteFinderStateKind.permanentlyLocationDenied =>
                                _openLocationSettings,
                              RouteFinderStateKind.emptyRoutes => _searchHere,
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
                      chainSelection: _chainSelection,
                      onRouteTap: _showRouteDetails,
                      onToggleChain: _toggleChainRoute,
                    ),
            ),
            if (_previewRoute != null && noDestination && !showingJourney)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    0,
                    14,
                    MediaQuery.paddingOf(context).bottom + 58,
                  ),
                  child: _RoutePreviewCard(
                    route: _previewRoute!,
                    language: language,
                    driven: drivenService.isDriven(_previewRoute!.id),
                    chainSelected: _chainSelection.containsKey(
                      _previewRoute!.id,
                    ),
                    onDetails: () => _showRouteDetails(_previewRoute!),
                    onStart: () => _startPreviewDrive(_previewRoute!),
                    onToggleChain: () => _toggleChainRoute(_previewRoute!),
                    onDismiss: _dismissRoutePreview,
                  ),
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

class _RoutePreviewCard extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;
  final bool driven;
  final bool chainSelected;
  final VoidCallback onDetails;
  final VoidCallback onStart;
  final VoidCallback onToggleChain;
  final VoidCallback onDismiss;

  const _RoutePreviewCard({
    required this.route,
    required this.language,
    required this.driven,
    required this.chainSelected,
    required this.onDetails,
    required this.onStart,
    required this.onToggleChain,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('route-preview-card'),
      color: AppColors.surfaceDim,
      elevation: 8,
      shadowColor: AppColors.surfaceLowest,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onDetails,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (driven) ...[
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 15,
                                  color: AppColors.red,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  routeDisplayName(route, language: language),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(
                                    size: 16,
                                    weight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              RouteNewBadge(route: route, language: language),
                            ],
                          ),
                          const SizedBox(height: 5),
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
                          const SizedBox(height: 8),
                          Text(
                            AppCopy.t(
                              language,
                              ko: '상세',
                              en: 'Details',
                              fr: 'Détails',
                            ),
                            style: AppText.label(
                              size: 12,
                              weight: FontWeight.w800,
                              color: AppColors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('preview-chain-toggle-${route.id}'),
                  tooltip: chainSelected
                      ? AppCopy.t(
                          language,
                          ko: '이어달리기에서 빼기',
                          en: 'Remove from chain',
                          fr: 'Retirer de l’enchaînement',
                        )
                      : AppCopy.t(
                          language,
                          ko: '이어달리기 추가',
                          en: 'Add to chain',
                          fr: 'Ajouter à l’enchaînement',
                        ),
                  onPressed: onToggleChain,
                  icon: Icon(
                    chainSelected ? Icons.check_rounded : Icons.add_rounded,
                    color: chainSelected
                        ? AppColors.success
                        : AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  key: const ValueKey('preview-dismiss'),
                  tooltip: AppCopy.t(
                    language,
                    ko: '미리보기 닫기',
                    en: 'Close preview',
                    fr: 'Fermer l’aperçu',
                  ),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: ValueKey('preview-start-drive-${route.id}'),
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  AppCopy.t(
                    language,
                    ko: '주행 시작',
                    en: 'Start drive',
                    fr: 'Démarrer',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteListSheet extends StatefulWidget {
  final List<RevvRoute> routes;
  final AppLanguage language;
  final Set<String> drivenIds;
  final Map<String, RevvRoute> chainSelection;
  final ValueChanged<RevvRoute> onRouteTap;
  final ValueChanged<RevvRoute> onToggleChain;
  final VoidCallback onClearChain;
  final VoidCallback onStartChain;
  final VoidCallback onFreeRoam;

  const _RouteListSheet({
    required this.routes,
    required this.language,
    required this.drivenIds,
    required this.chainSelection,
    required this.onRouteTap,
    required this.onToggleChain,
    required this.onClearChain,
    required this.onStartChain,
    required this.onFreeRoam,
  });

  @override
  State<_RouteListSheet> createState() => _RouteListSheetState();
}

class _RouteListSheetState extends State<_RouteListSheet> {
  late final Set<String> _selectedIds = widget.chainSelection.keys.toSet();

  void _toggle(RevvRoute route) {
    if (!_selectedIds.contains(route.id) &&
        _selectedIds.length >= _maxChainRoutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_chainLimitLabel(widget.language))),
      );
      return;
    }
    widget.onToggleChain(route);
    setState(() {
      if (!_selectedIds.add(route.id)) _selectedIds.remove(route.id);
    });
  }

  void _clearChain() {
    widget.onClearChain();
    setState(_selectedIds.clear);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: DecoratedBox(
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
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppCopy.t(
                          widget.language,
                          ko: '루트 선택',
                          en: 'Choose a route',
                          fr: 'Choisir une route',
                        ),
                        style: AppText.body(
                          size: 20,
                          weight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppCopy.cancel(widget.language),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
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
                  itemCount: widget.routes.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 20,
                    color: AppColors.outlineVariant.withValues(alpha: 0.18),
                  ),
                  itemBuilder: (context, index) {
                    final route = widget.routes[index];
                    final selected = _selectedIds.contains(route.id);
                    return _RouteListRow(
                      route: route,
                      language: widget.language,
                      driven: widget.drivenIds.contains(route.id),
                      chainSelected: selected,
                      onTap: () => widget.onRouteTap(route),
                      onToggleChain: () => _toggle(route),
                    );
                  },
                ),
              ),
              if (_selectedIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: OutlinedButton.icon(
                    key: const Key('finder-free-roam-button'),
                    onPressed: widget.onFreeRoam,
                    icon: const Icon(Icons.explore_rounded, size: 18),
                    label: Text(
                      AppCopy.t(
                        widget.language,
                        ko: '그냥 추천',
                        en: 'Surprise me',
                        fr: 'Suggestion',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                )
              else
                _RouteListChainFooter(
                  language: widget.language,
                  count: _selectedIds.length,
                  totalDistanceKm: widget.routes
                      .where((route) => _selectedIds.contains(route.id))
                      .fold(0, (total, route) => total + route.distanceKm),
                  onClear: _clearChain,
                  onStart: _selectedIds.length >= 2
                      ? widget.onStartChain
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteListChainFooter extends StatelessWidget {
  final AppLanguage language;
  final int count;
  final double totalDistanceKm;
  final VoidCallback onClear;
  final VoidCallback? onStart;

  const _RouteListChainFooter({
    required this.language,
    required this.count,
    required this.totalDistanceKm,
    required this.onClear,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _chainSummaryLabel(count, totalDistanceKm, language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  onStart == null
                      ? _chainPickMoreLabel(language)
                      : AppCopy.t(
                          language,
                          ko: '선택한 순서대로 연결해요',
                          en: 'Connected in selection order',
                          fr: 'Reliées dans l’ordre choisi',
                        ),
                  maxLines: 1,
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
          TextButton(
            key: const Key('finder-chain-clear-button'),
            onPressed: onClear,
            child: Text(
              AppCopy.t(language, ko: '선택 초기화', en: 'Clear', fr: 'Effacer'),
            ),
          ),
          if (onStart != null)
            FilledButton.icon(
              key: const Key('finder-chain-start-button'),
              onPressed: onStart,
              icon: const Icon(Icons.route_rounded, size: 17),
              label: Text(_chainDriveLabel(language)),
            ),
        ],
      ),
    );
  }
}

class _RouteListRow extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;
  final bool driven;
  final bool chainSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleChain;

  const _RouteListRow({
    required this.route,
    required this.language,
    required this.driven,
    required this.chainSelected,
    required this.onTap,
    required this.onToggleChain,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('route-list-row-${route.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (driven) ...[
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: AppColors.red,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          routeDisplayName(route, language: language),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 15,
                            weight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RouteNewBadge(route: route, language: language),
                    ],
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
            IconButton(
              key: ValueKey('chain-toggle-${route.id}'),
              tooltip: chainSelected
                  ? AppCopy.t(
                      language,
                      ko: '이어달리기에서 빼기',
                      en: 'Remove from chain',
                      fr: 'Retirer de l’enchaînement',
                    )
                  : AppCopy.t(
                      language,
                      ko: '이어달리기 추가',
                      en: 'Add to chain',
                      fr: 'Ajouter à l’enchaînement',
                    ),
              onPressed: onToggleChain,
              icon: Icon(
                chainSelected ? Icons.check_rounded : Icons.add_rounded,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
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
  final String emptyActionLabel;
  final IconData emptyActionIcon;
  final VoidCallback onEmptyAction;
  final VoidCallback? onFreeRoam;
  final Map<String, RevvRoute> chainSelection;
  final ValueChanged<RevvRoute> onRouteTap;
  final ValueChanged<RevvRoute> onToggleChain;

  const _FinderRoutesSheet({
    required this.language,
    required this.routes,
    required this.destinationName,
    required this.planning,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyActionLabel,
    required this.emptyActionIcon,
    required this.onEmptyAction,
    required this.onFreeRoam,
    required this.chainSelection,
    required this.onRouteTap,
    required this.onToggleChain,
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
                  actionLabel: emptyActionLabel,
                  actionIcon: emptyActionIcon,
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
                  _RouteListRow(
                    route: route,
                    language: language,
                    driven: false,
                    chainSelected: chainSelection.containsKey(route.id),
                    onTap: () => onRouteTap(route),
                    onToggleChain: () => onToggleChain(route),
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
  final VoidCallback? onBack;
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

class _FinderColdStartBackground extends StatelessWidget {
  const _FinderColdStartBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.bg),
      child: Center(
        child: AnimatedOpacity(
          opacity: 0.18,
          duration: Duration(milliseconds: 420),
          child: Text(
            'REVV',
            style: AppText.display(
              size: 54,
              weight: FontWeight.w900,
              letterSpacing: 0,
              color: AppColors.cream,
            ),
          ),
        ),
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
      key: const Key('finder-route-chain-bar'),
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
                  key: const Key('finder-chain-clear-button'),
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

class _SearchAreaPill extends StatelessWidget {
  final AppLanguage language;
  final VoidCallback onTap;

  const _SearchAreaPill({
    super.key,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.primaryContainer.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_rounded, size: 16, color: Colors.black),
            const SizedBox(width: 6),
            Text(
              AppCopy.t(
                language,
                ko: '이 지역에서 찾기',
                en: 'Search this area',
                fr: 'Chercher dans cette zone',
              ),
              style: AppText.body(
                size: 13,
                weight: FontWeight.w800,
                color: Colors.black,
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

String _routeListMeta(RevvRoute route, AppLanguage language) {
  final feature = route.isLoop
      ? AppCopy.t(language, ko: '루프', en: 'Loop', fr: 'Boucle')
      : route.tightCurveKm >= 1.2
      ? AppCopy.t(
          language,
          ko: '타이트 코너',
          en: 'Tight curves',
          fr: 'Virages serrés',
        )
      : route.mediumCurveKm >= 2.0
      ? AppCopy.t(language, ko: '스위퍼', en: 'Sweepers', fr: 'Courbes fluides')
      : AppCopy.t(
          language,
          ko: '가벼운 리듬',
          en: 'Light rhythm',
          fr: 'Rythme léger',
        );
  return '${route.distanceKm.toStringAsFixed(1)} km · ${driveMinutesLabel(route, language)} · $feature';
}

int routeChainSegmentCount(RevvRoute route) {
  if (route.isChainRoute) {
    final encoded = route.id.substring(RevvRoute.chainRouteIdPrefix.length);
    if (encoded.isEmpty) return 1;
    return encoded
        .split('/')
        .where((part) => part.isNotEmpty)
        .length
        .clamp(1, _maxChainRoutes)
        .toInt();
  }
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

String _chainLimitLabel(AppLanguage language) {
  return AppCopy.t(
    language,
    ko: '루트 체인은 최대 6개까지 연결할 수 있어요.',
    en: 'A route chain can include up to 6 routes.',
    fr: 'Une chaîne peut contenir jusqu’à 6 routes.',
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
  final now = DateTime.now();
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
          showNewCasing: route.isNewlyGeneratedAt(now),
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
      ko: '근처 루트를 찾으려면 위치 권한을 허용해 주세요.',
      en: 'Allow location to find nearby routes.',
      fr: 'Autorisez la position pour trouver des routes à proximité.',
    ),
    RouteFinderStateKind.permanentlyLocationDenied => AppCopy.t(
      language,
      ko: '권한이 차단되어 앱 안에서 다시 묻기 어렵습니다. 설정에서 위치를 허용해 주세요.',
      en: 'Permission is blocked. Open Settings to allow location.',
      fr: 'Autorisation bloquée. Ouvrez Réglages pour autoriser la position.',
    ),
    RouteFinderStateKind.emptyRoutes => AppCopy.t(
      language,
      ko: '지도를 옮기거나 축척을 바꾼 뒤 이 지도에서 다시 찾아보세요.',
      en: 'Move or zoom the map, then search this map again.',
      fr: 'Déplacez ou zoomez la carte, puis relancez la recherche ici.',
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
      ko: '이 지도에서 찾기',
      en: 'Search this map',
      fr: 'Rechercher ici',
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
  return _localizedRouteStatusBody(service, language) ??
      AppCopy.t(
        language,
        ko: '현재 위치와 연결 상태를 확인한 뒤 다시 시도해 주세요.',
        en: 'Check location and connection, then try again.',
        fr: 'Vérifiez la position et la connexion, puis réessayez.',
      );
}

enum _RouteServiceStatusKey {
  noCandidates,
  picksRefreshed,
  fieldLoading,
  usingCache,
  findingRoutes,
  dataConnectionNeeded,
  loadFailed,
  routesReady,
  noCurveRoads,
  keepingCache,
  fieldReady,
  unknown,
}

_RouteServiceStatusKey _routeServiceStatusKeyFor(String? title) {
  return switch (title) {
    '루트 후보 없음' => _RouteServiceStatusKey.noCandidates,
    '추천 후보 갱신' => _RouteServiceStatusKey.picksRefreshed,
    '커브길 필드 로딩 중' => _RouteServiceStatusKey.fieldLoading,
    '캐시 사용 중' => _RouteServiceStatusKey.usingCache,
    '루트 탐색 중' => _RouteServiceStatusKey.findingRoutes,
    '루트 데이터 연결 필요' ||
    '클라우드 설정 없음' => _RouteServiceStatusKey.dataConnectionNeeded,
    '루트 로드 실패' => _RouteServiceStatusKey.loadFailed,
    '루트 준비 완료' => _RouteServiceStatusKey.routesReady,
    '커브길 없음' => _RouteServiceStatusKey.noCurveRoads,
    '캐시 유지 중' => _RouteServiceStatusKey.keepingCache,
    '커브길 준비 완료' => _RouteServiceStatusKey.fieldReady,
    _ => _RouteServiceStatusKey.unknown,
  };
}

String routeFinderStatusTitleFor(String? title, AppLanguage language) {
  return switch (_routeServiceStatusKeyFor(title)) {
    _RouteServiceStatusKey.noCandidates => AppCopy.t(
      language,
      ko: '루트 후보 없음',
      en: 'No route picks',
      fr: 'Aucune option',
    ),
    _RouteServiceStatusKey.picksRefreshed => AppCopy.t(
      language,
      ko: '추천 후보 갱신',
      en: 'Picks refreshed',
      fr: 'Options actualisées',
    ),
    _RouteServiceStatusKey.fieldLoading => AppCopy.t(
      language,
      ko: '커브길 필드 로딩 중',
      en: 'Loading curve field',
      fr: 'Chargement des routes',
    ),
    _RouteServiceStatusKey.usingCache => AppCopy.t(
      language,
      ko: '캐시 사용 중',
      en: 'Using cached routes',
      fr: 'Routes en cache',
    ),
    _RouteServiceStatusKey.findingRoutes => AppCopy.t(
      language,
      ko: '루트 탐색 중',
      en: 'Finding routes',
      fr: 'Recherche de routes',
    ),
    _RouteServiceStatusKey.dataConnectionNeeded => AppCopy.t(
      language,
      ko: '루트 데이터 연결 필요',
      en: 'Route data connection needed',
      fr: 'Connexion aux données requise',
    ),
    _RouteServiceStatusKey.loadFailed => AppCopy.t(
      language,
      ko: '루트 로드 실패',
      en: 'Route load failed',
      fr: 'Échec du chargement',
    ),
    _RouteServiceStatusKey.routesReady => AppCopy.t(
      language,
      ko: '루트 준비 완료',
      en: 'Routes ready',
      fr: 'Routes prêtes',
    ),
    _RouteServiceStatusKey.noCurveRoads => AppCopy.t(
      language,
      ko: '커브길 없음',
      en: 'No curve roads',
      fr: 'Aucune route sinueuse',
    ),
    _RouteServiceStatusKey.keepingCache => AppCopy.t(
      language,
      ko: '캐시 유지 중',
      en: 'Keeping cached routes',
      fr: 'Cache conservé',
    ),
    _RouteServiceStatusKey.fieldReady => AppCopy.t(
      language,
      ko: '커브길 준비 완료',
      en: 'Curve field ready',
      fr: 'Routes prêtes',
    ),
    _RouteServiceStatusKey.unknown => 'Route status is unavailable.',
  };
}

String routeFinderStatusBodyFor(String? title, AppLanguage language) {
  return switch (_routeServiceStatusKeyFor(title)) {
    _RouteServiceStatusKey.noCandidates ||
    _RouteServiceStatusKey.noCurveRoads => AppCopy.t(
      language,
      ko: '지도 영역을 옮겨 다시 불러와 보세요.',
      en: 'Move the map and reload this area.',
      fr: 'Déplacez la carte et rechargez la zone.',
    ),
    _RouteServiceStatusKey.dataConnectionNeeded => AppCopy.t(
      language,
      ko: '루트 데이터 연결을 확인한 뒤 다시 시도해 주세요.',
      en: 'Check the route data connection, then try again.',
      fr: 'Vérifiez la connexion aux données, puis réessayez.',
    ),
    _RouteServiceStatusKey.loadFailed => AppCopy.t(
      language,
      ko: '연결 상태를 확인한 뒤 다시 시도해 주세요.',
      en: 'Check your connection and try again.',
      fr: 'Vérifiez votre connexion, puis réessayez.',
    ),
    _RouteServiceStatusKey.usingCache ||
    _RouteServiceStatusKey.keepingCache => AppCopy.t(
      language,
      ko: '저장된 커브길을 표시하고 있어요.',
      en: 'Showing saved curvy roads.',
      fr: 'Affichage des routes sinueuses enregistrées.',
    ),
    _RouteServiceStatusKey.fieldLoading ||
    _RouteServiceStatusKey.findingRoutes => AppCopy.t(
      language,
      ko: '주변 루트를 불러오고 있어요.',
      en: 'Loading nearby routes.',
      fr: 'Chargement des routes à proximité.',
    ),
    _RouteServiceStatusKey.picksRefreshed ||
    _RouteServiceStatusKey.routesReady ||
    _RouteServiceStatusKey.fieldReady => AppCopy.t(
      language,
      ko: '루트를 지도에서 확인해 보세요.',
      en: 'Check the routes on the map.',
      fr: 'Consultez les routes sur la carte.',
    ),
    _RouteServiceStatusKey.unknown => 'Route status is unavailable. Try again.',
  };
}

bool _routeStatusNeedsAttention(String? title) {
  return switch (_routeServiceStatusKeyFor(title)) {
    _RouteServiceStatusKey.fieldLoading ||
    _RouteServiceStatusKey.findingRoutes ||
    _RouteServiceStatusKey.usingCache ||
    _RouteServiceStatusKey.keepingCache ||
    _RouteServiceStatusKey.dataConnectionNeeded ||
    _RouteServiceStatusKey.loadFailed ||
    _RouteServiceStatusKey.noCandidates ||
    _RouteServiceStatusKey.noCurveRoads => true,
    _ => false,
  };
}

String? _localizedRouteStatusTitle(RouteService service, AppLanguage language) {
  final title = service.routeDataStatusTitle;
  if (title == null || title.isEmpty) return title;
  return routeFinderStatusTitleFor(title, language);
}

String? _localizedRouteStatusBody(RouteService service, AppLanguage language) {
  final body = service.routeDataStatusBody;
  if (body == null || body.isEmpty) return body;
  return routeFinderStatusBodyFor(service.routeDataStatusTitle, language);
}
