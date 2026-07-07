import '../models/revv_route.dart';

String googleMapsCoord(LatLng point) {
  return '${point.lat.toStringAsFixed(4)},${point.lng.toStringAsFixed(4)}';
}

Uri buildGoogleMapsAppUri({
  required LatLng origin,
  required LatLng destination,
  required List<LatLng> waypoints,
}) {
  return Uri(
    scheme: 'comgooglemapsurl',
    host: 'www.google.com',
    path: '/maps/dir/',
    queryParameters: {
      'api': '1',
      'saddr': googleMapsCoord(origin),
      'daddr': googleMapsCoord(destination),
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map(googleMapsCoord).join('|'),
      'directionsmode': 'driving',
    },
  );
}
