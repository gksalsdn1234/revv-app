/// SharedPreferences 키 중앙 관리
///
/// 모든 SP 키는 여기에 정의하고 각 서비스에서 참조.
/// 키 이름 변경 시 이 파일만 수정하면 됨.
///
/// 구조:
///   runs.*        — 런 기록
///   routes.*      — 저장된 루트 + 캐시
///   home.*        — 집 위치
///   settings.*    — 앱 설정
///   imu.*         — IMU 캘리브레이션
class StorageKeys {
  StorageKeys._();

  // ── 런 기록 (RunHistoryService) ─────────────────────────────
  /// RunSummary 배열 JSON (run_history_service.dart)
  static const runs = 'run_history';
  static const runDetailPrefix = 'run_detail_';
  static const routeFeedback = 'route_feedback';
  static const pendingRunSummaries = 'pending_run_summaries';
  static const pendingRunDetails = 'pending_run_details';
  static const pendingRunDetailsIndex = 'pending_run_details_index_v2';
  static const pendingRunDetailSecurePrefix = 'pending_run_detail_secure_';
  static const pendingRouteFeedback = 'pending_route_feedback';

  // ── 루트 (SavedRouteService, RouteService) ──────────────────
  /// 북마크된 RevvRoute 배열 JSON
  static const savedRoutes = 'saved_routes';

  /// 마지막 Overpass 검색 결과 캐시 JSON
  static const routeCache = 'revv_route_cache';

  /// 캐시 생성 시 사용자 위치 (lat,lng 문자열)
  static const routeCachePos = 'revv_route_cache_pos';

  /// 제외된 루트 센터 목록
  static const excludedCenters = 'revv_excluded_centers';

  /// 마지막으로 성공한 실제 위치
  static const lastKnownLat = 'revv_last_known_lat';
  static const lastKnownLng = 'revv_last_known_lng';

  /// 외부 내비로 시작점 이동 중인 드라이브
  static const pendingDriveRouteId = 'pending_drive_route_id';
  static const pendingDriveSavedAt = 'pending_drive_saved_at';

  // ── 집 위치 (HomeLocationService) ──────────────────────────
  static const homeLat = 'home_lat';
  static const homeLng = 'home_lng';
  static const homeName = 'home_name';

  // ── 앱 설정 (SettingsService) ───────────────────────────────
  static const ttsMuted = 'setting_ttsMuted';
  static const appLanguage = 'setting_appLanguage';
  static const searchRadius = 'setting_searchRadius';
  static const routeFilterStrength = 'setting_routeFilterStrength';
  static const distUnit = 'setting_distUnit';
  static const cloudRunStorageEnabled = 'setting_cloudRunStorageEnabled';
  static const regionRequestGrids = 'setting_regionRequestGrids';
  static const showSpeedHud = 'setting_showSpeedHud';
  static const offRouteAlert = 'setting_offRouteAlert';
  static const jarvisPersona =
      'setting_jarvisPersona'; // 'engineer' | 'friendly'
  static const alwaysListen = 'setting_alwaysListen';
  static const ttsRatePreset = 'setting_ttsRatePreset';
  static const ttsEngine = 'setting_ttsEngine';
  static const ttsVoiceName = 'setting_ttsVoiceName';
  static const ttsVoiceLocale = 'setting_ttsVoiceLocale';
  static const googleTtsVoiceName = 'setting_googleTtsVoiceName';

  // ── IMU 캘리브레이션 (ImuService) ───────────────────────────
  static const imuMount = 'imu_mount';
  static const imuOx = 'imu_ox';
  static const imuOy = 'imu_oy';
  static const imuOz = 'imu_oz';
  static const imuCal = 'imu_cal';

  // ── 클라우드 인증 (SupabaseService) ────────────────────────
  static const supabaseSession = 'supabase_session';
}
