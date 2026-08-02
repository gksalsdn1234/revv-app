import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_turn_service.dart';

void main() {
  test('fetchSteps downsamples route nodes and parses Mapbox maneuvers', () async {
    final requested = <Uri>[];
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient((request) async {
        requested.add(request.url);
        return http.Response(_directionsFixture, 200);
      }),
    );

    final steps = await service.fetchSteps(
      List.generate(40, (index) => LatLng(45 + index * 0.001, -73)),
    );

    expect(requested.single.pathSegments.last.split(';'), hasLength(25));
    expect(requested.single.queryParameters['waypoints'], '0;24');
    expect(steps, hasLength(2));
    expect(steps.first.maneuverType, 'fork');
    expect(steps.first.location.lat, 45.001);
    expect(steps.first.location.lng, -73.001);
    expect(steps.first.call(AppLanguage.korean), '우측 갈림길');
    expect(steps.first.call(AppLanguage.english), 'fork right');
    expect(steps.first.call(AppLanguage.french), 'bifurcation droite');
    // Mapbox step.distance is the distance from this maneuver to the next.
    expect(steps.first.distanceFromStartM, 0);
    expect(steps.last.distanceFromStartM, 120);
  });

  test('fetchSteps keeps only the first and last sampled nodes as waypoints', () async {
    final requested = <Uri>[];
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient((request) async {
        requested.add(request.url);
        return http.Response(_directionsFixture, 200);
      }),
    );

    await service.fetchSteps(
      List.generate(8, (index) => LatLng(45 + index * 0.001, -73)),
    );

    expect(requested.single.queryParameters['waypoints'], '0;7');
  });

  test('fetchSteps returns an empty list when Mapbox fails', () async {
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient((_) async => http.Response('nope', 500)),
    );

    final steps = await service.fetchSteps(const [
      LatLng(45, -73),
      LatLng(45.01, -73.01),
    ]);

    expect(steps, isEmpty);
  });

  test('recalculateSteps observes the 60 second cooldown', () async {
    var now = DateTime(2026, 7, 9, 10);
    var calls = 0;
    final service = RouteTurnService(
      accessToken: 'token',
      clock: () => now,
      client: _FakeClient((_) async {
        calls++;
        return http.Response(_directionsFixture, 200);
      }),
    );

    const current = LatLng(45, -73);
    const rejoin = LatLng(45.01, -73.01);
    await service.recalculateSteps(current: current, rejoin: rejoin);
    await service.recalculateSteps(current: current, rejoin: rejoin);
    now = now.add(const Duration(seconds: 61));
    await service.recalculateSteps(current: current, rejoin: rejoin);

    expect(calls, 2);
  });

  test('nextStepProgress advances through ordered steps', () {
    final progress = nextStepProgress(
      const LatLng(45.0005, -73),
      const [LatLng(45, -73), LatLng(45.01, -73)],
      const [
        NavStep(
          sequence: 1,
          maneuverType: 'fork',
          modifier: 'right',
          location: LatLng(45.001, -73),
          distanceFromStartM: 110,
        ),
        NavStep(
          sequence: 2,
          maneuverType: 'turn',
          modifier: 'left',
          location: LatLng(45.005, -73),
          distanceFromStartM: 550,
        ),
      ],
    );

    expect(progress?.step.sequence, 1);
    expect(progress?.aheadM, inInclusiveRange(40, 70));
  });

  test('recalculated turns stay ahead through route rejoin', () async {
    const routeNodes = [
      LatLng(45.000, -73),
      LatLng(45.003, -73),
      LatLng(45.006, -73),
      LatLng(45.009, -73),
    ];
    const offRoute = LatLng(45.004, -73);
    const rejoin = LatLng(45.006, -73);
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient((_) async => http.Response(_directionsFixture, 200)),
    );
    final recalculated = await service.recalculateSteps(
      current: offRoute,
      rejoin: rejoin,
    );
    final recoverySteps = offsetNavSteps(
      recalculated.where((step) => step.sequence == 2).toList(),
      routeDistanceFromStart(rejoin, routeNodes),
    );

    final beforeRejoin = nextStepProgress(
      offRoute,
      routeNodes,
      recoverySteps,
    );
    final atRejoin = nextStepProgress(rejoin, routeNodes, recoverySteps);

    expect(beforeRejoin?.step.sequence, 2);
    expect(atRejoin?.step.sequence, 2);
    expect(beforeRejoin!.aheadM, greaterThan(atRejoin!.aheadM));
    expect(atRejoin.aheadM, inInclusiveRange(118, 122));
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

final _directionsFixture = jsonEncode({
  'routes': [
    {
      'legs': [
        {
          'steps': [
            {
              'distance': 120.0,
              'maneuver': {
                'type': 'fork',
                'modifier': 'right',
                'location': [-73.001, 45.001],
              },
            },
            {
              'distance': 80.0,
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': [-73.002, 45.002],
              },
            },
          ],
        },
      ],
    },
  ],
});
