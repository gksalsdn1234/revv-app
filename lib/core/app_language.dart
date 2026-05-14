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

String appLanguageStorageValue(AppLanguage language) => language.code;
