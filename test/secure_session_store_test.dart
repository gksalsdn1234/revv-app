import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/services/secure_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'SecureSessionStore migrates legacy SharedPreferences session',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.supabaseSession: '{"access_token":"legacy"}',
      });
      final memory = MemorySecureStringStore();
      final store = SecureSessionStore(store: memory);

      final session = await store.readSession();

      expect(session, '{"access_token":"legacy"}');
      expect(memory.values[StorageKeys.supabaseSession], session);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.supabaseSession), isNull);
    },
  );

  test('SecureSessionStore writes and deletes secure session', () async {
    SharedPreferences.setMockInitialValues({});
    final memory = MemorySecureStringStore();
    final store = SecureSessionStore(store: memory);

    await store.writeSession('session-json');
    expect(await store.readSession(), 'session-json');

    await store.deleteSession();
    expect(await store.readSession(), isNull);
  });
}
