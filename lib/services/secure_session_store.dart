import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';

abstract class SecureStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStringStore implements SecureStringStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  const FlutterSecureStringStore();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SecureSessionStore {
  SecureSessionStore({
    SecureStringStore store = const FlutterSecureStringStore(),
  }) : _store = store;

  final SecureStringStore _store;

  Future<String?> readSession() async {
    final secure = await _store.read(StorageKeys.supabaseSession);
    if (secure != null && secure.isNotEmpty) return secure;

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(StorageKeys.supabaseSession);
    if (legacy == null || legacy.isEmpty) return null;

    await _store.write(StorageKeys.supabaseSession, legacy);
    await prefs.remove(StorageKeys.supabaseSession);
    return legacy;
  }

  Future<void> writeSession(String value) async {
    await _store.write(StorageKeys.supabaseSession, value);
  }

  Future<void> deleteSession() async {
    await _store.delete(StorageKeys.supabaseSession);
    await (await SharedPreferences.getInstance()).remove(
      StorageKeys.supabaseSession,
    );
  }
}

class MemorySecureStringStore implements SecureStringStore {
  final Map<String, String> values;

  MemorySecureStringStore([Map<String, String>? initial])
    : values = Map.of(initial ?? const {});

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
