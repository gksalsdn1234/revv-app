import '../models/revv_route.dart';

class ElevationService {
  Future<List<double>> fetchElevation(String routeId, List<LatLng> nodes) async {
    if (nodes.length < 2) return const [];
    final base = 120.0;
    return List<double>.generate(
      nodes.length,
      (i) => base + (i % 7) * 6.0,
      growable: false,
    );
  }
}
