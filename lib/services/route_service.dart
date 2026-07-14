import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/revv_route.dart';
import 'route_loading_policy.dart';
import 'route_overview_cache.dart';
import 'supabase_service.dart';

enum SprintStartMode { auto, guideToStart, joinFromCurrent }

typedef RouteOverviewFetcher =
    Future<List<RevvRoute>> Function(LatLng center, int maxResults);

class RouteService extends ChangeNotifier {
  RouteService({
    RouteOverviewFetcher? routeOverviewFetcher,
    RouteOverviewCache? routeOverviewCache,
  }) : _routeOverviewFetcher = routeOverviewFetcher,
       _routeOverviewCache = routeOverviewCache ?? RouteOverviewCache() {
    unawaited(_restorePendingDrive(_pendingGuideMutation));
  }

  static const int routeFieldRadiusKm = 160;
  static const int routeFieldFetchLimit = 650;
  static const int routeFieldInitialFetchLimit = 120;
  static const int routeOverviewPerRegionLimit = 30;
  static const int routeOverviewConcurrencyLimit = 3;
  static const double routeOverviewCoverageReuseKm = routeFieldRadiusKm / 2;
  static const double routeFieldCacheReuseKm = 40;
  static const Duration routeFieldCacheTtl = Duration(hours: 24);

  List<RevvRoute> rawCandidateRoutes = [];
  List<RevvRoute> mapVisualRoutes = [];
  List<RevvRoute> routes = [];
  RevvRoute? selectedRoute;

  bool isLoading = false;
  bool isLoadingInitial = false;
  bool isRefreshingDiversity = false;
  String? errorMessage;
  String? backgroundStatusMessage;
  String? routeSuggestionMessage;
  String? routeDataStatusTitle;
  String? routeDataStatusBody;
  String routeDataSourceLabel = '준비 중';

  int lastCloudCandidateCount = 0;
  int lastFilteredRouteCount = 0;
  int lastUsableCloudRouteCount = 0;
  int searchRadiusKm = routeFieldRadiusKm;
  int visibleRouteLimit = defaultVisibleRoutes;
  RouteFilterStrength filterStrength = RouteFilterStrength.balanced;
  LatLng? routeFieldCenter;
  DateTime? routeFieldFetchedAt;
  bool routeFieldFromCache = false;
  bool routeOverviewLoaded = false;
  bool routeOverviewLoading = false;

  bool sprintRequested = false;
  SprintStartMode sprintStartMode = SprintStartMode.auto;
  RevvRoute? sprintRoute;
  RevvRoute? pendingGuideRoute;
  DateTime? pendingGuideStartedAt;
  int _pendingGuideMutation = 0;
  Future<void> _pendingGuideWrites = Future.value();

  int _fetchToken = 0;
  int _overviewFetchToken = 0;
  final RouteOverviewFetcher? _routeOverviewFetcher;
  final RouteOverviewCache _routeOverviewCache;
  List<RevvRoute> _overviewRoutes = const [];
  final Set<String> _overviewCompletedRegionKeys = {};
  LatLng? _pendingOverviewReferencePoint;

  RevvRoute? get effectiveSprintRoute => sprintRoute ?? selectedRoute;

  bool get hasFreshPendingGuide {
    final startedAt = pendingGuideStartedAt;
    if (pendingGuideRoute == null || startedAt == null) return false;
    return DateTime.now().difference(startedAt) < const Duration(hours: 24);
  }

  bool shouldPromptPendingDrive({required double distanceKm}) {
    return hasFreshPendingGuide && distanceKm <= 0.5;
  }

  void beginGuideToStart(RevvRoute route) {
    _pendingGuideMutation++;
    pendingGuideRoute = route;
    pendingGuideStartedAt = DateTime.now();
    unawaited(_savePendingDrive(route, pendingGuideStartedAt!));
    notifyListeners();
  }

  void clearGuideToStart() {
    _pendingGuideMutation++;
    pendingGuideRoute = null;
    pendingGuideStartedAt = null;
    unawaited(_clearPendingDrive());
    notifyListeners();
  }

  Future<void> _savePendingDrive(RevvRoute route, DateTime savedAt) {
    final routeJson = jsonEncode(route.toJson());
    return _enqueuePendingGuideWrite((prefs) async {
      await Future.wait([
        prefs.setString(StorageKeys.pendingDriveRouteId, route.id),
        prefs.setString(
          StorageKeys.pendingDriveSavedAt,
          savedAt.toIso8601String(),
        ),
        prefs.setString(StorageKeys.pendingDriveRoute, routeJson),
      ]);
    });
  }

  Future<void> _clearPendingDrive() {
    return _enqueuePendingGuideWrite((prefs) async {
      await prefs.remove(StorageKeys.pendingDriveRouteId);
      await prefs.remove(StorageKeys.pendingDriveSavedAt);
      await prefs.remove(StorageKeys.pendingDriveRoute);
    });
  }

  Future<void> _enqueuePendingGuideWrite(
    Future<void> Function(SharedPreferences prefs) action,
  ) {
    final write = _pendingGuideWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await action(prefs);
    });
    _pendingGuideWrites = write.catchError((_) {});
    return write;
  }

  Future<void> _restorePendingDrive(int mutation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAt = DateTime.tryParse(
        prefs.getString(StorageKeys.pendingDriveSavedAt) ?? '',
      );
      final rawRoute = prefs.getString(StorageKeys.pendingDriveRoute);
      if (savedAt == null || rawRoute == null) return;
      if (DateTime.now().difference(savedAt) >= const Duration(hours: 24)) {
        if (mutation == _pendingGuideMutation) {
          await _clearPendingDrive();
        }
        return;
      }
      final decoded = jsonDecode(rawRoute) as Map<String, dynamic>;
      final route = RevvRoute.fromJson(decoded);
      if (mutation != _pendingGuideMutation) return;
      pendingGuideRoute = route;
      pendingGuideStartedAt = savedAt;
      notifyListeners();
    } catch (_) {
      if (mutation == _pendingGuideMutation) {
        await _clearPendingDrive();
      }
    }
  }

  void requestSprint({
    RevvRoute? route,
    SprintStartMode startMode = SprintStartMode.auto,
  }) {
    sprintRoute = route ?? selectedRoute;
    sprintStartMode = startMode;
    sprintRequested = sprintRoute != null;
    notifyListeners();
  }

  void clearSprintRequest() {
    sprintRequested = false;
    sprintRoute = null;
    sprintStartMode = SprintStartMode.auto;
    notifyListeners();
  }

  Future<void> changeRadius(int radiusKm, double lat, double lng) async {
    searchRadiusKm = radiusKm;
    await fetchRoutes(lat, lng);
  }

  Future<void> changeVisibleRouteLimit(
    int limit,
    double lat,
    double lng,
  ) async {
    visibleRouteLimit = limit.clamp(4, 32);
    _rebuildRecommendations();
    notifyListeners();
  }

  Future<void> changeFilterStrength(
    RouteFilterStrength strength,
    double lat,
    double lng,
  ) async {
    filterStrength = strength;
    _rebuildRecommendations();
    routeSuggestionMessage = _routeSuggestionForCount(routes.length);
    routeDataStatusTitle = rawCandidateRoutes.isEmpty ? '루트 후보 없음' : '추천 후보 갱신';
    routeDataStatusBody = rawCandidateRoutes.isEmpty
        ? '지도 영역을 옮겨 다시 불러와 보세요.'
        : '${routeFilterStrengthLabel(filterStrength)} 필터로 ${routes.length}개 추천 후보를 다시 골랐고, 지도에는 ${mapVisualRoutes.length}개 커브길을 유지합니다.';
    notifyListeners();
  }

  Future<void> prefetchRouteField(
    double lat,
    double lng, {
    bool forceRefresh = false,
  }) async {
    searchRadiusKm = routeFieldRadiusKm;
    final point = LatLng(lat, lng);
    final token = ++_fetchToken;
    isLoading = true;
    isLoadingInitial = rawCandidateRoutes.isEmpty;
    errorMessage = null;
    routeSuggestionMessage = null;
    backgroundStatusMessage = '주변 커브길 불러오는 중';
    routeDataStatusTitle = '커브길 필드 로딩 중';
    routeDataStatusBody =
        '현재 위치 기준 ${routeFieldRadiusKm}km 안의 커브길을 한 번에 불러옵니다.';
    notifyListeners();

    final cached = forceRefresh ? null : await _loadRouteFieldCache(point);
    if (token != _fetchToken) return;

    if (cached != null) {
      _applyRouteField(
        _routesRelativeTo(cached.routes, point),
        center: cached.center,
        fetchedAt: cached.fetchedAt,
        sourceLabel: '로컬 캐시',
        fromCache: true,
      );
      final ageMinutes = DateTime.now()
          .difference(cached.fetchedAt)
          .inMinutes
          .clamp(0, 1440);
      routeDataStatusTitle = '캐시 사용 중';
      routeDataStatusBody =
          '$routeFieldRadiusKm km 커브길 캐시 ${mapVisualRoutes.length}개를 먼저 표시합니다. $ageMinutes분 전 데이터예요.';
      isLoading = false;
      isLoadingInitial = false;
      backgroundStatusMessage = null;
      notifyListeners();
      unawaited(_refreshRouteField(point, token));
      return;
    }

    await _refreshRouteField(point, token, allowCacheFallback: true);
  }

  Future<void> prefetchRouteOverview(LatLng referencePoint) async {
    if (routeOverviewLoading) {
      _pendingOverviewReferencePoint = referencePoint;
      return;
    }
    if (routeOverviewLoaded && _hasOverviewCoverage(referencePoint)) return;
    routeOverviewLoading = true;
    final token = ++_overviewFetchToken;
    notifyListeners();

    try {
      final cached = await _routeOverviewCache.read();
      if (token != _overviewFetchToken) return;
      final staticRegionKeys = {
        for (final center in routeOverviewCenters) _overviewRegionKey(center),
      };
      final completedRegionKeys = <String>{
        ..._overviewCompletedRegionKeys,
        ...?cached?.completedRegionKeys,
      };
      _overviewCompletedRegionKeys.addAll(completedRegionKeys);
      if (cached != null) {
        _overviewRoutes = cached.routes;
        _refreshMapVisualRoutes();
        notifyListeners();
        routeOverviewLoaded = staticRegionKeys.every(
          completedRegionKeys.contains,
        );
        if (routeOverviewLoaded &&
            _hasOverviewCoverage(
              referencePoint,
              completedRegionKeys: completedRegionKeys,
            )) {
          return;
        }
      }

      final requestCenters = _overviewRequestCenters(
        referencePoint,
        completedRegionKeys,
      );
      final regionalFields = List<List<RevvRoute>?>.filled(
        requestCenters.length,
        null,
      );
      final baselineRoutes = _overviewRoutes;
      var nextRequest = 0;
      var newlyCompletedRegionCount = 0;

      Future<void> loadNextRegions() async {
        while (token == _overviewFetchToken) {
          if (nextRequest >= requestCenters.length) return;
          final index = nextRequest++;
          final center = requestCenters[index];
          List<RevvRoute> field;
          try {
            field = await _fetchRouteOverviewRegion(center);
          } catch (_) {
            continue;
          }
          if (token != _overviewFetchToken) return;
          regionalFields[index] = field;
          final regionKey = _overviewRegionKey(center);
          completedRegionKeys.add(regionKey);
          _overviewCompletedRegionKeys.add(regionKey);
          newlyCompletedRegionCount++;
          _overviewRoutes = mergeRouteOverviewFields([
            baselineRoutes,
            ...regionalFields.whereType<List<RevvRoute>>(),
          ], limit: routeFieldFetchLimit);
          _refreshMapVisualRoutes();
          notifyListeners();
        }
      }

      await Future.wait([
        for (var worker = 0; worker < routeOverviewConcurrencyLimit; worker++)
          loadNextRegions(),
      ]);
      if (token != _overviewFetchToken) return;

      if (newlyCompletedRegionCount > 0) {
        await _routeOverviewCache.write(
          RouteOverviewCacheEntry(
            routes: _overviewRoutes,
            completedRegionKeys: completedRegionKeys,
          ),
        );
      }

      routeOverviewLoaded = staticRegionKeys.every(
        completedRegionKeys.contains,
      );
    } catch (e) {
      if (token != _overviewFetchToken) return;
      if (kDebugMode) {
        debugPrint('[RouteService] route overview failed: ${e.runtimeType}');
      }
    } finally {
      routeOverviewLoading = false;
      if (token == _overviewFetchToken) {
        notifyListeners();
        final pendingReferencePoint = _pendingOverviewReferencePoint;
        _pendingOverviewReferencePoint = null;
        if (pendingReferencePoint != null &&
            !_hasOverviewCoverage(pendingReferencePoint)) {
          unawaited(prefetchRouteOverview(pendingReferencePoint));
        }
      }
    }
  }

  List<LatLng> _overviewRequestCenters(
    LatLng referencePoint,
    Set<String> completedRegionKeys,
  ) {
    final missingStaticCenters =
        routeOverviewCenters
            .where(
              (center) =>
                  !completedRegionKeys.contains(_overviewRegionKey(center)),
            )
            .toList()
          ..sort((a, b) {
            final distanceA = RevvRoute.haversineKm(referencePoint, a);
            final distanceB = RevvRoute.haversineKm(referencePoint, b);
            return distanceA.compareTo(distanceB);
          });
    if (_hasOverviewCoverage(
      referencePoint,
      completedRegionKeys: completedRegionKeys,
    )) {
      return missingStaticCenters;
    }

    if (missingStaticCenters.isNotEmpty &&
        RevvRoute.haversineKm(referencePoint, missingStaticCenters.first) <=
            routeOverviewCoverageReuseKm) {
      return missingStaticCenters;
    }
    return [referencePoint, ...missingStaticCenters];
  }

  bool _hasOverviewCoverage(
    LatLng referencePoint, {
    Set<String>? completedRegionKeys,
  }) {
    final keys = completedRegionKeys ?? _overviewCompletedRegionKeys;
    return keys.any((key) {
      final center = _overviewCenterFromKey(key);
      return center != null &&
          RevvRoute.haversineKm(referencePoint, center) <=
              routeOverviewCoverageReuseKm;
    });
  }

  LatLng? _overviewCenterFromKey(String key) {
    final parts = key.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String _overviewRegionKey(LatLng center) =>
      '${center.lat.toStringAsFixed(4)},${center.lng.toStringAsFixed(4)}';

  Future<List<RevvRoute>> _fetchRouteOverviewRegion(LatLng center) {
    final fetcher = _routeOverviewFetcher;
    if (fetcher != null) {
      return fetcher(center, routeOverviewPerRegionLimit);
    }
    return SupabaseService().fetchNearbyRoutes(
      center.lat,
      center.lng,
      routeFieldRadiusKm.toDouble(),
      maxResults: routeOverviewPerRegionLimit,
      throwOnFailure: true,
      trackFailureReason: false,
    );
  }

  Future<void> fetchRoutes(double lat, double lng) async {
    searchRadiusKm = searchRadiusKm <= 0 ? routeFieldRadiusKm : searchRadiusKm;
    await _fetchRoutesAt(LatLng(lat, lng), radiusKm: searchRadiusKm);
  }

  Future<void> _fetchRoutesAt(LatLng point, {required int radiusKm}) async {
    final token = ++_fetchToken;
    isLoading = true;
    isLoadingInitial = routes.isEmpty;
    errorMessage = null;
    routeSuggestionMessage = null;
    final strengthLabel = routeFilterStrengthLabel(filterStrength);
    backgroundStatusMessage = '주변 루트를 찾는 중';
    routeDataStatusTitle = '루트 탐색 중';
    routeDataStatusBody =
        '현재 위치 기준 ${radiusKm}km 안에서 $strengthLabel 필터로 후보를 불러옵니다.';
    notifyListeners();

    try {
      final cloud = SupabaseService();
      final cloudReady = cloud.isCloudAvailable;
      var candidates = await cloud.fetchNearbyRoutes(
        point.lat,
        point.lng,
        radiusKm.toDouble(),
        maxResults: routeFieldInitialFetchLimit,
      );
      lastCloudCandidateCount = candidates.length;

      if (candidates.isEmpty) {
        candidates = await cloud.fetchNearbyRoutesDirect(
          point.lat,
          point.lng,
          radiusKm.toDouble(),
          limit: routeFieldInitialFetchLimit,
        );
        lastCloudCandidateCount = candidates.length;
      }

      if (candidates.isEmpty) {
        final cached = await _loadRouteFieldCache(point);
        candidates = cached == null
            ? const []
            : _routesRelativeTo(cached.routes, point);
        routeDataSourceLabel = candidates.isEmpty ? '루트 없음' : '로컬 캐시';
      } else {
        routeDataSourceLabel = 'Supabase';
      }

      if (token != _fetchToken) return;

      _applyRouteField(
        candidates,
        center: point,
        fetchedAt: DateTime.now(),
        sourceLabel: routeDataSourceLabel,
        fromCache: routeDataSourceLabel == '로컬 캐시',
      );
      if (kDebugMode) {
        debugPrint(
          '[RouteService] route pool '
          'radius=${radiusKm}km '
          'strength=${routeFilterStrengthStorageValue(filterStrength)} '
          'raw=${rawCandidateRoutes.length} '
          'filtered=$lastFilteredRouteCount '
          'map=${mapVisualRoutes.length} '
          'visible=${routes.length}/$visibleRouteLimit',
        );
      }

      if (routes.isEmpty) {
        if (!cloudReady) {
          errorMessage = '루트 데이터를 연결하지 못했어요';
          routeDataStatusTitle = '루트 데이터 연결 필요';
          routeDataStatusBody = '앱의 루트 데이터 연결을 확인한 뒤 다시 시도해 주세요.';
        } else if (cloud.lastFailureReason != null) {
          errorMessage = '네트워크 연결을 확인해 주세요';
          routeDataStatusTitle = '루트 로드 실패';
          routeDataStatusBody = '루트 데이터 요청이 실패했어요. 연결 상태를 확인한 뒤 다시 시도해 주세요.';
        } else {
          errorMessage = '주변 루트를 찾지 못했어요';
          routeDataStatusTitle = '루트 후보 없음';
          routeDataStatusBody = _emptyRouteStatusBody(candidates.length);
        }
      } else {
        errorMessage = null;
        routeSuggestionMessage = _routeSuggestionForCount(routes.length);
        routeDataStatusTitle = '루트 준비 완료';
        routeDataStatusBody =
            '$strengthLabel 필터로 ${routes.length}개 추천 후보를 불러왔고, 지도에는 ${mapVisualRoutes.length}개 커브 후보를 표시합니다.';
        if (routeDataSourceLabel == 'Supabase') {
          unawaited(_saveRouteFieldCache(point, radiusKm, candidates));
        }
        unawaited(_hydrateSelectedRouteNodes());
      }
    } catch (e) {
      if (token != _fetchToken) return;
      final cached = await _loadRouteFieldCache(point);
      if (cached != null) {
        _applyRouteField(
          _routesRelativeTo(cached.routes, point),
          center: cached.center,
          fetchedAt: cached.fetchedAt,
          sourceLabel: '로컬 캐시',
          fromCache: true,
        );
        if (kDebugMode) {
          debugPrint(
            '[RouteService] cached route pool '
            'radius=${radiusKm}km '
            'strength=${routeFilterStrengthStorageValue(filterStrength)} '
            'filtered=$lastFilteredRouteCount '
            'map=${mapVisualRoutes.length} '
            'visible=${routes.length}/$visibleRouteLimit',
          );
        }
        routeDataSourceLabel = '로컬 캐시';
        errorMessage = null;
        routeSuggestionMessage = _routeSuggestionForCount(routes.length);
        routeDataStatusTitle = '캐시 사용 중';
        routeDataStatusBody = '네트워크 실패로 마지막 루트 목록을 사용합니다.';
      } else {
        errorMessage = '루트를 불러오지 못했어요';
        routeSuggestionMessage = null;
        routeDataStatusTitle = '루트 로드 실패';
        routeDataStatusBody = '연결 상태를 확인한 뒤 다시 시도해 주세요.';
      }
    } finally {
      if (token == _fetchToken) {
        isLoading = false;
        isLoadingInitial = false;
        backgroundStatusMessage = null;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshRouteField(
    LatLng point,
    int token, {
    bool allowCacheFallback = false,
  }) async {
    try {
      final cloud = SupabaseService();
      var candidates = await cloud.fetchNearbyRoutes(
        point.lat,
        point.lng,
        routeFieldRadiusKm.toDouble(),
        maxResults: routeFieldInitialFetchLimit,
      );
      lastCloudCandidateCount = candidates.length;

      if (candidates.isEmpty) {
        candidates = await cloud.fetchNearbyRoutesDirect(
          point.lat,
          point.lng,
          routeFieldRadiusKm.toDouble(),
          limit: routeFieldInitialFetchLimit,
        );
        lastCloudCandidateCount = candidates.length;
      }

      if (token != _fetchToken) return;

      if (candidates.isEmpty) {
        if (allowCacheFallback) {
          final cached = await _loadRouteFieldCache(point, ignoreTtl: true);
          if (token != _fetchToken) return;
          if (cached != null) {
            _applyRouteField(
              _routesRelativeTo(cached.routes, point),
              center: cached.center,
              fetchedAt: cached.fetchedAt,
              sourceLabel: '로컬 캐시',
              fromCache: true,
            );
          }
        }
        errorMessage = rawCandidateRoutes.isEmpty ? '주변 커브길을 찾지 못했어요' : null;
        routeDataStatusTitle = rawCandidateRoutes.isEmpty
            ? '커브길 없음'
            : '캐시 유지 중';
        routeDataStatusBody = rawCandidateRoutes.isEmpty
            ? '지도 영역을 옮겨 다시 불러와 보세요.'
            : '최신 데이터를 가져오지 못해 기존 커브길 캐시를 유지합니다.';
        return;
      }

      _applyRouteField(
        candidates,
        center: point,
        fetchedAt: DateTime.now(),
        sourceLabel: 'Supabase',
        fromCache: false,
      );
      await _saveRouteFieldCache(point, routeFieldRadiusKm, candidates);
      routeDataStatusTitle = '커브길 준비 완료';
      routeDataStatusBody =
          '지도에는 ${mapVisualRoutes.length}개 커브길을 깔고, ${routes.length}개 추천 후보를 골랐습니다.';
      routeSuggestionMessage = _routeSuggestionForCount(routes.length);
      if (kDebugMode) {
        debugPrint(
          '[RouteService] route field refreshed '
          'fieldRaw=${rawCandidateRoutes.length} '
          'fieldMap=${mapVisualRoutes.length} '
          'recommended=${routes.length}/$visibleRouteLimit '
          'cacheAge=0m',
        );
      }
    } catch (e) {
      if (token != _fetchToken) return;
      errorMessage = rawCandidateRoutes.isEmpty ? '커브길을 불러오지 못했어요' : null;
      routeDataStatusTitle = rawCandidateRoutes.isEmpty
          ? '루트 로드 실패'
          : '캐시 유지 중';
      routeDataStatusBody = rawCandidateRoutes.isEmpty
          ? '연결 상태를 확인한 뒤 다시 시도해 주세요.'
          : '최신 데이터 요청이 실패해 기존 커브길 캐시를 유지합니다.';
      if (kDebugMode) {
        debugPrint(
          '[RouteService] route field refresh failed: ${e.runtimeType}',
        );
      }
    } finally {
      if (token == _fetchToken) {
        isLoading = false;
        isLoadingInitial = false;
        backgroundStatusMessage = null;
        notifyListeners();
      }
    }
  }

  void selectRoute(RevvRoute route) {
    selectedRoute = route;
    notifyListeners();
    unawaited(_hydrateSelectedRouteNodes());
  }

  void deselectRoute() {
    selectedRoute = null;
    notifyListeners();
  }

  void resetCache() {
    _overviewFetchToken++;
    _pendingOverviewReferencePoint = null;
    _overviewRoutes = const [];
    _overviewCompletedRegionKeys.clear();
    routeOverviewLoaded = false;
    rawCandidateRoutes = [];
    mapVisualRoutes = [];
    routes = [];
    selectedRoute = null;
    routeFieldCenter = null;
    routeFieldFetchedAt = null;
    routeFieldFromCache = false;
    routeDataSourceLabel = '초기화됨';
    notifyListeners();
  }

  List<RevvRoute> _prepareVisibleRoutes(List<RevvRoute> candidates) {
    final unique = <String, RevvRoute>{};
    for (final route in candidates) {
      unique[route.id] = route;
    }
    final filtered = filterRoutesForStrength(unique.values, filterStrength);
    lastFilteredRouteCount = filtered.length;
    return diversifyRouteSlots(filtered, limit: visibleRouteLimit);
  }

  void _applyRouteField(
    List<RevvRoute> candidates, {
    required LatLng center,
    required DateTime fetchedAt,
    required String sourceLabel,
    required bool fromCache,
  }) {
    rawCandidateRoutes = List<RevvRoute>.unmodifiable(candidates);
    _refreshMapVisualRoutes();
    _rebuildRecommendations();
    selectedRoute = routes.isNotEmpty ? routes.first : null;
    routeFieldCenter = center;
    routeFieldFetchedAt = fetchedAt;
    routeFieldFromCache = fromCache;
    routeDataSourceLabel = sourceLabel;
  }

  void _refreshMapVisualRoutes() {
    mapVisualRoutes = mergeRouteOverviewFields([
      _prepareMapVisualRoutes(rawCandidateRoutes),
      _overviewRoutes,
    ], limit: routeFieldFetchLimit);
  }

  void _rebuildRecommendations() {
    final visible = _prepareVisibleRoutes(rawCandidateRoutes);
    lastUsableCloudRouteCount = visible.length;
    routes = visible;
    if (selectedRoute != null &&
        !rawCandidateRoutes.any((route) => route.id == selectedRoute!.id)) {
      selectedRoute = visible.isNotEmpty ? visible.first : null;
    }
  }

  List<RevvRoute> _prepareMapVisualRoutes(List<RevvRoute> candidates) {
    final unique = <String, RevvRoute>{};
    for (final route in candidates) {
      if (route.nodes.length > 1) {
        unique[route.id] = route;
      }
    }

    // The map layer is intentionally broader than the recommendation list.
    // Cards still use quality filters, but the map should show the full
    // curvature field so users can visually pick roads like Curvature.
    return List<RevvRoute>.unmodifiable(unique.values);
  }

  String? _routeSuggestionForCount(int count) {
    if (count >= 8) return null;
    if (filterStrength != RouteFilterStrength.broad) {
      return '후보가 적어요. 필터를 넓게로 바꿔볼까요?';
    }
    return '후보가 적어요. 지도 영역을 옮겨 다시 불러와 보세요.';
  }

  String _emptyRouteStatusBody(int rawCount) {
    if (rawCount > 0 && filterStrength != RouteFilterStrength.broad) {
      return '원본 후보 $rawCount개가 있었지만 ${routeFilterStrengthLabel(filterStrength)} 필터를 통과하지 못했어요. 넓게 보기로 다시 비교해 보세요.';
    }
    return '지도 영역을 옮겨 다시 불러와 보세요.';
  }

  Future<void> _hydrateSelectedRouteNodes() async {
    final route = selectedRoute;
    if (route == null || route.nodes.isNotEmpty) return;
    final nodes = await SupabaseService().fetchRouteNodes(route.id);
    if (nodes.isEmpty || selectedRoute?.id != route.id) return;
    final hydrated = route.copyWith(nodes: nodes);
    selectedRoute = hydrated;
    routes = [
      for (final item in routes) item.id == hydrated.id ? hydrated : item,
    ];
    notifyListeners();
  }

  Future<void> _saveRouteFieldCache(
    LatLng center,
    int radiusKm,
    List<RevvRoute> routes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageKeys.routeCache,
        jsonEncode({
          'version': 2,
          'centerLat': center.lat,
          'centerLng': center.lng,
          'radiusKm': radiusKm,
          'fetchedAt': DateTime.now().toIso8601String(),
          'routes': routes.map((route) => route.toJson()).toList(),
        }),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RouteService] cache save failed: ${e.runtimeType}');
      }
    }
  }

  Future<_RouteFieldCache?> _loadRouteFieldCache(
    LatLng target, {
    bool ignoreTtl = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(StorageKeys.routeCache);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final center = LatLng(
        (decoded['centerLat'] as num).toDouble(),
        (decoded['centerLng'] as num).toDouble(),
      );
      final radiusKm = (decoded['radiusKm'] as num?)?.toInt() ?? 0;
      final fetchedAt =
          DateTime.tryParse(decoded['fetchedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final routes = ((decoded['routes'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RevvRoute.fromJson)
          .toList();
      if (routes.isEmpty) return null;

      final cache = _RouteFieldCache(
        center: center,
        radiusKm: radiusKm,
        fetchedAt: fetchedAt,
        routes: routes,
      );
      if (!ignoreTtl && !_isRouteFieldCacheUsable(cache, target)) return null;
      return cache;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RouteService] cache load failed: ${e.runtimeType}');
      }
      return null;
    }
  }

  bool _isRouteFieldCacheUsable(_RouteFieldCache cache, LatLng target) {
    if (cache.radiusKm < routeFieldRadiusKm) return false;
    final age = DateTime.now().difference(cache.fetchedAt);
    if (age > routeFieldCacheTtl) return false;
    final distanceKm = RevvRoute.haversineKm(cache.center, target);
    return distanceKm <= routeFieldCacheReuseKm;
  }

  List<RevvRoute> _routesRelativeTo(List<RevvRoute> routes, LatLng target) {
    return routes
        .map(
          (route) => route.copyWith(
            distanceFromUser: RevvRoute.haversineKm(target, route.centerPoint),
          ),
        )
        .toList(growable: false);
  }
}

class _RouteFieldCache {
  final LatLng center;
  final int radiusKm;
  final DateTime fetchedAt;
  final List<RevvRoute> routes;

  const _RouteFieldCache({
    required this.center,
    required this.radiusKm,
    required this.fetchedAt,
    required this.routes,
  });
}
