class OBDData {
  final int? rpm;
  final int? speedKmh;
  final double? engineLoadPct;
  final double? throttlePct;
  final double? fuelLevelPct;
  final int? coolantTempC;
  final DateTime timestamp;

  const OBDData({
    this.rpm,
    this.speedKmh,
    this.engineLoadPct,
    this.throttlePct,
    this.fuelLevelPct,
    this.coolantTempC,
    required this.timestamp,
  });

  OBDData copyWith({
    int? rpm,
    int? speedKmh,
    double? engineLoadPct,
    double? throttlePct,
    double? fuelLevelPct,
    int? coolantTempC,
    DateTime? timestamp,
  }) =>
      OBDData(
        rpm: rpm ?? this.rpm,
        speedKmh: speedKmh ?? this.speedKmh,
        engineLoadPct: engineLoadPct ?? this.engineLoadPct,
        throttlePct: throttlePct ?? this.throttlePct,
        fuelLevelPct: fuelLevelPct ?? this.fuelLevelPct,
        coolantTempC: coolantTempC ?? this.coolantTempC,
        timestamp: timestamp ?? this.timestamp,
      );

  String get fuelDisplay =>
      fuelLevelPct != null ? '${fuelLevelPct!.round()}%' : '—';

  String get rpmDisplay => rpm != null ? '${rpm!}' : '—';

  String get throttleDisplay =>
      throttlePct != null ? '${throttlePct!.round()}%' : '—';

  String get coolantDisplay =>
      coolantTempC != null ? '${coolantTempC!}°C' : '—';
}
