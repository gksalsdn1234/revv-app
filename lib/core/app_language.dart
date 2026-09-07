enum AppLanguage {
  korean('ko', '한국어', 'KO'),
  english('en', 'English', 'EN'),
  french('fr', 'Français', 'FR');

  const AppLanguage(this.code, this.label, this.shortLabel);

  final String code;
  final String label;
  final String shortLabel;
}

AppLanguage appLanguageFromStorage(String? value) {
  return switch (value) {
    'ko' => AppLanguage.korean,
    'fr' => AppLanguage.french,
    'en' || _ => AppLanguage.english,
  };
}

/// Maps the platform's preferred language to one of the app's supported
/// languages. Native iOS permission sheets use this same platform language,
/// so the app UI must not override it with an independent persisted choice.
AppLanguage appLanguageFromLocaleCode(String? value) {
  return switch (value?.toLowerCase()) {
    'ko' => AppLanguage.korean,
    'fr' => AppLanguage.french,
    _ => AppLanguage.english,
  };
}

String appLanguageStorageValue(AppLanguage language) => language.code;
