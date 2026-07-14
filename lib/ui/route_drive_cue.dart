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

class TurnInstruction {
  final int sequence;
  final String directionLabel;
  final String intensityLabel;
  final String headline;
  final String command;
  final IconData icon;
  final double distanceFromStartM;
  final double aheadM;
  final int severity;
  final bool finish;

  const TurnInstruction({
    required this.sequence,
    required this.directionLabel,
    required this.intensityLabel,
    required this.headline,
    required this.command,
    required this.icon,
    required this.distanceFromStartM,
    required this.aheadM,
    required this.severity,
    this.finish = false,
  });
}

class TurnByTurnState {
  final TurnInstruction? instruction;
  final int completedInstructions;
  final int totalInstructions;
  final DriveRouteStatus status;

  const TurnByTurnState({
    required this.instruction,
    required this.completedInstructions,
    required this.totalInstructions,
    required this.status,
  });
}

List<TurnInstruction> buildTurnByTurnPlan(
  List<LatLng> nodes, {
  AppLanguage? language,
}) {
  if (nodes.length < 2) return const [];

  final cumulativeM = _cumulativeMeters(nodes);
  final instructions = <TurnInstruction>[];
  for (var i = 1; i < nodes.length - 1; i++) {
    final turn = _turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]);
    final absTurn = turn.abs();
    if (absTurn < 20) continue;
    instructions.add(
      _turnInstruction(
        sequence: instructions.length + 1,
        turn: turn,
        absTurn: absTurn,
        distanceFromStartM: cumulativeM[i],
        aheadM: cumulativeM[i],
        language: language,
      ),
    );
  }

  final finishM = cumulativeM.last;
  instructions.add(
    TurnInstruction(
      sequence: instructions.length + 1,
      directionLabel: _driveText(language, '피니시', 'Finish', 'Arrivée'),
      intensityLabel: _driveText(language, '완료', 'Done', 'Terminé'),
      headline:
          '${formatTurnMeters(finishM)} ${_driveText(language, '피니시', 'Finish', 'Arrivée')}',
      command: _driveText(
        language,
        '루트 완료 지점까지 흐름 유지',
        'Hold the rhythm to the finish',
        'Gardez le rythme jusqu’à l’arrivée',
      ),
      icon: Icons.sports_score_rounded,
      distanceFromStartM: finishM,
      aheadM: finishM,
      severity: 0,
      finish: true,
    ),
  );
  return instructions;
}

TurnByTurnState readTurnByTurnState(
  LatLng position,
  List<LatLng> nodes, {
  AppLanguage? language,
  double? routeProgress,
}) {
  final plan = buildTurnByTurnPlan(nodes, language: language);
  if (plan.isEmpty || nodes.length < 2) {
    return const TurnByTurnState(
      instruction: null,
      completedInstructions: 0,
      totalInstructions: 0,
      status: DriveRouteStatus.approachingStart,
    );
  }

  final cumulativeM = _cumulativeMeters(nodes);
  final totalM = cumulativeM.last;
  final nearest = routeProgress == null
      ? _nearestRouteProjection(position, nodes, cumulativeM)
      : _Projection(
          alongM: totalM * routeProgress.clamp(0.0, 1.0),
          distanceM: 0,
        );
  final distanceToStartM = RevvRoute.haversineKm(position, nodes.first) * 1000;
  final remainingM = math.max(0.0, totalM - nearest.alongM);
  final status = _routeStatus(
    distanceFromRouteM: nearest.distanceM,
    distanceToStartM: distanceToStartM,
    alongM: nearest.alongM,
    remainingM: remainingM,
  );

  final completed = plan
      .where(
        (instruction) => instruction.distanceFromStartM < nearest.alongM - 18,
      )
      .length;
  final nextIndex = completed.clamp(0, plan.length - 1);
  final next = plan[nextIndex];
  final aheadM = math.max(0.0, next.distanceFromStartM - nearest.alongM);
  return TurnByTurnState(
    instruction: _turnWithLiveTiming(
      next,
      aheadM: aheadM,
      status: status,
      language: language,
    ),
    completedInstructions: completed,
    totalInstructions: plan.length,
    status: status,
  );
}

DriveRouteState readDriveRouteState(
  LatLng position,
  List<LatLng> nodes, {
  AppLanguage? language,
  double? minProgress,
  double? maxProgress,
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

  final nearest = _nearestRouteProjection(
    position,
    nodes,
    cumulativeM,
    minAlongM: minProgress == null
        ? null
        : totalM * minProgress.clamp(0.0, 1.0),
    maxAlongM: maxProgress == null
        ? null
        : totalM * maxProgress.clamp(0.0, 1.0),
  );
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
            '${formatDriveMeters(nearest.distanceM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'jusqu’à la ligne')}',
        directionLabel: _driveText(language, '복귀', 'Rejoin', 'Retour'),
        intensityLabel: _driveText(language, '이탈', 'Off', 'Hors'),
        headline: _driveText(language, '루트 이탈', 'Off route', 'Hors route'),
        rhythmLine:
            '${formatDriveMeters(nearest.distanceM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'jusqu’à la ligne')}',
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
  if (distanceFromRouteM > 300) return DriveRouteStatus.offRoute;
  return DriveRouteStatus.onRoute;
}

TurnInstruction _turnInstruction({
  required int sequence,
  required double turn,
  required double absTurn,
  required double distanceFromStartM,
  required double aheadM,
  required AppLanguage? language,
}) {
  final direction = turn >= 0
      ? _driveText(language, '우측', 'Right', 'Droite')
      : _driveText(language, '좌측', 'Left', 'Gauche');
  final intensity = _curveIntensity(absTurn, language);
  final severity = _curveSeverity(absTurn);
  return TurnInstruction(
    sequence: sequence,
    directionLabel: direction,
    intensityLabel: intensity,
    headline: _turnHeadline(
      finish: false,
      directionLabel: direction,
      intensityLabel: intensity,
      aheadM: aheadM,
      language: language,
    ),
    command: _turnCommand(
      finish: false,
      directionLabel: direction,
      intensityLabel: intensity,
      aheadM: aheadM,
      status: DriveRouteStatus.onRoute,
      language: language,
    ),
    icon: _curveIcon(turn, absTurn),
    distanceFromStartM: distanceFromStartM,
    aheadM: aheadM,
    severity: severity,
  );
}

TurnInstruction _turnWithLiveTiming(
  TurnInstruction instruction, {
  required double aheadM,
  required DriveRouteStatus status,
  required AppLanguage? language,
}) {
  return TurnInstruction(
    sequence: instruction.sequence,
    directionLabel: instruction.directionLabel,
    intensityLabel: instruction.intensityLabel,
    headline: _turnHeadline(
      finish: instruction.finish,
      directionLabel: instruction.directionLabel,
      intensityLabel: instruction.intensityLabel,
      aheadM: aheadM,
      language: language,
    ),
    command: _turnCommand(
      finish: instruction.finish,
      directionLabel: instruction.directionLabel,
      intensityLabel: instruction.intensityLabel,
      aheadM: aheadM,
      status: status,
      language: language,
    ),
    icon: instruction.icon,
    distanceFromStartM: instruction.distanceFromStartM,
    aheadM: aheadM,
    severity: instruction.severity,
    finish: instruction.finish,
  );
}

String _turnHeadline({
  required bool finish,
  required String directionLabel,
  required String intensityLabel,
  required double aheadM,
  required AppLanguage? language,
}) {
  if (finish) {
    return '${formatTurnMeters(aheadM)} ${_driveText(language, '피니시', 'Finish', 'Arrivée')}';
  }
  return '${formatTurnMeters(aheadM)} $directionLabel $intensityLabel';
}

String _turnCommand({
  required bool finish,
  required String directionLabel,
  required String intensityLabel,
  required double aheadM,
  required DriveRouteStatus status,
  required AppLanguage? language,
}) {
  if (status == DriveRouteStatus.offRoute) {
    return _driveText(
      language,
      '루트로 복귀한 뒤 다음 턴을 다시 잡기',
      'Rejoin the route, then reacquire the next turn',
      'Rejoignez la route, puis reprenez le prochain virage',
    );
  }
  if (finish) {
    return _driveText(
      language,
      '피니시까지 흐름 유지',
      'Hold the rhythm to the finish',
      'Gardez le rythme jusqu’à l’arrivée',
    );
  }
  if (aheadM <= 80) {
    return '$directionLabel $intensityLabel ${_driveText(language, '진입', 'now', 'maintenant')}';
  }
  return '$directionLabel $intensityLabel ${_driveText(language, '준비', 'coming up', 'à venir')}';
}

String formatTurnMeters(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)}km';
  final rounded = (meters / 10).round() * 10;
  return '${rounded.clamp(0, 990)}m';
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
        '${formatDriveMeters(distanceFromRouteM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'jusqu’à la ligne')}',
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
        'Section fluide',
      ),
      advice: _driveText(
        language,
        '직선 구간',
        'Straight section',
        'Section droite',
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
    icon: _curveIcon(first.turn, first.absTurn),
    distanceM: first.aheadM,
    nextGapM: nextGap,
    curveCountAhead: countAhead,
    horizonM: horizonM,
    severity: severity,
  );
}

IconData _curveIcon(double turn, double absTurn) {
  final isRight = turn >= 0;
  if (absTurn >= 68) {
    return isRight
        ? Icons.turn_sharp_right_rounded
        : Icons.turn_sharp_left_rounded;
  }
  if (absTurn >= 42) {
    return isRight ? Icons.turn_right_rounded : Icons.turn_left_rounded;
  }
  return isRight
      ? Icons.turn_slight_right_rounded
      : Icons.turn_slight_left_rounded;
}

int _curveSeverity(double absTurn) {
  if (absTurn >= 68) return 3;
  if (absTurn >= 42) return 2;
  if (absTurn >= 26) return 1;
  return 0;
}

String _curveIntensity(double absTurn, AppLanguage? language) {
  if (absTurn >= 68) {
    return _driveText(language, '급회전', 'Very sharp', 'Très serré');
  }
  if (absTurn >= 42) {
    return _driveText(language, '급커브', 'Sharp', 'Serré');
  }
  if (absTurn >= 26) {
    return _driveText(language, '커브', 'Curve', 'Virage');
  }
  return _driveText(language, '완만한 커브', 'Easy curve', 'Virage doux');
}

String _rhythmLineForCue({
  required int countAhead,
  required double? nextGapM,
  required double firstAheadM,
  required double horizonM,
  required AppLanguage? language,
}) {
  if (countAhead >= 4 && (nextGapM ?? 999) <= 200) {
    return _driveText(
      language,
      '커브 $countAhead개 연속',
      '$countAhead curves ahead',
      '$countAhead virages à suivre',
    );
  }
  if (countAhead >= 3 && (nextGapM ?? 999) <= 280) {
    return _driveText(
      language,
      '커브 $countAhead개 연속',
      '$countAhead curves ahead',
      '$countAhead virages à suivre',
    );
  }
  if (countAhead >= 2) {
    return _driveText(
      language,
      '커브 $countAhead개 연속',
      '$countAhead curves ahead',
      '$countAhead virages à suivre',
    );
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
  if (cue.curveCountAhead >= 4 && (cue.nextGapM ?? 999) <= 200) {
    return _driveText(language, '연속 커브', 'Curve sequence', 'Virages liés');
  }
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
    return _driveText(language, '흐름 구간', 'Flow section', 'Section fluide');
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
  List<double> cumulativeM, {
  double? minAlongM,
  double? maxAlongM,
}) {
  var best = const _Projection(alongM: 0, distanceM: double.infinity);
  for (var i = 0; i < nodes.length - 1; i++) {
    final segmentM = cumulativeM[i + 1] - cumulativeM[i];
    if (segmentM <= 0) continue;
    final allowedStartM = math.max(cumulativeM[i], minAlongM ?? 0);
    final allowedEndM = math.min(
      cumulativeM[i + 1],
      maxAlongM ?? cumulativeM.last,
    );
    if (allowedStartM > allowedEndM) continue;
    final projection = _projectOnSegment(
      position,
      nodes[i],
      nodes[i + 1],
      minT: (allowedStartM - cumulativeM[i]) / segmentM,
      maxT: (allowedEndM - cumulativeM[i]) / segmentM,
    );
    final alongM = cumulativeM[i] + segmentM * projection.t;
    if (projection.distanceM < best.distanceM) {
      best = _Projection(alongM: alongM, distanceM: projection.distanceM);
    }
  }
  return best;
}

_SegmentProjection _projectOnSegment(
  LatLng p,
  LatLng a,
  LatLng b, {
  double minT = 0,
  double maxT = 1,
}) {
  final ap = _metersFrom(a, p);
  final ab = _metersFrom(a, b);
  final ab2 = ab.x * ab.x + ab.y * ab.y;
  final rawT = ab2 <= 0
      ? 0.0
      : ((ap.x * ab.x + ap.y * ab.y) / ab2).clamp(0.0, 1.0).toDouble();
  final t = rawT.clamp(minT, maxT).toDouble();
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
