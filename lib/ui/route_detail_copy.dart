import '../models/revv_route.dart';
import '../services/route_loading_policy.dart';
import 'route_geometry_insight.dart';
import 'route_reading_context.dart';

class RouteDetailCopy {
  final String heroReason;
  final List<String> decisionBullets;
  final String? cautionLine;
  final String shareText;

  const RouteDetailCopy({
    required this.heroReason,
    required this.decisionBullets,
    required this.cautionLine,
    required this.shareText,
  });

  factory RouteDetailCopy.fromRoute(
    RevvRoute route, {
    double? startDistanceKm,
    bool hasComposite = false,
  }) {
    final insight = RouteGeometryInsight.fromRoute(route);
    final context = RouteReadingContext.fromRoute(route);
    final hero = _heroReason(route, insight);
    final caution = _cautionLine(route, insight);
    final bullets = _dedupe(
      [
        ..._balancedInsightBullets(insight.bullets, context.bullets),
        _shapeBullet(route),
        _flowBullet(route),
        _startBullet(startDistanceKm),
        _controlBullet(route),
        if (hasComposite) '체인 적용 중 · 첫 구간 뒤 다음 흐름까지 이어서 확인할 수 있어요.',
      ],
      blocked: {hero, ?caution},
    );

    return RouteDetailCopy(
      heroReason: hero,
      decisionBullets: bullets.take(6).toList(),
      cautionLine: caution,
      shareText: _shareText(route, hero, caution),
    );
  }
}

List<String> _balancedInsightBullets(
  List<String> geometryBullets,
  List<String> contextBullets,
) {
  return [
    if (geometryBullets.isNotEmpty) geometryBullets[0],
    if (contextBullets.isNotEmpty) contextBullets[0],
    if (contextBullets.length > 1) contextBullets[1],
    if (contextBullets.length > 2) contextBullets[2],
    if (geometryBullets.length > 1) geometryBullets[1],
    if (contextBullets.length > 3) contextBullets[3],
    ...geometryBullets.skip(2),
    ...contextBullets.skip(4),
  ];
}

String _heroReason(RevvRoute route, RouteGeometryInsight insight) {
  final injected = route.primaryReason?.trim();
  if ((injected?.isNotEmpty ?? false) && !_isLowSignalInjectedCopy(injected!)) {
    return injected;
  }
  if (insight.hasGeometry && insight.heroLine.trim().isNotEmpty) {
    return insight.heroLine;
  }

  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final character = route.routeCharacter.isNotEmpty
      ? route.routeCharacter
      : routeCharacter(route);
  if (curvyKm >= 0.8) {
    return '${route.distanceDisplay} 안에 커브 집중 구간 ${curvyKm.toStringAsFixed(1)}km가 살아 있는 루트예요.';
  }
  if (route.maxContinuousKm >= 1.2) {
    return '연속 흐름 ${route.maxContinuousKm.toStringAsFixed(1)}km가 있어 중간 리듬을 읽기 좋은 루트예요.';
  }
  if (route.elevationDelta >= 60) {
    return '고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m가 섞여 시야와 노면 변화를 함께 보는 루트예요.';
  }
  if (character == 'tight_technical') {
    return '${route.sharpCurveCount}개 코너가 짧게 모여 있어 진입 라인을 차분히 고르기 좋은 루트예요.';
  }
  if (character == 'fast_sweeper') {
    return '${route.distanceDisplay} 동안 완만한 중속 코너 흐름을 확인하기 좋은 루트예요.';
  }
  return '${route.distanceDisplay} 루트 · 거리와 코너 구성이 균형 잡힌 드라이브 코스예요.';
}

String _shapeBullet(RevvRoute route) {
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  if (curvyKm >= 0.5) {
    return '${route.distanceDisplay} 루트 · 커브 집중 구간 ${curvyKm.toStringAsFixed(1)}km';
  }
  return '${route.distanceDisplay} 루트 · 코너 ${route.sharpCurveCount}개 기준으로 검토';
}

String _flowBullet(RevvRoute route) {
  if (route.maxContinuousKm >= 1.2) {
    return '연속 흐름 ${route.maxContinuousKm.toStringAsFixed(1)}km · 중간 리듬 유지에 유리';
  }
  if (route.flowScore > 0) {
    return '흐름 점수 ${route.flowScore.toStringAsFixed(2)} · 정지 요소와 코너 간격을 함께 확인';
  }
  if (route.elevationDelta >= 45) {
    return '고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m · 시야 전환이 있는 구성';
  }
  return '코너와 완만한 구간이 섞여 있어 지도 라인을 먼저 확인하기 좋음';
}

String? _startBullet(double? startDistanceKm) {
  if (startDistanceKm == null) return null;
  if (startDistanceKm < 0.3) {
    return '시작점 ${_distanceLabel(startDistanceKm)} · 바로 진입 가능한 거리';
  }
  if (startDistanceKm < 5.0) {
    return '시작점까지 ${_distanceLabel(startDistanceKm)} · 안내 후 진입 추천';
  }
  return '시작점까지 ${_distanceLabel(startDistanceKm)} · 중간 합류 동선 먼저 확인';
}

String? _controlBullet(RevvRoute route) {
  final controls = route.stopSignCount + route.trafficSignalCount;
  if (controls == 0) return 'stop/sign 적음 · 흐름 유지에 유리';
  return 'stop/sign $controls개 · 중간 흐름이 끊기는 지점 확인 필요';
}

String? _cautionLine(RevvRoute route, RouteGeometryInsight insight) {
  final injected = route.cautionNote?.trim();
  if ((injected?.isNotEmpty ?? false) && !_isLowSignalInjectedCopy(injected!)) {
    return injected;
  }
  if (insight.cautionLine?.trim().isNotEmpty ?? false) {
    return insight.cautionLine;
  }

  final controls = route.stopSignCount + route.trafficSignalCount;
  if (controls >= 6) {
    return '정지 요소가 $controls개 있어 루트 중간 페이스가 끊길 수 있어요.';
  }
  if (route.maxContinuousKm > 0 && route.maxContinuousKm < 0.9) {
    return '연속 흐름이 짧은 편이라 구간마다 페이스를 다시 잡는 쪽이 좋아요.';
  }
  if (route.distanceKm >= 35) {
    return '거리가 긴 편이라 출발 전 연료와 휴식 포인트를 먼저 확인하세요.';
  }
  if (route.isMajorRoadLike || isMajorRoadLikeRouteName(route.name)) {
    return '일부 구간은 간선도로 성격이 섞일 수 있어 현장 표지를 확인하세요.';
  }
  if (route.isBridgeLike || isBridgeLikeRouteName(route.name)) {
    return '브리지 연결 구간이 포함될 수 있어 합류 지점을 미리 확인하세요.';
  }
  if (route.isPrivateLike) {
    return '접근 제한 가능성이 있어 현장 표지와 통행 가능 여부를 확인하세요.';
  }
  return null;
}

String _shareText(RevvRoute route, String hero, String? caution) {
  return [
    'REVV 추천 루트',
    route.name,
    '${route.distanceDisplay} · ${route.durationDisplay}',
    hero,
    ?caution,
  ].join('\n');
}

List<String> _dedupe(List<String?> lines, {Set<String> blocked = const {}}) {
  final seen = <String>{...blocked.map(_normalize)};
  final result = <String>[];
  for (final raw in lines) {
    final line = raw?.trim();
    if (line == null || line.isEmpty) continue;
    final key = _normalize(line);
    if (seen.contains(key)) continue;
    seen.add(key);
    result.add(line);
  }
  return result;
}

String _normalize(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

bool _isLowSignalInjectedCopy(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length >= 48) return false;
  if (RegExp(r'\d').hasMatch(normalized)) return false;
  final hasSpecificCue = RegExp(
    r'(초반|중반|후반|강변|호수|산|고도|마을|브리지|교차|정지|합류|진입|탈출|오르막|내리막)',
  ).hasMatch(normalized);
  if (hasSpecificCue) return false;
  return RegExp(r'(스위퍼|와인딩|리듬|좋은|추천|드라이브|코스|루트예요)').hasMatch(normalized);
}

String _distanceLabel(double distanceKm) {
  if (distanceKm < 1) return '${(distanceKm * 1000).round()}m';
  return '${distanceKm.toStringAsFixed(1)}km';
}
