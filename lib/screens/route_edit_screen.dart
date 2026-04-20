import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../models/revv_route.dart';
import '../services/mapbox_service.dart';
import '../widgets/revv_ui.dart';

// ── 분기점 데이터 ─────────────────────────────────────────────────
class _BranchPoint {
  final int routeNodeIdx; // 현재 루트에서 분기 발생 위치
  final LatLng location;
  final RevvRoute branchRoute;
  final int branchNodeIdx; // 분기 루트에서 합류 위치
  final double kmFromStart; // 현재 루트 기준 출발부터 거리

  const _BranchPoint({
    required this.routeNodeIdx,
    required this.location,
    required this.branchRoute,
    required this.branchNodeIdx,
    required this.kmFromStart,
  });
}

// ══════════════════════════════════════════════════════════════════
// RouteEditScreen — 루트 편집 전용 화면
// ══════════════════════════════════════════════════════════════════
class RouteEditScreen extends StatefulWidget {
  final RevvRoute route;
  final List<RevvRoute> otherRoutes;

  const RouteEditScreen({
    super.key,
    required this.route,
    required this.otherRoutes,
  });

  @override
  State<RouteEditScreen> createState() => _RouteEditScreenState();
}

class _RouteEditScreenState extends State<RouteEditScreen> {
  mbx.MapboxMap? _map;
  mbx.PolylineAnnotationManager? _polyManager;
  bool _styleLoaded = false;

  List<_BranchPoint> _branches = [];
  _BranchPoint? _selected;

  // 분기점 오버레이 위치 (픽셀)
  final Map<int, Offset> _pinPositions = {};
  bool _updatingPins = false;

  @override
  void initState() {
    super.initState();
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
    _branches = _findBranchPoints(widget.route, widget.otherRoutes);
  }

  // ── 분기점 탐색 ──────────────────────────────────────────────────
  static List<_BranchPoint> _findBranchPoints(
    RevvRoute route,
    List<RevvRoute> others,
  ) {
    const snapDist = 0.08; // 80m 이내 = 같은 교차로
    const groupDist = 0.3; // 300m 이내 = 중복 분기점 병합
    const step = 15; // 성능: 15노드마다 체크

    // 누적 거리 사전 계산
    final cumDist = <double>[0.0];
    for (int i = 0; i < route.nodes.length - 1; i++) {
      cumDist.add(
        cumDist.last +
            RevvRoute.haversineKm(route.nodes[i], route.nodes[i + 1]),
      );
    }

    final raw = <_BranchPoint>[];

    for (final other in others) {
      // 바운딩박스 선필터
      double oMinLat = other.nodes[0].lat, oMaxLat = other.nodes[0].lat;
      double oMinLng = other.nodes[0].lng, oMaxLng = other.nodes[0].lng;
      for (final n in other.nodes) {
        if (n.lat < oMinLat) oMinLat = n.lat;
        if (n.lat > oMaxLat) oMaxLat = n.lat;
        if (n.lng < oMinLng) oMinLng = n.lng;
        if (n.lng > oMaxLng) oMaxLng = n.lng;
      }
      const buf = 0.001;

      double? bestDist;
      int bestI = -1, bestJ = -1;

      for (int i = 0; i < route.nodes.length; i += step) {
        final rn = route.nodes[i];
        if (rn.lat < oMinLat - buf ||
            rn.lat > oMaxLat + buf ||
            rn.lng < oMinLng - buf ||
            rn.lng > oMaxLng + buf) {
          continue;
        }

        for (int j = 0; j < other.nodes.length; j += step) {
          final d = RevvRoute.haversineKm(rn, other.nodes[j]);
          if (d < snapDist && (bestDist == null || d < bestDist)) {
            bestDist = d;
            bestI = i;
            bestJ = j;
          }
        }
      }

      if (bestI >= 0) {
        raw.add(
          _BranchPoint(
            routeNodeIdx: bestI,
            location: route.nodes[bestI],
            branchRoute: other,
            branchNodeIdx: bestJ,
            kmFromStart: cumDist[bestI],
          ),
        );
      }
    }

    // 300m 이내 중복 병합 (점수 높은 것 유지)
    raw.sort((a, b) => a.kmFromStart.compareTo(b.kmFromStart));
    final merged = <_BranchPoint>[];
    for (final bp in raw) {
      final tooClose = merged.any(
        (m) => RevvRoute.haversineKm(m.location, bp.location) < groupDist,
      );
      if (!tooClose) merged.add(bp);
    }
    return merged;
  }

  // ── 지도 콜백 ──────────────────────────────────────────────────
  void _onMapCreated(mbx.MapboxMap map) {
    _map = map;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    _polyManager = await _map?.annotations.createPolylineAnnotationManager();
    _styleLoaded = true;
    await _drawAll();
    _schedulePinUpdate();
  }

  Future<void> _drawAll() async {
    if (!_styleLoaded || _polyManager == null) return;
    await _polyManager!.deleteAll();

    // 다른 루트 (희미하게)
    for (final r in widget.otherRoutes) {
      final isBranch = _branches.any((b) => b.branchRoute.id == r.id);
      final coords = r.nodes.map((n) => mbx.Position(n.lng, n.lat)).toList();
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: coords),
          lineColor: isBranch ? 0xFFFBBF24 : 0xFF334155,
          lineWidth: isBranch ? 4.0 : 2.5,
          lineOpacity: isBranch ? 0.8 : 0.35,
        ),
      );
    }

    // 현재 루트
    final sel = _selected;
    if (sel != null) {
      // 트림 이후 구간 (희미)
      if (sel.routeNodeIdx < widget.route.nodes.length - 2) {
        final after = widget.route.nodes
            .sublist(sel.routeNodeIdx)
            .map((n) => mbx.Position(n.lng, n.lat))
            .toList();
        await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: after),
            lineColor: 0xFF334155,
            lineWidth: 5.0,
            lineOpacity: 0.4,
          ),
        );
      }
      // 분기점까지 구간 (풀 컬러)
      final before = widget.route.nodes
          .sublist(0, sel.routeNodeIdx + 1)
          .map((n) => mbx.Position(n.lng, n.lat))
          .toList();
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: before),
          lineColor: 0xFFFFFFFF,
          lineWidth: 7.0,
          lineOpacity: 1.0,
        ),
      );
      // 선택된 분기 루트 (노란색 강조)
      final branchCoords = sel.branchRoute.nodes
          .map((n) => mbx.Position(n.lng, n.lat))
          .toList();
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: branchCoords),
          lineColor: 0xFFFBBF24,
          lineWidth: 6.0,
          lineOpacity: 1.0,
        ),
      );
    } else {
      // 루트 전체 표시
      final coords = widget.route.nodes
          .map((n) => mbx.Position(n.lng, n.lat))
          .toList();
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: coords),
          lineColor: 0xFFFFFFFF,
          lineWidth: 7.0,
          lineOpacity: 1.0,
        ),
      );
      final diffColor = _diffColorInt(widget.route.difficultyLevel);
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: coords),
          lineColor: diffColor,
          lineWidth: 4.5,
          lineOpacity: 1.0,
        ),
      );
    }
  }

  // 분기 핀 위치를 픽셀로 변환
  Future<void> _schedulePinUpdate() async {
    if (_updatingPins || _map == null) return;
    _updatingPins = true;
    final newPos = <int, Offset>{};
    for (int i = 0; i < _branches.length; i++) {
      final bp = _branches[i];
      try {
        final px = await _map!.pixelForCoordinate(
          mbx.Point(
            coordinates: mbx.Position(bp.location.lng, bp.location.lat),
          ),
        );
        newPos[i] = Offset(px.x.toDouble(), px.y.toDouble());
      } catch (_) {}
    }
    if (mounted) setState(() => _pinPositions.addAll(newPos));
    _updatingPins = false;
  }

  // ── 적용 ──────────────────────────────────────────────────────
  void _applyBranch() {
    final bp = _selected;
    if (bp == null) return;

    final nodes = widget.route.nodes.sublist(0, bp.routeNodeIdx + 1);
    double dist = 0;
    for (int i = 0; i < nodes.length - 1; i++) {
      dist += RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
    }
    final trimmed = widget.route.copyWith(
      id: '${widget.route.id}_edit',
      nodes: nodes,
      distanceKm: dist,
    );
    // trimmed 루트 + 분기 루트를 결합해서 반환
    Navigator.pop(context, (trimmed: trimmed, branch: bp.branchRoute));
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 지도
          mbx.MapWidget(
            styleUri: MapboxService.cruiseStyle,
            cameraOptions: mbx.CameraOptions(
              center: mbx.Point(
                coordinates: mbx.Position(
                  widget.route.centerPoint.lng,
                  widget.route.centerPoint.lat,
                ),
              ),
              zoom: 11.0,
              pitch: 0,
            ),
            textureView: true,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onScrollListener: (_) => _schedulePinUpdate(),
          ),

          // ── 분기점 핀들 ──
          ..._branches.asMap().entries.map((e) {
            final i = e.key;
            final bp = e.value;
            final pos = _pinPositions[i];
            if (pos == null) return const SizedBox.shrink();
            final isSelected = sel?.branchRoute.id == bp.branchRoute.id;
            return Positioned(
              left: pos.dx - 18,
              top: pos.dy - 36,
              child: GestureDetector(
                onTap: () async {
                  setState(() => _selected = isSelected ? null : bp);
                  await _drawAll();
                  if (!isSelected) {
                    // 분기점으로 flyTo
                    _map?.flyTo(
                      mbx.CameraOptions(
                        center: mbx.Point(
                          coordinates: mbx.Position(
                            bp.location.lng,
                            bp.location.lat,
                          ),
                        ),
                        zoom: 12.5,
                      ),
                      mbx.MapAnimationOptions(duration: 500),
                    );
                  }
                },
                child: _BranchPin(
                  kmFromStart: bp.kmFromStart,
                  isSelected: isSelected,
                ),
              ),
            );
          }),

          // ── 상단 헤더 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.bg.withValues(alpha: 0.82),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: RevvGlassCard(
                      padding: EdgeInsets.zero,
                      color: AppColors.bg.withValues(alpha: 0.82),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_road_rounded,
                              size: 13,
                              color: AppColors.primaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '루트 편집  ·  분기점 ${_branches.length}개',
                              style: AppText.label(
                                size: 11,
                                color: AppColors.textPrimary,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 범례 ──
          if (_branches.isNotEmpty && sel == null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFBBF24),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '황색 핀을 탭하면 분기 방향 선택',
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 빈 상태 ──
          if (_branches.isEmpty && _styleLoaded)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    '주변에 분기 가능한 루트가 없어요',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

          // ── 분기점 선택 카드 ──
          if (sel != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: _BranchCard(
                currentRoute: widget.route,
                branch: sel,
                onApply: _applyBranch,
                onCancel: () async {
                  setState(() => _selected = null);
                  await _drawAll();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── 분기점 핀 위젯 ─────────────────────────────────────────────────
class _BranchPin extends StatelessWidget {
  final double kmFromStart;
  final bool isSelected;
  const _BranchPin({required this.kmFromStart, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFBBF24)
                : Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFFBBF24),
              width: isSelected ? 0 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    const BoxShadow(
                      color: Color(0x88FBBF24),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Text(
            '${kmFromStart.toStringAsFixed(1)}km',
            style: GoogleFonts.orbitron(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.black : const Color(0xFFFBBF24),
              letterSpacing: 0.5,
            ),
          ),
        ),
        // 핀 꼬리
        CustomPaint(
          size: const Size(10, 6),
          painter: _PinTailPainter(
            color: isSelected
                ? const Color(0xFFFBBF24)
                : const Color(0xFFFBBF24),
          ),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}

// ── 분기 선택 카드 ──────────────────────────────────────────────────
class _BranchCard extends StatelessWidget {
  final RevvRoute currentRoute;
  final _BranchPoint branch;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  const _BranchCard({
    required this.currentRoute,
    required this.branch,
    required this.onApply,
    required this.onCancel,
  });

  Color _diffColor(int level) {
    switch (level) {
      case 4:
        return const Color(0xFFEF4444);
      case 3:
        return const Color(0xFFF97316);
      case 2:
        return const Color(0xFFF59E0B);
      case 1:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF60A5FA);
    }
  }

  @override
  Widget build(BuildContext context) {
    final br = branch.branchRoute;
    final diffColor = _diffColor(br.difficultyLevel);
    final totalKm = branch.kmFromStart + br.distanceKm;

    return RevvGlassCard(
      padding: EdgeInsets.zero,
      color: AppColors.bg.withValues(alpha: 0.90),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 3, color: const Color(0xFFFBBF24)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 분기 방향 안내
                  Row(
                    children: [
                      const Icon(
                        Icons.fork_right_rounded,
                        size: 14,
                        color: Color(0xFFFBBF24),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${branch.kmFromStart.toStringAsFixed(1)}km 지점에서 분기',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          color: const Color(0xFFFBBF24),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 분기 루트 정보
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                          color: diffColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              br.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.rajdhani(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  br.difficultyLabel,
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10,
                                    color: diffColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${br.distanceDisplay}  ·  합산 ${totalKm.toStringAsFixed(0)}km',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 버튼
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onCancel,
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh.withValues(
                                alpha: 0.42,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Center(
                              child: Text(
                                '취소',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: onApply,
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFBBF24,
                                  ).withValues(alpha: 0.25),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '이 방향으로 계속',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onPrimary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _diffColorInt(int level) {
  switch (level) {
    case 4:
      return 0xFFEF4444;
    case 3:
      return 0xFFF97316;
    case 2:
      return 0xFFF59E0B;
    case 1:
      return 0xFF22C55E;
    default:
      return 0xFF60A5FA;
  }
}
