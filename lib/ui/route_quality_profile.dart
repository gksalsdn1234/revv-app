import '../models/revv_route.dart';

class RouteQuickMetric {
  final String label;
  final String value;

  const RouteQuickMetric(this.label, this.value);
}

enum RouteQualityTag { nearby, tight, sweeper, flow, loop, long, elevation }

class RouteQualityProfile {
  final String typeLabel;
  final String reasonLabel;
  final int qualityScore;
  final String curveDensityLabel;
  final String riskLabel;
  final List<RouteQuickMetric> quickMetrics;
  final Set<RouteQualityTag> tags;

  const RouteQualityProfile({
    required this.typeLabel,
    required this.reasonLabel,
    required this.qualityScore,
    required this.curveDensityLabel,
    required this.riskLabel,
    required this.quickMetrics,
    required this.tags,
  });

  factory RouteQualityProfile.fromRoute(RevvRoute route) {
    final curvyKm = route.tightCurveKm + route.mediumCurveKm;
    final curveRatio = route.distanceKm <= 0 ? 0.0 : curvyKm / route.distanceKm;
    final controls = route.stopSignCount + route.trafficSignalCount;
    final tags = <RouteQualityTag>{};

    if (route.distanceFromUser <= 18 || route.distanceKm <= 10) {
      tags.add(RouteQualityTag.nearby);
    }
    if (route.isLoop) tags.add(RouteQualityTag.loop);
    if (route.curveStyle == 'SWITCHBACK' || route.tightCurveKm >= 1.2) {
      tags.add(RouteQualityTag.tight);
    }
    if (route.curveStyle == 'SWEEPER' && route.mediumCurveKm >= 0.8) {
      tags.add(RouteQualityTag.sweeper);
    }
    if (route.maxContinuousKm >= 2.0 || route.flowScore >= 0.55) {
      tags.add(RouteQualityTag.flow);
    }
    if (route.distanceKm >= 24) tags.add(RouteQualityTag.long);
    if (route.elevationDelta >= 45) tags.add(RouteQualityTag.elevation);

    final typeLabel = _primaryTypeLabel(route, tags);
    final qualityScore = _qualityScore(route, curveRatio, controls);
    final curveDensityLabel = _curveDensityLabel(curveRatio, curvyKm);
    final riskLabel = _riskLabel(route, controls);
    final reasonLabel = _reasonLabel(route, typeLabel, curvyKm, controls);

    return RouteQualityProfile(
      typeLabel: typeLabel,
      reasonLabel: reasonLabel,
      qualityScore: qualityScore,
      curveDensityLabel: curveDensityLabel,
      riskLabel: riskLabel,
      tags: tags,
      quickMetrics: [
        RouteQuickMetric('거리', route.distanceDisplay),
        RouteQuickMetric('예상', route.durationDisplay),
        RouteQuickMetric('커브', '${curvyKm.toStringAsFixed(1)}km'),
        RouteQuickMetric('흐름', '${route.maxContinuousKm.toStringAsFixed(1)}km'),
        RouteQuickMetric('시작점', route.distanceFromUserDisplay),
        RouteQuickMetric('정지', '$controls개'),
      ],
    );
  }

  bool hasTag(RouteQualityTag tag) => tags.contains(tag);
}

String _primaryTypeLabel(RevvRoute route, Set<RouteQualityTag> tags) {
  if (tags.contains(RouteQualityTag.loop)) return '루프';
  if (tags.contains(RouteQualityTag.nearby)) return '근처';
  if (tags.contains(RouteQualityTag.tight)) return '타이트';
  if (tags.contains(RouteQualityTag.sweeper)) return '스위퍼';
  if (tags.contains(RouteQualityTag.flow)) return '흐름';
  if (tags.contains(RouteQualityTag.long)) return '긴 루트';
  if (tags.contains(RouteQualityTag.elevation)) return '고도 변화';
  if (route.routeCharacter == 'hill_climb') return '고도 변화';
  if (route.routeCharacter == 'tight_technical') return '타이트';
  if (route.routeCharacter == 'fast_sweeper') return '스위퍼';
  return '숨은 후보';
}

int _qualityScore(RevvRoute route, double curveRatio, int controls) {
  var score = 46.0;
  score += (curveRatio * 100).clamp(0, 35) * 0.70;
  score += route.maxContinuousKm.clamp(0, 3.2) * 6.0;
  if (route.isLoop) score += 5;
  if (route.distanceFromUser <= 18) score += 5;
  if (route.distanceKm >= 12 && route.distanceKm <= 36) score += 5;
  if (route.elevationDelta >= 45) score += 4;
  if (route.routeCharacter == 'tight_technical' ||
      route.routeCharacter == 'fast_sweeper') {
    score += 4;
  }
  score -= controls.clamp(0, 8) * 2.6;
  if (route.isPrivateLike || route.isMajorRoadLike || route.isConnectorLike) {
    score -= 7;
  }
  return score.round().clamp(35, 96);
}

String _curveDensityLabel(double curveRatio, double curvyKm) {
  if (curvyKm < 0.5) return '완만한 흐름';
  if (curveRatio >= 0.24) return '커브 밀도 높음';
  if (curveRatio >= 0.13) return '커브 밀도 보통';
  return '커브 듬성';
}

String _riskLabel(RevvRoute route, int controls) {
  if (route.isPrivateLike) return '접근 제한 가능성 · 현장 표지 먼저 확인';
  if (route.isMajorRoadLike) return '간선도로 성격 섞임 · 교통 흐름 우선';
  if (route.isBridgeLike) return '브리지/합류 구간 · 차선 흐름 확인';
  if (route.isConnectorLike) return '연결로 성격 섞임 · 진입/탈출 확인';
  if (controls >= 6) return '정지 요소 $controls개 · 리듬이 끊길 수 있음';
  if (route.maxContinuousKm > 0 && route.maxContinuousKm < 0.8) {
    return '연속 흐름 짧음 · 구간별로 다시 판단';
  }
  if (route.distanceKm >= 40) return '장거리 후보 · 연료와 복귀 동선 확인';
  return '기본 주의 · 현장 표지와 노면 상태 우선';
}

String _reasonLabel(
  RevvRoute route,
  String typeLabel,
  double curvyKm,
  int controls,
) {
  if (typeLabel == '루프') return '복귀 동선 단순 · 짧게 확인하기 좋은 루프형 후보';
  if (typeLabel == '근처') {
    return '시작점 ${route.distanceFromUserDisplay} · 바로 비교하기 좋은 근거리 후보';
  }
  if (typeLabel == '타이트') {
    return '타이트 구간 ${route.tightCurveKm.toStringAsFixed(1)}km · 촘촘한 조향 리듬';
  }
  if (typeLabel == '스위퍼') {
    return '중간 커브 ${route.mediumCurveKm.toStringAsFixed(1)}km · 완만한 스위퍼 흐름';
  }
  if (typeLabel == '흐름') {
    return '연속 흐름 ${route.maxContinuousKm.toStringAsFixed(1)}km · 중간 리듬 유지';
  }
  if (typeLabel == '긴 루트') return '${route.distanceDisplay} · 길게 이어지는 비교 후보';
  if (typeLabel == '고도 변화') {
    return '고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m · 시야 전환이 있는 후보';
  }
  if (controls == 0 && route.distanceKm >= 8) {
    return '정지 요소 적음 · 흐름을 길게 읽기 좋은 후보';
  }
  if (curvyKm >= 0.8) {
    return '커브 집중 구간 ${curvyKm.toStringAsFixed(1)}km · 지도에서 비교할 만한 후보';
  }
  return '${route.distanceDisplay} · 숨은 와인딩 후보로 비교해볼 만함';
}
