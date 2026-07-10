import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('beginGuideToStart persists pending drive and clear removes it', () async {
    SharedPreferences.setMockInitialValues({});
    final service = RouteService();

    service.beginGuideToStart(_route);
    await Future<void>.delayed(Duration.zero);

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.pendingDriveRouteId), 'route');
    expect(service.hasFreshPendingGuide, isTrue);

    service.clearGuideToStart();
    await Future<void>.delayed(Duration.zero);

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.pendingDriveRouteId), isNull);
  });

  test('pending drive prompt only appears within 500m', () {
    final service = RouteService();
    service.pendingGuideRoute = _route;
    service.pendingGuideStartedAt = DateTime.now();

    expect(service.shouldPromptPendingDrive(distanceKm: 0.49), isTrue);
    expect(service.shouldPromptPendingDrive(distanceKm: 0.51), isFalse);
  });

  test('pending guide expires after 24 hours', () async {
    SharedPreferences.setMockInitialValues({});
    final service = RouteService();

    service.pendingGuideRoute = _route;
    service.pendingGuideStartedAt = DateTime.now().subtract(
      const Duration(hours: 25),
    );

    expect(service.hasFreshPendingGuide, isFalse);
    expect(service.shouldPromptPendingDrive(distanceKm: 0.2), isFalse);
  });
}

const _route = RevvRoute(
  id: 'route',
  name: 'Route',
  nodes: [LatLng(45, -73), LatLng(45.01, -73.01)],
  distanceKm: 1,
  distanceFromUser: 0,
  windingScore: 1,
  starRating: 1,
  sharpCurveCount: 1,
  centerPoint: LatLng(45, -73),
);
