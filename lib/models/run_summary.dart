import 'dart:convert';

class RunSummary {
  final String id;
  final DateTime date;
  final double distanceKm;
  final int durationSeconds;
  final String routeName;
  final String? routeId;
  final String weatherEmoji;
  final String tempDisplay;
  /// IMU 최대 횡G — 실기기에서만 유효, 에뮬레이터는 0.0
  final double? maxLateralG;

  /// 급조작 횟수 (G > 0.45G 순간) — 실기기에서만 유효
  final int sharpCornersCount;

  const RunSummary({
    required this.id,
    required this.date,
    required this.distanceKm,
    required this.durationSeconds,
    required this.routeName,
    this.routeId,
    required this.weatherEmoji,
    required this.tempDisplay,
    this.maxLateralG,
    this.sharpCornersCount = 0,
  });

  String get durationDisplay {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'distanceKm': distanceKm,
        'durationSeconds': durationSeconds,
        'routeName': routeName,
        'routeId': routeId,
        'weatherEmoji': weatherEmoji,
        'tempDisplay': tempDisplay,
        if (maxLateralG != null) 'maxLateralG': maxLateralG,
        if (sharpCornersCount > 0) 'sharpCornersCount': sharpCornersCount,
      };

  factory RunSummary.fromJson(Map<String, dynamic> j) => RunSummary(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        durationSeconds: j['durationSeconds'] as int,
        routeName: j['routeName'] as String,
        routeId: j['routeId'] as String?,
        weatherEmoji: j['weatherEmoji'] as String,
        tempDisplay: j['tempDisplay'] as String,
        maxLateralG: (j['maxLateralG'] as num?)?.toDouble(),
        sharpCornersCount: (j['sharpCornersCount'] as int?) ?? 0,
      );

  static List<RunSummary> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => RunSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<RunSummary> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}
