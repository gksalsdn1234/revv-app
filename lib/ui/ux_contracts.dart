import '../models/revv_route.dart';
import '../models/run_session.dart';
import '../services/route_loading_policy.dart';
import '../services/route_service.dart';

enum CruiseUiState { idle, routeSelected, readyToStart }

CruiseUiState resolveCruiseUiState({
  required bool hasSelectedRoute,
  required bool nearRouteStart,
}) {
  if (!hasSelectedRoute) return CruiseUiState.idle;
  if (nearRouteStart) return CruiseUiState.readyToStart;
  return CruiseUiState.routeSelected;
}

class RouteRecommendation {
  final String title;
  final String reason;
  final List<String> primaryMetrics;
  final String primaryCta;
  final List<String> advancedActions;

  const RouteRecommendation({
    required this.title,
    required this.reason,
    required this.primaryMetrics,
    required this.primaryCta,
    required this.advancedActions,
  });
}

String describeRouteQuality(String qualityLabel) {
  switch (qualityLabel) {
    case 'keep':
      return '추천';
    case 'maybe':
      return '가볍게 검토';
    case 'reject':
      return '비추천';
    default:
      return '추천';
  }
}

String describeRouteCharacter(String character) {
  switch (character) {
    case 'tight_technical':
      return '타이트 코너';
    case 'fast_sweeper':
      return '스위퍼 중심';
    case 'rhythmic_flow':
      return '흐름 중심';
    case 'hill_climb':
      return '업힐 성향';
    case 'mixed_touring':
      return '투어링 밸런스';
    default:
      return '드라이브 밸런스';
  }
}

RouteRecommendation buildRouteRecommendation(RevvRoute route) {
  final reason =
      routePrimaryReason(route) ??
      (route.distanceKm <= 15 && route.windingDensityPct >= 0.2
          ? '가볍게 나서기 좋은 짧은 와인딩 드라이브예요.'
          : route.distanceKm >= 28
          ? '여유롭게 길게 달리기 좋은 드라이브 코스예요.'
          : '달리는 맛이 있는 드라이브 루트예요.');

  final characterLabel = describeRouteCharacter(
    route.routeCharacter.isNotEmpty
        ? route.routeCharacter
        : routeCharacter(route),
  );

  return RouteRecommendation(
    title: route.name,
    reason: reason,
    primaryMetrics: [
      route.distanceDisplay,
      route.durationDisplay,
      characterLabel,
    ],
    primaryCta: '이 루트로 달리기',
    advancedActions: const ['미리 보기', '고급 옵션'],
  );
}

class RunReviewSummary {
  final String headline;
  final List<String> topStats;
  final String primaryActionLabel;

  const RunReviewSummary({
    required this.headline,
    required this.topStats,
    required this.primaryActionLabel,
  });
}

RunReviewSummary resolveRunReviewSummary(RunSession session) {
  final headline = session.distanceKm >= 20
      ? '오늘 드라이브, 꽤 제대로 즐겼어요.'
      : session.maxLateralG >= 0.4
      ? '짧지만 인상적인 주행이었어요.'
      : '가볍게 달리기 좋은 한 번이었어요.';

  return RunReviewSummary(
    headline: headline,
    topStats: [
      session.distanceKm.toStringAsFixed(1),
      session.durationDisplay,
      session.avgSpeedKmh > 0 ? session.avgSpeedKmh.toStringAsFixed(0) : '—',
    ],
    primaryActionLabel: session.route != null ? '같은 루트 다시 보기' : '기록 보기',
  );
}

String describeSprintStartMode(SprintStartMode mode) {
  switch (mode) {
    case SprintStartMode.auto:
      return '자동 시작';
    case SprintStartMode.guideToStart:
      return '시작점 안내';
    case SprintStartMode.joinFromCurrent:
      return '현재 위치 합류';
  }
}

String buildSprintStartSummary(double startDistanceKm, SprintStartMode mode) {
  final distanceLabel = startDistanceKm < 1
      ? '${(startDistanceKm * 1000).round()}m'
      : '${startDistanceKm.toStringAsFixed(1)}km';
  switch (mode) {
    case SprintStartMode.auto:
      return startDistanceKm < 0.3
          ? '시작점까지 $distanceLabel 정도라 자동 모드로 바로 시작해도 자연스러워요. 가까우면 현장에서 HUD/내비 선택이 나옵니다.'
          : '시작점까지 $distanceLabel 떨어져 있어요. 자동 모드는 시작점까지 안내한 뒤 본 루트에 진입하는 흐름을 기본으로 잡습니다.';
    case SprintStartMode.guideToStart:
      return '시작점까지 $distanceLabel 이동한 뒤 루트 본편에 들어가는 모드예요. 처음 타는 길이면 가장 안전한 선택입니다.';
    case SprintStartMode.joinFromCurrent:
      return '현재 위치에서 바로 루트 흐름에 합류해요. 시작점으로 돌아가지 않고 현재 위치 기준으로 주행을 이어갑니다.';
  }
}

String sprintStartCtaLabel(SprintStartMode mode) {
  switch (mode) {
    case SprintStartMode.auto:
      return '이 설정으로 시작';
    case SprintStartMode.guideToStart:
      return '시작점까지 안내 후 시작';
    case SprintStartMode.joinFromCurrent:
      return '현재 위치에서 바로 합류';
  }
}

String describeRoutePhaseKorean(double progress) {
  if (progress >= 0.95) return '마지막 구간';
  if (progress >= 0.75) return '후반 흐름';
  if (progress >= 0.35) return '메인 섹션';
  return '초반 진입';
}

String describeRoutePhaseCompact(double progress) {
  if (progress >= 0.95) return 'FINISHING';
  if (progress >= 0.75) return 'LATE SECTION';
  if (progress >= 0.35) return 'MID SECTION';
  return 'EARLY SECTION';
}

String describeRouteGap(double gapKm) {
  if (gapKm <= 0) return '';
  if (gapKm >= 1) return '${gapKm.toStringAsFixed(1)}km 이탈';
  return '${(gapKm * 1000).round()}m 이탈';
}
