import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/revv_route.dart';
import '../models/loop_route.dart';

/// 그리디 서킷 빌더 — 현재 위치(또는 집)에서 출발해 와인딩 루트를 이어붙여
/// 30 / 60 / 90 km 순환 루프 3개를 생성한다.
class LoopRouteService extends ChangeNotifier {
  List<LoopRoute> loops = [];
  bool isBuilding = false;

  // 이전 빌드 파라미터 (중복 빌드 방지)
  LatLng? _lastOrigin;
  int? _lastRouteCount;

  static const _connectThresholdKm = 15.0; // 연결 허용 최대 거리
  static const _connectorFactor = 1.4;     // haversine → 예상 도로 거리 계수
  static const _targets = [30, 60, 90];

  Future<void> buildLoops(List<RevvRoute> routes, LatLng origin) async {
    // 노드가 있는 루트만 사용
    final usable = routes.where((r) => r.nodes.length >= 2).toList();
    if (usable.isEmpty) return;

    // 같은 origin + 같은 루트 수면 재빌드 스킵
    if (_lastOrigin != null && _lastRouteCount == usable.length) {
      final dist = RevvRoute.haversineKm(_lastOrigin!, origin);
      if (dist < 2) return;
    }

    isBuilding = true;
    notifyListeners();

    // 메인 스레드에서 실행 (루프 빌드는 가볍다)
    final results = <LoopRoute>[];
    for (final target in _targets) {
      // 두 가지 시드로 시도해서 더 좋은 결과 선택
      final a = _buildGreedyLoop(usable, origin, target.toDouble(), seed: 0);
      final b = _buildGreedyLoop(usable, origin, target.toDouble(), seed: 1);
      final best = _pickBetter(a, b);
      if (best != null) results.add(best);
    }

    loops = results;
    _lastOrigin = origin;
    _lastRouteCount = usable.length;
    isBuilding = false;
    notifyListeners();
  }

  void reset() {
    loops = [];
    _lastOrigin = null;
    _lastRouteCount = null;
    notifyListeners();
  }

  // ── 그리디 서킷 ─────────────────────────────────────────────────
  LoopRoute? _buildGreedyLoop(
    List<RevvRoute> routes,
    LatLng origin,
    double targetKm, {
    int seed = 0,
  }) {
    // seed에 따라 초기 루트 후보 셔플 (다양성)
    final shuffled = List<RevvRoute>.from(routes);
    if (seed > 0) {
      final rng = math.Random(seed * 31337);
      shuffled.shuffle(rng);
    }

    final used = <String>{};
    final segments = <RevvRoute>[];
    final connectors = <double>[];
    final revFlags = <bool>[];
    var current = origin;
    var totalRouteKm = 0.0;
    var totalConnKm = 0.0;

    for (int iter = 0; iter < 10; iter++) {
      // 현재 위치 → origin 귀환 예상
      final returnEst =
          RevvRoute.haversineKm(current, origin) * _connectorFactor;
      // 남은 예산 (귀환 포함)
      final budget = targetKm - totalRouteKm - totalConnKm - returnEst;
      if (budget < 3) break;

      RevvRoute? best;
      bool bestRev = false;
      double bestScore = -double.infinity;
      double bestConnKm = 0;

      for (final r in shuffled) {
        if (used.contains(r.id)) continue;
        // 너무 긴 루트 제외
        if (r.distanceKm > budget * 1.35 + 5) continue;

        for (final rev in [false, true]) {
          final entry = rev ? r.nodes.last : r.nodes.first;
          final exit = rev ? r.nodes.first : r.nodes.last;
          final connKm =
              RevvRoute.haversineKm(current, entry) * _connectorFactor;
          if (connKm > _connectThresholdKm) continue;
          if (connKm + r.distanceKm > budget * 1.35 + 5) continue;

          // 이 세그먼트 추가 후 귀환 예상
          final afterReturn =
              RevvRoute.haversineKm(exit, origin) * _connectorFactor;
          // 남은 여유 (음수 = 초과)
          final leftover =
              budget - connKm - r.distanceKm - afterReturn;

          // 와인딩 점수 우선, 예산 초과 패널티
          final score =
              r.windingScore - math.max(0.0, leftover) * 0.08 - math.max(0.0, -leftover) * 0.15;

          if (score > bestScore) {
            best = r;
            bestRev = rev;
            bestScore = score;
            bestConnKm = connKm;
          }
        }
      }

      if (best == null) break;

      used.add(best.id);
      segments.add(best);
      connectors.add(bestConnKm);
      revFlags.add(bestRev);
      totalConnKm += bestConnKm;
      totalRouteKm += best.distanceKm;
      current = bestRev ? best.nodes.first : best.nodes.last;
    }

    if (segments.isEmpty) return null;

    final returnKm =
        RevvRoute.haversineKm(current, origin) * _connectorFactor;
    final totalKm = totalRouteKm + totalConnKm + returnKm;
    final avgScore =
        segments.fold<double>(0, (s, r) => s + r.windingScore) /
            segments.length;

    return LoopRoute(
      segments: segments,
      origin: origin,
      totalKm: totalKm,
      windingScore: avgScore,
      targetKm: targetKm.toInt(),
      connectorKm: connectors,
      reversed: revFlags,
    );
  }

  LoopRoute? _pickBetter(LoopRoute? a, LoopRoute? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.windingScore >= b.windingScore ? a : b;
  }
}
