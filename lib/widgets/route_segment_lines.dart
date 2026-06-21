import '../models/revv_route.dart';
import 'map_widget.dart';

List<RouteDifficultyLine> routeSegmentLinesForRoute(
  RevvRoute? route, {
  bool focusMode = false,
}) {
  if (route == null || route.chainSegments.isEmpty || route.nodes.length < 2) {
    return const [];
  }

  final lines = <RouteDifficultyLine>[];
  for (var i = 0; i < route.chainSegments.length; i++) {
    final segment = route.chainSegments[i];
    final start = segment.startNodeIndex.clamp(0, route.nodes.length - 1);
    final end = segment.endNodeIndex.clamp(0, route.nodes.length - 1);
    if (end <= start) continue;
    final points = route.nodes.sublist(start, end + 1);
    if (points.length < 2) continue;
    final connector = segment.kind == RouteSegmentKind.connector;
    lines.add(
      RouteDifficultyLine(
        routeId: '${route.id}:segment:$i',
        points: points,
        colorArgb: connector ? 0xFF95A3AF : 0xFFFFB020,
        width: connector ? (focusMode ? 4.2 : 3.0) : (focusMode ? 5.2 : 3.8),
        opacity: connector ? 0.74 : 0.90,
      ),
    );
  }
  return lines;
}
