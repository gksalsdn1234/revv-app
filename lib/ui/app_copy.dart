import '../core/app_language.dart';

class AppCopy {
  AppCopy._();

  static bool isFr(AppLanguage language) => language == AppLanguage.french;
  static bool isKo(AppLanguage language) => language == AppLanguage.korean;

  static String t(
    AppLanguage language, {
    String? ko,
    required String en,
    required String fr,
  }) {
    if (isKo(language)) return ko ?? en;
    return isFr(language) ? fr : en;
  }

  static String homeTitle(AppLanguage language) => t(
    language,
    ko: '좋은 길을 찾고.\n바로 달리기.',
    en: 'Find the road.\nStart the drive.',
    fr: 'Trouver la route.\nLancer le trajet.',
  );

  static String homeSubtitle(AppLanguage language) => t(
    language,
    ko: '지도, 루트 선택, 주행, 요약 저장에 집중한 베타입니다.',
    en: 'A lean beta focused on the core flow: map, route choice, drive, and saved summary.',
    fr: 'Une bêta légère centrée sur l’essentiel : carte, choix de route, conduite et résumé.',
  );

  static String routeFinder(AppLanguage language) =>
      t(language, ko: '루트 찾기', en: 'Find routes', fr: 'Trouver des routes');

  static String location(AppLanguage language) =>
      t(language, ko: '위치', en: 'Location', fr: 'Position');

  static String routes(AppLanguage language) =>
      t(language, ko: '루트', en: 'Routes', fr: 'Routes');

  static String history(AppLanguage language) =>
      t(language, ko: '기록', en: 'History', fr: 'Historique');

  static String cloudRuns(AppLanguage language) =>
      t(language, ko: '클라우드', en: 'Cloud runs', fr: 'Cloud');

  static String ready(AppLanguage language) =>
      t(language, ko: '준비됨', en: 'Ready', fr: 'Prêt');

  static String permissionNeeded(AppLanguage language) =>
      t(language, ko: '필요', en: 'Needed', fr: 'Requis');

  static String standby(AppLanguage language) =>
      t(language, ko: '대기', en: 'Standby', fr: 'Attente');

  static String countRoutes(AppLanguage language, int count) =>
      t(language, ko: '$count개', en: '$count routes', fr: '$count routes');

  static String countRuns(AppLanguage language, int count) =>
      t(language, ko: '$count회', en: '$count runs', fr: '$count trajets');

  static String saved(AppLanguage language) =>
      t(language, ko: '저장', en: 'Saved', fr: 'Activé');

  static String off(AppLanguage language) =>
      t(language, ko: '끔', en: 'Off', fr: 'Off');

  static String refreshLocation(AppLanguage language) =>
      t(language, ko: '위치 갱신', en: 'Refresh location', fr: 'Actualiser');

  static String voiceOn(AppLanguage language) =>
      t(language, ko: '음성 켜기', en: 'Voice on', fr: 'Voix activée');

  static String voiceOff(AppLanguage language) =>
      t(language, ko: '음성 끄기', en: 'Voice off', fr: 'Voix coupée');

  static String cloudOff(AppLanguage language) =>
      t(language, ko: '클라우드 끄기', en: 'Disable cloud', fr: 'Couper cloud');

  static String cloudOn(AppLanguage language) =>
      t(language, ko: '클라우드 켜기', en: 'Enable cloud', fr: 'Activer cloud');

  static String deleteHistory(AppLanguage language) =>
      t(language, ko: '기록 삭제', en: 'Delete history', fr: 'Effacer');

  static String privacyPolicy(AppLanguage language) =>
      t(language, ko: '개인정보 처리방침', en: 'Privacy Policy', fr: 'Confidentialité');

  static String deleteRunsTitle(AppLanguage language) => t(
    language,
    ko: '주행 기록을 삭제할까요?',
    en: 'Delete drive history?',
    fr: 'Effacer l’historique ?',
  );

  static String deleteRunsBody(AppLanguage language) => t(
    language,
    ko: '로컬 캐시와 클라우드 주행 기록, 텔레메트리 상세, 피드백을 삭제합니다.',
    en: 'This deletes local cache plus cloud drive records, telemetry details, and feedback.',
    fr: 'Cela supprime le cache local, les trajets cloud, les détails télémétriques et les retours.',
  );

  static String cancel(AppLanguage language) =>
      t(language, ko: '취소', en: 'Cancel', fr: 'Annuler');

  static String delete(AppLanguage language) =>
      t(language, ko: '삭제', en: 'Delete', fr: 'Effacer');

  static String deleteRunsDone(AppLanguage language) => t(
    language,
    ko: '주행 기록을 삭제했어요.',
    en: 'Drive history deleted.',
    fr: 'Historique supprimé.',
  );

  static String deleteRunsFailed(AppLanguage language) => t(
    language,
    ko: '클라우드 삭제를 완료하지 못했어요. 연결 후 다시 시도해 주세요.',
    en: 'Cloud deletion did not finish. Reconnect and try again.',
    fr: 'La suppression cloud a échoué. Réessayez une fois connecté.',
  );

  static String pendingUploadsCleared(AppLanguage language) => t(
    language,
    ko: '대기 중인 클라우드 업로드를 삭제했어요.',
    en: 'Pending cloud uploads cleared.',
    fr: 'Téléversements cloud en attente supprimés.',
  );

  static String privacyMissing(AppLanguage language) => t(
    language,
    ko: '개인정보 처리방침 URL이 설정되지 않았어요.',
    en: 'Privacy Policy URL is not configured.',
    fr: 'L’URL de confidentialité n’est pas configurée.',
  );

  static String privacyOpenFailed(AppLanguage language) => t(
    language,
    ko: '개인정보 처리방침을 열지 못했어요.',
    en: 'Could not open the Privacy Policy.',
    fr: 'Impossible d’ouvrir la page de confidentialité.',
  );

  static String navigationOpenFailed(AppLanguage language) => t(
    language,
    ko: '내비게이션 앱을 열지 못했어요.',
    en: 'Could not open a navigation app.',
    fr: 'Impossible d’ouvrir une app de navigation.',
  );

  static String guidingToStart(AppLanguage language) => t(
    language,
    ko: '시작점으로 이동 중',
    en: 'Going to route start',
    fr: 'Vers le départ',
  );

  static String start(AppLanguage language) =>
      t(language, ko: '시작', en: 'Start', fr: 'Départ');

  static String permissionIntroTitle(AppLanguage language) => t(
    language,
    ko: '시작하기 전에',
    en: 'Before we start',
    fr: 'Avant de commencer',
  );

  static String permissionIntroBody(AppLanguage language) => t(
    language,
    ko: '권한은 핵심 기능에만 사용됩니다. 거부해도 계속할 수 있지만 일부 기능은 제한됩니다.',
    en: 'Permissions are used only for core features. You can continue if you decline, but some features will be limited.',
    fr: 'Les autorisations servent seulement aux fonctions clés. Vous pouvez continuer, mais certaines fonctions seront limitées.',
  );

  static String locationPermissionBody(AppLanguage language) => t(
    language,
    ko: '주변 루트 탐색, 시작점 거리 계산, 주행 요약 저장에 사용됩니다.',
    en: 'Used to find nearby routes, calculate distance to the start, and save drive summaries.',
    fr: 'Utilisée pour trouver des routes proches, calculer la distance au départ et sauvegarder les résumés.',
  );

  static String continuePermissions(AppLanguage language) =>
      t(language, ko: '계속', en: 'Continue', fr: 'Continuer');

  static String locationBlockedTitle(AppLanguage language) => t(
    language,
    ko: '위치 권한이 필요해요',
    en: 'Location permission needed',
    fr: 'Position requise',
  );

  static String permissionsReadyTitle(AppLanguage language) =>
      t(language, ko: '준비됨', en: 'Ready', fr: 'Prêt');

  static String locationBlockedBody(AppLanguage language) => t(
    language,
    ko: '루트 탐색은 위치 권한이 있을 때 가장 잘 동작합니다. 설정에서 위치를 켜주세요.',
    en: 'Route discovery works best with location permission. Turn it on in Settings to search nearby roads.',
    fr: 'La recherche de routes fonctionne mieux avec la position. Activez-la dans Réglages pour chercher près de vous.',
  );

  static String permissionsReadyBody(AppLanguage language) => t(
    language,
    ko: '핵심 권한이 준비됐어요.',
    en: 'Core permissions are ready.',
    fr: 'Les autorisations essentielles sont prêtes.',
  );

  static String openSettings(AppLanguage language) =>
      t(language, ko: '설정 열기', en: 'Open settings', fr: 'Réglages');

  static String continueAnyway(AppLanguage language) =>
      t(language, ko: '계속하기', en: 'Continue anyway', fr: 'Continuer');

  static String copilotStartCheck(AppLanguage language) => t(
    language,
    ko: '코파일럿 시작 체크',
    en: 'Copilot start check',
    fr: 'Vérification copilote',
  );

  static String startHere(AppLanguage language) =>
      t(language, ko: '여기서 시작', en: 'Start here', fr: 'Commencer ici');

  static String testDriveNow(AppLanguage language) => t(
    language,
    ko: '여기서 테스트 주행',
    en: 'Test drive from here',
    fr: 'Tester depuis ici',
  );
}
