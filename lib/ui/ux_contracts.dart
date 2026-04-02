import '../models/revv_route.dart';
import '../models/run_session.dart';
import '../services/route_loading_policy.dart';

enum CruiseUiState {
  idle,
  routeSelected,
  readyToStart,
}

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

RouteRecommendation buildRouteRecommendation(RevvRoute route) {
  final reason = primaryRouteReason(route) ??
      (route.distanceKm <= 15 && route.windingDensityPct >= 0.2
          ? '부담 없이 다녀오면서도 코너 감각을 살릴 수 있는 짧은 드라이브예요.'
          : '추천 이유 정리 중...');

  return RouteRecommendation(
    title: route.name,
    reason: reason,
    primaryMetrics: [
      route.distanceDisplay,
      route.durationDisplay,
      route.difficultyLabel,
    ],
    primaryCta: '이 루트로 달리기',
    advancedActions: const [
      '미리 보기',
      '고급 옵션',
    ],
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
      session.maxSpeedKmh > 0 ? session.maxSpeedKmh.toStringAsFixed(0) : '—',
    ],
    primaryActionLabel:
        session.route != null ? '같은 루트 다시 보기' : '기록 보기',
  );
}
