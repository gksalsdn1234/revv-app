int? routeCompletionPercent({
  required double drivenKm,
  required double? routeDistanceKm,
}) {
  if (routeDistanceKm == null || routeDistanceKm <= 0) return null;
  return (drivenKm / routeDistanceKm * 100).clamp(0.0, 999.0).round();
}
