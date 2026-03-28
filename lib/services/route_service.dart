import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';
import '../core/storage_keys.dart';
import 'cloud_sync_service.dart';
import 'waypoint_optimizer.dart';

// ─── compute() isolate 파라미터 / 결과 ────────────────────────────
// 메인 스레드 → isolate 전달 데이터 (모두 primitive)
class _IsolateParams {
  final String jsonBody;
  final double lat;
  final double lng;
  final int seed;
  const _IsolateParams(this.jsonBody, this.lat, this.lng, {this.seed = 0});
}

// isolate → 메인 스레드 반환 (routes + 로그)
class _IsolateResult {
  final List<RevvRoute> routes;
  final String log;
  const _IsolateResult(this.routes, this.log);
}

// ─── Top-level 처리 함수 (isolate에서 실행) ────────────────────────
// compute()는 top-level 함수만 받음 — 인스턴스 메서드 불가
_IsolateResult _processRoutes(_IsolateParams p) {
  final data = jsonDecode(p.jsonBody) as Map<String, dynamic>;
  final elements = data['elements'] as List;
  final userPos = LatLng(p.lat, p.lng);
  final rawWays = <_RawWay>[];
  final intersectionNodes = <LatLng>[];
  final signalNodes = <LatLng>[];

  for (final el in elements) {
    if (el['type'] == 'node') {
      final highway = el['tags']?['highway'] as String? ?? '';
      final pos = LatLng(
        (el['lat'] as num).toDouble(),
        (el['lon'] as num).toDouble(),
      );
      if (highway == 'traffic_signals' || highway == 'stop') {
        signalNodes.add(pos);
      } else {
        intersectionNodes.add(pos);
      }
    } else if (el['type'] == 'way') {
      final geom = el['geometry'] as List?;
      if (geom == null || geom.length < 10) continue;
      final nodes = geom
          .map((g) => LatLng(
              (g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()))
          .toList();
      final sampled = nodes.length > 400 ? _sampleNodes(nodes, 400) : nodes;
      final tags = el['tags'] as Map<String, dynamic>? ?? {};
      final name = tags['name'] as String? ?? '';
      if (_isUrbanName(name)) continue;
      final highway = tags['highway'] as String? ?? 'secondary';
      final surface = tags['surface'] as String? ?? '';
      final maxspeed = _parseMaxspeed(tags['maxspeed'] as String?);
      final lanes = int.tryParse(tags['lanes'] as String? ?? '') ?? 2;
      final id = el['id'].toString();
      rawWays.add(_RawWay(
        id: id, name: name, nodes: sampled, highwayType: highway,
        surface: surface, maxspeedKmh: maxspeed, lanes: lanes,
      ));
    }
  }

  // Way Stitching — 인접 도로 조각을 하나의 연속 루트로 이어붙임
  final stitched = _stitchWays(rawWays);
  final result = _selectTopRoutes(stitched, userPos, intersectionNodes, signalNodes, seed: p.seed);
  return _IsolateResult(result.routes, result.log);
}

// ─── Top-level 헬퍼 함수들 ───────────────────────────────────────
// (compute isolate에서 호출되므로 클래스 외부에 위치해야 함)

const _stitchThresholdKm = 0.25;   // 250m (단편화 방지)
const _stitchMaxAngleDeg = 130.0; // U턴 방지: 방향 차이 130° 이상이면 연결 거부

// chain 끝 진행 방향과 entry 시작 방향의 각도 차이 (0~180°)
double _stitchAngle(List<LatLng> chainNodes, List<LatLng> entryNodes) {
  if (chainNodes.length < 2 || entryNodes.length < 2) return 0;
  final exitB = _bearingDegTo(chainNodes[chainNodes.length - 2], chainNodes.last);
  final entryB = _bearingDegTo(entryNodes[0], entryNodes[1]);
  double d = (exitB - entryB).abs() % 360;
  return d > 180 ? 360 - d : d;
}

// 도심/교외 도로 이름 필터 — Boulevard, Avenue, Rue 등은 시가지 특징
bool _isUrbanName(String name) {
  final l = name.toLowerCase();
  return l.startsWith('boulevard ') ||
      l.startsWith('blvd ') ||
      l.startsWith('avenue ') ||
      l.startsWith('ave ') ||
      l.startsWith('rue ') ||
      l.contains(' boulevard') ||
      l.contains(' avenue') ||
      l.contains(' blvd');
}

List<LatLng> _sampleNodes(List<LatLng> nodes, int target) {
  final step = nodes.length / target;
  return List.generate(target, (i) => nodes[(i * step).floor()]);
}

List<_RawWay> _stitchWays(List<_RawWay> ways) {
  final used = <String>{};
  final result = <_RawWay>[];

  for (final seed in ways) {
    if (used.contains(seed.id)) continue;
    used.add(seed.id);

    var chain = seed.nodes.toList();
    final chainId = seed.id;
    var chainName = seed.name;
    var chainHighway = seed.highwayType;
    var chainSurface = seed.surface;
    var chainMaxspeed = seed.maxspeedKmh;
    var chainLanes = seed.lanes;

    // 앞뒤로 연결 가능한 way를 반복 탐색
    bool extended = true;
    while (extended) {
      extended = false;
      for (final other in ways) {
        if (used.contains(other.id)) continue;

        final chainEnd = chain.last;
        final chainStart = chain.first;

        void _mergeMetadata() {
          if (chainName.isEmpty) chainName = other.name;
          if (chainSurface.isEmpty) chainSurface = other.surface;
          chainMaxspeed ??= other.maxspeedKmh;
          if (chainLanes < other.lanes) chainLanes = other.lanes;
        }

        if (RevvRoute.haversineKm(chainEnd, other.nodes.first) < _stitchThresholdKm &&
            _stitchAngle(chain, other.nodes) < _stitchMaxAngleDeg) {
          chain.addAll(other.nodes.skip(1));
          used.add(other.id); _mergeMetadata(); extended = true; break;
        } else if (RevvRoute.haversineKm(chainEnd, other.nodes.last) < _stitchThresholdKm &&
            _stitchAngle(chain, other.nodes.reversed.toList()) < _stitchMaxAngleDeg) {
          chain.addAll(other.nodes.reversed.skip(1));
          used.add(other.id); _mergeMetadata(); extended = true; break;
        } else if (RevvRoute.haversineKm(chainStart, other.nodes.last) < _stitchThresholdKm &&
            _stitchAngle(other.nodes, chain) < _stitchMaxAngleDeg) {
          chain = [...other.nodes, ...chain.skip(1)];
          used.add(other.id); _mergeMetadata(); extended = true; break;
        } else if (RevvRoute.haversineKm(chainStart, other.nodes.first) < _stitchThresholdKm &&
            _stitchAngle(other.nodes.reversed.toList(), chain) < _stitchMaxAngleDeg) {
          chain = [...other.nodes.reversed.toList(), ...chain.skip(1)];
          used.add(other.id); _mergeMetadata(); extended = true; break;
        }
      }
    }

    final sampled = chain.length > 600 ? _sampleNodes(chain, 600) : chain;
    result.add(_RawWay(
      id: chainId,
      name: chainName,
      nodes: sampled,
      highwayType: chainHighway,
      surface: chainSurface,
      maxspeedKmh: chainMaxspeed,
      lanes: chainLanes,
    ));
  }

  return result;
}

bool _isLoop(List<LatLng> nodes) {
  if (nodes.length < 10) return false;
  return RevvRoute.haversineKm(nodes.first, nodes.last) < 3.0;
}

// 자기교차 감지: 실제 교차(50m 이내)를 80+ 노드(약 2km) 간격으로 체크
// → 스위치백/헤어핀은 허용, stitching으로 생긴 진짜 꼬임만 차단
bool _selfIntersects(List<LatLng> nodes) {
  const radius = 0.05; // 50m — 실제 교차점만 감지 (150m는 스위치백 오탈락)
  const minGap = 80;   // 80노드 ≈ 2km — 스위치백 반경 확보
  for (int i = 0; i < nodes.length - minGap; i += 6) {
    for (int j = i + minGap; j < nodes.length; j += 6) {
      if (RevvRoute.haversineKm(nodes[i], nodes[j]) < radius) return true;
    }
  }
  return false;
}

// 거리 패널티: 15km 이내 패널티 없음 / 15~60km 선형 감소 / 60km+ 0.55배
double _distancePenalty(double distFromUserKm) {
  if (distFromUserKm <= 15) return 1.0;
  if (distFromUserKm >= 60) return 0.55;
  return 1.0 - (distFromUserKm - 15) / 45 * 0.45;
}

double _totalDistance(List<LatLng> nodes) {
  double total = 0;
  for (int i = 0; i < nodes.length - 1; i++) {
    total += RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
  }
  return total;
}

LatLng _centerPoint(List<LatLng> nodes) {
  final lat = nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length;
  final lng = nodes.map((n) => n.lng).reduce((a, b) => a + b) / nodes.length;
  return LatLng(lat, lng);
}

double _rad(double deg) => deg * math.pi / 180;

double _bearing(LatLng from, LatLng to) {
  final lat1 = _rad(from.lat);
  final lat2 = _rad(to.lat);
  final dLng = _rad(to.lng - from.lng);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return math.atan2(y, x) * 180 / math.pi;
}

double _bearingDiff(LatLng a, LatLng b, LatLng c) {
  final b1 = _bearing(a, b);
  final b2 = _bearing(b, c);
  double diff = (b2 - b1).abs();
  if (diff > 180) diff = 360 - diff;
  return diff;
}

double _curvatureRateDegPerKm(LatLng a, LatLng b, LatLng c) {
  final d1 = RevvRoute.haversineKm(a, b);
  final d2 = RevvRoute.haversineKm(b, c);
  final pathLen = (d1 + d2) / 2;
  if (pathLen < 0.0001) return 0;
  return _bearingDiff(a, b, c) / pathLen;
}

// roadcurvature.com 방식:
//   totalCurvature = Σ (각도변화_deg × 구간거리_km) → 절댓값 누적합산
//   300+ = Lightly Curvy, 1000+ = Moderately, 2000+ = Very, 3000+ = Extremely
_CurveResult _analyzeCurves(List<LatLng> nodes) {
  double totalCurvature = 0;
  double tightKm = 0;
  double mediumKm = 0;
  double totalDist = 0;
  double currentContinuousKm = 0;
  double maxContinuousKm = 0;
  double straightAccum = 0;
  double maxStraightRunKm = 0;

  for (int i = 0; i < nodes.length - 2; i++) {
    final angle = _bearingDiff(nodes[i], nodes[i + 1], nodes[i + 2]);
    final segLen = RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
    totalDist += segLen;

    // roadcurvature.com 핵심 공식
    totalCurvature += angle * segLen;

    final rate = segLen > 0.0001 ? angle / segLen : 0;
    if (rate >= 200) {
      tightKm += segLen;
      currentContinuousKm += segLen;
      if (straightAccum > maxStraightRunKm) maxStraightRunKm = straightAccum;
      straightAccum = 0;
    } else if (rate >= 20) {
      mediumKm += segLen;
      currentContinuousKm += segLen;
      if (straightAccum > maxStraightRunKm) maxStraightRunKm = straightAccum;
      straightAccum = 0;
    } else {
      straightAccum += segLen;
      if (currentContinuousKm > maxContinuousKm) maxContinuousKm = currentContinuousKm;
      currentContinuousKm = 0;
    }
  }
  if (currentContinuousKm > maxContinuousKm) maxContinuousKm = currentContinuousKm;
  if (straightAccum > maxStraightRunKm) maxStraightRunKm = straightAccum;

  final curvyFraction = totalDist > 0 ? (tightKm + mediumKm) / totalDist : 0.0;

  return _CurveResult(
    totalCurvature: totalCurvature,
    tightKm: tightKm,
    mediumKm: mediumKm,
    maxContinuousKm: maxContinuousKm,
    maxStraightRunKm: maxStraightRunKm,
    curvyFraction: curvyFraction,
  );
}

int _countNearbyIntersections(List<LatLng> wayNodes, List<LatLng> intersections) {
  if (intersections.isEmpty) return 0;
  double minLat = wayNodes[0].lat, maxLat = wayNodes[0].lat;
  double minLng = wayNodes[0].lng, maxLng = wayNodes[0].lng;
  for (final n in wayNodes) {
    if (n.lat < minLat) minLat = n.lat;
    if (n.lat > maxLat) maxLat = n.lat;
    if (n.lng < minLng) minLng = n.lng;
    if (n.lng > maxLng) maxLng = n.lng;
  }
  const buf = 0.001;
  minLat -= buf; maxLat += buf;
  minLng -= buf; maxLng += buf;
  int count = 0;
  for (final n in intersections) {
    if (n.lat >= minLat && n.lat <= maxLat &&
        n.lng >= minLng && n.lng <= maxLng) count++;
  }
  return count;
}

// 신호등/스탑사인 카운트 (바운딩박스 선필터 후 80m 이내 정밀 체크)
int _countSignalsNearRoute(List<LatLng> wayNodes, List<LatLng> signalNodes) {
  if (signalNodes.isEmpty) return 0;
  double minLat = wayNodes[0].lat, maxLat = wayNodes[0].lat;
  double minLng = wayNodes[0].lng, maxLng = wayNodes[0].lng;
  for (final n in wayNodes) {
    if (n.lat < minLat) minLat = n.lat;
    if (n.lat > maxLat) maxLat = n.lat;
    if (n.lng < minLng) minLng = n.lng;
    if (n.lng > maxLng) maxLng = n.lng;
  }
  const buf = 0.001; // ~100m
  minLat -= buf; maxLat += buf;
  minLng -= buf; maxLng += buf;
  int count = 0;
  for (final signal in signalNodes) {
    if (signal.lat < minLat || signal.lat > maxLat ||
        signal.lng < minLng || signal.lng > maxLng) continue;
    for (final node in wayNodes) {
      if (RevvRoute.haversineKm(signal, node) < 0.08) {
        count++;
        break;
      }
    }
  }
  return count;
}

double _intersectionPenalty(int count, double distKm) {
  if (distKm <= 0) return 1.0;
  final perKm = count / distKm;
  if (perKm >= 3.0) return 0.6;
  if (perKm >= 2.0) return 0.7;
  return 1.0;
}

// maxspeed 태그 파싱: "70", "50 km/h", "30 mph" 등
int? _parseMaxspeed(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final n = int.tryParse(digits);
  if (n == null) return null;
  if (raw.toLowerCase().contains('mph')) return (n * 1.609).round();
  return n;
}

// 도로 표면 배수 (asphalt > paved > gravel > dirt)
double _surfaceMultiplier(String surface) {
  switch (surface.toLowerCase()) {
    case 'asphalt':
    case 'paved':
    case 'concrete':       return 1.0;
    case 'compacted':
    case 'fine_gravel':    return 0.85;
    case 'gravel':
    case 'unpaved':
    case 'cobblestone':    return 0.5;
    case 'dirt':
    case 'grass':
    case 'sand':
    case 'mud':            return 0.2;
    default:               return 1.0; // 태그 없으면 중립
  }
}

// 제한속도 배수: 60-80 km/h = 지방 와인딩 도로 최적
double _maxspeedMultiplier(int? kmh) {
  if (kmh == null) return 1.0;
  if (kmh <= 30)  return 0.6;  // 주거지/보행 구역
  if (kmh <= 50)  return 0.85; // 도심
  if (kmh <= 80)  return 1.15; // 지방 도로 ★ 최적
  if (kmh <= 90)  return 1.0;
  return 0.65;                  // 100km/h+ = 고속도로형
}

// 차선 수 배수: 1차선 좁은 시골길 > 2차선 > 넓은 다차선
double _lanesMultiplier(int lanes) {
  if (lanes == 1) return 1.2;
  if (lanes == 2) return 1.0;
  if (lanes == 3) return 0.75;
  return 0.55; // 4차선+
}

double _roadMultiplier(String highway) {
  switch (highway) {
    case 'secondary':    return 1.3;
    case 'tertiary':     return 1.2;
    case 'unclassified': return 1.0;
    case 'primary':      return 0.7;
    case 'residential':  return 0.5;
    default:             return 1.0;
  }
}

/// from → to 방위각 (0~360°, 북=0)
double _bearingDegTo(LatLng from, LatLng to) {
  final lat1 = _rad(from.lat);
  final lat2 = _rad(to.lat);
  final dLng = _rad(to.lng - from.lng);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

_IsolateResult _selectTopRoutes(
    List<_RawWay> ways, LatLng userPos, List<LatLng> intersections, List<LatLng> signalNodes,
    {int seed = 0}) {
  final scored = <_ScoredWay>[];

  int cDist = 0, cResidential = 0, cSignal = 0, cCurvature = 0,
      cContKm = 0, cStraight = 0, cCurvyFrac = 0, cSelfInt = 0,
      cDensity = 0, cSpread = 0, cAspect = 0;

  for (final way in ways) {
    final dist = _totalDistance(way.nodes);
    final isLoopRoute = _isLoop(way.nodes);
    if (isLoopRoute && dist < 8.0) { cDist++; continue; }
    if (!isLoopRoute && dist < 5.0) { cDist++; continue; } // 3→5km: 너무 짧은 단편 제거

    if (way.highwayType == 'residential') { cResidential++; continue; }

    final signalCount = _countSignalsNearRoute(way.nodes, signalNodes);
    if (signalCount >= 3) { cSignal++; continue; }

    final curves = _analyzeCurves(way.nodes);

    if (curves.totalCurvature < 75) { cCurvature++; continue; }
    if (curves.maxContinuousKm < 0.8) { cContKm++; continue; }
    if (curves.maxStraightRunKm > 1.5) { cStraight++; continue; }
    if (curves.curvyFraction < 0.25) { cCurvyFrac++; continue; }
    if (_selfIntersects(way.nodes)) { cSelfInt++; continue; }

    final curvatureDensity = curves.totalCurvature / dist;
    if (curvatureDensity < 7.5) { cDensity++; continue; }

    // Spread Ratio
    {
      double minLat = way.nodes[0].lat, maxLat = way.nodes[0].lat;
      double minLng = way.nodes[0].lng, maxLng = way.nodes[0].lng;
      for (final n in way.nodes) {
        if (n.lat < minLat) minLat = n.lat;
        if (n.lat > maxLat) maxLat = n.lat;
        if (n.lng < minLng) minLng = n.lng;
        if (n.lng > maxLng) maxLng = n.lng;
      }
      final avgLat = (minLat + maxLat) / 2;
      final latKm = (maxLat - minLat) * 111.0;
      final lngKm = (maxLng - minLng) * 111.0 * math.cos(_rad(avgLat));
      final bbDiagonal = math.sqrt(latKm * latKm + lngKm * lngKm);
      final spreadRatio = dist > 0 ? bbDiagonal / dist : 0;
      if (spreadRatio < 0.25) { cSpread++; continue; }

      // 종횡비 필터:
      // elongated(가늘고 길다) + 커브 적음 = rang 직선 도로 → 제거
      // elongated + 커브 많음 = 강/계곡 따르는 와인딩 도로 → 유지
      if (latKm > 0.1 && lngKm > 0.1) {
        final bbAspect = math.min(latKm, lngKm) / math.max(latKm, lngKm);
        if (bbAspect < 0.15 && curves.curvyFraction < 0.30) { cAspect++; continue; }
      }
    }
    final continuityBonus = 1.0 + (curves.maxContinuousKm / dist) * 0.6;
    final intersectCount = _countNearbyIntersections(way.nodes, intersections);
    final intersectPenalty = _intersectionPenalty(intersectCount, dist);
    final signalPenalty = signalCount == 0 ? 1.0 : signalCount == 1 ? 0.55 : 0.25;
    final roadMultiplier = _roadMultiplier(way.highwayType);
    final surfaceMult   = _surfaceMultiplier(way.surface);
    final speedMult     = _maxspeedMultiplier(way.maxspeedKmh);
    final lanesMult     = _lanesMultiplier(way.lanes);
    final loopBonus = isLoopRoute ? 1.25 : 1.0;
    final distPenalty = _distancePenalty(
        RevvRoute.haversineKm(userPos, way.nodes.first));

    // roadcurvature.com 방식 + 지리 데이터 배수
    final score = curvatureDensity * math.sqrt(dist) *
        continuityBonus * intersectPenalty * signalPenalty * roadMultiplier *
        surfaceMult * speedMult * lanesMult *
        loopBonus * distPenalty;

    scored.add(_ScoredWay(
      way: way,
      score: score,
      distKm: dist,
      center: _centerPoint(way.nodes),
      distFromUser: RevvRoute.haversineKm(userPos, way.nodes.first),
      curves: curves,
      isLoop: isLoopRoute,
    ));
  }

  debugPrint('[Filter] 탈락: 거리=$cDist 주거지=$cResidential 신호=$cSignal '
      '커브량=$cCurvature 연속커브=$cContKm 직선=$cStraight '
      '커브비율=$cCurvyFrac 자기교차=$cSelfInt 밀도=$cDensity '
      '스프레드=$cSpread 종횡비=$cAspect '
      '→ 통과: ${scored.length}개 / 총 ${ways.length}개');

  scored.sort((a, b) => b.score.compareTo(a.score));

  // ── 방향 다양성 선택 (8-sector Climoto 스타일) ──────────────────
  // 360°를 45° 단위 8개 섹터로 나눠 각 방향의 최고 루트 우선 선택
  const sectorCount = 8;
  final sectors = List<List<_ScoredWay>>.generate(sectorCount, (_) => []);
  for (final s in scored) {
    final bearing = _bearingDegTo(userPos, s.center);
    final idx = (bearing / (360 / sectorCount)).floor() % sectorCount;
    sectors[idx].add(s);
  }

  final selected = <_ScoredWay>[];

  bool isTooClose(_ScoredWay candidate) => selected.any(
      (sel) => RevvRoute.haversineKm(candidate.center, sel.center) < 6);

  // 1라운드: 각 섹터 상위 5개 풀에서 랜덤 선택 (seed로 다양성 보장)
  final rng = math.Random(seed == 0 ? null : seed);
  for (final sector in sectors) {
    final pool = sector.take(5).toList();
    if (seed != 0) pool.shuffle(rng);
    for (final candidate in pool) {
      if (!isTooClose(candidate)) { selected.add(candidate); break; }
    }
  }
  // 2라운드: 6km 간격 유지하며 나머지 채우기
  for (final s in scored) {
    if (selected.length >= 10) break;
    if (!selected.contains(s) && !isTooClose(s)) selected.add(s);
  }
  // 점수순 재정렬
  selected.sort((a, b) => b.score.compareTo(a.score));

  // ── 로그 문자열 빌드 (isolate → 메인에서 출력) ──────────────────
  final logBuf = StringBuffer();
  logBuf.writeln('\n==== REVV ROUTES (${selected.length}개) ====');
  for (int i = 0; i < selected.length; i++) {
    final s = selected[i];
    final density = s.distKm > 0 ? s.curves.totalCurvature / s.distKm : 0.0;
    final label = s.score >= 8.0
        ? 'EXTREME'
        : s.score >= 5.5
            ? 'HARD'
            : s.score >= 3.5
                ? 'MEDIUM'
                : s.score >= 2.0
                    ? 'EASY'
                    : 'SCENIC';
    logBuf.writeln('[#${i + 1}] '
        '${(s.way.name.isEmpty ? "(이름없음)" : s.way.name).padRight(22)} | '
        '${s.distKm.toStringAsFixed(1).padLeft(5)}km | '
        '${label.padRight(7)} | '
        'density=${density.toStringAsFixed(1).padLeft(4)} '
        'curvy=${(s.curves.curvyFraction * 100).toStringAsFixed(0).padLeft(2)}% '
        'straight=${s.curves.maxStraightRunKm.toStringAsFixed(2)}km '
        'score=${s.score.toStringAsFixed(2)}');
  }
  logBuf.write('==============================');

  final routes = selected.map((s) {
    final name = s.way.name.isNotEmpty
        ? s.way.name
        : RevvRoute.autoName(s.score);
    return RevvRoute(
      id: s.way.id,
      name: name,
      nodes: s.way.nodes,
      distanceKm: s.distKm,
      windingScore: s.score,
      starRating: RevvRoute.toStarRating(s.score),
      sharpCurveCount: 0,
      centerPoint: s.center,
      distanceFromUser: s.distFromUser,
      tightCurveKm: s.curves.tightKm,
      mediumCurveKm: s.curves.mediumKm,
      maxContinuousKm: s.curves.maxContinuousKm,
      isLoop: s.isLoop,
    );
  }).toList();
  return _IsolateResult(routes, logBuf.toString());
}

// ─── RouteService ─────────────────────────────────────────────────

class RouteService extends ChangeNotifier {
  List<RevvRoute> routes = [];
  RevvRoute? selectedRoute;
  bool isLoading = false;
  String? errorMessage;
  int searchRadiusKm = 50; // 기본 50km

  // 연결 루트 (선택 루트 끝점 기준)
  List<RevvRoute> connectingRoutes = [];
  bool isLoadingConnecting = false;

  LatLng? _lastFetchLocation;
  int? _lastFetchRadius;

  // 마지막 응답 JSON 캐시 — shuffleRoutes()에서 재사용
  String? _lastJsonBody;
  double? _lastJsonLat;
  double? _lastJsonLng;

  // ── 루트 배제 ────────────────────────────────────────────────
  final List<LatLng> _excludedCenters = [];
  bool _exclusionsLoaded = false;
  static const _excludeKey = StorageKeys.excludedCenters;

  Future<void> loadExclusions() async {
    if (_exclusionsLoaded) return;
    _exclusionsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_excludeKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      for (final item in list) {
        _excludedCenters.add(LatLng(
          (item[0] as num).toDouble(),
          (item[1] as num).toDouble(),
        ));
      }
      debugPrint('[RouteService] 배제 루트 로드: ${_excludedCenters.length}개');
    } catch (e) {
      debugPrint('[RouteService] 배제 목록 로드 오류: $e');
    }
  }

  bool isExcluded(RevvRoute route) {
    return _excludedCenters.any(
      (p) => RevvRoute.haversineKm(p, route.centerPoint) < 0.5,
    );
  }

  Future<void> excludeRoute(RevvRoute route) async {
    _excludedCenters.add(route.centerPoint);
    routes.removeWhere(isExcluded);
    if (selectedRoute != null && isExcluded(selectedRoute!)) {
      selectedRoute = routes.isNotEmpty ? routes.first : null;
      connectingRoutes = [];
    }
    notifyListeners();
    _saveExclusions();
  }

  /// 배제 목록 전체 초기화 (설정 화면에서 호출)
  void resetExclusions() {
    _excludedCenters.clear();
    _exclusionsLoaded = true;
    notifyListeners();
  }

  Future<void> _saveExclusions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _excludedCenters.map((p) => [p.lat, p.lng]).toList(),
      );
      await prefs.setString(_excludeKey, encoded);
    } catch (e) {
      debugPrint('[RouteService] 배제 목록 저장 오류: $e');
    }
  }

  // ── Sprint 요청 ────────────────────────────────────────────
  bool sprintRequested = false;
  RevvRoute? sprintRoute; // null이면 selectedRoute 사용

  void requestSprint({RevvRoute? route}) {
    sprintRequested = true;
    sprintRoute = route;
    notifyListeners();
  }

  void clearSprintRequest() {
    sprintRequested = false;
    sprintRoute = null;
  }

  void resetCache() {
    _lastFetchLocation = null;
    _lastFetchRadius = null;
  }

  /// 반경 변경 후 재검색
  Future<void> changeRadius(int radiusKm, double lat, double lng) async {
    searchRadiusKm = radiusKm;
    resetCache();
    routes = [];
    selectedRoute = null;
    notifyListeners();
    await fetchRoutes(lat, lng);
  }

  Future<void> fetchRoutes(double lat, double lng) async {
    // ① 캐시 즉시 표시 (stale-while-revalidate)
    final cached = await _loadFromCache();
    if (cached != null && cached.isNotEmpty && routes.isEmpty) {
      routes = cached;
      selectedRoute = routes.first;
      notifyListeners();
    }

    // ② 같은 위치 + 같은 반경이면 스킵 (캐시로 충분)
    if (_lastFetchLocation != null && _lastFetchRadius == searchRadiusKm) {
      final dist = RevvRoute.haversineKm(_lastFetchLocation!, LatLng(lat, lng));
      if (dist < 10) return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await loadExclusions();

      // ③-a 전역 DB 먼저 조회 (커뮤니티 루트)
      final globalRoutes = await CloudSyncService().fetchNearbyRoutes(
        lat, lng, searchRadiusKm.toDouble(),
      );
      final globalFiltered =
          globalRoutes.where((r) => !isExcluded(r)).toList();

      List<RevvRoute> fresh;
      if (globalFiltered.length >= 5) {
        // ③-b-skip 전역 DB에 충분 → Overpass 스킵 (네트워크 절약)
        fresh = globalFiltered;
        debugPrint('[RouteService] Global DB ${globalFiltered.length}개 — Overpass 스킵');
      } else {
        // ③-b-overpass Overpass fallback
        final seed = math.Random().nextInt(0x7FFFFFFF);
        var overpass =
            await _fetchAndScore(lat, lng, searchRadiusKm * 1000, seed: seed);
        overpass = overpass.where((r) => !isExcluded(r)).toList();

        if (overpass.length < 3 && searchRadiusKm < 100) {
          debugPrint('[RouteService] 루트 부족 (${overpass.length}개) → 100km 자동 확장');
          overpass = await _fetchAndScore(lat, lng, 100000, seed: seed);
          overpass = overpass.where((r) => !isExcluded(r)).toList();
        }

        // Overpass 신규 루트 → 전역 DB 게시 (fire-and-forget)
        _publishNewRoutes(overpass, globalFiltered);

        // 전역 + Overpass 병합
        fresh = _mergeRoutePools(globalFiltered, overpass);
      }

      // 고도 분석: 지형 기반 점수 보정
      fresh = await _enrichWithElevation(fresh);

      // ④ 누적: 기존 풀 + 새 루트 병합 (중복 6km 기준 제거), 상위 25개 유지
      final merged = _mergeRoutePools(routes, fresh);
      merged.sort((a, b) => b.windingScore.compareTo(a.windingScore));
      routes = merged.take(25).toList();

      selectedRoute = routes.isNotEmpty ? routes.first : null;
      // 전역 DB에서 온 루트는 nodes=[] — 첫 번째 루트 노드 미리 로드 (지도 폴리라인용)
      if (selectedRoute != null && selectedRoute!.nodes.isEmpty) {
        _ensureRouteNodes(selectedRoute!); // fire-and-forget
      }
      _lastFetchLocation = LatLng(lat, lng);
      _lastFetchRadius = searchRadiusKm;
      debugPrint('[RouteService] 풀 누적 후 루트: ${routes.length}개 (신규 ${fresh.length}개)');

      // ⑤ 캐시 저장 (SharedPreferences + Firestore 비동기)
      _saveToCache(routes, lat, lng);
      _saveRoutesToFirestore(routes);
    } catch (e, st) {
      debugPrint('[RouteService] 예외: $e\n$st');
      if (routes.isEmpty) {
        final fallback = await _loadFromCache();
        if (fallback != null && fallback.isNotEmpty) {
          routes = fallback;
          selectedRoute = routes.first;
          errorMessage = '오프라인 모드 — 마지막 검색 결과를 표시합니다';
          debugPrint('[RouteService] 오프라인 캐시 복원: ${routes.length}개');
        } else {
          errorMessage = '네트워크 오류가 발생했어요. 인터넷 연결을 확인하세요.';
        }
      }
    }

    isLoading = false;
    notifyListeners();
  }

  /// 기존 풀 + 새 루트 병합 — centerPoint 6km 이내 중복 제거
  List<RevvRoute> _mergeRoutePools(List<RevvRoute> existing, List<RevvRoute> fresh) {
    final pool = List<RevvRoute>.from(existing);
    for (final r in fresh) {
      final isDup = pool.any(
        (e) => RevvRoute.haversineKm(e.centerPoint, r.centerPoint) < 6,
      );
      if (!isDup) pool.add(r);
    }
    return pool;
  }

  /// 개인 Firestore 캐시 저장 (preloadFromFirestore용)
  void _saveRoutesToFirestore(List<RevvRoute> rs) {
    CloudSyncService().saveDiscoveredRoutes(rs).catchError((e) {
      debugPrint('[RouteService] Firestore 루트 저장 실패: $e');
    });
  }

  /// Overpass 결과 중 전역 DB에 없는 신규 루트 게시 (fire-and-forget)
  void _publishNewRoutes(
      List<RevvRoute> overpassRoutes, List<RevvRoute> globalRoutes) {
    final globalIds = globalRoutes.map((r) => r.id).toSet();
    for (final r in overpassRoutes) {
      if (!globalIds.contains(r.id)) {
        CloudSyncService().publishRoute(r).catchError((e) {
          debugPrint('[RouteService] 루트 게시 실패: $e');
        });
      }
    }
  }

  /// Firestore에서 루트 풀 사전 로드 (앱 시작 시)
  Future<void> preloadFromFirestore() async {
    if (routes.isNotEmpty) return; // 이미 캐시가 있으면 스킵
    try {
      final firestoreRoutes = await CloudSyncService().loadDiscoveredRoutes();
      if (firestoreRoutes.isNotEmpty && routes.isEmpty) {
        routes = firestoreRoutes;
        selectedRoute = routes.first;
        notifyListeners();
        debugPrint('[RouteService] Firestore 사전 로드: ${routes.length}개');
      }
    } catch (e) {
      debugPrint('[RouteService] Firestore 사전 로드 실패: $e');
    }
  }

  // ─── 오프라인 캐시 ─────────────────────────────────────────────
  static const _cacheKey = StorageKeys.routeCache;
  static const _cachePosKey = StorageKeys.routeCachePos;

  Future<void> _saveToCache(List<RevvRoute> rs, double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, RevvRoute.listToJson(rs));
      await prefs.setString(_cachePosKey, '$lat,$lng');
    } catch (e) {
      debugPrint('[RouteService] 캐시 저장 실패: $e');
    }
  }

  Future<List<RevvRoute>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      return RevvRoute.listFromJson(raw);
    } catch (e) {
      debugPrint('[RouteService] 캐시 로드 실패: $e');
      return null;
    }
  }

  /// CHAIN: 이미 로드된 routes 캐시에서 끝점 근처 루트 즉시 탐색 (Overpass 재호출 없음)
  Future<void> fetchConnectingRoutes(RevvRoute fromRoute) async {
    isLoadingConnecting = true;
    connectingRoutes = [];
    notifyListeners();

    final endpoint = fromRoute.nodes.last;
    const maxDistKm = 15.0;

    final candidates = routes
        .where((r) => r.id != fromRoute.id)
        .where((r) {
          final dStart = RevvRoute.haversineKm(endpoint, r.nodes.first);
          final dEnd = RevvRoute.haversineKm(endpoint, r.nodes.last);
          return dStart < maxDistKm || dEnd < maxDistKm;
        })
        .toList();

    candidates.sort((a, b) {
      final da = math.min(
        RevvRoute.haversineKm(endpoint, a.nodes.first),
        RevvRoute.haversineKm(endpoint, a.nodes.last),
      );
      final db = math.min(
        RevvRoute.haversineKm(endpoint, b.nodes.first),
        RevvRoute.haversineKm(endpoint, b.nodes.last),
      );
      return da.compareTo(db);
    });

    connectingRoutes = candidates.take(3).toList();
    debugPrint('[RouteService] CHAIN (캐시): ${connectingRoutes.length}개');

    isLoadingConnecting = false;
    notifyListeners();
  }

  /// Overpass 조회 → compute() isolate에서 파싱+스코어링
  // ─── 고도 분석: 지형 기반 점수 보정 ────────────────────────────────
  // Open Topo Data SRTM30m (무료, 키 불필요) — 루트당 8개 샘플 포인트
  // 고도 변화가 클수록 산악/언덕 지형 = 와인딩 도로 품질 ↑
  // 평지(퀘벡 rang 지역) = 약한 패널티
  Future<List<RevvRoute>> _enrichWithElevation(List<RevvRoute> routes) async {
    if (routes.isEmpty) return routes;
    const samplePer = 8;
    final points = <LatLng>[];
    final startIdx = <int>[];

    for (final r in routes) {
      startIdx.add(points.length);
      final nodes = r.nodes;
      for (int i = 0; i < samplePer; i++) {
        final idx = ((i / (samplePer - 1)) * (nodes.length - 1)).round()
            .clamp(0, nodes.length - 1);
        points.add(nodes[idx]);
      }
    }

    final locs = points.map((p) => '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}').join('|');
    try {
      final resp = await http.get(
        Uri.parse('https://api.opentopodata.org/v1/srtm30m?locations=$locs'),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return routes;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = data['results'] as List;

      return List.generate(routes.length, (ri) {
        final s = startIdx[ri];
        final elevs = List.generate(
          samplePer,
          (j) => (results[s + j]['elevation'] as num?)?.toDouble() ?? 0.0,
        );
        final minE = elevs.reduce(math.min);
        final maxE = elevs.reduce(math.max);
        final elevRange = maxE - minE;

        // 고도 변화 → 배수 보정
        double mult;
        if (elevRange >= 120)      mult = 1.6;  // 산악 (로렌시안, 아팔래치안)
        else if (elevRange >= 60)  mult = 1.35; // 언덕
        else if (elevRange >= 30)  mult = 1.1;  // 완만한 언덕
        else if (elevRange >= 15)  mult = 1.0;  // 중간
        else                       mult = 0.75; // 평지 (퀘벡 rang 지역)

        debugPrint('[Elev] ${routes[ri].name}: ${elevRange.toStringAsFixed(0)}m → ×${mult}');
        return routes[ri].copyWith(
          windingScore: routes[ri].windingScore * mult,
          elevationDelta: elevRange,
        );
      });
    } catch (e) {
      debugPrint('[Elev] 조회 실패 (무시): $e');
      return routes; // 실패해도 원본 그대로
    }
  }

  Future<List<RevvRoute>> _fetchAndScore(double lat, double lng, int radiusM, {int seed = 0}) async {
    // ["name"] 필터: 이름 없는 도로 제거 → 데이터량 80% 감소
    // primary 포함: 캐나다 일부 primary가 와인딩 명소
    final query = '''
[out:json][timeout:55];
(
  way["highway"="primary"]["name"](around:$radiusM,$lat,$lng);
  way["highway"="secondary"]["name"](around:$radiusM,$lat,$lng);
  way["highway"="tertiary"]["name"](around:$radiusM,$lat,$lng);
  way["highway"="unclassified"]["name"](around:$radiusM,$lat,$lng);
  node["highway"="traffic_signals"](around:$radiusM,$lat,$lng);
  node["highway"="stop"](around:$radiusM,$lat,$lng);
);
out geom qt;
''';

    debugPrint('[RouteService] _fetchAndScore ($lat, $lng, r=${radiusM}m)');

    final endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://z.overpass-api.de/api/interpreter',
      'https://lz4.overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.osm.ch/api/interpreter',
      'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    ];

    String? resBody;
    for (final url in endpoints) {
      try {
        final r = await http.post(
          Uri.parse(url),
          body: {'data': query},
        ).timeout(const Duration(seconds: 60));
        if (r.statusCode == 200) {
          final body = utf8.decode(r.bodyBytes);
          // Overpass가 XML 에러 페이지를 200으로 반환하는 경우 방어
          if (body.trimLeft().startsWith('<')) {
            debugPrint('[RouteService] $url XML 에러 응답 → 다음 서버 시도');
            continue;
          }
          resBody = body;
          debugPrint('[RouteService] $url 성공 (${body.length} bytes)');
          break;
        }
        debugPrint('[RouteService] $url → ${r.statusCode}');
      } catch (e) {
        debugPrint('[RouteService] $url 실패: $e');
      }
    }

    if (resBody == null) {
      debugPrint('[RouteService] 모든 서버 실패');
      return [];
    }

    // JSON 캐시 저장 (shuffleRoutes에서 재사용)
    _lastJsonBody = resBody;
    _lastJsonLat = lat;
    _lastJsonLng = lng;

    // ── compute() isolate: JSON 파싱 + Way Stitching + 스코어링 ──
    // 메인 스레드에서 실행하면 320프레임+ 스킵 발생 → 별도 isolate로 분리
    debugPrint('[RouteService] compute() isolate 시작 (seed=$seed)');
    final result = await compute(_processRoutes, _IsolateParams(resBody, lat, lng, seed: seed));
    debugPrint(result.log); // ← 메인 스레드에서 번호 로그 출력
    debugPrint('[RouteService] compute() 완료: ${result.routes.length}개');
    return result.routes;
  }

  /// 새 랜덤 시드로 캐시된 JSON 재처리 — 네트워크 호출 없이 다른 루트 조합 반환
  Future<void> shuffleRoutes() async {
    if (_lastJsonBody == null) return;
    isLoading = true;
    notifyListeners();

    final seed = math.Random().nextInt(0x7FFFFFFF);
    try {
      final result = await compute(
        _processRoutes,
        _IsolateParams(_lastJsonBody!, _lastJsonLat!, _lastJsonLng!, seed: seed),
      );
      debugPrint(result.log);
      routes = result.routes.where((r) => !isExcluded(r)).toList();
      selectedRoute = routes.isNotEmpty ? routes.first : null;
      connectingRoutes = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectRoute(RevvRoute route) {
    if (!routes.any((r) => r.id == route.id)) {
      routes = [route, ...routes];
    }
    selectedRoute = route;
    connectingRoutes = [];
    notifyListeners();
    // 전역 DB에서 온 루트는 nodes=[] — 반드시 노드 로드 후 체인 탐색
    if (route.nodes.isEmpty) {
      _ensureNodesThenConnect(route);
    } else {
      fetchConnectingRoutes(route);
    }
  }

  /// 노드 lazy 로드 → 지도 폴리라인 + 체인 탐색 순서 보장
  Future<void> _ensureNodesThenConnect(RevvRoute route) async {
    await _ensureRouteNodes(route);
    if (selectedRoute?.id == route.id && selectedRoute!.nodes.isNotEmpty) {
      fetchConnectingRoutes(selectedRoute!);
    }
  }

  /// 전역 DB 루트의 노드를 lazy 로드해 routes 리스트와 selectedRoute를 갱신
  Future<void> _ensureRouteNodes(RevvRoute route) async {
    final nodes = await CloudSyncService().fetchRouteNodes(route.id);
    if (nodes.isEmpty) return;
    final full = route.copyWith(nodes: nodes);
    routes = routes.map((r) => r.id == route.id ? full : r).toList();
    if (selectedRoute?.id == route.id) {
      selectedRoute = full;
      notifyListeners();
    }
  }

  void deselectRoute() {
    selectedRoute = null;
    connectingRoutes = [];
    notifyListeners();
  }

  /// G. 수동 체인 — 사용자가 직접 연결할 루트 추가/제거
  void addManualChain(RevvRoute route) {
    if (connectingRoutes.any((r) => r.id == route.id)) return;
    connectingRoutes = [...connectingRoutes, route];
    notifyListeners();
  }

  void removeFromChain(String routeId) {
    connectingRoutes = connectingRoutes.where((r) => r.id != routeId).toList();
    notifyListeners();
  }

  // ── 경유지 최적화 ──────────────────────────────────────────────

  bool isOptimizing = false;
  OptimizedRoute? lastOptimized;

  Future<OptimizedRoute?> optimizeWaypoints({
    required LatLng userPos,
    required List<RevvRoute> segments,
    bool returnHome = false,
  }) async {
    if (segments.isEmpty) return null;

    isOptimizing = true;
    lastOptimized = null;
    notifyListeners();

    try {
      final result = await WaypointOptimizer.optimize(
        userPos: userPos,
        segments: segments,
        returnHome: returnHome,
      );
      lastOptimized = result;
      return result;
    } catch (e) {
      debugPrint('[RouteService] optimizeWaypoints 오류: $e');
      return null;
    } finally {
      isOptimizing = false;
      notifyListeners();
    }
  }
}

// ─── 내부 클래스 ──────────────────────────────────────────────────

class _CurveResult {
  final double totalCurvature; // roadcurvature.com 방식 (deg × km)
  final double tightKm;
  final double mediumKm;
  final double maxContinuousKm;
  final double maxStraightRunKm; // 최장 직선 구간
  final double curvyFraction;    // 전체 거리 중 커브 비율 (0..1)
  const _CurveResult({
    required this.totalCurvature,
    required this.tightKm,
    required this.mediumKm,
    required this.maxContinuousKm,
    required this.maxStraightRunKm,
    required this.curvyFraction,
  });
}

class _RawWay {
  final String id;
  final String name;
  final List<LatLng> nodes;
  final String highwayType;
  final String surface;    // asphalt/paved/gravel/dirt/unknown
  final int? maxspeedKmh;  // 속도 제한 (km/h)
  final int lanes;         // 차선 수
  _RawWay({
    required this.id,
    required this.name,
    required this.nodes,
    required this.highwayType,
    this.surface = '',
    this.maxspeedKmh,
    this.lanes = 2,
  });
}

class _ScoredWay {
  final _RawWay way;
  final double score;
  final double distKm;
  final LatLng center;
  final double distFromUser;
  final _CurveResult curves;
  final bool isLoop;
  _ScoredWay({
    required this.way,
    required this.score,
    required this.distKm,
    required this.center,
    required this.distFromUser,
    required this.curves,
    this.isLoop = false,
  });
}
