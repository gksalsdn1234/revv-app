import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/services/route_auto_record_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_session_service.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts after two accurate moving fixes in the start zone', () {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService();
    final service = RouteAutoRecordService(routes: routes, sessions: sessions);
    final firstAt = DateTime.utc(2026, 7, 12, 20);

    service.handleFix(
      AutoRecordFix(
        point: _route.nodes.first,
        speedKmh: 20,
        accuracyM: 8,
        timestamp: firstAt,
      ),
    );
    expect(sessions.isRecording, isFalse);

    service.handleFix(
      AutoRecordFix(
        point: const LatLng(45.0001, -73.0001),
        speedKmh: 22,
        accuracyM: 9,
        timestamp: firstAt.add(const Duration(seconds: 6)),
      ),
    );

    expect(service.state, AutoRecordState.recording);
    expect(service.activeRoute?.id, _route.id);
    expect(sessions.isRecording, isTrue);
    expect(sessions.currentRoute?.id, _route.id);
    expect(routes.pendingGuideRoute, isNull);
  });

  test('rejects poor accuracy, stationary fixes, and GPS spikes', () {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService();
    final service = RouteAutoRecordService(routes: routes, sessions: sessions);
    final now = DateTime.utc(2026, 7, 12, 20);

    service.handleFix(
      AutoRecordFix(
        point: _route.nodes.first,
        speedKmh: 20,
        accuracyM: 90,
        timestamp: now,
      ),
    );
    service.handleFix(
      AutoRecordFix(
        point: _route.nodes.first,
        speedKmh: 2,
        accuracyM: 5,
        timestamp: now.add(const Duration(seconds: 6)),
      ),
    );
    service.handleFix(
      AutoRecordFix(
        point: const LatLng(46, -74),
        speedKmh: 30,
        accuracyM: 5,
        timestamp: now.add(const Duration(seconds: 12)),
      ),
    );

    expect(service.state, AutoRecordState.armed);
    expect(sessions.isRecording, isFalse);
  });

  test('drive screen claim preserves the auto-started session', () {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService();
    final service = RouteAutoRecordService(routes: routes, sessions: sessions);
    final firstAt = DateTime.utc(2026, 7, 12, 20);
    for (final seconds in [0, 6]) {
      service.handleFix(
        AutoRecordFix(
          point: LatLng(45 + seconds / 100000, -73),
          speedKmh: 20,
          accuracyM: 5,
          timestamp: firstAt.add(Duration(seconds: seconds)),
        ),
      );
    }

    expect(service.claimRecording(_route.id), isTrue);
    expect(service.state, AutoRecordState.claimed);
    final distanceBefore = sessions.currentDistance;
    service.handleFix(
      AutoRecordFix(
        point: const LatLng(45.002, -73),
        speedKmh: 25,
        accuracyM: 5,
        timestamp: firstAt.add(const Duration(seconds: 12)),
      ),
    );
    expect(sessions.currentDistance, distanceBefore);
  });

  test('unclaimed background recording stops at its duration limit', () async {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService();
    RunSession? completed;
    final service = RouteAutoRecordService(
      routes: routes,
      sessions: sessions,
      maxUnclaimedDuration: const Duration(minutes: 30),
      onCompleted: (session) async => completed = session,
    );
    final startedAt = DateTime.utc(2026, 7, 12, 20);
    for (final seconds in [0, 6]) {
      service.handleFix(
        AutoRecordFix(
          point: LatLng(45 + seconds / 100000, -73),
          speedKmh: 20,
          accuracyM: 5,
          timestamp: startedAt.add(Duration(seconds: seconds)),
        ),
      );
    }

    service.handleFix(
      AutoRecordFix(
        point: const LatLng(45.005, -73.005),
        speedKmh: 20,
        accuracyM: 5,
        timestamp: startedAt.add(const Duration(minutes: 31)),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.state, AutoRecordState.idle);
    expect(sessions.isRecording, isFalse);
    expect(completed, isNotNull);
  });

  test('duration timer stops recording without another GPS fix', () async {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService();
    RunSession? completed;
    final service = RouteAutoRecordService(
      routes: routes,
      sessions: sessions,
      maxUnclaimedDuration: const Duration(milliseconds: 20),
      onCompleted: (session) async => completed = session,
    );
    addTearDown(service.dispose);
    final startedAt = DateTime.utc(2026, 7, 12, 20);
    for (final seconds in [0, 6]) {
      service.handleFix(
        AutoRecordFix(
          point: LatLng(45 + seconds / 100000, -73),
          speedKmh: 20,
          accuracyM: 5,
          timestamp: startedAt.add(Duration(seconds: seconds)),
        ),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(service.state, AutoRecordState.idle);
    expect(sessions.isRecording, isFalse);
    expect(completed, isNotNull);
  });

  test('armed auto record never overwrites a manual session', () {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService()..startSession(_manualRoute);
    final service = RouteAutoRecordService(routes: routes, sessions: sessions);
    final startedAt = sessions.currentStartTime;
    final now = DateTime.utc(2026, 7, 12, 20);

    for (final seconds in [0, 6]) {
      service.handleFix(
        AutoRecordFix(
          point: _route.nodes.first,
          speedKmh: 20,
          accuracyM: 5,
          timestamp: now.add(Duration(seconds: seconds)),
        ),
      );
    }

    expect(sessions.currentRoute?.id, _manualRoute.id);
    expect(sessions.currentStartTime, startedAt);
    expect(service.state, AutoRecordState.armed);
  });

  test('manual claim disarms the same pending route', () {
    final routes = RouteService()..beginGuideToStart(_route);
    final sessions = RunSessionService();
    final location = _FakeLocationService();
    final service = RouteAutoRecordService(
      routes: routes,
      sessions: sessions,
      location: location,
    );

    service.claimManualDrive(_route.id);

    expect(service.state, AutoRecordState.claimed);
    expect(routes.pendingGuideRoute, isNull);
    expect(location.stopCalls, 1);
  });

  test('manual claim disarms an unrelated pending route', () {
    final routes = RouteService()..beginGuideToStart(_route);
    final location = _FakeLocationService();
    final service = RouteAutoRecordService(
      routes: routes,
      sessions: RunSessionService(),
      location: location,
    );

    service.claimManualDrive(_manualRoute.id);

    expect(service.state, AutoRecordState.claimed);
    expect(routes.pendingGuideRoute, isNull);
    expect(location.stopCalls, 1);
  });

  test('expired pending route stops armed background tracking', () async {
    final routes = RouteService()..beginGuideToStart(_route);
    final location = _FakeLocationService();
    final service = RouteAutoRecordService(
      routes: routes,
      sessions: RunSessionService(),
      location: location,
    );
    routes.pendingGuideStartedAt = DateTime.now().subtract(
      const Duration(hours: 25),
    );

    service.handleFix(
      AutoRecordFix(
        point: _route.nodes.first,
        speedKmh: 20,
        accuracyM: 5,
        timestamp: DateTime.now(),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.state, AutoRecordState.idle);
    expect(location.stopCalls, 1);
  });

  test('arming restarts an existing foreground location stream', () async {
    final location = _FakeLocationService()
      ..hasPermission = true
      ..isTracking = true;

    await location.startArmedTracking();

    expect(location.stopCalls, 1);
    expect(location.startCalls, 1);
  });
}

class _FakeLocationService extends LocationService {
  int stopCalls = 0;
  int startCalls = 0;

  @override
  Future<void> startTracking() async {
    startCalls++;
    isTracking = true;
  }

  @override
  void stopTracking() {
    stopCalls++;
    isTracking = false;
  }

  @override
  Future<void> stopArmedTracking() async {
    stopCalls++;
  }
}

const _route = RevvRoute(
  id: 'route',
  name: 'Route',
  nodes: [LatLng(45, -73), LatLng(45.01, -73.01)],
  distanceKm: 2,
  distanceFromUser: 0,
  windingScore: 4,
  starRating: 3,
  sharpCurveCount: 2,
  centerPoint: LatLng(45.005, -73.005),
);

const _manualRoute = RevvRoute(
  id: 'manual',
  name: 'Manual',
  nodes: [LatLng(46, -74), LatLng(46.01, -74.01)],
  distanceKm: 2,
  distanceFromUser: 0,
  windingScore: 2,
  starRating: 2,
  sharpCurveCount: 1,
  centerPoint: LatLng(46.005, -74.005),
);
