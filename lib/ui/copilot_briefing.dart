import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/route_loading_policy.dart';
import 'app_copy.dart';
import 'route_detail_copy.dart';
import 'route_quality_profile.dart';

class CopilotRouteBriefing {
  final String headline;
  final String primaryAdvice;
  final String startAdvice;
  final String riskAdvice;
  final String routeContextAdvice;
  final String fitLabel;
  final String nextActionLabel;
  final List<String> decisionChips;

  const CopilotRouteBriefing({
    required this.headline,
    required this.primaryAdvice,
    required this.startAdvice,
    required this.riskAdvice,
    required this.routeContextAdvice,
    required this.fitLabel,
    required this.nextActionLabel,
    required this.decisionChips,
  });

  factory CopilotRouteBriefing.fromRoute(
    RevvRoute route, {
    RouteQualityProfile? profile,
    double? startDistanceKm,
    RouteFilterStrength? filterStrength,
    AppLanguage? language,
  }) {
    final p =
        profile ?? RouteQualityProfile.fromRoute(route, language: language);
    final startKm = startDistanceKm ?? route.distanceFromUser;
    final curvyKm = route.tightCurveKm + route.mediumCurveKm;
    final controls = route.stopSignCount + route.trafficSignalCount;
    final headline = _headline(route, p, language);
    final primary = routeInformativePreviewLine(route, language: language);
    final start = _startAdvice(startKm, language);
    final risk = _riskAdvice(route, p, controls, filterStrength, language);
    final fit = _fitLabel(route, p, language);

    return CopilotRouteBriefing(
      headline: headline,
      primaryAdvice: primary,
      startAdvice: start,
      riskAdvice: risk,
      routeContextAdvice: _routeContextAdvice(route, language),
      fitLabel: fit,
      nextActionLabel: _nextActionLabel(startKm, language),
      decisionChips: _dedupe([
        p.typeLabel,
        _distanceChip(startKm, language),
        if (curvyKm >= 0.5)
          _text(
            language,
            '커브 ${curvyKm.toStringAsFixed(1)}km',
            'Curves ${curvyKm.toStringAsFixed(1)}km',
            'Virages ${curvyKm.toStringAsFixed(1)}km',
          ),
        if (route.maxContinuousKm >= 0.8)
          _text(
            language,
            '흐름 ${route.maxContinuousKm.toStringAsFixed(1)}km',
            'Flow ${route.maxContinuousKm.toStringAsFixed(1)}km',
            'Flow ${route.maxContinuousKm.toStringAsFixed(1)}km',
          ),
        if (controls > 0)
          _text(
            language,
            '정지 $controls개',
            'Stops $controls',
            'Stops $controls',
          ),
        if (filterStrength != null) _strengthLabel(filterStrength, language),
      ]).take(5).toList(),
    );
  }
}

String _routeContextAdvice(RevvRoute route, AppLanguage? language) {
  final facts = <String>[
    if (route.stopSignCount > 0)
      _text(
        language,
        '정지표지 ${route.stopSignCount}',
        '${route.stopSignCount} stop signs',
        '${route.stopSignCount} arrêts',
      ),
    if (route.trafficSignalCount > 0)
      _text(
        language,
        '신호 ${route.trafficSignalCount}',
        '${route.trafficSignalCount} signals',
        '${route.trafficSignalCount} feux',
      ),
    if (route.surfaceSummary.trim().isNotEmpty)
      _text(
        language,
        '노면 ${route.surfaceSummary.trim()}',
        'surface ${route.surfaceSummary.trim()}',
        'surface ${route.surfaceSummary.trim()}',
      ),
    if (route.speedLimitSummary.trim().isNotEmpty)
      _text(
        language,
        '제한속도 정보 ${route.speedLimitSummary.trim()}',
        'limit data ${route.speedLimitSummary.trim()}',
        'limites ${route.speedLimitSummary.trim()}',
      ),
  ];
  final caution = route.cautionNote?.trim();
  if ((language == null || language == AppLanguage.korean) &&
      caution != null &&
      caution.isNotEmpty) {
    facts.add(caution);
  }
  if (facts.isEmpty) return '';
  return _text(
    language,
    '루트 전체 · ${facts.join(' · ')}',
    'Route-wide · ${facts.join(' · ')}',
    'Route entière · ${facts.join(' · ')}',
  );
}

String _headline(
  RevvRoute route,
  RouteQualityProfile profile,
  AppLanguage? language,
) {
  if (route.isMajorRoadLike || route.isBridgeLike || route.isConnectorLike) {
    return _text(
      language,
      '먼저 현장 흐름을 확인할 후보',
      'Check real-road flow first',
      'À vérifier sur place',
    );
  }
  if (profile.hasTag(RouteQualityTag.tight)) {
    return _text(
      language,
      '조향 리듬을 촘촘히 읽는 후보',
      'Dense steering rhythm',
      'Rythme serré à lire',
    );
  }
  if (profile.hasTag(RouteQualityTag.sweeper)) {
    return _text(
      language,
      '부드럽게 이어가는 스위퍼 후보',
      'Smooth sweeper candidate',
      'Grandes courbes fluides',
    );
  }
  if (profile.hasTag(RouteQualityTag.flow)) {
    return _text(
      language,
      '중간 리듬을 유지하기 좋은 후보',
      'Good steady-flow candidate',
      'Bon rythme continu',
    );
  }
  if (profile.hasTag(RouteQualityTag.loop)) {
    return _text(
      language,
      '복귀 동선이 단순한 루프 후보',
      'Simple loop candidate',
      'Boucle simple',
    );
  }
  if (profile.hasTag(RouteQualityTag.long)) {
    return _text(
      language,
      '긴 호흡으로 확인할 후보',
      'Longer route to assess',
      'Route à long souffle',
    );
  }
  if (profile.hasTag(RouteQualityTag.elevation)) {
    return _text(
      language,
      '시야 전환이 살아 있는 후보',
      'Elevation and sightline changes',
      'Dénivelé et vision variée',
    );
  }
  if (profile.hasTag(RouteQualityTag.nearby)) {
    return _text(
      language,
      '바로 비교하기 좋은 근거리 후보',
      'Nearby route to compare now',
      'Option proche à comparer',
    );
  }
  return _text(
    language,
    '지도에서 먼저 읽어볼 후보',
    'Read it on the map first',
    'À lire sur la carte',
  );
}

String _startAdvice(double startKm, AppLanguage? language) {
  if (startKm < 1.0) {
    return _text(
      language,
      '시작점까지 ${_distanceLabel(startKm)}라 바로 주행을 시작해도 자연스러워요.',
      'Start is ${_distanceLabel(startKm)} away. Starting now is natural.',
      'Départ à ${_distanceLabel(startKm)}. Vous pouvez commencer ici.',
    );
  }
  if (startKm < 10.0) {
    return _text(
      language,
      '시작점까지 ${_distanceLabel(startKm)}라 먼저 이동한 뒤 본 루트에 진입하는 게 좋아요.',
      'Start is ${_distanceLabel(startKm)} away. Navigate there, then enter the route.',
      'Départ à ${_distanceLabel(startKm)}. Allez-y d’abord, puis entrez dans la route.',
    );
  }
  return _text(
    language,
    '시작점까지 ${_distanceLabel(startKm)}라 출발 전 지도에서 진입 동선을 먼저 확인하세요.',
    'Start is ${_distanceLabel(startKm)} away. Check the approach before driving.',
    'Départ à ${_distanceLabel(startKm)}. Vérifiez l’approche avant de partir.',
  );
}

String _riskAdvice(
  RevvRoute route,
  RouteQualityProfile profile,
  int controls,
  RouteFilterStrength? filterStrength,
  AppLanguage? language,
) {
  if (route.isPrivateLike) {
    return _text(
      language,
      '접근 제한 가능성이 있어 현장 표지와 통행 가능 여부를 먼저 확인하세요.',
      'Possible restricted access. Check signs and access before committing.',
      'Accès possiblement limité. Vérifiez les panneaux.',
    );
  }
  if (route.isConnectorLike) {
    return _text(
      language,
      '연결로 성격이 섞여 있어 진입/탈출 지점을 먼저 확인하세요.',
      'Connector sections mixed in. Check entry and exit points.',
      'Bretelles possibles. Vérifiez entrée et sortie.',
    );
  }
  if (route.isBridgeLike) {
    return _text(
      language,
      '브리지/합류 구간이 섞여 있어 차선 흐름과 표지를 우선 확인하세요.',
      'Bridge or merge sections. Prioritize lane flow and signs.',
      'Ponts ou fusions. Priorité aux voies et panneaux.',
    );
  }
  if (route.isMajorRoadLike) {
    return _text(
      language,
      '간선도로 성격이 섞인 후보라 교통 흐름과 제한 표지를 우선하세요.',
      'Major-road character mixed in. Prioritize traffic flow and limits.',
      'Route majeure possible. Priorité au trafic et limites.',
    );
  }
  if (controls >= 6) {
    return _text(
      language,
      '정지 요소가 $controls개 있어 중간 리듬이 끊길 수 있어요.',
      '$controls stops can break the middle rhythm.',
      '$controls arrêts peuvent casser le rythme.',
    );
  }
  if (route.maxContinuousKm > 0 && route.maxContinuousKm < 0.8) {
    return _text(
      language,
      '연속 흐름이 짧아 구간마다 다시 판단하는 쪽이 좋아요.',
      'Continuous flow is short. Reassess each segment.',
      'Rythme continu court. Réévaluez chaque section.',
    );
  }
  final maybe = routeQualityLabel(route) == 'maybe';
  if (filterStrength == RouteFilterStrength.broad || maybe) {
    return _text(
      language,
      '넓게 보기 후보라 품질 여유는 낮을 수 있어 지도 라인과 현장 표지를 함께 확인하세요.',
      'Broad-mode candidate. Quality margin may be lower; check map line and signs.',
      'Option en mode large. Qualité moins sûre; vérifiez carte et panneaux.',
    );
  }
  if (!profile.riskLabel.startsWith('기본 주의') &&
      !profile.riskLabel.startsWith('Standard caution') &&
      !profile.riskLabel.startsWith('Prudence')) {
    return profile.riskLabel;
  }
  return _text(
    language,
    '현장 표지, 노면 상태, 교통 흐름을 우선해서 차분히 확인하세요.',
    'Read signs, surface, and traffic flow first.',
    'Lisez panneaux, surface et trafic d’abord.',
  );
}

String _fitLabel(
  RevvRoute route,
  RouteQualityProfile profile,
  AppLanguage? language,
) {
  if (profile.hasTag(RouteQualityTag.tight)) {
    return _text(
      language,
      '짧고 촘촘한 코너를 차분히 읽고 싶은 운전자',
      'Drivers who like reading tight corners calmly',
      'Pour lire des virages serrés calmement',
    );
  }
  if (profile.hasTag(RouteQualityTag.sweeper)) {
    return _text(
      language,
      '완만한 코너를 부드럽게 이어가고 싶은 운전자',
      'Drivers who like smooth sweeping corners',
      'Pour grandes courbes fluides',
    );
  }
  if (profile.hasTag(RouteQualityTag.flow)) {
    return _text(
      language,
      '중간 리듬을 끊기지 않게 유지하고 싶은 운전자',
      'Drivers who want steady mid-route rhythm',
      'Pour garder un rythme continu',
    );
  }
  if (profile.hasTag(RouteQualityTag.loop)) {
    return _text(
      language,
      '복귀 동선까지 단순하게 확인하고 싶은 운전자',
      'Drivers who want a simple return path',
      'Pour un retour simple',
    );
  }
  if (route.distanceKm >= 30) {
    return _text(
      language,
      '긴 호흡의 근교 드라이브를 원하는 운전자',
      'Drivers looking for a longer backroad drive',
      'Pour une sortie plus longue',
    );
  }
  return _text(
    language,
    '부담 없이 새 루트를 비교해보고 싶은 운전자',
    'Drivers comparing new routes without commitment',
    'Pour comparer sans engagement',
  );
}

String _nextActionLabel(double startKm, AppLanguage? language) {
  if (startKm < 1.0) {
    return _text(
      language,
      '바로 주행 시작',
      'Start drive now',
      'Démarrer maintenant',
    );
  }
  if (startKm < 10.0) {
    return _text(
      language,
      '시작점까지 이동 후 시작',
      'Navigate to start first',
      'Aller au départ',
    );
  }
  return _text(
    language,
    '지도 확인 후 주행 시작',
    'Check map, then start',
    'Vérifier puis partir',
  );
}

String _distanceChip(double distanceKm, AppLanguage? language) {
  final label = _text(language, '시작점', 'Start', 'Départ');
  if (distanceKm < 1.0) return '$label ${(distanceKm * 1000).round()}m';
  return '$label ${distanceKm.toStringAsFixed(1)}km';
}

String _distanceLabel(double distanceKm) {
  if (distanceKm < 1.0) return '${(distanceKm * 1000).round()}m';
  return '${distanceKm.toStringAsFixed(1)}km';
}

String _strengthLabel(RouteFilterStrength strength, AppLanguage? language) {
  if (language == null) return routeFilterStrengthLabel(strength);
  return switch (strength) {
    RouteFilterStrength.precise => AppCopy.t(
      language,
      ko: '정밀',
      en: 'Precise',
      fr: 'Précis',
    ),
    RouteFilterStrength.balanced => AppCopy.t(
      language,
      ko: '균형',
      en: 'Balanced',
      fr: 'Équilibré',
    ),
    RouteFilterStrength.broad => AppCopy.t(
      language,
      ko: '넓게',
      en: 'Broad',
      fr: 'Large',
    ),
  };
}

String _text(AppLanguage? language, String ko, String en, String fr) {
  if (language == null) return ko;
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
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
