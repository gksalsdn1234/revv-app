import 'dart:math' as math;

import '../models/revv_route.dart';

class RouteGeometryInsight {
  final bool hasGeometry;
  final String heroLine;
  final List<String> bullets;
  final String? cautionLine;
  final String briefContext;

  const RouteGeometryInsight({
    required this.hasGeometry,
    required this.heroLine,
    required this.bullets,
    required this.cautionLine,
    required this.briefContext,
  });

  factory RouteGeometryInsight.fromRoute(RevvRoute route) {
    final nodes = route.nodes;
    if (nodes.length < 4 || route.distanceKm <= 0) {
      return const RouteGeometryInsight(
        hasGeometry: false,
        heroLine: '',
        bullets: [],
        cautionLine: null,
        briefContext: '실제 좌표 샘플이 부족해서 요약 지표 중심으로 판단해야 합니다.',
      );
    }

    final segments = <_Segment>[];
    var cumulativeKm = 0.0;
    for (var i = 0; i < nodes.length - 1; i++) {
      final distanceKm = RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
      if (distanceKm <= 0) continue;
      final bearing = _bearing(nodes[i], nodes[i + 1]);
      segments.add(
        _Segment(
          startKm: cumulativeKm,
          endKm: cumulativeKm + distanceKm,
          distanceKm: distanceKm,
          bearing: bearing,
        ),
      );
      cumulativeKm += distanceKm;
    }
    if (segments.length < 3 || cumulativeKm <= 0) {
      return const RouteGeometryInsight(
        hasGeometry: false,
        heroLine: '',
        bullets: [],
        cautionLine: null,
        briefContext: '실제 좌표 샘플이 부족해서 요약 지표 중심으로 판단해야 합니다.',
      );
    }

    final thirds = [
      _ThirdStats('초반', 0, cumulativeKm / 3),
      _ThirdStats('중반', cumulativeKm / 3, cumulativeKm * 2 / 3),
      _ThirdStats('후반', cumulativeKm * 2 / 3, cumulativeKm),
    ];

    var totalTurn = 0.0;
    var tightTurns = 0;
    var mediumTurns = 0;
    var longestCalmKm = 0.0;
    var currentCalmKm = 0.0;

    for (var i = 1; i < segments.length; i++) {
      final previous = segments[i - 1];
      final current = segments[i];
      final turn = _angleDelta(previous.bearing, current.bearing);
      final positionKm = current.startKm;
      final owner = thirds.firstWhere(
        (third) => positionKm >= third.startKm && positionKm <= third.endKm,
        orElse: () => thirds.last,
      );
      owner.turnEnergy += turn;
      owner.distanceKm += current.distanceKm;
      if (turn >= 55) {
        owner.tightTurns += 1;
        tightTurns += 1;
      } else if (turn >= 24) {
        owner.mediumTurns += 1;
        mediumTurns += 1;
      }
      totalTurn += turn;

      if (turn < 12) {
        currentCalmKm += current.distanceKm;
        longestCalmKm = math.max(longestCalmKm, currentCalmKm);
      } else {
        currentCalmKm = 0;
      }
    }

    final strongest = List<_ThirdStats>.from(thirds)
      ..sort((a, b) => b.turnEnergy.compareTo(a.turnEnergy));
    final primary = strongest.first;
    final secondary = strongest.length > 1 ? strongest[1] : primary;
    final turnDensity = totalTurn / cumulativeKm;
    final tightRatio = tightTurns / math.max(1, tightTurns + mediumTurns);
    final directionLabel = _directionLabel(
      _angleDelta(segments.first.bearing, segments.last.bearing),
    );

    final heroLine = _heroLine(
      route: route,
      primary: primary,
      secondary: secondary,
      turnDensity: turnDensity,
      tightRatio: tightRatio,
      directionLabel: directionLabel,
    );

    final bullets = <String>[
      '${primary.label}에 방향 전환이 가장 몰림 · 누적 회전 ${primary.turnEnergy.toStringAsFixed(0)}°',
      _turnMixLine(tightTurns, mediumTurns, tightRatio),
      if (secondary.turnEnergy > primary.turnEnergy * 0.55)
        '${secondary.label}까지 굴곡이 이어져 한 구간짜리 루트보다 흐름이 길어요.',
      if (longestCalmKm >= 1.0)
        '가장 긴 완만한 구간 ${longestCalmKm.toStringAsFixed(1)}km · 호흡을 정리할 틈이 있어요.',
      '전체 방향 변화는 $directionLabel · 지도에서 진입/탈출 방향을 확인하기 좋아요.',
    ];

    return RouteGeometryInsight(
      hasGeometry: true,
      heroLine: heroLine,
      bullets: bullets,
      cautionLine: _cautionLine(
        route: route,
        strongest: primary,
        longestCalmKm: longestCalmKm,
        turnDensity: turnDensity,
      ),
      briefContext:
          '좌표 기반 분석: ${primary.label} 굴곡 집중, '
          'tight=$tightTurns, medium=$mediumTurns, '
          'turnDensity=${turnDensity.toStringAsFixed(1)}deg/km, '
          'longestCalm=${longestCalmKm.toStringAsFixed(1)}km, '
          'overall=$directionLabel.',
    );
  }
}

String _heroLine({
  required RevvRoute route,
  required _ThirdStats primary,
  required _ThirdStats secondary,
  required double turnDensity,
  required double tightRatio,
  required String directionLabel,
}) {
  final routeName = route.name.trim().isEmpty ? '이 루트' : route.name.trim();
  if (primary.turnEnergy <= 0) {
    return '$routeName는 큰 방향 전환보다 완만한 흐름을 길게 읽는 쪽에 가까운 루트예요.';
  }
  if (tightRatio >= 0.55) {
    return '$routeName는 ${primary.label}에 짧은 방향 전환이 몰려 있어, 진입 전에 라인과 탈출 방향을 먼저 읽어야 하는 구성이에요.';
  }
  if (turnDensity >= 70) {
    return '$routeName는 ${primary.label}부터 ${secondary.label}까지 굴곡 에너지가 이어져, 한 번 타고 끝나는 직선형 루트보다 길을 계속 읽게 만드는 편이에요.';
  }
  if (directionLabel == '돌아나오는 형태') {
    return '$routeName는 전체적으로 돌아나오는 형태라 시작과 끝의 방향 전환을 같이 보는 루프 감각의 루트예요.';
  }
  return '$routeName는 ${primary.label}에 핵심 굴곡이 있고 나머지 구간은 흐름을 정리하며 이어지는, 구조가 비교적 분명한 루트예요.';
}

String _turnMixLine(int tightTurns, int mediumTurns, double tightRatio) {
  if (tightTurns == 0 && mediumTurns == 0) {
    return '큰 조향 포인트는 적음 · 풍경/흐름 확인용에 가까워요.';
  }
  if (tightRatio >= 0.55) {
    return '짧은 코너 $tightTurns개 중심 · 조향 타이밍이 촘촘한 편이에요.';
  }
  if (mediumTurns >= tightTurns * 2) {
    return '중간 각도 코너 $mediumTurns개 중심 · 급한 조작보다 흐름 유지가 중요해요.';
  }
  return '짧은 코너 $tightTurns개와 중간 코너 $mediumTurns개가 섞인 혼합형이에요.';
}

String? _cautionLine({
  required RevvRoute route,
  required _ThirdStats strongest,
  required double longestCalmKm,
  required double turnDensity,
}) {
  if (strongest.tightTurns >= 4) {
    return '${strongest.label}에 짧은 방향 전환이 몰려 있어 처음 주행할 때는 진입 속도보다 시야 확보를 우선하세요.';
  }
  if (turnDensity >= 85) {
    return '굴곡 밀도가 높은 편이라 코너 하나보다 다음 코너 위치를 같이 보고 들어가는 게 좋아요.';
  }
  if (longestCalmKm >= route.distanceKm * 0.28 && route.distanceKm >= 10) {
    return '완만한 구간 뒤 다시 굴곡이 나오는 구조라 리듬이 풀리는 지점을 조심하세요.';
  }
  return null;
}

String _directionLabel(double delta) {
  if (delta >= 135) return '돌아나오는 형태';
  if (delta >= 75) return '크게 꺾이는 형태';
  if (delta >= 35) return '방향을 서서히 바꾸는 형태';
  return '한 방향으로 뻗는 형태';
}

double _bearing(LatLng from, LatLng to) {
  final lat1 = _rad(from.lat);
  final lat2 = _rad(to.lat);
  final dLng = _rad(to.lng - from.lng);
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _angleDelta(double a, double b) {
  var delta = (a - b).abs() % 360;
  if (delta > 180) delta = 360 - delta;
  return delta;
}

double _rad(double degree) => degree * math.pi / 180;

class _Segment {
  final double startKm;
  final double endKm;
  final double distanceKm;
  final double bearing;

  const _Segment({
    required this.startKm,
    required this.endKm,
    required this.distanceKm,
    required this.bearing,
  });
}

class _ThirdStats {
  final String label;
  final double startKm;
  final double endKm;
  double distanceKm = 0;
  double turnEnergy = 0;
  int tightTurns = 0;
  int mediumTurns = 0;

  _ThirdStats(this.label, this.startKm, this.endKm);
}
