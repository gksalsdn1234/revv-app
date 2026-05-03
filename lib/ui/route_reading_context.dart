import 'dart:math' as math;

import '../models/revv_route.dart';

class RouteReadingContext {
  final List<String> bullets;
  final String briefContext;

  const RouteReadingContext({
    required this.bullets,
    required this.briefContext,
  });

  factory RouteReadingContext.fromRoute(RevvRoute route) {
    final road = _roadLine(route);
    final namedRoad = _namedRoadLine(route);
    final surface = _surfaceLine(route);
    final speed = _speedLine(route);
    final poi = _poiLine(route);
    final elevation = _elevationLine(route);
    final controls = _controlLine(route);
    final routeType = _routeTypeLine(route);
    final bullets = [
      ?namedRoad,
      ?road,
      ?surface,
      ?elevation,
      ?speed,
      ?poi,
      ?controls,
      ?routeType,
    ];

    return RouteReadingContext(
      bullets: bullets,
      briefContext: [
        if (namedRoad != null) '주요 도로: $namedRoad',
        if (road != null) '도로 성격: $road',
        if (surface != null) '노면: $surface',
        if (speed != null) '제한속도: $speed',
        if (poi != null) '주변 맥락: $poi',
        if (elevation != null) '고도/시야: $elevation',
        if (controls != null) '정지 요소: $controls',
        if (routeType != null) '루트 성격: $routeType',
      ].join(' / '),
    );
  }
}

String? _namedRoadLine(RevvRoute route) {
  final names = route.roadNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .take(3)
      .toList();
  if (names.isEmpty) return null;
  if (names.length == 1) {
    return '${names.first} 중심 · 실제 도로명을 기준으로 따라가기 쉬워요.';
  }
  return '${names.join(' / ')} 구간이 이어짐 · 도로명이 바뀌는 지점을 확인하세요.';
}

String? _surfaceLine(RevvRoute route) {
  final surface = route.surfaceSummary.trim();
  if (surface.isEmpty) return null;
  if (surface == 'asphalt' || surface == 'paved') {
    return '노면 정보 $surface · 기본 포장도로로 잡혀 있어요.';
  }
  return '노면 정보 $surface · 실제 포장 상태를 먼저 확인하세요.';
}

String? _speedLine(RevvRoute route) {
  final speed = route.speedLimitSummary.trim();
  if (speed.isEmpty) return null;
  return '제한속도 표기 $speed · 현장 표지 기준으로 진입하세요.';
}

String? _poiLine(RevvRoute route) {
  final pois = route.nearbyPoiNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .take(2)
      .toList();
  if (pois.isEmpty) return null;
  if (pois.length == 1) {
    return '${pois.first} 주변 · 루트의 위치 맥락이 비교적 분명해요.';
  }
  return '${pois.join(' / ')} 주변을 지남 · 풍경/진입 맥락을 같이 읽기 좋아요.';
}

String? _roadLine(RevvRoute route) {
  final bucket = route.roadClassBucket.trim();
  if (route.isPrivateLike) {
    return '접근 제한 가능성이 있는 구간 · 현장 표지 확인이 먼저예요.';
  }
  if (route.isBridgeLike) {
    return '브리지/연결도로 성격 · 합류와 차선 흐름을 먼저 확인해야 해요.';
  }
  if (route.isConnectorLike) {
    return '연결로 성격이 섞임 · 짧은 진입/탈출 판단이 중요한 구간이에요.';
  }
  if (route.isMajorRoadLike) {
    return '간선도로 성격이 섞임 · 루트 재미보다 교통 흐름 확인이 우선이에요.';
  }
  if (bucket.contains('rural')) {
    return '이름 있는 외곽도로 성격 · 본선 흐름과 주변 진입로를 같이 봐야 해요.';
  }
  if (bucket.contains('residential')) {
    return '생활도로 성격이 섞임 · 시야보다 보행자/교차로 확인이 먼저예요.';
  }
  if (bucket.contains('named')) {
    return '이름 있는 도로 기반 · 지도상 루트 추적이 비교적 쉬운 편이에요.';
  }
  if (!route.isNamed || route.name.trim().isEmpty) {
    return '이름 정보가 약한 후보 · 실제 표지와 지도 라인을 같이 확인해야 해요.';
  }
  return null;
}

String? _elevationLine(RevvRoute route) {
  final profile = route.elevationProfile;
  if (profile != null && profile.length >= 2) {
    var gain = 0.0;
    var loss = 0.0;
    for (var i = 1; i < profile.length; i++) {
      final diff = profile[i] - profile[i - 1];
      if (diff > 0) {
        gain += diff;
      } else {
        loss += diff.abs();
      }
    }
    final range = profile.reduce(math.max) - profile.reduce(math.min);
    if (gain + loss < 25 && range < 20) {
      return '고도 변화가 작음 · 노면 흐름과 코너 간격을 읽는 쪽이에요.';
    }
    if (gain > loss * 1.35) {
      return '상승 ${gain.toStringAsFixed(0)}m 중심 · 시야가 열리는 지점을 체크하세요.';
    }
    if (loss > gain * 1.35) {
      return '하강 ${loss.toStringAsFixed(0)}m 중심 · 다음 코너 위치를 일찍 확인하세요.';
    }
    return '상승 ${gain.toStringAsFixed(0)}m/하강 ${loss.toStringAsFixed(0)}m · 리듬 변화가 있는 루트예요.';
  }
  if (route.elevationDelta >= 80) {
    return '고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m · 시야와 노면 전환이 섞여 있어요.';
  }
  if (route.elevationDelta >= 35) {
    return '완만한 고도 변화 ${route.elevationDelta.toStringAsFixed(0)}m · 코너 뒤 시야 변화를 확인하세요.';
  }
  return null;
}

String? _controlLine(RevvRoute route) {
  final controls = route.stopSignCount + route.trafficSignalCount;
  if (controls >= 6) {
    return 'stop/sign $controls개 · 흐름이 끊기는 구간이 꽤 있어요.';
  }
  if (controls >= 3) {
    return 'stop/sign $controls개 · 중간 합류와 정지 리듬을 감안해야 해요.';
  }
  if (controls == 0 && route.distanceKm >= 8) {
    return '정지 요소가 거의 없음 · 루트 라인을 길게 읽기 좋아요.';
  }
  return null;
}

String? _routeTypeLine(RevvRoute route) {
  final character = route.routeCharacter.trim();
  if (route.isLoop) {
    return '시작점과 끝점이 가까운 루프형 · 복귀 동선이 단순한 편이에요.';
  }
  if (character == 'hill_climb') {
    return '고도 변화가 섞인 클라임형 · 코너보다 시야 전환을 같이 봐야 해요.';
  }
  if (character == 'tight_technical') {
    return '타이트한 기술형 · 짧은 조향 포인트가 연속될 가능성이 높아요.';
  }
  if (character == 'fast_sweeper') {
    return '넓은 스위퍼형 · 급한 조작보다 일정한 흐름 확인에 가까워요.';
  }
  return null;
}
