import 'dart:io' show Platform;
import 'dart:math' as math;

import '../models/drive_plan.dart';
import '../models/revv_route.dart';

typedef ExternalNavigationLauncher = Future<bool> Function(Uri uri);

Future<bool> launchExternalNavigationWithFallback({
  required Uri primaryUri,
  Uri? fallbackUri,
  required ExternalNavigationLauncher launcher,
}) async {
  try {
    if (await launcher(primaryUri)) return true;
  } catch (_) {}
  if (fallbackUri == null || fallbackUri == primaryUri) return false;
  try {
    return await launcher(fallbackUri);
  } catch (_) {
    return false;
  }
}

String googleMapsCoord(LatLng point) {
  return '${point.lat.toStringAsFixed(5)},${point.lng.toStringAsFixed(5)}';
}

Uri buildGoogleMapsDirectionsUri({
  LatLng? origin,
  required LatLng destination,
  required List<LatLng> waypoints,
}) {
  return Uri.https(
    'www.google.com',
    '/maps/dir/',
    _googleMapsDirectionsParameters(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    ),
  );
}

/// Opens the installed Google Maps app with the Maps URLs API parameters.
///
/// `comgooglemapsurl://` wraps the same Maps URL as the web fallback, so it
/// needs `origin`/`destination` rather than legacy `saddr`/`daddr` keys.
String googleMapsCoord(LatLng point) {
  return '${point.lat.toStringAsFixed(6)},${point.lng.toStringAsFixed(6)}';
}

Uri buildGoogleMapsAppUri({
  LatLng? origin,
  required LatLng destination,
  required List<LatLng> waypoints,
  bool? isIOS,
}) {
  final queryParameters = {
    'api': '1',
    if (origin != null) 'origin': googleMapsCoord(origin),
    'destination': googleMapsCoord(destination),
    if (waypoints.isNotEmpty)
      'waypoints': waypoints.map(googleMapsCoord).join('|'),
    'travelmode': 'driving',
  };

  if (!(isIOS ?? Platform.isIOS)) {
    return Uri.https('www.google.com', '/maps/dir/', queryParameters);
  }

  // comgooglemapsurl://는 구글맵 앱에 "이 웹 URL을 열어라"로 전달되므로
  // Maps URLs API 규격(origin/destination/travelmode)을 써야 한다.
  // saddr/daddr는 구형 comgooglemaps:// 스킴 전용이라 여기선 무시되어
  // 출발·도착 없이 waypoints만 찍히는 깨진 경로가 됐다 (2026-07-12).
  return Uri(
    scheme: 'comgooglemapsurl',
    host: 'www.google.com',
    path: '/maps/dir/',
    queryParameters: _googleMapsDirectionsParameters(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    ),
    queryParameters: queryParameters,
  );
}

Map<String, String> _googleMapsDirectionsParameters({
  required LatLng? origin,
  required LatLng destination,
  required List<LatLng> waypoints,
}) {
  return {
    'api': '1',
    if (origin != null) 'origin': googleMapsCoord(origin),
    'destination': googleMapsCoord(destination),
    if (waypoints.isNotEmpty)
      'waypoints': waypoints.map(googleMapsCoord).join('|'),
    'travelmode': 'driving',
  };
}

List<LatLng> selectHandoffWaypoints({
  required List<DrivePlanLeg> legs,
  required LatLng origin,
  required LatLng destination,
}) {
  final windingLegs = legs
      .where((leg) => leg.kind == DrivePlanLegKind.winding)
      .where((leg) => leg.nodes.length >= 2)
      .toList();
  if (windingLegs.isEmpty) return const [];

  final candidates = <LatLng>[];
  for (var index = 0; index < windingLegs.length; index++) {
    final leg = windingLegs[index];
    final anchor =
        _middleNode(leg.nodes) ??
        (index == 0 ? leg.nodes.last : leg.nodes.first);
    if (!_samePoint(anchor, origin) && !_samePoint(anchor, destination)) {
      _addPoint(candidates, anchor);
    }
  }
  if (candidates.length <= 3) return candidates;
  return [
    candidates.first,
    candidates[candidates.length ~/ 2],
    candidates.last,
  ];
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
  return nodes[smoothestIndexNear(nodes, nodes.length ~/ 2)];
}

List<LatLng> _routeMiddleNodes(List<LatLng> nodes) {
  final middle = nodes.sublist(1, nodes.length - 1);
  if (middle.length <= 2) return middle;
  final firstIndex = smoothestIndexNear(nodes, (nodes.length / 3).round());
  final secondIndex = smoothestIndexNear(
    nodes,
    ((nodes.length * 2) / 3).round(),
  );
  if (firstIndex == secondIndex) return [nodes[firstIndex]];
  return [nodes[firstIndex], nodes[secondIndex]];
}

/// 앵커 주변 창에서 국소 방향 변화가 가장 작은(가장 직선인) 노드를 고른다.
/// 외부 내비가 경유지를 도로에 스냅할 때 교차로·헤어핀 꼭짓점에 찍히면
/// 옆길로 들어갔다 나오는 스퍼가 생기므로, 직선 구간의 점으로 옮겨 찍는다.
/// 동률이면 앵커를 유지해 직선 폴리라인에서는 기존 선택과 동일하다.
int smoothestIndexNear(List<LatLng> nodes, int anchor, {int? window}) {
  final lastInner = nodes.length - 2;
  if (lastInner < 1) return anchor.clamp(0, nodes.length - 1);
  final base = anchor.clamp(1, lastInner);
  final w = window ?? math.max(2, nodes.length ~/ 10);
  var best = base;
  var bestTurn = _turnAtDeg(nodes, base);
  for (var i = math.max(1, base - w); i <= math.min(lastInner, base + w); i++) {
    final turn = _turnAtDeg(nodes, i);
    if (turn < bestTurn) {
      bestTurn = turn;
      best = i;
    }
  }
  return best;
}

double _turnAtDeg(List<LatLng> nodes, int i) {
  final before = _bearingDeg(nodes[i - 1], nodes[i]);
  final after = _bearingDeg(nodes[i], nodes[i + 1]);
  var diff = (after - before).abs();
  if (diff > 180) diff = 360 - diff;
  return diff;
}

double _bearingDeg(LatLng a, LatLng b) {
  final lat1 = a.lat * math.pi / 180;
  final lat2 = b.lat * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return math.atan2(y, x) * 180 / math.pi;
}

void _addPoint(List<LatLng> points, LatLng point) {
  if (points.any((current) => _samePoint(current, point))) return;
  points.add(point);
}

bool _samePoint(LatLng a, LatLng b) => googleMapsCoord(a) == googleMapsCoord(b);
