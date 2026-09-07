import 'dart:ui' show PlatformDispatcher;

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

  test('SettingsService persists requested region grid keys', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();

    await settings.load();
    await settings.markRegionRequested('43.7,-79.4');

    expect(settings.hasRequestedRegion('43.7,-79.4'), isTrue);

    final reloaded = SettingsService();
    await reloaded.load();

    expect(reloaded.hasRequestedRegion('43.7,-79.4'), isTrue);
  });

  test('cloud copy describes detailed storage without requiring login now', () {
    expect(
      AppCopy.cloudOn(AppLanguage.english),
      'Detailed drive cloud storage',
    );
    expect(
      AppCopy.cloudStorageDetail(AppLanguage.english, false),
      'Keep drive reports on this device',
    );
  });

  test(
    'SettingsService follows the device language instead of stored overrides',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.appLanguage: 'fr',
      });

      final settings = SettingsService();
      await settings.load();
      expect(
        settings.appLanguage,
        appLanguageFromLocaleCode(
          PlatformDispatcher.instance.locale.languageCode,
        ),
      );

      // The override remains available to copy-focused widget tests, but it
      // is intentionally not written to preferences.
      await settings.setAppLanguage(AppLanguage.french);
      expect(settings.appLanguage, AppLanguage.french);

      final reloaded = SettingsService();
      await reloaded.load();
      expect(
        reloaded.appLanguage,
        appLanguageFromLocaleCode(
          PlatformDispatcher.instance.locale.languageCode,
        ),
      );
    },
  );
}
