import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';
import 'waypoint_optimizer.dart';

class RouteService extends ChangeNotifier {
  List<RevvRoute> routes = [];
  RevvRoute? selectedRoute;
  bool isLoading = false;
  String? errorMessage;
  int searchRadiusKm = 50; // 기본 50km

  // 연결 루트 (선택 루트 끝점 기준)
  List<RevvRoute> connectingRoutes = [];
  bool isLoadingConnecting = false;

  LatLng? _lastFetchLocation;
  int? _lastFetchRadius;

  // ── Sprint 요청 ────────────────────────────────────────────
  bool sprintRequested = false;
  void requestSprint() {
    sprintRequested = true;
    notifyListeners();
  }
  void clearSprintRequest() {
    sprintRequested = false;
    // notifyListeners 생략 — 이미 처리됨
  }

  void resetCache() {
    _lastFetchLocation = null;
    _lastFetchRadius = null;
  }

  /// 반경 변경 후 재검색
  Future<void> changeRadius(int radiusKm, double lat, double lng) async {
    searchRadiusKm = radiusKm;
    resetCache();
    // 즉시 기존 결과 초기화 → 로딩 UI 표시
    routes = [];
    selectedRoute = null;
    notifyListeners();
    await fetchRoutes(lat, lng);
  }

  Future<void> fetchRoutes(double lat, double lng) async {
    if (_lastFetchLocation != null && _lastFetchRadius == searchRadiusKm) {
      final dist = RevvRoute.haversineKm(_lastFetchLocation!, LatLng(lat, lng));
      if (dist < 10) return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _fetchAndScore(lat, lng, searchRadiusKm * 1000);
      routes = result;
      selectedRoute = routes.isNotEmpty ? routes.first : null;
      _lastFetchLocation = LatLng(lat, lng);
      _lastFetchRadius = searchRadiusKm;
      debugPrint('[RouteService] 선택된 루트: ${routes.length}개');
      // 오프라인 캐시 저장
      _saveToCache(result, lat, lng);
    } catch (e, st) {
      debugPrint('[RouteService] 예외: $e\n$st');
      // 오프라인 캐시에서 복원 시도
      final cached = await _loadFromCache();
      if (cached != null && cached.isNotEmpty) {
        routes = cached;
        selectedRoute = routes.first;
        errorMessage = '오프라인 모드 — 마지막 검색 결과를 표시합니다';
        debugPrint('[RouteService] 오프라인 캐시 복원: ${routes.length}개');
      } else {
        errorMessage = '네트워크 오류가 발생했어요. 인터넷 연결을 확인하세요.';
      }
    }

    isLoading = false;
    notifyListeners();
  }

  // ─── 오프라인 캐시 ───────────────────────────────────────────────
  static const _cacheKey = 'revv_route_cache';
  static const _cachePosKey = 'revv_route_cache_pos';

  Future<void> _saveToCache(List<RevvRoute> rs, double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, RevvRoute.listToJson(rs));
      await prefs.setString(_cachePosKey, '$lat,$lng');
    } catch (e) {
      debugPrint('[RouteService] 캐시 저장 실패: $e');
    }
  }

  Future<List<RevvRoute>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      return RevvRoute.listFromJson(raw);
    } catch (e) {
      debugPrint('[RouteService] 캐시 로드 실패: $e');
      return null;
    }
  }

  /// 선택 루트 끝점 기준 연결 루트 검색 (15km 반경)
  Future<void> fetchConnectingRoutes(RevvRoute fromRoute) async {
    final endpoint = fromRoute.nodes.last;
    isLoadingConnecting = true;
    connectingRoutes = [];
    notifyListeners();

    try {
      final all = await _fetchAndScore(endpoint.lat, endpoint.lng, 15000);
      // 현재 선택 루트는 제외, 상위 5개
      connectingRoutes = all
          .where((r) => r.id != fromRoute.id)
          .take(5)
          .toList();
      debugPrint('[RouteService] 연결 루트: ${connectingRoutes.length}개');
    } catch (e) {
      debugPrint('[RouteService] fetchConnectingRoutes 오류: $e');
    }

    isLoadingConnecting = false;
    notifyListeners();
  }

  /// 공통 Overpass 조회 + 커브 스코어링 → RevvRoute 리스트 반환
  Future<List<RevvRoute>> _fetchAndScore(double lat, double lng, int radiusM) async {
    // primary도 추가 — 캐나다 일부 구간은 1차선 primary가 와인딩 명소
    final query = '''
[out:json][timeout:35];
(
  way["highway"="primary"](around:$radiusM,$lat,$lng);
  way["highway"="secondary"](around:$radiusM,$lat,$lng);
  way["highway"="tertiary"](around:$radiusM,$lat,$lng);
  way["highway"="unclassified"](around:$radiusM,$lat,$lng);
);
out geom qt;
(
  node["highway"="traffic_signals"](around:$radiusM,$lat,$lng);
  node["highway"="stop"](around:$radiusM,$lat,$lng);
);
out qt;
''';

    debugPrint('[RouteService] _fetchAndScore ($lat, $lng, r=${radiusM}m)');

    final endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    ];

    http.Response? res;
    for (final url in endpoints) {
      try {
        final r = await http.post(
          Uri.parse(url),
          body: {'data': query},
        ).timeout(const Duration(seconds: 35));
        if (r.statusCode == 200) { res = r; break; }
        debugPrint('[RouteService] $url → ${r.statusCode}');
      } catch (e) {
        debugPrint('[RouteService] $url 실패: $e');
      }
    }

    if (res == null) return [];

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final elements = data['elements'] as List;
    final userPos = LatLng(lat, lng);
    final rawWays = <_RawWay>[];
    final intersectionNodes = <LatLng>[];

    for (final el in elements) {
      if (el['type'] == 'node') {
        intersectionNodes.add(LatLng(
          (el['lat'] as num).toDouble(),
          (el['lon'] as num).toDouble(),
        ));
      } else if (el['type'] == 'way') {
        final geom = el['geometry'] as List?;
        if (geom == null || geom.length < 10) continue;
        final nodes = geom
            .map((g) => LatLng(
                (g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()))
            .toList();
        final sampled = nodes.length > 200 ? _sampleNodes(nodes, 200) : nodes;
        final name = el['tags']?['name'] as String? ?? '';
        final highway = el['tags']?['highway'] as String? ?? 'secondary';
        final id = el['id'].toString();
        rawWays.add(_RawWay(id: id, name: name, nodes: sampled, highwayType: highway));
      }
    }

    debugPrint('[RouteService] ways: ${rawWays.length}개, 교차로: ${intersectionNodes.length}개');
    // Way Stitching — 인접 도로 조각을 하나의 연속 루트로 이어붙임
    final stitched = _stitchWays(rawWays);
    debugPrint('[RouteService] 스티칭 후: ${stitched.length}개');
    return _selectTopRoutes(stitched, userPos, intersectionNodes);
  }

  // ─── Way Stitching ──────────────────────────────────────────────
  // 인접한 way들의 끝점이 150m 이내면 하나의 연속 루트로 이어붙임
  // → 실제 드라이빙 루트는 여러 way 조각으로 구성되므로 이어붙이면 훨씬 자연스러움
  static const _stitchThresholdKm = 0.15; // 150m

  List<_RawWay> _stitchWays(List<_RawWay> ways) {
    final used = <String>{};
    final result = <_RawWay>[];

    for (final seed in ways) {
      if (used.contains(seed.id)) continue;
      used.add(seed.id);

      var chain = seed.nodes.toList();
      final chainId = seed.id;
      var chainName = seed.name;
      var chainHighway = seed.highwayType;

      // 앞뒤로 연결 가능한 way를 반복 탐색
      bool extended = true;
      while (extended) {
        extended = false;
        for (final other in ways) {
          if (used.contains(other.id)) continue;

          final chainEnd = chain.last;
          final chainStart = chain.first;

          if (RevvRoute.haversineKm(chainEnd, other.nodes.first) < _stitchThresholdKm) {
            // 체인 끝 → other 시작
            chain.addAll(other.nodes.skip(1));
            used.add(other.id);
            if (chainName.isEmpty) chainName = other.name;
            extended = true;
            break;
          } else if (RevvRoute.haversineKm(chainEnd, other.nodes.last) < _stitchThresholdKm) {
            // 체인 끝 → other 끝 (other 뒤집기)
            chain.addAll(other.nodes.reversed.skip(1));
            used.add(other.id);
            if (chainName.isEmpty) chainName = other.name;
            extended = true;
            break;
          } else if (RevvRoute.haversineKm(chainStart, other.nodes.last) < _stitchThresholdKm) {
            // other 끝 → 체인 앞
            chain = [...other.nodes, ...chain.skip(1)];
            used.add(other.id);
            if (chainName.isEmpty) chainName = other.name;
            extended = true;
            break;
          } else if (RevvRoute.haversineKm(chainStart, other.nodes.first) < _stitchThresholdKm) {
            // other 시작 → 체인 앞 (other 뒤집기)
            chain = [...other.nodes.reversed.toList(), ...chain.skip(1)];
            used.add(other.id);
            if (chainName.isEmpty) chainName = other.name;
            extended = true;
            break;
          }
        }
      }

      final sampled = chain.length > 300 ? _sampleNodes(chain, 300) : chain;
      result.add(_RawWay(
        id: chainId,
        name: chainName,
        nodes: sampled,
        highwayType: chainHighway,
      ));
    }

    return result;
  }

  // ─── 루프 감지 ───────────────────────────────────────────────────
  // 시작점과 끝점이 3km 이내면 루프 루트 — 돌아올 걱정 없어서 편안함
  bool _isLoop(List<LatLng> nodes) {
    if (nodes.length < 10) return false;
    return RevvRoute.haversineKm(nodes.first, nodes.last) < 3.0;
  }

  // ─── 거리 패널티 ─────────────────────────────────────────────────
  // 가까운 루트를 약간 우대. 너무 먼 루트는 현실적으로 부담스러움.
  // 15km 이내: 패널티 없음 / 15~60km: 선형 감소 / 60km 초과: 0.55배
  double _distancePenalty(double distFromUserKm) {
    if (distFromUserKm <= 15) return 1.0;
    if (distFromUserKm >= 60) return 0.55;
    return 1.0 - (distFromUserKm - 15) / 45 * 0.45;
  }

  List<LatLng> _sampleNodes(List<LatLng> nodes, int target) {
    final step = nodes.length / target;
    return List.generate(target, (i) => nodes[(i * step).floor()]);
  }

  List<RevvRoute> _selectTopRoutes(
      List<_RawWay> ways, LatLng userPos, List<LatLng> intersections) {
    final scored = <_ScoredWay>[];

    for (final way in ways) {
      final dist = _totalDistance(way.nodes);
      if (dist < 5.0) continue;

      final curves = _analyzeCurves(way.nodes);

      // ── 품질 필터 ─────────────────────────────────────────────
      // 최소 연속 와인딩 1.5km 미달 탈락
      if (curves.maxContinuousKm < 1.5) continue;

      // 커브 밀도: (tight×2 + med×1) / totalKm
      // 0.4 미만 = 전체의 40% 이하가 커브 → 직선 위주 탈락
      final curveScore = curves.tightKm * 2 + curves.mediumKm;
      final curveRatio = curveScore / dist;
      if (curveRatio < 0.4) continue;

      // ── 점수 계산 ─────────────────────────────────────────────
      // 밀도 × √거리: 꼬불꼬불한 비율이 높고 적당히 긴 도로 우선
      final continuityBonus = 1.0 + (curves.maxContinuousKm / dist) * 0.6;
      final intersectCount = _countNearbyIntersections(way.nodes, intersections);
      final intersectPenalty = _intersectionPenalty(intersectCount, dist);
      final roadMultiplier = _roadMultiplier(way.highwayType);
      // 루프 루트 보너스: 출발점으로 돌아오는 루트 → 더 편안함
      final loopBonus = _isLoop(way.nodes) ? 1.25 : 1.0;
      // 거리 패널티: 너무 먼 루트는 살짝 하향
      final distPenalty = _distancePenalty(
          RevvRoute.haversineKm(userPos, way.nodes.first));

      final score = curveRatio * math.sqrt(dist) *
          continuityBonus * intersectPenalty * roadMultiplier *
          loopBonus * distPenalty;

      scored.add(_ScoredWay(
        way: way,
        score: score,
        distKm: dist,
        center: _centerPoint(way.nodes),
        distFromUser: RevvRoute.haversineKm(userPos, way.nodes.first),
        curves: curves,
        isLoop: _isLoop(way.nodes),
      ));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    debugPrint('[RouteService] 필터 후 후보: ${scored.length}개');

    // ── 방향 다양성 선택 (Climoto 스타일) ────────────────────────
    // 360°를 45° 단위 8개 섹터로 나눠 각 방향의 최고 루트 우선 선택
    // → 북/북동/동/남동/남/남서/서/북서 방향 균등 분포
    const sectorCount = 8;
    final sectors = List<List<_ScoredWay>>.generate(sectorCount, (_) => []);
    for (final s in scored) {
      final bearing = _bearingDegTo(userPos, s.center);
      final idx = (bearing / (360 / sectorCount)).floor() % sectorCount;
      sectors[idx].add(s);
    }

    final selected = <_ScoredWay>[];

    bool isTooClose(_ScoredWay candidate) => selected.any(
        (sel) => RevvRoute.haversineKm(candidate.center, sel.center) < 6);

    // 1라운드: 각 섹터 1등 (이미 선택된 것과 6km 이상 떨어진 것만)
    for (final sector in sectors) {
      for (final candidate in sector) {
        if (!isTooClose(candidate)) { selected.add(candidate); break; }
      }
    }
    // 2라운드: 6km 간격 유지하며 나머지 채우기
    for (final s in scored) {
      if (selected.length >= 10) break;
      if (!selected.contains(s) && !isTooClose(s)) selected.add(s);
    }
    // 점수순 재정렬
    selected.sort((a, b) => b.score.compareTo(a.score));

    return selected.map((s) {
      final name = s.way.name.isNotEmpty
          ? s.way.name
          : RevvRoute.autoName(s.score);
      return RevvRoute(
        id: s.way.id,
        name: name,
        nodes: s.way.nodes,
        distanceKm: s.distKm,
        windingScore: s.score,
        starRating: RevvRoute.toStarRating(s.score),
        sharpCurveCount: 0,
        centerPoint: s.center,
        distanceFromUser: s.distFromUser,
        tightCurveKm: s.curves.tightKm,
        mediumCurveKm: s.curves.mediumKm,
        maxContinuousKm: s.curves.maxContinuousKm,
        isLoop: s.isLoop,
      );
    }).toList();
  }

  // ─── 방향변화율 기반 곡률 분석 ────────────────────────────────
  // deg/km 단위 → 노드 밀도에 무관하게 실제 커브 타이트함 반영

  /// 연속 3점의 방향변화율 (도/km)
  double _curvatureRateDegPerKm(LatLng a, LatLng b, LatLng c) {
    final d1 = RevvRoute.haversineKm(a, b);
    final d2 = RevvRoute.haversineKm(b, c);
    final pathLen = (d1 + d2) / 2;
    if (pathLen < 0.0001) return 0;
    return _bearingDiff(a, b, c) / pathLen;
  }

  double _bearingDiff(LatLng a, LatLng b, LatLng c) {
    final b1 = _bearing(a, b);
    final b2 = _bearing(b, c);
    double diff = (b2 - b1).abs();
    if (diff > 180) diff = 360 - diff;
    return diff;
  }

  double _bearing(LatLng from, LatLng to) {
    final lat1 = _rad(from.lat);
    final lat2 = _rad(to.lat);
    final dLng = _rad(to.lng - from.lng);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return math.atan2(y, x) * 180 / math.pi;
  }

  _CurveResult _analyzeCurves(List<LatLng> nodes) {
    double tightKm = 0;
    double mediumKm = 0;
    double currentContinuousKm = 0;
    double maxContinuousKm = 0;
    double straightAccum = 0;

    for (int i = 0; i < nodes.length - 2; i++) {
      final segLen = RevvRoute.haversineKm(nodes[i + 1], nodes[i + 2]);
      // deg/km: 200+ = 타이트, 50~200 = 미디엄, <50 = 직선
      final rate = _curvatureRateDegPerKm(nodes[i], nodes[i + 1], nodes[i + 2]);

      if (rate >= 200) {
        tightKm += segLen;
        currentContinuousKm += segLen;
        straightAccum = 0;
      } else if (rate >= 50) {
        mediumKm += segLen;
        currentContinuousKm += segLen;
        straightAccum = 0;
      } else {
        straightAccum += segLen;
        if (straightAccum >= 0.3) {
          // 300m 직선 → 연속성 리셋 (기존 500m보다 엄격)
          if (currentContinuousKm > maxContinuousKm) maxContinuousKm = currentContinuousKm;
          currentContinuousKm = 0;
          straightAccum = 0;
        }
      }
    }
    if (currentContinuousKm > maxContinuousKm) maxContinuousKm = currentContinuousKm;

    return _CurveResult(
      tightKm: tightKm,
      mediumKm: mediumKm,
      maxContinuousKm: maxContinuousKm,
    );
  }

  // ─── 교차로 밀도 페널티 ─────────────────────────────────────────

  int _countNearbyIntersections(List<LatLng> wayNodes, List<LatLng> intersections) {
    if (intersections.isEmpty) return 0;
    double minLat = wayNodes[0].lat, maxLat = wayNodes[0].lat;
    double minLng = wayNodes[0].lng, maxLng = wayNodes[0].lng;
    for (final n in wayNodes) {
      if (n.lat < minLat) minLat = n.lat;
      if (n.lat > maxLat) maxLat = n.lat;
      if (n.lng < minLng) minLng = n.lng;
      if (n.lng > maxLng) maxLng = n.lng;
    }
    const buf = 0.001;
    minLat -= buf; maxLat += buf;
    minLng -= buf; maxLng += buf;
    int count = 0;
    for (final n in intersections) {
      if (n.lat >= minLat && n.lat <= maxLat &&
          n.lng >= minLng && n.lng <= maxLng) count++;
    }
    return count;
  }

  double _intersectionPenalty(int count, double distKm) {
    if (distKm <= 0) return 1.0;
    final perKm = count / distKm;
    if (perKm >= 3.0) return 0.6;
    if (perKm >= 2.0) return 0.7;
    return 1.0;
  }

  // ─── 도로 등급 가중치 ───────────────────────────────────────────

  double _roadMultiplier(String highway) {
    switch (highway) {
      case 'secondary':    return 1.3;
      case 'tertiary':     return 1.2;
      case 'unclassified': return 1.0;
      case 'primary':      return 0.7;
      case 'residential':  return 0.5;
      default:             return 1.0;
    }
  }

  // ─── 유틸 ───────────────────────────────────────────────────────

  double _totalDistance(List<LatLng> nodes) {
    double total = 0;
    for (int i = 0; i < nodes.length - 1; i++) {
      total += RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
    }
    return total;
  }

  LatLng _centerPoint(List<LatLng> nodes) {
    final lat = nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length;
    final lng = nodes.map((n) => n.lng).reduce((a, b) => a + b) / nodes.length;
    return LatLng(lat, lng);
  }

  double _rad(double deg) => deg * math.pi / 180;

  /// from → to 방위각 (0~360°, 북=0)
  double _bearingDegTo(LatLng from, LatLng to) {
    final lat1 = _rad(from.lat);
    final lat2 = _rad(to.lat);
    final dLng = _rad(to.lng - from.lng);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void selectRoute(RevvRoute route) {
    if (!routes.any((r) => r.id == route.id)) {
      routes = [route, ...routes];
    }
    selectedRoute = route;
    connectingRoutes = [];
    notifyListeners();
    // 끝점 기준 연결 루트 비동기 검색
    fetchConnectingRoutes(route);
  }

  // ── 경유지 최적화 ──────────────────────────────────────────────

  bool isOptimizing = false;
  OptimizedRoute? lastOptimized;

  /// 선택된 여러 와인딩 구간을 최적 순서로 연결하는 경로를 계산한다.
  ///
  /// [userPos]   : 현재 위치 (출발지)
  /// [segments]  : 반드시 통과할 RevvRoute 목록
  /// [returnHome]: 마지막 구간 후 출발지 복귀 여부
  Future<OptimizedRoute?> optimizeWaypoints({
    required LatLng userPos,
    required List<RevvRoute> segments,
    bool returnHome = false,
  }) async {
    if (segments.isEmpty) return null;

    isOptimizing = true;
    lastOptimized = null;
    notifyListeners();

    try {
      final result = await WaypointOptimizer.optimize(
        userPos: userPos,
        segments: segments,
        returnHome: returnHome,
      );
      lastOptimized = result;
      return result;
    } catch (e) {
      debugPrint('[RouteService] optimizeWaypoints 오류: $e');
      return null;
    } finally {
      isOptimizing = false;
      notifyListeners();
    }
  }
}

// ─── 내부 클래스 ──────────────────────────────────────────────────

class _CurveResult {
  final double tightKm;
  final double mediumKm;
  final double maxContinuousKm;
  const _CurveResult({
    required this.tightKm,
    required this.mediumKm,
    required this.maxContinuousKm,
  });
}

class _RawWay {
  final String id;
  final String name;
  final List<LatLng> nodes;
  final String highwayType;
  _RawWay({required this.id, required this.name, required this.nodes, required this.highwayType});
}

class _ScoredWay {
  final _RawWay way;
  final double score;
  final double distKm;
  final LatLng center;
  final double distFromUser;
  final _CurveResult curves;
  final bool isLoop;
  _ScoredWay({
    required this.way,
    required this.score,
    required this.distKm,
    required this.center,
    required this.distFromUser,
    required this.curves,
    this.isLoop = false,
  });
}
