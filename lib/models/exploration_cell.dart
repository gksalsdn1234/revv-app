import 'dart:math' as math;

import 'revv_route.dart';

class ExplorationCellBounds {
  const ExplorationCellBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  bool contains(LatLng point) =>
      point.lat >= minLat &&
      point.lat <= maxLat &&
      point.lng >= minLng &&
      point.lng <= maxLng;

  List<LatLng> get polygon => [
    LatLng(minLat, minLng),
    LatLng(minLat, maxLng),
    LatLng(maxLat, maxLng),
    LatLng(maxLat, minLng),
    LatLng(minLat, minLng),
  ];
}

class ExplorationCell {
  const ExplorationCell({required this.id, required this.bounds});

  final String id;
  final ExplorationCellBounds bounds;

  factory ExplorationCell.fromPoint(LatLng point) {
    final id = RevvRoute.encodeGeohash(
      point.lat,
      point.lng,
      ExplorationGrid.precision,
    );
    return ExplorationCell(id: id, bounds: ExplorationGrid.decodeBounds(id));
  }
}

class ExplorationGrid {
  ExplorationGrid._();

  static const int precision = 7;
  static const double interpolationKm = 0.075;
  static const String _alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

  static List<String> cellsForPath(List<LatLng> path) {
    if (path.isEmpty) return const [];
    final ordered = <String>[];
    final seen = <String>{};

    void addPoint(LatLng point) {
      final id = RevvRoute.encodeGeohash(point.lat, point.lng, precision);
      if (seen.add(id)) ordered.add(id);
    }

    addPoint(path.first);
    for (var index = 1; index < path.length; index++) {
      final start = path[index - 1];
      final end = path[index];
      final distanceKm = RevvRoute.haversineKm(start, end);
      final steps = math.max(1, (distanceKm / interpolationKm).ceil());
      for (var step = 1; step <= steps; step++) {
        final fraction = step / steps;
        addPoint(
          LatLng(
            start.lat + ((end.lat - start.lat) * fraction),
            start.lng + ((end.lng - start.lng) * fraction),
          ),
        );
      }
    }
    return ordered;
  }

  static ExplorationCellBounds decodeBounds(String id) {
    if (id.isEmpty) throw const FormatException('Empty exploration cell id');
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLng = -180.0;
    var maxLng = 180.0;
    var longitudeBit = true;

    for (final codeUnit in id.codeUnits) {
      final value = _alphabet.indexOf(String.fromCharCode(codeUnit));
      if (value < 0) throw FormatException('Invalid exploration cell id: $id');
      for (var mask = 16; mask != 0; mask >>= 1) {
        final upperHalf = value & mask != 0;
        if (longitudeBit) {
          final mid = (minLng + maxLng) / 2;
          if (upperHalf) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if (upperHalf) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        longitudeBit = !longitudeBit;
      }
    }

    return ExplorationCellBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }
}
