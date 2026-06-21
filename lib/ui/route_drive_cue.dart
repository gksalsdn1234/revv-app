import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import 'app_copy.dart';
import 'drive_corner_state_machine.dart';
import 'route_corner_profile.dart';

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
  final String? etaText;
  final String? phaseLabel;
  final String? cornerTypeLabel;
  final String? sequenceLine;

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
    this.etaText,
    this.phaseLabel,
    this.cornerTypeLabel,
    this.sequenceLine,
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
  final double alongM;
  final double remainingKm;
  final DriveCurveCue? cue;
  final DriveRhythmBrief rhythmBrief;
  final DriveRouteStatus status;
  final double distanceFromRouteM;
  final double distanceToStartM;

  const DriveRouteState({
    required this.progress,
    required this.alongM,
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
  double? minimumAlongM,
  double speedKmh = 0,
  RouteCornerProfile? cornerProfile,
  DriveCornerStateMachine? cornerStateMachine,
  List<RouteSegmentRange> routeSegments = const [],
}) {
  if (nodes.length < 3) {
    return DriveRouteState(
      progress: 0,
      alongM: 0,
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
      alongM: 0,
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

  final rawNearest = _nearestRouteProjection(position, nodes, cumulativeM);
  final minimumM = minimumAlongM?.clamp(0.0, totalM).toDouble();
  final nearest =
      minimumM != null &&
          rawNearest.distanceM <= 120 &&
          rawNearest.alongM < minimumM
      ? _Projection(alongM: minimumM, distanceM: rawNearest.distanceM)
      : rawNearest;
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
      alongM: nearest.alongM,
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
      alongM: nearest.alongM,
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
      alongM: nearest.alongM,
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

  final profile = cornerProfile ?? cornerStateMachine?.profile;
  final stateMachine =
      cornerStateMachine ??
      DriveCornerStateMachine(profile ?? RouteCornerProfile.fromNodes(nodes));
  final cornerSnapshot = stateMachine.read(
    alongM: nearest.alongM,
    speedKmh: speedKmh,
  );
  final inConnector = _isConnectorSegment(
    routeSegments,
    cumulativeM,
    nearest.alongM,
  );
  final cue = inConnector
      ? null
      : _curveCueFromSnapshot(cornerSnapshot, language);
  return DriveRouteState(
    progress: progress,
    alongM: nearest.alongM,
    remainingKm: remainingM / 1000,
    status: status,
    distanceFromRouteM: nearest.distanceM,
    distanceToStartM: distanceToStartM,
    cue: cue,
    rhythmBrief: inConnector
        ? _rhythmForConnector(language)
        : _rhythmForOnRoute(cue, language),
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
        '${formatDriveMeters(distanceFromRouteM)} ${_driveText(language, '앞 복귀', 'to rejoin', 'jusqu’à la ligne')}',
    horizonText: 'REJOIN',
    severity: 2,
  );
}

DriveRhythmBrief _rhythmForConnector(AppLanguage? language) {
  return DriveRhythmBrief(
    rhythmLabel: _driveText(language, '연결 구간', 'Connector', 'Liaison'),
    advice: _driveText(
      language,
      '다음 와인딩까지 흐름 유지',
      'Hold flow to the next winding section',
      'Gardez le rythme jusqu’au prochain sinueux',
    ),
    horizonText: 'LINK',
    severity: 0,
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
        '1.0km 흐름 구간',
        '1.0km flow section',
        '1.0km fluide',
      ),
      horizonText: 'CLEAR',
      severity: 0,
    );
  }

  return DriveRhythmBrief(
    rhythmLabel: _rhythmLabelForCue(cue, language),
    advice: cue.sequenceLine ?? cue.rhythmLine,
    horizonText: formatDriveMeters(cue.distanceM),
    severity: cue.severity,
  );
}

DriveCurveCue? _curveCueFromSnapshot(
  DriveCornerSnapshot snapshot,
  AppLanguage? language,
) {
  final corner = snapshot.corner;
  if (corner == null || snapshot.phase == DriveCornerPhase.clear) return null;

  final distanceM = snapshot.distanceM;
  if (distanceM > 800) return null;

  final direction = corner.turnDegrees >= 0
      ? _driveText(language, '우측', 'Right', 'Droite')
      : _driveText(language, '좌측', 'Left', 'Gauche');
  final intensity = _cornerIntensity(corner, language);
  final etaText = snapshot.phase == DriveCornerPhase.passed
      ? _driveText(language, '방금', 'Just now', 'À l’instant')
      : _formatEta(snapshot.etaSeconds, language);
  final phaseLabel = _phaseLabel(snapshot.phase, language);
  final typeLabel = _cornerTypeLabel(corner.type, language);
  final sequenceLine = _sequenceLineForSnapshot(snapshot, language);
  final headline = switch (snapshot.phase) {
    DriveCornerPhase.active =>
      '${_driveText(language, '진입 중', 'Entering', 'Entrée')} · $direction $intensity',
    DriveCornerPhase.passed =>
      '${_driveText(language, '통과', 'Passed', 'Passé')} · $direction $intensity',
    _ =>
      '$etaText ${_driveText(language, '뒤', 'out', 'avant')} · ${formatDriveMeters(distanceM)} $direction $intensity',
  };

  return DriveCurveCue(
    label: '$direction $intensity',
    detail: sequenceLine,
    directionLabel: direction,
    intensityLabel: intensity,
    headline: headline,
    rhythmLine: sequenceLine,
    icon: corner.turnDegrees >= 0
        ? Icons.turn_slight_right_rounded
        : Icons.turn_slight_left_rounded,
    distanceM: distanceM,
    nextGapM: corner.nextGapM,
    curveCountAhead: snapshot.sequence.length,
    horizonM: _sequenceHorizonM(snapshot),
    severity: corner.severity,
    etaText: etaText,
    phaseLabel: phaseLabel,
    cornerTypeLabel: typeLabel,
    sequenceLine: sequenceLine,
  );
}

String _cornerIntensity(RouteCorner corner, AppLanguage? language) {
  switch (corner.type) {
    case RouteCornerType.hairpin:
      return _driveText(language, '헤어핀', 'Hairpin', 'Épingle');
    case RouteCornerType.switchback:
      return _driveText(language, '스위치백', 'Switchback', 'Lacet');
    case RouteCornerType.chicane:
      return _driveText(language, '전환', 'Chicane', 'Chicane');
    case RouteCornerType.sweeper:
      return _driveText(language, '스위퍼', 'Sweeper', 'Balayage');
    case RouteCornerType.tight:
      return _driveText(language, '타이트', 'Tight', 'Serré');
    case RouteCornerType.medium:
      return _driveText(language, '중간', 'Medium', 'Moyen');
    case RouteCornerType.kink:
      return _driveText(language, '킥', 'Kink', 'Cassure');
  }
}

String _cornerTypeLabel(RouteCornerType type, AppLanguage? language) {
  switch (type) {
    case RouteCornerType.hairpin:
      return _driveText(language, '헤어핀', 'Hairpin', 'Épingle');
    case RouteCornerType.switchback:
      return _driveText(language, '스위치백', 'Switchback', 'Lacet');
    case RouteCornerType.chicane:
      return _driveText(language, '시케인', 'Chicane', 'Chicane');
    case RouteCornerType.sweeper:
      return _driveText(language, '스위퍼', 'Sweeper', 'Balayage');
    case RouteCornerType.tight:
      return _driveText(language, '타이트', 'Tight', 'Serré');
    case RouteCornerType.medium:
      return _driveText(language, '중간 코너', 'Medium corner', 'Virage moyen');
    case RouteCornerType.kink:
      return _driveText(language, '짧은 킥', 'Kink', 'Cassure');
  }
}

String _phaseLabel(DriveCornerPhase phase, AppLanguage? language) {
  switch (phase) {
    case DriveCornerPhase.upcoming:
      return _driveText(language, '미리보기', 'Preview', 'Aperçu');
    case DriveCornerPhase.armed:
      return _driveText(language, '준비', 'Ready', 'Prêt');
    case DriveCornerPhase.active:
      return _driveText(language, '진입', 'Entry', 'Entrée');
    case DriveCornerPhase.passed:
      return _driveText(language, '통과', 'Passed', 'Passé');
    case DriveCornerPhase.clear:
      return _driveText(language, '흐름', 'Flow', 'Fluide');
  }
}

String _formatEta(double etaSeconds, AppLanguage? language) {
  if (!etaSeconds.isFinite) {
    return _driveText(language, '대기', 'Wait', 'Attente');
  }
  if (etaSeconds >= 60) {
    return '${(etaSeconds / 60).round()}${_driveText(language, '분', 'm', 'min')}';
  }
  return '${math.max(1, etaSeconds.round())}${_driveText(language, '초', 's', 's')}';
}

String _sequenceLineForSnapshot(
  DriveCornerSnapshot snapshot,
  AppLanguage? language,
) {
  final sequence = snapshot.sequence;
  if (sequence.length >= 3) {
    final nextGap = sequence.first.nextGapM;
    final gapText = nextGap == null ? '' : ' · ${formatDriveMeters(nextGap)}';
    return '${sequence.length}${_driveText(language, '개 짧은 전환', ' quick switches', ' transitions rapides')}$gapText';
  }
  if (sequence.length == 2) {
    final gapM = sequence.last.alongM - sequence.first.alongM;
    return '${_driveText(language, '이후', 'Next', 'Puis')} ${formatDriveMeters(gapM)} ${_driveText(language, '연속 코너', 'continuous corners', 'virages enchaînés')}';
  }

  final corner = snapshot.corner;
  if (corner?.nextGapM != null) {
    return '${_driveText(language, '이후', 'Next', 'Puis')} ${formatDriveMeters(corner!.nextGapM!)} ${_driveText(language, '여유', 'clear gap', 'respiration')}';
  }
  return _driveText(language, '단일 커브', 'Single curve', 'Virage isolé');
}

double _sequenceHorizonM(DriveCornerSnapshot snapshot) {
  final sequence = snapshot.sequence;
  if (sequence.isEmpty) return snapshot.distanceM;
  return math.max(
    snapshot.distanceM,
    sequence.last.alongM - sequence.first.alongM + snapshot.distanceM,
  );
}

String _rhythmLabelForCue(DriveCurveCue cue, AppLanguage? language) {
  if (cue.curveCountAhead >= 3) {
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
  return _driveText(language, '단일 커브', 'Single curve', 'Virage isolé');
}

bool _isConnectorSegment(
  List<RouteSegmentRange> segments,
  List<double> cumulativeM,
  double alongM,
) {
  if (segments.isEmpty || cumulativeM.length < 2) return false;
  for (final segment in segments) {
    if (!segment.isConnector) continue;
    final start = segment.startNodeIndex.clamp(0, cumulativeM.length - 1);
    final end = segment.endNodeIndex.clamp(0, cumulativeM.length - 1);
    if (end <= start) continue;
    final startM = cumulativeM[start];
    final endM = cumulativeM[end];
    if (alongM >= startM && alongM <= endM) return true;
  }
  return false;
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
