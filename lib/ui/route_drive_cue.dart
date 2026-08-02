import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/route_turn_service.dart';
import 'app_copy.dart';

enum DriveRouteStatus { approachingStart, onRoute, offRoute, completed }
enum CurveConfidence { reliable, unknown }

/// Resampling keeps the source segment length so synthetic density never
/// disguises a sparse source corner as reliable geometry.
class ResampledPolyline {
  final List<LatLng> points;
  final double effectiveStepM;
  final List<double> sourceSegmentM;

  const ResampledPolyline({
    required this.points,
    required this.effectiveStepM,
    required this.sourceSegmentM,
  });
}

class CornerEvent {
  final int entryIndex;
  final double distanceFromStartM;
  final double radiusM;
  final int grade;
  final int turnSign;

  const CornerEvent({
    required this.entryIndex,
    required this.distanceFromStartM,
    required this.radiusM,
    required this.grade,
    required this.turnSign,
  });
}

/// Route-level geometry compiled once per route content. Position is projected
/// against this immutable structure separately, so GPS ticks do not rebuild it.
class RouteCueGeometry {
  final ResampledPolyline poly;
  final List<double> cumulativeM;
  final List<double> radiusM;
  final List<int> grade;
  final List<CurveConfidence> conf;
  final List<CornerEvent> corners;
  final List<TurnInstruction> turnPlan;

  const RouteCueGeometry({
    required this.poly,
    required this.cumulativeM,
    required this.radiusM,
    required this.grade,
    required this.conf,
    required this.corners,
    required this.turnPlan,
  });
}

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
  final int grade;
  final int? clusterId;

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
    this.grade = 0,
    this.clusterId,
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
  final int grade;
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
    this.grade = 0,
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
  String? routeId,
}) {
  final geometry = _geometryFor(nodes, routeId: routeId);
  if (geometry.poly.points.length < 2) return const [];
  if (language == null) return geometry.turnPlan;
  return _turnPlanForGeometry(geometry, language);
}

TurnByTurnState readTurnByTurnState(
  LatLng position,
  List<LatLng> nodes, {
  AppLanguage? language,
  String? routeId,
}) {
  final geometry = _geometryFor(nodes, routeId: routeId);
  final plan = language == null ? geometry.turnPlan : _turnPlanForGeometry(geometry, language);
  if (plan.isEmpty || geometry.poly.points.length < 2) {
    return const TurnByTurnState(
      instruction: null,
      completedInstructions: 0,
      totalInstructions: 0,
      status: DriveRouteStatus.approachingStart,
    );
  }

  final totalM = geometry.cumulativeM.last;
  final nearest = _projectionFor(geometry, position);
  final distanceToStartM =
      RevvRoute.haversineKm(position, geometry.poly.points.first) * 1000;
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
  String? routeId,
}) {
  final geometry = _geometryFor(nodes, routeId: routeId);
  if (geometry.poly.points.length < 3) {
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

  final cumulativeM = geometry.cumulativeM;
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

  final nearest = _projectionFor(geometry, position);
  final distanceToStartM =
      RevvRoute.haversineKm(position, geometry.poly.points.first) * 1000;
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

  final cue = _nextCurveCue(geometry, nearest.alongM, language);
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

/// Removes invalid points and zero-length source segments before resampling.
List<LatLng> normalizePolyline(List<LatLng> nodes) {
  final normalized = <LatLng>[];
  for (final node in nodes) {
    if (!node.lat.isFinite || !node.lng.isFinite) continue;
    if (normalized.isNotEmpty &&
        RevvRoute.haversineKm(normalized.last, node) * 1000 <= 0.000001) {
      continue;
    }
    normalized.add(node);
  }
  return List.unmodifiable(normalized);
}

/// Samples a polyline at equal arc-length intervals while retaining the length
/// of the original segment that supplied every sample.
ResampledPolyline resampleByArcLength(
  List<LatLng> nodes, {
  double stepM = 10,
}) {
  final normalized = normalizePolyline(nodes);
  if (normalized.length < 2) {
    return ResampledPolyline(
      points: normalized,
      effectiveStepM: 0,
      sourceSegmentM: List<double>.filled(normalized.length, 0),
    );
  }

  final sourceSegments = List<double>.generate(
    normalized.length - 1,
    (index) =>
        RevvRoute.haversineKm(normalized[index], normalized[index + 1]) * 1000,
  );
  final cumulative = List<double>.filled(normalized.length, 0);
  for (var i = 1; i < normalized.length; i++) {
    cumulative[i] = cumulative[i - 1] + sourceSegments[i - 1];
  }
  final totalM = cumulative.last;
  if (!totalM.isFinite || totalM <= 0) {
    return ResampledPolyline(
      points: List.unmodifiable([normalized.first]),
      effectiveStepM: 0,
      sourceSegmentM: const [0],
    );
  }

  final requestedStepM = stepM.isFinite && stepM > 0 ? stepM : 10.0;
  final segmentCount = math.min(3999, math.max(1, (totalM / requestedStepM).ceil()));
  final effectiveStepM = totalM / segmentCount;
  final points = <LatLng>[];
  final sourceForPoint = <double>[];
  var sourceIndex = 0;
  for (var sampleIndex = 0; sampleIndex <= segmentCount; sampleIndex++) {
    final targetM = sampleIndex == segmentCount
        ? totalM
        : sampleIndex * effectiveStepM;
    while (sourceIndex < sourceSegments.length - 1 &&
        cumulative[sourceIndex + 1] < targetM) {
      sourceIndex++;
    }
    final startM = cumulative[sourceIndex];
    final sourceM = sourceSegments[sourceIndex];
    final t = sourceM <= 0
        ? 0.0
        : ((targetM - startM) / sourceM).clamp(0.0, 1.0).toDouble();
    final a = normalized[sourceIndex];
    final b = normalized[sourceIndex + 1];
    points.add(LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t));
    sourceForPoint.add(sourceM);
  }
  points[0] = normalized.first;
  points[points.length - 1] = normalized.last;
  sourceForPoint[sourceForPoint.length - 1] = sourceSegments.last;
  return ResampledPolyline(
    points: List.unmodifiable(points),
    effectiveStepM: effectiveStepM,
    sourceSegmentM: List.unmodifiable(sourceForPoint),
  );
}

/// Circumcircle radius at [i]. The lookaround is a physical span, not an
/// adjacent-point count, so the result stays stable if resampling is capped.
double curveRadiusM(
  ResampledPolyline poly,
  int i, {
  double spanM = 20,
}) {
  final k = _spanIndex(poly, spanM);
  if (i - k < 0 || i + k >= poly.points.length) return double.infinity;
  final a = _metersFrom(poly.points[i], poly.points[i - k]);
  final c = _metersFrom(poly.points[i], poly.points[i + k]);
  final sideA = math.sqrt(c.x * c.x + c.y * c.y);
  final sideB = math.sqrt(a.x * a.x + a.y * a.y);
  final dx = c.x - a.x;
  final dy = c.y - a.y;
  final sideC = math.sqrt(dx * dx + dy * dy);
  final twiceArea = (a.x * c.y - a.y * c.x).abs();
  if (twiceArea < 0.000002) return double.infinity;
  return sideA * sideB * sideC / (2 * twiceArea);
}

CurveConfidence curveConfidenceAt(
  ResampledPolyline poly,
  int i, {
  double spanM = 20,
}) {
  final k = _spanIndex(poly, spanM);
  if (i - k < 0 || i + k >= poly.sourceSegmentM.length) {
    return CurveConfidence.unknown;
  }
  final maxSourceM = math.max(
    poly.sourceSegmentM[i - k],
    math.max(poly.sourceSegmentM[i], poly.sourceSegmentM[i + k]),
  );
  return maxSourceM <= 60
      ? CurveConfidence.reliable
      : CurveConfidence.unknown;
}

int rallyGradeFromRadius(double radiusM) {
  if (!radiusM.isFinite || radiusM >= 400) return 0;
  if (radiusM < 25) return 1;
  if (radiusM < 45) return 2;
  if (radiusM < 80) return 3;
  if (radiusM < 140) return 4;
  if (radiusM < 250) return 5;
  return 6;
}

int _spanIndex(ResampledPolyline poly, double spanM) {
  final stepM = poly.effectiveStepM;
  if (!stepM.isFinite || stepM <= 0) return 2;
  return math.max(2, (spanM / stepM).round());
}

List<double> medianRadius5(List<double> radii) {
  final filtered = List<double>.filled(radii.length, double.infinity);
  for (var index = 0; index < radii.length; index++) {
    final start = math.max(0, index - 2);
    final end = math.min(radii.length, index + 3);
    switch (end - start) {
      case 1:
        filtered[index] = radii[start];
        break;
      case 2:
        filtered[index] = _upperMedian2(radii[start], radii[start + 1]);
        break;
      case 3:
        filtered[index] = _median3(
          radii[start],
          radii[start + 1],
          radii[start + 2],
        );
        break;
      case 4:
        filtered[index] = _upperMedian4(
          radii[start],
          radii[start + 1],
          radii[start + 2],
          radii[start + 3],
        );
        break;
      default:
        filtered[index] = _median5(
          radii[start],
          radii[start + 1],
          radii[start + 2],
          radii[start + 3],
          radii[start + 4],
        );
    }
  }
  return filtered;
}

double _upperMedian2(double a, double b) => a > b ? a : b;

double _median3(double a, double b, double c) {
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  if (b > c) {
    final value = b;
    b = c;
    c = value;
  }
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  return b;
}

double _upperMedian4(double a, double b, double c, double d) {
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  if (b > c) {
    final value = b;
    b = c;
    c = value;
  }
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  if (c > d) {
    final value = c;
    c = d;
    d = value;
  }
  if (b > c) {
    final value = b;
    b = c;
    c = value;
  }
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  return c;
}

double _median5(double a, double b, double c, double d, double e) {
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  if (b > c) {
    final value = b;
    b = c;
    c = value;
  }
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  if (c > d) {
    final value = c;
    c = d;
    d = value;
  }
  if (b > c) {
    final value = b;
    b = c;
    c = value;
  }
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  if (d > e) {
    final value = d;
    d = e;
    e = value;
  }
  if (c > d) {
    final value = c;
    c = d;
    d = value;
  }
  if (b > c) {
    final value = b;
    b = c;
    c = value;
  }
  if (a > b) {
    final value = a;
    a = b;
    b = value;
  }
  return c;
}

int _routeCueCompileCount = 0;
int get debugRouteCueCompileCount => _routeCueCompileCount;
_RouteCueCache? _routeCueCache;

void debugResetRouteCueCache() {
  _routeCueCache = null;
  _routeCueCompileCount = 0;
}

RouteCueGeometry compileRouteCueGeometry(List<LatLng> nodes) {
  _routeCueCompileCount++;
  final poly = resampleByArcLength(nodes);
  final cumulativeM = _cumulativeMeters(poly.points);
  final rawRadius = List<double>.filled(poly.points.length, double.infinity);
  final conf = List<CurveConfidence>.generate(
    poly.points.length,
    (index) => curveConfidenceAt(poly, index),
  );
  final span = _spanIndex(poly, 20);
  for (var index = span; index + span < poly.points.length; index++) {
    if (!_isCoarseCurveCandidate(poly, index, span)) continue;
    if (conf[index] == CurveConfidence.reliable) {
      rawRadius[index] = curveRadiusM(poly, index);
    }
  }
  final radiusM = medianRadius5(rawRadius);
  final grade = List<int>.generate(
    poly.points.length,
    (index) => conf[index] == CurveConfidence.reliable
        ? rallyGradeFromRadius(radiusM[index])
        : 0,
  );
  final corners = _mergeCorners(poly, cumulativeM, radiusM, grade);
  final draft = RouteCueGeometry(
    poly: poly,
    cumulativeM: List.unmodifiable(cumulativeM),
    radiusM: List.unmodifiable(radiusM),
    grade: List.unmodifiable(grade),
    conf: List.unmodifiable(conf),
    corners: List.unmodifiable(corners),
    turnPlan: const [],
  );
  return RouteCueGeometry(
    poly: draft.poly,
    cumulativeM: draft.cumulativeM,
    radiusM: draft.radiusM,
    grade: draft.grade,
    conf: draft.conf,
    corners: draft.corners,
    turnPlan: List.unmodifiable(_turnPlanForGeometry(draft, null)),
  );
}

/// Rejects straight samples with only vector arithmetic before the more
/// expensive local circumcircle calculation. A one-degree threshold is below
/// the smallest turn that can yield a 400m rally-grade radius at a 20m span.
bool _isCoarseCurveCandidate(ResampledPolyline poly, int index, int span) {
  final a = poly.points[index - span];
  final b = poly.points[index];
  final c = poly.points[index + span];
  final inX = a.lng - b.lng;
  final inY = a.lat - b.lat;
  final outX = c.lng - b.lng;
  final outY = c.lat - b.lat;
  final inSquared = inX * inX + inY * inY;
  final outSquared = outX * outX + outY * outY;
  if (inSquared <= 0 || outSquared <= 0) return false;
  final cross = inX * outY - inY * outX;
  const sinOneDegreeSquared = 0.000304586490452;
  return cross * cross > inSquared * outSquared * sinOneDegreeSquared;
}

RouteCueGeometry primeRouteCueGeometry(
  List<LatLng> nodes, {
  String? routeId,
}) => _geometryFor(nodes, routeId: routeId);

RouteCueGeometry _geometryFor(List<LatLng> nodes, {String? routeId}) {
  final cached = _routeCueCache;
  if (cached != null &&
      cached.routeId == routeId &&
      _sameRouteNodeContent(cached.nodes, nodes)) {
    return cached.geometry;
  }
  final geometry = compileRouteCueGeometry(nodes);
  _routeCueCache = _RouteCueCache(
    routeId: routeId,
    nodes: List.unmodifiable(List<LatLng>.from(nodes)),
    geometry: geometry,
  );
  return geometry;
}

bool _sameRouteNodeContent(List<LatLng> a, List<LatLng> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].lat != b[i].lat || a[i].lng != b[i].lng) return false;
  }
  return true;
}

_Projection _projectionFor(RouteCueGeometry geometry, LatLng position) {
  final cached = _routeCueCache;
  if (cached != null && identical(cached.geometry, geometry)) {
    final lastPosition = cached.projectionPosition;
    final lastProjection = cached.projection;
    if (lastPosition != null &&
        lastProjection != null &&
        lastPosition.lat == position.lat &&
        lastPosition.lng == position.lng) {
      return lastProjection;
    }
    final projection = _nearestRouteProjection(
      position,
      geometry.poly.points,
      geometry.cumulativeM,
    );
    cached.projectionPosition = position;
    cached.projection = projection;
    return projection;
  }
  return _nearestRouteProjection(position, geometry.poly.points, geometry.cumulativeM);
}

/// Uses the same cached projection as the drive cue and turn book for a GPS
/// tick; the route-turn service remains the owner of NavStep parsing/networking.
NavStepProgress? nextStepProgressWithRouteCueGeometry(
  LatLng position,
  List<LatLng> routeNodes,
  List<NavStep> steps, {
  String? routeId,
}) {
  if (steps.isEmpty) return null;
  final geometry = _geometryFor(routeNodes, routeId: routeId);
  if (geometry.poly.points.length < 2) return null;
  final alongM = _projectionFor(geometry, position).alongM;
  for (final step in steps) {
    final aheadM = step.distanceFromStartM - alongM;
    if (aheadM >= -18) {
      return NavStepProgress(step: step, aheadM: math.max(0.0, aheadM));
    }
  }
  return null;
}

List<CornerEvent> _mergeCorners(
  ResampledPolyline poly,
  List<double> cumulativeM,
  List<double> radiusM,
  List<int> grade,
) {
  final signs = List<int>.generate(grade.length, (index) {
    if (grade[index] == 0) return 0;
    final k = _spanIndex(poly, 20);
    if (index - k < 0 || index + k >= poly.points.length) return 0;
    final turn = _turnDegrees(poly.points[index - k], poly.points[index], poly.points[index + k]);
    return turn >= 0 ? 1 : -1;
  });
  final stabilizedSigns =
      stabilizeCornerSigns(signs, grade, cumulativeM, poly.effectiveStepM);
  final candidateIndexes = <int>[
    for (var i = 0; i < grade.length; i++)
      if (grade[i] > 0 && stabilizedSigns[i] != 0) i,
  ];
  return mergeCornerEvents([
    for (final index in candidateIndexes)
      CornerEvent(
        entryIndex: index,
        distanceFromStartM: cumulativeM[index],
        radiusM: radiusM[index],
        grade: grade[index],
        turnSign: stabilizedSigns[index],
      ),
  ]);
}

/// Merges already confidence-gated, sign-stabilized corner samples into the
/// clusters used by the UI, turn book, and voice budget.
List<CornerEvent> mergeCornerEvents(List<CornerEvent> corners) {
  final merged = <CornerEvent>[];
  var cursor = 0;
  while (cursor < corners.length) {
    final entry = corners[cursor];
    var last = entry;
    var minRadius = entry.radiusM;
    var minGrade = entry.grade;
    cursor++;
    while (cursor < corners.length) {
      final next = corners[cursor];
      if (next.turnSign != entry.turnSign ||
          next.distanceFromStartM - last.distanceFromStartM > 30) {
        break;
      }
      minRadius = math.min(minRadius, next.radiusM);
      minGrade = math.min(minGrade, next.grade);
      last = next;
      cursor++;
    }
    merged.add(CornerEvent(
      entryIndex: entry.entryIndex,
      distanceFromStartM: entry.distanceFromStartM,
      radiusM: minRadius,
      grade: minGrade,
      turnSign: entry.turnSign,
    ));
  }
  return List.unmodifiable(merged);
}

List<int> stabilizeCornerSigns(
  List<int> signs,
  List<int> grade,
  List<double> cumulativeM,
  double stepM,
) {
  final stabilized = List<int>.from(signs);
  final runs = <_SignRun>[];
  var index = 0;
  while (index < stabilized.length) {
    if (grade[index] == 0 || stabilized[index] == 0) {
      index++;
      continue;
    }
    final sign = stabilized[index];
    final start = index;
    while (index + 1 < stabilized.length &&
        grade[index + 1] > 0 &&
        stabilized[index + 1] == sign) {
      index++;
    }
    runs.add(_SignRun(sign: sign, start: start, end: index));
    index++;
  }
  for (var runIndex = 1; runIndex < runs.length - 1; runIndex++) {
    final previous = runs[runIndex - 1];
    final current = runs[runIndex];
    final next = runs[runIndex + 1];
    final sustainedM = math.max(
      stepM,
      cumulativeM[current.end] - cumulativeM[current.start],
    );
    if (previous.sign == next.sign &&
        current.sign != previous.sign &&
        sustainedM < 15) {
      for (var point = current.start; point <= current.end; point++) {
        stabilized[point] = previous.sign;
      }
    }
  }
  return List.unmodifiable(stabilized);
}

class _SignRun {
  final int sign;
  final int start;
  final int end;

  const _SignRun({required this.sign, required this.start, required this.end});
}

class _RouteCueCache {
  final String? routeId;
  final List<LatLng> nodes;
  final RouteCueGeometry geometry;
  LatLng? projectionPosition;
  _Projection? projection;

  _RouteCueCache({
    required this.routeId,
    required this.nodes,
    required this.geometry,
  });
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
  required int turnSign,
  required int grade,
  required double distanceFromStartM,
  required double aheadM,
  required AppLanguage? language,
}) {
  final direction = turnSign >= 0
      ? _driveText(language, '우측', 'Right', 'Droite')
      : _driveText(language, '좌측', 'Left', 'Gauche');
  final intensity = _curveIntensityForGrade(grade, language);
  final severity = _curveSeverityForGrade(grade);
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
    icon: _curveIconForGrade(turnSign, grade),
    distanceFromStartM: distanceFromStartM,
    aheadM: aheadM,
    severity: severity,
    grade: grade,
  );
}

List<TurnInstruction> _turnPlanForGeometry(
  RouteCueGeometry geometry,
  AppLanguage? language,
) {
  if (geometry.poly.points.length < 2) return const [];
  final instructions = <TurnInstruction>[];
  for (final corner in geometry.corners) {
    instructions.add(_turnInstruction(
      sequence: instructions.length + 1,
      turnSign: corner.turnSign,
      grade: corner.grade,
      distanceFromStartM: corner.distanceFromStartM,
      aheadM: corner.distanceFromStartM,
      language: language,
    ));
  }
  final finishM = geometry.cumulativeM.last;
  instructions.add(TurnInstruction(
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
  ));
  return instructions;
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
    grade: instruction.grade,
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
  RouteCueGeometry geometry,
  double alongM,
  AppLanguage? language,
) {
  final candidates = _cornerCandidates(
    geometry,
    alongM,
    minAheadM: 30,
    maxAheadM: 1000,
  );

  if (candidates.isEmpty || candidates.first.aheadM > 800) return null;
  return _cueForCornerCandidates(candidates, language);
}

/// Voice selection is deliberately separate from the UI's next-corner cue:
/// among eligible clusters it chooses the smallest grade (highest risk).
DriveCurveCue? readVoiceCurveCue(
  LatLng position,
  List<LatLng> nodes, {
  required double? trustedSpeedMps,
  AppLanguage? language,
  String? routeId,
}) {
  final geometry = _geometryFor(nodes, routeId: routeId);
  if (geometry.poly.points.length < 2) return null;
  final alongM = _projectionFor(geometry, position).alongM;
  final all = _cornerCandidates(
    geometry,
    alongM,
    minAheadM: 0,
    maxAheadM: 1000,
  );
  final eligible = all.where((candidate) {
    final speedMps = trustedSpeedMps;
    if (speedMps != null && speedMps.isFinite && speedMps > 0) {
      final ttc = candidate.aheadM / speedMps;
      return ttc >= 4 && ttc <= 10;
    }
    return candidate.aheadM >= 50 && candidate.aheadM <= 320;
  }).toList();
  if (eligible.isEmpty) return null;
  eligible.sort((a, b) {
    final grade = a.corner.grade.compareTo(b.corner.grade);
    return grade != 0 ? grade : a.aheadM.compareTo(b.aheadM);
  });
  final selected = eligible.first;
  final tail = all.where((candidate) => candidate.aheadM >= selected.aheadM).toList();
  return _cueForCornerCandidates([selected, ...tail.skip(1)], language);
}

List<_CornerCandidate> _cornerCandidates(
  RouteCueGeometry geometry,
  double alongM, {
  required double minAheadM,
  required double maxAheadM,
}) {
  final candidates = <_CornerCandidate>[];
  for (final corner in geometry.corners) {
    final aheadM = corner.distanceFromStartM - alongM;
    if (aheadM < minAheadM) continue;
    if (aheadM > maxAheadM) break;
    candidates.add(_CornerCandidate(corner: corner, aheadM: aheadM));
  }
  return candidates;
}

DriveCurveCue _cueForCornerCandidates(
  List<_CornerCandidate> candidates,
  AppLanguage? language,
) {
  final first = candidates.first;
  final direction = first.corner.turnSign >= 0
      ? _driveText(language, '우측', 'Right', 'Droite')
      : _driveText(language, '좌측', 'Left', 'Gauche');
  final severity = _curveSeverityForGrade(first.corner.grade);
  final intensity = _curveIntensityForGrade(first.corner.grade, language);
  final nextGap = candidates.length < 2
      ? null
      : candidates[1].aheadM - first.aheadM;
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
    icon: _curveIconForGrade(first.corner.turnSign, first.corner.grade),
    distanceM: first.aheadM,
    nextGapM: nextGap,
    curveCountAhead: countAhead,
    horizonM: horizonM,
    severity: severity,
    grade: first.corner.grade,
    clusterId: first.corner.entryIndex,
  );
}

IconData _curveIconForGrade(int turnSign, int grade) {
  final isRight = turnSign >= 0;
  if (grade == 1) {
    return isRight
        ? Icons.turn_sharp_right_rounded
        : Icons.turn_sharp_left_rounded;
  }
  if (grade == 2 || grade == 3) {
    return isRight ? Icons.turn_right_rounded : Icons.turn_left_rounded;
  }
  return isRight
      ? Icons.turn_slight_right_rounded
      : Icons.turn_slight_left_rounded;
}

int _curveSeverityForGrade(int grade) {
  if (grade == 1) return 3;
  if (grade == 2 || grade == 3) return 2;
  if (grade == 4) return 1;
  return 0;
}

String _curveIntensityForGrade(int grade, AppLanguage? language) {
  if (grade == 1) {
    return _driveText(language, '헤어핀', 'Hairpin', 'Épingle');
  }
  if (grade == 2 || grade == 3) {
    return _driveText(language, '타이트', 'Tight', 'Serré');
  }
  if (grade == 4) {
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
  if (countAhead >= 4 && (nextGapM ?? 999) <= 200) {
    return _driveText(
      language,
      '스위치백 구간',
      'Switchback section',
      'Section en lacets',
    );
  }
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
  if (cue.curveCountAhead >= 4 && (cue.nextGapM ?? 999) <= 200) {
    return _driveText(language, '스위치백', 'Switchback', 'Lacets');
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

class _CornerCandidate {
  final CornerEvent corner;
  final double aheadM;

  const _CornerCandidate({
    required this.corner,
    required this.aheadM,
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
