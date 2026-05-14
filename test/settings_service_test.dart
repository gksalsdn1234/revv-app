import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'SettingsService normalizes invalid route filter strength to balanced',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.routeFilterStrength: 'wild',
      });

      final settings = SettingsService();
      await settings.load();

      expect(settings.routeFilterStrength, RouteFilterStrength.balanced);
    },
  );

  test('SettingsService persists route filter strength', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = SettingsService();
    await settings.load();
    await settings.setRouteFilterStrength(RouteFilterStrength.broad);

    expect(settings.routeFilterStrength, RouteFilterStrength.broad);

    final reloaded = SettingsService();
    await reloaded.load();

    expect(reloaded.routeFilterStrength, RouteFilterStrength.broad);
  });

  test('SettingsService persists cloud run storage toggle', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = SettingsService();
    await settings.load();
    expect(settings.cloudRunStorageEnabled, isTrue);

    await settings.setCloudRunStorageEnabled(false);
    expect(settings.cloudRunStorageEnabled, isFalse);

    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.cloudRunStorageEnabled, isFalse);
  });

  test(
    'SettingsService defaults language to English and persists French',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.appLanguage: 'unexpected',
      });

      final settings = SettingsService();
      await settings.load();
      expect(settings.appLanguage, AppLanguage.english);

      await settings.setAppLanguage(AppLanguage.french);
      expect(settings.appLanguage, AppLanguage.french);

      final reloaded = SettingsService();
      await reloaded.load();
      expect(reloaded.appLanguage, AppLanguage.french);
    },
  );
}
