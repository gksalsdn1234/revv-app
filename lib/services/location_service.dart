import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService extends ChangeNotifier {
  static const defaultLat = 45.5019;
  static const defaultLng = -73.5674;

  Position? currentPosition;
  double speedKmh = 0;
  double heading = 0; // 이동 방향 (0=북, 90=동, 단위: degrees)
  bool hasPermission = false;
  bool isTracking = false;

  StreamSubscription<Position>? _subscription;
  bool _notifyPending = false;

  Future<void> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    hasPermission = status.isGranted;
    notifyListeners();
  }

  Future<void> startTracking() async {
    if (!hasPermission || isTracking) return;
    isTracking = true;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) {
      currentPosition = position;
      speedKmh = (position.speed * 3.6).clamp(0, 300);
      if (position.heading >= 0) heading = position.heading;
      _scheduleNotify();
    }, onError: (_) {
      // GPS 신호 없을 때 마지막 위치 유지, 속도 0
      speedKmh = 0;
      _scheduleNotify();
    });
  }

  void _scheduleNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyPending = false;
      notifyListeners();
    });
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
    isTracking = false;
  }

  double get lat => currentPosition?.latitude ?? defaultLat;
  double get lng => currentPosition?.longitude ?? defaultLng;

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
