import '../models/revv_route.dart';
import '../services/route_loading_policy.dart';
import 'route_quality_profile.dart';

class CopilotRouteBriefing {
  final String headline;
  final String primaryAdvice;
  final String startAdvice;
  final String riskAdvice;
  final String fitLabel;
  final String nextActionLabel;
  final List<String> decisionChips;

  const CopilotRouteBriefing({
    required this.headline,
    required this.primaryAdvice,
    required this.startAdvice,
    required this.riskAdvice,
    required this.fitLabel,
    required this.nextActionLabel,
    required this.decisionChips,
  });

  factory CopilotRouteBriefing.fromRoute(
    RevvRoute route, {
    RouteQualityProfile? profile,
    double? startDistanceKm,
    RouteFilterStrength? filterStrength,
  }) {
    final p = profile ?? RouteQualityProfile.fromRoute(route);
    final startKm = startDistanceKm ?? route.distanceFromUser;
    final curvyKm = route.tightCurveKm + route.mediumCurveKm;
    final controls = route.stopSignCount + route.trafficSignalCount;
    final headline = _headline(route, p);
    final primary = _primaryAdvice(route, p, curvyKm, controls);
    final start = _startAdvice(startKm);
    final risk = _riskAdvice(route, p, controls, filterStrength);
    final fit = _fitLabel(route, p);

    return CopilotRouteBriefing(
      headline: headline,
      primaryAdvice: primary,
      startAdvice: start,
      riskAdvice: risk,
      fitLabel: fit,
      nextActionLabel: _nextActionLabel(startKm),
      decisionChips: _dedupe([
        p.typeLabel,
        _distanceChip(startKm),
        if (curvyKm >= 0.5) '커브 ${curvyKm.toStringAsFixed(1)}km',
        if (route.maxContinuousKm >= 0.8)
          '흐름 ${route.maxContinuousKm.toStringAsFixed(1)}km',
        if (controls > 0) '정지 $controls개',
        if (filterStrength != null) routeFilterStrengthLabel(filterStrength),
      ]).take(5).toList(),
    );
  }
}

String _headline(RevvRoute route, RouteQualityProfile profile) {
  if (route.isMajorRoadLike || route.isBridgeLike || route.isConnectorLike) {
    return '먼저 현장 흐름을 확인할 후보';
  }
  switch (profile.typeLabel) {
    case '타이트':
      return '조향 리듬을 촘촘히 읽는 후보';
    case '스위퍼':
      return '부드럽게 이어가는 스위퍼 후보';
    case '흐름':
      return '중간 리듬을 유지하기 좋은 후보';
    case '루프':
      return '복귀 동선이 단순한 루프 후보';
    case '긴 루트':
      return '긴 호흡으로 확인할 후보';
    case '고도 변화':
      return '시야 전환이 살아 있는 후보';
    case '근처':
      return '바로 비교하기 좋은 근거리 후보';
  }
  return '지도에서 먼저 읽어볼 후보';
}

String _primaryAdvice(
  RevvRoute route,
  RouteQualityProfile profile,
  double curvyKm,
  int controls,
) {
  if (profile.typeLabel == '타이트') {
    return '타이트 구간 ${route.tightCurveKm.toStringAsFixed(1)}km가 모여 있어 속도보다 진입 라인 판단이 핵심이에요.';
  }
  if (profile.typeLabel == '스위퍼') {
    return '중간 커브 ${route.mediumCurveKm.toStringAsFixed(1)}km가 이어져 부드러운 조향 흐름을 보기 좋아요.';
  }
  if (profile.typeLabel == '흐름') {
    return '코너 사이 간격이 자연스러워 페이스를 자주 끊지 않고 이어가기 좋은 후보예요.';
  }
  if (profile.typeLabel == '루프') {
    return '시작점과 복귀 동선이 단순해서 짧게 확인하고 돌아오기 좋은 루프예요.';
  }
  if (controls == 0 && route.maxContinuousKm >= 1.4) {
    return '정지 요소가 적고 ${route.maxContinuousKm.toStringAsFixed(1)}km 연속 흐름이 있어 리듬 잡기 좋아요.';
  }
  if (route.distanceKm >= 30) {
    return '${route.distanceDisplay}라 루트 전체보다 중간 휴식/복귀 동선까지 보고 시작하는 게 좋아요.';
  }
  if (curvyKm >= 0.8) {
    return '커브 집중 구간 ${curvyKm.toStringAsFixed(1)}km가 있어 지도에서 리듬이 살아나는 후보예요.';
  }
  return '${route.distanceDisplay} 안에서 부담 없이 루트 성격을 확인하기 좋은 후보예요.';
}

String _startAdvice(double startKm) {
  if (startKm < 1.0) {
    return '시작점까지 ${_distanceLabel(startKm)}라 바로 주행을 시작해도 자연스러워요.';
  }
  if (startKm < 10.0) {
    return '시작점까지 ${_distanceLabel(startKm)}라 먼저 이동한 뒤 본 루트에 진입하는 게 좋아요.';
  }
  return '시작점까지 ${_distanceLabel(startKm)}라 출발 전 지도에서 진입 동선을 먼저 확인하세요.';
}

String _riskAdvice(
  RevvRoute route,
  RouteQualityProfile profile,
  int controls,
  RouteFilterStrength? filterStrength,
) {
  if (route.isPrivateLike) return '접근 제한 가능성이 있어 현장 표지와 통행 가능 여부를 먼저 확인하세요.';
  if (route.isConnectorLike) return '연결로 성격이 섞여 있어 진입/탈출 지점을 먼저 확인하세요.';
  if (route.isBridgeLike) return '브리지/합류 구간이 섞여 있어 차선 흐름과 표지를 우선 확인하세요.';
  if (route.isMajorRoadLike) return '간선도로 성격이 섞인 후보라 교통 흐름과 제한 표지를 우선하세요.';
  if (controls >= 6) return '정지 요소가 $controls개 있어 중간 리듬이 끊길 수 있어요.';
  if (route.maxContinuousKm > 0 && route.maxContinuousKm < 0.8) {
    return '연속 흐름이 짧아 구간마다 다시 판단하는 쪽이 좋아요.';
  }
  final maybe = routeQualityLabel(route) == 'maybe';
  if (filterStrength == RouteFilterStrength.broad || maybe) {
    return '넓게 보기 후보라 품질 여유는 낮을 수 있어 지도 라인과 현장 표지를 함께 확인하세요.';
  }
  if (!profile.riskLabel.startsWith('기본 주의')) return profile.riskLabel;
  return '현장 표지, 노면 상태, 교통 흐름을 우선해서 차분히 확인하세요.';
}

String _fitLabel(RevvRoute route, RouteQualityProfile profile) {
  if (profile.typeLabel == '타이트') return '짧고 촘촘한 코너를 차분히 읽고 싶은 운전자';
  if (profile.typeLabel == '스위퍼') return '완만한 코너를 부드럽게 이어가고 싶은 운전자';
  if (profile.typeLabel == '흐름') return '중간 리듬을 끊기지 않게 유지하고 싶은 운전자';
  if (profile.typeLabel == '루프') return '복귀 동선까지 단순하게 확인하고 싶은 운전자';
  if (route.distanceKm >= 30) return '긴 호흡의 근교 드라이브를 원하는 운전자';
  return '부담 없이 새 루트를 비교해보고 싶은 운전자';
}

String _nextActionLabel(double startKm) {
  if (startKm < 1.0) return '바로 주행 시작';
  if (startKm < 10.0) return '시작점까지 이동 후 시작';
  return '지도 확인 후 주행 시작';
}

String _distanceChip(double distanceKm) {
  if (distanceKm < 1.0) return '시작점 ${(distanceKm * 1000).round()}m';
  return '시작점 ${distanceKm.toStringAsFixed(1)}km';
}

String _distanceLabel(double distanceKm) {
  if (distanceKm < 1.0) return '${(distanceKm * 1000).round()}m';
  return '${distanceKm.toStringAsFixed(1)}km';
}

List<String> _dedupe(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    result.add(trimmed);
  }
  return result;
}
