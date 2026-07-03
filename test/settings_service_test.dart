import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/ui/app_copy.dart';
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

  test('SettingsService defaults detailed cloud upload to off', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();

    await settings.load();

    expect(settings.cloudRunStorageEnabled, isFalse);
  });

  test(
    'SettingsService preserves existing detailed cloud upload preference',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.cloudRunStorageEnabled: true,
      });
      final settings = SettingsService();

      await settings.load();

      expect(settings.cloudRunStorageEnabled, isTrue);
    },
  );

  test('cloud copy describes detailed upload without requiring login now', () {
    expect(
      AppCopy.cloudOn(AppLanguage.english),
      contains('detailed drive cloud upload'),
    );
    expect(
      AppCopy.t(
        AppLanguage.english,
        ko: '',
        en: 'Local reports stay available · cross-device cloud sync will require sign-in later',
        fr: '',
      ),
      contains('sign-in later'),
    );
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
