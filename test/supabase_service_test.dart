import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/supabase_config.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/route_feedback.dart';
import 'package:revv_app/models/run_telemetry_detail.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/services/drive_dynamics_tracker.dart';
import 'package:revv_app/services/supabase_service.dart';

void main() {
  test('SupabaseConfig instance defaults to disabled without dart-defines', () {
    final config = SupabaseConfig.instance;

    expect(config.isConfigured, isFalse);
    expect(config.url, isEmpty);
    expect(config.anonKey, isEmpty);
  });

  test('RunSummary serializes into Supabase run payload columns', () {
    final summary = RunSummary(
      id: 'run-1',
      date: DateTime.parse('2026-04-01T10:00:00Z'),
      distanceKm: 12.5,
      durationSeconds: 780,
      maxSpeedKmh: 88,
      avgSpeedKmh: 57,
      routeName: '북악 스카이웨이',
      routeId: 'route-9',
      weatherEmoji: '🌤',
      tempDisplay: '18°C',
      maxLateralG: 0.48,
      sharpCornersCount: 2,
      startPoint: const LatLng(37.0, 127.0),
      endPoint: const LatLng(37.1, 127.1),
    );

    final payload = SupabaseService.runSummaryToRow(summary, userId: 'user-1');

    expect(payload['id'], 'run-1');
    expect(payload['user_id'], 'user-1');
    expect(payload['route_name'], '북악 스카이웨이');
    expect(payload['route_id'], 'route-9');
    expect(payload['max_speed_kmh'], 88);
    expect(payload['avg_speed_kmh'], 57);
    expect(payload['start_lat'], 37.0);
    expect(payload['end_lng'], 127.1);
  });

  test('RunTelemetryDetail serializes into Supabase run_details payload', () {
    final detail = RunTelemetryDetail(
      runId: 'run-1',
      version: 1,
      routeSnapshot: const {'id': 'route-1', 'name': 'Loop'},
      samples: const [
        TelemetrySample(
          tMs: 0,
          lat: 45.0,
          lng: -73.0,
          speedKmh: 42,
          lateralG: 0.12,
          longitudinalG: 0.03,
          driveMode: 'cruise',
        ),
      ],
      sharpEvents: const [
        {'lat': 45.0, 'lng': -73.0, 'lateralG': 0.5},
      ],
      analytics: const {
        'revvScore': 91,
        'segments': [
          {'mode': 'winding', 'score': 0.87},
        ],
        'gBuckets': {'0.2': 4, '0.4': 2},
      },
      driveModeSeconds: const {'cruise': 12},
      weather: const {'emoji': '🌤', 'tempDisplay': '18°C'},
      createdAt: DateTime.parse('2026-04-01T10:00:00Z'),
    );

    final row = SupabaseService.runDetailToRow(detail, userId: 'user-1');
    final restored = SupabaseService.runDetailFromRow(row);

    expect(row['run_id'], 'run-1');
    expect(row['user_id'], 'user-1');
    expect(row['detail_version'], 1);
    expect(row['telemetry_json'], isA<Map<String, dynamic>>());
    expect(restored.samples.single.speedKmh, 42);
    expect(restored.analytics['segments'], [
      {'mode': 'winding', 'score': 0.87},
    ]);
    expect(restored.analytics['gBuckets'], {'0.2': 4, '0.4': 2});
    expect(restored.weather['tempDisplay'], '18°C');
  });

  test(
    'DriveDynamicsSummary serializes into Supabase telemetry_summary payload',
    () {
      const summary = DriveDynamicsSummary(
        hardBrakeCount: 1,
        harshSteerCount: 2,
        smoothRatio: 0.92,
        p95LateralG: 0.42,
        sampleSeconds: 480,
      );

      final row = SupabaseService.telemetrySummaryToRow(
        'run-1',
        summary,
        userId: 'user-1',
      );

      expect(row, {
        'run_id': 'run-1',
        'user_id': 'user-1',
        'hard_brake_count': 1,
        'harsh_steer_count': 2,
        'smooth_ratio': 0.92,
        'p95_lateral_g': 0.42,
        'sample_seconds': 480,
        'detail_version': 'v1',
      });
      expect(row.keys, isNot(contains('telemetry_json')));
      expect(row.keys, isNot(contains('gps_path')));
    },
  );

  test('RouteFeedback serializes into Supabase route_feedback payload', () {
    final feedback = RouteFeedback(
      id: 'run-1_liked',
      runId: 'run-1',
      routeId: 'route-1',
      routeName: 'Mountain Sweep',
      feedbackType: 'liked',
      createdAt: DateTime.parse('2026-04-01T10:03:00Z'),
    );

    final row = SupabaseService.routeFeedbackToRow(feedback, userId: 'user-1');

    expect(row['id'], 'run-1_liked');
    expect(row['user_id'], 'user-1');
    expect(row['run_id'], 'run-1');
    expect(row['route_id'], 'route-1');
    expect(row['feedback_type'], 'liked');
  });

  test('Route rows map back into RevvRoute models', () {
    final route = SupabaseService.routeFromRow({
      'id': 'route-1',
      'name': 'Mountain Sweep',
      'nodes': [
        {'lat': 45.0, 'lng': -73.0},
        {'lat': 45.1, 'lng': -73.1},
      ],
      'distance_km': 18.4,
      'winding_score': 6.3,
      'star_rating': 4,
      'sharp_curve_count': 11,
      'elevation_delta': 86.5,
      'center_lat': 45.05,
      'center_lng': -73.05,
      'distance_from_user_km': 12.0,
      'route_rank_score': 8.9,
      'fun_score': 9.4,
      'flow_score': 0.84,
      'driveability_penalty': 0.72,
      'stop_sign_count': 2,
      'traffic_signal_count': 1,
      'stop_control_density': 0.19,
      'road_class_bucket': 'rural_named',
      'is_named': true,
      'is_facility_like': false,
      'is_bridge_like': false,
      'is_connector_like': false,
      'is_major_road_like': false,
      'is_private_like': false,
      'tight_curve_km': 3.1,
      'medium_curve_km': 4.4,
      'max_continuous_km': 1.8,
      'is_loop': true,
      'elevation_profile': [10, 24, 18],
      'road_names': ['Chemin du Lac', 'North Ridge'],
      'surface_summary': 'asphalt',
      'speed_limit_summary': '50',
      'nearby_pois': [
        {'name': 'Belvédère Nord', 'category': 'viewpoint'},
      ],
      'run_count': 7,
      'published_by': 'user-1',
      'is_generated': true,
      'activated_at': '2026-07-16T04:30:00Z',
      'province_code': 'AB',
      'catalog_epoch': 9,
    });

    expect(route.id, 'route-1');
    expect(route.nodes, hasLength(2));
    expect(route.isLoop, isTrue);
    expect(route.curveStyle, isNotEmpty);
    expect(route.routeRankScore, 8.9);
    expect(route.funScore, 9.4);
    expect(route.flowScore, 0.84);
    expect(route.driveabilityPenalty, 0.72);
    expect(route.stopSignCount, 2);
    expect(route.trafficSignalCount, 1);
    expect(route.elevationDelta, 86.5);
    expect(route.elevationProfile, [10, 24, 18]);
    expect(route.roadNames, ['Chemin du Lac', 'North Ridge']);
    expect(route.surfaceSummary, 'asphalt');
    expect(route.speedLimitSummary, '50');
    expect(route.nearbyPoiNames, ['Belvédère Nord']);
    expect(route.runCount, 7);
    expect(route.publishedBy, 'user-1');
    expect(route.isGenerated, isTrue);
    expect(route.activatedAt, DateTime.utc(2026, 7, 16, 4, 30));
    expect(route.provinceCode, 'AB');
    expect(route.catalogEpoch, 9);
  });

  test('Route rows cap and validate geometry before map rendering', () {
    final nodes = List.generate(5000, (index) {
      if (index == 2500) return {'lat': double.infinity, 'lng': -73.0};
      return {'lat': 45.0 + (index / 100000), 'lng': -73.0 - (index / 100000)};
    });

    final route = SupabaseService.routeFromRow({
      'id': 'oversized-route',
      'name': 'Oversized Route',
      'nodes': nodes,
    });

    expect(route.nodes.length, lessThanOrEqualTo(1200));
    expect(route.nodes.every((point) => point.lat.isFinite), isTrue);
    expect(route.nodes.first.lat, 45);
    expect(route.nodes.first.lng, -73);
    expect(route.nodes.last.lat, closeTo(45.04999, 0.00001));
  });

  test(
    'Route rows derive distance when rpc payload omits distance_from_user_km',
    () {
      final route = SupabaseService.routeFromRow(
        {
          'id': 'route-2',
          'name': 'North Ridge',
          'nodes': [
            {'lat': 45.46, 'lng': -73.62},
            {'lat': 45.49, 'lng': -73.68},
          ],
          'distance_km': 11.2,
          'winding_score': 5.8,
          'star_rating': 4,
          'sharp_curve_count': 8,
          'center_lat': 45.49,
          'center_lng': -73.68,
        },
        userLat: 45.4627,
        userLng: -73.6266,
      );

      expect(route.distanceFromUser, greaterThan(0));
    },
  );

  test('route payload only uses columns present in curvy_roads schema', () {
    final payload = SupabaseService.routeToRow(
      const RevvRoute(
        id: 'route-1',
        name: 'Mountain Sweep',
        nodes: [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
        distanceKm: 18.4,
        windingScore: 6.3,
        starRating: 4,
        sharpCurveCount: 11,
        centerPoint: LatLng(45.05, -73.05),
        distanceFromUser: 12.0,
        tightCurveKm: 3.1,
        mediumCurveKm: 4.4,
        maxContinuousKm: 1.8,
        isLoop: true,
        routeRankScore: 9.1,
        funScore: 9.8,
        flowScore: 0.88,
        driveabilityPenalty: 0.91,
        stopSignCount: 1,
        trafficSignalCount: 0,
        stopControlDensity: 0.08,
        roadClassBucket: 'rural_named',
        roadNames: ['Chemin du Lac'],
        surfaceSummary: 'asphalt',
        speedLimitSummary: '50',
        nearbyPoiNames: ['Belvédère Nord'],
        elevationProfile: [10, 24, 18],
        isNamed: true,
        runCount: 7,
        publishedBy: 'user-1',
      ),
    );

    expect(payload.containsKey('distance_from_user_km'), isFalse);
    expect(payload['curvature_score'], 6.3);
    expect(payload['sharp_curve_count'], 11);
    expect(payload['route_rank_score'], 9.1);
    expect(payload['flow_score'], 0.88);
    expect(payload['stop_sign_count'], 1);
    expect(payload['road_class_bucket'], 'rural_named');
    expect(payload['road_names'], ['Chemin du Lac']);
    expect(payload['surface_summary'], 'asphalt');
    expect(payload['speed_limit_summary'], '50');
    expect(payload['nearby_pois'], [
      {'name': 'Belvédère Nord', 'category': 'saved'},
    ]);
    expect(payload['elevation_profile'], [10, 24, 18]);
    expect(payload['run_count'], 7);
  });

  test(
    'discovered route cache rows are scoped to a user and stored as json',
    () {
      final row = SupabaseService.discoveredRouteCacheRow(
        const RevvRoute(
          id: 'route-1',
          name: 'Mountain Sweep',
          nodes: [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
          distanceKm: 18.4,
          windingScore: 6.3,
          starRating: 4,
          sharpCurveCount: 11,
          centerPoint: LatLng(45.05, -73.05),
          distanceFromUser: 12.0,
          tightCurveKm: 3.1,
          mediumCurveKm: 4.4,
          maxContinuousKm: 1.8,
          isLoop: true,
          runCount: 7,
        ),
        userId: 'user-1',
      );

      expect(row['user_id'], 'user-1');
      expect(row['route_id'], 'route-1');
      expect(row['route_data'], isA<Map<String, dynamic>>());
    },
  );

  test(
    'recordRouteRun uses rpc payload instead of read-then-write increment',
    () {
      final payload = SupabaseService.recordRouteRunRpcParams(
        'route-1',
        'run-1',
      );

      expect(payload, {'route_id_input': 'route-1', 'run_id_input': 'run-1'});
    },
  );

  test('explored cell rows contain no ordered GPS or telemetry fields', () {
    final rows = SupabaseService.exploredCellRows({
      'f25dvk1': DateTime.utc(2026, 7, 12, 20),
    }, userId: 'user-1');

    expect(rows, [
      {
        'user_id': 'user-1',
        'cell_id': 'f25dvk1',
        'explored_at': '2026-07-12T20:00:00.000Z',
      },
    ]);
    expect(
      rows.single.keys,
      unorderedEquals(['user_id', 'cell_id', 'explored_at']),
    );
  });
}
