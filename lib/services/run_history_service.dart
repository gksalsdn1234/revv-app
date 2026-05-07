import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/storage_keys.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import 'supabase_service.dart';

class RunHistoryService extends ChangeNotifier {
  List<RunSummary> _history = [];
  List<RouteFeedback> _feedback = [];
  List<RunSummary> get history => List.unmodifiable(_history);
  List<RouteFeedback> get feedback => List.unmodifiable(_feedback);

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
    notifyListeners();
  }

  /// 로컬에 없는 클라우드 런을 가져와 병합 + 로컬에 없는 런을 클라우드에도 업로드
  Future<void> syncWithCloud() async {
    final sync = SupabaseService();
    if (!sync.isReady) return;

    final localIds = _history.map((r) => r.id).toSet();
    final missing = await sync.fetchMissingRuns(localIds);
    if (missing.isNotEmpty) {
      _history = [..._history, ...missing]
        ..sort((a, b) => b.date.compareTo(a.date));
      await _persist();
      notifyListeners();
    }

    final cloudIds = await _fetchCloudIds(sync);
    final localOnly = _history.where((r) => !cloudIds.contains(r.id)).toList();
    if (localOnly.isNotEmpty) {
      await sync.uploadAll(localOnly);
    }
  }

  Future<Set<String>> _fetchCloudIds(SupabaseService sync) async {
    return sync.fetchRunIds();
  }

  Future<RunSummary> save(RunSession session) async {
    final path = session.gpsPath;
    final LatLng? startPt = path.isNotEmpty ? path.first : null;
    final LatLng? endPt = path.length > 1 ? path.last : null;

    final summary = RunSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: session.startTime,
      distanceKm: session.distanceKm,
      durationSeconds: session.duration.inSeconds,
      maxSpeedKmh: session.maxSpeedKmh,
      avgSpeedKmh: session.avgSpeedKmh,
      routeName: session.routeName,
      routeId: session.route?.id,
      weatherEmoji: session.weatherEmoji,
      tempDisplay: session.tempDisplay,
      maxLateralG: session.maxLateralG > 0 ? session.maxLateralG : null,
      sharpCornersCount: session.sharpCorners.length,
      startPoint: startPt,
      endPoint: endPt,
    );

    _history.insert(0, summary);
    await _persist();
    notifyListeners();

    final sync = SupabaseService();
    sync.uploadRun(summary);
    if (session.route?.id != null) {
      sync.recordRouteRun(session.route!.id);
    }

    return summary;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.runs, RunSummary.listToJson(_history));
  }

  Future<void> saveDetail(RunTelemetryDetail detail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${StorageKeys.runDetailPrefix}${detail.runId}',
      jsonEncode(detail.toJson()),
    );
    SupabaseService().uploadRunDetail(detail);
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
    SupabaseService().uploadRouteFeedback(feedback);
  }

  Future<void> _persistFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StorageKeys.routeFeedback,
      RouteFeedback.listToJson(_feedback),
    );
  }

  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${StorageKeys.runDetailPrefix}$runId');
    if (raw != null) {
      try {
        return RunTelemetryDetail.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('[RunHistory] detail decode failed: $e');
      }
    }
    final remote = await SupabaseService().fetchRunDetail(runId);
    if (remote != null) {
      await prefs.setString(
        '${StorageKeys.runDetailPrefix}$runId',
        jsonEncode(remote.toJson()),
      );
    }
    return remote;
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
        .where((s) => s.maxLateralG != null && s.maxLateralG! > 0)
        .map((s) => s.maxLateralG!)
        .toList();
    if (gs.isEmpty) return null;
    return gs.reduce((a, b) => a > b ? a : b);
  }
}
