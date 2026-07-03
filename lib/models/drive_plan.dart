import 'revv_route.dart';

enum DrivePlanLegKind {
  transit('transit'),
  winding('winding'),
  rest('rest');

  final String value;
  const DrivePlanLegKind(this.value);

  static DrivePlanLegKind fromJsonValue(String value) {
    return switch (value) {
      'winding' => DrivePlanLegKind.winding,
      'rest' => DrivePlanLegKind.rest,
      _ => DrivePlanLegKind.transit,
    };
  }
}

class DrivePlanRequest {
  final LatLng origin;
  final LatLng destination;
  final int windingBudgetMinutes;

  const DrivePlanRequest({
    required this.origin,
    required this.destination,
    required this.windingBudgetMinutes,
  });
}

class DrivePlanLeg {
  final DrivePlanLegKind kind;
  final List<LatLng> nodes;
  final double distanceKm;
  final int estimatedMinutes;
  final RevvRoute? route;

  const DrivePlanLeg({
    required this.kind,
    required this.nodes,
    required this.distanceKm,
    required this.estimatedMinutes,
    this.route,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.value,
    'nodes': nodes.map(_latLngToJson).toList(),
    'distanceKm': distanceKm,
    'estimatedMinutes': estimatedMinutes,
    if (route != null) 'route': route!.toJson(),
  };

  factory DrivePlanLeg.fromJson(Map<String, dynamic> json) {
    return DrivePlanLeg(
      kind: DrivePlanLegKind.fromJsonValue(json['kind']?.toString() ?? ''),
      nodes: _latLngListFromJson(json['nodes']),
      distanceKm: (json['distanceKm'] as num).toDouble(),
      estimatedMinutes: (json['estimatedMinutes'] as num).toInt(),
      route: json['route'] is Map<String, dynamic>
          ? RevvRoute.fromJson(json['route'] as Map<String, dynamic>)
          : null,
    );
  }
}

class DrivePlan {
  final List<DrivePlanLeg> legs;
  final int totalMinutes;
  final int windingMinutes;
  final int transitMinutes;
  final int restMinutes;
  final List<LatLng> waypoints;
  final int budgetShortfallMinutes;
  final bool usesApproximateTransit;

  const DrivePlan({
    required this.legs,
    required this.totalMinutes,
    required this.windingMinutes,
    required this.transitMinutes,
    this.restMinutes = 0,
    required this.waypoints,
    this.budgetShortfallMinutes = 0,
    this.usesApproximateTransit = false,
  });

  Map<String, dynamic> toJson() => {
    'legs': legs.map((leg) => leg.toJson()).toList(),
    'totalMinutes': totalMinutes,
    'windingMinutes': windingMinutes,
    'transitMinutes': transitMinutes,
    'restMinutes': restMinutes,
    'waypoints': waypoints.map(_latLngToJson).toList(),
    'budgetShortfallMinutes': budgetShortfallMinutes,
    'usesApproximateTransit': usesApproximateTransit,
  };

  factory DrivePlan.fromJson(Map<String, dynamic> json) {
    return DrivePlan(
      legs: ((json['legs'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DrivePlanLeg.fromJson)
          .toList(),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
      windingMinutes: (json['windingMinutes'] as num).toInt(),
      transitMinutes: (json['transitMinutes'] as num).toInt(),
      restMinutes: (json['restMinutes'] as num?)?.toInt() ?? 0,
      waypoints: _latLngListFromJson(json['waypoints']),
      budgetShortfallMinutes:
          (json['budgetShortfallMinutes'] as num?)?.toInt() ?? 0,
      usesApproximateTransit: json['usesApproximateTransit'] == true,
    );
  }
}

Map<String, dynamic> _latLngToJson(LatLng point) => {
  'lat': point.lat,
  'lng': point.lng,
};

List<LatLng> _latLngListFromJson(Object? raw) {
  return ((raw as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => LatLng(
          (item['lat'] as num).toDouble(),
          (item['lng'] as num).toDouble(),
        ),
      )
      .toList();
}
