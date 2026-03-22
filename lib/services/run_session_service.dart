import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/run_session.dart';
import '../models/revv_route.dart';

class RunSessionService extends ChangeNotifier {
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
  LatLng? _lastPosition;

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
      _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  void startSession(
    RevvRoute? route, {
    String weatherEmoji = '🌤',
    String tempDisplay = '—',
    String weatherDesc = '',
  }) {
    _startTime = DateTime.now();
    isRecording = true;
    _maxSpeedKmh = 0;
    _totalSpeedSum = 0;
    _speedSamples = 0;
    _distanceKm = 0;
    _gpsPath.clear();
    _lastPosition = null;
    _route = route;
    _weatherEmoji = weatherEmoji;
    _tempDisplay = tempDisplay;
    _weatherDesc = weatherDesc;
    _currentMode = 'cruise';
    _currentModeStart = DateTime.now();
    _driveModeSeconds.clear();
    _scheduleNotify();
  }

  void recordPosition(double lat, double lng, double speedKmh) {
    if (!isRecording) return;
    final point = LatLng(lat, lng);
    if (_lastPosition != null) {
      _distanceKm += RevvRoute.haversineKm(_lastPosition!, point);
    }
    _lastPosition = point;
    _gpsPath.add(point);
    if (speedKmh > _maxSpeedKmh) _maxSpeedKmh = speedKmh;
    _totalSpeedSum += speedKmh;
    _speedSamples++;
    _scheduleNotify();
  }

  /// DriveMode 변경 시 호출 (mode.name 전달 → 'cruise' / 'winding' / 'sport')
  void recordDriveMode(String modeName) {
    if (!isRecording || modeName == _currentMode) return;
    _finalizeCurrentMode();
    _currentMode = modeName;
    _currentModeStart = DateTime.now();
  }

  void _finalizeCurrentMode() {
    final start = _currentModeStart;
    if (start == null) return;
    final secs = DateTime.now().difference(start).inSeconds;
    _driveModeSeconds[_currentMode] = (_driveModeSeconds[_currentMode] ?? 0) + secs;
  }

  /// maxLateralG, maxLonG는 ImuService에서 읽어 전달
  RunSession? stopSession({
    double maxLateralG = 0.0,
    double maxLonG = 0.0,
  }) {
    if (!isRecording || _startTime == null) return null;
    isRecording = false;
    _finalizeCurrentMode();
    final session = RunSession(
      startTime: _startTime!,
      endTime: DateTime.now(),
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
    );
    _scheduleNotify();
    return session;
  }
}
