import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import '../models/exploration_cell.dart';
import '../models/revv_route.dart';
import '../models/run_session.dart';

typedef ExplorationClock = DateTime Function();
typedef ExplorationCloudSyncEnabled = bool Function();

abstract class ExplorationCloudClient {
  bool get isReady;
  String? get uid;
  Future<Map<String, DateTime>> fetchExploredCells();
  Future<bool> upsertExploredCells(Map<String, DateTime> cells);
  Future<bool> deleteExploredCells();
}

class ExplorationService extends ChangeNotifier {
  ExplorationService({
    ExplorationClock? clock,
    ExplorationCloudClient? cloud,
    ExplorationCloudSyncEnabled? cloudSyncEnabled,
  }) : _clock = clock ?? DateTime.now,
       _cloud = cloud,
       _cloudSyncEnabled = cloudSyncEnabled ?? _alwaysEnableCloudSync;

  static const int currentVersion = 1;

  final ExplorationClock _clock;
  final ExplorationCloudClient? _cloud;
  final ExplorationCloudSyncEnabled _cloudSyncEnabled;
  final Map<String, DateTime> _exploredAt = {};
  Future<void> _cloudOperations = Future.value();
  int _generation = 0;
  String? _ownerUid;

  static bool _alwaysEnableCloudSync() => true;

  Set<String> get exploredCellIds => Set.unmodifiable(_exploredAt.keys);

  DateTime? exploredAt(String cellId) => _exploredAt[cellId];

  Future<void> bindCloudIdentity(String? uid) async {
    if (uid == null || uid == _ownerUid) return;
    final changedOwner = _ownerUid != null;
    _ownerUid = uid;
    if (changedOwner) {
      _generation++;
      _exploredAt.clear();
    }
    await _persist();
    if (changedOwner) notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.exploredCells);
    if (raw == null) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      if ((payload['version'] as num?)?.toInt() != currentVersion) return;
      final cells = (payload['cells'] as Map?)?.cast<String, dynamic>();
      if (cells == null) return;
      final restored = <String, DateTime>{};
      for (final entry in cells.entries) {
        if (entry.key.length != ExplorationGrid.precision) continue;
        final timestamp = DateTime.tryParse(entry.value.toString());
        if (timestamp != null) restored[entry.key] = timestamp;
      }
      _exploredAt
        ..clear()
        ..addAll(restored);
      _ownerUid = payload['owner_uid'] as String?;
      notifyListeners();
    } catch (_) {
      // Keep a malformed payload untouched so a later recovery can inspect it.
    }
  }

  Future<Set<String>> recordPath(List<LatLng> path) async {
    final ids = ExplorationGrid.cellsForPath(path);
    if (ids.isEmpty) return const {};
    final added = <String>{};
    final now = _clock().toUtc();
    for (final id in ids) {
      if (_exploredAt.containsKey(id)) continue;
      _exploredAt[id] = now;
      added.add(id);
    }
    if (added.isEmpty) return const {};
    await _persist();
    notifyListeners();
    return Set.unmodifiable(added);
  }

  Future<Set<String>> recordSession(RunSession session) async {
    if (session.simulated || session.gpsPath.length < 2) return const {};
    final added = await recordPath(session.gpsPath);
    if (added.isNotEmpty) unawaited(syncWithCloud());
    return added;
  }

  Future<void> reset() async {
    _generation++;
    _exploredAt.clear();
    _ownerUid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.exploredCells);
    notifyListeners();
  }

  Future<bool> syncWithCloud() => _enqueueCloudOperation(_syncWithCloud);

  Future<bool> _syncWithCloud() async {
    final cloud = _cloud;
    final prefs = await SharedPreferences.getInstance();
    final pendingDeletionUids =
        (prefs.getStringList(StorageKeys.pendingExplorationDeletionUids) ??
                const <String>[])
            .toSet();
    final currentDeletionPending = pendingDeletionUids.contains(cloud?.uid);
    var deletionHandled = false;
    if (cloud?.uid case final uid? when currentDeletionPending) {
      if (!cloud!.isReady || !await cloud.deleteExploredCells()) return false;
      pendingDeletionUids.remove(uid);
      await prefs.setStringList(
        StorageKeys.pendingExplorationDeletionUids,
        pendingDeletionUids.toList()..sort(),
      );
      deletionHandled = true;
    }
    if (cloud != null && cloud.uid != null) {
      await bindCloudIdentity(cloud.uid);
    }
    if (!_cloudSyncEnabled()) {
      return currentDeletionPending && deletionHandled;
    }
    if (cloud == null || !cloud.isReady || cloud.uid == null) return false;
    final uid = cloud.uid!;
    final generation = _generation;
    try {
      final remote = await cloud.fetchExploredCells();
      if (generation != _generation ||
          cloud.uid != uid ||
          !_cloudSyncEnabled()) {
        return false;
      }
      final missingRemote = <String, DateTime>{};
      for (final entry in _exploredAt.entries) {
        if (!remote.containsKey(entry.key)) {
          missingRemote[entry.key] = entry.value;
        }
      }
      var changed = false;
      for (final entry in remote.entries) {
        final local = _exploredAt[entry.key];
        if (local == null || entry.value.isBefore(local)) {
          _exploredAt[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        await _persist();
        notifyListeners();
      }
      if (missingRemote.isEmpty) return true;
      if (generation != _generation ||
          cloud.uid != uid ||
          !_cloudSyncEnabled()) {
        return false;
      }
      return cloud.upsertExploredCells(missingRemote);
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteEverywhere() => _enqueueCloudOperation(_deleteEverywhere);

  Future<bool> _deleteEverywhere() async {
    final cloud = _cloud;
    final prefs = await SharedPreferences.getInstance();
    final mayHaveRemoteData = _ownerUid != null || _cloudSyncEnabled();
    var remoteDeleted = !mayHaveRemoteData;
    if (mayHaveRemoteData) {
      final deletionUid = _ownerUid ?? cloud?.uid;
      if (deletionUid != null) {
        final pendingUids =
            (prefs.getStringList(StorageKeys.pendingExplorationDeletionUids) ??
                    const <String>[])
                .toSet()
              ..add(deletionUid);
        await prefs.setStringList(
          StorageKeys.pendingExplorationDeletionUids,
          pendingUids.toList()..sort(),
        );
      }
      if (deletionUid != null &&
          cloud != null &&
          cloud.isReady &&
          cloud.uid != null) {
        remoteDeleted =
            deletionUid == cloud.uid && await cloud.deleteExploredCells();
        if (remoteDeleted) {
          final pendingUids =
              (prefs.getStringList(
                        StorageKeys.pendingExplorationDeletionUids,
                      ) ??
                      const <String>[])
                  .toSet()
                ..remove(deletionUid);
          await prefs.setStringList(
            StorageKeys.pendingExplorationDeletionUids,
            pendingUids.toList()..sort(),
          );
        }
      }
    }
    await reset();
    return remoteDeleted || !_cloudSyncEnabled();
  }

  Future<bool> _enqueueCloudOperation(Future<bool> Function() action) {
    final result = _cloudOperations.then((_) => action());
    _cloudOperations = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _persist() async {
    final sorted = _exploredAt.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final payload = {
      'version': currentVersion,
      if (_ownerUid != null) 'owner_uid': _ownerUid,
      'cells': {
        for (final entry in sorted)
          entry.key: entry.value.toUtc().toIso8601String(),
      },
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.exploredCells, jsonEncode(payload));
  }
}
