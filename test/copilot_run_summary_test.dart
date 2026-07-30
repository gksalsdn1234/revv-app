import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/ui/copilot_run_summary.dart';

RunSession sessionWith(List<SharpCorner> corners, {double distanceKm = 10}) {
  final route = RevvRoute(
    id: 'route-1',
    name: 'Rang Saint-Simon',
    nodes: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    distanceKm: 12,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: const LatLng(45.05, -73.05),
    distanceFromUser: 2,
  );
  return RunSession(
    startTime: DateTime.parse('2026-05-01T10:00:00Z'),
    endTime: DateTime.parse('2026-05-01T10:20:00Z'),
    maxSpeedKmh: 72,
    avgSpeedKmh: 42,
    distanceKm: distanceKm,
    gpsPath: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    route: route,
    weatherEmoji: '',
    tempDisplay: '',
    weatherDesc: '',
    maxLateralG: 0.5,
    maxLonG: 0.2,
    sharpCorners: corners,
  );
}

SharpCorner corner(String iso, double g) => SharpCorner(
  position: const LatLng(45.02, -73.02),
  lateralG: g,
  time: DateTime.parse(iso),
);

void main() {
  test('summary copy uses route rhythm and corner events', () {
    final route = RevvRoute(
      id: 'route-1',
      name: 'Rang Saint-Simon',
      nodes: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
      distanceKm: 12,
      windingScore: 6,
      starRating: 4,
      sharpCurveCount: 8,
      centerPoint: const LatLng(45.05, -73.05),
      distanceFromUser: 2,
    );
    final session = RunSession(
      startTime: DateTime.parse('2026-05-01T10:00:00Z'),
      endTime: DateTime.parse('2026-05-01T10:18:00Z'),
      maxSpeedKmh: 72,
      avgSpeedKmh: 42,
      distanceKm: 10.2,
      gpsPath: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
      route: route,
      weatherEmoji: '',
      tempDisplay: '',
      weatherDesc: '',
      maxLateralG: 0.52,
      maxLonG: 0.21,
      sharpCorners: [
        SharpCorner(
          position: const LatLng(45.02, -73.02),
          lateralG: 0.52,
          time: DateTime.parse('2026-05-01T10:05:00Z'),
        ),
      ],
    );

    final copy = CopilotRunSummaryCopy.fromSession(session);

    // The coach note says something about the road rather than restating the
    // numbers already on screen, and the next step is a real, labelled action.
    expect(copy.coachNote, isNotEmpty);
    expect(copy.nextActionLabel, isNotEmpty);
    expect(copy.nextAction, CopilotNextAction.findRoute);
    expect(copy.nextRouteId, isNull);
    // The subtitle describes character only. Route name, distance, duration and
    // corner count all already appear elsewhere on the screen, so repeating any
    // of them here is the duplication this line used to cause.
    expect(copy.summaryLine, isNotEmpty);
    expect(copy.summaryLine, isNot(contains('Rang Saint-Simon')));
    expect(copy.summaryLine, isNot(contains('km')));
    expect(copy.summaryLine, isNot(contains('복원')));
    expect(copy.summaryLine, isNot(matches(RegExp(r'\d'))));
    expect(copy.notableStats.map((stat) => stat.label), contains('커브 이벤트'));
    expect(copy.nextSuggestion, contains('추천'));
  });

  test('coach note varies with corner character on the same route', () {
    // Three committed corners → committed coach note.
    final committed = CopilotRunSummaryCopy.fromSession(
      sessionWith([
        corner('2026-05-01T10:03:00Z', 0.52),
        corner('2026-05-01T10:05:00Z', 0.48),
        corner('2026-05-01T10:07:00Z', 0.51),
      ]),
    ).coachNote;

    // A single gentle corner → calm coach note.
    final calm = CopilotRunSummaryCopy.fromSession(
      sessionWith([corner('2026-05-01T10:05:00Z', 0.12)]),
    ).coachNote;

    // Only a third of the route driven → partial coach note.
    final partial = CopilotRunSummaryCopy.fromSession(
      sessionWith([
        corner('2026-05-01T10:05:00Z', 0.5),
      ], distanceKm: 3),
    ).coachNote;

    expect(committed, isNot(equals(calm)));
    expect(partial, isNot(equals(committed)));
    expect(partial, isNot(equals(calm)));
  });

  test('an unfinished route offers to reopen that same route', () {
    final partial = CopilotRunSummaryCopy.fromSession(
      sessionWith([corner('2026-05-01T10:05:00Z', 0.5)], distanceKm: 3),
    );
    final finished = CopilotRunSummaryCopy.fromSession(
      sessionWith([corner('2026-05-01T10:05:00Z', 0.5)], distanceKm: 11),
    );

    expect(partial.nextAction, CopilotNextAction.retryRoute);
    expect(partial.nextRouteId, 'route-1');
    expect(finished.nextAction, CopilotNextAction.findRoute);
    expect(finished.nextRouteId, isNull);
  });
}
