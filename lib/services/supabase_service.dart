import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../core/supabase_config.dart';
import '../core/supabase_tables.dart';
import '../models/revv_route.dart';
import '../models/run_summary.dart';
import 'route_loading_policy.dart';

enum SyncStatus { idle, syncing, done, error }

class SupabaseService extends ChangeNotifier {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  SupabaseConfig? _config;
  bool _initialized = false;
  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;
  String? _lastFailureReason;
  String? get lastFailureReason => _lastFailureReason;

  bool _ready = false;
  bool get isReady => _ready;
  bool get isCloudAvailable => _ready && uid != null;
  String get availabilityLabel {
    if (_ready) return '클라우드 연결됨';
    if (_status == SyncStatus.error) return '클라우드 연결 실패';
    return '클라우드 비활성';
  }

  String? get uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> init({SupabaseConfig? config}) async {
    if (_initialized) return;
    _initialized = true;
    _config ??= config ?? SupabaseConfig.instance;
    if (!_config!.isConfigured) {
      _ready = false;
      _lastFailureReason = 'Supabase 설정이 없어 클라우드 기능을 비활성화했어요.';
      _setStatus(SyncStatus.idle);
      debugPrint('[Supabase] configuration missing; cloud features disabled');
      return;
    }

    try {
      await Supabase.initialize(url: _config!.url, anonKey: _config!.anonKey);
      final auth = Supabase.instance.client.auth;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      _ready = true;
      _lastFailureReason = null;
      _setStatus(SyncStatus.done);
      debugPrint('[Supabase] initialized — uid: $uid');
    } catch (e) {
      _ready = false;
      _lastFailureReason = '$e';
      _setStatus(SyncStatus.error);
      debugPrint('[Supabase] init failed: $e');
    }
    notifyListeners();
  }

  Future<void> uploadRun(RunSummary summary) async {
    if (!_ready || uid == null) return;
    try {
      await client!
          .from(SupabaseTables.runs)
          .upsert(runSummaryToRow(summary, userId: uid!), onConflict: 'id');
      debugPrint('[Supabase] run uploaded — ${summary.id}');
    } catch (e) {
      debugPrint('[Supabase] uploadRun failed: $e');
    }
  }

  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds) async {
    if (!_ready || uid == null) return const [];
    _setStatus(SyncStatus.syncing);
    try {
      final rows = await client!
          .from(SupabaseTables.runs)
          .select()
          .eq('user_id', uid!)
          .order('date', ascending: false)
          .limit(200);
      final missing = (rows as List)
          .whereType<Map<String, dynamic>>()
          .where((row) => !localIds.contains(row['id'] as String? ?? ''))
          .map(runSummaryFromRow)
          .toList();
      _setStatus(SyncStatus.done);
      return missing;
    } catch (e) {
      debugPrint('[Supabase] fetchMissingRuns failed: $e');
      _setStatus(SyncStatus.error);
      return const [];
    }
  }

  Future<Set<String>> fetchRunIds() async {
    if (!_ready || uid == null) return const {};
    try {
      final rows = await client!
          .from(SupabaseTables.runs)
          .select('id')
          .eq('user_id', uid!);
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('[Supabase] fetchRunIds failed: $e');
      return const {};
    }
  }

  Future<void> uploadAll(List<RunSummary> runs) async {
    if (!_ready || uid == null || runs.isEmpty) return;
    _setStatus(SyncStatus.syncing);
    try {
      await client!
          .from(SupabaseTables.runs)
          .upsert(
            runs.map((r) => runSummaryToRow(r, userId: uid!)).toList(),
            onConflict: 'id',
          );
      _setStatus(SyncStatus.done);
      debugPrint('[Supabase] bulk upload ${runs.length} runs');
    } catch (e) {
      debugPrint('[Supabase] uploadAll failed: $e');
      _setStatus(SyncStatus.error);
    }
  }

  Future<void> saveDiscoveredRoutes(List<RevvRoute> routes) async {
    if (!_ready || uid == null || routes.isEmpty) return;
    try {
      await client!
          .from(SupabaseTables.discoveredRoutes)
          .upsert(
            routes
                .map((route) => discoveredRouteCacheRow(route, userId: uid!))
                .toList(),
            onConflict: 'user_id,route_id',
          );
      debugPrint('[Supabase] route pool saved — ${routes.length}');
    } catch (e) {
      debugPrint('[Supabase] saveDiscoveredRoutes failed: $e');
    }
  }

  Future<List<RevvRoute>> loadDiscoveredRoutes() async {
    if (!_ready || uid == null) return const [];
    try {
      final rows = await client!
          .from(SupabaseTables.discoveredRoutes)
          .select('route_data')
          .eq('user_id', uid!)
          .order('saved_at', ascending: false)
          .limit(25);
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => row['route_data'])
          .whereType<Map<String, dynamic>>()
          .map(routeFromRow)
          .toList();
    } catch (e) {
      debugPrint('[Supabase] loadDiscoveredRoutes failed: $e');
      return const [];
    }
  }

  Future<void> publishRoute(RevvRoute route) async {
    if (!_ready) return;
    debugPrint(
      '[Supabase] publishRoute skipped: curvy_roads is canonical read-only',
    );
  }

  Future<List<RevvRoute>> fetchNearbyRoutes(
    double lat,
    double lng,
    double radiusKm,
  ) async {
    return findCurvyRoads(
      lat: lat,
      lng: lng,
      radiusM: (radiusKm * 1000).round(),
      maxResults: 200,
    );
  }

  Future<List<RevvRoute>> fetchNearbyRoutesDirect(
    double lat,
    double lng,
    double radiusKm, {
    int limit = 200,
  }) async {
    if (!_ready) return const [];
    try {
      final latDelta = radiusKm / 111.0;
      final lngScale = cos(_toRadians(lat)).abs().clamp(0.2, 1.0);
      final lngDelta = radiusKm / (111.0 * lngScale);

      final rows = await client!
          .from(SupabaseTables.curvyRoads)
          .select()
          .gte('center_lat', lat - latDelta)
          .lte('center_lat', lat + latDelta)
          .gte('center_lng', lng - lngDelta)
          .lte('center_lng', lng + lngDelta)
          .gte('distance_km', 4.0)
          .order('winding_score', ascending: false)
          .order('run_count', ascending: false)
          .limit(limit);

      final routes =
          (rows as List)
              .whereType<Map<String, dynamic>>()
              .map((row) => routeFromRow(row, userLat: lat, userLng: lng))
              .where((route) => route.distanceFromUser <= radiusKm * 1.35)
              .toList()
            ..sort((a, b) {
              final scoreDiff = b.windingScore.compareTo(a.windingScore);
              if (scoreDiff != 0) return scoreDiff;
              return a.distanceFromUser.compareTo(b.distanceFromUser);
            });

      debugPrint(
        '[Supabase] direct nearby fallback: ${routes.length} rows '
        '(lat=${lat.toStringAsFixed(4)}, lng=${lng.toStringAsFixed(4)}, r=${radiusKm.toStringAsFixed(0)}km)',
      );
      return routes;
    } catch (e) {
      debugPrint('[Supabase] fetchNearbyRoutesDirect failed: $e');
      return const [];
    }
  }

  Future<List<RevvRoute>> findCurvyRoads({
    required double lat,
    required double lng,
    required int radiusM,
    double minScore = 0,
    int maxResults = 30,
  }) async {
    if (!_ready) return const [];
    try {
      final rows = await client!.rpc(
        'find_curvy_roads',
        params: {
          'user_lat': lat,
          'user_lng': lng,
          'radius_m': radiusM,
          'min_score': minScore,
          'max_results': maxResults,
        },
      );
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => routeFromRow(row, userLat: lat, userLng: lng))
          .toList();
    } catch (e) {
      debugPrint('[Supabase] findCurvyRoads failed: $e');
      return const [];
    }
  }

  Future<List<LatLng>> fetchRouteNodes(String routeId) async {
    if (!_ready) return const [];
    try {
      final row = await client!
          .from(SupabaseTables.curvyRoads)
          .select('nodes')
          .eq('id', routeId)
          .maybeSingle();
      final nodes = (row?['nodes'] as List?) ?? const [];
      return nodes
          .whereType<Map<String, dynamic>>()
          .map(
            (n) => LatLng(
              (n['lat'] as num).toDouble(),
              (n['lng'] as num).toDouble(),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('[Supabase] fetchRouteNodes failed: $e');
      return const [];
    }
  }

  Future<void> recordRouteRun(String? routeId) async {
    if (!_ready || routeId == null) return;
    try {
      await client!.rpc(
        'increment_route_run_count',
        params: recordRouteRunRpcParams(routeId),
      );
    } catch (e) {
      debugPrint('[Supabase] recordRouteRun failed: $e');
    }
  }

  Future<Map<String, Map<String, dynamic>>> fetchRouteRecords() async {
    if (!_ready || uid == null) return const {};
    try {
      final rows = await client!
          .from(SupabaseTables.routeRecords)
          .select()
          .eq('user_id', uid!);
      final map = <String, Map<String, dynamic>>{};
      for (final row in rows as List) {
        if (row is Map<String, dynamic>) {
          final routeId = row['route_id'] as String?;
          if (routeId != null) {
            map[routeId] = row;
          }
        }
      }
      return map;
    } catch (e) {
      debugPrint('[Supabase] fetchRouteRecords failed: $e');
      return const {};
    }
  }

  Future<void> upsertRouteRecord({
    required String routeId,
    required int bestTimeSeconds,
    required double bestMaxG,
    required int runCount,
    required DateTime lastRunAt,
  }) async {
    if (!_ready || uid == null) return;
    try {
      await client!.from(SupabaseTables.routeRecords).upsert({
        'user_id': uid!,
        'route_id': routeId,
        'best_time_seconds': bestTimeSeconds,
        'best_max_g': bestMaxG,
        'run_count': runCount,
        'last_run_at': lastRunAt.toIso8601String(),
      }, onConflict: 'user_id,route_id');
    } catch (e) {
      debugPrint('[Supabase] upsertRouteRecord failed: $e');
    }
  }

  Future<List<RevvRoute>> fetchTopRoutes({int limit = 20}) async {
    if (!_ready) return const [];
    try {
      final rows = await client!
          .from(SupabaseTables.curvyRoads)
          .select()
          .order('run_count', ascending: false)
          .order('winding_score', ascending: false)
          .limit(limit);
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(routeFromRow)
          .toList();
    } catch (e) {
      debugPrint('[Supabase] fetchTopRoutes failed: $e');
      return const [];
    }
  }

  Future<List<RevvRoute>> loadSavedRoutes() async {
    if (!_ready || uid == null) return const [];
    try {
      final rows = await client!
          .from(SupabaseTables.savedRoutes)
          .select('route_data')
          .eq('user_id', uid!)
          .order('saved_at', ascending: false);
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => row['route_data'])
          .whereType<Map<String, dynamic>>()
          .map(routeFromRow)
          .toList();
    } catch (e) {
      debugPrint('[Supabase] loadSavedRoutes failed: $e');
      return const [];
    }
  }

  Future<void> saveRouteBookmark(RevvRoute route, {required bool saved}) async {
    if (!_ready || uid == null) return;
    try {
      if (saved) {
        final enrichedRoute = hydrateRouteMetadata(route);
        await client!.from(SupabaseTables.savedRoutes).upsert({
          'user_id': uid!,
          'route_id': enrichedRoute.id,
          'route_data': routeToRow(enrichedRoute),
          'saved_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,route_id');
      } else {
        await client!
            .from(SupabaseTables.savedRoutes)
            .delete()
            .eq('user_id', uid!)
            .eq('route_id', route.id);
      }
    } catch (e) {
      debugPrint('[Supabase] saveRouteBookmark failed: $e');
    }
  }

  static Map<String, dynamic> runSummaryToRow(
    RunSummary summary, {
    required String userId,
  }) {
    return {
      'id': summary.id,
      'user_id': userId,
      'date': summary.date.toIso8601String(),
      'distance_km': summary.distanceKm,
      'duration_seconds': summary.durationSeconds,
      'route_name': summary.routeName,
      'route_id': summary.routeId,
      'weather_emoji': summary.weatherEmoji,
      'temp_display': summary.tempDisplay,
      if (summary.maxLateralG != null) 'max_lateral_g': summary.maxLateralG,
      if (summary.sharpCornersCount > 0)
        'sharp_corners_count': summary.sharpCornersCount,
      if (summary.startPoint != null) 'start_lat': summary.startPoint!.lat,
      if (summary.startPoint != null) 'start_lng': summary.startPoint!.lng,
      if (summary.endPoint != null) 'end_lat': summary.endPoint!.lat,
      if (summary.endPoint != null) 'end_lng': summary.endPoint!.lng,
    };
  }

  static RunSummary runSummaryFromRow(Map<String, dynamic> row) {
    return RunSummary(
      id: row['id'] as String,
      date: DateTime.parse(row['date'] as String),
      distanceKm: (row['distance_km'] as num).toDouble(),
      durationSeconds: (row['duration_seconds'] as num).toInt(),
      routeName: row['route_name'] as String? ?? '',
      routeId: row['route_id'] as String?,
      weatherEmoji: row['weather_emoji'] as String? ?? '',
      tempDisplay: row['temp_display'] as String? ?? '',
      maxLateralG: (row['max_lateral_g'] as num?)?.toDouble(),
      sharpCornersCount: (row['sharp_corners_count'] as num?)?.toInt() ?? 0,
      startPoint: _pointFromRow(row, 'start'),
      endPoint: _pointFromRow(row, 'end'),
    );
  }

  static Map<String, dynamic> routeToRow(
    RevvRoute route, {
    String? publishedBy,
  }) {
    return {
      'id': route.id,
      'name': route.name,
      'nodes': route.nodes.map((n) => {'lat': n.lat, 'lng': n.lng}).toList(),
      'distance_km': route.distanceKm,
      'curvature_score': route.windingScore,
      'winding_score': route.windingScore,
      'star_rating': route.starRating,
      'sharp_curve_count': route.sharpCurveCount,
      'center_lat': route.centerPoint.lat,
      'center_lng': route.centerPoint.lng,
      'tight_curve_km': route.tightCurveKm,
      'medium_curve_km': route.mediumCurveKm,
      'max_continuous_km': route.maxContinuousKm,
      'is_loop': route.isLoop,
      'route_rank_score': route.routeRankScore,
      'fun_score': route.funScore,
      'flow_score': route.flowScore,
      'driveability_penalty': route.driveabilityPenalty,
      'stop_sign_count': route.stopSignCount,
      'traffic_signal_count': route.trafficSignalCount,
      'stop_control_density': route.stopControlDensity,
      'road_class_bucket': route.roadClassBucket,
      'is_named': route.isNamed,
      'is_facility_like': route.isFacilityLike,
      'is_bridge_like': route.isBridgeLike,
      'is_connector_like': route.isConnectorLike,
      'is_major_road_like': route.isMajorRoadLike,
      'is_private_like': route.isPrivateLike,
      'quality_label': route.qualityLabel,
      'quality_reject_reason': route.qualityRejectReason,
      'route_character': route.routeCharacter,
      'primary_reason': route.primaryReason,
      'caution_note': route.cautionNote,
      'elevation_delta': route.elevationDelta,
      'source': 'revv',
      if (route.runCount > 0) 'run_count': route.runCount,
      if (publishedBy != null) 'published_by': publishedBy,
    };
  }

  static Map<String, dynamic> discoveredRouteCacheRow(
    RevvRoute route, {
    required String userId,
  }) {
    final enrichedRoute = hydrateRouteMetadata(route);
    return {
      'user_id': userId,
      'route_id': enrichedRoute.id,
      'route_data': routeToRow(
        enrichedRoute,
        publishedBy: enrichedRoute.publishedBy,
      ),
      'saved_at': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> recordRouteRunRpcParams(String routeId) {
    return {'route_id_input': routeId};
  }

  static RevvRoute routeFromRow(
    Map<String, dynamic> row, {
    double? userLat,
    double? userLng,
  }) {
    final centerLat = (row['center_lat'] as num?)?.toDouble() ?? 0;
    final centerLng = (row['center_lng'] as num?)?.toDouble() ?? 0;
    final nodes =
        (row['nodes'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(
              (n) => LatLng(
                (n['lat'] as num).toDouble(),
                (n['lng'] as num).toDouble(),
              ),
            )
            .toList() ??
        const [];
    final distanceFromUser =
        (row['distance_from_user_km'] as num?)?.toDouble() ??
        ((userLat != null &&
                userLng != null &&
                centerLat != 0 &&
                centerLng != 0)
            ? _distanceKmBetween(userLat, userLng, centerLat, centerLng)
            : 0);
    return hydrateRouteMetadata(
      RevvRoute(
        id: row['id'] as String,
        name: row['name'] as String? ?? '',
        nodes: nodes,
        distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0,
        windingScore: (row['winding_score'] as num?)?.toDouble() ?? 0,
        starRating: (row['star_rating'] as num?)?.toInt() ?? 1,
        sharpCurveCount: (row['sharp_curve_count'] as num?)?.toInt() ?? 0,
        centerPoint: LatLng(centerLat, centerLng),
        distanceFromUser: distanceFromUser,
        tightCurveKm: (row['tight_curve_km'] as num?)?.toDouble() ?? 0,
        mediumCurveKm: (row['medium_curve_km'] as num?)?.toDouble() ?? 0,
        maxContinuousKm: (row['max_continuous_km'] as num?)?.toDouble() ?? 0,
        isLoop: row['is_loop'] as bool? ?? false,
        routeRankScore: (row['route_rank_score'] as num?)?.toDouble() ?? 0,
        funScore: (row['fun_score'] as num?)?.toDouble() ?? 0,
        flowScore: (row['flow_score'] as num?)?.toDouble() ?? 0,
        driveabilityPenalty:
            (row['driveability_penalty'] as num?)?.toDouble() ?? 0,
        stopSignCount: (row['stop_sign_count'] as num?)?.toInt() ?? 0,
        trafficSignalCount: (row['traffic_signal_count'] as num?)?.toInt() ?? 0,
        stopControlDensity:
            (row['stop_control_density'] as num?)?.toDouble() ?? 0,
        roadClassBucket: row['road_class_bucket'] as String? ?? '',
        isNamed:
            row['is_named'] as bool? ??
            (row['name'] as String? ?? '').trim().isNotEmpty,
        isFacilityLike: row['is_facility_like'] as bool? ?? false,
        isBridgeLike: row['is_bridge_like'] as bool? ?? false,
        isConnectorLike: row['is_connector_like'] as bool? ?? false,
        isMajorRoadLike: row['is_major_road_like'] as bool? ?? false,
        isPrivateLike: row['is_private_like'] as bool? ?? false,
        qualityLabel: row['quality_label'] as String? ?? '',
        qualityRejectReason: row['quality_reject_reason'] as String?,
        routeCharacter: row['route_character'] as String? ?? '',
        primaryReason: row['primary_reason'] as String?,
        cautionNote: row['caution_note'] as String?,
        runCount: (row['run_count'] as num?)?.toInt() ?? 0,
        publishedBy: row['published_by'] as String?,
      ),
    );
  }

  static LatLng? _pointFromRow(Map<String, dynamic> row, String prefix) {
    final lat = row['${prefix}_lat'];
    final lng = row['${prefix}_lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  static double _distanceKmBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) =>
      degrees * 3.1415926535897932 / 180.0;

  void _setStatus(SyncStatus s) {
    _status = s;
    notifyListeners();
  }
}
