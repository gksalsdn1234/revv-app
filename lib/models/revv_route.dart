import 'dart:convert';
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
  // 루프 루트 여부 (시작점~끝점 3km 이내)
  final bool isLoop;

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
    this.isLoop = false,
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

  /// 집에서 거리 표시
  String get distanceFromUserDisplay {
    if (distanceFromUser < 1.0) return '${(distanceFromUser * 1000).round()}m';
    return '${distanceFromUser.toStringAsFixed(0)}km 거리';
  }

  /// 난이도 레이블 (windingScore 기반)
  String get difficultyLabel {
    if (windingScore >= 8.0) return 'EXTREME';
    if (windingScore >= 5.5) return 'HARD';
    if (windingScore >= 3.5) return 'MEDIUM';
    if (windingScore >= 2.0) return 'EASY';
    return 'SCENIC';
  }

  /// 난이도 단계 0-4 (색상 매핑용)
  int get difficultyLevel {
    if (windingScore >= 8.0) return 4;
    if (windingScore >= 5.5) return 3;
    if (windingScore >= 3.5) return 2;
    if (windingScore >= 2.0) return 1;
    return 0;
  }

  /// 와인딩 밀도 0.0~1.0 (스코어바용)
  double get windingDensityPct {
    if (distanceKm <= 0) return 0;
    final density = (tightCurveKm + mediumCurveKm) / distanceKm;
    return density.clamp(0.0, 1.0);
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

  RevvRoute copyWith({
    String? id,
    String? name,
    List<LatLng>? nodes,
    double? distanceKm,
    double? windingScore,
    int? starRating,
    int? sharpCurveCount,
    double? elevationDelta,
    LatLng? centerPoint,
    double? distanceFromUser,
    double? tightCurveKm,
    double? mediumCurveKm,
    double? maxContinuousKm,
    bool? isLoop,
  }) {
    return RevvRoute(
      id: id ?? this.id,
      name: name ?? this.name,
      nodes: nodes ?? this.nodes,
      distanceKm: distanceKm ?? this.distanceKm,
      windingScore: windingScore ?? this.windingScore,
      starRating: starRating ?? this.starRating,
      sharpCurveCount: sharpCurveCount ?? this.sharpCurveCount,
      elevationDelta: elevationDelta ?? this.elevationDelta,
      centerPoint: centerPoint ?? this.centerPoint,
      distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      tightCurveKm: tightCurveKm ?? this.tightCurveKm,
      mediumCurveKm: mediumCurveKm ?? this.mediumCurveKm,
      maxContinuousKm: maxContinuousKm ?? this.maxContinuousKm,
      isLoop: isLoop ?? this.isLoop,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nodes': nodes.map((n) => {'lat': n.lat, 'lng': n.lng}).toList(),
        'distanceKm': distanceKm,
        'windingScore': windingScore,
        'starRating': starRating,
        'sharpCurveCount': sharpCurveCount,
        'elevationDelta': elevationDelta,
        'centerPoint': {'lat': centerPoint.lat, 'lng': centerPoint.lng},
        'distanceFromUser': distanceFromUser,
        'tightCurveKm': tightCurveKm,
        'mediumCurveKm': mediumCurveKm,
        'maxContinuousKm': maxContinuousKm,
        'isLoop': isLoop,
      };

  factory RevvRoute.fromJson(Map<String, dynamic> j) => RevvRoute(
        id: j['id'] as String,
        name: j['name'] as String,
        nodes: (j['nodes'] as List)
            .map((n) => LatLng(
                  (n['lat'] as num).toDouble(),
                  (n['lng'] as num).toDouble(),
                ))
            .toList(),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        windingScore: (j['windingScore'] as num).toDouble(),
        starRating: j['starRating'] as int,
        sharpCurveCount: j['sharpCurveCount'] as int? ?? 0,
        elevationDelta: (j['elevationDelta'] as num?)?.toDouble() ?? 0,
        centerPoint: LatLng(
          (j['centerPoint']['lat'] as num).toDouble(),
          (j['centerPoint']['lng'] as num).toDouble(),
        ),
        distanceFromUser: (j['distanceFromUser'] as num).toDouble(),
        tightCurveKm: (j['tightCurveKm'] as num?)?.toDouble() ?? 0,
        mediumCurveKm: (j['mediumCurveKm'] as num?)?.toDouble() ?? 0,
        maxContinuousKm: (j['maxContinuousKm'] as num?)?.toDouble() ?? 0,
        isLoop: j['isLoop'] as bool? ?? false,
      );

  static List<RevvRoute> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => RevvRoute.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<RevvRoute> routes) =>
      jsonEncode(routes.map((r) => r.toJson()).toList());
}
