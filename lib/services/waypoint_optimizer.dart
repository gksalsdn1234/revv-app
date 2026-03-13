import '../models/revv_route.dart';
import 'directions_service.dart';

// ── 최적화 결과 ─────────────────────────────────────────────────

class OptimizedRoute {
  /// 최적 방문 순서로 재배열된 구간 목록
  final List<RevvRoute> orderedSegments;

  /// 각 구간을 역방향으로 주행하는지 여부
  final List<bool> reversed;

  /// Mapbox Directions API에 넘길 경유지 목록 (출발→구간1입구→구간1출구→…)
  final List<LatLng> navigationWaypoints;

  /// 실제 내비 폴리라인 (Mapbox에서 받은 도로 기반 경로)
  final List<LatLng> polyline;

  /// 총 예상 직선 거리 (구간 간 연결 포함, km)
  final double totalConnectKm;

  /// 구간들의 와인딩 점수 합계
  final double totalWindingScore;

  const OptimizedRoute({
    required this.orderedSegments,
    required this.reversed,
    required this.navigationWaypoints,
    required this.polyline,
    required this.totalConnectKm,
    required this.totalWindingScore,
  });

  /// 순서 요약 문자열 (디버그/UI용)
  String get summary => orderedSegments
      .asMap()
      .entries
      .map((e) => '${e.key + 1}. ${e.value.name}${reversed[e.key] ? " (역)" : ""}')
      .join(' → ');
}

// ── 최적화 엔진 ─────────────────────────────────────────────────

class WaypointOptimizer {
  /// 주어진 와인딩 구간들을 최적 순서로 연결하는 경로를 계산한다.
  ///
  /// [userPos]  : 출발 위치 (현재 GPS)
  /// [segments] : 반드시 통과할 RevvRoute 목록 (1~10개 권장)
  /// [returnHome]: true이면 마지막 구간 뒤 출발지 복귀
  ///
  /// 알고리즘:
  ///   1. Nearest-Neighbor heuristic (방향 동시 최적화) → 초기 해
  ///   2. 2-opt swap 개선 → 지역 최적해
  ///   3. Mapbox Directions API로 실제 도로 경로 생성
  static Future<OptimizedRoute?> optimize({
    required LatLng userPos,
    required List<RevvRoute> segments,
    bool returnHome = false,
  }) async {
    if (segments.isEmpty) return null;

    final List<int> order;
    final List<bool> dirs;

    if (segments.length == 1) {
      // 단일 구간: 가까운 쪽 입구로 진입
      final rev = _closerEnd(segments[0], userPos);
      order = [0];
      dirs = [rev];
    } else {
      // 1단계: Nearest-Neighbor
      final (nnOrder, nnDirs) = _nearestNeighbor(segments, userPos);
      // 2단계: 2-opt 개선
      final (optOrder, optDirs) = _twoOpt(segments, userPos, nnOrder, nnDirs);
      order = optOrder;
      dirs = optDirs;
    }

    // 경유지 목록 조립
    final orderedSegs = order.map((i) => segments[i]).toList();
    final waypoints = _buildWaypoints(
      userPos: userPos,
      segs: orderedSegs,
      dirs: dirs,
      returnHome: returnHome,
    );

    // Mapbox Directions API 제한: 최대 25 경유지
    // 구간이 많으면 각 구간의 입구/출구만 대표점으로 사용
    final navWps = _limitWaypoints(waypoints, 23);
    final poly = await DirectionsService.getMultiRoute(navWps);

    return OptimizedRoute(
      orderedSegments: orderedSegs,
      reversed: dirs,
      navigationWaypoints: navWps,
      polyline: poly,
      totalConnectKm: _connectCost(segments, userPos, order, dirs),
      totalWindingScore: orderedSegs.fold(0.0, (s, r) => s + r.windingScore),
    );
  }

  // ── Nearest-Neighbor ───────────────────────────────────────────

  static (List<int>, List<bool>) _nearestNeighbor(
    List<RevvRoute> segs,
    LatLng start,
  ) {
    final unvisited = List<int>.generate(segs.length, (i) => i);
    final order = <int>[];
    final dirs = <bool>[];
    LatLng current = start;

    while (unvisited.isNotEmpty) {
      double bestDist = double.infinity;
      int bestIdx = unvisited.first;
      bool bestRev = false;

      for (final i in unvisited) {
        final (d, rev) = _nearestEntry(segs[i], current);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
          bestRev = rev;
        }
      }

      unvisited.remove(bestIdx);
      order.add(bestIdx);
      dirs.add(bestRev);
      current = _exit(segs[bestIdx], bestRev);
    }

    return (order, dirs);
  }

  // ── 2-opt 개선 ────────────────────────────────────────────────
  //
  // 구간 i와 j를 swap했을 때 총 연결비용이 줄면 교체.
  // 교체 후 방향은 greedy로 재최적화.

  static (List<int>, List<bool>) _twoOpt(
    List<RevvRoute> segs,
    LatLng start,
    List<int> initOrder,
    List<bool> initDirs,
  ) {
    var bestOrder = List<int>.from(initOrder);
    var bestDirs = List<bool>.from(initDirs);
    var bestCost = _connectCost(segs, start, bestOrder, bestDirs);

    bool improved = true;
    while (improved) {
      improved = false;
      for (int i = 0; i < bestOrder.length - 1; i++) {
        for (int j = i + 1; j < bestOrder.length; j++) {
          // swap i ↔ j
          final newOrder = List<int>.from(bestOrder);
          newOrder[i] = bestOrder[j];
          newOrder[j] = bestOrder[i];

          // 방향 greedy 재최적화
          final newDirs = _greedyDirs(segs, start, newOrder);
          final cost = _connectCost(segs, start, newOrder, newDirs);

          if (cost < bestCost - 0.001) {
            bestOrder = newOrder;
            bestDirs = newDirs;
            bestCost = cost;
            improved = true;
          }
        }
      }
    }

    return (bestOrder, bestDirs);
  }

  // ── 방향 greedy 최적화 ────────────────────────────────────────
  //
  // 주어진 순서 고정, 현재 위치에서 각 구간 입구 중 가까운 쪽 선택

  static List<bool> _greedyDirs(
    List<RevvRoute> segs,
    LatLng start,
    List<int> order,
  ) {
    final dirs = <bool>[];
    LatLng current = start;
    for (final i in order) {
      final (_, rev) = _nearestEntry(segs[i], current);
      dirs.add(rev);
      current = _exit(segs[i], rev);
    }
    return dirs;
  }

  // ── 비용 계산 ─────────────────────────────────────────────────
  // 연결 비용 = Σ(이전 출구 → 다음 입구 직선거리)
  // 구간 내부 이동은 고정이므로 최적화 목적 함수에서 제외 가능

  static double _connectCost(
    List<RevvRoute> segs,
    LatLng start,
    List<int> order,
    List<bool> dirs,
  ) {
    double cost = 0;
    LatLng current = start;
    for (int i = 0; i < order.length; i++) {
      final seg = segs[order[i]];
      cost += RevvRoute.haversineKm(current, _entry(seg, dirs[i]));
      current = _exit(seg, dirs[i]);
    }
    return cost;
  }

  // ── 경유지 조립 ───────────────────────────────────────────────

  static List<LatLng> _buildWaypoints({
    required LatLng userPos,
    required List<RevvRoute> segs,
    required List<bool> dirs,
    required bool returnHome,
  }) {
    final wps = <LatLng>[userPos];
    for (int i = 0; i < segs.length; i++) {
      wps.add(_entry(segs[i], dirs[i]));
      wps.add(_exit(segs[i], dirs[i]));
    }
    if (returnHome) wps.add(userPos);
    return wps;
  }

  // ── 경유지 수 제한 ────────────────────────────────────────────
  // Mapbox Directions: 최대 25 경유지
  // 초과 시 균등 샘플링 (첫점·끝점 반드시 유지)

  static List<LatLng> _limitWaypoints(List<LatLng> wps, int max) {
    if (wps.length <= max) return wps;
    final result = <LatLng>[wps.first];
    final step = (wps.length - 2) / (max - 2);
    for (int i = 1; i < max - 1; i++) {
      result.add(wps[(i * step).round().clamp(1, wps.length - 2)]);
    }
    result.add(wps.last);
    return result;
  }

  // ── 헬퍼 ──────────────────────────────────────────────────────

  /// current에서 더 가까운 입구를 반환. (거리, 역방향 여부)
  static (double, bool) _nearestEntry(RevvRoute r, LatLng current) {
    final dfwd = RevvRoute.haversineKm(current, r.nodes.first);
    final drev = RevvRoute.haversineKm(current, r.nodes.last);
    return dfwd <= drev ? (dfwd, false) : (drev, true);
  }

  /// 정방향이면 nodes.first, 역방향이면 nodes.last
  static LatLng _entry(RevvRoute r, bool rev) =>
      rev ? r.nodes.last : r.nodes.first;

  /// 정방향이면 nodes.last, 역방향이면 nodes.first
  static LatLng _exit(RevvRoute r, bool rev) =>
      rev ? r.nodes.first : r.nodes.last;

  /// current에서 가까운 쪽 끝점이 역방향인지 반환
  static bool _closerEnd(RevvRoute r, LatLng current) {
    final dfwd = RevvRoute.haversineKm(current, r.nodes.first);
    final drev = RevvRoute.haversineKm(current, r.nodes.last);
    return drev < dfwd;
  }
}
