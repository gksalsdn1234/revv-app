import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/revv_route.dart';

enum DriveRouteStatus { approachingStart, onRoute, offRoute, completed }

class DriveCurveCue {
  final String label;
  final String detail;
  final IconData icon;
  final double distanceM;
  final double? nextGapM;
  final int severity;

  const DriveCurveCue({
    required this.label,
    required this.detail,
    required this.icon,
    required this.distanceM,
    required this.nextGapM,
    required this.severity,
  });
}

class DriveRhythmBrief {
  final String rhythmLabel;
  final String advice;
  final String horizonText;
  final int severity;

  const DriveRhythmBrief({
    required this.rhythmLabel,
    required this.advice,
    required this.horizonText,
    required this.severity,
  });
}

class DriveRouteState {
  final double progress;
  final double remainingKm;
  final DriveCurveCue? cue;
  final DriveRhythmBrief rhythmBrief;
  final DriveRouteStatus status;
  final double distanceFromRouteM;
  final double distanceToStartM;

  const DriveRouteState({
    required this.progress,
    required this.remainingKm,
    required this.cue,
    required this.rhythmBrief,
    required this.status,
    required this.distanceFromRouteM,
    required this.distanceToStartM,
  });
}

DriveRouteState readDriveRouteState(LatLng position, List<LatLng> nodes) {
  if (nodes.length < 3) {
    return const DriveRouteState(
      progress: 0,
      remainingKm: 0,
      cue: null,
      rhythmBrief: DriveRhythmBrief(
        rhythmLabel: '경로 대기',
        advice: '루트 데이터가 부족해 지도 라인을 먼저 확인해야 해요.',
        horizonText: 'WAIT',
        severity: 0,
      ),
      status: DriveRouteStatus.approachingStart,
      distanceFromRouteM: double.infinity,
      distanceToStartM: double.infinity,
    );
  }

  final cumulativeM = _cumulativeMeters(nodes);
  final totalM = cumulativeM.last;
  if (totalM <= 0) {
    return const DriveRouteState(
      progress: 0,
      remainingKm: 0,
      cue: null,
      rhythmBrief: DriveRhythmBrief(
        rhythmLabel: '경로 대기',
        advice: '루트 길이를 계산하지 못했어요. 지도 라인을 먼저 확인하세요.',
        horizonText: 'WAIT',
        severity: 0,
      ),
      status: DriveRouteStatus.approachingStart,
      distanceFromRouteM: double.infinity,
      distanceToStartM: double.infinity,
    );
  }

  final nearest = _nearestRouteProjection(position, nodes, cumulativeM);
  final distanceToStartM = RevvRoute.haversineKm(position, nodes.first) * 1000;
  final remainingM = math.max(0.0, totalM - nearest.alongM);
  final progress = (nearest.alongM / totalM).clamp(0.0, 1.0).toDouble();
  final status = _routeStatus(
    distanceFromRouteM: nearest.distanceM,
    distanceToStartM: distanceToStartM,
    alongM: nearest.alongM,
    remainingM: remainingM,
  );

  if (status == DriveRouteStatus.approachingStart) {
    return DriveRouteState(
      progress: 0,
      remainingKm: totalM / 1000,
      status: status,
      distanceFromRouteM: nearest.distanceM,
      distanceToStartM: distanceToStartM,
      cue: DriveCurveCue(
        label: '시작점까지 이동',
        detail: '루트 시작점 근처에서 커브 리듬 안내를 시작합니다.',
        icon: Icons.flag_rounded,
        distanceM: distanceToStartM,
        nextGapM: null,
        severity: 0,
      ),
      rhythmBrief: _rhythmForApproachingStart(distanceToStartM),
    );
  }

  if (status == DriveRouteStatus.offRoute) {
    return DriveRouteState(
      progress: progress,
      remainingKm: remainingM / 1000,
      status: status,
      distanceFromRouteM: nearest.distanceM,
      distanceToStartM: distanceToStartM,
      cue: DriveCurveCue(
        label: '루트에서 벗어남',
        detail: '지도 라인 가까이 복귀하면 리듬 안내를 이어갑니다.',
        icon: Icons.near_me_disabled_rounded,
        distanceM: nearest.distanceM,
        nextGapM: null,
        severity: 2,
      ),
      rhythmBrief: _rhythmForOffRoute(nearest.distanceM),
    );
  }

  if (status == DriveRouteStatus.completed) {
    return DriveRouteState(
      progress: 1,
      remainingKm: 0,
      status: status,
      distanceFromRouteM: nearest.distanceM,
      distanceToStartM: distanceToStartM,
      cue: const DriveCurveCue(
        label: '루트 마무리',
        detail: '주행을 종료하고 기록을 저장할 수 있어요.',
        icon: Icons.done_rounded,
        distanceM: 0,
        nextGapM: null,
        severity: 0,
      ),
      rhythmBrief: const DriveRhythmBrief(
        rhythmLabel: '루트 완료',
        advice: '주행을 종료하고 오늘의 리듬을 저장하세요.',
        horizonText: 'DONE',
        severity: 0,
      ),
    );
  }

  final cue = _nextCurveCue(nodes, cumulativeM, nearest.alongM);
  return DriveRouteState(
    progress: progress,
    remainingKm: remainingM / 1000,
    status: status,
    distanceFromRouteM: nearest.distanceM,
    distanceToStartM: distanceToStartM,
    cue: cue,
    rhythmBrief: _rhythmForOnRoute(cue),
  );
}

List<double> _cumulativeMeters(List<LatLng> nodes) {
  final cumulative = List<double>.filled(nodes.length, 0);
  var totalM = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    totalM += RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
    cumulative[i] = totalM;
  }
  return cumulative;
}

DriveRouteStatus _routeStatus({
  required double distanceFromRouteM,
  required double distanceToStartM,
  required double alongM,
  required double remainingM,
}) {
  if (remainingM <= 45) return DriveRouteStatus.completed;
  if (distanceToStartM > 180 && alongM < 180) {
    return DriveRouteStatus.approachingStart;
  }
  if (distanceFromRouteM > 120) return DriveRouteStatus.offRoute;
  return DriveRouteStatus.onRoute;
}

DriveRhythmBrief _rhythmForApproachingStart(double distanceToStartM) {
  return DriveRhythmBrief(
    rhythmLabel: '시작 준비',
    advice:
        '시작점까지 ${formatDriveMeters(distanceToStartM)}. 루트 가까이 오면 커브 리듬 안내를 시작합니다.',
    horizonText: 'START',
    severity: 0,
  );
}

DriveRhythmBrief _rhythmForOffRoute(double distanceFromRouteM) {
  return DriveRhythmBrief(
    rhythmLabel: '루트 복귀',
    advice:
        '지도 라인까지 약 ${formatDriveMeters(distanceFromRouteM)}. 가까워지면 안내를 이어갑니다.',
    horizonText: 'REJOIN',
    severity: 2,
  );
}

DriveRhythmBrief _rhythmForOnRoute(DriveCurveCue? cue) {
  if (cue == null) {
    return const DriveRhythmBrief(
      rhythmLabel: '흐름 구간',
      advice: '30-800m 안에 큰 기준 커브가 없어요. 라인을 부드럽게 유지하세요.',
      horizonText: 'CLEAR',
      severity: 0,
    );
  }

  final gap = cue.nextGapM;
  if (gap != null && gap <= 360) {
    return DriveRhythmBrief(
      rhythmLabel: '연속 코너 구간',
      advice:
          '${formatDriveMeters(cue.distanceM)} 뒤 ${cue.label}, 이후 ${formatDriveMeters(gap)} 안에 다음 커브가 이어져요.',
      horizonText: 'NEXT ${formatDriveMeters(cue.distanceM)}',
      severity: cue.severity,
    );
  }
  if (gap != null) {
    return DriveRhythmBrief(
      rhythmLabel: '리듬 연결',
      advice:
          '${formatDriveMeters(cue.distanceM)} 뒤 ${cue.label}. 이후 ${formatDriveMeters(gap)} 정도 여유가 있어요.',
      horizonText: 'NEXT ${formatDriveMeters(cue.distanceM)}',
      severity: cue.severity,
    );
  }
  return DriveRhythmBrief(
    rhythmLabel: '단일 커브',
    advice:
        '${formatDriveMeters(cue.distanceM)} 뒤 ${cue.label}. 이후 다음 기준 커브를 다시 감지합니다.',
    horizonText: 'NEXT ${formatDriveMeters(cue.distanceM)}',
    severity: cue.severity,
  );
}

DriveCurveCue? _nextCurveCue(
  List<LatLng> nodes,
  List<double> cumulativeM,
  double alongM,
) {
  for (var i = 1; i < nodes.length - 1; i++) {
    final aheadM = cumulativeM[i] - alongM;
    if (aheadM < 30) continue;
    if (aheadM > 800) break;

    final turn = _turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]);
    final absTurn = turn.abs();
    if (absTurn < 20) continue;

    final direction = turn >= 0 ? '우측' : '좌측';
    final severity = absTurn >= 68
        ? 3
        : absTurn >= 42
        ? 2
        : absTurn >= 26
        ? 1
        : 0;
    final intensity = absTurn >= 68
        ? '헤어핀'
        : absTurn >= 42
        ? '급커브'
        : absTurn >= 26
        ? '중간 커브'
        : '완만한 커브';
    final nextGap = _nextCurveGapM(nodes, cumulativeM, i);
    return DriveCurveCue(
      label: '$direction $intensity',
      detail: nextGap == null
          ? '다음 기준 커브 감지 중'
          : '다음 커브 ${formatDriveMeters(nextGap)} 후',
      icon: turn >= 0
          ? Icons.turn_slight_right_rounded
          : Icons.turn_slight_left_rounded,
      distanceM: aheadM,
      nextGapM: nextGap,
      severity: severity,
    );
  }
  return null;
}

double? _nextCurveGapM(
  List<LatLng> nodes,
  List<double> cumulativeM,
  int fromIndex,
) {
  final fromM = cumulativeM[fromIndex];
  for (var i = fromIndex + 1; i < nodes.length - 1; i++) {
    final gapM = cumulativeM[i] - fromM;
    if (gapM > 900) return null;
    if (_turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]).abs() >= 20) {
      return gapM;
    }
  }
  return null;
}

_Projection _nearestRouteProjection(
  LatLng position,
  List<LatLng> nodes,
  List<double> cumulativeM,
) {
  var best = const _Projection(alongM: 0, distanceM: double.infinity);
  for (var i = 0; i < nodes.length - 1; i++) {
    final segmentM = cumulativeM[i + 1] - cumulativeM[i];
    if (segmentM <= 0) continue;
    final projection = _projectOnSegment(position, nodes[i], nodes[i + 1]);
    final alongM = cumulativeM[i] + segmentM * projection.t;
    if (projection.distanceM < best.distanceM) {
      best = _Projection(alongM: alongM, distanceM: projection.distanceM);
    }
  }
  return best;
}

_SegmentProjection _projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final ap = _metersFrom(a, p);
  final ab = _metersFrom(a, b);
  final ab2 = ab.x * ab.x + ab.y * ab.y;
  final t = ab2 <= 0
      ? 0.0
      : ((ap.x * ab.x + ap.y * ab.y) / ab2).clamp(0.0, 1.0).toDouble();
  final closestX = ab.x * t;
  final closestY = ab.y * t;
  final dx = ap.x - closestX;
  final dy = ap.y - closestY;
  return _SegmentProjection(t: t, distanceM: math.sqrt(dx * dx + dy * dy));
}

_PointM _metersFrom(LatLng origin, LatLng point) {
  final latRad = origin.lat * math.pi / 180;
  return _PointM(
    x: (point.lng - origin.lng) * math.cos(latRad) * 111320,
    y: (point.lat - origin.lat) * 110540,
  );
}

double _turnDegrees(LatLng a, LatLng b, LatLng c) {
  final inBearing = _bearingDegrees(a, b);
  final outBearing = _bearingDegrees(b, c);
  var delta = outBearing - inBearing;
  while (delta > 180) {
    delta -= 360;
  }
  while (delta < -180) {
    delta += 360;
  }
  return delta;
}

double _bearingDegrees(LatLng from, LatLng to) {
  final lat1 = from.lat * math.pi / 180;
  final lat2 = to.lat * math.pi / 180;
  final dLng = (to.lng - from.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String formatDriveMeters(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)}km';
  return '${meters.round()}m';
}

class _Projection {
  final double alongM;
  final double distanceM;

  const _Projection({required this.alongM, required this.distanceM});
}

class _SegmentProjection {
  final double t;
  final double distanceM;

  const _SegmentProjection({required this.t, required this.distanceM});
}

class _PointM {
  final double x;
  final double y;

  const _PointM({required this.x, required this.y});
}
