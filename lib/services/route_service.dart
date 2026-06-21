import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';
import 'waypoint_optimizer.dart';

// ─── compute() isolate 파라미터 ───────────────────────────────────
// 메인 스레드 → isolate 전달 데이터 (모두 primitive)
class _IsolateParams {
  final String jsonBody;
  final double lat;
  final double lng;
  const _IsolateParams(this.jsonBody, this.lat, this.lng);
}

// ─── Top-level 처리 함수 (isolate에서 실행) ────────────────────────
// compute()는 top-level 함수만 받음 — 인스턴스 메서드 불가
List<RevvRoute> _processRoutes(_IsolateParams p) {
  final data = jsonDecode(p.jsonBody) as Map<String, dynamic>;
  final elements = data['elements'] as List;
  final userPos = LatLng(p.lat, p.lng);
  final rawWays = <_RawWay>[];
  final intersectionNodes = <LatLng>[];
  final signalNodes = <LatLng>[];

  for (final el in elements) {
    if (el['type'] == 'node') {
      final highway = el['tags']?['highway'] as String? ?? '';
      final pos = LatLng(
        (el['lat'] as num).toDouble(),
        (el['lon'] as num).toDouble(),
      );
      if (highway == 'traffic_signals' || highway == 'stop') {
        signalNodes.add(pos);
      } else {
        intersectionNodes.add(pos);
      }
    } else if (el['type'] == 'way') {
      final geom = el['geometry'] as List?;
      if (geom == null || geom.length < 10) continue;
      final nodes = geom
          .map((g) => LatLng(
              (g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()))
          .toList();
      final sampled = nodes.length > 200 ? _sampleNodes(nodes, 200) : nodes;
      final name = el['tags']?['name'] as String? ?? '';
      if (_isUrbanName(name)) continue; // 교외 boulevard/avenue/rue 제외
      final highway = el['tags']?['highway'] as String? ?? 'secondary';
      final id = el['id'].toString();
      rawWays.add(_RawWay(id: id, name: name, nodes: sampled, highwayType: highway));
    }
  }

  // Way Stitching — 인접 도로 조각을 하나의 연속 루트로 이어붙임
  final stitched = _stitchWays(rawWays);
  debugPrint('[RouteService] 신호/정지 노드: ${signalNodes.length}개');
  return _selectTopRoutes(stitched, userPos, intersectionNodes, signalNodes);
}

// ─── Top-level 헬퍼 함수들 ───────────────────────────────────────
// (compute isolate에서 호출되므로 클래스 외부에 위치해야 함)

const _stitchThresholdKm = 0.15; // 150m

// 도심/교외 도로 이름 필터 — Boulevard, Avenue, Rue 등은 시가지 특징
bool _isUrbanName(String name) {
  final l = name.toLowerCase();
  return l.startsWith('boulevard ') ||
      l.startsWith('blvd ') ||
      l.startsWith('avenue ') ||
      l.startsWith('ave ') ||
      l.startsWith('rue ') ||
      l.contains(' boulevard') ||
      l.contains(' avenue') ||
      l.contains(' blvd');
}

List<LatLng> _sampleNodes(List<LatLng> nodes, int target) {
  final step = nodes.length / target;
  return List.generate(target, (i) => nodes[(i * step).floor()]);
}

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
          chain.addAll(other.nodes.skip(1));
          used.add(other.id);
          if (chainName.isEmpty) chainName = other.name;
          extended = true;
          break;
        } else if (RevvRoute.haversineKm(chainEnd, other.nodes.last) < _stitchThresholdKm) {
          chain.addAll(other.nodes.reversed.skip(1));
          used.add(other.id);
          if (chainName.isEmpty) chainName = other.name;
          extended = true;
          break;
        } else if (RevvRoute.haversineKm(chainStart, other.nodes.last) < _stitchThresholdKm) {
          chain = [...other.nodes, ...chain.skip(1)];
          used.add(other.id);
          if (chainName.isEmpty) chainName = other.name;
          extended = true;
          break;
        } else if (RevvRoute.haversineKm(chainStart, other.nodes.first) < _stitchThresholdKm) {
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

bool _isLoop(List<LatLng> nodes) {
  if (nodes.length < 10) return false;
  return RevvRoute.haversineKm(nodes.first, nodes.last) < 3.0;
}

// 거리 패널티: 15km 이내 패널티 없음 / 15~60km 선형 감소 / 60km+ 0.55배
double _distancePenalty(double distFromUserKm) {
  if (distFromUserKm <= 15) return 1.0;
  if (distFromUserKm >= 60) return 0.55;
  return 1.0 - (distFromUserKm - 15) / 45 * 0.45;
}

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

double _bearing(LatLng from, LatLng to) {
  final lat1 = _rad(from.lat);
  final lat2 = _rad(to.lat);
  final dLng = _rad(to.lng - from.lng);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return math.atan2(y, x) * 180 / math.pi;
}

double _bearingDiff(LatLng a, LatLng b, LatLng c) {
  final b1 = _bearing(a, b);
  final b2 = _bearing(b, c);
  double diff = (b2 - b1).abs();
  if (diff > 180) diff = 360 - diff;
  return diff;
}

double _curvatureRateDegPerKm(LatLng a, LatLng b, LatLng c) {
  final d1 = RevvRoute.haversineKm(a, b);
  final d2 = RevvRoute.haversineKm(b, c);
  final pathLen = (d1 + d2) / 2;
  if (pathLen < 0.0001) return 0;
  return _bearingDiff(a, b, c) / pathLen;
}

// roadcurvature.com 방식:
//   totalCurvature = Σ (각도변화_deg × 구간거리_km) → 절댓값 누적합산
//   300+ = Lightly Curvy, 1000+ = Moderately, 2000+ = Very, 3000+ = Extremely
_CurveResult _analyzeCurves(List<LatLng> nodes) {
  double totalCurvature = 0;
  double tightKm = 0;
  double mediumKm = 0;
  double currentContinuousKm = 0;
  double maxContinuousKm = 0;
  double straightAccum = 0;

  for (int i = 0; i < nodes.length - 2; i++) {
    final angle = _bearingDiff(nodes[i], nodes[i + 1], nodes[i + 2]);
    final segLen = RevvRoute.haversineKm(nodes[i], nodes[i + 1]);

    // roadcurvature.com 핵심 공식
    totalCurvature += angle * segLen;

    final rate = segLen > 0.0001 ? angle / segLen : 0;
    if (rate >= 200) {
      tightKm += segLen;
      currentContinuousKm += segLen;
      straightAccum = 0;
    } else if (rate >= 20) {
      mediumKm += segLen;
      currentContinuousKm += segLen;
      straightAccum = 0;
    } else {
      straightAccum += segLen;
      if (straightAccum >= 0.3) {
        if (currentContinuousKm > maxContinuousKm) maxContinuousKm = currentContinuousKm;
        currentContinuousKm = 0;
        straightAccum = 0;
      }
    }
  }
  if (currentContinuousKm > maxContinuousKm) maxContinuousKm = currentContinuousKm;

  return _CurveResult(
    totalCurvature: totalCurvature,
    tightKm: tightKm,
    mediumKm: mediumKm,
    maxContinuousKm: maxContinuousKm,
  );
}

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

// 신호등/스탑사인 카운트 (바운딩박스 선필터 후 80m 이내 정밀 체크)
int _countSignalsNearRoute(List<LatLng> wayNodes, List<LatLng> signalNodes) {
  if (signalNodes.isEmpty) return 0;
  double minLat = wayNodes[0].lat, maxLat = wayNodes[0].lat;
  double minLng = wayNodes[0].lng, maxLng = wayNodes[0].lng;
  for (final n in wayNodes) {
    if (n.lat < minLat) minLat = n.lat;
    if (n.lat > maxLat) maxLat = n.lat;
    if (n.lng < minLng) minLng = n.lng;
    if (n.lng > maxLng) maxLng = n.lng;
  }
  const buf = 0.001; // ~100m
  minLat -= buf; maxLat += buf;
  minLng -= buf; maxLng += buf;
  int count = 0;
  for (final signal in signalNodes) {
    if (signal.lat < minLat || signal.lat > maxLat ||
        signal.lng < minLng || signal.lng > maxLng) continue;
    for (final node in wayNodes) {
      if (RevvRoute.haversineKm(signal, node) < 0.08) {
        count++;
        break;
      }
    }
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

List<RevvRoute> _selectTopRoutes(
    List<_RawWay> ways, LatLng userPos, List<LatLng> intersections, List<LatLng> signalNodes) {
  final scored = <_ScoredWay>[];

  for (final way in ways) {
    final dist = _totalDistance(way.nodes);
    if (dist < 5.0) continue; // 5km 미만 도심 단편 루트 제거

    // 신호등/스탑사인 3개 이상 → 도심 루트, 제외
    final signalCount = _countSignalsNearRoute(way.nodes, signalNodes);
    if (signalCount >= 3) continue;

    final curves = _analyzeCurves(way.nodes);

    // roadcurvature.com 기준: 300 미만은 지루한 도로
    // 300=Lightly, 1000=Moderately, 2000=Very, 3000=Extremely Curvy
    if (curves.totalCurvature < 300) continue;
    if (curves.maxContinuousKm < 0.6) continue;

    // curvature density (deg/km): 전체 루트의 커브 밀도
    final curvatureDensity = curves.totalCurvature / dist;
    final continuityBonus = 1.0 + (curves.maxContinuousKm / dist) * 0.6;
    final intersectCount = _countNearbyIntersections(way.nodes, intersections);
    final intersectPenalty = _intersectionPenalty(intersectCount, dist);
    // 신호 패널티: 0개=1.0, 1개=0.55, 2개=0.25
    final signalPenalty = signalCount == 0 ? 1.0 : signalCount == 1 ? 0.55 : 0.25;
    final roadMultiplier = _roadMultiplier(way.highwayType);
    final loopBonus = _isLoop(way.nodes) ? 1.25 : 1.0;
    final distPenalty = _distancePenalty(
        RevvRoute.haversineKm(userPos, way.nodes.first));

    // roadcurvature.com 방식: density × sqrt(dist)로 밀도+길이 균형
    final score = curvatureDensity * math.sqrt(dist) *
        continuityBonus * intersectPenalty * signalPenalty * roadMultiplier *
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

  // ── 방향 다양성 선택 (8-sector Climoto 스타일) ──────────────────
  // 360°를 45° 단위 8개 섹터로 나눠 각 방향의 최고 루트 우선 선택
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

  // 1라운드: 각 섹터 1등 (6km 간격 유지)
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

// ─── RouteService ─────────────────────────────────────────────────

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

  // ── 루트 배제 ────────────────────────────────────────────────
  final List<LatLng> _excludedCenters = [];
  bool _exclusionsLoaded = false;
  static const _excludeKey = 'revv_excluded_centers';

  Future<void> loadExclusions() async {
    if (_exclusionsLoaded) return;
    _exclusionsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_excludeKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      for (final item in list) {
        _excludedCenters.add(LatLng(
          (item[0] as num).toDouble(),
          (item[1] as num).toDouble(),
        ));
      }
      debugPrint('[RouteService] 배제 루트 로드: ${_excludedCenters.length}개');
    } catch (e) {
      debugPrint('[RouteService] 배제 목록 로드 오류: $e');
    }
  }

  bool isExcluded(RevvRoute route) {
    return _excludedCenters.any(
      (p) => RevvRoute.haversineKm(p, route.centerPoint) < 2.0,
    );
  }

  Future<void> excludeRoute(RevvRoute route) async {
    _excludedCenters.add(route.centerPoint);
    routes.removeWhere(isExcluded);
    if (selectedRoute != null && isExcluded(selectedRoute!)) {
      selectedRoute = routes.isNotEmpty ? routes.first : null;
      connectingRoutes = [];
    }
    notifyListeners();
    _saveExclusions();
  }

  Future<void> _saveExclusions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _excludedCenters.map((p) => [p.lat, p.lng]).toList(),
      );
      await prefs.setString(_excludeKey, encoded);
    } catch (e) {
      debugPrint('[RouteService] 배제 목록 저장 오류: $e');
    }
  }

  // ── Sprint 요청 ────────────────────────────────────────────
  bool sprintRequested = false;
  RevvRoute? sprintRoute; // null이면 selectedRoute 사용

  void requestSprint({RevvRoute? route}) {
    sprintRequested = true;
    sprintRoute = route;
    notifyListeners();
  }

  void clearSprintRequest() {
    sprintRequested = false;
    sprintRoute = null;
  }

  void resetCache() {
    _lastFetchLocation = null;
    _lastFetchRadius = null;
  }

  /// 반경 변경 후 재검색
  Future<void> changeRadius(int radiusKm, double lat, double lng) async {
    searchRadiusKm = radiusKm;
    resetCache();
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
      await loadExclusions();
      final result = await _fetchAndScore(lat, lng, searchRadiusKm * 1000);
      routes = result.where((r) => !isExcluded(r)).toList();
      selectedRoute = routes.isNotEmpty ? routes.first : null;
      _lastFetchLocation = LatLng(lat, lng);
      _lastFetchRadius = searchRadiusKm;
      debugPrint('[RouteService] 선택된 루트: ${routes.length}개');
      _saveToCache(result, lat, lng);
    } catch (e, st) {
      debugPrint('[RouteService] 예외: $e\n$st');
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

  // ─── 오프라인 캐시 ─────────────────────────────────────────────
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

  /// CHAIN: 이미 로드된 routes 캐시에서 끝점 근처 루트 즉시 탐색 (Overpass 재호출 없음)
  Future<void> fetchConnectingRoutes(RevvRoute fromRoute) async {
    isLoadingConnecting = true;
    connectingRoutes = [];
    notifyListeners();

    final endpoint = fromRoute.nodes.last;
    const maxDistKm = 15.0;

    final candidates = routes
        .where((r) => r.id != fromRoute.id)
        .where((r) {
          final dStart = RevvRoute.haversineKm(endpoint, r.nodes.first);
          final dEnd = RevvRoute.haversineKm(endpoint, r.nodes.last);
          return dStart < maxDistKm || dEnd < maxDistKm;
        })
        .toList();

    candidates.sort((a, b) {
      final da = math.min(
        RevvRoute.haversineKm(endpoint, a.nodes.first),
        RevvRoute.haversineKm(endpoint, a.nodes.last),
      );
      final db = math.min(
        RevvRoute.haversineKm(endpoint, b.nodes.first),
        RevvRoute.haversineKm(endpoint, b.nodes.last),
      );
      return da.compareTo(db);
    });

    connectingRoutes = candidates.take(3).toList();
    debugPrint('[RouteService] CHAIN (캐시): ${connectingRoutes.length}개');

    isLoadingConnecting = false;
    notifyListeners();
  }

  /// Overpass 조회 → compute() isolate에서 파싱+스코어링
  Future<List<RevvRoute>> _fetchAndScore(double lat, double lng, int radiusM) async {
    // ["name"] 필터: 이름 없는 도로 제거 → 데이터량 80% 감소
    // primary 포함: 캐나다 일부 primary가 와인딩 명소
    final query = '''
[out:json][timeout:25];
(
  way["highway"="primary"]["name"](around:$radiusM,$lat,$lng);
  way["highway"="secondary"]["name"](around:$radiusM,$lat,$lng);
  way["highway"="tertiary"]["name"](around:$radiusM,$lat,$lng);
  way["highway"="unclassified"]["name"](around:$radiusM,$lat,$lng);
  node["highway"="traffic_signals"](around:$radiusM,$lat,$lng);
  node["highway"="stop"](around:$radiusM,$lat,$lng);
);
out geom qt;
''';

    debugPrint('[RouteService] _fetchAndScore ($lat, $lng, r=${radiusM}m)');

    final endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://z.overpass-api.de/api/interpreter',
      'https://lz4.overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.osm.ch/api/interpreter',
      'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    ];

    String? resBody;
    for (final url in endpoints) {
      try {
        final r = await http.post(
          Uri.parse(url),
          body: {'data': query},
        ).timeout(const Duration(seconds: 28)); // Overpass timeout(25s)보다 여유
        if (r.statusCode == 200) {
          final body = utf8.decode(r.bodyBytes);
          // Overpass가 XML 에러 페이지를 200으로 반환하는 경우 방어
          if (body.trimLeft().startsWith('<')) {
            debugPrint('[RouteService] $url XML 에러 응답 → 다음 서버 시도');
            continue;
          }
          resBody = body;
          debugPrint('[RouteService] $url 성공 (${body.length} bytes)');
          break;
        }
        debugPrint('[RouteService] $url → ${r.statusCode}');
      } catch (e) {
        debugPrint('[RouteService] $url 실패: $e');
      }
    }

    if (resBody == null) {
      debugPrint('[RouteService] 모든 서버 실패');
      return [];
    }

    // ── compute() isolate: JSON 파싱 + Way Stitching + 스코어링 ──
    // 메인 스레드에서 실행하면 320프레임+ 스킵 발생 → 별도 isolate로 분리
    debugPrint('[RouteService] compute() isolate 시작');
    final result = await compute(_processRoutes, _IsolateParams(resBody, lat, lng));
    debugPrint('[RouteService] compute() 완료: ${result.length}개');
    return result;
  }

  void selectRoute(RevvRoute route) {
    if (!routes.any((r) => r.id == route.id)) {
      routes = [route, ...routes];
    }
    selectedRoute = route;
    connectingRoutes = [];
    notifyListeners();
    fetchConnectingRoutes(route);
  }

  void deselectRoute() {
    selectedRoute = null;
    connectingRoutes = [];
    notifyListeners();
  }

  // ── 경유지 최적화 ──────────────────────────────────────────────

  bool isOptimizing = false;
  OptimizedRoute? lastOptimized;

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
  final double totalCurvature; // roadcurvature.com 방식 (deg × km)
  final double tightKm;
  final double mediumKm;
  final double maxContinuousKm;
  const _CurveResult({
    required this.totalCurvature,
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
