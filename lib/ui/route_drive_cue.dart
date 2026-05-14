import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import 'app_copy.dart';

enum DriveRouteStatus { approachingStart, onRoute, offRoute, completed }

class DriveCurveCue {
  final String label;
  final String detail;
  final String directionLabel;
  final String intensityLabel;
  final String headline;
  final String rhythmLine;
  final IconData icon;
  final double distanceM;
  final double? nextGapM;
  final int curveCountAhead;
  final double horizonM;
  final int severity;

  const DriveCurveCue({
    required this.label,
    required this.detail,
    required this.directionLabel,
    required this.intensityLabel,
    required this.headline,
    required this.rhythmLine,
    required this.icon,
    required this.distanceM,
    required this.nextGapM,
    required this.curveCountAhead,
    required this.horizonM,
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

DriveRouteState readDriveRouteState(
  LatLng position,
  List<LatLng> nodes, {
  AppLanguage? language,
}) {
  if (nodes.length < 3) {
    return DriveRouteState(
      progress: 0,
      remainingKm: 0,
      cue: null,
      rhythmBrief: DriveRhythmBrief(
        rhythmLabel: _driveText(
          language,
          '경로 대기',
          'Route standby',
          'Route en attente',
        ),
        advice: _driveText(
          language,
          '루트 데이터가 부족해 지도 라인을 먼저 확인해야 해요.',
          'Route data is thin. Check the map line first.',
          'Données de route limitées. Vérifiez la ligne sur carte.',
        ),
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
    return DriveRouteState(
      progress: 0,
      remainingKm: 0,
      cue: null,
      rhythmBrief: DriveRhythmBrief(
        rhythmLabel: _driveText(
          language,
          '경로 대기',
          'Route standby',
          'Route en attente',
        ),
        advice: _driveText(
          language,
          '루트 길이를 계산하지 못했어요. 지도 라인을 먼저 확인하세요.',
          'Route length could not be calculated. Check the map line first.',
          'Longueur inconnue. Vérifiez la ligne sur carte.',
        ),
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
        label: _driveText(
          language,
          '시작점까지 이동',
          'Go to start',
          'Aller au départ',
        ),
        detail: _driveText(
          language,
          '루트 진입 대기',
          'Waiting to enter route',
          'En attente d’entrée',
        ),
        directionLabel: _driveText(language, '시작', 'Start', 'Départ'),
        intensityLabel: _driveText(language, '대기', 'Standby', 'Attente'),
        headline:
            '${_driveText(language, '시작점', 'Start', 'Départ')} ${formatDriveMeters(distanceToStartM)}',
        rhythmLine: _driveText(
          language,
          '루트 진입 대기',
          'Waiting to enter route',
          'En attente d’entrée',
        ),
        icon: Icons.flag_rounded,
        distanceM: distanceToStartM,
        nextGapM: null,
        curveCountAhead: 0,
        horizonM: distanceToStartM,
        severity: 0,
      ),
      rhythmBrief: _rhythmForApproachingStart(distanceToStartM, language),
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
        label: _driveText(language, '루트에서 벗어남', 'Off route', 'Hors route'),
        detail:
            '${formatDriveMeters(nearest.distanceM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'avant retour')}',
        directionLabel: _driveText(language, '복귀', 'Rejoin', 'Retour'),
        intensityLabel: _driveText(language, '이탈', 'Off', 'Hors'),
        headline: _driveText(language, '루트 이탈', 'Off route', 'Hors route'),
        rhythmLine:
            '${formatDriveMeters(nearest.distanceM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'avant retour')}',
        icon: Icons.near_me_disabled_rounded,
        distanceM: nearest.distanceM,
        nextGapM: null,
        curveCountAhead: 0,
        horizonM: nearest.distanceM,
        severity: 2,
      ),
      rhythmBrief: _rhythmForOffRoute(nearest.distanceM, language),
    );
  }

  if (status == DriveRouteStatus.completed) {
    return DriveRouteState(
      progress: 1,
      remainingKm: 0,
      status: status,
      distanceFromRouteM: nearest.distanceM,
      distanceToStartM: distanceToStartM,
      cue: DriveCurveCue(
        label: _driveText(language, '루트 마무리', 'Route finish', 'Fin de route'),
        detail: _driveText(
          language,
          '주행 종료 가능',
          'Ready to end drive',
          'Fin possible',
        ),
        directionLabel: _driveText(language, '완료', 'Done', 'Terminé'),
        intensityLabel: _driveText(language, '마무리', 'Finish', 'Fin'),
        headline: _driveText(
          language,
          '루트 완료',
          'Route complete',
          'Route terminée',
        ),
        rhythmLine: _driveText(
          language,
          '주행 종료 가능',
          'Ready to end drive',
          'Fin possible',
        ),
        icon: Icons.done_rounded,
        distanceM: 0,
        nextGapM: null,
        curveCountAhead: 0,
        horizonM: 0,
        severity: 0,
      ),
      rhythmBrief: DriveRhythmBrief(
        rhythmLabel: _driveText(
          language,
          '루트 완료',
          'Route complete',
          'Route terminée',
        ),
        advice: _driveText(
          language,
          '주행을 종료하고 오늘의 리듬을 저장하세요.',
          'End the drive and save this rhythm.',
          'Terminez et sauvegardez ce rythme.',
        ),
        horizonText: 'DONE',
        severity: 0,
      ),
    );
  }

  final cue = _nextCurveCue(nodes, cumulativeM, nearest.alongM, language);
  return DriveRouteState(
    progress: progress,
    remainingKm: remainingM / 1000,
    status: status,
    distanceFromRouteM: nearest.distanceM,
    distanceToStartM: distanceToStartM,
    cue: cue,
    rhythmBrief: _rhythmForOnRoute(cue, language),
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

DriveRhythmBrief _rhythmForApproachingStart(
  double distanceToStartM,
  AppLanguage? language,
) {
  return DriveRhythmBrief(
    rhythmLabel: _driveText(
      language,
      '시작 대기',
      'Start standby',
      'Attente départ',
    ),
    advice:
        '${_driveText(language, '시작점', 'Start', 'Départ')} ${formatDriveMeters(distanceToStartM)}',
    horizonText: 'START',
    severity: 0,
  );
}

DriveRhythmBrief _rhythmForOffRoute(
  double distanceFromRouteM,
  AppLanguage? language,
) {
  return DriveRhythmBrief(
    rhythmLabel: _driveText(language, '루트 복귀', 'Rejoin route', 'Retour route'),
    advice:
        '${formatDriveMeters(distanceFromRouteM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'avant retour')}',
    horizonText: 'REJOIN',
    severity: 2,
  );
}

DriveRhythmBrief _rhythmForOnRoute(DriveCurveCue? cue, AppLanguage? language) {
  if (cue == null) {
    return DriveRhythmBrief(
      rhythmLabel: _driveText(
        language,
        '흐름 구간',
        'Flow section',
        'Section flow',
      ),
      advice: _driveText(
        language,
        '1.0km 흐름 구간',
        '1.0km flow section',
        '1.0km de flow',
      ),
      horizonText: 'CLEAR',
      severity: 0,
    );
  }

  final rhythmLabel = _rhythmLabelForCue(cue, language);
  return DriveRhythmBrief(
    rhythmLabel: rhythmLabel,
    advice: cue.rhythmLine,
    horizonText: formatDriveMeters(cue.distanceM),
    severity: cue.severity,
  );
}

DriveCurveCue? _nextCurveCue(
  List<LatLng> nodes,
  List<double> cumulativeM,
  double alongM,
  AppLanguage? language,
) {
  final candidates = <_CurveCandidate>[];
  for (var i = 1; i < nodes.length - 1; i++) {
    final aheadM = cumulativeM[i] - alongM;
    if (aheadM < 30) continue;
    if (aheadM > 1000) break;

    final turn = _turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]);
    final absTurn = turn.abs();
    if (absTurn < 20) continue;
    candidates.add(
      _CurveCandidate(index: i, aheadM: aheadM, turn: turn, absTurn: absTurn),
    );
  }

  if (candidates.isEmpty || candidates.first.aheadM > 800) return null;

  final first = candidates.first;
  final direction = first.turn >= 0
      ? _driveText(language, '우측', 'Right', 'Droite')
      : _driveText(language, '좌측', 'Left', 'Gauche');
  final severity = _curveSeverity(first.absTurn);
  final intensity = _curveIntensity(first.absTurn, language);
  final nextGap = _nextCurveGapM(nodes, cumulativeM, first.index);
  final countAhead = candidates.length;
  final horizonM = candidates.last.aheadM;
  final rhythmLine = _rhythmLineForCue(
    countAhead: countAhead,
    nextGapM: nextGap,
    firstAheadM: first.aheadM,
    horizonM: horizonM,
    language: language,
  );

  return DriveCurveCue(
    label: '$direction $intensity',
    detail: rhythmLine,
    directionLabel: direction,
    intensityLabel: intensity,
    headline: '${formatDriveMeters(first.aheadM)} $direction $intensity',
    rhythmLine: rhythmLine,
    icon: first.turn >= 0
        ? Icons.turn_slight_right_rounded
        : Icons.turn_slight_left_rounded,
    distanceM: first.aheadM,
    nextGapM: nextGap,
    curveCountAhead: countAhead,
    horizonM: horizonM,
    severity: severity,
  );
}

int _curveSeverity(double absTurn) {
  if (absTurn >= 68) return 3;
  if (absTurn >= 42) return 2;
  if (absTurn >= 26) return 1;
  return 0;
}

String _curveIntensity(double absTurn, AppLanguage? language) {
  if (absTurn >= 68) {
    return _driveText(language, '헤어핀', 'Hairpin', 'Épingle');
  }
  if (absTurn >= 42) {
    return _driveText(language, '타이트', 'Tight', 'Serré');
  }
  if (absTurn >= 26) {
    return _driveText(language, '중간', 'Medium', 'Moyen');
  }
  return _driveText(language, '완만', 'Gentle', 'Doux');
}

String _rhythmLineForCue({
  required int countAhead,
  required double? nextGapM,
  required double firstAheadM,
  required double horizonM,
  required AppLanguage? language,
}) {
  if (countAhead >= 3 && (nextGapM ?? 999) <= 280) {
    return _driveText(
      language,
      '짧은 좌우 전환',
      'Quick left-right switch',
      'Gauche-droite rapide',
    );
  }
  if (countAhead >= 2) {
    final spanM = math.max(nextGapM ?? 0, horizonM - firstAheadM);
    return '${_driveText(language, '이후', 'Next', 'Puis')} ${formatDriveMeters(spanM)} ${_driveText(language, '연속 코너', 'continuous corners', 'virages enchaînés')}';
  }
  if (nextGapM != null && nextGapM <= 420) {
    return '${_driveText(language, '이후', 'Next', 'Puis')} ${formatDriveMeters(nextGapM)} ${_driveText(language, '연속 코너', 'continuous corners', 'virages enchaînés')}';
  }
  if (nextGapM != null) {
    return '${_driveText(language, '이후', 'Next', 'Puis')} ${formatDriveMeters(nextGapM)} ${_driveText(language, '여유', 'clear gap', 'respiration')}';
  }
  return _driveText(language, '단일 커브', 'Single curve', 'Virage isolé');
}

String _rhythmLabelForCue(DriveCurveCue cue, AppLanguage? language) {
  if (cue.curveCountAhead >= 3 && (cue.nextGapM ?? 999) <= 280) {
    return _driveText(language, '짧은 전환', 'Quick switch', 'Transition rapide');
  }
  if (cue.curveCountAhead >= 2) {
    return _driveText(
      language,
      '연속 코너',
      'Continuous corners',
      'Virages enchaînés',
    );
  }
  if (cue.rhythmLine.contains('흐름') ||
      cue.rhythmLine.contains('flow') ||
      cue.rhythmLine.contains('Flow')) {
    return _driveText(language, '흐름 구간', 'Flow section', 'Section flow');
  }
  return _driveText(language, '단일 커브', 'Single curve', 'Virage isolé');
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

String _driveText(AppLanguage? language, String ko, String en, String fr) {
  if (language == null) return ko;
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}

class _Projection {
  final double alongM;
  final double distanceM;

  const _Projection({required this.alongM, required this.distanceM});
}

class _CurveCandidate {
  final int index;
  final double aheadM;
  final double turn;
  final double absTurn;

  const _CurveCandidate({
    required this.index,
    required this.aheadM,
    required this.turn,
    required this.absTurn,
  });
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
