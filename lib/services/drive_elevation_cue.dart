import 'package:flutter/foundation.dart';

enum DriveElevationTrend { uphill, downhill }

enum DriveElevationFeature { grade, crest }

@immutable
class DriveElevationCue {
  const DriveElevationCue({
    required this.trend,
    required this.changeM,
    required this.distanceM,
    required this.stageId,
    this.feature = DriveElevationFeature.grade,
    this.followingChangeM,
  });

  final DriveElevationTrend trend;
  final double changeM;
  final double distanceM;
  final String stageId;
  final DriveElevationFeature feature;
  final double? followingChangeM;

  bool get isCrest => feature == DriveElevationFeature.crest;
}

/// Returns the next sustained climb or descent within the near driving
/// horizon. Small/noisy undulations and gentle grades stay silent.
DriveElevationCue? nextDriveElevationCue({
  required List<double>? elevationProfile,
  required double routeDistanceKm,
  required double routeProgress,
  double lookAheadM = 500,
  double minimumChangeM = 30,
  double minimumAverageGrade = 0.025,
}) {
  final profile = elevationProfile;
  if (profile == null ||
      profile.length < 2 ||
      profile.any((value) => !value.isFinite) ||
      !routeDistanceKm.isFinite ||
      routeDistanceKm <= 0 ||
      !routeProgress.isFinite) {
    return null;
  }
  final routeDistanceM = routeDistanceKm * 1000;
  final currentM = routeProgress.clamp(0.0, 1.0) * routeDistanceM;
  final runs = _elevationRuns(profile);

  // A crest is only claimed when the aligned profile has a meaningful climb
  // followed by a meaningful descent at the same stable local maximum.
  DriveElevationCue? nearestCrest;
  for (var index = 0; index < runs.length - 1; index++) {
    final climb = runs[index];
    final descent = runs[index + 1];
    if (climb.endIndex != descent.startIndex ||
        profile[climb.endIndex] <= profile[climb.startIndex] ||
        profile[descent.endIndex] >= profile[descent.startIndex]) {
      continue;
    }
    final crestM = routeDistanceM * climb.endIndex / (profile.length - 1);
    final distanceToCrestM = crestM - currentM;
    if (distanceToCrestM < 30 || distanceToCrestM > lookAheadM) continue;
    final climbM = profile[climb.endIndex] - profile[climb.startIndex];
    final descentM = profile[descent.startIndex] - profile[descent.endIndex];
    final climbDistanceM =
        routeDistanceM *
        (climb.endIndex - climb.startIndex) /
        (profile.length - 1);
    final descentDistanceM =
        routeDistanceM *
        (descent.endIndex - descent.startIndex) /
        (profile.length - 1);
    if (climbM < minimumChangeM ||
        descentM < minimumChangeM ||
        climbDistanceM <= 0 ||
        descentDistanceM <= 0 ||
        climbM / climbDistanceM < minimumAverageGrade ||
        descentM / descentDistanceM < minimumAverageGrade) {
      continue;
    }
    final candidate = DriveElevationCue(
      trend: DriveElevationTrend.uphill,
      changeM: climbM,
      followingChangeM: descentM,
      distanceM: distanceToCrestM,
      stageId: 'crest:${climb.endIndex}',
      feature: DriveElevationFeature.crest,
    );
    if (nearestCrest == null || candidate.distanceM < nearestCrest.distanceM) {
      nearestCrest = candidate;
    }
  }
  if (nearestCrest != null) return nearestCrest;

  DriveElevationCue? best;
  for (final run in runs) {
    final startM = routeDistanceM * run.startIndex / (profile.length - 1);
    final endM = routeDistanceM * run.endIndex / (profile.length - 1);
    if (endM <= currentM + 20) continue;
    final distanceToStartM = startM > currentM ? startM - currentM : 0.0;
    if (distanceToStartM > lookAheadM) continue;

    final totalChangeM = (profile[run.endIndex] - profile[run.startIndex])
        .abs();
    final eventDistanceM = endM - startM;
    if (totalChangeM < minimumChangeM ||
        eventDistanceM <= 0 ||
        totalChangeM / eventDistanceM < minimumAverageGrade) {
      continue;
    }

    final currentElevation = currentM <= startM
        ? profile[run.startIndex]
        : _interpolatedElevation(profile, currentM / routeDistanceM);
    final remainingChangeM = (profile[run.endIndex] - currentElevation).abs();
    if (remainingChangeM < minimumChangeM * 0.65) continue;

    final trend = profile[run.endIndex] > profile[run.startIndex]
        ? DriveElevationTrend.uphill
        : DriveElevationTrend.downhill;
    final candidate = DriveElevationCue(
      trend: trend,
      changeM: currentM <= startM ? totalChangeM : remainingChangeM,
      distanceM: distanceToStartM,
      stageId: '${trend.name}:${run.startIndex}:${run.endIndex}',
    );
    if (best == null ||
        candidate.distanceM < best.distanceM ||
        (candidate.distanceM == best.distanceM &&
            candidate.changeM > best.changeM)) {
      best = candidate;
    }
  }
  return best;
}

class _ElevationRun {
  const _ElevationRun(this.startIndex, this.endIndex);

  final int startIndex;
  final int endIndex;
}

List<_ElevationRun> _elevationRuns(List<double> profile) {
  const reversalToleranceM = 8.0;
  final runs = <_ElevationRun>[];
  var anchor = 0;
  var extreme = 0;
  var trend = 0;
  for (var index = 1; index < profile.length; index++) {
    if (trend == 0) {
      final change = profile[index] - profile[anchor];
      if (change.abs() >= reversalToleranceM) {
        if (index > anchor + 1 &&
            (profile[index - 1] - profile[anchor]).abs() < 1) {
          anchor = index - 1;
        }
        trend = change > 0 ? 1 : -1;
        extreme = index;
      }
      continue;
    }
    if (trend > 0) {
      if (profile[index] >= profile[extreme]) {
        extreme = index;
      } else if (profile[extreme] - profile[index] >= reversalToleranceM) {
        runs.add(_ElevationRun(anchor, extreme));
        anchor = extreme;
        extreme = index;
        trend = -1;
      }
    } else if (profile[index] <= profile[extreme]) {
      extreme = index;
    } else if (profile[index] - profile[extreme] >= reversalToleranceM) {
      runs.add(_ElevationRun(anchor, extreme));
      anchor = extreme;
      extreme = index;
      trend = 1;
    }
  }
  if (trend != 0 && extreme != anchor) {
    runs.add(_ElevationRun(anchor, extreme));
  }
  return runs;
}

double _interpolatedElevation(List<double> profile, double progress) {
  final position = progress.clamp(0.0, 1.0) * (profile.length - 1);
  final lower = position.floor();
  if (lower >= profile.length - 1) return profile.last;
  final fraction = position - lower;
  return profile[lower] + (profile[lower + 1] - profile[lower]) * fraction;
}
