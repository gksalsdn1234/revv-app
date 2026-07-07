import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/recommendation_log_service.dart';

void main() {
  test('logShown inserts rounded origin and route ids', () async {
    final payloads = <Map<String, Object?>>[];
    final service = RecommendationLogService.forTesting(
      insert: (payload) async => payloads.add(payload),
    );

    await service.logShown(
      mode: 'destination',
      routeIds: const ['a', 'b'],
      origin: const LatLng(45.54, -73.64),
      budgetMinutes: 60,
    );

    expect(payloads.single, {
      'event': 'shown',
      'mode': 'destination',
      'route_ids': ['a', 'b'],
      'origin_geohash4': '45.5,-73.6',
      'budget_minutes': 60,
    });
  });

  test('logChosen inserts one chosen route id and option kind', () async {
    final payloads = <Map<String, Object?>>[];
    final service = RecommendationLogService.forTesting(
      insert: (payload) async => payloads.add(payload),
    );

    await service.logChosen(
      mode: 'chain',
      routeId: 'route-1',
      optionKind: 'standard',
      origin: const LatLng(45.56, -73.66),
      budgetMinutes: 30,
    );

    expect(payloads.single, {
      'event': 'chosen',
      'mode': 'chain',
      'route_ids': ['route-1'],
      'option_kind': 'standard',
      'origin_geohash4': '45.6,-73.7',
      'budget_minutes': 30,
    });
  });

  test('insert failure is swallowed', () async {
    final service = RecommendationLogService.forTesting(
      insert: (_) async => throw StateError('offline'),
    );

    await expectLater(
      service.logShown(mode: 'destination', routeIds: const ['a']),
      completes,
    );
  });

  test('cloud unavailable is a no-op', () async {
    var inserts = 0;
    final service = RecommendationLogService.forTesting(
      isCloudAvailable: () => false,
      insert: (_) async => inserts++,
    );

    await service.logShown(mode: 'destination', routeIds: const ['a']);

    expect(inserts, 0);
  });
}
