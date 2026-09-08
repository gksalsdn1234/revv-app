import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/storage_keys.dart';
import 'route_loading_policy.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import '../ui/run_report_metrics.dart';
import 'drive_dynamics_tracker.dart';
import 'exploration_service.dart';
import 'run_pending_upload_store.dart';
import 'run_local_store.dart';
import 'supabase_service.dart';

abstract class RunHistoryCloudClient {
  bool get isReady;
  String? get uid;
  Future<bool> uploadRun(RunSummary summary);
  Future<bool> uploadRunDetail(RunTelemetryDetail detail);
  Future<bool> uploadRouteFeedback(RouteFeedback feedback);
  Future<bool> uploadTelemetrySummary(
    String runId,
    DriveDynamicsSummary summary,
  );
  Future<List<RunSummary>?> fetchMissingRuns(Set<String> localIds);
  Future<Set<String>?> fetchRunIds();
  Future<RunTelemetryDetail?> fetchRunDetail(String runId);
  Future<bool> recordRouteRun(String? routeId, String runId);
  Future<bool> deleteUserRunData();
}

class SupabaseRunHistoryCloudClient implements RunHistoryCloudClient {
  SupabaseRunHistoryCloudClient({SupabaseService? service})
    : _service = service ?? SupabaseService();

  final SupabaseService _service;

  @override
  bool get isReady => _service.isReady;

  @override
  String? get uid => _service.uid;

  @override
  Future<bool> uploadRun(RunSummary summary) => _service.uploadRun(summary);

  @override
  Future<bool> uploadRunDetail(RunTelemetryDetail detail) =>
      _service.uploadRunDetail(detail);

  @override
  Future<bool> uploadRouteFeedback(RouteFeedback feedback) =>
      _service.uploadRouteFeedback(feedback);

  @override
  Future<bool> uploadTelemetrySummary(
    String runId,
    DriveDynamicsSummary summary,
  ) => _service.saveTelemetrySummary(runId, summary);

  @override
  Future<List<RunSummary>?> fetchMissingRuns(Set<String> localIds) =>
      _service.fetchMissingRuns(localIds);

  @override
  Future<Set<String>?> fetchRunIds() => _service.fetchRunIds();

  @override
  Future<RunTelemetryDetail?> fetchRunDetail(String runId) =>
      _service.fetchRunDetail(runId);

  @override
  Future<bool> recordRouteRun(String? routeId, String runId) =>
      _service.recordRouteRun(routeId, runId);

  @override
  Future<bool> deleteUserRunData() => _service.deleteUserRunData();
}

enum CloudHistorySyncState { local, syncing, synced, error }

class RunHistoryService extends ChangeNotifier {
  static final _sessionIds = Expando<String>();
  RunHistoryService({
    RunPendingUploadStore pendingStore = const RunPendingUploadStore(),
    RunHistoryCloudClient? cloudClient,
    ExplorationService? exploration,
    RunLocalStore? localStore,
  }) : _pendingStore = pendingStore,
       _cloud = cloudClient ?? SupabaseRunHistoryCloudClient(),
       _exploration = exploration {
    _localStore =
        localStore ?? createDefaultRunLocalStore(ownerUid: _cloud.uid);
  }

  final RunPendingUploadStore _pendingStore;
  final RunHistoryCloudClient _cloud;
  final ExplorationService? _exploration;
  late final RunLocalStore _localStore;
  Future<void> _cloudOperations = Future.value();
  List<RunSummary> _history = [];
  List<RouteFeedback> _feedback = [];
  CloudHistorySyncState _cloudSyncState = CloudHistorySyncState.local;
  List<RunSummary> get history => List.unmodifiable(_history);
  List<RouteFeedback> get feedback => List.unmodifiable(_feedback);
  CloudHistorySyncState get cloudSyncState => _cloudSyncState;

  RouteFeedback? feedbackForRun(String runId) {
    for (final item in _feedback) {
      if (item.runId == runId) return item;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingAccountDeletionUid = prefs.getString(
      StorageKeys.pendingAccountDeletionUid,
    );
    final confirmedAccountDeletionUid = prefs.getString(
      StorageKeys.confirmedAccountDeletionUid,
    );
    if (pendingAccountDeletionUid != null &&
        pendingAccountDeletionUid == confirmedAccountDeletionUid) {
      await clearLocalAfterAccountDeletion(pendingAccountDeletionUid);
      return;
    }
    _history = await _localStore.loadRuns();
    _feedback = await _localStore.loadFeedback();
    await _pendingStore.purgeStaleDetails();
    notifyListeners();
  }

  /// 클라우드 원본을 우선하되, 실패한 pending 업로드를 먼저 비운다.
  Future<bool> syncWithCloud({bool repairDetails = false}) =>
      _enqueueCloudOperation(() async {
        _cloudSyncState = CloudHistorySyncState.syncing;
        notifyListeners();
        try {
          final synced = await _syncWithCloud(repairDetails: repairDetails);
          _cloudSyncState = synced
              ? CloudHistorySyncState.synced
              : CloudHistorySyncState.error;
          notifyListeners();
          return synced;
        } catch (_) {
          _cloudSyncState = CloudHistorySyncState.error;
          notifyListeners();
          return false;
        }
      });

  Future<bool> _syncWithCloud({required bool repairDetails}) async {
    final sync = _cloud;
    final prefs = await SharedPreferences.getInstance();
    final pendingDeletionUids =
        (prefs.getStringList(StorageKeys.pendingRunDataDeletionUids) ??
                const <String>[])
            .toSet();
    if (sync.uid case final uid? when pendingDeletionUids.contains(uid)) {
      if (!sync.isReady || !await sync.deleteUserRunData()) return false;
      pendingDeletionUids.remove(uid);
      await prefs.setStringList(
        StorageKeys.pendingRunDataDeletionUids,
        pendingDeletionUids.toList()..sort(),
      );
    }
    if (!await _cloudUploadEnabled()) {
      _cloudSyncState = CloudHistorySyncState.local;
      return true;
    }
    if (!sync.isReady) return false;
    if (!await _claimCloudDataOwner(sync.uid)) {
      await _pendingStore.clearAll();
      return false;
    }

    await _retryPendingUploads();

    final remoteIds = await sync.fetchRunIds();
    if (remoteIds == null) return false;
    for (final summary in _history) {
      if (!remoteIds.contains(summary.id)) {
        await _pendingStore.saveSummary(summary);
        await _uploadSummaryAndClearPending(summary);
      }
      final detail = await _loadLocalDetail(summary.id);
      if (detail != null) {
        await _uploadDirtyDetail(
          detail,
          force: repairDetails || !remoteIds.contains(summary.id),
        );
      }
    }
    for (final item in _feedback) {
      await _pendingStore.saveFeedback(item);
      if (await sync.uploadRouteFeedback(item)) {
        await _pendingStore.removeFeedback(item.id);
      }
    }

    final localIds = _history.map((r) => r.id).toSet();
    final missing = await sync.fetchMissingRuns(localIds);
    if (missing == null) return false;
    if (missing.isNotEmpty) {
      _history = [..._history, ...missing]
        ..sort((a, b) => b.date.compareTo(a.date));
      await _persist();
      notifyListeners();
    }
    return !await _pendingStore.hasPending();
  }

  Future<void> retryPendingUploads() =>
      _enqueueCloudOperation(_retryPendingUploads);

  Future<void> _retryPendingUploads() async {
    if (!await _cloudUploadEnabled()) return;
    final sync = _cloud;
    if (!sync.isReady) return;
    if (!await _claimCloudDataOwner(sync.uid)) return;

    for (final summary in await _pendingStore.loadSummaries()) {
      await _uploadSummaryAndClearPending(summary);
    }

    for (final detail in await _pendingStore.loadDetails()) {
      await _uploadDirtyDetail(detail);
    }

    for (final item in await _pendingStore.loadFeedback()) {
      if (await sync.uploadRouteFeedback(item)) {
        await _pendingStore.removeFeedback(item.id);
      }
    }
  }

  Future<RunSummary> save(RunSession session) =>
      _saveSessionData(session, includeDetail: false);

  Future<RunSummary> saveSession(RunSession session) =>
      _saveSessionData(session, includeDetail: true);

  Future<RunSummary> _saveSessionData(
    RunSession session, {
    required bool includeDetail,
  }) async {
    final path = session.gpsPath;
    final LatLng? startPt = path.isNotEmpty ? path.first : null;
    final LatLng? endPt = path.length > 1 ? path.last : null;
    final routeDistance = session.route?.distanceKm;
    // Real sessions carry a UUID through recording and recovery. Older callers
    // without one keep an ID for retries of that same session object.
    final runId = session.runId ?? (_sessionIds[session] ??= const Uuid().v4());
    final detail = RunTelemetryDetail.fromSession(runId, session);
    final analytics = detail.analytics;
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

    if (includeDetail) {
      await _localStore.saveRunWithDetail(summary, detail);
    } else {
      await _localStore.saveRuns([summary]);
    }
    _history.removeWhere((run) => run.id == summary.id);
    _history.insert(0, summary);
    try {
      await _exploration?.recordSession(session);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[RunHistory] exploration save failed: $error');
      }
    }
    notifyListeners();

    // The local transaction is the save boundary. Network/queue failures must
    // neither delay it nor turn a persisted drive into a failed save.
    bool uploadEnabled;
    try {
      uploadEnabled = await _cloudUploadEnabled();
    } catch (_) {
      return summary;
    }
    if (!uploadEnabled) return summary;
    unawaited(
      _enqueueCloudOperation(() async {
        if (!await _cloudUploadEnabled() ||
            !await _claimCloudDataOwner(_cloud.uid)) {
          return;
        }
        await _pendingStore.saveSummary(summary);
        if (includeDetail) await _pendingStore.saveDetail(detail);
        await _uploadSummaryAndClearPending(summary);
        await _cloud.uploadTelemetrySummary(
          summary.id,
          DriveDynamicsTracker.summarizeSamples(session.telemetrySamples),
        );
        if (includeDetail) await _uploadDirtyDetail(detail);
      }).catchError((Object error) {
        if (kDebugMode) {
          debugPrint('[RunHistory] background sync deferred: $error');
        }
      }),
    );

    return summary;
  }

  Future<bool> _uploadSummaryAndClearPending(RunSummary summary) async {
    final sync = _cloud;
    if (!await sync.uploadRun(summary)) return false;
    if (summary.routeId != null &&
        !summary.routeId!.startsWith(RevvRoute.chainRouteIdPrefix) &&
        !await sync.recordRouteRun(summary.routeId, summary.id)) {
      return false;
    }
    await _pendingStore.removeSummary(summary.id);
    return true;
  }

  Future<void> _persist() async {
    await _localStore.saveRuns(_history);
  }

  Future<void> saveDetail(RunTelemetryDetail detail) async {
    await _saveLocalDetail(detail);
    if (!await _cloudUploadEnabled() ||
        !await _claimCloudDataOwner(_cloud.uid)) {
      return;
    }
    await _uploadDetailAndClearPending(detail);
  }

  Future<void> _uploadDetailAndClearPending(RunTelemetryDetail detail) async {
    await _pendingStore.saveDetail(detail);
    await _enqueueCloudOperation(() => _uploadDirtyDetail(detail));
  }

  String _detailDigest(RunTelemetryDetail detail) {
    final payload = Map<String, dynamic>.of(detail.toJson())
      ..remove('createdAt');
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  Map<String, String> _readDetailReceipts(SharedPreferences prefs) {
    try {
      return (jsonDecode(
                prefs.getString(StorageKeys.uploadedRunDetailDigests) ?? '{}',
              )
              as Map)
          .cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  Future<bool> _uploadDirtyDetail(
    RunTelemetryDetail detail, {
    bool force = false,
  }) async {
    final uid = _cloud.uid;
    if (uid == null ||
        !await _cloudUploadEnabled() ||
        !await _claimCloudDataOwner(uid)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = '$uid/${detail.runId}';
    final digest = _detailDigest(detail);
    if (!force && _readDetailReceipts(prefs)[key] == digest) {
      await _pendingStore.removeDetail(detail.runId);
      return true;
    }
    await _pendingStore.saveDetail(detail);
    // Keep mutations serialized through actual completion: abandoning an
    // upload Future could let it finish after a queued account/data deletion.
    final uploaded = await _cloud.uploadRunDetail(detail);
    if (!uploaded || _cloud.uid != uid) return false;
    final receipts = _readDetailReceipts(prefs)..[key] = digest;
    await prefs.setString(
      StorageKeys.uploadedRunDetailDigests,
      jsonEncode(receipts),
    );
    await _pendingStore.removeDetail(detail.runId);
    return true;
  }

  Future<void> _saveLocalDetail(RunTelemetryDetail detail) async {
    await _localStore.saveDetail(detail);
  }

  Future<void> saveFeedback(RouteFeedback feedback) async {
    await _persistFeedback(feedback);
    final existingIndex = _feedback.indexWhere(
      (item) => item.runId == feedback.runId,
    );
    if (existingIndex >= 0) {
      _feedback[existingIndex] = feedback;
    } else {
      _feedback.insert(0, feedback);
    }
    notifyListeners();

    if (await _cloudUploadEnabled() && await _claimCloudDataOwner(_cloud.uid)) {
      await _pendingStore.saveFeedback(feedback);
      final sync = _cloud;
      if (await _enqueueCloudOperation(
        () => sync.uploadRouteFeedback(feedback),
      )) {
        await _pendingStore.removeFeedback(feedback.id);
      }
    }
  }

  Future<void> _persistFeedback(RouteFeedback feedback) =>
      _localStore.saveFeedback(feedback);

  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    final local = await _loadLocalDetail(runId);
    if (local != null) return local;
    final pending = await _pendingStore.loadDetail(runId);
    if (pending != null) return pending;
    if (!await _cloudUploadEnabled() ||
        !await _claimCloudDataOwner(_cloud.uid)) {
      return _loadLocalDetail(runId);
    }

    final remote = await _cloud
        .fetchRunDetail(runId)
        .timeout(const Duration(seconds: 8));
    if (remote != null) {
      await _localStore.saveDetail(remote);
      return remote;
    }
    return null;
  }

  Future<RunTelemetryDetail?> _loadLocalDetail(String runId) async {
    return _localStore.loadDetail(runId);
  }

  Future<bool> deleteAllRunData() async {
    final prefs = await SharedPreferences.getInstance();
    final sync = _cloud;
    final deletionUid = sync.uid;
    if (deletionUid != null) {
      final pendingUids =
          (prefs.getStringList(StorageKeys.pendingRunDataDeletionUids) ??
                  const <String>[])
              .toSet()
            ..add(deletionUid);
      await prefs.setStringList(
        StorageKeys.pendingRunDataDeletionUids,
        pendingUids.toList()..sort(),
      );
    }
    final remoteDeleted = await _enqueueCloudOperation(() async {
      if (!sync.isReady || deletionUid == null || deletionUid != sync.uid) {
        return false;
      }
      return sync.deleteUserRunData();
    });
    if (remoteDeleted) {
      final pendingUids =
          (prefs.getStringList(StorageKeys.pendingRunDataDeletionUids) ??
                  const <String>[])
              .toSet()
            ..remove(deletionUid);
      await prefs.setStringList(
        StorageKeys.pendingRunDataDeletionUids,
        pendingUids.toList()..sort(),
      );
    }
    final exploration = _exploration;
    await exploration?.deleteEverywhere();
    final cloudUploadEnabled = await _cloudUploadEnabled();

    _history = [];
    _feedback = [];
    await _localStore.clearAll();
    await _pendingStore.clearAll();
    await prefs.remove(StorageKeys.cloudRunStorageOwnerUid);
    await prefs.remove(StorageKeys.uploadedRunDetailDigests);
    notifyListeners();
    return remoteDeleted || !cloudUploadEnabled;
  }

  Future<void> markAccountDeletionPending(String uid) async {
    await (await SharedPreferences.getInstance()).setString(
      StorageKeys.pendingAccountDeletionUid,
      uid,
    );
  }

  Future<void> cancelAccountDeletionPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.pendingAccountDeletionUid);
    await prefs.remove(StorageKeys.confirmedAccountDeletionUid);
  }

  Future<void> clearLocalAfterAccountDeletion(String? deletedUid) async {
    final prefs = await SharedPreferences.getInstance();
    _history = [];
    _feedback = [];
    _cloudSyncState = CloudHistorySyncState.local;
    await _localStore.clearAll();
    await _pendingStore.clearAll();
    await prefs.remove(StorageKeys.cloudRunStorageOwnerUid);
    await prefs.remove(StorageKeys.uploadedRunDetailDigests);
    if (deletedUid != null) {
      final pendingRunUids =
          (prefs.getStringList(StorageKeys.pendingRunDataDeletionUids) ??
                  const <String>[])
              .toSet()
            ..remove(deletedUid);
      await prefs.setStringList(
        StorageKeys.pendingRunDataDeletionUids,
        pendingRunUids.toList()..sort(),
      );
      final pendingExplorationUids =
          (prefs.getStringList(StorageKeys.pendingExplorationDeletionUids) ??
                  const <String>[])
              .toSet()
            ..remove(deletedUid);
      await prefs.setStringList(
        StorageKeys.pendingExplorationDeletionUids,
        pendingExplorationUids.toList()..sort(),
      );
    }
    await _exploration?.reset();
    await prefs.remove(StorageKeys.pendingAccountDeletionUid);
    await prefs.remove(StorageKeys.confirmedAccountDeletionUid);
    notifyListeners();
  }

  Future<T> _enqueueCloudOperation<T>(Future<T> Function() action) {
    final result = _cloudOperations.then((_) => action());
    _cloudOperations = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> purgePendingUploads() async {
    await _pendingStore.clearAll();
    _cloudSyncState = CloudHistorySyncState.local;
    notifyListeners();
  }

  Future<bool> _cloudUploadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.cloudRunStorageEnabled) ?? false;
  }

  Future<bool> _claimCloudDataOwner(String? currentUid) async {
    if (currentUid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final ownerUid = prefs.getString(StorageKeys.cloudRunStorageOwnerUid);
    if (ownerUid == null) {
      await prefs.setString(StorageKeys.cloudRunStorageOwnerUid, currentUid);
      return true;
    }
    return ownerUid == currentUid;
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
