import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_turn_service.dart';
import 'package:revv_app/ui/route_drive_cue.dart';

const _origin = LatLng(45, -73);

LatLng _pointM(double x, double y) {
  final lat = _origin.lat + y / 110540;
  final lng = _origin.lng + x / (111320 * math.cos(_origin.lat * math.pi / 180));
  return LatLng(lat, lng);
}

List<LatLng> _arcNodes({double radiusM = 60, double sampleArcM = 10}) {
  return _arcAround(
    centerX: 0,
    centerY: 0,
    radiusM: radiusM,
    start: 0,
    end: math.pi / 2,
    sampleArcM: sampleArcM,
  );
}

List<LatLng> _arcAround({
  required double centerX,
  required double centerY,
  required double radiusM,
  required double start,
  required double end,
  required double sampleArcM,
}) {
  final count = math.max(1, (radiusM * (end - start).abs() / sampleArcM).ceil());
  return List<LatLng>.generate(count + 1, (index) {
    final angle = start + (end - start) * index / count;
    return _pointM(
      centerX + radiusM * math.cos(angle),
      centerY + radiusM * math.sin(angle),
    );
  });
}

List<LatLng> _denseCurveRoute() {
  final lead = List<LatLng>.generate(11, (index) => _pointM(60, -100 + index * 10));
  return [...lead, ..._arcNodes().skip(1)];
}

List<LatLng> _twoDifferentCorners() {
  final lead = List<LatLng>.generate(11, (index) => _pointM(60, -100 + index * 10));
  final first = _arcNodes().skip(1);
  final bridge = List<LatLng>.generate(5, (index) => _pointM(-10 - index * 10, 60));
  final sharp = _arcAround(
    centerX: -50,
    centerY: 40,
    radiusM: 20,
    start: math.pi / 2,
    end: math.pi * 3 / 2,
    sampleArcM: 5,
  ).skip(1);
  return [...lead, ...first, ...bridge, ...sharp];
}

const _sparseTurnBookFixture = [
  LatLng(45.0000, -73.0000),
  LatLng(45.0010, -73.0000),
  LatLng(45.0010, -72.9985),
  LatLng(45.0024, -72.9985),
  LatLng(45.0024, -72.9970),
];

List<LatLng> _denseTurnBookRoute() {
  final nodes = <LatLng>[];
  void appendLine(double fromX, double fromY, double toX, double toY) {
    final lengthM = math.sqrt(
      math.pow(toX - fromX, 2) + math.pow(toY - fromY, 2),
    );
    final steps = math.max(1, (lengthM / 22).ceil());
    for (var step = nodes.isEmpty ? 0 : 1; step <= steps; step++) {
      final progress = step / steps;
      nodes.add(_pointM(
        fromX + (toX - fromX) * progress,
        fromY + (toY - fromY) * progress,
      ));
    }
  }
  void appendArc({
    required double centerX,
    required double centerY,
    required double start,
    required double end,
  }) {
    nodes.addAll(_arcAround(
      centerX: centerX,
      centerY: centerY,
      radiusM: 20,
      start: start,
      end: end,
      sampleArcM: 10,
    ).skip(nodes.isEmpty ? 0 : 1));
  }

  appendLine(0, 0, 0, 110);
  appendArc(centerX: 20, centerY: 110, start: math.pi, end: math.pi / 2);
  appendLine(20, 130, 130, 130);
  appendArc(centerX: 130, centerY: 150, start: -math.pi / 2, end: 0);
  appendLine(150, 150, 150, 260);
  appendArc(centerX: 170, centerY: 260, start: math.pi, end: math.pi / 2);
  appendLine(170, 280, 280, 280);
  return nodes;
}

double _lengthM(List<LatLng> nodes) {
  var total = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    total += RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
  }
  return total;
}

void main() {
  test('normalizePolyline removes duplicate, zero-length, and non-finite points', () {
    final normalized = normalizePolyline([
      const LatLng(45, -73),
      const LatLng(45, -73),
      LatLng(double.nan, -73),
      LatLng(45, double.infinity),
      const LatLng(45.0001, -73),
    ]);

    expect(normalized, hasLength(2));
    expect(normalized.first.lat, 45);
    expect(normalized.last.lat, 45.0001);
  });

  test('resampleByArcLength preserves endpoints, length, and effective step', () {
    final nodes = [const LatLng(45, -73), _pointM(0, 1030)];
    final sampled = resampleByArcLength(nodes);

    expect(sampled.points.first.lat, nodes.first.lat);
    expect(sampled.points.first.lng, nodes.first.lng);
    expect(sampled.points.last.lat, nodes.last.lat);
    expect(sampled.points.last.lng, nodes.last.lng);
    expect(sampled.effectiveStepM, closeTo(10, 1));
    expect(_lengthM(sampled.points), closeTo(_lengthM(nodes), _lengthM(nodes) * 0.01));
  });

  test('resampleByArcLength raises effective step at the 4000 point cap', () {
    final sampled = resampleByArcLength([
      const LatLng(45, -73),
      _pointM(0, 100000),
    ]);

    expect(sampled.points.length, lessThanOrEqualTo(4000));
    expect(sampled.effectiveStepM, greaterThan(10));
  });

  test('fine 5m, 10m, and 15m inputs produce the same radius grade', () {
    final grades = [5.0, 10.0, 15.0].map((spacing) {
      final geometry = compileRouteCueGeometry(_arcNodes(sampleArcM: spacing));
      return geometry.grade.where((grade) => grade > 0).toSet();
    }).toList();

    expect(grades, everyElement(equals({3})));
  });

  test('a sparse source arc is unknown and emits no corner event', () {
    final geometry = compileRouteCueGeometry(_arcNodes(sampleArcM: 200));

    expect(geometry.conf, everyElement(CurveConfidence.unknown));
    expect(geometry.grade, everyElement(0));
    expect(geometry.corners, isEmpty);
  });

  test('curve radius keeps k at two when the effective step is 25m', () {
    final poly = ResampledPolyline(
      points: [_pointM(0, 0), _pointM(25, 0), _pointM(25, 25), _pointM(50, 25)],
      effectiveStepM: 25,
      sourceSegmentM: const [25, 25, 25, 25],
    );

    expect(curveRadiusM(poly, 1), double.infinity);
  });

  test('confidence gate uses only the circumcircle source points', () {
    final poly = ResampledPolyline(
      points: List<LatLng>.generate(7, (index) => _pointM(index * 10, 0)),
      effectiveStepM: 10,
      sourceSegmentM: const [20, 20, 120, 20, 20, 20, 20],
    );

    expect(curveConfidenceAt(poly, 3), CurveConfidence.reliable);
  });

  test('rally grade boundaries follow the agreed radius table', () {
    expect(rallyGradeFromRadius(24.999), 1);
    expect(rallyGradeFromRadius(25), 2);
    expect(rallyGradeFromRadius(44.999), 2);
    expect(rallyGradeFromRadius(45), 3);
    expect(rallyGradeFromRadius(79.999), 3);
    expect(rallyGradeFromRadius(80), 4);
    expect(rallyGradeFromRadius(139.999), 4);
    expect(rallyGradeFromRadius(140), 5);
    expect(rallyGradeFromRadius(249.999), 5);
    expect(rallyGradeFromRadius(250), 6);
    expect(rallyGradeFromRadius(399.999), 6);
    expect(rallyGradeFromRadius(400), 0);
  });

  test('five-point median keeps one or two radius spikes from becoming calls', () {
    final filtered = medianRadius5([
      double.infinity,
      double.infinity,
      40,
      double.infinity,
      40,
      double.infinity,
      double.infinity,
    ]);

    expect(filtered[2], double.infinity);
    expect(filtered[4], double.infinity);
    expect(rallyGradeFromRadius(filtered[2]), 0);
    expect(rallyGradeFromRadius(filtered[4]), 0);
  });

  test('merge keeps same-direction nearby samples together and chicanes apart', () {
    CornerEvent corner(int index, double atM, int sign, int grade) => CornerEvent(
      entryIndex: index,
      distanceFromStartM: atM,
      radiusM: 60,
      grade: grade,
      turnSign: sign,
    );
    final sameDirection = mergeCornerEvents([
      corner(1, 100, 1, 4),
      corner(2, 120, 1, 3),
      corner(3, 140, 1, 2),
    ]);
    final chicane = mergeCornerEvents([
      corner(1, 100, -1, 3),
      corner(2, 120, 1, 3),
      corner(3, 140, -1, 3),
    ]);

    expect(sameDirection, hasLength(1));
    expect(sameDirection.single.distanceFromStartM, 100);
    expect(sameDirection.single.grade, 2);
    expect(chicane, hasLength(3));
  });

  test('short sign jitter is ignored before corner merging', () {
    final stabilized = stabilizeCornerSigns(
      const [1, -1, 1],
      const [3, 3, 3],
      const [0, 10, 20],
      10,
    );

    expect(stabilized, const [1, 1, 1]);
  });

  test('reliable geometry produces a grade-derived cue and turn book', () {
    final route = _denseCurveRoute();
    final state = readDriveRouteState(_pointM(60, -100), route);
    final plan = buildTurnByTurnPlan(route);

    expect(state.status, DriveRouteStatus.onRoute);
    expect(state.cue, isNotNull);
    expect(state.cue!.grade, 3);
    expect(state.cue!.severity, 2);
    expect(state.cue!.intensityLabel, '타이트');
    expect(plan, hasLength(2));
    expect(plan.first.grade, 3);
    expect(plan.last.finish, isTrue);
  });

  test('voice geometry selects the most dangerous eligible cluster, not UI first', () {
    final route = _twoDifferentCorners();
    final position = _pointM(60, -100);
    final uiCue = readDriveRouteState(position, route).cue;
    final voiceCue = readVoiceCurveCue(
      position,
      route,
      trustedSpeedMps: null,
    );

    expect(uiCue?.grade, 3);
    expect(voiceCue?.grade, 1);
  });

  test('sparse geometry remains silent in the route state and turn book', () {
    final sparse = [
      _pointM(60, -100),
      _pointM(60, 0),
      ..._arcNodes(sampleArcM: 200).skip(1),
    ];
    final state = readDriveRouteState(_pointM(60, -100), sparse);

    expect(state.cue, isNull);
    expect(buildTurnByTurnPlan(sparse), hasLength(1));
  });

  test('sparse turn-book fixture keeps only the ungated finish cue', () {
    final plan = buildTurnByTurnPlan(_sparseTurnBookFixture);

    expect(plan, hasLength(1));
    expect(plan.single.finish, isTrue);
  });

  test('drive cue supports English and French copy', () {
    final route = _denseCurveRoute();
    final english = readDriveRouteState(
      _pointM(60, -100),
      route,
      language: AppLanguage.english,
    );
    final french = readDriveRouteState(
      _pointM(60, -100),
      route,
      language: AppLanguage.french,
    );

    expect(english.cue?.headline, contains('Left'));
    expect(french.cue?.headline, contains('Gauche'));
  });

  test('route geometry compiles once for position-only changes and recompiles for nodes', () {
    final route = _denseCurveRoute();
    debugResetRouteCueCache();
    for (var index = 0; index < 20; index++) {
      readDriveRouteState(
        _pointM(60, -100 + index.toDouble()),
        route,
        routeId: 'a',
      );
      readTurnByTurnState(
        _pointM(60, -100 + index.toDouble()),
        route,
        routeId: 'a',
      );
      nextStepProgressWithRouteCueGeometry(
        _pointM(60, -100 + index.toDouble()),
        route,
        const <NavStep>[],
        routeId: 'a',
      );
    }
    expect(debugRouteCueCompileCount, 1);

    readDriveRouteState(_pointM(60, -100), [...route, _pointM(-1, 61)], routeId: 'a');
    expect(debugRouteCueCompileCount, 2);
  });

  test('reports the 4000-point route geometry compile time', () {
    final nodes = List<LatLng>.generate(
      4000,
      (index) => _pointM(0, index * 25.0),
    );
    final stopwatch = Stopwatch()..start();
    final geometry = compileRouteCueGeometry(nodes);
    stopwatch.stop();

    // Kept in test output for the release report; no timing threshold is
    // imposed in this wave because async compilation is explicitly deferred.
    // ignore: avoid_print
    print('compileRouteCueGeometry_4000ms=${stopwatch.elapsedMicroseconds / 1000}');
    expect(geometry.poly.points.length, lessThanOrEqualTo(4000));
  });

  test('reports grade distribution for a dense turn-book fixture', () {
    final fixture = _denseTurnBookRoute();
    final segments = [
      for (var index = 1; index < fixture.length; index++)
        RevvRoute.haversineKm(fixture[index - 1], fixture[index]) * 1000,
    ]..sort();
    expect(
      segments[segments.length ~/ 2],
      inInclusiveRange(20, 25),
    );

    final geometry = compileRouteCueGeometry(fixture);
    final total = geometry.grade.length;
    final gradeCounts = [
      for (var grade = 1; grade <= 6; grade++)
        geometry.grade.where((value) => value == grade).length,
    ];
    final unknown = geometry.conf
        .where((value) => value == CurveConfidence.unknown)
        .length;

    // ignore: avoid_print
    print(
      'dense_fixture_grade_distribution='
      'g1:${gradeCounts[0]},g2:${gradeCounts[1]},g3:${gradeCounts[2]},'
      'g4:${gradeCounts[3]},g5:${gradeCounts[4]},g6:${gradeCounts[5]},'
      'unknown:$unknown,total:$total',
    );
    expect(gradeCounts.reduce((sum, count) => sum + count), greaterThan(0));
    expect(unknown, lessThan(total));
  });
}
