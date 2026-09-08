import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/run_session.dart';

typedef RunRecoveryDirectoryProvider = Future<Directory> Function();

class RunRecoveryStore {
  RunRecoveryStore({RunRecoveryDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
      _readLegacy = directoryProvider == null;

  final RunRecoveryDirectoryProvider _directoryProvider;
  final bool _readLegacy;
  // Shell, recording and deferred-save stores may be distinct instances.
  static Future<void> _operations = Future.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  String _name(String id) =>
      'run_recovery_${base64Url.encode(utf8.encode(id))}.json';

  Future<void> writeSnapshot(RunRecoverySnapshot snapshot) => _serialize(
    () async {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      final file = File('${directory.path}/${_name(snapshot.recoveryId)}');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await temporary.rename(file.path);
    },
  );

  Future<List<({File file, RunRecoverySnapshot snapshot})>> _entries() async {
    final directory = await _directoryProvider();
    if (_readLegacy) {
      final legacy = File(
        '${(await getTemporaryDirectory()).path}/run_recovery.json',
      );
      final destination = File('${directory.path}/run_recovery.json');
      if (await legacy.exists() && !await destination.exists()) {
        await directory.create(recursive: true);
        await legacy.copy(destination.path);
        await legacy.delete();
      }
    }
    final entries = <({File file, RunRecoverySnapshot snapshot})>[];
    if (!await directory.exists()) return entries;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!(name == 'run_recovery.json' || name.startsWith('run_recovery_')) ||
          !name.endsWith('.json')) {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        entries.add((
          file: entity,
          snapshot: RunRecoverySnapshot.fromJson(
            (json as Map).cast<String, dynamic>(),
          ),
        ));
      } catch (_) {
        // Preserve corrupt files; a bad entry must not hide other drives.
      }
    }
    entries.sort(
      (a, b) => a.snapshot.startTime.compareTo(b.snapshot.startTime),
    );
    return entries;
  }

  Future<RunRecoverySnapshot?> readSnapshot() => _serialize(() async {
    final entries = await _entries();
    return entries.isEmpty ? null : entries.first.snapshot;
  });

  Future<void> clear({String? runId}) => _serialize(() async {
    final directory = await _directoryProvider();
    final files = <File>[];
    if (runId != null) {
      files.add(File('${directory.path}/${_name(runId)}'));
    } else if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('run_recovery_') &&
            (name.endsWith('.json') || name.endsWith('.json.tmp'))) {
          files.add(entity);
        }
      }
    }
    final legacy = [
      File('${directory.path}/run_recovery.json'),
      if (_readLegacy)
        File('${(await getTemporaryDirectory()).path}/run_recovery.json'),
    ];
    for (final file in legacy) {
      if (!await file.exists()) continue;
      if (runId == null) {
        files.add(file);
      } else {
        try {
          final snapshot = RunRecoverySnapshot.fromJson(
            (jsonDecode(await file.readAsString()) as Map)
                .cast<String, dynamic>(),
          );
          if (snapshot.recoveryId == runId) files.add(file);
        } catch (_) {}
      }
    }
    for (final file in files) {
      if (await file.exists()) await file.delete();
      final temporary = File('${file.path}.tmp');
      if (await temporary.exists()) await temporary.delete();
    }
  });
}
