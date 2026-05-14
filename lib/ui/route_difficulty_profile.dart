import '../models/revv_route.dart';

enum RouteDifficultyLevel { muted, gentle, winding, tight }

class RouteDifficultyProfile {
  final RouteDifficultyLevel difficulty;
  final String label;
  final int colorArgb;
  final int score;
  final double opacity;
  final double lineWidth;

  const RouteDifficultyProfile({
    required this.difficulty,
    required this.label,
    required this.colorArgb,
    required this.score,
    required this.opacity,
    required this.lineWidth,
  });

  factory RouteDifficultyProfile.fromRoute(RevvRoute route) {
    final distance = route.distanceKm <= 0 ? 1.0 : route.distanceKm;
    final curvatureDensity =
        ((route.tightCurveKm * 1.8) + route.mediumCurveKm) / distance;
    final tightRatio = route.tightCurveKm / distance;
    final hardRisk =
        route.isFacilityLike ||
        route.isPrivateLike ||
        route.isConnectorLike ||
        route.qualityRejectReason != null;
    final softRisk = route.isMajorRoadLike || route.isBridgeLike;

    if (hardRisk) {
      return const RouteDifficultyProfile(
        difficulty: RouteDifficultyLevel.muted,
        label: '참고',
        colorArgb: 0xFF8A9499,
        score: 20,
        opacity: 0.24,
        lineWidth: 1.2,
      );
    }

    final rawScore = ((curvatureDensity * 70) + (tightRatio * 90))
        .round()
        .clamp(0, 100);

    // The source data marks generous curve spans, so red must be reserved for
    // the genuinely dense/tight end of the field. Otherwise every good road
    // becomes "tight" and the map loses its visual gradient.
    if (tightRatio >= 0.32 || curvatureDensity >= 0.72) {
      return RouteDifficultyProfile(
        difficulty: RouteDifficultyLevel.tight,
        label: '타이트',
        colorArgb: 0xFFFF2E38,
        score: rawScore,
        opacity: softRisk ? 0.58 : 0.92,
        lineWidth: 2.2,
      );
    }

    if (curvatureDensity >= 0.34 || tightRatio >= 0.14) {
      return RouteDifficultyProfile(
        difficulty: RouteDifficultyLevel.winding,
        label: '와인딩',
        colorArgb: 0xFFFF7A1A,
        score: rawScore,
        opacity: softRisk ? 0.48 : 0.84,
        lineWidth: 2.0,
      );
    }

    if (curvatureDensity >= 0.08 ||
        route.tightCurveKm + route.mediumCurveKm >= 0.8) {
      return RouteDifficultyProfile(
        difficulty: RouteDifficultyLevel.gentle,
        label: '완만',
        colorArgb: 0xFFFFE94A,
        score: rawScore,
        opacity: softRisk ? 0.40 : 0.74,
        lineWidth: 1.7,
      );
    }

    return RouteDifficultyProfile(
      difficulty: RouteDifficultyLevel.muted,
      label: '참고',
      colorArgb: 0xFF8A9499,
      score: rawScore,
      opacity: 0.22,
      lineWidth: 1.1,
    );
  }
}
