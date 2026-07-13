import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/services/exploration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('records, persists, and reloads a monotonic set of cells', () async {
    final now = DateTime.utc(2026, 7, 12, 20);
    final service = ExplorationService(clock: () => now);

    final added = await service.recordPath(const [
      LatLng(45.5, -73.6),
      LatLng(45.5, -73.59),
    ]);
    final duplicate = await service.recordPath(const [
      LatLng(45.5, -73.6),
      LatLng(45.5, -73.59),
    ]);

    expect(added, isNotEmpty);
    expect(duplicate, isEmpty);

    final restored = ExplorationService();
    await restored.load();
    expect(restored.exploredCellIds, service.exploredCellIds);
  });

  test(
    'malformed and future-version payloads fail closed without crashing',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.exploredCells: '{broken',
      });
      final malformed = ExplorationService();
      await malformed.load();
      expect(malformed.exploredCellIds, isEmpty);

      SharedPreferences.setMockInitialValues({
        StorageKeys.exploredCells: jsonEncode({
          'version': ExplorationService.currentVersion + 1,
          'cells': {'future': '2026-07-12T20:00:00.000Z'},
        }),
      });
      final future = ExplorationService();
      await future.load();
      expect(future.exploredCellIds, isEmpty);
    },
  );

  test('reset clears both memory and persisted exploration', () async {
    final service = ExplorationService();
    await service.recordPath(const [LatLng(45.5, -73.6)]);

    await service.reset();

    expect(service.exploredCellIds, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.exploredCells), isNull);
  });

  test('simulated sessions never reveal exploration cells', () async {
    final service = ExplorationService();
    final now = DateTime.utc(2026, 7, 12, 20);
    final session = RunSession(
      startTime: now,
      endTime: now.add(const Duration(minutes: 2)),
      maxSpeedKmh: 40,
      avgSpeedKmh: 25,
      distanceKm: 1,
      gpsPath: const [LatLng(45.5, -73.6), LatLng(45.51, -73.6)],
      weatherEmoji: '',
      tempDisplay: '',
      weatherDesc: '',
      simulated: true,
    );

    expect(await service.recordSession(session), isEmpty);
    expect(service.exploredCellIds, isEmpty);
  });

  test('a one-point session does not reveal an area', () async {
    final now = DateTime.utc(2026, 7, 12, 20);
    final service = ExplorationService();
    final session = RunSession(
      startTime: now,
      endTime: now.add(const Duration(seconds: 5)),
      maxSpeedKmh: 10,
      avgSpeedKmh: 5,
      distanceKm: 0,
      gpsPath: const [LatLng(45.5, -73.6)],
      weatherEmoji: '',
      tempDisplay: '',
      weatherDesc: '',
    );

    expect(await service.recordSession(session), isEmpty);
  });

  test(
    'cloud sync unions local and remote cells and uploads only missing',
    () async {
      final remoteTime = DateTime.utc(2026, 7, 11);
      final cloud = _FakeExplorationCloud(remote: {'f25dvk1': remoteTime});
      final service = ExplorationService(cloud: cloud);
      await service.recordPath(const [LatLng(45.5, -73.6)]);
      final localBeforeSync = service.exploredCellIds.single;

      expect(await service.syncWithCloud(), isTrue);

      expect(
        service.exploredCellIds,
        containsAll(['f25dvk1', localBeforeSync]),
      );
      expect(cloud.lastUpsert.keys, {localBeforeSync});
    },
  );

  test('cloud sync respects the cloud storage opt-in', () async {
    final cloud = _FakeExplorationCloud(
      remote: {'f25dvk1': DateTime.utc(2026, 7, 11)},
    );
    final service = ExplorationService(
      cloud: cloud,
      cloudSyncEnabled: () => false,
    );
    await service.recordPath(const [LatLng(45.5, -73.6)]);

    expect(await service.syncWithCloud(), isFalse);
    expect(cloud.fetchCount, 0);
    expect(cloud.lastUpsert, isEmpty);
  });

  test('cloud opt-out deletion clears local cells without a network', () async {
    final cloud = _FakeExplorationCloud()..ready = false;
    final service = ExplorationService(
      cloud: cloud,
      cloudSyncEnabled: () => false,
    );
    await service.recordPath(const [LatLng(45.5, -73.6)]);

    expect(await service.deleteEverywhere(), isTrue);
    expect(service.exploredCellIds, isEmpty);
    expect(cloud.deleteCount, 0);
  });

  test('cloud operations serialize sync before deletion', () async {
    final fetch = Completer<Map<String, DateTime>>();
    final cloud = _FakeExplorationCloud(fetchCompleter: fetch);
    final service = ExplorationService(cloud: cloud);
    await service.recordPath(const [LatLng(45.5, -73.6)]);

    final sync = service.syncWithCloud();
    await Future<void>.delayed(Duration.zero);
    final deletion = service.deleteEverywhere();
    fetch.complete({'f25dvk1': DateTime.utc(2026, 7, 11)});

    await sync;
    expect(await deletion, isTrue);
    expect(service.exploredCellIds, isEmpty);
    expect(cloud.deleteCount, 1);
  });

  test('turning cloud storage off cancels an in-flight upload', () async {
    var enabled = true;
    final fetch = Completer<Map<String, DateTime>>();
    final cloud = _FakeExplorationCloud(fetchCompleter: fetch);
    final service = ExplorationService(
      cloud: cloud,
      cloudSyncEnabled: () => enabled,
    );
    await service.recordPath(const [LatLng(45.5, -73.6)]);

    final sync = service.syncWithCloud();
    await Future<void>.delayed(Duration.zero);
    enabled = false;
    fetch.complete({'f25dvk1': DateTime.utc(2026, 7, 11)});

    expect(await sync, isFalse);
    expect(service.exploredCellIds, isNot(contains('f25dvk1')));
    expect(cloud.lastUpsert, isEmpty);
  });

  test(
    'an opt-out deletion retries a previously synced remote erase',
    () async {
      var enabled = true;
      final cloud = _FakeExplorationCloud();
      final service = ExplorationService(
        cloud: cloud,
        cloudSyncEnabled: () => enabled,
      );
      await service.recordPath(const [LatLng(45.5, -73.6)]);
      await service.syncWithCloud();
      enabled = false;
      cloud.ready = false;

      expect(await service.deleteEverywhere(), isTrue);
      var prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(StorageKeys.pendingExplorationDeletionUids),
        contains('user-1'),
      );

      cloud.ready = true;
      expect(await service.syncWithCloud(), isTrue);
      prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(StorageKeys.pendingExplorationDeletionUids),
        isEmpty,
      );
    },
  );

  test('a changed cloud identity cannot inherit local exploration', () async {
    final cloud = _FakeExplorationCloud();
    final service = ExplorationService(cloud: cloud);
    await service.recordPath(const [LatLng(45.5, -73.6)]);
    await service.syncWithCloud();

    cloud.userId = 'user-2';
    cloud.lastUpsert = const {};
    await service.syncWithCloud();

    expect(service.exploredCellIds, isEmpty);
    expect(cloud.lastUpsert, isEmpty);
  });

  test('a pending deletion never targets a replacement identity', () async {
    var enabled = true;
    final cloud = _FakeExplorationCloud();
    final service = ExplorationService(
      cloud: cloud,
      cloudSyncEnabled: () => enabled,
    );
    await service.recordPath(const [LatLng(45.5, -73.6)]);
    await service.syncWithCloud();
    enabled = false;
    cloud.ready = false;
    await service.deleteEverywhere();

    cloud
      ..userId = 'user-2'
      ..ready = true;
    expect(await service.syncWithCloud(), isFalse);
    expect(cloud.deleteCount, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(StorageKeys.pendingExplorationDeletionUids),
      contains('user-1'),
    );

    await service.bindCloudIdentity('user-2');
    await service.recordPath(const [LatLng(45.6, -73.6)]);
    cloud.ready = false;
    await service.deleteEverywhere();
    expect(
      prefs.getStringList(StorageKeys.pendingExplorationDeletionUids),
      containsAll(['user-1', 'user-2']),
    );
  });

  test(
    'cloud delete failure clears local cells and queues remote deletion',
    () async {
      final cloud = _FakeExplorationCloud(
        upsertResult: false,
        deleteResult: false,
      );
      final service = ExplorationService(cloud: cloud);
      await service.recordPath(const [LatLng(45.5, -73.6)]);

      expect(await service.syncWithCloud(), isFalse);
      expect(await service.deleteEverywhere(), isFalse);
      expect(service.exploredCellIds, isEmpty);
      var prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(StorageKeys.pendingExplorationDeletionUids),
        contains('user-1'),
      );

      cloud.deleteResult = true;
      expect(await service.syncWithCloud(), isTrue);
      expect(service.exploredCellIds, isEmpty);
      prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(StorageKeys.pendingExplorationDeletionUids),
        isEmpty,
      );
    },
  );
}

class _FakeExplorationCloud implements ExplorationCloudClient {
  _FakeExplorationCloud({
    this.remote = const {},
    this.upsertResult = true,
    this.deleteResult = true,
    this.fetchCompleter,
  });

  final Map<String, DateTime> remote;
  bool upsertResult;
  bool deleteResult;
  final Completer<Map<String, DateTime>>? fetchCompleter;
  bool ready = true;
  String userId = 'user-1';
  int fetchCount = 0;
  int deleteCount = 0;
  Map<String, DateTime> lastUpsert = const {};

  @override
  bool get isReady => ready;

  @override
  String? get uid => userId;

  @override
  Future<bool> deleteExploredCells() async {
    deleteCount++;
    return deleteResult;
  }

  @override
  Future<Map<String, DateTime>> fetchExploredCells() async {
    fetchCount++;
    if (fetchCompleter != null) return fetchCompleter!.future;
    return remote;
  }

  @override
  Future<bool> upsertExploredCells(Map<String, DateTime> cells) async {
    lastUpsert = Map.of(cells);
    return upsertResult;
  }
}
