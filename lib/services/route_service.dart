import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/revv_route.dart';
import 'route_loading_policy.dart';
import 'supabase_service.dart';

enum SprintStartMode { auto, guideToStart, joinFromCurrent }

class RouteService extends ChangeNotifier {
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
  int searchRadiusKm = 50;
  int visibleRouteLimit = defaultVisibleRoutes;

  bool sprintRequested = false;
  SprintStartMode sprintStartMode = SprintStartMode.auto;
  RevvRoute? sprintRoute;

  int _fetchToken = 0;

  RevvRoute? get effectiveSprintRoute => sprintRoute ?? selectedRoute;

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
    await fetchRoutes(lat, lng);
  }

  Future<void> fetchRoutes(double lat, double lng) async {
    final token = ++_fetchToken;
    isLoading = true;
    isLoadingInitial = routes.isEmpty;
    errorMessage = null;
    routeSuggestionMessage = null;
    backgroundStatusMessage = '주변 루트를 찾는 중';
    routeDataStatusTitle = '루트 탐색 중';
    routeDataStatusBody = '현재 위치 기준 ${searchRadiusKm}km 안에서 후보를 불러옵니다.';
    notifyListeners();

    try {
      final cloud = SupabaseService();
      final cloudReady = cloud.isCloudAvailable;
      var candidates = await cloud.fetchNearbyRoutes(
        lat,
        lng,
        searchRadiusKm.toDouble(),
      );
      lastCloudCandidateCount = candidates.length;

      if (candidates.isEmpty) {
        candidates = await cloud.fetchNearbyRoutesDirect(
          lat,
          lng,
          searchRadiusKm.toDouble(),
          limit: 160,
        );
      }

      if (candidates.isEmpty) {
        candidates = await _loadFromCache() ?? const [];
        routeDataSourceLabel = candidates.isEmpty ? '루트 없음' : '로컬 캐시';
      } else {
        routeDataSourceLabel = 'Supabase';
      }

      if (token != _fetchToken) return;

      final visible = _prepareVisibleRoutes(candidates);
      lastUsableCloudRouteCount = visible.length;
      routes = visible;
      selectedRoute = visible.isNotEmpty ? visible.first : null;
      debugPrint(
        '[RouteService] route pool '
        'radius=${searchRadiusKm}km '
        'raw=${candidates.length} '
        'filtered=$lastFilteredRouteCount '
        'visible=${visible.length}/$visibleRouteLimit',
      );

      if (visible.isEmpty) {
        if (!cloudReady) {
          errorMessage = '클라우드 설정이 필요해요';
          routeDataStatusTitle = '클라우드 설정 없음';
          routeDataStatusBody =
              cloud.lastFailureReason ?? 'Supabase URL과 anon key를 확인해 주세요.';
        } else if (cloud.lastFailureReason != null) {
          errorMessage = '네트워크 연결을 확인해 주세요';
          routeDataStatusTitle = '루트 로드 실패';
          routeDataStatusBody = '클라우드 요청이 실패했어요. 연결 상태를 확인한 뒤 다시 시도해 주세요.';
        } else {
          errorMessage = '주변 루트를 찾지 못했어요';
          routeDataStatusTitle = '루트 후보 없음';
          routeDataStatusBody = '검색 반경을 넓히거나 위치를 옮겨 다시 찾아보세요.';
        }
      } else {
        errorMessage = null;
        routeSuggestionMessage = visible.length < 8 && searchRadiusKm < 100
            ? '후보가 적어요. 반경을 100km로 넓혀볼까요?'
            : null;
        routeDataStatusTitle = '루트 준비 완료';
        routeDataStatusBody = '${visible.length}개 후보를 불러왔어요.';
        unawaited(_saveToCache(visible));
        unawaited(_hydrateSelectedRouteNodes());
      }
    } catch (e) {
      if (token != _fetchToken) return;
      final cached = await _loadFromCache();
      if (cached != null && cached.isNotEmpty) {
        routes = _prepareVisibleRoutes(cached);
        selectedRoute = routes.isEmpty ? null : routes.first;
        debugPrint(
          '[RouteService] cached route pool '
          'radius=${searchRadiusKm}km '
          'filtered=$lastFilteredRouteCount '
          'visible=${routes.length}/$visibleRouteLimit',
        );
        routeDataSourceLabel = '로컬 캐시';
        errorMessage = null;
        routeSuggestionMessage = routes.length < 8 && searchRadiusKm < 100
            ? '후보가 적어요. 반경을 100km로 넓혀볼까요?'
            : null;
        routeDataStatusTitle = '캐시 사용 중';
        routeDataStatusBody = '네트워크 실패로 마지막 루트 목록을 사용합니다.';
      } else {
        errorMessage = '루트를 불러오지 못했어요';
        routeSuggestionMessage = null;
        routeDataStatusTitle = '루트 로드 실패';
        routeDataStatusBody = '네트워크 또는 Supabase 설정을 확인해 주세요.';
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
    routes = [];
    selectedRoute = null;
    routeDataSourceLabel = '초기화됨';
    notifyListeners();
  }

  List<RevvRoute> _prepareVisibleRoutes(List<RevvRoute> candidates) {
    final unique = <String, RevvRoute>{};
    for (final route in candidates) {
      unique[route.id] = route;
    }
    final filtered = unique.values
        .where((route) => route.distanceKm >= 3.0)
        .where((route) => route.qualityRejectReason == null)
        .toList();
    lastFilteredRouteCount = filtered.length;
    return diversifyRouteSlots(filtered, limit: visibleRouteLimit);
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

  Future<void> _saveToCache(List<RevvRoute> routes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageKeys.routeCache,
        RevvRoute.listToJson(routes),
      );
    } catch (e) {
      debugPrint('[RouteService] cache save failed: $e');
    }
  }

  Future<List<RevvRoute>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(StorageKeys.routeCache);
      if (raw == null || raw.isEmpty) return null;
      return RevvRoute.listFromJson(raw);
    } catch (e) {
      debugPrint('[RouteService] cache load failed: $e');
      return null;
    }
  }
}
