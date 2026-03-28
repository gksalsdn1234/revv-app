/// Firestore 컬렉션/문서 경로 중앙 관리
///
/// 경로 변경 시 이 파일만 수정하면 됨.
///
/// 현재 구조 (revv-eb7c9 프로젝트):
///
///   users/{uid}/
///     runs/{runId}               → RunSummary (경량, ~1KB)
///     discovered_routes/{routeId} → RevvRoute (개인 캐시 — preload용)
///
///   routes/{routeId}             → RevvRoute (전역 커뮤니티 풀)
///     runs/{uid}                 → 유저별 주행 기록 (서브컬렉션)
///
/// 인증: Firebase Anonymous Auth (익명 로그인)
/// 보안 규칙: firestore.rules
class FirestorePaths {
  FirestorePaths._();

  // ── 런 기록 ───────────────────────────────────────────────
  static String runsCollection(String uid) => 'users/$uid/runs';
  static String runDoc(String uid, String runId) => 'users/$uid/runs/$runId';

  // ── 개인 발견 루트 캐시 (preload용) ──────────────────────
  static String routesCollection(String uid) => 'users/$uid/discovered_routes';
  static String routeDoc(String uid, String routeId) =>
      'users/$uid/discovered_routes/$routeId';

  // ── 전역 커뮤니티 루트 풀 ─────────────────────────────────
  static String globalRoutes() => 'routes';
  static String globalRoute(String routeId) => 'routes/$routeId';
  static String globalRouteRuns(String routeId) => 'routes/$routeId/runs';
  static String globalRouteRun(String routeId, String uid) =>
      'routes/$routeId/runs/$uid';
}
