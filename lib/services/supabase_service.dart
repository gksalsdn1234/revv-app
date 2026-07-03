import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../core/supabase_config.dart';
import '../core/supabase_tables.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_telemetry_detail.dart';
import '../models/run_summary.dart';
import 'route_loading_policy.dart';
import 'secure_session_store.dart';

enum SyncStatus { idle, syncing, done, error }

enum CloudSessionState { unavailable, anonymous, identified }

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
  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSubscription;
  SecureSessionStore sessionStore = SecureSessionStore();
  bool? _debugReadyOverride;
  String? _debugUidOverride;
  bool? _debugAnonymousOverride;

  bool _ready = false;
  bool get isReady => _debugReadyOverride ?? _ready;
  bool get isCloudAvailable => isReady && uid != null;
  bool get isIdentifiedCloudSession =>
      cloudSessionState == CloudSessionState.identified;
  CloudSessionState get cloudSessionState {
    if (!isReady || uid == null) return CloudSessionState.unavailable;
    final anonymous =
        _debugAnonymousOverride ?? _client?.auth.currentUser?.isAnonymous;
    return anonymous == true
        ? CloudSessionState.anonymous
        : CloudSessionState.identified;
  }

  String get availabilityLabel {
    switch (cloudSessionState) {
      case CloudSessionState.identified:
        return '계정 클라우드 연결됨';
      case CloudSessionState.anonymous:
        return '게스트 클라우드 연결됨';
      case CloudSessionState.unavailable:
        break;
    }
    if (_status == SyncStatus.error) return '클라우드 연결 실패';
    return '클라우드 비활성';
  }

  String? get uid {
    if (_debugUidOverride != null) return _debugUidOverride;
    try {
      return _client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void debugSetCloudSessionStateForTesting({
    required bool ready,
    required String? uid,
    required bool anonymous,
  }) {
    _debugReadyOverride = ready;
    _debugUidOverride = uid;
    _debugAnonymousOverride = anonymous;
  }

  @visibleForTesting
  void debugResetForTesting() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _config = null;
    _initialized = false;
    _status = SyncStatus.idle;
    _lastFailureReason = null;
    _client = null;
    sessionStore = SecureSessionStore();
    _ready = false;
    _debugReadyOverride = null;
    _debugUidOverride = null;
    _debugAnonymousOverride = null;
  }

  SupabaseClient? get client {
    return _client;
  }

  Future<void> init({SupabaseConfig? config}) async {
    if (_initialized) return;
    _initialized = true;
    _config ??= config ?? SupabaseConfig.instance;
    if (!_config!.isConfigured) {
      _ready = false;
      _lastFailureReason = 'Supabase 설정이 없어 클라우드 기능을 비활성화했어요.';
      _setStatus(SyncStatus.idle);
      _debugLog('[Supabase] configuration missing; cloud features disabled');
      return;
    }

    try {
      _client = SupabaseClient(_config!.url, _config!.anonKey);
      final auth = _client!.auth;
      await _recoverPersistedSession();
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
        await _persistCurrentSession();
      }
      _listenForAuthPersistence();
      _ready = true;
      _lastFailureReason = null;
      _setStatus(SyncStatus.done);
      _debugLog('[Supabase] initialized — uid: ${_masked(uid)}');
    } catch (e) {
      _ready = false;
      _lastFailureReason = '클라우드 연결에 실패했어요.';
      _setStatus(SyncStatus.error);
      _debugLog('[Supabase] init failed: ${_safeError(e)}');
    }
    notifyListeners();
  }

  Future<void> _recoverPersistedSession() async {
    final stored = await sessionStore.readSession();
    if (stored == null || stored.isEmpty || _client == null) return;
    try {
      await _client!.auth.recoverSession(stored);
    } catch (e) {
      await sessionStore.deleteSession();
      _debugLog('[Supabase] stored session recovery failed: ${_safeError(e)}');
    }
  }

  void _listenForAuthPersistence() {
    _authSubscription?.cancel();
    _authSubscription = _client?.auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      if (session == null) {
        await sessionStore.deleteSession();
        return;
      }
      await sessionStore.writeSession(jsonEncode(session.toJson()));
    });
  }

  Future<void> _persistCurrentSession() async {
    final session = _client?.auth.currentSession;
    if (session == null) return;
    await sessionStore.writeSession(jsonEncode(session.toJson()));
  }

  Future<bool> uploadRun(RunSummary summary) async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from(SupabaseTables.runs)
          .upsert(runSummaryToRow(summary, userId: uid!), onConflict: 'id');
      _debugLog('[Supabase] run uploaded — ${summary.id}');
      return true;
    } catch (e) {
      _debugLog('[Supabase] uploadRun failed: ${_safeError(e)}');
      return false;
    }
  }

  Future<Map<String, dynamic>?> invokeFunction(
    String name, {
    Map<String, dynamic> body = const {},
  }) async {
    if (!_ready || client == null) return null;
    try {
      final response = await client!.functions.invoke(name, body: body);
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String && data.trim().isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      _debugLog('[Supabase] function $name failed: ${_safeError(e)}');
    }
    return null;
  }

  Future<bool> uploadRunDetail(RunTelemetryDetail detail) async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from(SupabaseTables.runDetails)
          .upsert(runDetailToRow(detail, userId: uid!), onConflict: 'run_id');
      _debugLog('[Supabase] run detail uploaded — ${detail.runId}');
      return true;
    } catch (e) {
      _debugLog('[Supabase] uploadRunDetail failed: ${_safeError(e)}');
      return false;
    }
  }

  Future<bool> uploadRouteFeedback(RouteFeedback feedback) async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from(SupabaseTables.routeFeedback)
          .upsert(routeFeedbackToRow(feedback, userId: uid!), onConflict: 'id');
      _debugLog('[Supabase] route feedback uploaded — ${feedback.id}');
      return true;
    } catch (e) {
      _debugLog('[Supabase] uploadRouteFeedback failed: ${_safeError(e)}');
      return false;
    }
  }

  Future<bool> recordRegionRequest(
    RegionRequestGrid grid, {
    required String locale,
  }) async {
    _config ??= SupabaseConfig.instance;
    if (!_config!.isConfigured) return false;
    try {
      final requestClient = SupabaseClient(_config!.url, _config!.anonKey);
      await requestClient.from(SupabaseTables.regionRequests).insert({
        'grid_key': grid.gridKey,
        'lat_rounded': grid.latRounded,
        'lng_rounded': grid.lngRounded,
        'locale': locale,
      });
      _debugLog('[Supabase] region request recorded — ${grid.gridKey}');
      return true;
    } catch (e) {
      _debugLog('[Supabase] recordRegionRequest failed: ${_safeError(e)}');
      return false;
    }
  }

  Future<RunTelemetryDetail?> fetchRunDetail(String runId) async {
    if (!_ready || uid == null) return null;
    try {
      final row = await client!
          .from(SupabaseTables.runDetails)
          .select()
          .eq('user_id', uid!)
          .eq('run_id', runId)
          .maybeSingle();
      if (row == null) return null;
      return runDetailFromRow(row);
    } catch (e) {
      _debugLog('[Supabase] fetchRunDetail failed: ${_safeError(e)}');
      return null;
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
      _debugLog('[Supabase] fetchMissingRuns failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] fetchRunIds failed: ${_safeError(e)}');
      return const {};
    }
  }

  Future<bool> uploadAll(List<RunSummary> runs) async {
    if (!_ready || uid == null || runs.isEmpty) return false;
    _setStatus(SyncStatus.syncing);
    try {
      await client!
          .from(SupabaseTables.runs)
          .upsert(
            runs.map((r) => runSummaryToRow(r, userId: uid!)).toList(),
            onConflict: 'id',
          );
      _setStatus(SyncStatus.done);
      _debugLog('[Supabase] bulk upload ${runs.length} runs');
      return true;
    } catch (e) {
      _debugLog('[Supabase] uploadAll failed: ${_safeError(e)}');
      _setStatus(SyncStatus.error);
      return false;
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
      _debugLog('[Supabase] route pool saved — ${routes.length}');
    } catch (e) {
      _debugLog('[Supabase] saveDiscoveredRoutes failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] loadDiscoveredRoutes failed: ${_safeError(e)}');
      return const [];
    }
  }

  Future<void> publishRoute(RevvRoute route) async {
    if (!_ready) return;
    _debugLog(
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
      maxResults: _nearbyRouteFetchLimit(radiusKm),
    );
  }

  int _nearbyRouteFetchLimit(double radiusKm) {
    if (radiusKm >= 160) return 650;
    if (radiusKm >= 100) return 400;
    return 250;
  }

  Future<List<RevvRoute>> fetchNearbyRoutesDirect(
    double lat,
    double lng,
    double radiusKm, {
    int limit = 200,
  }) async {
    if (!_ready) return const [];
    _lastFailureReason = null;
    try {
      _debugLog(
        '[Supabase] fetchNearbyRoutesDirect request '
        'lat=${lat.toStringAsFixed(3)} '
        'lng=${lng.toStringAsFixed(3)} '
        'radius=${radiusKm.toStringAsFixed(1)}km '
        'limit=$limit',
      );
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

      _debugLog(
        '[Supabase] direct nearby fallback: ${routes.length} rows '
        '(lat=${lat.toStringAsFixed(2)}, lng=${lng.toStringAsFixed(2)}, r=${radiusKm.toStringAsFixed(0)}km)',
      );
      return routes;
    } catch (e) {
      _lastFailureReason = '클라우드 루트 조회에 실패했어요.';
      _debugLog('[Supabase] fetchNearbyRoutesDirect failed: ${_safeError(e)}');
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
    _lastFailureReason = null;
    try {
      _debugLog(
        '[Supabase] findCurvyRoads request '
        'lat=${lat.toStringAsFixed(3)} '
        'lng=${lng.toStringAsFixed(3)} '
        'radius=${radiusM}m '
        'minScore=$minScore '
        'maxResults=$maxResults',
      );
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
      final mapped = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => routeFromRow(row, userLat: lat, userLng: lng))
          .toList();
      final preview = mapped
          .take(5)
          .map(
            (route) =>
                '${route.name.isEmpty ? '(noname)' : route.name}'
                '[${route.distanceKm.toStringAsFixed(1)}km/'
                '${route.distanceFromUser.toStringAsFixed(1)}km away]',
          )
          .join(', ');
      _debugLog(
        '[Supabase] findCurvyRoads response: ${mapped.length} rows'
        '${preview.isEmpty ? '' : ' -> $preview'}',
      );
      return mapped;
    } catch (e) {
      _lastFailureReason = '클라우드 루트 검색에 실패했어요.';
      _debugLog('[Supabase] findCurvyRoads failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] fetchRouteNodes failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] recordRouteRun failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] fetchRouteRecords failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] upsertRouteRecord failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] fetchTopRoutes failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] loadSavedRoutes failed: ${_safeError(e)}');
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
      _debugLog('[Supabase] saveRouteBookmark failed: ${_safeError(e)}');
    }
  }

  Future<bool> deleteUserRunData() async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from(SupabaseTables.runDetails)
          .delete()
          .eq('user_id', uid!);
      await client!
          .from(SupabaseTables.routeFeedback)
          .delete()
          .eq('user_id', uid!);
      await client!
          .from(SupabaseTables.routeRecords)
          .delete()
          .eq('user_id', uid!);
      await client!.from(SupabaseTables.runs).delete().eq('user_id', uid!);
      _debugLog('[Supabase] user run data deleted');
      return true;
    } catch (e) {
      _debugLog('[Supabase] deleteUserRunData failed: ${_safeError(e)}');
      return false;
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
      if (summary.maxSpeedKmh > 0) 'max_speed_kmh': summary.maxSpeedKmh,
      if (summary.avgSpeedKmh > 0) 'avg_speed_kmh': summary.avgSpeedKmh,
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
      maxSpeedKmh: (row['max_speed_kmh'] as num?)?.toDouble() ?? 0,
      avgSpeedKmh: (row['avg_speed_kmh'] as num?)?.toDouble() ?? 0,
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

  static Map<String, dynamic> runDetailToRow(
    RunTelemetryDetail detail, {
    required String userId,
  }) {
    return {
      'run_id': detail.runId,
      'user_id': userId,
      'detail_version': detail.version,
      'telemetry_json': detail.toJson(),
      'created_at': detail.createdAt.toIso8601String(),
    };
  }

  static RunTelemetryDetail runDetailFromRow(Map<String, dynamic> row) {
    final json = row['telemetry_json'];
    if (json is Map<String, dynamic>) {
      return RunTelemetryDetail.fromJson(json);
    }
    if (json is Map) {
      return RunTelemetryDetail.fromJson(json.cast<String, dynamic>());
    }
    throw FormatException('Invalid telemetry_json for run ${row['run_id']}');
  }

  static Map<String, dynamic> routeFeedbackToRow(
    RouteFeedback feedback, {
    required String userId,
  }) {
    return {
      'id': feedback.id,
      'user_id': userId,
      'run_id': feedback.runId,
      'route_id': feedback.routeId,
      'route_name': feedback.routeName,
      'feedback_type': feedback.feedbackType,
      'created_at': feedback.createdAt.toIso8601String(),
    };
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
      if (route.elevationProfile != null)
        'elevation_profile': route.elevationProfile,
      'road_names': route.roadNames,
      'surface_summary': route.surfaceSummary,
      'speed_limit_summary': route.speedLimitSummary,
      'nearby_pois': route.nearbyPoiNames
          .map((name) => {'name': name, 'category': 'saved'})
          .toList(),
      'source': 'revv',
      if (route.runCount > 0) 'run_count': route.runCount,
      'published_by': ?publishedBy,
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
        roadNames: _stringListFromJson(row['road_names']),
        surfaceSummary: row['surface_summary'] as String? ?? '',
        speedLimitSummary: row['speed_limit_summary'] as String? ?? '',
        nearbyPoiNames: _poiNamesFromJson(row['nearby_pois']),
        elevationProfile: _doubleListFromJson(row['elevation_profile']),
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

  static List<String> _stringListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<String> _poiNamesFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is Map) {
            return (item['name'] ?? item['category'] ?? '').toString().trim();
          }
          return item.toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<double>? _doubleListFromJson(dynamic value) {
    if (value is! List) return null;
    final result = value
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList();
    return result.isEmpty ? null : result;
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

  void _debugLog(String message) {
    if (kDebugMode) debugPrint(message);
  }

  String _masked(String? value) {
    if (value == null || value.length < 8) return 'anonymous';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  String _safeError(Object error) {
    if (kDebugMode) return error.toString();
    return error.runtimeType.toString();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
