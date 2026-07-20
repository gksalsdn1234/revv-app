import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/ui/app_copy.dart';

void main() {
  test('map, loading, and settings policy labels are localized', () {
    expect(AppCopy.mapNav(AppLanguage.korean), '지도');
    expect(AppCopy.mapNav(AppLanguage.english), 'Map');
    expect(AppCopy.mapNav(AppLanguage.french), 'Carte');

    expect(AppCopy.loadingTagline(AppLanguage.korean), contains('안전'));
    expect(AppCopy.loadingScanning(AppLanguage.english), 'Scan');
    expect(AppCopy.loadingLocation(AppLanguage.french), 'Position');

    expect(AppCopy.settingsUnitsDisplay(AppLanguage.korean), '단위 / 표시');
    expect(
      AppCopy.settingsVoiceGuidance(AppLanguage.english),
      'Voice guidance',
    );
    expect(AppCopy.settingsCurveAlerts(AppLanguage.french), 'Alertes virage');
    expect(AppCopy.mapDataCredits(AppLanguage.korean), '지도 데이터 · 루트 출처');
    expect(
      AppCopy.mapDataCredits(AppLanguage.english),
      'Map data & route sources',
    );
    expect(
      AppCopy.mapDataCredits(AppLanguage.french),
      'Données cartographiques et sources',
    );
    expect(
      AppCopy.mapDataCreditsDetail(AppLanguage.english),
      'Generated routes: © OpenStreetMap contributors · ODbL',
    );
    expect(
      AppCopy.mapDataCreditsLinkSemantics(AppLanguage.korean),
      'OpenStreetMap 저작권 정보 열기',
    );
    expect(
      AppCopy.mapDataCreditsLinkSemantics(AppLanguage.english),
      'Open OpenStreetMap copyright information',
    );
    expect(
      AppCopy.mapDataCreditsLinkSemantics(AppLanguage.french),
      'Ouvrir les informations de droit d’auteur OpenStreetMap',
    );
  });
}
