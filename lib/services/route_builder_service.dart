import 'dart:math' as math;
import '../models/revv_route.dart';
import 'directions_service.dart';

/// 목표 거리(km) 기반 루프 루트 빌더
class RouteBuilderService {
  /// [center]    : 출발/도착 위치 (현재위치)
  /// [targetKm]  : 목표 총 주행 거리
  /// [candidates]: RouteService에서 받은 흥미로운 도로 세그먼트 목록
  static Future<RevvRoute?> buildLoop({
    required LatLng center,
    required int targetKm,
    required List<RevvRoute> candidates,
  }) async {
    if (candidates.isEmpty) return null;

    // 1. 그리디 세그먼트 선택 — 현위치에서 가장 가까운 것부터 탐욕적으로 추가
    final selected = _greedySelect(center, candidates, targetKm);
    if (selected.isEmpty) return null;

    // 2. 경유지 리스트 구성
    //    현위치 → seg1_start … seg1_end → seg2_start … → 현위치
    //    Mapbox 최대 25 경유지 제한에 맞게 세그먼트당 3개 노드 샘플
    final waypoints = <LatLng>[center];
    for (final seg in selected) {
      final nodes = seg.nodes;
      waypoints.add(nodes.first);
      if (nodes.length > 4) waypoints.add(nodes[nodes.length ~/ 2]);
      waypoints.add(nodes.last);
      if (waypoints.length >= 22) break; // 안전 마진 (max 25)
    }
    waypoints.add(center); // 루프 닫기

    // 3. Mapbox Directions — 실제 주행 가능 경로
    final polyline = await DirectionsService.getMultiRoute(waypoints);
    if (polyline.isEmpty) return null;

    // 4. 실제 거리 계산
    double totalKm = 0;
    for (var i = 1; i < polyline.length; i++) {
      totalKm += RevvRoute.haversineKm(polyline[i - 1], polyline[i]);
    }

    // 5. 루트 이름: 가장 점수 높은 세그먼트 이름 기반
    final topName = selected.first.name.isNotEmpty
        ? selected.first.name
        : '${targetKm}km 드라이빙 루프';
    final name = '$topName 코스 (${totalKm.toStringAsFixed(0)}km)';

    return RevvRoute(
      id: 'loop_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      nodes: polyline,
      distanceKm: totalKm,
      windingScore: selected.map((r) => r.windingScore).reduce(math.max),
      starRating: selected.first.starRating,
      sharpCurveCount: 0,
      centerPoint: center,
      distanceFromUser: 0,
      tightCurveKm: selected.fold(0, (s, r) => s + r.tightCurveKm),
      mediumCurveKm: selected.fold(0, (s, r) => s + r.mediumCurveKm),
      maxContinuousKm: selected.map((r) => r.maxContinuousKm).reduce(math.max),
      elevationDelta: 0,
    );
  }

  /// 그리디 알고리즘: 현위치에서 가까운 세그먼트부터 추가하며 목표 거리 달성
  static List<RevvRoute> _greedySelect(
      LatLng start, List<RevvRoute> candidates, int targetKm) {
    final rand = math.Random();
    final available = List<RevvRoute>.from(candidates);
    final selected = <RevvRoute>[];
    var estimatedTotal = 0.0;
    var currentPos = start;

    while (available.isNotEmpty && estimatedTotal < targetKm) {
      // 가장 가까운 + 점수 높은 세그먼트 선택 (약간의 랜덤성으로 다양한 루트 생성)
      available.sort((a, b) {
        final distA = RevvRoute.haversineKm(currentPos, a.nodes.first);
        final distB = RevvRoute.haversineKm(currentPos, b.nodes.first);
        final scoreA = (a.windingScore / (1 + distA * 0.1)) * (0.8 + rand.nextDouble() * 0.4);
        final scoreB = (b.windingScore / (1 + distB * 0.1)) * (0.8 + rand.nextDouble() * 0.4);
        return scoreB.compareTo(scoreA);
      });

      final best = available.removeAt(0);
      final connectingKm = RevvRoute.haversineKm(currentPos, best.nodes.first) * 1.3;
      estimatedTotal += connectingKm + best.distanceKm;
      selected.add(best);
      currentPos = best.nodes.last;
    }

    return selected;
  }
}
