import 'revv_route.dart';

/// 그리디 서킷으로 조립된 드라이빙 루프
/// segments: 실제 RevvRoute 조각들
/// connectorKm[i]: origin(또는 이전 세그먼트 끝) → segments[i] 시작점 사이 예상 주행 거리 (haversine × 1.4)
class LoopRoute {
  final List<RevvRoute> segments;
  final LatLng origin;
  final double totalKm;       // segments km 합 + connector 합 + 귀환 구간
  final double windingScore;  // 세그먼트 평균 점수
  final int targetKm;         // 목표 거리 (30 / 60 / 90)
  final List<double> connectorKm; // segments[i] 진입 전 연결 구간 (길이 == segments.length)
  final List<bool> reversed;      // segments[i]를 역방향 주행 여부

  const LoopRoute({
    required this.segments,
    required this.origin,
    required this.totalKm,
    required this.windingScore,
    required this.targetKm,
    required this.connectorKm,
    required this.reversed,
  });

  String get totalDisplay => '${totalKm.toStringAsFixed(0)} km';

  String get difficultyLabel {
    if (windingScore >= 8.0) return 'EXTREME';
    if (windingScore >= 5.5) return 'HARD';
    if (windingScore >= 3.5) return 'MEDIUM';
    if (windingScore >= 2.0) return 'EASY';
    return 'SCENIC';
  }

  int get difficultyLevel {
    if (windingScore >= 8.0) return 4;
    if (windingScore >= 5.5) return 3;
    if (windingScore >= 3.5) return 2;
    if (windingScore >= 2.0) return 1;
    return 0;
  }

  String get scoreDisplay => windingScore.toStringAsFixed(1);

  /// 실제 루트 주행 거리만 합산 (커넥터 제외)
  double get routeOnlyKm =>
      segments.fold(0.0, (s, r) => s + r.distanceKm);
}
