import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import 'route_loading_policy.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import '../ui/run_report_metrics.dart';
import 'run_pending_upload_store.dart';
import 'supabase_service.dart';

abstract class RunHistoryCloudClient {
  bool get isReady;
  Future<bool> uploadRun(RunSummary summary);
  Future<bool> uploadRunDetail(RunTelemetryDetail detail);
  Future<bool> uploadRouteFeedback(RouteFeedback feedback);
  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds);
  Future<Set<String>> fetchRunIds();
  Future<RunTelemetryDetail?> fetchRunDetail(String runId);
  Future<void> recordRouteRun(String? routeId);
  Future<bool> deleteUserRunData();
}

class SupabaseRunHistoryCloudClient implements RunHistoryCloudClient {
  SupabaseRunHistoryCloudClient({SupabaseService? service})
    : _service = service ?? SupabaseService();

  final SupabaseService _service;

  @override
  bool get isReady => _service.isReady;

  @override
  Future<bool> uploadRun(RunSummary summary) => _service.uploadRun(summary);

  @override
  Future<bool> uploadRunDetail(RunTelemetryDetail detail) =>
      _service.uploadRunDetail(detail);

  @override
  Future<bool> uploadRouteFeedback(RouteFeedback feedback) =>
      _service.uploadRouteFeedback(feedback);

  @override
  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds) =>
      _service.fetchMissingRuns(localIds);

  @override
  Future<Set<String>> fetchRunIds() => _service.fetchRunIds();

  @override
  Future<RunTelemetryDetail?> fetchRunDetail(String runId) =>
      _service.fetchRunDetail(runId);

  @override
  Future<void> recordRouteRun(String? routeId) =>
      _service.recordRouteRun(routeId);

  @override
  Future<bool> deleteUserRunData() => _service.deleteUserRunData();
}

class RunHistoryService extends ChangeNotifier {
  RunHistoryService({
    RunPendingUploadStore pendingStore = const RunPendingUploadStore(),
    RunHistoryCloudClient? cloudClient,
  }) : _pendingStore = pendingStore,
       _cloud = cloudClient ?? SupabaseRunHistoryCloudClient();

  final RunPendingUploadStore _pendingStore;
  final RunHistoryCloudClient _cloud;
  List<RunSummary> _history = [];
  List<RouteFeedback> _feedback = [];
  List<RunSummary> get history => List.unmodifiable(_history);
  List<RouteFeedback> get feedback => List.unmodifiable(_feedback);

  RouteFeedback? feedbackForRun(String runId) {
    for (final item in _feedback) {
      if (item.runId == runId) return item;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.runs);
    if (raw != null) {
      _history = RunSummary.listFromJson(raw);
    }
    final feedbackRaw = prefs.getString(StorageKeys.routeFeedback);
    if (feedbackRaw != null) {
      _feedback = RouteFeedback.listFromJson(feedbackRaw);
    }
    await _pendingStore.purgeStaleDetails();
    notifyListeners();
  }

  /// 클라우드 원본을 우선하되, 실패한 pending 업로드를 먼저 비운다.
  Future<void> syncWithCloud() async {
    if (!await _cloudUploadEnabled()) return;
    final sync = _cloud;
    if (!sync.isReady) return;

    await retryPendingUploads();

    final localIds = _history.map((r) => r.id).toSet();
    final missing = await sync.fetchMissingRuns(localIds);
    if (missing.isNotEmpty) {
      _history = [..._history, ...missing]
        ..sort((a, b) => b.date.compareTo(a.date));
      await _persist();
      notifyListeners();
    }
  }

  Future<void> retryPendingUploads() async {
    if (!await _cloudUploadEnabled()) return;
    final sync = _cloud;
    if (!sync.isReady) return;

    for (final summary in await _pendingStore.loadSummaries()) {
      if (await sync.uploadRun(summary)) {
        await _pendingStore.removeSummary(summary.id);
      }
    }

    for (final detail in await _pendingStore.loadDetails()) {
      if (await sync.uploadRunDetail(detail)) {
        await _pendingStore.removeDetail(detail.runId);
      }
    }

    for (final item in await _pendingStore.loadFeedback()) {
      if (await sync.uploadRouteFeedback(item)) {
        await _pendingStore.removeFeedback(item.id);
      }
    }
  }

  Future<RunSummary> save(RunSession session) async {
    final path = session.gpsPath;
    final LatLng? startPt = path.isNotEmpty ? path.first : null;
    final LatLng? endPt = path.length > 1 ? path.last : null;
    final routeDistance = session.route?.distanceKm;
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final analytics = RunTelemetryDetail.fromSession(runId, session).analytics;
    final routeCompletionPct = routeCompletionPercent(
      drivenKm: session.distanceKm,
      routeDistanceKm: routeDistance,
    );

    final summary = RunSummary(
      id: runId,
      date: session.startTime,
      distanceKm: session.distanceKm,
      durationSeconds: session.duration.inSeconds,
      maxSpeedKmh: session.maxSpeedKmh,
      avgSpeedKmh: session.avgSpeedKmh,
      routeName: session.route == null
          ? session.routeName
          : routeDisplayName(session.route!),
      routeId: session.route?.id,
      weatherEmoji: session.weatherEmoji,
      tempDisplay: session.tempDisplay,
      maxLateralG: session.maxLateralG > 0 ? session.maxLateralG : null,
      maxLongitudinalG: session.maxLonG > 0 ? session.maxLonG : null,
      sharpCornersCount: session.sharpCorners.length,
      telemetrySampleCount: session.telemetrySamples.length,
      windingSeconds: session.driveModeSeconds['winding'] ?? 0,
      sportSeconds:
          (session.driveModeSeconds['sport'] ?? 0) +
          (session.driveModeSeconds['attack'] ?? 0),
      revvScore: (analytics['revvScore'] as num?)?.toInt(),
      windingSamplePct: (analytics['windingSamplePct'] as num?)?.toDouble(),
      p95LateralG: (analytics['p95AbsLateralG'] as num?)?.toDouble(),
      brakingEventCount: (analytics['brakingEventCount'] as num?)?.toInt() ?? 0,
      accelerationEventCount:
          (analytics['accelerationEventCount'] as num?)?.toInt() ?? 0,
      smoothnessScore: (analytics['smoothnessScore'] as num?)?.toInt(),
      routeDistanceKm: routeDistance,
      routeCompletionPct: routeCompletionPct,
      startPoint: startPt,
      endPoint: endPt,
    );

    _history.insert(0, summary);
    await _persist();
    notifyListeners();

    final cloudUploadEnabled = await _cloudUploadEnabled();
    if (cloudUploadEnabled) {
      await _pendingStore.saveSummary(summary);
      unawaited(_uploadSummaryAndClearPending(summary));
    }

    final sync = _cloud;
    if (cloudUploadEnabled && session.route?.id != null) {
      unawaited(sync.recordRouteRun(session.route!.id));
    }

    return summary;
  }

  Future<void> _uploadSummaryAndClearPending(RunSummary summary) async {
    final sync = _cloud;
    if (await sync.uploadRun(summary)) {
      await _pendingStore.removeSummary(summary.id);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.runs, RunSummary.listToJson(_history));
  }

  Future<void> saveDetail(RunTelemetryDetail detail) async {
    if (!await _cloudUploadEnabled()) {
      await _saveLocalDetail(detail);
      return;
    }

    await _pendingStore.saveDetail(detail);
    final sync = _cloud;
    if (await sync.uploadRunDetail(detail)) {
      await _pendingStore.removeDetail(detail.runId);
    }
    await _saveLocalDetail(detail);
  }

  Future<void> _saveLocalDetail(RunTelemetryDetail detail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${StorageKeys.runDetailPrefix}${detail.runId}',
      jsonEncode(detail.toJson()),
    );
  }

  Future<void> saveFeedback(RouteFeedback feedback) async {
    final existingIndex = _feedback.indexWhere(
      (item) => item.runId == feedback.runId,
    );
    if (existingIndex >= 0) {
      _feedback[existingIndex] = feedback;
    } else {
      _feedback.insert(0, feedback);
    }
    await _persistFeedback();
    notifyListeners();

    if (await _cloudUploadEnabled()) {
      await _pendingStore.saveFeedback(feedback);
      final sync = _cloud;
      if (await sync.uploadRouteFeedback(feedback)) {
        await _pendingStore.removeFeedback(feedback.id);
      }
    }
  }

  Future<void> _persistFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StorageKeys.routeFeedback,
      RouteFeedback.listToJson(_feedback),
    );
  }

  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    if (!await _cloudUploadEnabled()) return _loadLocalDetail(runId);

    final remote = await _cloud.fetchRunDetail(runId);
    if (remote != null) {
      await _pendingStore.removeDetail(runId);
      return remote;
    }

    final pending = await _pendingStore.loadDetail(runId);
    if (pending != null) return pending;

    return _loadLocalDetail(runId);
  }

  Future<RunTelemetryDetail?> _loadLocalDetail(String runId) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      '${StorageKeys.runDetailPrefix}$runId',
    );
    if (raw != null) {
      try {
        return RunTelemetryDetail.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[RunHistory] detail decode failed: $e');
      }
    }
    return null;
  }

  Future<bool> deleteAllRunData() async {
    final cloudUploadEnabled = await _cloudUploadEnabled();
    if (cloudUploadEnabled) {
      final sync = _cloud;
      if (!sync.isReady) return false;
      final remoteDeleted = await sync.deleteUserRunData();
      if (!remoteDeleted) return false;
    }

    _history = [];
    _feedback = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.runs);
    await prefs.remove(StorageKeys.routeFeedback);
    await _clearLocalDetails(prefs);
    await _pendingStore.clearAll();
    notifyListeners();
    return true;
  }

  Future<void> _clearLocalDetails(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(StorageKeys.runDetailPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> purgePendingUploads() async {
    await _pendingStore.clearAll();
  }

  Future<bool> _cloudUploadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.cloudRunStorageEnabled) ?? false;
  }

  int visitCount(String? routeId) {
    if (routeId == null) return 1;
    return _history.where((s) => s.routeId == routeId).length;
  }

  double get totalDistanceKm =>
      _history.fold(0, (sum, s) => sum + s.distanceKm);

  int get totalRuns => _history.length;

  double? get bestMaxG {
    final gs = _history
        .map((s) => s.peakG)
        .where((g) => g != null && g > 0)
        .cast<double>()
        .toList();
    if (gs.isEmpty) return null;
    return gs.reduce((a, b) => a > b ? a : b);
  }
}
