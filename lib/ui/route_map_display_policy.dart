import '../models/revv_route.dart';

List<RevvRoute> routeFinderMapDisplayRoutes({
  required List<RevvRoute> mapVisualRoutes,
  required List<RevvRoute> visibleRoutes,
}) {
  return mapVisualRoutes.isNotEmpty ? mapVisualRoutes : visibleRoutes;
}
