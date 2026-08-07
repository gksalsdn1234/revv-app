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
  bool _armedBackgroundTracking = false;
  int _armedTrackingRequest = 0;

  StreamSubscription<Position>? _subscription;
  bool _notifyPending = false;
  Timer? _notifyTimer;
  DateTime? _lastNotifiedAt;

  LocationService() {
    unawaited(_clearLegacyPersistedLocation());
  }

  Future<void> _clearLegacyPersistedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.lastKnownLat);
      await prefs.remove(StorageKeys.lastKnownLng);
    } catch (_) {}
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
          locationSettings: _trackingSettings(_armedBackgroundTracking),
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
    // 노림수: 사용자가 구글맵/Waze 로 루트 시작점까지 가는 동안 REVV 는
    // 백그라운드에 있고, 도착해서 출발하면 RouteAutoRecordService 가 알아서
    // 주행 기록을 시작한다 — 앱을 다시 열 필요가 없다.
    //
    // Always 권한은 iOS 에서 요청하지 않는다. 첫 App Store 제출에 얹기에
    // 심사 리스크가 커서 Info.plist 의 purpose string 도 함께 뺐다.
    //
    // 그렇다고 iOS 에서 무장 추적이 죽는 것은 아니다. When In Use 권한이라도
    // 포그라운드에서 시작한 위치 스트림은 UIBackgroundModes=location 과
    // _trackingSettings 의 allowBackgroundLocationUpdates 로 백그라운드에서
    // 이어진다. Always 가 필요한 영역은 "앱이 종료된 뒤 위치 이벤트로
    // 재실행되는" 경우다 — 그건 지원하지 않는 게 맞다.
    //
    // ⚠ 다만 이 동작은 아직 실기기에서 확인하지 않았다. 제출 전에 확인할 것:
    // 루트를 armed 로 만들고 백그라운드 전환 → 파란 위치 표시가 뜨는지,
    // 시작점에서 자동 기록이 시작되는지, 강제 종료 후에는 재개되지 않는지,
    // 주행 종료·루트 취소 시 표시와 업데이트가 즉시 멈추는지.
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
    if (isTracking) {
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
  }) async {
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
          locationSettings: _trackingSettings(false),
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

  double get lat => bestKnownLatLng?.lat ?? 0.0;
  double get lng => bestKnownLatLng?.lng ?? 0.0;

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
