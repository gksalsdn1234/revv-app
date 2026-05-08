import 'package:flutter_test/flutter_test.dart';
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
}
