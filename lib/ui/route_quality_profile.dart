import '../models/revv_route.dart';
import '../core/app_language.dart';
import 'app_copy.dart';

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

  factory RouteQualityProfile.fromRoute(
    RevvRoute route, {
    AppLanguage? language,
  }) {
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

    final typeLabel = _primaryTypeLabel(route, tags, language);
    final qualityScore = _qualityScore(route, curveRatio, controls);
    final curveDensityLabel = _curveDensityLabel(curveRatio, curvyKm, language);
    final riskLabel = _riskLabel(route, controls, language);
    final reasonLabel = _reasonLabel(
      route,
      typeLabel,
      curvyKm,
      controls,
      language,
    );

    return RouteQualityProfile(
      typeLabel: typeLabel,
      reasonLabel: reasonLabel,
      qualityScore: qualityScore,
      curveDensityLabel: curveDensityLabel,
      riskLabel: riskLabel,
      tags: tags,
      quickMetrics: [
        RouteQuickMetric(
          _label(language, '거리', 'Dist', 'Dist'),
          route.distanceDisplay,
        ),
        RouteQuickMetric(
          _label(language, '예상', 'ETA', 'Durée'),
          route.durationDisplay,
        ),
        RouteQuickMetric(
          _label(language, '커브', 'Curves', 'Virages'),
          '${curvyKm.toStringAsFixed(1)}km',
        ),
        RouteQuickMetric(
          _label(language, '흐름', 'Flow', 'Rythme'),
          '${route.maxContinuousKm.toStringAsFixed(1)}km',
        ),
        RouteQuickMetric(
          _label(language, '시작점', 'Start', 'Départ'),
          route.distanceFromUserDisplayFor(language ?? AppLanguage.korean),
        ),
        RouteQuickMetric(
          _label(language, '정지', 'Stops', 'Stops'),
          _controlsLabel(controls, language),
        ),
      ],
    );
  }

  bool hasTag(RouteQualityTag tag) => tags.contains(tag);
}

String _primaryTypeLabel(
  RevvRoute route,
  Set<RouteQualityTag> tags,
  AppLanguage? language,
) {
  if (tags.contains(RouteQualityTag.loop)) {
    return _label(language, '루프', 'Loop', 'Boucle');
  }
  if (tags.contains(RouteQualityTag.nearby)) {
    return _label(language, '근처', 'Nearby', 'Proche');
  }
  if (tags.contains(RouteQualityTag.tight)) {
    return _label(language, '타이트', 'Tight', 'Serré');
  }
  if (tags.contains(RouteQualityTag.sweeper)) {
    return _label(language, '스위퍼', 'Sweeper', 'Large');
  }
  if (tags.contains(RouteQualityTag.flow)) {
    return _label(language, '흐름', 'Flow', 'Rythme');
  }
  if (tags.contains(RouteQualityTag.long)) {
    return _label(language, '긴 루트', 'Long route', 'Longue');
  }
  if (tags.contains(RouteQualityTag.elevation)) {
    return _label(language, '고도 변화', 'Elevation', 'Dénivelé');
  }
  if (route.routeCharacter == 'hill_climb') {
    return _label(language, '고도 변화', 'Elevation', 'Dénivelé');
  }
  if (route.routeCharacter == 'tight_technical') {
    return _label(language, '타이트', 'Tight', 'Serré');
  }
  if (route.routeCharacter == 'fast_sweeper') {
    return _label(language, '스위퍼', 'Sweeper', 'Large');
  }
  return _label(language, '숨은 후보', 'Hidden pick', 'Option cachée');
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

String _curveDensityLabel(
  double curveRatio,
  double curvyKm,
  AppLanguage? language,
) {
  if (curvyKm < 0.5) {
    return _label(language, '완만한 흐름', 'Gentle flow', 'Rythme doux');
  }
  if (curveRatio >= 0.24) {
    return _label(language, '커브 밀도 높음', 'High curve density', 'Virages denses');
  }
  if (curveRatio >= 0.13) {
    return _label(
      language,
      '커브 밀도 보통',
      'Medium curve density',
      'Densité moyenne',
    );
  }
  return _label(language, '커브 듬성', 'Sparse curves', 'Virages espacés');
}

String _riskLabel(RevvRoute route, int controls, AppLanguage? language) {
  if (route.isPrivateLike) {
    return _label(
      language,
      '접근 제한 가능성 · 현장 표지 먼저 확인',
      'Possible restricted access · Check signs first',
      'Accès possiblement limité · Vérifiez les panneaux',
    );
  }
  if (route.isMajorRoadLike) {
    return _label(
      language,
      '간선도로 성격 섞임 · 교통 흐름 우선',
      'Major-road sections · Prioritize traffic flow',
      'Sections routières majeures · Priorité au trafic',
    );
  }
  if (route.isBridgeLike) {
    return _label(
      language,
      '브리지/합류 구간 · 차선 흐름 확인',
      'Bridge/merge sections · Read lane flow',
      'Ponts/fusions · Surveillez les voies',
    );
  }
  if (route.isConnectorLike) {
    return _label(
      language,
      '연결로 성격 섞임 · 진입/탈출 확인',
      'Connector sections · Check entry/exit',
      'Bretelles possibles · Vérifiez entrée/sortie',
    );
  }
  if (controls >= 6) {
    return _label(
      language,
      '정지 요소 $controls개 · 리듬이 끊길 수 있음',
      '$controls stops · Rhythm may break',
      '$controls arrêts · Le rythme peut casser',
    );
  }
  if (route.maxContinuousKm > 0 && route.maxContinuousKm < 0.8) {
    return _label(
      language,
      '연속 흐름 짧음 · 구간별로 다시 판단',
      'Short continuous flow · Reassess by segment',
      'Rythme court · Réévaluez par section',
    );
  }
  if (route.distanceKm >= 40) {
    return _label(
      language,
      '장거리 후보 · 연료와 복귀 동선 확인',
      'Long route · Check fuel and return path',
      'Long trajet · Vérifiez carburant et retour',
    );
  }
  return _label(
    language,
    '기본 주의 · 현장 표지와 노면 상태 우선',
    'Standard caution · Signs and road surface first',
    'Prudence · Panneaux et état de route d’abord',
  );
}

String _reasonLabel(
  RevvRoute route,
  String typeLabel,
  double curvyKm,
  int controls,
  AppLanguage? language,
) {
  if (route.isLoop) {
    return _label(
      language,
      '복귀 동선 단순 · 짧게 확인하기 좋은 루프형 후보',
      'Simple return path · Good short loop to test',
      'Retour simple · Bonne boucle courte à tester',
    );
  }
  if (route.distanceFromUser <= 18 || route.distanceKm <= 10) {
    return _label(
      language,
      '시작점 ${route.distanceFromUserDisplayFor(AppLanguage.korean)} · 바로 비교하기 좋은 근거리 후보',
      'Start ${route.distanceFromUserDisplayFor(AppLanguage.english)} · Easy nearby comparison',
      'Départ ${route.distanceFromUserDisplayFor(AppLanguage.french)} · Option proche à comparer',
    );
  }
  if (route.curveStyle == 'SWITCHBACK' || route.tightCurveKm >= 1.2) {
    return _label(
      language,
      '타이트 구간 ${route.tightCurveKm.toStringAsFixed(1)}km · 촘촘한 조향 리듬',
      '${route.tightCurveKm.toStringAsFixed(1)}km tight sections · Dense steering rhythm',
      '${route.tightCurveKm.toStringAsFixed(1)}km serrés · Rythme dense',
    );
  }
  if (route.curveStyle == 'SWEEPER' && route.mediumCurveKm >= 0.8) {
    return _label(
      language,
      '중간 커브 ${route.mediumCurveKm.toStringAsFixed(1)}km · 완만한 스위퍼 흐름',
      '${route.mediumCurveKm.toStringAsFixed(1)}km medium curves · Smooth sweeper flow',
      '${route.mediumCurveKm.toStringAsFixed(1)}km moyens · Grandes courbes fluides',
    );
  }
  if (route.maxContinuousKm >= 2.0 || route.flowScore >= 0.55) {
    return _label(
      language,
      '연속 흐름 ${route.maxContinuousKm.toStringAsFixed(1)}km · 중간 리듬 유지',
      '${route.maxContinuousKm.toStringAsFixed(1)}km continuous flow · Holds a steady rhythm',
      '${route.maxContinuousKm.toStringAsFixed(1)}km de rythme · Rythme stable',
    );
  }
  if (route.distanceKm >= 24) {
    return _label(
      language,
      '${route.distanceDisplay} · 길게 이어지는 비교 후보',
      '${route.distanceDisplay} · Longer comparison route',
      '${route.distanceDisplay} · Option plus longue',
    );
  }
  if (route.elevationDelta >= 45 || route.routeCharacter == 'hill_climb') {
    return _label(
      language,
      '고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m · 시야 전환이 있는 후보',
      '${route.elevationDelta.toStringAsFixed(0)}m elevation change · More visual transitions',
      '${route.elevationDelta.toStringAsFixed(0)}m de dénivelé · Changements de vue',
    );
  }
  if (controls == 0 && route.distanceKm >= 8) {
    return _label(
      language,
      '정지 요소 적음 · 흐름을 길게 읽기 좋은 후보',
      'Few stops · Good for reading longer flow',
      'Peu d’arrêts · Bon rythme prolongé',
    );
  }
  if (curvyKm >= 0.8) {
    return _label(
      language,
      '커브 집중 구간 ${curvyKm.toStringAsFixed(1)}km · 지도에서 비교할 만한 후보',
      '${curvyKm.toStringAsFixed(1)}km curve focus · Worth comparing on the map',
      '${curvyKm.toStringAsFixed(1)}km de virages · À comparer sur carte',
    );
  }
  return _label(
    language,
    '${route.distanceDisplay} · 숨은 와인딩 후보로 비교해볼 만함',
    '${route.distanceDisplay} · Hidden winding candidate',
    '${route.distanceDisplay} · Option sinueuse cachée',
  );
}

String _controlsLabel(int controls, AppLanguage? language) {
  if (language == null) return '$controls개';
  return AppCopy.t(
    language,
    ko: '$controls개',
    en: '$controls',
    fr: '$controls',
  );
}

String _label(AppLanguage? language, String ko, String en, String fr) {
  if (language == null) return ko;
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
