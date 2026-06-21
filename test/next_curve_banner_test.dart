import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/ui/route_drive_cue.dart';
import 'package:revv_app/widgets/next_curve_banner.dart';

void main() {
  testWidgets('next curve banner renders ETA phase and corner type metadata', (
    tester,
  ) async {
    const cue = DriveCurveCue(
      label: '우측 헤어핀',
      detail: '이후 80m 연속 코너',
      directionLabel: '우측',
      intensityLabel: '헤어핀',
      headline: '9초 뒤 · 240m 우측 헤어핀',
      rhythmLine: '이후 80m 연속 코너',
      icon: Icons.turn_slight_right_rounded,
      distanceM: 240,
      nextGapM: 80,
      curveCountAhead: 2,
      horizonM: 320,
      severity: 3,
      etaText: '9초',
      phaseLabel: '준비',
      cornerTypeLabel: '헤어핀',
      sequenceLine: '이후 80m 연속 코너',
    );
    const rhythm = DriveRhythmBrief(
      rhythmLabel: '연속 코너',
      advice: '이후 80m 연속 코너',
      horizonText: '240m',
      severity: 3,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 390,
              child: NextCurveBanner(
                cue: cue,
                rhythmBrief: rhythm,
                status: DriveRouteStatus.onRoute,
                eventMessage: null,
                language: AppLanguage.korean,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('9초 뒤 · 240m 우측 헤어핀'), findsOneWidget);
    expect(find.text('준비'), findsOneWidget);
    expect(find.text('9초'), findsOneWidget);
    expect(find.text('헤어핀'), findsOneWidget);
  });
}
