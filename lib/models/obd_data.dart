class OBDData {
  // ── ENGINE ───────────────────────
  final int? rpm;
  final double? engineLoadPct;
  final double? throttlePct;
  final double? relThrottlePct;
  final int? coolantTempC;
  final int? oilTempC;

  // ── AIR ─────────────────────────
  final int? intakeAirTempC;
  final int? intakeMapKpa;
  final double? mafGps;

  // ── FUEL ────────────────────────
  final double? fuelLevelPct;
  final double? fuelRateLph;

  // ── VEHICLE ─────────────────────
  final int? speedKmh;
  final double? accelPedalPct;
  final double? moduleVoltageV;

  final DateTime timestamp;

  const OBDData({
    this.rpm,
    this.engineLoadPct,
    this.throttlePct,
    this.relThrottlePct,
    this.coolantTempC,
    this.oilTempC,
    this.intakeAirTempC,
    this.intakeMapKpa,
    this.mafGps,
    this.fuelLevelPct,
    this.fuelRateLph,
    this.speedKmh,
    this.accelPedalPct,
    this.moduleVoltageV,
    required this.timestamp,
  });

  OBDData copyWith({
    int? rpm,
    double? engineLoadPct,
    double? throttlePct,
    double? relThrottlePct,
    int? coolantTempC,
    int? oilTempC,
    int? intakeAirTempC,
    int? intakeMapKpa,
    double? mafGps,
    double? fuelLevelPct,
    double? fuelRateLph,
    int? speedKmh,
    double? accelPedalPct,
    double? moduleVoltageV,
    DateTime? timestamp,
  }) =>
      OBDData(
        rpm: rpm ?? this.rpm,
        engineLoadPct: engineLoadPct ?? this.engineLoadPct,
        throttlePct: throttlePct ?? this.throttlePct,
        relThrottlePct: relThrottlePct ?? this.relThrottlePct,
        coolantTempC: coolantTempC ?? this.coolantTempC,
        oilTempC: oilTempC ?? this.oilTempC,
        intakeAirTempC: intakeAirTempC ?? this.intakeAirTempC,
        intakeMapKpa: intakeMapKpa ?? this.intakeMapKpa,
        mafGps: mafGps ?? this.mafGps,
        fuelLevelPct: fuelLevelPct ?? this.fuelLevelPct,
        fuelRateLph: fuelRateLph ?? this.fuelRateLph,
        speedKmh: speedKmh ?? this.speedKmh,
        accelPedalPct: accelPedalPct ?? this.accelPedalPct,
        moduleVoltageV: moduleVoltageV ?? this.moduleVoltageV,
        timestamp: timestamp ?? this.timestamp,
      );

  // ── 표시용 포맷 ──────────────────
  String get rpmDisplay => rpm != null ? '$rpm' : '—';
  String get speedDisplay => speedKmh != null ? '$speedKmh' : '—';
  String get fuelDisplay => fuelLevelPct != null ? '${fuelLevelPct!.round()}' : '—';
  String get throttleDisplay => throttlePct != null ? '${throttlePct!.round()}' : '—';
  String get coolantDisplay => coolantTempC != null ? '$coolantTempC' : '—';
  String get oilDisplay => oilTempC != null ? '$oilTempC' : '—';
  String get loadDisplay => engineLoadPct != null ? '${engineLoadPct!.round()}' : '—';
  String get intakeTempDisplay => intakeAirTempC != null ? '$intakeAirTempC' : '—';
  String get mapDisplay => intakeMapKpa != null ? '$intakeMapKpa' : '—';
  String get mafDisplay => mafGps != null ? mafGps!.toStringAsFixed(1) : '—';
  String get accelDisplay => accelPedalPct != null ? '${accelPedalPct!.round()}' : '—';
  String get voltageDisplay => moduleVoltageV != null ? moduleVoltageV!.toStringAsFixed(1) : '—';
  String get fuelRateDisplay => fuelRateLph != null ? fuelRateLph!.toStringAsFixed(1) : '—';
  String get relThrottleDisplay => relThrottlePct != null ? '${relThrottlePct!.round()}' : '—';
}

class OBDRunSummary {
  final int? maxRpm;
  final double? avgFuelRateLph;
  final double? startFuelLevelPct;
  final double? endFuelLevelPct;
  final int? maxCoolantTempC;

  const OBDRunSummary({
    this.maxRpm,
    this.avgFuelRateLph,
    this.startFuelLevelPct,
    this.endFuelLevelPct,
    this.maxCoolantTempC,
  });

  bool get hasData =>
      maxRpm != null ||
      avgFuelRateLph != null ||
      startFuelLevelPct != null ||
      endFuelLevelPct != null ||
      maxCoolantTempC != null;

  Map<String, dynamic> toJson() => {
        if (maxRpm != null) 'maxRpm': maxRpm,
        if (avgFuelRateLph != null) 'avgFuelRateLph': avgFuelRateLph,
        if (startFuelLevelPct != null) 'startFuelLevelPct': startFuelLevelPct,
        if (endFuelLevelPct != null) 'endFuelLevelPct': endFuelLevelPct,
        if (maxCoolantTempC != null) 'maxCoolantTempC': maxCoolantTempC,
      };

  factory OBDRunSummary.fromJson(Map<String, dynamic> json) => OBDRunSummary(
        maxRpm: json['maxRpm'] as int?,
        avgFuelRateLph: (json['avgFuelRateLph'] as num?)?.toDouble(),
        startFuelLevelPct: (json['startFuelLevelPct'] as num?)?.toDouble(),
        endFuelLevelPct: (json['endFuelLevelPct'] as num?)?.toDouble(),
        maxCoolantTempC: json['maxCoolantTempC'] as int?,
      );
}
