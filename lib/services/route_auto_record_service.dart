import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/revv_route.dart';
import '../models/run_session.dart';
import 'route_service.dart';
import 'run_session_service.dart';
import 'location_service.dart';

enum AutoRecordState { idle, armed, recording, claimed }

class AutoRecordFix {
  const AutoRecordFix({
    required this.point,
    required this.speedKmh,
    required this.accuracyM,
    required this.timestamp,
  });

  final LatLng point;
  final double speedKmh;
  final double accuracyM;
  final DateTime timestamp;
}

class RouteAutoRecordService extends ChangeNotifier {
  RouteAutoRecordService({
    required RouteService routes,
    required RunSessionService sessions,
    LocationService? location,
    this.maxUnclaimedDuration = const Duration(hours: 8),
    this.offRouteGrace = const Duration(minutes: 5),
    this.onCompleted,
  }) : _routes = routes,
       _sessions = sessions,
       _location = location {
    _refreshArmedRoute();
  }

  static const double startRadiusKm = 0.08;
  static const double maxAccuracyM = 50;
  static const double minSpeedKmh = 8;
  static const Duration confirmationWindow = Duration(seconds: 5);

  final RouteService _routes;
  final RunSessionService _sessions;
  final LocationService? _location;
  final Duration maxUnclaimedDuration;
  final Duration offRouteGrace;
  final Future<void> Function(RunSession session)? onCompleted;
  bool _attached = false;
  AutoRecordState _state = AutoRecordState.idle;
  RevvRoute? _activeRoute;
  DateTime? _firstQualifyingAt;
  int _qualifyingFixes = 0;
  DateTime? _recordingStartedAt;
  DateTime? _offRouteSince;
  RunSession? _lastCompletedSession;
  Timer? _maxDurationTimer;

  AutoRecordState get state => _state;
  RevvRoute? get activeRoute => _activeRoute;
  RunSession? get lastCompletedSession => _lastCompletedSession;

  void attach() {
    if (_attached) return;
    _attached = true;
    _routes.addListener(_onRouteChanged);
    _location?.addListener(_onLocationChanged);
    _onRouteChanged();
  }

  void refreshArmedRoute() {
    _refreshArmedRoute();
    notifyListeners();
  }

  void handleFix(AutoRecordFix fix) {
    if (_state == AutoRecordState.claimed) return;
    if (_state == AutoRecordState.recording) {
      final startedAt = _recordingStartedAt;
      if (startedAt != null &&
          fix.timestamp.difference(startedAt) >= maxUnclaimedDuration) {
        _completeUnclaimedRecording();
        return;
      }
      if (fix.accuracyM > maxAccuracyM) return;
      final route = _activeRoute;
      if (route == null) {
        _completeUnclaimedRecording();
        return;
      }
      if (_distanceToRouteKm(fix.point, route) > 1) {
        _offRouteSince ??= fix.timestamp;
        if (fix.timestamp.difference(_offRouteSince!) >= offRouteGrace) {
          _completeUnclaimedRecording();
        }
        return;
      }
      _offRouteSince = null;
      final accepted = _sessions.recordPosition(
        fix.point.lat,
        fix.point.lng,
        fix.speedKmh,
        accuracyM: fix.accuracyM,
        sampleTime: fix.timestamp,
      );
      if (accepted && _hasReachedRouteEnd(fix.point, route)) {
        _completeUnclaimedRecording();
      }
      return;
    }

    final route = _routes.pendingGuideRoute;
    if (route == null || !_routes.hasFreshPendingGuide) {
      _setIdle();
      unawaited(_location?.stopArmedTracking());
      notifyListeners();
      return;
    }
    if (_sessions.isRecording) {
      _firstQualifyingAt = null;
      _qualifyingFixes = 0;
      return;
    }
    _activeRoute = route;
    _state = AutoRecordState.armed;
    final start = route.nodes.isEmpty ? route.centerPoint : route.nodes.first;
    final qualifies =
        fix.accuracyM <= maxAccuracyM &&
        fix.speedKmh >= minSpeedKmh &&
        RevvRoute.haversineKm(fix.point, start) <= startRadiusKm;
    if (!qualifies) {
      _firstQualifyingAt = null;
      _qualifyingFixes = 0;
      return;
    }

    _firstQualifyingAt ??= fix.timestamp;
    _qualifyingFixes++;
    final elapsed = fix.timestamp.difference(_firstQualifyingAt!);
    if (_qualifyingFixes < 2 || elapsed < confirmationWindow) return;

    _sessions.startSession(route);
    _sessions.recordPosition(
      fix.point.lat,
      fix.point.lng,
      fix.speedKmh,
      accuracyM: fix.accuracyM,
      sampleTime: fix.timestamp,
    );
    _state = AutoRecordState.recording;
    _recordingStartedAt = fix.timestamp;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(
      maxUnclaimedDuration,
      _completeUnclaimedRecording,
    );
    _offRouteSince = null;
    _routes.clearGuideToStart();
    notifyListeners();
  }

  /// 주행 화면은 `didChangeDependencies`에서 claim을 부른다 — 그 시점은 빌드
  /// 중이라 곧바로 notify하면 `setState() called during build`로 터진다.
  /// 상태 변경은 그대로 즉시 반영하고(호출자가 반환값을 동기적으로 쓴다),
  /// 알림만 마이크로태스크로 미뤄 빌드 단계를 벗어난다.
  void _notifyOutsideBuild() {
    scheduleMicrotask(notifyListeners);
  }

  bool claimRecording(String routeId) {
    if (_state != AutoRecordState.recording || _activeRoute?.id != routeId) {
      return false;
    }
    _state = AutoRecordState.claimed;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _recordingStartedAt = null;
    _offRouteSince = null;
    _notifyOutsideBuild();
    return true;
  }

  void claimManualDrive(String routeId) {
    if (_state == AutoRecordState.recording) return;
    if (_routes.pendingGuideRoute != null) {
      _routes.clearGuideToStart();
    }
    _state = AutoRecordState.claimed;
    _activeRoute = null;
    _firstQualifyingAt = null;
    _qualifyingFixes = 0;
    unawaited(_location?.stopArmedTracking());
    _notifyOutsideBuild();
  }

  void finish() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _recordingStartedAt = null;
    _offRouteSince = null;
    _refreshArmedRoute();
    if (_state == AutoRecordState.armed) {
      unawaited(_location?.startArmedTracking());
    } else {
      unawaited(_location?.stopArmedTracking());
    }
    notifyListeners();
  }

  void _onRouteChanged() {
    if (_state == AutoRecordState.recording ||
        _state == AutoRecordState.claimed) {
      return;
    }
    _refreshArmedRoute();
    if (_state == AutoRecordState.armed) {
      _location?.startArmedTracking();
    } else {
      _location?.stopArmedTracking();
    }
    notifyListeners();
  }

  void _onLocationChanged() {
    final position = _location?.currentPosition;
    if (position == null) return;
    handleFix(
      AutoRecordFix(
        point: LatLng(position.latitude, position.longitude),
        speedKmh: _location?.speedKmh ?? 0,
        accuracyM: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
  }

  void _refreshArmedRoute() {
    final route = _routes.pendingGuideRoute;
    if (route == null || !_routes.hasFreshPendingGuide) {
      _setIdle();
      return;
    }
    _activeRoute = route;
    _state = AutoRecordState.armed;
  }

  void _setIdle() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _state = AutoRecordState.idle;
    _activeRoute = null;
    _firstQualifyingAt = null;
    _qualifyingFixes = 0;
    _recordingStartedAt = null;
    _offRouteSince = null;
  }

  bool _hasReachedRouteEnd(LatLng point, RevvRoute route) {
    final end = route.nodes.isEmpty ? route.centerPoint : route.nodes.last;
    if (RevvRoute.haversineKm(point, end) > 0.15) return false;
    return _sessions.currentDistance >= math.max(0.3, route.distanceKm * 0.5);
  }

  double _distanceToRouteKm(LatLng point, RevvRoute route) {
    final nodes = route.nodes.isEmpty ? [route.centerPoint] : route.nodes;
    var nearest = double.infinity;
    for (final node in nodes) {
      nearest = math.min(nearest, RevvRoute.haversineKm(point, node));
    }
    return nearest;
  }

  void _completeUnclaimedRecording() {
    if (_state != AutoRecordState.recording) return;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    final session = _sessions.stopSession();
    _lastCompletedSession = session;
    _state = AutoRecordState.idle;
    _activeRoute = null;
    _recordingStartedAt = null;
    _offRouteSince = null;
    unawaited(_location?.stopArmedTracking());
    if (session != null && onCompleted != null) {
      unawaited(onCompleted!(session));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _maxDurationTimer?.cancel();
    if (_attached) {
      _routes.removeListener(_onRouteChanged);
      _location?.removeListener(_onLocationChanged);
    }
    super.dispose();
  }
}
