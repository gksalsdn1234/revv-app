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
typedef RouteCatalogFetcher = Future<List<RevvRoute>> Function(int maxResults);
typedef RouteCatalogEpochFetcher = Future<int> Function();
typedef RouteNodeFetcher = Future<List<LatLng>> Function(String routeId);

class _RouteOverviewRegionResult {
  const _RouteOverviewRegionResult({
    required this.routes,
    required this.isComplete,
  });

  final List<RevvRoute> routes;
  final bool isComplete;
}

class RouteService extends ChangeNotifier {
  RouteService({
    RouteOverviewFetcher? routeOverviewFetcher,
    RouteOverviewFetcher? routeMapSegmentFetcher,
    RouteCatalogFetcher? routeCatalogFetcher,
    RouteCatalogEpochFetcher? routeCatalogEpochFetcher,
    RouteOverviewFetcher? routeLocalV2Fetcher,
    RouteOverviewFetcher? routeLegacyFetcher,
    RouteOverviewFetcher? routeLegacyDirectFetcher,
    RouteNodeFetcher? routeNodeV2Fetcher,
    RouteNodeFetcher? routeLegacyNodeFetcher,
    RouteOverviewCache? routeOverviewCache,
  }) : _routeOverviewFetcher = routeOverviewFetcher,
       _routeMapSegmentFetcher = routeMapSegmentFetcher,
       _routeCatalogFetcher = routeCatalogFetcher,
       _routeCatalogEpochFetcher = routeCatalogEpochFetcher,
       _routeLocalV2Fetcher = routeLocalV2Fetcher,
       _routeLegacyFetcher = routeLegacyFetcher,
       _routeLegacyDirectFetcher = routeLegacyDirectFetcher,
       _routeNodeV2Fetcher = routeNodeV2Fetcher,
       _routeLegacyNodeFetcher = routeLegacyNodeFetcher,
       _routeOverviewCache = routeOverviewCache ?? RouteOverviewCache();

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
  int routeFieldGeneration = 0;
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

  int _fetchToken = 0;
  int _overviewFetchToken = 0;
  final RouteOverviewFetcher? _routeOverviewFetcher;
  final RouteOverviewFetcher? _routeMapSegmentFetcher;
  final RouteCatalogFetcher? _routeCatalogFetcher;
  final RouteCatalogEpochFetcher? _routeCatalogEpochFetcher;
  final RouteOverviewFetcher? _routeLocalV2Fetcher;
  final RouteOverviewFetcher? _routeLegacyFetcher;
  final RouteOverviewFetcher? _routeLegacyDirectFetcher;
  final RouteNodeFetcher? _routeNodeV2Fetcher;
  final RouteNodeFetcher? _routeLegacyNodeFetcher;
  final RouteOverviewCache _routeOverviewCache;
  List<RevvRoute> _overviewRoutes = const [];
  final Set<String> _overviewCompletedRegionKeys = {};
  final Map<String, bool> _overviewRegionHadRoutes = {};
  LatLng? _pendingOverviewReferencePoint;
  Future<int?>? _catalogEpochValidation;
  int? _validatedCatalogEpoch;
  bool _catalogAttempted = false;
  bool _overviewCacheRestored = false;
  bool _disposed = false;

  RevvRoute? get effectiveSprintRoute => sprintRoute ?? selectedRoute;

  void beginGuideToStart(RevvRoute route) {
    pendingGuideRoute = route;
    pendingGuideStartedAt = DateTime.now();
    notifyListeners();
  }

  void clearGuideToStart() {
    pendingGuideRoute = null;
    pendingGuideStartedAt = null;
    notifyListeners();
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
    routeFieldGeneration++;
    notifyListeners();
  }

  Future<void> changeFilterStrength(
    RouteFilterStrength strength,
    double lat,
    double lng,
  ) async {
    filterStrength = strength;
    _rebuildRecommendations();
    routeFieldGeneration++;
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
    _catalogEpochValidation = null;
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
    _catalogEpochValidation = null;
    routeOverviewLoading = true;
    final token = ++_overviewFetchToken;
    notifyListeners();

    try {
      if (!_overviewCacheRestored) {
        _overviewCacheRestored = true;
        final cached = await _routeOverviewCache.read();
        if (token != _overviewFetchToken) return;
        if (cached != null) {
          _overviewCompletedRegionKeys.addAll(cached.completedRegionKeys);
          _overviewRegionHadRoutes.addAll(cached.regionHadRoutes);
          _overviewRoutes = await _validatedCachedRoutes(
            cached.routes,
            cached.catalogEpoch,
          );
          _refreshMapVisualRoutes();
          notifyListeners();
        }
      }

      final epoch = await _ensureCatalogEpoch();
      if (token != _overviewFetchToken) return;
      if (!_catalogAttempted && epoch != null) {
        _catalogAttempted = true;
        try {
          final fetcher = _routeCatalogFetcher;
          final catalog = fetcher != null
              ? await fetcher(routeFieldFetchLimit)
              : await SupabaseService().fetchRouteCatalog(
                  maxResults: routeFieldFetchLimit,
                );
          if (token != _overviewFetchToken) return;
          _overviewRoutes = mergeRouteOverviewFields([
            _overviewRoutes.where((route) => !route.isGenerated).toList(),
            _routesAllowedForEpoch(catalog, epoch),
          ], limit: routeFieldFetchLimit);
          _refreshMapVisualRoutes();
          notifyListeners();
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[RouteService] route catalog failed: ${error.runtimeType}',
            );
          }
        }
      }

      var cacheChanged = false;
      if (!_hasOverviewCoverage(referencePoint)) {
        try {
          final result = await _fetchRouteOverviewRegion(referencePoint);
          if (token != _overviewFetchToken) return;
          final field = epoch == null
              ? result.routes.where((route) => !route.isGenerated).toList()
              : _routesAllowedForEpoch(result.routes, epoch);
          _overviewRoutes = mergeRouteOverviewFields([
            _overviewRoutes,
            field,
          ], limit: routeFieldFetchLimit);
          _refreshMapVisualRoutes();
          notifyListeners();
          final key = _overviewRegionKey(referencePoint);
          if (result.isComplete) {
            _overviewCompletedRegionKeys.add(key);
            _overviewRegionHadRoutes[key] = field.isNotEmpty;
            cacheChanged = true;
          } else {
            _overviewCompletedRegionKeys.remove(key);
            _overviewRegionHadRoutes.remove(key);
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[RouteService] viewport supplement failed: ${error.runtimeType}',
            );
          }
        }
      }

      routeOverviewLoaded = true;
      if ((_catalogAttempted || cacheChanged) &&
          _overviewCompletedRegionKeys.isNotEmpty) {
        await _routeOverviewCache.write(
          RouteOverviewCacheEntry(
            routes: _overviewRoutes,
            completedRegionKeys: _overviewCompletedRegionKeys,
            regionHadRoutes: {
              for (final key in _overviewCompletedRegionKeys)
                key: _overviewRegionHadRoutes[key] ?? false,
            },
            catalogEpoch: epoch,
          ),
        );
      }
    } catch (e) {
      if (token != _overviewFetchToken) return;
      if (kDebugMode) {
        debugPrint('[RouteService] route overview failed: ${e.runtimeType}');
      }
    } finally {
      routeOverviewLoading = false;
      if (token == _overviewFetchToken && !_disposed) {
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

  bool _hasOverviewCoverage(
    LatLng referencePoint, {
    Set<String>? completedRegionKeys,
  }) {
    final keys = completedRegionKeys ?? _overviewCompletedRegionKeys;
    final nearbyKeys = keys.where((key) {
      final center = _overviewCenterFromKey(key);
      return center != null &&
          RevvRoute.haversineKm(referencePoint, center) <=
              routeOverviewCoverageReuseKm;
    }).toList();
    if (nearbyKeys.isEmpty) return false;
    for (final key in nearbyKeys) {
      if (_overviewRegionHadRoutes[key] != true) return true;
      final center = _overviewCenterFromKey(key)!;
      if (_overviewRoutes.any(
        (route) =>
            RevvRoute.haversineKm(center, route.centerPoint) <=
            routeFieldRadiusKm,
      )) {
        return true;
      }
    }
    return false;
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

  Future<_RouteOverviewRegionResult> _fetchRouteOverviewRegion(
    LatLng center,
  ) async {
    final fetcher = _routeOverviewFetcher;
    final recommended = fetcher != null
        ? await fetcher(center, routeOverviewPerRegionLimit)
        : await _fetchLocalRoutes(center, routeOverviewPerRegionLimit);
    if (recommended.length >= routeOverviewPerRegionLimit) {
      return _RouteOverviewRegionResult(routes: recommended, isComplete: true);
    }

    final segmentFetcher = _routeMapSegmentFetcher;
    if (segmentFetcher == null && fetcher != null) {
      return _RouteOverviewRegionResult(routes: recommended, isComplete: true);
    }
    try {
      final mapSegments = segmentFetcher != null
          ? await segmentFetcher(center, routeOverviewPerRegionLimit)
          : await SupabaseService().fetchMapSegments(
              center.lat,
              center.lng,
              routeFieldRadiusKm.toDouble(),
              maxResults: routeOverviewPerRegionLimit,
              throwOnFailure: true,
            );
      return _RouteOverviewRegionResult(
        routes: mergeRouteOverviewFields([
          recommended,
          mapSegments,
        ], limit: routeOverviewPerRegionLimit),
        isComplete: true,
      );
    } catch (_) {
      return _RouteOverviewRegionResult(routes: recommended, isComplete: false);
    }
  }

  Future<int?> _ensureCatalogEpoch() {
    return _catalogEpochValidation ??= () async {
      final previousEpoch = _validatedCatalogEpoch;
      try {
        final fetcher = _routeCatalogEpochFetcher;
        final epoch = fetcher != null
            ? await fetcher()
            : await SupabaseService().fetchRouteCatalogEpoch();
        if (epoch < 0) {
          _validatedCatalogEpoch = null;
          _catalogAttempted = false;
          if (previousEpoch != null) _removeGeneratedRoutes();
          return null;
        }
        if (previousEpoch != null && previousEpoch != epoch) {
          _catalogAttempted = false;
          _removeGeneratedRoutes();
        }
        _validatedCatalogEpoch = epoch;
        return epoch;
      } catch (error) {
        _validatedCatalogEpoch = null;
        _catalogAttempted = false;
        if (previousEpoch != null) _removeGeneratedRoutes();
        if (kDebugMode) {
          debugPrint(
            '[RouteService] catalog epoch failed: ${error.runtimeType}',
          );
        }
        return null;
      }
    }();
  }

  Future<List<RevvRoute>> _validatedCachedRoutes(
    List<RevvRoute> cachedRoutes,
    int? cachedEpoch,
  ) async {
    if (!cachedRoutes.any((route) => route.isGenerated)) {
      return cachedRoutes;
    }
    final onlineEpoch = await _ensureCatalogEpoch();
    if (onlineEpoch == null || cachedEpoch != onlineEpoch) {
      return cachedRoutes
          .where((route) => !route.isGenerated)
          .toList(growable: false);
    }
    return _routesAllowedForEpoch(cachedRoutes, onlineEpoch);
  }

  List<RevvRoute> _routesAllowedForEpoch(
    Iterable<RevvRoute> candidates,
    int epoch,
  ) {
    return candidates
        .where((route) => !route.isGenerated || route.catalogEpoch == epoch)
        .take(routeFieldFetchLimit)
        .toList(growable: false);
  }

  Future<List<RevvRoute>> _fetchLocalRoutes(
    LatLng center,
    int maxResults, {
    double? radiusKm,
  }) async {
    final boundedResults = maxResults.clamp(1, routeFieldInitialFetchLimit);
    final requestRadiusKm = radiusKm ?? routeFieldRadiusKm.toDouble();
    final epoch = await _ensureCatalogEpoch();
    try {
      final fetcher = _routeLocalV2Fetcher;
      final routes = fetcher != null
          ? await fetcher(center, boundedResults)
          : await SupabaseService().fetchNearbyRoutesV2(
              center.lat,
              center.lng,
              requestRadiusKm,
              maxResults: boundedResults,
            );
      final accepted = epoch == null
          ? routes
                .where((route) => !route.isGenerated)
                .take(boundedResults)
                .toList(growable: false)
          : _routesAllowedForEpoch(
              routes,
              epoch,
            ).take(boundedResults).toList(growable: false);
      if (accepted.isNotEmpty) return accepted;
    } catch (_) {}
    try {
      final fallback = _routeLegacyFetcher;
      final routes = fallback != null
          ? await fallback(center, boundedResults)
          : await SupabaseService().fetchNearbyRoutes(
              center.lat,
              center.lng,
              requestRadiusKm,
            );
      final accepted = routes
          .where((route) => !route.isGenerated)
          .take(boundedResults)
          .toList(growable: false);
      if (accepted.isNotEmpty) return accepted;
    } catch (_) {}
    final directFetcher = _routeLegacyDirectFetcher;
    final routes = directFetcher != null
        ? await directFetcher(center, boundedResults)
        : await SupabaseService().fetchNearbyRoutesDirect(
            center.lat,
            center.lng,
            requestRadiusKm,
            limit: requestRadiusKm >= 160
                ? routeFieldFetchLimit
                : requestRadiusKm >= 100
                ? 400
                : 250,
          );
    return routes
        .where((route) => !route.isGenerated)
        .take(boundedResults)
        .toList(growable: false);
  }

  Future<void> fetchRoutes(double lat, double lng) async {
    _catalogEpochValidation = null;
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
      var candidates = await _fetchLocalRoutes(
        point,
        routeFieldInitialFetchLimit,
        radiusKm: radiusKm.toDouble(),
      );
      lastCloudCandidateCount = candidates.length;

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
      if (token == _fetchToken && !_disposed) {
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
      var candidates = await _fetchLocalRoutes(
        point,
        routeFieldInitialFetchLimit,
      );
      lastCloudCandidateCount = candidates.length;

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
      if (token == _fetchToken && !_disposed) {
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

  @override
  void dispose() {
    _disposed = true;
    _fetchToken++;
    _overviewFetchToken++;
    super.dispose();
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
    _overviewRegionHadRoutes.clear();
    _catalogEpochValidation = null;
    _validatedCatalogEpoch = null;
    _catalogAttempted = false;
    _overviewCacheRestored = false;
    routeOverviewLoaded = false;
    rawCandidateRoutes = [];
    mapVisualRoutes = [];
    routes = [];
    selectedRoute = null;
    routeFieldCenter = null;
    routeFieldFetchedAt = null;
    routeFieldFromCache = false;
    routeDataSourceLabel = '초기화됨';
    routeFieldGeneration++;
    notifyListeners();
  }

  void _removeGeneratedRoutes() {
    _overviewRoutes = _overviewRoutes
        .where((route) => !route.isGenerated)
        .toList(growable: false);
    rawCandidateRoutes = rawCandidateRoutes
        .where((route) => !route.isGenerated)
        .toList(growable: false);
    _rebuildRecommendations();
    _refreshMapVisualRoutes();
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
    routeFieldGeneration++;
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
    final hydrated = await hydrateRouteNodes(route);
    if (hydrated.nodes.isEmpty || selectedRoute?.id != route.id) return;
    selectedRoute = hydrated;
    routes = [
      for (final item in routes) item.id == hydrated.id ? hydrated : item,
    ];
    routeFieldGeneration++;
    notifyListeners();
  }

  Future<RevvRoute> hydrateRouteNodes(RevvRoute route) async {
    if (route.nodes.isNotEmpty) return route;
    try {
      final fetcher = _routeNodeV2Fetcher;
      final nodes = fetcher != null
          ? await fetcher(route.id)
          : await SupabaseService().fetchRouteNodesV2(route.id);
      if (nodes.isNotEmpty) return route.copyWith(nodes: nodes);
    } catch (_) {
      // Generated routes must never cross the legacy direct-select boundary.
    }
    if (route.isGenerated) return route;
    final fallback = _routeLegacyNodeFetcher;
    final nodes = fallback != null
        ? await fallback(route.id)
        : await SupabaseService().fetchRouteNodes(route.id);
    return nodes.isEmpty ? route : route.copyWith(nodes: nodes);
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
          'version': 3,
          'centerLat': center.lat,
          'centerLng': center.lng,
          'radiusKm': radiusKm,
          'fetchedAt': DateTime.now().toIso8601String(),
          if (_validatedCatalogEpoch != null)
            'catalogEpoch': _validatedCatalogEpoch,
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
      final decodedRoutes = ((decoded['routes'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RevvRoute.fromJson)
          .toList();
      final catalogEpoch = (decoded['catalogEpoch'] as num?)?.toInt();
      final routes = await _validatedCachedRoutes(decodedRoutes, catalogEpoch);
      if (routes.isEmpty) return null;

      final cache = _RouteFieldCache(
        center: center,
        radiusKm: radiusKm,
        fetchedAt: fetchedAt,
        routes: routes,
        catalogEpoch: catalogEpoch,
      );
      if (!_isRouteFieldCacheUsable(cache, target, ignoreTtl: ignoreTtl)) {
        return null;
      }
      return cache;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RouteService] cache load failed: ${e.runtimeType}');
      }
      return null;
    }
  }

  bool _isRouteFieldCacheUsable(
    _RouteFieldCache cache,
    LatLng target, {
    bool ignoreTtl = false,
  }) => isRouteFieldCacheReusable(
    cacheCenter: cache.center,
    targetCenter: target,
    cacheRadiusKm: cache.radiusKm,
    requiredRadiusKm: routeFieldRadiusKm,
    fetchedAt: cache.fetchedAt,
    now: DateTime.now(),
    maxAge: routeFieldCacheTtl,
    maxCenterDistanceKm: routeFieldCacheReuseKm,
    ignoreAge: ignoreTtl,
  );

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
  final int? catalogEpoch;

  const _RouteFieldCache({
    required this.center,
    required this.radiusKm,
    required this.fetchedAt,
    required this.routes,
    this.catalogEpoch,
  });
}
