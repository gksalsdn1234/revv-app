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
  final double routeRankScore;
  final double funScore;
  final double flowScore;
  final double driveabilityPenalty;
  final int stopSignCount;
  final int trafficSignalCount;
  final double stopControlDensity;
  final String roadClassBucket;
  final bool isNamed;
  final bool isFacilityLike;
  final bool isBridgeLike;
  final bool isConnectorLike;
  final bool isMajorRoadLike;
  final bool isPrivateLike;
  final String qualityLabel;
  final String? qualityRejectReason;
  final String routeCharacter;
  final String? primaryReason;
  final String? cautionNote;

  // ElevationService로 채워지는 고도 프로파일 (선택적)
  final List<double>? elevationProfile;

  // ── 커뮤니티 필드 ─────────────────────────────────────────
  /// 이 루트를 완주한 유저 수 (global Firestore에서 읽어옴)
  final int runCount;
  /// 최초 발견자 uid
  final String? publishedBy;

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
    this.routeRankScore = 0,
    this.funScore = 0,
    this.flowScore = 0,
    this.driveabilityPenalty = 0,
    this.stopSignCount = 0,
    this.trafficSignalCount = 0,
    this.stopControlDensity = 0,
    this.roadClassBucket = '',
    this.isNamed = true,
    this.isFacilityLike = false,
    this.isBridgeLike = false,
    this.isConnectorLike = false,
    this.isMajorRoadLike = false,
    this.isPrivateLike = false,
    this.qualityLabel = '',
    this.qualityRejectReason,
    this.routeCharacter = '',
    this.primaryReason,
    this.cautionNote,
    this.elevationProfile,
    this.runCount = 0,
    this.publishedBy,
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

  /// 커브 특성 태그 (tightCurveKm 비율 기준)
  /// SWITCHBACK = 헤어핀 위주 (tight > 55%), SWEEPER = 넓은 스위퍼 (tight < 25%), MIXED
  String get curveStyle {
    final total = tightCurveKm + mediumCurveKm;
    if (total < 0.5) return 'MIXED';
    final ratio = tightCurveKm / total;
    if (ratio > 0.55) return 'SWITCHBACK';
    if (ratio < 0.25) return 'SWEEPER';
    return 'MIXED';
  }

  /// 와인딩 밀도 0.0~1.0 (스코어바용)
  double get windingDensityPct {
    if (distanceKm <= 0) return 0;
    final density = (tightCurveKm + mediumCurveKm) / distanceKm;
    return density.clamp(0.0, 1.0);
  }

  /// 총 상승고도 (m)
  double get elevationGainM {
    final p = elevationProfile;
    if (p == null || p.length < 2) return 0;
    double gain = 0;
    for (int i = 1; i < p.length; i++) {
      final d = p[i] - p[i - 1];
      if (d > 0) gain += d;
    }
    return gain;
  }

  /// 총 하강고도 (m, 절댓값)
  double get elevationLossM {
    final p = elevationProfile;
    if (p == null || p.length < 2) return 0;
    double loss = 0;
    for (int i = 1; i < p.length; i++) {
      final d = p[i] - p[i - 1];
      if (d < 0) loss += d.abs();
    }
    return loss;
  }

  double get maxElevationM =>
      elevationProfile?.reduce(math.max) ?? 0;

  double get minElevationM =>
      elevationProfile?.reduce(math.min) ?? 0;

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

  // ── Geohash 인코더 (패키지 없이 인라인) ───────────────────────────
  static const _ghChars = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// lat/lng → geohash 문자열 (precision 4 = ~26km×20km 셀)
  static String encodeGeohash(double lat, double lng, int precision) {
    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;
    int bits = 0, val = 0;
    bool isLng = true;
    final buf = StringBuffer();
    while (buf.length < precision) {
      if (isLng) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) { val = (val << 1) | 1; minLng = mid; }
        else             { val <<= 1;            maxLng = mid; }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) { val = (val << 1) | 1; minLat = mid; }
        else             { val <<= 1;            maxLat = mid; }
      }
      isLng = !isLng;
      if (++bits == 5) { buf.write(_ghChars[val]); bits = 0; val = 0; }
    }
    return buf.toString();
  }

  /// 이 루트 중심점의 precision-4 geohash (Firestore whereIn 쿼리용)
  String get geohash4 => encodeGeohash(centerPoint.lat, centerPoint.lng, 4);

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
    double? routeRankScore,
    double? funScore,
    double? flowScore,
    double? driveabilityPenalty,
    int? stopSignCount,
    int? trafficSignalCount,
    double? stopControlDensity,
    String? roadClassBucket,
    bool? isNamed,
    bool? isFacilityLike,
    bool? isBridgeLike,
    bool? isConnectorLike,
    bool? isMajorRoadLike,
    bool? isPrivateLike,
    String? qualityLabel,
    String? qualityRejectReason,
    String? routeCharacter,
    String? primaryReason,
    String? cautionNote,
    List<double>? elevationProfile,
    int? runCount,
    String? publishedBy,
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
      routeRankScore: routeRankScore ?? this.routeRankScore,
      funScore: funScore ?? this.funScore,
      flowScore: flowScore ?? this.flowScore,
      driveabilityPenalty: driveabilityPenalty ?? this.driveabilityPenalty,
      stopSignCount: stopSignCount ?? this.stopSignCount,
      trafficSignalCount: trafficSignalCount ?? this.trafficSignalCount,
      stopControlDensity: stopControlDensity ?? this.stopControlDensity,
      roadClassBucket: roadClassBucket ?? this.roadClassBucket,
      isNamed: isNamed ?? this.isNamed,
      isFacilityLike: isFacilityLike ?? this.isFacilityLike,
      isBridgeLike: isBridgeLike ?? this.isBridgeLike,
      isConnectorLike: isConnectorLike ?? this.isConnectorLike,
      isMajorRoadLike: isMajorRoadLike ?? this.isMajorRoadLike,
      isPrivateLike: isPrivateLike ?? this.isPrivateLike,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      qualityRejectReason: qualityRejectReason ?? this.qualityRejectReason,
      routeCharacter: routeCharacter ?? this.routeCharacter,
      primaryReason: primaryReason ?? this.primaryReason,
      cautionNote: cautionNote ?? this.cautionNote,
      elevationProfile: elevationProfile ?? this.elevationProfile,
      runCount: runCount ?? this.runCount,
      publishedBy: publishedBy ?? this.publishedBy,
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
        // 쿼리용 flat 필드 (Firestore 범위 쿼리)
        'centerLat': centerPoint.lat,
        'centerLng': centerPoint.lng,
        'geohash4': geohash4,
        'distanceFromUser': distanceFromUser,
        'tightCurveKm': tightCurveKm,
        'mediumCurveKm': mediumCurveKm,
        'maxContinuousKm': maxContinuousKm,
        'isLoop': isLoop,
        'routeRankScore': routeRankScore,
        'funScore': funScore,
        'flowScore': flowScore,
        'driveabilityPenalty': driveabilityPenalty,
        'stopSignCount': stopSignCount,
        'trafficSignalCount': trafficSignalCount,
        'stopControlDensity': stopControlDensity,
        'roadClassBucket': roadClassBucket,
        'isNamed': isNamed,
        'isFacilityLike': isFacilityLike,
        'isBridgeLike': isBridgeLike,
        'isConnectorLike': isConnectorLike,
        'isMajorRoadLike': isMajorRoadLike,
        'isPrivateLike': isPrivateLike,
        'qualityLabel': qualityLabel,
        if (qualityRejectReason != null) 'qualityRejectReason': qualityRejectReason,
        'routeCharacter': routeCharacter,
        if (primaryReason != null) 'primaryReason': primaryReason,
        if (cautionNote != null) 'cautionNote': cautionNote,
        if (elevationProfile != null) 'elevationProfile': elevationProfile,
        if (runCount > 0) 'runCount': runCount,
        if (publishedBy != null) 'publishedBy': publishedBy,
      };

  factory RevvRoute.fromJson(Map<String, dynamic> j) => RevvRoute(
        id: j['id'] as String,
        name: j['name'] as String,
        nodes: ((j['nodes'] as List?) ?? [])
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
        routeRankScore: (j['routeRankScore'] as num?)?.toDouble() ?? 0,
        funScore: (j['funScore'] as num?)?.toDouble() ?? 0,
        flowScore: (j['flowScore'] as num?)?.toDouble() ?? 0,
        driveabilityPenalty: (j['driveabilityPenalty'] as num?)?.toDouble() ?? 0,
        stopSignCount: (j['stopSignCount'] as num?)?.toInt() ?? 0,
        trafficSignalCount: (j['trafficSignalCount'] as num?)?.toInt() ?? 0,
        stopControlDensity: (j['stopControlDensity'] as num?)?.toDouble() ?? 0,
        roadClassBucket: j['roadClassBucket'] as String? ?? '',
        isNamed: j['isNamed'] as bool? ?? true,
        isFacilityLike: j['isFacilityLike'] as bool? ?? false,
        isBridgeLike: j['isBridgeLike'] as bool? ?? false,
        isConnectorLike: j['isConnectorLike'] as bool? ?? false,
        isMajorRoadLike: j['isMajorRoadLike'] as bool? ?? false,
        isPrivateLike: j['isPrivateLike'] as bool? ?? false,
        qualityLabel: j['qualityLabel'] as String? ?? '',
        qualityRejectReason: j['qualityRejectReason'] as String?,
        routeCharacter: j['routeCharacter'] as String? ?? '',
        primaryReason: j['primaryReason'] as String?,
        cautionNote: j['cautionNote'] as String?,
        elevationProfile: (j['elevationProfile'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
        runCount: (j['runCount'] as int?) ?? 0,
        publishedBy: j['publishedBy'] as String?,
      );

  static List<RevvRoute> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => RevvRoute.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<RevvRoute> routes) =>
      jsonEncode(routes.map((r) => r.toJson()).toList());
}
