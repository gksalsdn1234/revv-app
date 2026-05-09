import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/route_feedback.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';

class RunPendingUploadStore {
  const RunPendingUploadStore();

  Future<void> saveSummary(RunSummary summary) async {
    final map = await _loadMap(StorageKeys.pendingRunSummaries);
    map[summary.id] = summary.toJson();
    await _saveMap(StorageKeys.pendingRunSummaries, map);
  }

  Future<void> removeSummary(String runId) async {
    final map = await _loadMap(StorageKeys.pendingRunSummaries);
    map.remove(runId);
    await _saveMap(StorageKeys.pendingRunSummaries, map);
  }

  Future<List<RunSummary>> loadSummaries() async {
    final map = await _loadMap(StorageKeys.pendingRunSummaries);
    return map.values
        .whereType<Map>()
        .map((item) => RunSummary.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<void> saveDetail(RunTelemetryDetail detail) async {
    final map = await _loadMap(StorageKeys.pendingRunDetails);
    map[detail.runId] = detail.toJson();
    await _saveMap(StorageKeys.pendingRunDetails, map);
  }

  Future<void> removeDetail(String runId) async {
    final map = await _loadMap(StorageKeys.pendingRunDetails);
    map.remove(runId);
    await _saveMap(StorageKeys.pendingRunDetails, map);
    await (await SharedPreferences.getInstance()).remove(
      '${StorageKeys.runDetailPrefix}$runId',
    );
  }

  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    final map = await _loadMap(StorageKeys.pendingRunDetails);
    final item = map[runId];
    if (item is Map) {
      return RunTelemetryDetail.fromJson(item.cast<String, dynamic>());
    }
    return null;
  }

  Future<List<RunTelemetryDetail>> loadDetails() async {
    final map = await _loadMap(StorageKeys.pendingRunDetails);
    return map.values
        .whereType<Map>()
        .map(
          (item) => RunTelemetryDetail.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
  }

  Future<void> saveFeedback(RouteFeedback feedback) async {
    final map = await _loadMap(StorageKeys.pendingRouteFeedback);
    map[feedback.id] = feedback.toJson();
    await _saveMap(StorageKeys.pendingRouteFeedback, map);
  }

  Future<void> removeFeedback(String feedbackId) async {
    final map = await _loadMap(StorageKeys.pendingRouteFeedback);
    map.remove(feedbackId);
    await _saveMap(StorageKeys.pendingRouteFeedback, map);
  }

  Future<List<RouteFeedback>> loadFeedback() async {
    final map = await _loadMap(StorageKeys.pendingRouteFeedback);
    return map.values
        .whereType<Map>()
        .map((item) => RouteFeedback.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<bool> hasPending() async {
    final summaries = await _loadMap(StorageKeys.pendingRunSummaries);
    final details = await _loadMap(StorageKeys.pendingRunDetails);
    final feedback = await _loadMap(StorageKeys.pendingRouteFeedback);
    return summaries.isNotEmpty || details.isNotEmpty || feedback.isNotEmpty;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.pendingRunSummaries);
    await prefs.remove(StorageKeys.pendingRunDetails);
    await prefs.remove(StorageKeys.pendingRouteFeedback);
    for (final key in prefs.getKeys()) {
      if (key.startsWith(StorageKeys.runDetailPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<Map<String, dynamic>> _loadMap(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Future<void> _saveMap(String key, Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    if (map.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(map));
    }
  }
}
