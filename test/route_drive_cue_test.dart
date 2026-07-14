import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_drive_cue.dart';

const _routeNodes = [
  LatLng(45.0000, -73.0000),
  LatLng(45.0010, -73.0000),
  LatLng(45.0010, -72.9985),
  LatLng(45.0024, -72.9985),
  LatLng(45.0024, -72.9970),
];

void main() {
  test('far before route start asks driver to reach the start point', () {
    final state = readDriveRouteState(
      const LatLng(44.9950, -73.0000),
      _routeNodes,
    );

    expect(state.status, DriveRouteStatus.approachingStart);
    expect(state.progress, 0);
    expect(state.cue?.label, '시작점까지 이동');
    expect(state.cue?.headline, startsWith('시작점'));
    expect(state.rhythmBrief.rhythmLabel, '시작 대기');
  });

  test('on-route state exposes the next meaningful curve within 30-800m', () {
    final state = readDriveRouteState(
      const LatLng(45.00035, -73.0000),
      _routeNodes,
    );

    expect(state.status, DriveRouteStatus.onRoute);
    expect(state.cue, isNotNull);
    expect(state.cue!.distanceM, inInclusiveRange(30, 800));
    expect(state.cue!.headline, matches(RegExp(r'^\d+m (좌측|우측) ')));
    expect(state.cue!.rhythmLine, isNotEmpty);
    expect(state.rhythmBrief.rhythmLabel, anyOf('연속 코너', '짧은 전환', '단일 커브'));
  });

  test(
    'off-route state is explicit after the driver leaves the route line',
    () {
      final state = readDriveRouteState(
        const LatLng(45.0064, -72.9977),
        _routeNodes,
      );

      expect(state.status, DriveRouteStatus.offRoute);
      expect(state.cue?.label, '루트에서 벗어남');
      expect(state.rhythmBrief.rhythmLabel, '루트 복귀');
      expect(state.distanceFromRouteM, greaterThan(300));
    },
  );

  test('near route end is treated as completed', () {
    final state = readDriveRouteState(
      const LatLng(45.0024, -72.99705),
      _routeNodes,
    );

    expect(state.status, DriveRouteStatus.completed);
    expect(state.remainingKm, lessThan(0.05));
    expect(state.cue?.label, '루트 마무리');
    expect(state.rhythmBrief.rhythmLabel, '루트 완료');
  });

  test('on-route state without nearby curves exposes flow rhythm fallback', () {
    const straightNodes = [
      LatLng(45.0000, -73.0000),
      LatLng(45.0020, -73.0000),
      LatLng(45.0040, -73.0000),
      LatLng(45.0060, -73.0000),
    ];

    final state = readDriveRouteState(
      const LatLng(45.0022, -73.0000),
      straightNodes,
    );

    expect(state.status, DriveRouteStatus.onRoute);
    expect(state.cue, isNull);
    expect(state.rhythmBrief.rhythmLabel, '흐름 구간');
    expect(state.rhythmBrief.advice, '직선 구간');
  });

  test('drive cue supports English and French copy', () {
    final english = readDriveRouteState(
      const LatLng(45.00035, -73.0000),
      _routeNodes,
      language: AppLanguage.english,
    );
    final french = readDriveRouteState(
      const LatLng(45.00035, -73.0000),
      _routeNodes,
      language: AppLanguage.french,
    );

    expect(english.cue?.headline, anyOf(contains('Right'), contains('Left')));
    expect(french.cue?.headline, anyOf(contains('Droite'), contains('Gauche')));
  });

  test('turn-by-turn plan exposes ordered route instructions', () {
    final plan = buildTurnByTurnPlan(_routeNodes);

    expect(plan, hasLength(4));
    expect(plan.first.sequence, 1);
    expect(plan.first.distanceFromStartM, inInclusiveRange(100, 140));
    expect(plan.first.headline, '110m 우측 급회전');
    expect(plan.first.command, contains('우측'));
    expect(plan.last.finish, isTrue);
  });

  test('next turn-by-turn instruction follows current route progress', () {
    final state = readTurnByTurnState(
      const LatLng(45.00020, -73.0000),
      _routeNodes,
    );

    expect(state.instruction, isNotNull);
    expect(state.instruction!.sequence, 1);
    expect(state.instruction!.aheadM, inInclusiveRange(80, 100));
    expect(state.instruction!.command, contains('우측'));
    expect(state.instruction!.command, contains('준비'));
    expect(state.completedInstructions, 0);
    expect(state.totalInstructions, 4);
  });

  test('progress bounds keep crossing-route state on the current branch', () {
    const crossing = [
      LatLng(45.0000, -73.0020),
      LatLng(45.0000, -72.9980),
      LatLng(45.0020, -73.0000),
      LatLng(44.9980, -73.0000),
      LatLng(45.0000, -73.0020),
    ];

    final state = readDriveRouteState(
      const LatLng(45.0000, -73.0000),
      crossing,
      minProgress: 0,
      maxProgress: 0.3,
    );
    final turns = readTurnByTurnState(
      const LatLng(45.0000, -73.0000),
      crossing,
      routeProgress: state.progress,
    );

    expect(state.progress, lessThanOrEqualTo(0.3));
    expect(state.remainingKm, greaterThan(0));
    expect(state.status, isNot(DriveRouteStatus.completed));
    expect(turns.completedInstructions, lessThan(turns.totalInstructions));
  });
}
