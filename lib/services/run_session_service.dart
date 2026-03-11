import 'package:flutter/material.dart';
import '../models/run_session.dart';
import '../models/revv_route.dart';

class RunSessionService extends ChangeNotifier {
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
    notifyListeners();
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
    notifyListeners();
  }

  RunSession? stopSession() {
    if (!isRecording || _startTime == null) return null;
    isRecording = false;
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
    );
    notifyListeners();
    return session;
  }
}
