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

  static String routeFinder(AppLanguage language) =>
      t(language, ko: '루트 찾기', en: 'Find routes', fr: 'Trouver des routes');

  static String location(AppLanguage language) =>
      t(language, ko: '위치', en: 'Location', fr: 'Position');

  static String routes(AppLanguage language) =>
      t(language, ko: '루트', en: 'Routes', fr: 'Routes');

  static String history(AppLanguage language) =>
      t(language, ko: '기록', en: 'History', fr: 'Historique');

  static String mapNav(AppLanguage language) =>
      t(language, ko: '지도', en: 'Map', fr: 'Carte');

  static String settingsNav(AppLanguage language) =>
      t(language, ko: '설정', en: 'Settings', fr: 'Réglages');

  static String cloudRuns(AppLanguage language) =>
      t(language, ko: '클라우드', en: 'Cloud sync', fr: 'Sync cloud');

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
      t(language, ko: '켜짐', en: 'On', fr: 'Activé');

  static String off(AppLanguage language) =>
      t(language, ko: '끔', en: 'Off', fr: 'Off');

  static String refreshLocation(AppLanguage language) =>
      t(language, ko: '위치 갱신', en: 'Refresh location', fr: 'Actualiser');

  static String voiceOn(AppLanguage language) =>
      t(language, ko: '음성 켜기', en: 'Voice on', fr: 'Voix activée');

  static String voiceOff(AppLanguage language) =>
      t(language, ko: '음성 끄기', en: 'Voice off', fr: 'Voix coupée');

  static String cloudOff(AppLanguage language) => t(
    language,
    ko: '상세 주행 데이터 클라우드 업로드 끄기',
    en: 'Turn detailed drive cloud upload off',
    fr: 'Désactiver l’upload détaillé',
  );

  static String cloudOn(AppLanguage language) => t(
    language,
    ko: '상세 주행 데이터 클라우드 업로드 켜기',
    en: 'Turn detailed drive cloud upload on',
    fr: 'Activer l’upload détaillé',
  );

  static String deleteHistory(AppLanguage language) => t(
    language,
    ko: '기록 삭제',
    en: 'Delete history',
    fr: 'Effacer l’historique',
  );

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
    en: 'This deletes local cache plus cloud drive history, telemetry details, and feedback.',
    fr: 'Cela supprime le cache local, les trajets cloud, les détails télémétriques et les retours.',
  );

  static String cancel(AppLanguage language) =>
      t(language, ko: '취소', en: 'Cancel', fr: 'Annuler');

  static String recoverRunTitle(AppLanguage language) => t(
    language,
    ko: '지난 주행 기록이 남아 있어요. 저장할까요?',
    en: 'A previous drive is still available. Save it?',
    fr: 'Un trajet précédent est encore disponible. L’enregistrer ?',
  );

  static String saveRun(AppLanguage language) =>
      t(language, ko: '저장', en: 'Save', fr: 'Enregistrer');

  static String discardRun(AppLanguage language) =>
      t(language, ko: '버리기', en: 'Discard', fr: 'Ignorer');

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
    fr: 'Autorisation de position requise',
  );

  static String permissionsReadyTitle(AppLanguage language) =>
      t(language, ko: '준비됨', en: 'Ready', fr: 'Prêt');

  static String locationBlockedBody(AppLanguage language) => t(
    language,
    ko: '루트 탐색은 위치 권한이 있을 때 가장 잘 동작합니다. 설정에서 위치를 켜주세요.',
    en: 'Route discovery uses location permission. Turn it on in Settings to search nearby roads.',
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

  static String continueAnyway(AppLanguage language) => t(
    language,
    ko: '계속하기',
    en: 'Continue anyway',
    fr: 'Continuer quand même',
  );

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

  static String sharePreview(AppLanguage language) =>
      t(language, ko: '공유 미리보기', en: 'Share preview', fr: 'Aperçu');

  static String exportCard(AppLanguage language) =>
      t(language, ko: '카드 내보내기', en: 'Export card', fr: 'Exporter');

  static String privateRoute(AppLanguage language) =>
      t(language, ko: '비공개 루트', en: 'Private route', fr: 'Route privée');

  static String sharePresetStory(AppLanguage language) =>
      t(language, ko: '스토리', en: 'Story', fr: 'Story');

  static String sharePresetSquare(AppLanguage language) =>
      t(language, ko: '스퀘어', en: 'Square', fr: 'Carré');

  static String sharePresetSticker(AppLanguage language) =>
      t(language, ko: '스티커', en: 'Sticker', fr: 'Sticker');

  static String sharePresetSubtitle(AppLanguage language, String presetLabel) =>
      t(
        language,
        ko: 'REVV $presetLabel',
        en: 'REVV $presetLabel',
        fr: 'REVV $presetLabel',
      );

  static String shareDateLabel(AppLanguage language, DateTime date) {
    final month = switch (language) {
      AppLanguage.korean => '${date.month}월',
      AppLanguage.french => const [
        'janv.',
        'févr.',
        'mars',
        'avr.',
        'mai',
        'juin',
        'juil.',
        'août',
        'sept.',
        'oct.',
        'nov.',
        'déc.',
      ][date.month - 1],
      AppLanguage.english => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][date.month - 1],
    };
    return switch (language) {
      AppLanguage.korean => '${date.year}년 $month ${date.day}일',
      AppLanguage.french => '${date.day} $month ${date.year}',
      AppLanguage.english => '$month ${date.day}, ${date.year}',
    };
  }

  static String shareMetricLabel(AppLanguage language, String metricId) {
    return switch (metricId) {
      'distance' => t(language, ko: '거리', en: 'Distance', fr: 'Distance'),
      'duration' => t(language, ko: '시간', en: 'Duration', fr: 'Durée'),
      'avgSpeed' => t(
        language,
        ko: '평균 속도',
        en: 'Avg speed',
        fr: 'Vitesse moy.',
      ),
      'revvScore' => t(
        language,
        ko: 'REVV 점수',
        en: 'REVV Score',
        fr: 'Score REVV',
      ),
      'flow' => t(language, ko: '흐름', en: 'Flow', fr: 'Flow'),
      'technical' => t(language, ko: '테크닉', en: 'Technical', fr: 'Technique'),
      'smoothness' => t(language, ko: '스무스', en: 'Smoothness', fr: 'Fluidité'),
      'winding' => t(language, ko: '와인딩', en: 'Winding', fr: 'Virages'),
      'cornerEvents' => t(
        language,
        ko: '코너 이벤트',
        en: 'Corner events',
        fr: 'Virages',
      ),
      'route' => t(language, ko: '루트', en: 'Route', fr: 'Route'),
      'maxSpeed' => t(
        language,
        ko: '속도 상세',
        en: 'Speed detail',
        fr: 'Détail vitesse',
      ),
      _ => metricId,
    };
  }

  static String routeCompletion(AppLanguage language, int percent) => t(
    language,
    ko: '$percent% 완료',
    en: '$percent% done',
    fr: '$percent % fait',
  );

  static String loadingTagline(AppLanguage language) => t(
    language,
    ko: '루트 확인 · 안전 준비',
    en: 'Route check · Safe start',
    fr: 'Route prête · Départ sûr',
  );

  static String loadingGps(AppLanguage language) =>
      t(language, ko: 'GPS', en: 'GPS', fr: 'GPS');

  static String loadingImu(AppLanguage language) =>
      t(language, ko: '센서', en: 'IMU', fr: 'IMU');

  static String loadingLocation(AppLanguage language) =>
      t(language, ko: '위치', en: 'Location', fr: 'Position');

  static String loadingScanning(AppLanguage language) =>
      t(language, ko: '확인 중', en: 'Scan', fr: 'Scan');

  static String loadingReady(AppLanguage language) =>
      t(language, ko: '완료', en: 'OK', fr: 'OK');

  static String settingsGarage(AppLanguage language) => t(
    language,
    ko: '설정 / 차고',
    en: 'Settings / Garage',
    fr: 'Réglages / Garage',
  );

  static String anonymousDriver(AppLanguage language) => t(
    language,
    ko: '익명 드라이버',
    en: 'Anonymous driver',
    fr: 'Conducteur anonyme',
  );

  static String noSavedRuns(AppLanguage language) => t(
    language,
    ko: '저장된 런 없음',
    en: 'No saved runs yet',
    fr: 'Aucune sortie enregistrée',
  );

  static String profileRunsMeta(
    AppLanguage language,
    int runCount,
    String since,
  ) {
    return t(
      language,
      ko: '총 $runCount회 · 시작 $since',
      en: '$runCount ${runCount == 1 ? 'run' : 'runs'} · since $since',
      fr: '$runCount ${runCount == 1 ? 'sortie' : 'sorties'} · depuis $since',
    );
  }

  static String settingsUnitsDisplay(AppLanguage language) => t(
    language,
    ko: '단위 / 표시',
    en: 'Units / Display',
    fr: 'Unités / Affichage',
  );

  static String settingsDistance(AppLanguage language) =>
      t(language, ko: '거리', en: 'Distance', fr: 'Distance');

  static String settingsLanguage(AppLanguage language) =>
      t(language, ko: '언어', en: 'Language', fr: 'Langue');

  static String settingsDrive(AppLanguage language) =>
      t(language, ko: '주행', en: 'Drive', fr: 'Trajet');

  static String settingsCloudSync(AppLanguage language) =>
      t(language, ko: '클라우드 동기화', en: 'Cloud sync', fr: 'Sync cloud');

  static String cloudSyncDetail(AppLanguage language) => t(
    language,
    ko: '로컬 리포트 유지 · 기기 동기화는 나중에 로그인 필요',
    en: 'Local reports stay · device sync needs sign-in later',
    fr: 'Rapports locaux gardés · sync avec connexion plus tard',
  );

  static String settingsVoiceGuidance(AppLanguage language) =>
      t(language, ko: '음성 안내', en: 'Voice guidance', fr: 'Guidage vocal');

  static String voiceGuidanceDetail(AppLanguage language) => t(
    language,
    ko: '페이스 노트와 회전 안내',
    en: 'Pace notes and turns',
    fr: 'Notes et virages',
  );

  static String settingsCurveAlerts(AppLanguage language) =>
      t(language, ko: '커브 알림', en: 'Curve alerts', fr: 'Alertes virage');

  static String curveAlertsDetail(AppLanguage language) => t(
    language,
    ko: '미리 속도 확인',
    en: 'Early ease-off cues',
    fr: 'Rappels de lever tôt',
  );

  static String settingsData(AppLanguage language) =>
      t(language, ko: '데이터', en: 'Data', fr: 'Données');
}
