import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_turn_service.dart';
import 'package:revv_app/services/voice_briefing_service.dart';
import 'package:revv_app/ui/route_drive_cue.dart';

/// 2026-07-22 실주행 리그레션: 와인딩 구간에서 코파일럿이 거의 말을 안 했다.
/// 원인 3개 (노드 밀도 종속 코너 감지 / 먼 분기 하이재킹 / 구간당 1회 재무장)
/// 을 각각 붙잡아 두는 테스트.
const originLat = 45.5017;
const originLng = -73.5673;

LatLng _fromMeters(double x, double y) {
  final latRad = originLat * math.pi / 180;
  return LatLng(
    originLat + y / 110540,
    originLng + x / (111320 * math.cos(latRad)),
  );
}

/// 곡선·직선을 이어 붙여 산길 비슷한 폴리라인을 만든다.
/// [spacingM] = 노드 간격 (맵매칭 10m ~ OSM 희소 50m 시뮬레이션).
List<LatLng> buildWindingRoute({required double spacingM}) {
  final points = <LatLng>[_fromMeters(0, 0)];
  var x = 0.0;
  var y = 0.0;
  var heading = 0.0;

  void run(double lengthM, double curvatureDegPerM) {
    var travelled = 0.0;
    while (travelled < lengthM) {
      final step = math.min(spacingM, lengthM - travelled);
      heading += curvatureDegPerM * step * math.pi / 180;
      x += math.sin(heading) * step;
      y += math.cos(heading) * step;
      points.add(_fromMeters(x, y));
      travelled += step;
    }
  }

  run(400, 0);
  run(120, 0.75); // 우 스위퍼 R≈76m
  run(80, 0);
  run(100, -0.9); // 좌 타이트
  run(60, 0);
  run(90, 1.0); // 우 타이트
  run(200, 0);
  run(70, -1.7); // 좌 헤어핀
  run(150, 0);
  run(300, 0.3); // 완만한 우 R≈191m
  run(400, 0);
  run(110, -0.8);
  run(90, 0.85);
  run(80, -0.9);
  run(700, 0);
  return points;
}

double _routeLengthM(List<LatLng> nodes) {
  var total = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    total += RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
  }
  return total;
}

/// 루트를 따라 [speedKmh]로 1초마다 샘플링한 위치.
List<LatLng> _simulateDrive(List<LatLng> nodes, double speedKmh) {
  final stepM = speedKmh / 3.6;
  final samples = <LatLng>[nodes.first];
  var carry = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    final segM = RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
    if (segM <= 0) continue;
    var t = carry;
    while (t < segM) {
      final f = t / segM;
      samples.add(
        LatLng(
          nodes[i - 1].lat + (nodes[i].lat - nodes[i - 1].lat) * f,
          nodes[i - 1].lng + (nodes[i].lng - nodes[i - 1].lng) * f,
        ),
      );
      t += stepM;
    }
    carry = t - segM;
  }
  return samples;
}

List<String> _driveAndCollect({
  required List<LatLng> nodes,
  required double speedKmh,
  List<NavStep> navSteps = const [],
}) {
  final spoken = <String>[];
  var clock = DateTime(2026, 7, 22, 10);
  final voice = VoiceBriefingService(
    speak: (text, _) async => spoken.add(text),
    clock: () => clock,
  );
  for (final position in _simulateDrive(nodes, speedKmh)) {
    final state = readDriveRouteState(
      position,
      nodes,
      language: AppLanguage.korean,
    );
    final progress = nextStepProgress(position, nodes, navSteps);
    voice.onCoPilotCue(
      navStep: progress?.step,
      navDistanceM: progress?.aheadM,
      curveCue: state.cue,
      speedKmh: speedKmh,
      language: AppLanguage.korean,
      muted: false,
    );
    clock = clock.add(const Duration(seconds: 1));
  }
  return spoken;
}

void main() {
  test('corner detection does not depend on polyline node density', () {
    final byDensity = {
      for (final spacing in [10.0, 25.0, 50.0])
        spacing: detectRouteCorners(buildWindingRoute(spacingM: spacing)),
    };

    for (final entry in byDensity.entries) {
      expect(
        entry.value.where((corner) => corner.severity >= 1).length,
        greaterThanOrEqualTo(7),
        reason: '노드 간격 ${entry.key}m에서 코너가 사라짐',
      );
    }
    // 헤어핀 하나는 어느 밀도에서도 헤어핀으로 읽혀야 한다.
    for (final corners in byDensity.values) {
      expect(corners.where((corner) => corner.severity == 3), hasLength(1));
    }
  });

  test('long sweepers are not called hairpins', () {
    // 300m에 걸친 90도 = 반경 191m — 성격은 완만이다.
    final corners = detectRouteCorners(buildWindingRoute(spacingM: 10));
    final sweeper = corners.firstWhere(
      (corner) => corner.arcM > 250,
      orElse: () => throw StateError('스위퍼를 찾지 못함'),
    );
    expect(sweeper.turnDeg.abs(), greaterThan(60));
    expect(sweeper.severity, 0);
  });

  test('a winding route gets pacenotes at every node density', () {
    for (final spacing in [10.0, 25.0, 50.0]) {
      final spoken = _driveAndCollect(
        nodes: buildWindingRoute(spacingM: spacing),
        speedKmh: 60,
      );
      expect(
        spoken.length,
        greaterThanOrEqualTo(6),
        reason: '노드 간격 ${spacing}m: 3km 와인딩에서 발화 ${spoken.length}회',
      );
      expect(spoken.any((phrase) => phrase.contains('헤어핀')), isTrue);
    }
  });

  test('a far-away nav step does not swallow the corner pacenotes', () {
    final nodes = buildWindingRoute(spacingM: 10);
    final withoutNav = _driveAndCollect(nodes: nodes, speedKmh: 60);
    final withFarNav = _driveAndCollect(
      nodes: nodes,
      speedKmh: 60,
      navSteps: [
        NavStep(
          sequence: 1,
          maneuverType: 'arrive',
          modifier: null,
          location: nodes.last,
          distanceFromStartM: _routeLengthM(nodes),
        ),
      ],
    );

    final corners = withFarNav.where((phrase) => !phrase.contains('피니시'));
    expect(corners, hasLength(withoutNav.length));
  });

  test('pacenotes keep the safety gap between callouts', () {
    var clock = DateTime(2026, 7, 22, 10);
    final gaps = <Duration>[];
    DateTime? last;
    final voice = VoiceBriefingService(
      speak: (_, _) async {
        if (last != null) gaps.add(clock.difference(last!));
        last = clock;
      },
      clock: () => clock,
    );
    final nodes = buildWindingRoute(spacingM: 10);
    for (final position in _simulateDrive(nodes, 60)) {
      final state = readDriveRouteState(
        position,
        nodes,
        language: AppLanguage.korean,
      );
      voice.onCoPilotCue(
        curveCue: state.cue,
        speedKmh: 60,
        language: AppLanguage.korean,
        muted: false,
      );
      clock = clock.add(const Duration(seconds: 1));
    }

    expect(gaps, isNotEmpty);
    for (final gap in gaps) {
      expect(gap, greaterThanOrEqualTo(VoiceBriefingService.minGap));
    }
  });
}
