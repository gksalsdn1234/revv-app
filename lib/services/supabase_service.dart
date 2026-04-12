import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../core/supabase_tables.dart';
import '../models/revv_route.dart';
import '../models/run_summary.dart';

enum SyncStatus { idle, syncing, done, error }

class SupabaseService extends ChangeNotifier {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  SupabaseConfig? _config;
  bool _initialized = false;
  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  bool _ready = false;
  bool get isReady => _ready;

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
      _setStatus(SyncStatus.done);
      debugPrint('[Supabase] initialized — uid: $uid');
    } catch (e) {
      _ready = false;
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
          .from(SupabaseTables.curvyRoads)
          .upsert(routes.map(routeToRow).toList(), onConflict: 'id');
      debugPrint('[Supabase] route pool saved — ${routes.length}');
    } catch (e) {
      debugPrint('[Supabase] saveDiscoveredRoutes failed: $e');
    }
  }

  Future<List<RevvRoute>> loadDiscoveredRoutes() async {
    if (!_ready) return const [];
    try {
      final rows = await client!
          .from(SupabaseTables.curvyRoads)
          .select()
          .order('winding_score', ascending: false)
          .limit(25);
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(routeFromRow)
          .toList();
    } catch (e) {
      debugPrint('[Supabase] loadDiscoveredRoutes failed: $e');
      return const [];
    }
  }

  Future<void> publishRoute(RevvRoute route) async {
    if (!_ready || uid == null) return;
    try {
      await client!
          .from(SupabaseTables.curvyRoads)
          .upsert(routeToRow(route, publishedBy: uid!), onConflict: 'id');
    } catch (e) {
      debugPrint('[Supabase] publishRoute failed: $e');
    }
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
    );
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
          .map(routeFromRow)
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
      final current = await client!
          .from(SupabaseTables.curvyRoads)
          .select('run_count')
          .eq('id', routeId)
          .maybeSingle();
      final runCount = ((current?['run_count'] as num?)?.toInt() ?? 0) + 1;
      await client!
          .from(SupabaseTables.curvyRoads)
          .update({'run_count': runCount})
          .eq('id', routeId);
    } catch (e) {
      debugPrint('[Supabase] recordRouteRun failed: $e');
    }
  }

  Future<Map<String, Map<String, dynamic>>> fetchRouteRecords(
    String userId,
  ) async {
    if (!_ready) return const {};
    try {
      final rows = await client!
          .from(SupabaseTables.routeRecords)
          .select()
          .eq('user_id', userId);
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
    required String userId,
    required String routeId,
    required int bestTimeSeconds,
    required double bestMaxG,
    required int runCount,
    required DateTime lastRunAt,
  }) async {
    if (!_ready) return;
    try {
      await client!.from(SupabaseTables.routeRecords).upsert({
        'user_id': userId,
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
        await client!.from(SupabaseTables.savedRoutes).upsert({
          'user_id': uid!,
          'route_id': route.id,
          'route_data': routeToRow(route),
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
      'elevation_delta': route.elevationDelta,
      'source': 'revv',
      if (route.runCount > 0) 'run_count': route.runCount,
      if (publishedBy != null) 'published_by': publishedBy,
    };
  }

  static RevvRoute routeFromRow(Map<String, dynamic> row) {
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
    return RevvRoute(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      nodes: nodes,
      distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0,
      windingScore: (row['winding_score'] as num?)?.toDouble() ?? 0,
      starRating: (row['star_rating'] as num?)?.toInt() ?? 1,
      sharpCurveCount: (row['sharp_curve_count'] as num?)?.toInt() ?? 0,
      centerPoint: LatLng(centerLat, centerLng),
      distanceFromUser: (row['distance_from_user_km'] as num?)?.toDouble() ?? 0,
      tightCurveKm: (row['tight_curve_km'] as num?)?.toDouble() ?? 0,
      mediumCurveKm: (row['medium_curve_km'] as num?)?.toDouble() ?? 0,
      maxContinuousKm: (row['max_continuous_km'] as num?)?.toDouble() ?? 0,
      isLoop: row['is_loop'] as bool? ?? false,
      runCount: (row['run_count'] as num?)?.toInt() ?? 0,
      publishedBy: row['published_by'] as String?,
    );
  }

  static LatLng? _pointFromRow(Map<String, dynamic> row, String prefix) {
    final lat = row['${prefix}_lat'];
    final lng = row['${prefix}_lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    notifyListeners();
  }
}
