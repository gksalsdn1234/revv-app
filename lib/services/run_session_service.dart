import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/run_session.dart';
import '../models/revv_route.dart';
import '../models/run_telemetry_detail.dart';
import 'drive_dynamics_tracker.dart';
import 'run_recovery_store.dart';
// SharpCorner는 run_session.dart에 정의됨

class RunSessionService extends ChangeNotifier {
  RunSessionService({
    DateTime Function()? clock,
    RunRecoveryStore? recoveryStore,
  }) : _clock = clock ?? DateTime.now,
       _recoveryStore = recoveryStore;

  final DateTime Function() _clock;
  RunRecoveryStore? _recoveryStore;
  DateTime? _lastSnapshotTime;
  Future<void> _recoveryWrites = Future.value();

  void configureRecoveryStore(RunRecoveryStore recoveryStore) {
    _recoveryStore ??= recoveryStore;
  }

  void _enqueueRecoveryWrite(Future<void> Function(RunRecoveryStore) action) {
    final store = _recoveryStore;
    if (store == null) return;
    _recoveryWrites = _recoveryWrites.then((_) => action(store)).catchError((
      Object error,
    ) {
      if (kDebugMode) {
        debugPrint('Run recovery snapshot failed: $error');
      }
    });
    unawaited(_recoveryWrites);
  }

  // ── post-frame 안전 notify ────────────────────────────────────
  // recordPosition()은 LocationService post-frame callback 안에서 호출됨.
  // 직접 notifyListeners() → Consumer rebuild → 같은 프레임 layout 재진입 가능.
  // → addPostFrameCallback으로 항상 다음 프레임에 notify.
  bool _notifyPending = false;
  void _scheduleNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyPending = false;
      notifyListeners();
    });
  }

  bool isRecording = false;

  DateTime? _startTime;
  double _maxSpeedKmh = 0;
  double _totalSpeedSum = 0;
  int _speedSamples = 0;
  double _distanceKm = 0;
  final List<LatLng> _gpsPath = [];
  final List<TelemetrySample> _telemetrySamples = [];
  DriveDynamicsTracker _dynamicsTracker = DriveDynamicsTracker();
  LatLng? _lastPosition;
  DateTime? _lastTelemetrySampleTime;
  LatLng? _lastTelemetrySamplePosition;
  double _latestSpeedKmh = 0;

  // ── 급조작 감지 ──────────────────────────────────────────────
  static const double _sharpCornerGThreshold = 0.45; // G 임계값
  static const Duration _sharpCooldown = Duration(seconds: 3); // 연속 감지 방지
  final List<SharpCorner> _sharpCorners = [];
  DateTime? _lastSharpTime;

  RevvRoute? _route;
  String _weatherEmoji = '🌤';
  String _tempDisplay = '—';
  String _weatherDesc = '';

  // ── DriveMode 시간 추적 ────────────────────────────────────
  String _currentMode = 'cruise';
  DateTime? _currentModeStart;
  final Map<String, int> _driveModeSeconds = {};

  double get currentMaxSpeed => _maxSpeedKmh;
  double get currentDistance => _distanceKm;
  Duration get currentDuration =>
      _startTime != null ? _clock().difference(_startTime!) : Duration.zero;

  void startSession(
    RevvRoute? route, {
    String weatherEmoji = '🌤',
    String tempDisplay = '—',
    String weatherDesc = '',
  }) {
    final now = _clock();
    _enqueueRecoveryWrite((store) => store.clear());
    _startTime = now;
    _lastSnapshotTime = now;
    isRecording = true;
    _maxSpeedKmh = 0;
    _totalSpeedSum = 0;
    _speedSamples = 0;
    _distanceKm = 0;
    _gpsPath.clear();
    _telemetrySamples.clear();
    _dynamicsTracker = DriveDynamicsTracker();
    _lastPosition = null;
    _lastTelemetrySampleTime = null;
    _lastTelemetrySamplePosition = null;
    _latestSpeedKmh = 0;
    _route = route;
    _weatherEmoji = weatherEmoji;
    _tempDisplay = tempDisplay;
    _weatherDesc = weatherDesc;
    _currentMode = 'cruise';
    _currentModeStart = now;
    _driveModeSeconds.clear();
    _sharpCorners.clear();
    _lastSharpTime = null;
    _scheduleNotify();
  }

  void recordPosition(
    double lat,
    double lng,
    double speedKmh, {
    double lateralG = 0,
    double longitudinalG = 0,
    String? driveMode,
  }) {
    if (!isRecording) return;
    final point = LatLng(lat, lng);
    if (_lastPosition != null) {
      _distanceKm += RevvRoute.haversineKm(_lastPosition!, point);
    }
    _lastPosition = point;
    _gpsPath.add(point);
    _latestSpeedKmh = speedKmh;
    if (speedKmh > _maxSpeedKmh) _maxSpeedKmh = speedKmh;
    _totalSpeedSum += speedKmh;
    _speedSamples++;
    _recordTelemetrySample(
      point,
      speedKmh,
      lateralG: lateralG,
      longitudinalG: longitudinalG,
      driveMode: driveMode ?? _currentMode,
    );
    _dynamicsTracker.addSample(
      lateralG: lateralG,
      longitudinalG: longitudinalG,
      elapsed: currentDuration,
    );
    _writeSnapshotIfDue();
    _scheduleNotify();
  }

  void _writeSnapshotIfDue() {
    final startTime = _startTime;
    final lastSnapshotTime = _lastSnapshotTime;
    if (startTime == null || lastSnapshotTime == null) return;
    final now = _clock();
    if (now.difference(lastSnapshotTime) < const Duration(seconds: 30)) return;
    _lastSnapshotTime = now;
    final modeSeconds = Map<String, int>.of(_driveModeSeconds);
    final modeStart = _currentModeStart;
    if (modeStart != null) {
      modeSeconds[_currentMode] =
          (modeSeconds[_currentMode] ?? 0) +
          now.difference(modeStart).inSeconds;
    }
    final snapshot = RunRecoverySnapshot(
      startTime: startTime,
      routeId: _route?.id,
      routeName: _route?.name,
      gpsPath: List.of(_gpsPath),
      distanceKm: _distanceKm,
      maxSpeedKmh: _maxSpeedKmh,
      totalSpeedSum: _totalSpeedSum,
      speedSamples: _speedSamples,
      driveModeSeconds: modeSeconds,
      sharpCorners: List.of(_sharpCorners),
      telemetrySamples: List.of(_telemetrySamples),
      weatherEmoji: _weatherEmoji,
      tempDisplay: _tempDisplay,
      weatherDesc: _weatherDesc,
      lastSampleTime: now,
    );
    _enqueueRecoveryWrite((store) => store.writeSnapshot(snapshot));
  }

  void _recordTelemetrySample(
    LatLng point,
    double speedKmh, {
    required double lateralG,
    required double longitudinalG,
    required String driveMode,
  }) {
    final start = _startTime;
    if (start == null) return;
    final now = _clock();
    final lastTime = _lastTelemetrySampleTime;
    final lastPoint = _lastTelemetrySamplePosition;
    final movedKm = lastPoint == null
        ? double.infinity
        : RevvRoute.haversineKm(lastPoint, point);
    final enoughTime =
        lastTime == null || now.difference(lastTime).inMilliseconds >= 500;
    final meaningfulMove = movedKm >= 0.005;
    if (_telemetrySamples.isNotEmpty && !enoughTime && !meaningfulMove) {
      return;
    }
    _lastTelemetrySampleTime = now;
    _lastTelemetrySamplePosition = point;
    _telemetrySamples.add(
      TelemetrySample(
        tMs: now.difference(start).inMilliseconds,
        lat: point.lat,
        lng: point.lng,
        speedKmh: speedKmh,
        lateralG: lateralG,
        longitudinalG: longitudinalG,
        driveMode: driveMode,
      ),
    );
  }

  /// 급조작 순간 기록 — ImuService에서 G > 임계값 감지 시 호출
  void recordSharpCorner(
    double lat,
    double lng,
    double lateralG, {
    double? speedKmh,
    String? driveMode,
  }) {
    if (!isRecording) return;
    final now = _clock();
    // 쿨다운: 마지막 급조작 후 3초 이내 중복 감지 방지
    if (_lastSharpTime != null &&
        now.difference(_lastSharpTime!) < _sharpCooldown) {
      return;
    }
    if (lateralG.abs() < _sharpCornerGThreshold) return;
    _lastSharpTime = now;
    _sharpCorners.add(
      SharpCorner(
        position: LatLng(lat, lng),
        lateralG: lateralG.abs(),
        speedKmh: speedKmh ?? _latestSpeedKmh,
        driveMode: driveMode ?? _currentMode,
        time: now,
      ),
    );
  }

  /// 급조작 개수 실시간 조회
  int get sharpCornerCount => _sharpCorners.length;

  /// DriveMode 변경 시 호출 (mode.name 전달 → 'cruise' / 'winding' / 'sport')
  void recordDriveMode(String modeName) {
    if (!isRecording || modeName == _currentMode) return;
    _finalizeCurrentMode();
    _currentMode = modeName;
    _currentModeStart = _clock();
  }

  void _finalizeCurrentMode() {
    final start = _currentModeStart;
    if (start == null) return;
    final secs = _clock().difference(start).inSeconds;
    _driveModeSeconds[_currentMode] =
        (_driveModeSeconds[_currentMode] ?? 0) + secs;
  }

  /// maxLateralG, maxLonG는 ImuService에서 읽어 전달
  RunSession? stopSession({double maxLateralG = 0.0, double maxLonG = 0.0}) {
    if (!isRecording || _startTime == null) return null;
    isRecording = false;
    _dynamicsTracker.summarize();
    _finalizeCurrentMode();
    final session = RunSession(
      startTime: _startTime!,
      endTime: _clock(),
      maxSpeedKmh: _maxSpeedKmh,
      avgSpeedKmh: _speedSamples > 0 ? _totalSpeedSum / _speedSamples : 0,
      distanceKm: _distanceKm,
      gpsPath: List.unmodifiable(_gpsPath),
      route: _route,
      weatherEmoji: _weatherEmoji,
      tempDisplay: _tempDisplay,
      weatherDesc: _weatherDesc,
      maxLateralG: maxLateralG,
      maxLonG: maxLonG,
      driveModeSeconds: Map.unmodifiable(Map.of(_driveModeSeconds)),
      sharpCorners: List.unmodifiable(List.of(_sharpCorners)),
      telemetrySamples: List.unmodifiable(List.of(_telemetrySamples)),
    );
    _enqueueRecoveryWrite((store) => store.clear());
    _scheduleNotify();
    return session;
  }
}
