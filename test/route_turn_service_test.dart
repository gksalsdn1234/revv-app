import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_turn_service.dart';

void main() {
  test(
    'fetchSteps downsamples route nodes and parses Mapbox maneuvers',
    () async {
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
      expect(steps, hasLength(2));
      expect(steps.first.maneuverType, 'fork');
      expect(steps.first.location.lat, 45.001);
      expect(steps.first.location.lng, -73.001);
      expect(steps.first.call(AppLanguage.korean), '우측 갈림길');
      expect(steps.first.call(AppLanguage.english), 'fork right');
      expect(steps.first.call(AppLanguage.french), 'bifurcation à droite');
      expect(steps.first.distanceFromStartM, 0);
      expect(steps.first.segmentDistanceM, 120);
      expect(steps.last.distanceFromStartM, 120);
      expect(steps.last.segmentDistanceM, 80);
    },
  );

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

  test('resetRecalculationCooldown starts a new off-route episode', () async {
    final client = _FakeClient(
      (_) async => http.Response(_directionsFixture, 200),
    );
    final service = RouteTurnService(client: client, accessToken: 'token');
    const current = LatLng(45, -73);
    const rejoin = LatLng(45.01, -73.01);

    expect(
      await service.recalculateSteps(current: current, rejoin: rejoin),
      isNotEmpty,
    );
    expect(
      await service.recalculateSteps(current: current, rejoin: rejoin),
      isEmpty,
    );
    service.resetRecalculationCooldown();
    expect(
      await service.recalculateSteps(current: current, rejoin: rejoin),
      isNotEmpty,
    );
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
          segmentDistanceM: 400,
        ),
        NavStep(
          sequence: 2,
          maneuverType: 'turn',
          modifier: 'left',
          location: LatLng(45.005, -73),
          distanceFromStartM: 550,
          segmentDistanceM: 300,
        ),
      ],
    );

    expect(progress?.step.sequence, 1);
    expect(progress?.aheadM, inInclusiveRange(40, 70));
  });

  test('nextStepProgress skips short straight briefing steps', () {
    final progress = nextStepProgress(
      const LatLng(45.0005, -73),
      const [LatLng(45, -73), LatLng(45.01, -73)],
      const [
        NavStep(
          sequence: 1,
          maneuverType: 'continue',
          modifier: 'straight',
          location: LatLng(45.001, -73),
          distanceFromStartM: 110,
          segmentDistanceM: 400,
        ),
        NavStep(
          sequence: 2,
          maneuverType: 'turn',
          modifier: 'left',
          location: LatLng(45.005, -73),
          distanceFromStartM: 550,
          segmentDistanceM: 300,
        ),
      ],
    );

    expect(progress?.step.sequence, 2);
  });

  test('straight calls do not masquerade as a fork', () {
    const step = NavStep(
      sequence: 1,
      maneuverType: 'continue',
      modifier: 'straight',
      location: LatLng(45, -73),
      distanceFromStartM: 0,
      segmentDistanceM: 1200,
    );

    expect(step.call(AppLanguage.korean), '직진');
    expect(step.call(AppLanguage.english), 'straight');
    expect(step.call(AppLanguage.french), 'tout droit');
  });

  test(
    'finish follows the real route end instead of a stale Mapbox offset',
    () {
      const routeNodes = [LatLng(45, -73), LatLng(45.1, -73)];
      const steps = [
        NavStep(
          sequence: 1,
          maneuverType: 'arrive',
          modifier: null,
          location: LatLng(45.02, -73),
          distanceFromStartM: 2220,
          segmentDistanceM: 0,
        ),
      ];

      final midRoute = nextStepProgress(
        const LatLng(45.02, -73),
        routeNodes,
        steps,
      );
      final nearFinish = nextStepProgress(
        const LatLng(45.095, -73),
        routeNodes,
        steps,
      );

      expect(midRoute, isNull);
      expect(nearFinish?.step.maneuverType, 'arrive');
      expect(nearFinish?.aheadM, inInclusiveRange(500, 600));
    },
  );

  test('fetchSteps drops intermediate leg arrivals', () async {
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient(
        (_) async => http.Response(
          jsonEncode({
            'routes': [
              {
                'legs': [
                  {
                    'steps': [
                      {
                        'distance': 900.0,
                        'maneuver': {
                          'type': 'continue',
                          'modifier': 'straight',
                          'location': [-73.0, 45.0],
                        },
                      },
                      {
                        'distance': 0.0,
                        'maneuver': {
                          'type': 'arrive',
                          'location': [-73.0, 45.01],
                        },
                      },
                    ],
                  },
                  {
                    'steps': [
                      {
                        'distance': 1200.0,
                        'maneuver': {
                          'type': 'depart',
                          'modifier': 'straight',
                          'location': [-73.0, 45.01],
                        },
                      },
                      {
                        'distance': 0.0,
                        'maneuver': {
                          'type': 'arrive',
                          'location': [-73.0, 45.02],
                        },
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );

    final steps = await service.fetchSteps(const [
      LatLng(45, -73),
      LatLng(45.01, -73),
      LatLng(45.02, -73),
    ]);

    expect(steps.where((step) => step.maneuverType == 'arrive'), hasLength(1));
    expect(steps.where((step) => step.maneuverType == 'depart'), isEmpty);
    expect(steps.last.maneuverType, 'arrive');
  });

  test('fetchStepsForLegs keeps one continuous maneuver timeline', () async {
    var requestIndex = 0;
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient((_) async {
        final index = requestIndex++;
        return http.Response(
          jsonEncode({
            'routes': [
              {
                'legs': [
                  {
                    'steps': index == 0
                        ? [
                            {
                              'distance': 500.0,
                              'maneuver': {
                                'type': 'turn',
                                'modifier': 'right',
                                'location': [-73.0, 45.005],
                              },
                            },
                            {
                              'distance': 0.0,
                              'maneuver': {
                                'type': 'arrive',
                                'location': [-73.0, 45.01],
                              },
                            },
                          ]
                        : [
                            {
                              'distance': 600.0,
                              'maneuver': {
                                'type': 'depart',
                                'modifier': 'straight',
                                'location': [-73.0, 45.01],
                              },
                            },
                            {
                              'distance': 400.0,
                              'maneuver': {
                                'type': 'turn',
                                'modifier': 'left',
                                'location': [-73.0, 45.015],
                              },
                            },
                            {
                              'distance': 0.0,
                              'maneuver': {
                                'type': 'arrive',
                                'location': [-73.0, 45.02],
                              },
                            },
                          ],
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    final steps = await service.fetchStepsForLegs(const [
      [LatLng(45, -73), LatLng(45.01, -73)],
      [LatLng(45.01, -73), LatLng(45.02, -73)],
    ]);

    expect(requestIndex, 2);
    expect(steps.map((step) => step.maneuverType), ['turn', 'turn', 'arrive']);
    expect(steps.map((step) => step.sequence), [1, 2, 3]);
    expect(steps[1].distanceFromStartM, greaterThan(1600));
    expect(steps.last.distanceFromStartM, greaterThan(2000));
  });

  test(
    'fetchStepsForLegs projects maneuver offsets onto plan geometry',
    () async {
      final client = _FakeClient(
        (_) async => http.Response(_directionsFixture, 200),
      );
      final service = RouteTurnService(client: client, accessToken: 'token');
      const first = [LatLng(45, -73), LatLng(45.001, -73)];
      const second = [LatLng(45.001, -73), LatLng(45.002, -73)];

      final steps = await service.fetchStepsForLegs([first, second]);

      final firstLegM = RevvRoute.haversineKm(first.first, first.last) * 1000;
      expect(
        steps.where((step) => step.sequence > 2).first.distanceFromStartM,
        inInclusiveRange(firstLegM, firstLegM * 2 + 1),
      );
    },
  );

  test('fetchSteps caps retained maneuvers', () async {
    final rawSteps = List.generate(
      700,
      (index) => {
        'distance': 1.0,
        'maneuver': {
          'type': 'turn',
          'location': [-73.0, 45.0],
        },
      },
    );
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient(
        (_) async => http.Response(
          jsonEncode({
            'routes': [
              {
                'legs': [
                  {'steps': rawSteps},
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );

    final steps = await service.fetchSteps(const [
      LatLng(45, -73),
      LatLng(45.01, -73.01),
    ]);

    expect(steps, hasLength(500));
  });

  test('fetchSteps reserves the final arrival at the maneuver cap', () async {
    final rawSteps = [
      ...List.generate(
        700,
        (index) => {
          'distance': 1.0,
          'maneuver': {
            'type': 'turn',
            'modifier': index.isEven ? 'left' : 'right',
            'location': [-73.0, 45.0],
          },
        },
      ),
      {
        'distance': 0.0,
        'maneuver': {
          'type': 'arrive',
          'location': [-73.01, 45.01],
        },
      },
    ];
    final service = RouteTurnService(
      accessToken: 'token',
      client: _FakeClient(
        (_) async => http.Response(
          jsonEncode({
            'routes': [
              {
                'legs': [
                  {'steps': rawSteps},
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );

    final steps = await service.fetchSteps(const [
      LatLng(45, -73),
      LatLng(45.01, -73.01),
    ]);

    expect(steps, hasLength(500));
    expect(steps.last.maneuverType, 'arrive');
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
