import '../models/revv_route.dart';

typedef WindingExperienceMetric = ({String label, String value});

class WindingExperienceProfile {
  final int score;
  final String title;
  final String rhythm;
  final String caution;
  final List<String> badges;
  final List<WindingExperienceMetric> metrics;

  const WindingExperienceProfile({
    required this.score,
    required this.title,
    required this.rhythm,
    required this.caution,
    required this.badges,
    required this.metrics,
  });

  factory WindingExperienceProfile.fromRoute(RevvRoute route) {
    final curvyKm = route.tightCurveKm + route.mediumCurveKm;
    final density = route.distanceKm <= 0 ? 0.0 : curvyKm / route.distanceKm;
    final controls = route.stopSignCount + route.trafficSignalCount;
    final flowBonus = route.maxContinuousKm.clamp(0.0, 4.0) * 8;
    final curveBonus = (density * 100).clamp(0.0, 34.0);
    final mediumBonus = route.mediumCurveKm.clamp(0.0, 5.0) * 3.0;
    final tightBonus = route.tightCurveKm.clamp(0.0, 2.5) * 3.5;
    final loopBonus = route.isLoop ? 6.0 : 0.0;
    final nearbyBonus = route.distanceFromUser <= 8
        ? 7.0
        : route.distanceFromUser <= 22
        ? 3.0
        : -4.0;
    final lengthFit = route.distanceKm >= 10 && route.distanceKm <= 36
        ? 5.0
        : route.distanceKm < 6
        ? -6.0
        : -2.0;
    final interruptionPenalty = controls.clamp(0, 10) * 3.0;
    final roadPenalty =
        (route.isPrivateLike ? 12.0 : 0.0) +
        (route.isMajorRoadLike ? 8.0 : 0.0) +
        (route.isConnectorLike ? 10.0 : 0.0) +
        (route.isFacilityLike ? 6.0 : 0.0);
    final score =
        (42 +
                curveBonus +
                mediumBonus +
                tightBonus +
                flowBonus +
                loopBonus +
                nearbyBonus +
                lengthFit -
                interruptionPenalty -
                roadPenalty)
            .round()
            .clamp(0, 100);

    return WindingExperienceProfile(
      score: score,
      title: _title(score),
      rhythm: _rhythm(route, density),
      caution: _caution(route, controls),
      badges: _badges(route, density),
      metrics: [
        (label: 'Fun', value: '$score'),
        (label: 'Curves', value: '${curvyKm.toStringAsFixed(1)}km'),
        (label: 'Flow', value: '${route.maxContinuousKm.toStringAsFixed(1)}km'),
      ],
    );
  }
}

class RankedWindingRoute {
  final RevvRoute route;
  final WindingExperienceProfile profile;

  const RankedWindingRoute({required this.route, required this.profile});
}

List<RankedWindingRoute> rankWindingRoutes(List<RevvRoute> routes) {
  final ranked = routes
      .map(
        (route) => RankedWindingRoute(
          route: route,
          profile: WindingExperienceProfile.fromRoute(route),
        ),
      )
      .toList();
  ranked.sort((a, b) {
    final score = b.profile.score.compareTo(a.profile.score);
    if (score != 0) return score;
    final flow = b.route.maxContinuousKm.compareTo(a.route.maxContinuousKm);
    if (flow != 0) return flow;
    return a.route.distanceFromUser.compareTo(b.route.distanceFromUser);
  });
  return ranked;
}

String _title(int score) {
  if (score >= 82) return 'Prime winding';
  if (score >= 68) return 'Fun pick';
  if (score >= 52) return 'Easy rhythm';
  return 'Scout first';
}

String _rhythm(RevvRoute route, double density) {
  if (route.isLoop && route.maxContinuousKm >= 2.4) {
    return 'Loop rhythm with a long connected flow.';
  }
  if (route.tightCurveKm >= 1.2) {
    return 'Tight technical sections lead the drive.';
  }
  if (route.mediumCurveKm >= 2.0 || density >= 0.18) {
    return 'Sweepers and medium curves carry the pace.';
  }
  if (route.maxContinuousKm >= 2.0) {
    return 'Cleaner flow than curve density suggests.';
  }
  return 'Light curve rhythm, better as a quick scout.';
}

String _caution(RevvRoute route, int controls) {
  if (route.isPrivateLike) return 'Check access before committing.';
  if (route.isMajorRoadLike || route.isConnectorLike) {
    return 'Traffic and connector interruptions may break rhythm.';
  }
  if (controls >= 5) return 'Frequent interruptions may break flow.';
  if (route.distanceFromUser > 30) return 'Farther start; budget the transfer.';
  return 'Read road signs and surface before continuing.';
}

List<String> _badges(RevvRoute route, double density) {
  final badges = <String>[];
  if (route.isLoop) badges.add('Loop');
  if (route.distanceFromUser <= 8) badges.add('Nearby');
  if (route.maxContinuousKm >= 2.0) badges.add('Flow');
  if (density >= 0.18) badges.add('Curvy');
  if (route.tightCurveKm >= 1.2) badges.add('Technical');
  if (badges.isEmpty) badges.add('Scout');
  return badges;
}
