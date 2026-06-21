import 'dart:math' as math;

import 'route_corner_profile.dart';

enum DriveCornerPhase { upcoming, armed, active, passed, clear }

class DriveCornerSnapshot {
  final RouteCorner? corner;
  final DriveCornerPhase phase;
  final double distanceM;
  final double etaSeconds;
  final List<RouteCorner> sequence;

  const DriveCornerSnapshot({
    required this.corner,
    required this.phase,
    required this.distanceM,
    required this.etaSeconds,
    required this.sequence,
  });

  const DriveCornerSnapshot.clear()
    : corner = null,
      phase = DriveCornerPhase.clear,
      distanceM = double.infinity,
      etaSeconds = double.infinity,
      sequence = const [];
}

class DriveCornerStateMachine {
  static const double _passWindowM = 20;
  static const double _activeWindowM = 20;
  static const double _armedWindowM = 120;
  static const double _previewWindowM = 420;
  static const double _previewEtaS = 12;
  static const double _armedEtaS = 5;

  final RouteCornerProfile profile;

  const DriveCornerStateMachine(this.profile);

  DriveCornerSnapshot read({required double alongM, required double speedKmh}) {
    final candidate = _nextCorner(alongM, speedKmh);
    if (candidate == null) return const DriveCornerSnapshot.clear();

    final corner = candidate.corner;
    final distanceM = candidate.distanceM;
    final etaSeconds = _etaSeconds(distanceM, speedKmh);
    final phase = _phaseFor(distanceM, etaSeconds);
    final sequence = _sequenceFrom(corner);

    return DriveCornerSnapshot(
      corner: corner,
      phase: phase,
      distanceM: math.max(0, distanceM),
      etaSeconds: etaSeconds,
      sequence: sequence,
    );
  }

  _CornerCandidate? _nextCorner(double alongM, double speedKmh) {
    for (final corner in profile.corners) {
      final distanceM = corner.alongM - alongM;
      if (distanceM < -_passWindowM) continue;

      final etaSeconds = _etaSeconds(distanceM, speedKmh);
      final phase = _phaseFor(distanceM, etaSeconds);
      if (phase != DriveCornerPhase.clear) {
        return _CornerCandidate(corner: corner, distanceM: distanceM);
      }

      if (distanceM > _previewWindowM) break;
    }
    return null;
  }

  DriveCornerPhase _phaseFor(double distanceM, double etaSeconds) {
    if (distanceM < -_passWindowM) return DriveCornerPhase.clear;
    if (distanceM < 0) return DriveCornerPhase.passed;
    if (distanceM <= _activeWindowM) return DriveCornerPhase.active;
    if (distanceM <= _armedWindowM || etaSeconds <= _armedEtaS) {
      return DriveCornerPhase.armed;
    }
    if (etaSeconds <= _previewEtaS || distanceM <= _previewWindowM) {
      return DriveCornerPhase.upcoming;
    }
    return DriveCornerPhase.clear;
  }

  List<RouteCorner> _sequenceFrom(RouteCorner corner) {
    final start = profile.corners.indexWhere(
      (item) => item.nodeIndex == corner.nodeIndex,
    );
    if (start < 0) return [corner];

    final result = <RouteCorner>[corner];
    for (var i = start + 1; i < profile.corners.length; i++) {
      final gapM = profile.corners[i].alongM - profile.corners[i - 1].alongM;
      if (gapM > 180) break;
      result.add(profile.corners[i]);
      if (result.length >= 4) break;
    }
    return List.unmodifiable(result);
  }
}

class _CornerCandidate {
  final RouteCorner corner;
  final double distanceM;

  const _CornerCandidate({required this.corner, required this.distanceM});
}

double _etaSeconds(double distanceM, double speedKmh) {
  final metersPerSecond = speedKmh <= 1 ? 13.9 : speedKmh / 3.6;
  return math.max(0, distanceM) / metersPerSecond;
}
