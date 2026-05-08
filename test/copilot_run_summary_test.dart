import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/ui/copilot_run_summary.dart';

void main() {
  test('summary copy uses route, sharp events, and G peak without OBD', () {
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

    expect(copy.headline, contains('루트'));
    expect(copy.summaryLine, contains('Rang Saint-Simon'));
    expect(copy.summaryLine, contains('G 이벤트 1회'));
    expect(copy.notableStats.map((stat) => stat.label), contains('커브 이벤트'));
    expect(copy.nextSuggestion, contains('추천'));
  });
}
