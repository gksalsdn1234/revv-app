import 'package:flutter/foundation.dart';
import '../models/revv_route.dart';
import '../models/loop_route.dart';
import 'loop_route_service.dart';
import 'directions_service.dart';

/// 결과 서킷 — 실제 Mapbox 도로로 연결된 start=end 루프
class CircuitResult {
  final List<LatLng> polyline; // 실제 도로 폴리라인 (Mapbox)
  final LoopRoute loop;        // 그리디 루프 메타 (세그먼트, 점수)
  final double realKm;         // Mapbox 실 주행 거리 (추정)
  final int targetKm;

  CircuitResult({
    required this.polyline,
    required this.loop,
    required this.realKm,
    required this.targetKm,
  });

  String get realKmDisplay => '${realKm.toStringAsFixed(0)} km';

  String get difficultyLabel => loop.difficultyLabel;
  int get difficultyLevel   => loop.difficultyLevel;
  String get scoreDisplay   => loop.scoreDisplay;

  /// RevvRoute로 변환 — SprintScreen / DriveScreen에서 바로 사용 가능
  RevvRoute toRevvRoute() {
    final segs = loop.segments;
    final name = segs.isNotEmpty ? '${segs.first.name} Circuit' : 'Circuit';
    // 중심점: 폴리라인 중간 노드
    final midNode = polyline[polyline.length ~/ 2];
    return RevvRoute(
      id: 'circuit_${targetKm}_${loop.origin.lat.toStringAsFixed(3)}',
      name: name,
      nodes: polyline,
      distanceKm: realKm,
      windingScore: loop.windingScore,
      starRating: (loop.windingScore / 2.5).clamp(1.0, 5.0).round(),
      sharpCurveCount: loop.segments.fold<int>(0, (s, r) => s + r.sharpCurveCount),
      centerPoint: midNode,
      distanceFromUser: RevvRoute.haversineKm(loop.origin, midNode),
      isLoop: true,
    );
  }
}

class CircuitService extends ChangeNotifier {
  final LoopRouteService _loopSvc = LoopRouteService();

  CircuitResult? result;
  bool isBuilding = false;
  String? error;

  int _lastTarget = 0;
  LatLng? _lastOrigin;
  int? _lastRouteCount;

  static const _targets = [20, 40, 60];
  static const List<int> targets = _targets;

  Future<void> build(
    List<RevvRoute> routes,
    LatLng origin,
    int targetKm,
  ) async {
    // 동일 파라미터 중복 빌드 방지
    if (_lastOrigin != null &&
        _lastTarget == targetKm &&
        _lastRouteCount == routes.length) {
      final d = RevvRoute.haversineKm(_lastOrigin!, origin);
      if (d < 1.0) return;
    }

    isBuilding = true;
    error = null;
    result = null;
    notifyListeners();

    try {
      // 1. 그리디 루프 빌드 (도로 세그먼트 조합)
      await _loopSvc.buildLoops(routes, origin);
      final loops = _loopSvc.loops;
      if (loops.isEmpty) {
        error = '주변 루트가 부족해요. 반경을 늘려보세요.';
        isBuilding = false;
        notifyListeners();
        return;
      }

      // targetKm에 가장 가까운 루프 선택
      final best = loops.reduce((a, b) =>
          (a.totalKm - targetKm).abs() < (b.totalKm - targetKm).abs() ? a : b);

      // 2. 경유지 추출: origin → seg1.entry → seg1.exit → ... → origin
      final waypoints = _buildWaypoints(best);
      if (waypoints.length < 3) {
        error = '경유지가 부족해요.';
        isBuilding = false;
        notifyListeners();
        return;
      }

      // 3. Mapbox Directions로 실제 도로 연결
      final polyline = await DirectionsService.getMultiRoute(waypoints);
      if (polyline.isEmpty) {
        error = '도로 경로를 찾지 못했어요.';
        isBuilding = false;
        notifyListeners();
        return;
      }

      // 4. 실 주행 거리 계산
      double realKm = 0;
      for (int i = 1; i < polyline.length; i++) {
        realKm += RevvRoute.haversineKm(polyline[i - 1], polyline[i]);
      }

      result = CircuitResult(
        polyline: polyline,
        loop: best,
        realKm: realKm,
        targetKm: targetKm,
      );
      _lastOrigin = origin;
      _lastTarget = targetKm;
      _lastRouteCount = routes.length;
    } catch (e) {
      error = '오류가 발생했어요: $e';
      debugPrint('[CircuitService] error: $e');
    }

    isBuilding = false;
    notifyListeners();
  }

  void reset() {
    result = null;
    error = null;
    _lastOrigin = null;
    _lastTarget = 0;
    _lastRouteCount = null;
    notifyListeners();
  }

  /// LoopRoute → Mapbox 경유지 리스트 (origin 포함, 마지막 = origin)
  List<LatLng> _buildWaypoints(LoopRoute loop) {
    final pts = <LatLng>[loop.origin];
    for (int i = 0; i < loop.segments.length; i++) {
      final seg = loop.segments[i];
      final rev = loop.reversed[i];
      final entry = rev ? seg.nodes.last  : seg.nodes.first;
      final exit  = rev ? seg.nodes.first : seg.nodes.last;
      // 너무 가까운 연속 경유지 제거 (Mapbox 25개 한도 최적화)
      if (pts.isEmpty || RevvRoute.haversineKm(pts.last, entry) > 0.05) {
        pts.add(entry);
      }
      if (RevvRoute.haversineKm(entry, exit) > 0.05) {
        pts.add(exit);
      }
    }
    pts.add(loop.origin); // 닫힘 — 시작=끝
    // Mapbox Directions 최대 25 경유지 제한
    if (pts.length > 25) {
      final step = pts.length / 23;
      final trimmed = <LatLng>[pts.first];
      for (double i = step; i < pts.length - 1; i += step) {
        trimmed.add(pts[i.toInt()]);
      }
      trimmed.add(pts.last);
      return trimmed;
    }
    return pts;
  }
}
