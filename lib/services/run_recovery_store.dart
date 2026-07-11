import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/run_session.dart';

typedef RunRecoveryDirectoryProvider = Future<Directory> Function();

class RunRecoveryStore {
  RunRecoveryStore({RunRecoveryDirectoryProvider? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  final RunRecoveryDirectoryProvider _directoryProvider;

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/run_recovery.json');
  }

  Future<void> writeSnapshot(RunRecoverySnapshot snapshot) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<RunRecoverySnapshot?> readSnapshot() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return RunRecoverySnapshot.fromJson(
        (json as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }
}
