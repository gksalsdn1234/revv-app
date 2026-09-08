import 'route_performance.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/storage_keys.dart';
import '../models/revv_route.dart';

class LocationService extends ChangeNotifier {
  static const Duration _notifyThrottle = Duration(milliseconds: 250);

  Position? currentPosition;
  double speedKmh = 0;
  double heading = 0; // 이동 방향 (0=북, 90=동, 단위: degrees)
  bool hasPermission = false;
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  bool isTracking = false;
  bool _disposed = false;
  bool _armedBackgroundTracking = false;
  bool _driveBackgroundTracking = false;
  bool _permissionChecked = false;
  Future<void>? _permissionRequest;
  Future<LatLng?>? _locationRequest;
  final Future<PermissionStatus> Function() _permissionRequester;
  final Future<PermissionStatus> Function() _permissionChecker;
  bool get permissionChecked => _permissionChecked;
  bool get isRequestingPermission => _permissionRequest != null;
  bool get isLocating => _locationRequest != null;
  int _armedTrackingRequest = 0;

  StreamSubscription<Position>? _subscription;
  bool _notifyPending = false;
  Timer? _notifyTimer;
  DateTime? _lastNotifiedAt;

  LocationService({
    Future<PermissionStatus> Function()? permissionRequester,
    Future<PermissionStatus> Function()? permissionChecker,
  }) : _permissionRequester =
           permissionRequester ??
           (() => Permission.locationWhenInUse.request()),
       _permissionChecker =
           permissionChecker ?? (() => Permission.locationWhenInUse.status) {
    unawaited(_clearLegacyPersistedLocation());
  }

  Future<void> _clearLegacyPersistedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.lastKnownLat);
      await prefs.remove(StorageKeys.lastKnownLng);
    } catch (_) {}
  }

  Future<void> requestPermission() => _permissionRequest ??=
      _requestPermission().whenComplete(() => _permissionRequest = null);

  Future<void> _requestPermission() async {
    final current = await _permissionChecker();
    final status =
        current.isGranted || current.isPermanentlyDenied || current.isRestricted
        ? current
        : await RoutePerformance.measure(
            'location.permission',
            _permissionRequester,
          );
    _permissionStatus = status;
    _permissionChecked = true;
    hasPermission = status.isGranted;
    notifyListeners();
  }

  Future<void> refreshPermission() async {
    final status = await _permissionChecker();
    if (_disposed) return;
    _permissionStatus = status;
    _permissionChecked = true;
    hasPermission = status.isGranted;
    if (!hasPermission) stopTracking();
    notifyListeners();
  }

  PermissionStatus get permissionStatus => _permissionStatus;

  String get permissionStatusLabel {
    if (hasPermission) return '위치 허용됨';
    if (!_permissionChecked) return '위치 권한 확인 중';
    if (_permissionStatus.isPermanentlyDenied) return '설정에서 위치 권한 필요';
    if (_permissionStatus.isDenied) return '위치 권한 꺼짐';
    if (_permissionStatus.isRestricted) return '위치 권한 제한됨';
    return '위치 권한 확인 필요';
  }

  String? get lastFailureReason {
    if (hasPermission || !_permissionChecked) return null;
    return '주변 루트 탐색에는 현재 위치 권한이 필요해요.';
  }

  Future<void> startTracking() async {
    if (_disposed || !hasPermission || isTracking) return;
    isTracking = true;
    _subscription =
        Geolocator.getPositionStream(
          locationSettings: _trackingSettings(
            _armedBackgroundTracking || _driveBackgroundTracking,
          ),
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

  Future<void> startArmedTracking() async {
    final request = ++_armedTrackingRequest;
    final wasArmed = _armedBackgroundTracking;
    _armedBackgroundTracking = true;
    if (!hasPermission) await requestPermission();
    if (request != _armedTrackingRequest || !_armedBackgroundTracking) return;
    if (!hasPermission) {
      _armedBackgroundTracking = false;
      return;
    }
    if (Platform.isAndroid) {
      await Permission.locationAlways.request();
      if (request != _armedTrackingRequest || !_armedBackgroundTracking) {
        return;
      }
    }
    if (wasArmed && isTracking) return;
    if (isTracking) stopTracking();
    await startTracking();
  }

  Future<void> stopArmedTracking() async {
    _armedTrackingRequest++;
    if (!_armedBackgroundTracking) return;
    _armedBackgroundTracking = false;
    if (isTracking && !_driveBackgroundTracking) {
      stopTracking();
      await startTracking();
    }
  }

  Future<void> startDriveTracking() async {
    if (_driveBackgroundTracking && isTracking) return;
    _driveBackgroundTracking = true;
    if (isTracking) stopTracking();
    await startTracking();
  }

  Future<void> stopDriveTracking() async {
    if (!_driveBackgroundTracking) return;
    _driveBackgroundTracking = false;
    if (isTracking && !_armedBackgroundTracking) {
      stopTracking();
      await startTracking();
    }
  }

  LocationSettings _trackingSettings(bool background) {
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: background,
        allowBackgroundLocationUpdates: background,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: 'REVV route recording',
                notificationText:
                    'Waiting for the route start and recording your drive.',
                enableWakeLock: true,
              )
            : null,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
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

  LatLng? get bestKnownLatLng => liveLatLng;

  bool get hasBestKnownLocation => bestKnownLatLng != null;

  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) => _locationRequest ??= RoutePerformance.measure(
    'location.fix',
    () => _ensureLiveLocation(timeout: timeout),
  ).whenComplete(() => _locationRequest = null);

  Future<LatLng?> _ensureLiveLocation({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    Duration remaining() {
      final left = deadline.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }

    try {
      if (!hasPermission) {
        final status = await _permissionChecker().timeout(remaining());
        _permissionStatus = status;
        _permissionChecked = true;
        hasPermission = status.isGranted;
        if (!hasPermission || _disposed) return null;
      }
      if (_isFreshEnough(currentPosition)) return liveLatLng;
      final lastKnown = await Geolocator.getLastKnownPosition().timeout(
        Duration(microseconds: remaining().inMicroseconds ~/ 3),
        onTimeout: () => null,
      );
      if (_disposed) return null;
      if (_isFreshEnough(lastKnown)) {
        _applyPosition(lastKnown!);
        notifyListeners();
        return liveLatLng;
      }
      if (remaining() == Duration.zero) return null;
      // The retained subscription can supply a fix for the entire remaining
      // budget. A second subscription would compete with its native settings.
      if (isTracking) return await _awaitTrackedLocation(remaining());
      final streamed = await _awaitSingleStreamLocation(
        Duration(microseconds: remaining().inMicroseconds ~/ 2),
      );
      if (streamed != null || _disposed) return streamed;
      if (remaining() == Duration.zero) return null;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: remaining(),
        ),
      ).timeout(remaining());
      if (_disposed) return null;
      _applyPosition(position);
      notifyListeners();
      return liveLatLng;
    } catch (_) {
      return _isFreshEnough(currentPosition) ? liveLatLng : null;
    }
  }

  void _applyPosition(Position position) {
    currentPosition = position;
    speedKmh = (position.speed * 3.6).clamp(0, 300);
    if (position.heading >= 0) heading = position.heading;
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
      return _isFreshEnough(currentPosition) ? liveLatLng : null;
    }
  }

  Future<LatLng?> _awaitSingleStreamLocation(Duration timeout) async {
    StreamSubscription<Position>? tempSubscription;
    final completer = Completer<LatLng?>();
    var accepting = true;

    tempSubscription =
        Geolocator.getPositionStream(
          locationSettings: _trackingSettings(false),
        ).listen(
          (position) {
            if (!accepting || _disposed) return;
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
      accepting = false;
      unawaited(tempSubscription.cancel().catchError((Object _) {}));
    }
  }

  double get lat => bestKnownLatLng?.lat ?? 0.0;
  double get lng => bestKnownLatLng?.lng ?? 0.0;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopTracking();
    super.dispose();
  }
}
