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
    final hero = routeInformativePreviewLine(route);
    final caution = routeInformativeCautionLine(route);
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
  final controls = route.stopSignCount + route.trafficSignalCount;
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final hero = routeInformativePreviewLine(route, language: language);
  final caution = routeInformativeCautionLine(route, language: language);
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

String routeInformativePreviewLine(RevvRoute route, {AppLanguage? language}) {
  final curvyKm = route.tightCurveKm + route.mediumCurveKm;
  final controls = route.stopSignCount + route.trafficSignalCount;
  final stopSummary = controls == 0
      ? _text(
          language,
          '정지 요소는 0개라 흐름을 읽기 좋아요.',
          '0 stop controls, so the flow is easier to read.',
          '0 arrêt/feu, donc le rythme se lit plus facilement.',
        )
      : _text(
          language,
          '정지 요소는 $controls개예요.',
          '$controls stop controls are on the route.',
          '$controls arrêts/feux sur la route.',
        );
  final character = route.routeCharacter.isNotEmpty
      ? route.routeCharacter
      : routeCharacter(route);
  if (_tightCurveRatio(route) >= 0.12 && route.tightCurveKm >= 0.8) {
    return _pickInformativeText(route, 'preview_tight', [
      _text(
        language,
        '타이트 커브 ${route.tightCurveKm.toStringAsFixed(1)}km가 전체 ${route.distanceKm.toStringAsFixed(0)}km 중 ${_percentLabel(_tightCurveRatio(route))}예요. 최장 연속 와인딩은 ${route.maxContinuousKm.toStringAsFixed(1)}km입니다.',
        '${route.tightCurveKm.toStringAsFixed(1)}km of tight curves, ${_percentLabel(_tightCurveRatio(route))} of the ${route.distanceKm.toStringAsFixed(0)}km route. Longest continuous winding is ${route.maxContinuousKm.toStringAsFixed(1)}km.',
        '${route.tightCurveKm.toStringAsFixed(1)}km de virages serrés, ${_percentLabel(_tightCurveRatio(route))} des ${route.distanceKm.toStringAsFixed(0)}km. Enchaînement le plus long: ${route.maxContinuousKm.toStringAsFixed(1)}km.',
      ),
      _text(
        language,
        '${route.sharpCurveCount}개 주요 코너와 타이트 커브 ${route.tightCurveKm.toStringAsFixed(1)}km가 모여 있어요. $stopSummary',
        '${route.sharpCurveCount} notable corners and ${route.tightCurveKm.toStringAsFixed(1)}km of tight curves are grouped here. $stopSummary',
        '${route.sharpCurveCount} virages notables et ${route.tightCurveKm.toStringAsFixed(1)}km de serré sont regroupés. $stopSummary',
      ),
    ]);
  }
  if (route.maxContinuousKm >= 1.8) {
    return _pickInformativeText(route, 'preview_continuous', [
      _text(
        language,
        '최장 연속 와인딩 ${route.maxContinuousKm.toStringAsFixed(1)}km가 있고 커브 구간은 ${curvyKm.toStringAsFixed(1)}km예요. $stopSummary',
        '${route.maxContinuousKm.toStringAsFixed(1)}km longest continuous winding with ${curvyKm.toStringAsFixed(1)}km of curve sections. $stopSummary',
        '${route.maxContinuousKm.toStringAsFixed(1)}km d’enchaînement continu avec ${curvyKm.toStringAsFixed(1)}km de virages. $stopSummary',
      ),
      _text(
        language,
        '${route.distanceDisplay} · 예상 ${estimatedDriveMinutes(route)}분 안에 ${route.maxContinuousKm.toStringAsFixed(1)}km 연속 구간이 들어 있어요.',
        '${route.distanceDisplay} · about ${estimatedDriveMinutes(route)} min with a ${route.maxContinuousKm.toStringAsFixed(1)}km continuous section.',
        '${route.distanceDisplay} · environ ${estimatedDriveMinutes(route)} min avec ${route.maxContinuousKm.toStringAsFixed(1)}km continus.',
      ),
    ]);
  }
  if (route.elevationDelta >= 60) {
    return _text(
      language,
      '고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m와 커브 구간 ${curvyKm.toStringAsFixed(1)}km가 함께 있어 시야 변화가 잦아요.',
      '${route.elevationDelta.toStringAsFixed(0)}m of elevation change with ${curvyKm.toStringAsFixed(1)}km of curve sections, so sightlines change often.',
      '${route.elevationDelta.toStringAsFixed(0)}m de dénivelé avec ${curvyKm.toStringAsFixed(1)}km de virages; la visibilité change souvent.',
    );
  }
  if (character == 'tight_technical') {
    return _text(
      language,
      '${route.sharpCurveCount}개 주요 코너가 ${route.distanceKm.toStringAsFixed(0)}km 안에 모여 있고 타이트 커브는 ${route.tightCurveKm.toStringAsFixed(1)}km예요.',
      '${route.sharpCurveCount} notable corners within ${route.distanceKm.toStringAsFixed(0)}km, including ${route.tightCurveKm.toStringAsFixed(1)}km of tight curves.',
      '${route.sharpCurveCount} virages notables sur ${route.distanceKm.toStringAsFixed(0)}km, dont ${route.tightCurveKm.toStringAsFixed(1)}km serrés.',
    );
  }
  if (character == 'fast_sweeper') {
    return _text(
      language,
      '중간 커브 ${route.mediumCurveKm.toStringAsFixed(1)}km와 최장 연속 ${route.maxContinuousKm.toStringAsFixed(1)}km가 이어지는 ${route.distanceDisplay} 루트예요.',
      '${route.distanceDisplay} route with ${route.mediumCurveKm.toStringAsFixed(1)}km of medium curves and ${route.maxContinuousKm.toStringAsFixed(1)}km longest continuous flow.',
      '${route.distanceDisplay} avec ${route.mediumCurveKm.toStringAsFixed(1)}km de virages moyens et ${route.maxContinuousKm.toStringAsFixed(1)}km continus au plus long.',
    );
  }
  if (route.isLoop) {
    return _text(
      language,
      '${route.distanceDisplay} 루프라 복귀 동선이 단순하고 예상 소요는 ${estimatedDriveMinutes(route)}분이에요.',
      '${route.distanceDisplay} loop with a simple return path; estimated time is ${estimatedDriveMinutes(route)} min.',
      'Boucle de ${route.distanceDisplay}; retour simple, durée estimée ${estimatedDriveMinutes(route)} min.',
    );
  }
  return _text(
    language,
    '${route.distanceDisplay} · 예상 ${estimatedDriveMinutes(route)}분, 커브 구간 ${curvyKm.toStringAsFixed(1)}km와 정지 요소 $controls개를 보고 판단하세요.',
    '${route.distanceDisplay} · about ${estimatedDriveMinutes(route)} min, with ${curvyKm.toStringAsFixed(1)}km of curve sections and $controls stop controls.',
    '${route.distanceDisplay} · environ ${estimatedDriveMinutes(route)} min, avec ${curvyKm.toStringAsFixed(1)}km de virages et $controls arrêts/feux.',
  );
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

String? routeInformativeCautionLine(RevvRoute route, {AppLanguage? language}) {
  final injected = route.cautionNote?.trim();
  if (injected?.isNotEmpty ?? false) {
    return injected;
  }

  final controls = route.stopSignCount + route.trafficSignalCount;
  if (_tightCurveRatio(route) >= 0.14 && route.tightCurveKm >= 1.0) {
    return _text(
      language,
      '타이트 커브 비중이 높아요. 초반 몇 개는 여유 있게 진입하며 라인과 시야를 먼저 읽으세요.',
      'Tight curves take a high share. Give the first few entries extra margin and read line plus sightline first.',
      'La part de virages serrés est élevée. Gardez de la marge au début et lisez ligne et visibilité.',
    );
  }
  if (route.maxContinuousKm >= 3.0) {
    return _text(
      language,
      '긴 연속 구간이라 집중 유지가 필요해요. 중간 여유 지점에서 쉬어가세요.',
      'Long continuous section. Keep attention steady and use a calm point for a break.',
      'Long enchaînement continu. Gardez l’attention et faites une pause au point calme.',
    );
  }
  if (_stopControlDensity(route, controls) >= 0.35 || controls >= 6) {
    return _text(
      language,
      '정지 요소가 잦아요. 재가속 반복 구간이라 표지와 교차 흐름을 먼저 확인하세요.',
      'Stop controls are frequent. Expect repeated re-entry points; read signs and cross traffic first.',
      'Arrêts fréquents. Attendez-vous à des reprises; lisez panneaux et trafic transversal.',
    );
  }
  if (route.isMajorRoadLike || isMajorRoadLikeRouteName(route.name)) {
    return _text(
      language,
      '간선도로 성격이 섞일 수 있어요. 교차 흐름, 차선 변화, 제한 표지를 먼저 확인하세요.',
      'Major-road character may be mixed in. Read cross traffic, lane changes, and limit signs first.',
      'Des sections de grand axe peuvent apparaître. Vérifiez trafic transversal, voies et panneaux.',
    );
  }
  if (route.isBridgeLike || isBridgeLikeRouteName(route.name)) {
    return _text(
      language,
      '브리지/합류 구간이 섞일 수 있어요. 합류 지점과 차선 흐름을 먼저 확인하세요.',
      'Bridge or merge sections may be mixed in. Check merge points and lane flow first.',
      'Ponts ou fusions possibles. Vérifiez points de fusion et voies.',
    );
  }
  if (route.sharpCurveCount >= 10 && route.distanceKm <= 14) {
    return _text(
      language,
      '커브 밀도가 높아 도로 폭과 시야를 먼저 읽으세요.',
      'Curve density is high. Read road width and sightlines first.',
      'Densité de virages élevée. Lisez largeur de route et visibilité d’abord.',
    );
  }
  if (route.isPrivateLike) {
    return _text(
      language,
      '접근 제한 가능성이 있어요. 진입 전 표지와 통행 가능 여부를 확인하세요.',
      'Access may be restricted. Check signs and access before entering.',
      'Accès possiblement limité. Vérifiez les panneaux avant d’entrer.',
    );
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

String _pickInformativeText(
  RevvRoute route,
  String salt,
  List<String> options,
) {
  return options[_routeTextVariant(route, salt, options.length)];
}

int _routeTextVariant(RevvRoute route, String salt, int modulo) {
  if (modulo <= 1) return 0;
  final key = '${route.id}|${route.name}|$salt';
  var hash = 0;
  for (final code in key.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash % modulo;
}

double _tightCurveRatio(RevvRoute route) {
  if (route.distanceKm <= 0) return 0;
  return route.tightCurveKm / route.distanceKm;
}

double _stopControlDensity(RevvRoute route, int controls) {
  if (route.stopControlDensity > 0) return route.stopControlDensity;
  if (route.distanceKm <= 0) return 0;
  return controls / route.distanceKm;
}

String _percentLabel(double value) => '${(value * 100).round()}%';

String _text(AppLanguage? language, String ko, String en, String fr) {
  if (language == null) return ko;
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}

String _distanceLabel(double distanceKm) {
  if (distanceKm < 1) return '${(distanceKm * 1000).round()}m';
  return '${distanceKm.toStringAsFixed(1)}km';
}
