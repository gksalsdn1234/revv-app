import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/revv_ui.dart';
import 'cruise_screen.dart';

// SharedPreferences 키 — 캘리브레이션 완료 여부
const String kCalibrationDoneKey = 'revv_calibration_done';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  double _dragDx = 0;
  bool _animating = false;
  late AnimationController _flyCtrl;
  late Animation<double> _flyAnim;
  bool _flyLeft = false;
  // fetch가 완료되기 전까지는 로딩 상태로 표시
  bool _fetchDone = false;

  Future<void> _fetchRoutesFromLiveLocation() async {
    final svc = context.read<RouteService>();
    final loc = context.read<LocationService>();
    await loc.requestPermission();
    if (loc.hasPermission) {
      await loc.startTracking();
    }
    final anchor = await loc.ensureLiveLocation(
      timeout: const Duration(seconds: 6),
    );
    if (!mounted) return;
    if (anchor == null) {
      setState(() => _fetchDone = true);
      return;
    }
    svc.resetCache(); // 캘리브레이션은 항상 새로 탐색
    await svc.fetchRoutes(anchor.lat, anchor.lng);
    if (mounted) setState(() => _fetchDone = true);
  }

  @override
  void initState() {
    super.initState();
    _flyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _flyAnim = CurvedAnimation(parent: _flyCtrl, curve: Curves.easeIn);
    _flyCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _flyCtrl.reset();
        setState(() {
          _index++;
          _dragDx = 0;
          _animating = false;
        });
        if (_index >= _routes().length) {
          _finish();
        }
      }
    });

    // 루트 탐색 시작 — resetCache()로 10km 스킵 조건 우회
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fetchRoutesFromLiveLocation();
    });
  }

  @override
  void dispose() {
    _flyCtrl.dispose();
    super.dispose();
  }

  List<RevvRoute> _routes() => context.read<RouteService>().routes;

  void _swipe(bool exclude) {
    if (_animating) return;
    final routes = _routes();
    if (_index >= routes.length) {
      _finish();
      return;
    }

    if (exclude) {
      context.read<RouteService>().excludeRoute(routes[_index]);
    }
    _flyLeft = exclude;
    _animating = true;
    _flyCtrl.forward();
  }

  Future<void> _finish() async {
    // 루트를 최소 1장 이상 봤을 때만 캘리브레이션 완료로 표시
    // → 루트 0개 상태에서 건너뛰면 다음 실행에서 다시 캘리브레이션 진행
    if (_index > 0 || (_fetchDone && _routes().isNotEmpty)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kCalibrationDoneKey, true);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CruiseScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Consumer<RouteService>(
        builder: (ctx, svc, _) {
          if (svc.isLoading || !_fetchDone) return _buildLoading();
          final routes = svc.routes;
          if (routes.isEmpty) return _buildEmpty();
          if (_index >= routes.length) return _buildDone();
          return _buildCards(routes);
        },
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '주변 드라이빙 루트 탐색 중...',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              color: AppColors.textSecondary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.route,
            size: 40,
            color: AppColors.primaryContainer.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '주변에 루트가 없어요',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _SkipButton(onTap: _finish),
        ],
      ),
    );
  }

  Widget _buildDone() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '캘리브레이션 완료!',
            style: GoogleFonts.orbitron(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '싫어요한 루트는 앞으로 표시되지 않아요',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            child: RevvPrimaryButton(
              label: 'REVV 시작',
              icon: Icons.bolt_rounded,
              onPressed: _finish,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(List<RevvRoute> routes) {
    final route = routes[_index];
    final screenW = MediaQuery.of(context).size.width;
    final total = routes.length;
    final progress = _index / total;

    // 플라이 오프셋 계산
    final flyOffset = _animating
        ? (_flyLeft ? -1.0 : 1.0) * _flyAnim.value * screenW * 1.2
        : 0.0;
    final totalDx = _dragDx + flyOffset;
    final tiltRad = (totalDx / screenW) * 0.3;

    // 좌/우 힌트 opacity
    final hintOpacity = ((totalDx.abs() / 80).clamp(0.0, 1.0));
    final showLeft = totalDx < 0;

    return AnimatedBuilder(
      animation: _flyCtrl,
      builder: (context, _) {
        return SafeArea(
          child: Column(
            children: [
              // ── 헤더 ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CALIBRATION',
                          style: AppText.label(
                            size: 11,
                            color: AppColors.primaryContainer,
                            letterSpacing: 3,
                          ),
                        ),
                        Text(
                          '좋아하는 루트 스타일을 알려주세요',
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _SkipButton(onTap: _finish),
                  ],
                ),
              ),
              // ── 진행 바 ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.surface,
                    color: AppColors.primaryContainer,
                    minHeight: 3,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$_index / $total',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      color: AppColors.textHint,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── 카드 ───────────────────────────────────────────────
              Expanded(
                child: GestureDetector(
                  onPanUpdate: (d) {
                    if (!_animating) setState(() => _dragDx += d.delta.dx);
                  },
                  onPanEnd: (_) {
                    if (_animating) return;
                    if (_dragDx < -80) {
                      _swipe(true); // 배제
                    } else if (_dragDx > 80) {
                      _swipe(false); // 유지
                    } else {
                      setState(() => _dragDx = 0); // 스냅백
                    }
                  },
                  child: Stack(
                    children: [
                      // 다음 카드 (배경에 살짝 보임)
                      if (_index + 1 < routes.length)
                        Positioned.fill(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24) +
                                const EdgeInsets.only(bottom: 32),
                            child: Transform.scale(
                              scale: 0.94,
                              child: _RouteCard(
                                route: routes[_index + 1],
                                opacity: 0.45,
                              ),
                            ),
                          ),
                        ),
                      // 현재 카드
                      Positioned.fill(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16) +
                              const EdgeInsets.only(bottom: 24),
                          child: Transform(
                            transform: Matrix4.translationValues(
                              totalDx,
                              0.0,
                              0.0,
                            )..rotateZ(tiltRad),
                            alignment: Alignment.bottomCenter,
                            child: Stack(
                              children: [
                                _RouteCard(route: route),
                                // 좌측 배제 힌트
                                if (showLeft)
                                  Positioned(
                                    top: 24,
                                    left: 20,
                                    child: Opacity(
                                      opacity: hintOpacity,
                                      child: _HintBadge(
                                        label: '싫어요',
                                        color: AppColors.red,
                                        icon: Icons.close_rounded,
                                      ),
                                    ),
                                  ),
                                // 우측 좋아요 힌트
                                if (!showLeft && totalDx > 0)
                                  Positioned(
                                    top: 24,
                                    right: 20,
                                    child: Opacity(
                                      opacity: hintOpacity,
                                      child: _HintBadge(
                                        label: '좋아요',
                                        color: const Color(0xFF22C55E),
                                        icon: Icons.favorite_rounded,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 하단 버튼 ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.close_rounded,
                      color: AppColors.red,
                      label: '싫어요',
                      onTap: () => _swipe(true),
                    ),
                    _ActionButton(
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFF22C55E),
                      label: '좋아요',
                      onTap: () => _swipe(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 루트 카드 (게임 맵 스타일) ────────────────────────────────────────
class _RouteCard extends StatelessWidget {
  final RevvRoute route;
  final double opacity;
  const _RouteCard({required this.route, this.opacity = 1.0});

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
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diffColor(route.difficultyLevel);
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: diff.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: diff.withValues(alpha: 0.15),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 미니맵 영역 ──────────────────────────────────────
              Stack(
                children: [
                  // 미니맵 CustomPainter
                  SizedBox(
                    height: 200,
                    child: CustomPaint(
                      painter: _RouteMapPainter(
                        nodes: route.nodes,
                        routeColor: diff,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // 좌상단 — 난이도 배지
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: diff.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        route.difficultyLabel,
                        style: GoogleFonts.orbitron(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  // 우상단 — 집 거리
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.home_rounded,
                            size: 10,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            route.distanceFromUserDisplay,
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 하단 — 거리 + 시간 오버레이
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          _MapStatChip(
                            icon: Icons.straighten,
                            value: route.distanceDisplay,
                            color: diff,
                          ),
                          const SizedBox(width: 10),
                          _MapStatChip(
                            icon: Icons.schedule,
                            value: route.durationDisplay,
                          ),
                          if (route.isLoop) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppColors.cyan.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.loop,
                                    size: 9,
                                    color: AppColors.cyan,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'LOOP',
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.cyan,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          // 와인딩 밀도 %
                          if (route.windingDensityPct > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.turn_right,
                                  size: 10,
                                  color: diff.withValues(alpha: 0.9),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${route.windingDensityPct.toStringAsFixed(0)}%',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: diff,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // ── 하단 정보 패널 ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: GoogleFonts.orbitron(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    _CurveBar(route: route, accentColor: diff),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 게임 맵 스타일 루트 미니맵 ──────────────────────────────────────────
class _RouteMapPainter extends CustomPainter {
  final List<LatLng> nodes;
  final Color routeColor;
  const _RouteMapPainter({required this.nodes, required this.routeColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 2) return;
    final pad = size.width * 0.1;

    // ── 좌표 정규화 ───────────────────────────────────────────────
    double minLat = nodes[0].lat, maxLat = nodes[0].lat;
    double minLng = nodes[0].lng, maxLng = nodes[0].lng;
    for (final n in nodes) {
      if (n.lat < minLat) minLat = n.lat;
      if (n.lat > maxLat) maxLat = n.lat;
      if (n.lng < minLng) minLng = n.lng;
      if (n.lng > maxLng) maxLng = n.lng;
    }
    final latRange = (maxLat - minLat).abs();
    final lngRange = (maxLng - minLng).abs();
    final range = math.max(latRange, lngRange);
    if (range < 1e-7) return;

    // 종횡비 보정
    final latScale =
        (size.height - pad * 2) / (latRange < 1e-7 ? range : latRange);
    final lngScale =
        (size.width - pad * 2) / (lngRange < 1e-7 ? range : lngRange);
    final scale = math.min(latScale, lngScale);

    final latOffset = (size.height - pad * 2 - latRange * scale) / 2;
    final lngOffset = (size.width - pad * 2 - lngRange * scale) / 2;

    Offset toCanvas(LatLng n) => Offset(
      pad + lngOffset + (n.lng - minLng) * scale,
      size.height - pad - latOffset - (n.lat - minLat) * scale,
    );

    // ── 배경 ─────────────────────────────────────────────────────
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0A0D),
    );

    // ── 격자 (게임 맵 느낌) ────────────────────────────────────────
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    const gridCount = 8;
    for (int i = 0; i <= gridCount; i++) {
      final x = i / gridCount * size.width;
      final y = i / gridCount * size.height;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── 루트 글로우 (외곽선) ──────────────────────────────────────
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = routeColor.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final routePath = Path();
    for (int i = 0; i < nodes.length; i++) {
      final pt = toCanvas(nodes[i]);
      if (i == 0) {
        routePath.moveTo(pt.dx, pt.dy);
      } else {
        routePath.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(routePath, glowPaint);

    // ── 루트 본선 ─────────────────────────────────────────────────
    canvas.drawPath(
      routePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = routeColor,
    );

    // ── 시작점 (녹색 원) ──────────────────────────────────────────
    final start = toCanvas(nodes.first);
    canvas.drawCircle(start, 5, Paint()..color = const Color(0xFF22C55E));
    canvas.drawCircle(
      start,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.8),
    );

    // ── 끝점 (체크 깃발 느낌 — 흰 원) ────────────────────────────
    final end = toCanvas(nodes.last);
    canvas.drawCircle(
      end,
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      end,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = routeColor,
    );
  }

  @override
  bool shouldRepaint(_RouteMapPainter old) =>
      old.nodes != nodes || old.routeColor != routeColor;
}

// ── 맵 오버레이 스탯 칩 ──────────────────────────────────────────────
class _MapStatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _MapStatChip({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha: 0.7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: c),
        const SizedBox(width: 3),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c,
          ),
        ),
      ],
    );
  }
}

// ── 커브 분포 바 ─────────────────────────────────────────────────────
class _CurveBar extends StatelessWidget {
  final RevvRoute route;
  final Color accentColor;
  const _CurveBar({required this.route, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final total = route.tightCurveKm + route.mediumCurveKm;
    if (total <= 0) return const SizedBox.shrink();
    final tightRatio = (route.tightCurveKm / total).clamp(0.0, 1.0);
    final medRatio = (route.mediumCurveKm / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CURVE MIX',
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            color: AppColors.textHint,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                Expanded(
                  flex: (tightRatio * 100).round(),
                  child: Container(color: accentColor),
                ),
                Expanded(
                  flex: (medRatio * 100).round(),
                  child: Container(color: accentColor.withValues(alpha: 0.45)),
                ),
                if (tightRatio + medRatio < 1.0)
                  Expanded(
                    flex: ((1 - tightRatio - medRatio) * 100).round(),
                    child: Container(color: AppColors.surface),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _CurveChip('TIGHT', route.tightCurveKm, accentColor),
            const SizedBox(width: 8),
            _CurveChip(
              'MED',
              route.mediumCurveKm,
              accentColor.withValues(alpha: 0.6),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurveChip extends StatelessWidget {
  final String label;
  final double km;
  final Color color;
  const _CurveChip(this.label, this.km, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, color: color),
        const SizedBox(width: 4),
        Text(
          '$label ${km.toStringAsFixed(1)}km',
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            color: AppColors.textHint,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── 힌트 배지 (드래그 시 표시) ─────────────────────────────────────────
class _HintBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _HintBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.orbitron(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 액션 버튼 ─────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 스킵 버튼 ─────────────────────────────────────────────────────────
class _SkipButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        '건너뛰기',
        style: GoogleFonts.rajdhani(
          fontSize: 12,
          color: AppColors.textHint,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
