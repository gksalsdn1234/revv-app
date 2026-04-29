import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/storage_keys.dart';
import '../models/revv_route.dart';

class LocationService extends ChangeNotifier {
  static const LocationSettings _trackingSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5,
  );
  static const Duration _notifyThrottle = Duration(milliseconds: 250);

  Position? currentPosition;
  LatLng? _persistedLatLng;
  double speedKmh = 0;
  double heading = 0; // 이동 방향 (0=북, 90=동, 단위: degrees)
  bool hasPermission = false;
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  bool isTracking = false;
  bool _hydrated = false;

  StreamSubscription<Position>? _subscription;
  bool _notifyPending = false;
  Timer? _notifyTimer;
  DateTime? _lastNotifiedAt;

  LocationService() {
    unawaited(_hydrateLastKnownLocation());
  }

  Future<void> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    _permissionStatus = status;
    hasPermission = status.isGranted;
    notifyListeners();
  }

  PermissionStatus get permissionStatus => _permissionStatus;

  String get permissionStatusLabel {
    if (hasPermission) return '위치 허용됨';
    if (_permissionStatus.isPermanentlyDenied) return '설정에서 위치 권한 필요';
    if (_permissionStatus.isDenied) return '위치 권한 꺼짐';
    if (_permissionStatus.isRestricted) return '위치 권한 제한됨';
    return '위치 권한 확인 필요';
  }

  String? get lastFailureReason {
    if (hasPermission) return null;
    return '주변 루트 탐색에는 현재 위치 권한이 필요해요.';
  }

  Future<void> startTracking() async {
    if (!hasPermission || isTracking) return;
    isTracking = true;
    _subscription =
        Geolocator.getPositionStream(
          locationSettings: _trackingSettings,
        ).listen(
          (position) {
            _applyPosition(position);
            _scheduleNotify();
          },
          onError: (_) {
            // GPS 신호 없을 때 마지막 위치 유지, 속도 0
            speedKmh = 0;
            _scheduleNotify();
          },
        );
    await ensureLiveLocation(timeout: const Duration(seconds: 5));
  }

  void _scheduleNotify() {
    final now = DateTime.now();
    final last = _lastNotifiedAt;
    if (last == null || now.difference(last) >= _notifyThrottle) {
      _emitNotify();
      return;
    }

    if (_notifyPending) return;
    _notifyPending = true;
    final wait = _notifyThrottle - now.difference(last);
    _notifyTimer = Timer(wait, () {
      _notifyPending = false;
      _emitNotify();
    });
  }

  void _emitNotify() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _lastNotifiedAt = DateTime.now();
    notifyListeners();
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
    isTracking = false;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _notifyPending = false;
  }

  bool get hasLiveLocation => currentPosition != null;

  LatLng? get liveLatLng => currentPosition == null
      ? null
      : LatLng(currentPosition!.latitude, currentPosition!.longitude);

  LatLng? get bestKnownLatLng => liveLatLng ?? _persistedLatLng;

  bool get hasBestKnownLocation => bestKnownLatLng != null;

  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await _hydrateLastKnownLocation();
    if (!hasPermission) {
      final status = await Permission.locationWhenInUse.status;
      _permissionStatus = status;
      hasPermission = status.isGranted;
      if (!hasPermission) return bestKnownLatLng;
    }
    final current = liveLatLng;
    if (_isFreshEnough(currentPosition)) return current;

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (_isFreshEnough(lastKnown)) {
      _applyPosition(lastKnown!);
      notifyListeners();
      return liveLatLng;
    }

    if (isTracking) {
      final tracked = await _awaitTrackedLocation(timeout);
      if (tracked != null) return tracked;
    }

    final streamed = await _awaitSingleStreamLocation(timeout);
    if (streamed != null) return streamed;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: timeout,
        ),
      );
      _applyPosition(position);
      notifyListeners();
    } catch (_) {
      // 마지막 fallback까지 실패하면 null 유지
    }

    return liveLatLng;
  }

  void _applyPosition(Position position) {
    currentPosition = position;
    speedKmh = (position.speed * 3.6).clamp(0, 300);
    if (position.heading >= 0) heading = position.heading;
    _persistedLatLng = LatLng(position.latitude, position.longitude);
    unawaited(_persistLastKnownLocation());
  }

  bool _isFreshEnough(Position? position) {
    if (position == null) return false;
    final timestamp = position.timestamp;
    return DateTime.now().difference(timestamp).inMinutes < 2;
  }

  Future<LatLng?> _awaitTrackedLocation(Duration timeout) async {
    if (_isFreshEnough(currentPosition)) return liveLatLng;
    final completer = Completer<LatLng?>();

    void listener() {
      if (!_isFreshEnough(currentPosition) || completer.isCompleted) return;
      completer.complete(liveLatLng);
      removeListener(listener);
    }

    addListener(listener);
    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      removeListener(listener);
      return liveLatLng;
    }
  }

  Future<LatLng?> _awaitSingleStreamLocation(Duration timeout) async {
    StreamSubscription<Position>? tempSubscription;
    final completer = Completer<LatLng?>();

    tempSubscription =
        Geolocator.getPositionStream(
          locationSettings: _trackingSettings,
        ).listen(
          (position) {
            _applyPosition(position);
            if (!completer.isCompleted) {
              completer.complete(liveLatLng);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        );

    try {
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      if (result != null) {
        notifyListeners();
      }
      return result;
    } finally {
      await tempSubscription.cancel();
    }
  }

  Future<void> _hydrateLastKnownLocation() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(StorageKeys.lastKnownLat);
      final lng = prefs.getDouble(StorageKeys.lastKnownLng);
      if (lat != null && lng != null) {
        _persistedLatLng = LatLng(lat, lng);
      }
    } catch (_) {
      _hydrated = false;
    }
  }

  Future<void> _persistLastKnownLocation() async {
    final last = _persistedLatLng;
    if (last == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(StorageKeys.lastKnownLat, last.lat);
      await prefs.setDouble(StorageKeys.lastKnownLng, last.lng);
    } catch (_) {}
  }

  double get lat => bestKnownLatLng?.lat ?? 0.0;
  double get lng => bestKnownLatLng?.lng ?? 0.0;

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
