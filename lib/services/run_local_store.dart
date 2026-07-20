import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../core/storage_keys.dart';
import '../models/route_feedback.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';

abstract class RunLocalStore {
  Future<List<RunSummary>> loadRuns();
  Future<void> saveRuns(Iterable<RunSummary> runs);
  Future<void> saveRunWithDetail(RunSummary run, RunTelemetryDetail detail);
  Future<List<RouteFeedback>> loadFeedback();
  Future<void> saveFeedback(RouteFeedback feedback);
  Future<RunTelemetryDetail?> loadDetail(String runId);
  Future<void> saveDetail(RunTelemetryDetail detail);
  Future<void> clearAll();
}

RunLocalStore createDefaultRunLocalStore({String? ownerUid}) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return PreferencesRunLocalStore();
  }
  return SqfliteRunLocalStore(ownerUid: ownerUid);
}

class SqfliteRunLocalStore implements RunLocalStore {
  SqfliteRunLocalStore({
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
    String? ownerUid,
  }) : _databaseFactory = factory ?? databaseFactory,
       _databasePath = databasePath,
       _ownerUid = ownerUid;

  final DatabaseFactory _databaseFactory;
  final Future<String> Function()? _databasePath;
  final String? _ownerUid;
  Future<Database>? _opening;

  Future<Database> get _database => _opening ??= _open();

  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    await (await opening).close();
    _opening = null;
  }

  Future<Database> _open() async {
    final path = _databasePath == null
        ? p.join(await _databaseFactory.getDatabasesPath(), 'revv_runs.db')
        : await _databasePath();
    final database = await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA secure_delete = ON');
          await db.rawQuery('PRAGMA journal_mode = DELETE');
        },
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE runs (
              id TEXT PRIMARY KEY,
              date_ms INTEGER NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX runs_date_idx ON runs(date_ms DESC)');
          await db.execute('''
            CREATE TABLE run_details (
              run_id TEXT PRIMARY KEY,
              created_at_ms INTEGER NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE route_feedback (
              id TEXT PRIMARY KEY,
              run_id TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX route_feedback_run_idx ON route_feedback(run_id)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX route_feedback_run_unique ON route_feedback(run_id)',
          );
          await db.execute('''
            CREATE TABLE store_metadata (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute('''
              DELETE FROM route_feedback
              WHERE rowid NOT IN (
                SELECT MAX(rowid) FROM route_feedback GROUP BY run_id
              )
            ''');
            await db.execute(
              'CREATE UNIQUE INDEX route_feedback_run_unique ON route_feedback(run_id)',
            );
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE store_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
          }
        },
      ),
    );
    await _bindOwner(database);
    await _migrateLegacy(database);
    return database;
  }

  Future<void> _bindOwner(Database database) async {
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) return;
    final rows = await database.query(
      'store_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['owner_uid'],
      limit: 1,
    );
    final existingOwner = rows.isEmpty ? null : rows.single['value'] as String?;
    if (existingOwner != null && existingOwner != ownerUid) {
      await _clearDatabase(database);
      await database.execute('VACUUM');
    }
    await database.insert('store_metadata', {
      'key': 'owner_uid',
      'value': ownerUid,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<RunSummary>> loadRuns() async {
    final rows = await (await _database).query(
      'runs',
      columns: ['payload'],
      orderBy: 'date_ms DESC',
    );
    return rows.map(_runFromRow).toList(growable: false);
  }

  @override
  Future<void> saveRuns(Iterable<RunSummary> runs) async {
    final database = await _database;
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final run in runs) {
        batch.insert(
          'runs',
          _runRow(run),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> saveRunWithDetail(
    RunSummary run,
    RunTelemetryDetail detail,
  ) async {
    final database = await _database;
    await database.transaction((txn) async {
      await txn.insert(
        'runs',
        _runRow(run),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'run_details',
        _detailRow(detail),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<RouteFeedback>> loadFeedback() async {
    final rows = await (await _database).query(
      'route_feedback',
      columns: ['payload'],
      orderBy: 'created_at_ms DESC',
    );
    return rows.map(_feedbackFromRow).toList(growable: false);
  }

  @override
  Future<void> saveFeedback(RouteFeedback feedback) async {
    await (await _database).insert(
      'route_feedback',
      _feedbackRow(feedback),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    final rows = await (await _database).query(
      'run_details',
      columns: ['payload'],
      where: 'run_id = ?',
      whereArgs: [runId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _detailFromRow(rows.single);
  }

  @override
  Future<void> saveDetail(RunTelemetryDetail detail) async {
    await (await _database).insert(
      'run_details',
      _detailRow(detail),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearAll() async {
    final database = await _database;
    await _clearDatabase(database);
    await database.execute('VACUUM');
  }

  Future<void> _clearDatabase(Database database) async {
    await database.transaction((txn) async {
      await txn.delete('run_details');
      await txn.delete('route_feedback');
      await txn.delete('runs');
    });
  }

  Future<void> _migrateLegacy(Database database) async {
    final prefs = await SharedPreferences.getInstance();
    final detailKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(StorageKeys.runDetailPrefix))
        .toList();
    final legacyOwner = prefs.getString(StorageKeys.cloudRunStorageOwnerUid);
    if (_ownerUid != null && legacyOwner != null && legacyOwner != _ownerUid) {
      await _removeLegacyPayloads(prefs, detailKeys);
      return;
    }
    final runs = _legacyRuns(prefs.getString(StorageKeys.runs));
    final feedback = _legacyFeedback(
      prefs.getString(StorageKeys.routeFeedback),
    );
    final details = <RunTelemetryDetail>[];
    for (final key in detailKeys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        details.add(
          RunTelemetryDetail.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>(),
          ),
        );
      } on Object {
        continue;
      }
    }
    if (runs.isEmpty && feedback.isEmpty && details.isEmpty) return;

    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final run in runs) {
        batch.insert(
          'runs',
          _runRow(run),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final item in feedback) {
        batch.insert(
          'route_feedback',
          _feedbackRow(item),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final detail in details) {
        batch.insert(
          'run_details',
          _detailRow(detail),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
    await _removeLegacyPayloads(prefs, detailKeys);
  }

  Future<void> _removeLegacyPayloads(
    SharedPreferences prefs,
    List<String> detailKeys,
  ) async {
    await prefs.remove(StorageKeys.runs);
    await prefs.remove(StorageKeys.routeFeedback);
    for (final key in detailKeys) {
      await prefs.remove(key);
    }
  }

  static Map<String, Object?> _runRow(RunSummary run) => {
    'id': run.id,
    'date_ms': run.date.toUtc().millisecondsSinceEpoch,
    'payload': jsonEncode(run.toJson()),
  };

  static RunSummary _runFromRow(Map<String, Object?> row) =>
      RunSummary.fromJson(
        (jsonDecode(row['payload']! as String) as Map).cast<String, dynamic>(),
      );

  static Map<String, Object?> _feedbackRow(RouteFeedback feedback) => {
    'id': feedback.id,
    'run_id': feedback.runId,
    'created_at_ms': feedback.createdAt.toUtc().millisecondsSinceEpoch,
    'payload': jsonEncode(feedback.toJson()),
  };

  static RouteFeedback _feedbackFromRow(Map<String, Object?> row) =>
      RouteFeedback.fromJson(
        (jsonDecode(row['payload']! as String) as Map).cast<String, dynamic>(),
      );

  static Map<String, Object?> _detailRow(RunTelemetryDetail detail) => {
    'run_id': detail.runId,
    'created_at_ms': detail.createdAt.toUtc().millisecondsSinceEpoch,
    'payload': jsonEncode(detail.toJson()),
  };

  static RunTelemetryDetail _detailFromRow(Map<String, Object?> row) =>
      RunTelemetryDetail.fromJson(
        (jsonDecode(row['payload']! as String) as Map).cast<String, dynamic>(),
      );
}

class PreferencesRunLocalStore implements RunLocalStore {
  @override
  Future<List<RunSummary>> loadRuns() async => _legacyRuns(
    (await SharedPreferences.getInstance()).getString(StorageKeys.runs),
  );

  @override
  Future<void> saveRuns(Iterable<RunSummary> runs) async {
    final merged = await loadRuns();
    for (final run in runs) {
      final index = merged.indexWhere((item) => item.id == run.id);
      if (index < 0) {
        merged.add(run);
      } else {
        merged[index] = run;
      }
    }
    merged.sort((a, b) => b.date.compareTo(a.date));
    await (await SharedPreferences.getInstance()).setString(
      StorageKeys.runs,
      RunSummary.listToJson(merged),
    );
  }

  @override
  Future<void> saveRunWithDetail(
    RunSummary run,
    RunTelemetryDetail detail,
  ) async {
    await saveRuns([run]);
    await saveDetail(detail);
  }

  @override
  Future<List<RouteFeedback>> loadFeedback() async => _legacyFeedback(
    (await SharedPreferences.getInstance()).getString(
      StorageKeys.routeFeedback,
    ),
  );

  @override
  Future<void> saveFeedback(RouteFeedback feedback) async {
    final items = await loadFeedback();
    final index = items.indexWhere((item) => item.runId == feedback.runId);
    if (index < 0) {
      items.insert(0, feedback);
    } else {
      items[index] = feedback;
    }
    await (await SharedPreferences.getInstance()).setString(
      StorageKeys.routeFeedback,
      RouteFeedback.listToJson(items),
    );
  }

  @override
  Future<RunTelemetryDetail?> loadDetail(String runId) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      '${StorageKeys.runDetailPrefix}$runId',
    );
    if (raw == null) return null;
    try {
      return RunTelemetryDetail.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveDetail(RunTelemetryDetail detail) async {
    await (await SharedPreferences.getInstance()).setString(
      '${StorageKeys.runDetailPrefix}${detail.runId}',
      jsonEncode(detail.toJson()),
    );
  }

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.runs);
    await prefs.remove(StorageKeys.routeFeedback);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(StorageKeys.runDetailPrefix)) {
        await prefs.remove(key);
      }
    }
  }
}

List<RunSummary> _legacyRuns(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    return RunSummary.listFromJson(raw);
  } on Object {
    return [];
  }
}

List<RouteFeedback> _legacyFeedback(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    return RouteFeedback.listFromJson(raw);
  } on Object {
    return [];
  }
}
