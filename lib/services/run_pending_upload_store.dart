import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/route_feedback.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import 'secure_session_store.dart';

class RunPendingUploadStore {
  static const defaultDetailTtl = Duration(days: 14);

  const RunPendingUploadStore({
    SecureStringStore detailStore = const FlutterSecureStringStore(),
  }) : _detailStore = detailStore;

  final SecureStringStore _detailStore;

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
    await _migrateLegacyDetails();
    await _detailStore.write(
      _detailKey(detail.runId),
      jsonEncode(detail.toJson()),
    );
    final ids = await _loadDetailIds();
    ids.add(detail.runId);
    await _saveDetailIds(ids);
  }

  Future<void> removeDetail(String runId) async {
    final ids = await _loadDetailIds();
    ids.remove(runId);
    await _saveDetailIds(ids);
    await _detailStore.delete(_detailKey(runId));
    final legacyMap = await _loadMap(StorageKeys.pendingRunDetails);
    if (legacyMap.remove(runId) != null) {
      await _saveMap(StorageKeys.pendingRunDetails, legacyMap);
    }
    await (await SharedPreferences.getInstance()).remove(
      '${StorageKeys.runDetailPrefix}$runId',
    );
  }

  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    await _migrateLegacyDetails();
    final raw = await _detailStore.read(_detailKey(runId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final detail = RunTelemetryDetail.fromJson(
          decoded.cast<String, dynamic>(),
        );
        if (_isStaleDetail(detail)) {
          await removeDetail(runId);
          return null;
        }
        return detail;
      }
    } on Object {
      await removeDetail(runId);
    }
    return null;
  }

  Future<List<RunTelemetryDetail>> loadDetails() async {
    await _migrateLegacyDetails();
    await purgeStaleDetails();
    final ids = await _loadDetailIds();
    final details = <RunTelemetryDetail>[];
    for (final id in ids) {
      final detail = await loadDetail(id);
      if (detail != null) {
        details.add(detail);
      }
    }
    return details;
  }

  Future<int> purgeStaleDetails({
    DateTime? now,
    Duration maxAge = defaultDetailTtl,
  }) async {
    await _migrateLegacyDetails();
    final reference = (now ?? DateTime.now()).toUtc();
    final ids = await _loadDetailIds();
    var removed = 0;

    for (final id in ids.toList()) {
      final raw = await _detailStore.read(_detailKey(id));
      var shouldRemove = raw == null || raw.isEmpty;
      if (!shouldRemove) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final detail = RunTelemetryDetail.fromJson(
              decoded.cast<String, dynamic>(),
            );
            shouldRemove = _isStaleDetail(
              detail,
              now: reference,
              maxAge: maxAge,
            );
          } else {
            shouldRemove = true;
          }
        } on Object {
          shouldRemove = true;
        }
      }

      if (shouldRemove) {
        ids.remove(id);
        await _detailStore.delete(_detailKey(id));
        removed += 1;
      }
    }

    if (removed > 0) {
      await _saveDetailIds(ids);
    }
    return removed;
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
    await _migrateLegacyDetails();
    await purgeStaleDetails();
    final details = await _loadDetailIds();
    final feedback = await _loadMap(StorageKeys.pendingRouteFeedback);
    return summaries.isNotEmpty || details.isNotEmpty || feedback.isNotEmpty;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final detailIds = await _loadDetailIds();
    for (final id in detailIds) {
      await _detailStore.delete(_detailKey(id));
    }
    await prefs.remove(StorageKeys.pendingRunSummaries);
    await prefs.remove(StorageKeys.pendingRunDetails);
    await prefs.remove(StorageKeys.pendingRunDetailsIndex);
    await prefs.remove(StorageKeys.pendingRouteFeedback);
    for (final key in prefs.getKeys()) {
      if (key.startsWith(StorageKeys.runDetailPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<Set<String>> _loadDetailIds() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      StorageKeys.pendingRunDetailsIndex,
    );
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<String>().toSet();
    }
    return <String>{};
  }

  Future<void> _saveDetailIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(StorageKeys.pendingRunDetailsIndex);
    } else {
      await prefs.setString(
        StorageKeys.pendingRunDetailsIndex,
        jsonEncode(ids.toList()..sort()),
      );
    }
  }

  Future<void> _migrateLegacyDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _loadDetailIds();
    var changed = false;

    final legacyMap = await _loadMap(StorageKeys.pendingRunDetails);
    for (final entry in legacyMap.entries) {
      final id = entry.key;
      final item = entry.value;
      if (item is Map) {
        final key = _detailKey(id);
        if (await _detailStore.read(key) == null) {
          await _detailStore.write(
            key,
            jsonEncode(item.cast<String, dynamic>()),
          );
        }
        ids.add(id);
        changed = true;
      }
    }
    if (legacyMap.isNotEmpty) {
      await prefs.remove(StorageKeys.pendingRunDetails);
    }

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(StorageKeys.runDetailPrefix)) continue;
      final id = key.substring(StorageKeys.runDetailPrefix.length);
      final raw = prefs.getString(key);
      if (id.isNotEmpty && raw != null && raw.isNotEmpty) {
        final detailKey = _detailKey(id);
        if (await _detailStore.read(detailKey) == null) {
          await _detailStore.write(detailKey, raw);
        }
        ids.add(id);
        changed = true;
      }
      await prefs.remove(key);
    }

    if (changed) {
      await _saveDetailIds(ids);
    }
  }

  static String _detailKey(String runId) =>
      '${StorageKeys.pendingRunDetailSecurePrefix}$runId';

  static bool _isStaleDetail(
    RunTelemetryDetail detail, {
    DateTime? now,
    Duration maxAge = defaultDetailTtl,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    final cutoff = reference.subtract(maxAge);
    return detail.createdAt.toUtc().isBefore(cutoff);
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
