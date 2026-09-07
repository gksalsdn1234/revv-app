import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'route_performance.dart';
import 'route_overview_transport.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

import '../core/supabase_config.dart';
import '../core/supabase_tables.dart';
import '../core/storage_keys.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_telemetry_detail.dart';
import '../models/run_summary.dart';
import 'drive_dynamics_tracker.dart';
import 'route_loading_policy.dart';
import 'secure_session_store.dart';

enum SyncStatus { idle, syncing, done, error }

enum CloudSessionState { unavailable, anonymous, identified }

enum _AccountDeletionResult { deleted, retryableFailure }

class _RouteCatalogState {
  const _RouteCatalogState({required this.epoch, required this.routeIds});

  final int epoch;
  final List<String> routeIds;
}

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
  _RouteCatalogState? _routeCatalogState;

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
    if (!isReady) return null;
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
    _routeCatalogState = null;
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
      _client = SupabaseClient(
        _config!.url,
        _config!.anonKey,
        httpClient: RouteTimingClient(http.Client()),
      );
      final auth = _client!.auth;
      await _recoverPersistedSession();
      final canContinue = await _resumePendingAccountDeletion();
      if (!canContinue) {
        _ready = false;
        _lastFailureReason = '계정 삭제를 완료하지 못했어요. 연결 후 앱을 다시 시작해 주세요.';
        _setStatus(SyncStatus.error);
        return;
      }
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

  Future<bool> _resumePendingAccountDeletion() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingUid = prefs.getString(StorageKeys.pendingAccountDeletionUid);
    if (pendingUid == null) return true;
    final currentUid = _client?.auth.currentUser?.id;
    if (currentUid == null || currentUid != pendingUid) {
      return false;
    }

    final result = await _requestAccountDeletion();
    if (result == _AccountDeletionResult.retryableFailure) {
      return false;
    }
    await _completeAccountDeletionAuthCleanup(pendingUid);
    return true;
  }

  Future<void> _recoverPersistedSession() async {
    final stored = await sessionStore.readSession();
    if (stored == null || stored.isEmpty || _client == null) return;
    try {
      await _client!.auth.recoverSession(stored);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final pendingUid = prefs.getString(StorageKeys.pendingAccountDeletionUid);
      if (pendingUid == null) await sessionStore.deleteSession();
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

  Future<bool> saveTelemetrySummary(
    String runId,
    DriveDynamicsSummary summary,
  ) async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from('telemetry_summary')
          .insert(telemetrySummaryToRow(runId, summary, userId: uid!));
      _debugLog('[Supabase] telemetry summary uploaded — $runId');
      return true;
    } catch (e) {
      _debugLog('[Supabase] saveTelemetrySummary failed: ${_safeError(e)}');
      return false;
    }
  }

  Future<bool> uploadRouteFeedback(RouteFeedback feedback) async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from(SupabaseTables.routeFeedback)
          .upsert(
            routeFeedbackToRow(feedback, userId: uid!),
            onConflict: 'user_id,run_id',
          );
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
    if (!_ready || uid == null || client == null) return false;
    try {
      await client!.from(SupabaseTables.regionRequests).insert({
        'user_id': uid!,
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

  Future<List<RunSummary>?> fetchMissingRuns(Set<String> localIds) async {
    if (!_ready || uid == null) return null;
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
      return null;
    }
  }

  Future<Set<String>?> fetchRunIds() async {
    if (!_ready || uid == null) return null;
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
      return null;
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
    double radiusKm, {
    int? maxResults,
    bool throwOnFailure = false,
    bool trackFailureReason = true,
  }) async {
    return findCurvyRoads(
      lat: lat,
      lng: lng,
      radiusM: (radiusKm * 1000).round(),
      maxResults: maxResults ?? _nearbyRouteFetchLimit(radiusKm),
      throwOnFailure: throwOnFailure,
      trackFailureReason: trackFailureReason,
    );
  }

  Future<int> fetchRouteCatalogEpoch() async {
    return (await _loadRouteCatalogState(forceRefresh: true)).epoch;
  }

  late final _overviewTransport = RouteOverviewTransport(
    (name, params) async => client!.rpc(name, params: params),
  );

  Future<List<RevvRoute>> fetchRouteCatalog({int maxResults = 650}) async {
    final state = await _loadRouteCatalogState();
    final routeIds = state.routeIds.take(maxResults.clamp(1, 650)).toList();
    if (routeIds.isEmpty) return const [];
    final rows = await _overviewTransport.request(
      'get_route_overview_v2',
      'get_route_nodes_v2',
      {'route_ids_input': routeIds},
    );
    return RoutePerformance.measureSync(
      'catalog.model_decode',
      () => (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(_catalogRouteFromNodeRow)
          .where((route) => route.nodes.length > 1)
          .take(650)
          .toList(growable: false),
    );
  }

  Future<_RouteCatalogState> _loadRouteCatalogState({
    bool forceRefresh = false,
  }) async {
    if (!_ready || uid == null || client == null) {
      throw StateError('Authenticated Supabase session required');
    }
    if (!forceRefresh && _routeCatalogState != null) {
      return _routeCatalogState!;
    }
    final rows = await client!.rpc('get_route_catalog_v2');
    final row = (rows as List).whereType<Map<String, dynamic>>().firstOrNull;
    if (row == null) throw StateError('Route catalog is unavailable');
    final epoch = (row['catalog_epoch'] as num?)?.toInt();
    if (epoch == null || epoch < 0) {
      throw const FormatException('Invalid route catalog epoch');
    }
    final ids = ((row['route_ids'] as List?) ?? const [])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .take(650)
        .toList(growable: false);
    return _routeCatalogState = _RouteCatalogState(epoch: epoch, routeIds: ids);
  }

  Future<List<RevvRoute>> fetchNearbyRoutesV2(
    double lat,
    double lng,
    double radiusKm, {
    int maxResults = 120,
  }) async {
    if (!_ready || uid == null || client == null) {
      throw StateError('Authenticated Supabase session required');
    }
    final rows = await _overviewTransport
        .request('find_curvy_roads_overview_v2', 'find_curvy_roads_v2', {
          'user_lat': lat,
          'user_lng': lng,
          'radius_m': (radiusKm * 1000).round(),
          'min_score': 0,
          'max_results': maxResults.clamp(1, 120),
        });
    return RoutePerformance.measureSync(
      'nearby.model_decode',
      () => (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => routeFromRow(row, userLat: lat, userLng: lng))
          .take(120)
          .toList(growable: false),
    );
  }

  Future<List<RevvRoute>> fetchMapSegments(
    double lat,
    double lng,
    double radiusKm, {
    int maxResults = 30,
    bool throwOnFailure = false,
  }) async {
    if (!_ready) {
      if (throwOnFailure) {
        throw StateError('Supabase is not ready');
      }
      return const [];
    }
    try {
      final rows = await client!.rpc(
        'find_curvy_map_segments',
        params: {
          'user_lat': lat,
          'user_lng': lng,
          'radius_m': (radiusKm * 1000).round(),
          'min_distance_km': 0.3,
          'max_results': maxResults,
        },
      );
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => routeFromRow(row, userLat: lat, userLng: lng))
          .where((route) => route.nodes.length > 1)
          .toList(growable: false);
    } catch (e) {
      _debugLog('[Supabase] fetchMapSegments failed: ${_safeError(e)}');
      if (throwOnFailure) rethrow;
      return const [];
    }
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
    bool throwOnFailure = false,
    bool trackFailureReason = true,
  }) async {
    if (!_ready) {
      if (throwOnFailure) {
        throw StateError('Supabase is not ready');
      }
      return const [];
    }
    if (trackFailureReason) _lastFailureReason = null;
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
      if (trackFailureReason) {
        _lastFailureReason = '클라우드 루트 검색에 실패했어요.';
      }
      _debugLog('[Supabase] findCurvyRoads failed: ${_safeError(e)}');
      if (throwOnFailure) rethrow;
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

  Future<List<LatLng>> fetchRouteNodesV2(String routeId) async {
    if (!_ready || uid == null || client == null) {
      throw StateError('Authenticated Supabase session required');
    }
    final rows = await client!.rpc(
      'get_route_nodes_v2',
      params: {
        'route_ids_input': [routeId],
      },
    );
    final row = (rows as List).whereType<Map<String, dynamic>>().firstOrNull;
    return _nodesFromJson(row?['nodes']);
  }

  Future<bool> recordRouteRun(String? routeId, String runId) async {
    if (!_ready || routeId == null) return false;
    try {
      await client!.rpc(
        'increment_route_run_count',
        params: recordRouteRunRpcParams(routeId, runId),
      );
      return true;
    } catch (e) {
      _debugLog('[Supabase] recordRouteRun failed: ${_safeError(e)}');
      return false;
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
          .from(SupabaseTables.telemetrySummary)
          .delete()
          .eq('user_id', uid!);
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
      await client!
          .from(SupabaseTables.exploredCells)
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

  Future<bool> deleteAccount() async {
    if (!_ready || uid == null || client == null) return false;
    final deletedUid = uid!;
    final result = await _requestAccountDeletion();
    if (result != _AccountDeletionResult.deleted) return false;
    await _completeAccountDeletionAuthCleanup(deletedUid);
    await _authSubscription?.cancel();
    _authSubscription = null;
    _client = null;
    _ready = false;
    _initialized = false;
    _lastFailureReason = null;
    _setStatus(SyncStatus.idle);
    notifyListeners();
    return true;
  }

  Future<_AccountDeletionResult> _requestAccountDeletion() async {
    final activeClient = client;
    if (activeClient == null) return _AccountDeletionResult.retryableFailure;
    try {
      final response = await activeClient.functions.invoke(
        'delete-account',
        method: HttpMethod.post,
      );
      final data = response.data;
      if (response.status != 200 || data is! Map || data['deleted'] != true) {
        return _AccountDeletionResult.retryableFailure;
      }
      return _AccountDeletionResult.deleted;
    } on FunctionException catch (error) {
      _debugLog('[Supabase] deleteAccount failed: ${_safeError(error)}');
      return _AccountDeletionResult.retryableFailure;
    } catch (e) {
      _debugLog('[Supabase] deleteAccount failed: ${_safeError(e)}');
      return _AccountDeletionResult.retryableFailure;
    }
  }

  Future<void> _completeAccountDeletionAuthCleanup(String deletedUid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.confirmedAccountDeletionUid, deletedUid);
    try {
      await client?.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    await sessionStore.deleteSession();
  }

  Future<Map<String, DateTime>> fetchExploredCells() async {
    if (!_ready || uid == null) return const {};
    try {
      const pageSize = 1000;
      final cells = <String, DateTime>{};
      for (var offset = 0; ; offset += pageSize) {
        final rows = await client!
            .from(SupabaseTables.exploredCells)
            .select('cell_id,explored_at')
            .eq('user_id', uid!)
            .order('cell_id')
            .range(offset, offset + pageSize - 1);
        final page = (rows as List).whereType<Map<String, dynamic>>().toList();
        for (final row in page) {
          final cellId = row['cell_id'] as String?;
          final exploredAt = DateTime.tryParse(
            row['explored_at']?.toString() ?? '',
          );
          if (cellId != null && exploredAt != null) cells[cellId] = exploredAt;
        }
        if (page.length < pageSize) break;
      }
      return cells;
    } catch (e) {
      _debugLog('[Supabase] fetchExploredCells failed: ${_safeError(e)}');
      rethrow;
    }
  }

  Future<bool> upsertExploredCells(Map<String, DateTime> cells) async {
    if (!_ready || uid == null) return false;
    if (cells.isEmpty) return true;
    try {
      final rows = exploredCellRows(cells, userId: uid!);
      const batchSize = 500;
      for (var start = 0; start < rows.length; start += batchSize) {
        final end = min(start + batchSize, rows.length);
        await client!
            .from(SupabaseTables.exploredCells)
            .upsert(rows.sublist(start, end), onConflict: 'user_id,cell_id');
      }
      return true;
    } catch (e) {
      _debugLog('[Supabase] upsertExploredCells failed: ${_safeError(e)}');
      return false;
    }
  }

  Future<bool> deleteExploredCells() async {
    if (!_ready || uid == null) return false;
    try {
      await client!
          .from(SupabaseTables.exploredCells)
          .delete()
          .eq('user_id', uid!);
      return true;
    } catch (e) {
      _debugLog('[Supabase] deleteExploredCells failed: ${_safeError(e)}');
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

  static List<Map<String, dynamic>> exploredCellRows(
    Map<String, DateTime> cells, {
    required String userId,
  }) {
    final entries = cells.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        {
          'user_id': userId,
          'cell_id': entry.key,
          'explored_at': entry.value.toUtc().toIso8601String(),
        },
    ];
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

  static Map<String, dynamic> telemetrySummaryToRow(
    String runId,
    DriveDynamicsSummary summary, {
    required String userId,
  }) {
    return {
      'run_id': runId,
      'user_id': userId,
      'hard_brake_count': summary.hardBrakeCount,
      'harsh_steer_count': summary.harshSteerCount,
      'smooth_ratio': summary.smoothRatio,
      'p95_lateral_g': summary.p95LateralG,
      'sample_seconds': summary.sampleSeconds,
      'detail_version': 'v1',
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

  static Map<String, dynamic> recordRouteRunRpcParams(
    String routeId,
    String runId,
  ) {
    return {'route_id_input': routeId, 'run_id_input': runId};
  }

  static RevvRoute routeFromRow(
    Map<String, dynamic> row, {
    double? userLat,
    double? userLng,
  }) {
    final centerLat = (row['center_lat'] as num?)?.toDouble() ?? 0;
    final centerLng = (row['center_lng'] as num?)?.toDouble() ?? 0;
    const maxRouteNodes = 1200;
    final rawNodes = (row['nodes'] as List?) ?? const [];
    final sampledNodes = rawNodes.length <= maxRouteNodes
        ? rawNodes
        : List.generate(maxRouteNodes, (index) {
            final sourceIndex =
                (index * (rawNodes.length - 1) / (maxRouteNodes - 1)).round();
            return rawNodes[sourceIndex];
          }, growable: false);
    final nodes = sampledNodes
        .whereType<Map<String, dynamic>>()
        .expand((node) {
          final lat = (node['lat'] as num?)?.toDouble();
          final lng = (node['lng'] as num?)?.toDouble();
          if (lat == null ||
              lng == null ||
              !lat.isFinite ||
              !lng.isFinite ||
              lat < -90 ||
              lat > 90 ||
              lng < -180 ||
              lng > 180) {
            return const <LatLng>[];
          }
          return [LatLng(lat, lng)];
        })
        .toList(growable: false);
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
        geometryIsOverview: row['geometry_detail'] == 'overview',
        distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0,
        windingScore: (row['winding_score'] as num?)?.toDouble() ?? 0,
        starRating: (row['star_rating'] as num?)?.toInt() ?? 1,
        sharpCurveCount: (row['sharp_curve_count'] as num?)?.toInt() ?? 0,
        elevationDelta: (row['elevation_delta'] as num?)?.toDouble() ?? 0,
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
        isGenerated: row['is_generated'] as bool? ?? false,
        activatedAt: DateTime.tryParse(row['activated_at']?.toString() ?? ''),
        provinceCode: row['province_code'] as String?,
        catalogEpoch: (row['catalog_epoch'] as num?)?.toInt(),
      ),
    );
  }

  static RevvRoute _catalogRouteFromNodeRow(Map<String, dynamic> row) {
    if (row['geometry_detail'] == 'overview') return routeFromRow(row);
    final nodes = _nodesFromJson(row['nodes']);
    final center = nodes.isEmpty
        ? const LatLng(0, 0)
        : LatLng(
            nodes.fold<double>(0, (sum, node) => sum + node.lat) / nodes.length,
            nodes.fold<double>(0, (sum, node) => sum + node.lng) / nodes.length,
          );
    final id = row['id'] as String? ?? '';
    return RevvRoute(
      id: id,
      name: id,
      nodes: nodes,
      distanceKm: _polylineDistanceKm(nodes),
      windingScore: 0,
      starRating: 1,
      sharpCurveCount: 0,
      centerPoint: center,
      distanceFromUser: 0,
      isGenerated: row['is_generated'] as bool? ?? false,
      activatedAt: DateTime.tryParse(row['activated_at']?.toString() ?? ''),
      provinceCode: row['province_code'] as String?,
      catalogEpoch: (row['catalog_epoch'] as num?)?.toInt(),
    );
  }

  static List<LatLng> _nodesFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .expand((node) {
          final lat = (node['lat'] as num?)?.toDouble();
          final lng = (node['lng'] as num?)?.toDouble();
          if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
            return const <LatLng>[];
          }
          return [LatLng(lat, lng)];
        })
        .toList(growable: false);
  }

  static double _polylineDistanceKm(List<LatLng> nodes) {
    var distance = 0.0;
    for (var index = 1; index < nodes.length; index++) {
      distance += RevvRoute.haversineKm(nodes[index - 1], nodes[index]);
    }
    return distance;
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
