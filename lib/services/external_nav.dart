import '../models/drive_plan.dart';
import '../models/revv_route.dart';

String googleMapsCoord(LatLng point) {
  return '${point.lat.toStringAsFixed(4)},${point.lng.toStringAsFixed(4)}';
}

Uri buildGoogleMapsAppUri({
  required LatLng origin,
  required LatLng destination,
  required List<LatLng> waypoints,
}) {
  // comgooglemapsurl://는 구글맵 앱에 "이 웹 URL을 열어라"로 전달되므로
  // Maps URLs API 규격(origin/destination/travelmode)을 써야 한다.
  // saddr/daddr는 구형 comgooglemaps:// 스킴 전용이라 여기선 무시되어
  // 출발·도착 없이 waypoints만 찍히는 깨진 경로가 됐다 (2026-07-12).
  return Uri(
    scheme: 'comgooglemapsurl',
    host: 'www.google.com',
    path: '/maps/dir/',
    queryParameters: {
      'api': '1',
      'origin': googleMapsCoord(origin),
      'destination': googleMapsCoord(destination),
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map(googleMapsCoord).join('|'),
      'travelmode': 'driving',
    },
  );
}

List<LatLng> selectHandoffWaypoints({required List<DrivePlanLeg> legs}) {
  final windingLegs = legs
      .where((leg) => leg.kind == DrivePlanLegKind.winding)
      .where((leg) => leg.nodes.length >= 2)
      .toList();
  if (windingLegs.isEmpty) return const [];

  final points = <LatLng>[];
  _addPoint(points, windingLegs.first.nodes.first);
  for (final leg in windingLegs.take(2)) {
    final middle = _middleNode(leg.nodes);
    if (middle != null) _addPoint(points, middle);
  }
  _addPoint(points, windingLegs.last.nodes.last);
  return points;
}

List<LatLng> selectRouteHandoffPoints(List<LatLng> nodes) {
  if (nodes.length <= 2) return nodes;
  final points = <LatLng>[nodes.first];
  for (final point in _routeMiddleNodes(nodes)) {
    _addPoint(points, point);
  }
  _addPoint(points, nodes.last);
  return points;
}

LatLng? _middleNode(List<LatLng> nodes) {
  if (nodes.length <= 2) return null;
  return nodes[nodes.length ~/ 2];
}

List<LatLng> _routeMiddleNodes(List<LatLng> nodes) {
  final middle = nodes.sublist(1, nodes.length - 1);
  if (middle.length <= 2) return middle;
  final firstIndex = (nodes.length / 3).round().clamp(1, nodes.length - 2);
  final secondIndex = ((nodes.length * 2) / 3).round().clamp(
    1,
    nodes.length - 2,
  );
  if (firstIndex == secondIndex) return [nodes[firstIndex]];
  return [nodes[firstIndex], nodes[secondIndex]];
}

void _addPoint(List<LatLng> points, LatLng point) {
  if (points.any((current) => _samePoint(current, point))) return;
  points.add(point);
}

bool _samePoint(LatLng a, LatLng b) => a.lat == b.lat && a.lng == b.lng;
