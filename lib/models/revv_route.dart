import 'dart:math' as math;

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

class RevvRoute {
  final String id;
  final String name;
  final List<LatLng> nodes;
  final double distanceKm;
  final double windingScore;
  final int starRating;
  final int sharpCurveCount;
  final double elevationDelta;
  final LatLng centerPoint;
  final double distanceFromUser;
  // 새 곡률 분석 필드
  final double tightCurveKm;
  final double mediumCurveKm;
  final double maxContinuousKm;

  const RevvRoute({
    required this.id,
    required this.name,
    required this.nodes,
    required this.distanceKm,
    required this.windingScore,
    required this.starRating,
    required this.sharpCurveCount,
    this.elevationDelta = 0,
    required this.centerPoint,
    required this.distanceFromUser,
    this.tightCurveKm = 0,
    this.mediumCurveKm = 0,
    this.maxContinuousKm = 0,
  });

  String get starDisplay => '★' * starRating + '☆' * (5 - starRating);

  String get distanceDisplay => '${distanceKm.toStringAsFixed(0)} km';

  String get durationDisplay {
    final totalMin = (distanceKm / 60 * 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static String autoName(double windingScore) {
    if (windingScore >= 8.0) return '언노운 와인딩 루트';
    if (windingScore >= 4.0) return '근교 드라이빙 루트';
    return '경치 좋은 루트';
  }

  static int toStarRating(double score) {
    if (score >= 8.0) return 5;
    if (score >= 5.5) return 4;
    if (score >= 3.5) return 3;
    if (score >= 2.0) return 2;
    return 1;
  }

  /// Haversine 거리 계산 (km)
  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.lat - a.lat);
    final dLng = _rad(b.lng - a.lng);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h = sinDLat * sinDLat +
        math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * sinDLng * sinDLng;
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
