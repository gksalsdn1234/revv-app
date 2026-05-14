import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/route_loading_policy.dart';
import 'app_copy.dart';
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
    AppLanguage? language,
  }) {
    if (language != null && language != AppLanguage.korean) {
      return _localizedRouteDetailCopy(
        route,
        startDistanceKm: startDistanceKm,
        hasComposite: hasComposite,
        language: language,
      );
    }
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

RouteDetailCopy _localizedRouteDetailCopy(
  RevvRoute route, {
  required AppLanguage language,
  double? startDistanceKm,
  bool hasComposite = false,
}) {
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final controls = route.stopSignCount + route.trafficSignalCount;
  final hero = _localizedHero(route, curvyKm, language);
  final caution = _localizedCaution(route, controls, language);
  final bullets = _dedupe(
    [
      _localizedShapeBullet(route, curvyKm, language),
      _localizedFlowBullet(route, language),
      _localizedStartBullet(startDistanceKm, language),
      _localizedControlBullet(controls, language),
      if (route.elevationDelta >= 45)
        AppCopy.t(
          language,
          ko: '${route.elevationDelta.toStringAsFixed(0)}m 고도 변화 · 시야가 빠르게 바뀔 수 있음',
          en: '${route.elevationDelta.toStringAsFixed(0)}m elevation change · sightlines may change quickly',
          fr: '${route.elevationDelta.toStringAsFixed(0)}m de dénivelé · la visibilité peut changer vite',
        ),
      if (hasComposite)
        AppCopy.t(
          language,
          ko: '체인 모드 · 다음 구간으로 넘어가기 전 첫 구간을 먼저 읽기',
          en: 'Chain mode · read the first section before committing to the next',
          fr: 'Mode chaîne · lisez la première section avant d’enchaîner',
        ),
    ],
    blocked: {hero, ?caution},
  );

  return RouteDetailCopy(
    heroReason: hero,
    decisionBullets: bullets.take(6).toList(),
    cautionLine: caution,
    shareText: _localizedShareText(route, hero, caution, language),
  );
}

String _localizedHero(RevvRoute route, double curvyKm, AppLanguage language) {
  if (curvyKm >= 0.8) {
    return AppCopy.t(
      language,
      ko: '${route.distanceDisplay} · 커브 집중 구간 ${curvyKm.toStringAsFixed(1)}km',
      en: '${route.distanceDisplay} with ${curvyKm.toStringAsFixed(1)}km of curve-focused sections.',
      fr: '${route.distanceDisplay} avec ${curvyKm.toStringAsFixed(1)}km de sections à virages.',
    );
  }
  if (route.maxContinuousKm >= 1.2) {
    return AppCopy.t(
      language,
      ko: '${route.maxContinuousKm.toStringAsFixed(1)}km 연속 흐름이 있어 루트를 읽기 좋습니다.',
      en: '${route.maxContinuousKm.toStringAsFixed(1)}km of continuous flow makes this route easy to read.',
      fr: '${route.maxContinuousKm.toStringAsFixed(1)}km de rythme continu rendent la route lisible.',
    );
  }
  if (route.elevationDelta >= 60) {
    return AppCopy.t(
      language,
      ko: '${route.elevationDelta.toStringAsFixed(0)}m 고도 변화가 시야와 노면 변화를 더합니다.',
      en: '${route.elevationDelta.toStringAsFixed(0)}m of elevation change adds sightline and surface variation.',
      fr: '${route.elevationDelta.toStringAsFixed(0)}m de dénivelé ajoutent des changements de vue et de surface.',
    );
  }
  if (route.routeCharacter == 'tight_technical') {
    return AppCopy.t(
      language,
      ko: '${route.sharpCurveCount}개 코너가 촘촘히 모여 있어 차분한 진입 라인이 중요합니다.',
      en: '${route.sharpCurveCount} corners grouped tightly. Focus on calm entry lines.',
      fr: '${route.sharpCurveCount} virages regroupés. Priorité aux lignes d’entrée calmes.',
    );
  }
  if (route.routeCharacter == 'fast_sweeper') {
    return AppCopy.t(
      language,
      ko: '${route.distanceDisplay} 동안 완만한 중간 속도 커브 흐름이 이어집니다.',
      en: '${route.distanceDisplay} of smoother medium-speed curve flow.',
      fr: '${route.distanceDisplay} de grandes courbes plus fluides.',
    );
  }
  return AppCopy.t(
    language,
    ko: '${route.distanceDisplay} · 거리와 코너 구성이 균형 잡힌 루트입니다.',
    en: '${route.distanceDisplay} route with a balanced distance and corner mix.',
    fr: '${route.distanceDisplay} avec un bon équilibre distance/virages.',
  );
}

String _localizedShapeBullet(
  RevvRoute route,
  double curvyKm,
  AppLanguage language,
) {
  if (curvyKm >= 0.5) {
    return AppCopy.t(
      language,
      ko: '${route.distanceDisplay} 루트 · 커브 집중 ${curvyKm.toStringAsFixed(1)}km',
      en: '${route.distanceDisplay} route · ${curvyKm.toStringAsFixed(1)}km curve focus',
      fr: '${route.distanceDisplay} · ${curvyKm.toStringAsFixed(1)}km de virages',
    );
  }
  return AppCopy.t(
    language,
    ko: '${route.distanceDisplay} 루트 · 주요 코너 ${route.sharpCurveCount}개',
    en: '${route.distanceDisplay} route · ${route.sharpCurveCount} notable corners',
    fr: '${route.distanceDisplay} · ${route.sharpCurveCount} virages notables',
  );
}

String _localizedFlowBullet(RevvRoute route, AppLanguage language) {
  if (route.maxContinuousKm >= 1.2) {
    return AppCopy.t(
      language,
      ko: '${route.maxContinuousKm.toStringAsFixed(1)}km 연속 흐름 · 리듬 유지에 유리',
      en: '${route.maxContinuousKm.toStringAsFixed(1)}km continuous flow · good rhythm retention',
      fr: '${route.maxContinuousKm.toStringAsFixed(1)}km de rythme · bon maintien du rythme',
    );
  }
  if (route.flowScore > 0) {
    return AppCopy.t(
      language,
      ko: '흐름 점수 ${route.flowScore.toStringAsFixed(2)} · 정지 요소와 코너 간격 확인',
      en: 'Flow score ${route.flowScore.toStringAsFixed(2)} · check stops and corner spacing',
      fr: 'Score rythme ${route.flowScore.toStringAsFixed(2)} · vérifiez arrêts et espacement',
    );
  }
  return AppCopy.t(
    language,
    ko: '코너와 완만한 구간 혼합 · 지도 라인 먼저 확인',
    en: 'Mixed corners and gentle sections · read the map line first',
    fr: 'Virages et sections douces · lire la ligne sur carte d’abord',
  );
}

String? _localizedStartBullet(double? startDistanceKm, AppLanguage language) {
  if (startDistanceKm == null) return null;
  if (startDistanceKm < 0.3) {
    return AppCopy.t(
      language,
      ko: '시작점 ${_distanceLabel(startDistanceKm)} · 바로 진입 가능',
      en: 'Start ${_distanceLabel(startDistanceKm)} · close enough to enter now',
      fr: 'Départ ${_distanceLabel(startDistanceKm)} · entrée directe possible',
    );
  }
  if (startDistanceKm < 5.0) {
    return AppCopy.t(
      language,
      ko: '시작점까지 ${_distanceLabel(startDistanceKm)} · 먼저 이동 후 진입',
      en: 'Start ${_distanceLabel(startDistanceKm)} away · navigate first, then enter',
      fr: 'Départ à ${_distanceLabel(startDistanceKm)} · naviguer d’abord',
    );
  }
  return AppCopy.t(
    language,
    ko: '시작점까지 ${_distanceLabel(startDistanceKm)} · 진입 동선 먼저 확인',
    en: 'Start ${_distanceLabel(startDistanceKm)} away · check approach before joining',
    fr: 'Départ à ${_distanceLabel(startDistanceKm)} · vérifier l’approche',
  );
}

String _localizedControlBullet(int controls, AppLanguage language) {
  if (controls == 0) {
    return AppCopy.t(
      language,
      ko: '정지 요소 적음 · 흐름 유지에 유리',
      en: 'Few stop/sign controls · better flow continuity',
      fr: 'Peu de stops/feux · meilleur rythme',
    );
  }
  return AppCopy.t(
    language,
    ko: '정지/신호 $controls개 · 리듬이 끊기는 지점 확인',
    en: '$controls stops/signals · check where the rhythm breaks',
    fr: '$controls stops/feux · repérer les ruptures de rythme',
  );
}

String? _localizedCaution(RevvRoute route, int controls, AppLanguage language) {
  if (controls >= 6) {
    return AppCopy.t(
      language,
      ko: '정지/신호 $controls개가 중간 리듬을 끊을 수 있습니다.',
      en: '$controls stops/signals may break the mid-route rhythm.',
      fr: '$controls stops/feux peuvent casser le rythme.',
    );
  }
  if (route.maxContinuousKm > 0 && route.maxContinuousKm < 0.9) {
    return AppCopy.t(
      language,
      ko: '연속 흐름이 짧습니다. 구간별로 페이스를 다시 판단하세요.',
      en: 'Continuous flow is short. Reassess pace segment by segment.',
      fr: 'Rythme continu court. Réévaluez section par section.',
    );
  }
  if (route.distanceKm >= 35) {
    return AppCopy.t(
      language,
      ko: '긴 루트입니다. 출발 전 연료, 시간, 복귀 동선을 확인하세요.',
      en: 'Longer route. Check fuel, time, and return path before starting.',
      fr: 'Route plus longue. Vérifiez carburant, temps et retour.',
    );
  }
  if (route.isMajorRoadLike || isMajorRoadLikeRouteName(route.name)) {
    return AppCopy.t(
      language,
      ko: '일부 구간은 간선도로처럼 느껴질 수 있습니다. 표지를 먼저 확인하세요.',
      en: 'Some sections may behave like major roads. Read signs first.',
      fr: 'Certaines sections peuvent être des axes majeurs. Lisez les panneaux.',
    );
  }
  if (route.isBridgeLike || isBridgeLikeRouteName(route.name)) {
    return AppCopy.t(
      language,
      ko: '브리지/합류 구간이 포함될 수 있습니다. 합류 지점을 확인하세요.',
      en: 'Bridge or merge sections may be included. Check merge points.',
      fr: 'Ponts ou fusions possibles. Vérifiez les points de fusion.',
    );
  }
  if (route.isPrivateLike) {
    return AppCopy.t(
      language,
      ko: '접근 제한 가능성이 있습니다. 진입 전 표지와 통행 가능 여부를 확인하세요.',
      en: 'Possible restricted access. Check signs and access before entering.',
      fr: 'Accès possiblement limité. Vérifiez les panneaux avant d’entrer.',
    );
  }
  return null;
}

String _localizedShareText(
  RevvRoute route,
  String hero,
  String? caution,
  AppLanguage language,
) {
  return [
    AppCopy.t(
      language,
      ko: 'REVV 추천 루트',
      en: 'REVV route pick',
      fr: 'Route REVV',
    ),
    route.name,
    '${route.distanceDisplay} · ${route.durationDisplay}',
    hero,
    ?caution,
  ].join('\n');
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
