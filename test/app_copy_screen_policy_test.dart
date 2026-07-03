import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/ui/app_copy.dart';

void main() {
  test('home, loading, and settings policy labels are localized', () {
    expect(AppCopy.homeNav(AppLanguage.korean), '홈');
    expect(AppCopy.homeNav(AppLanguage.english), 'Home');
    expect(AppCopy.homeNav(AppLanguage.french), 'Accueil');

    expect(AppCopy.loadingTagline(AppLanguage.korean), contains('안전'));
    expect(AppCopy.loadingScanning(AppLanguage.english), 'Scan');
    expect(AppCopy.loadingLocation(AppLanguage.french), 'Position');

    expect(AppCopy.settingsUnitsDisplay(AppLanguage.korean), '단위 / 표시');
    expect(
      AppCopy.settingsVoiceGuidance(AppLanguage.english),
      'Voice guidance',
    );
    expect(AppCopy.settingsCurveAlerts(AppLanguage.french), 'Alertes virage');
  });
}
