import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../theme/colors.dart';
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
      final svc = context.read<RouteService>();
      final loc = context.read<LocationService>();
      svc.resetCache(); // 캘리브레이션은 항상 새로 탐색
      await svc.fetchRoutes(loc.lat, loc.lng);
      if (mounted) setState(() => _fetchDone = true);
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
    if (_index >= routes.length) { _finish(); return; }

    if (exclude) {
      context.read<RouteService>().excludeRoute(routes[_index]);
    }
    _flyLeft = exclude;
    _animating = true;
    _flyCtrl.forward();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kCalibrationDoneKey, true);
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
              color: AppColors.red,
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
          Icon(Icons.route, size: 40, color: AppColors.red.withOpacity(0.5)),
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
          GestureDetector(
            onTap: _finish,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.redGlow,
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                'REVV 시작',
                style: GoogleFonts.orbitron(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
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
                          style: GoogleFonts.orbitron(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red,
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
                    color: AppColors.red,
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
                            padding: const EdgeInsets.symmetric(horizontal: 24) +
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
                          padding: const EdgeInsets.symmetric(horizontal: 16) +
                              const EdgeInsets.only(bottom: 24),
                          child: Transform(
                            transform: Matrix4.translationValues(totalDx, 0.0, 0.0)
                              ..rotateZ(tiltRad),
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

// ── 루트 카드 ────────────────────────────────────────────────────────
class _RouteCard extends StatelessWidget {
  final RevvRoute route;
  final double opacity;
  const _RouteCard({required this.route, this.opacity = 1.0});

  Color _diffColor(int level) {
    switch (level) {
      case 4: return const Color(0xFFEF4444);
      case 3: return const Color(0xFFF97316);
      case 2: return const Color(0xFFF59E0B);
      case 1: return const Color(0xFF22C55E);
      default: return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diffColor(route.difficultyLevel);
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: diff.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: diff.withOpacity(0.08),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 컬러 스트립
              Container(height: 4, color: diff),
              // 곡률 시각화 (미니 파형)
              _CurvatureViz(route: route, accentColor: diff),
              // 루트 정보
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 난이도 + 이름
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: diff.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        route.difficultyLabel,
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: diff,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      route.name,
                      style: GoogleFonts.orbitron(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    // 스탯 행
                    Row(
                      children: [
                        _StatItem(icon: Icons.straighten, value: route.distanceDisplay),
                        const SizedBox(width: 20),
                        _StatItem(icon: Icons.schedule, value: route.durationDisplay),
                        const SizedBox(width: 20),
                        _StatItem(
                          icon: Icons.near_me,
                          value: route.distanceFromUserDisplay,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 커브 분포 바
                    _CurveBar(route: route, accentColor: diff),
                    if (route.isLoop) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.loop, size: 10, color: AppColors.cyan),
                            const SizedBox(width: 4),
                            Text(
                              'LOOP',
                              style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.cyan,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

// ── 곡률 시각화 (미니 파형) ─────────────────────────────────────────
class _CurvatureViz extends StatelessWidget {
  final RevvRoute route;
  final Color accentColor;
  const _CurvatureViz({required this.route, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: CustomPaint(
        painter: _WaveformPainter(
          nodes: route.nodes,
          color: accentColor,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<LatLng> nodes;
  final Color color;
  const _WaveformPainter({required this.nodes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 3) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.6);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.08);

    // 방위각 변화로 "파형" 생성
    final angles = <double>[];
    for (int i = 1; i < nodes.length; i++) {
      final dlat = nodes[i].lat - nodes[i - 1].lat;
      final dlng = nodes[i].lng - nodes[i - 1].lng;
      angles.add(math.atan2(dlng, dlat));
    }

    // 샘플링
    const steps = 60;
    final step = math.max(1, angles.length ~/ steps);
    final sampled = <double>[];
    for (int i = 0; i < angles.length; i += step) sampled.add(angles[i]);

    if (sampled.isEmpty) return;

    // 스무딩
    final smoothed = <double>[];
    for (int i = 0; i < sampled.length; i++) {
      double sum = 0;
      int cnt = 0;
      for (int j = math.max(0, i - 2); j <= math.min(sampled.length - 1, i + 2); j++) {
        sum += sampled[j]; cnt++;
      }
      smoothed.add(sum / cnt);
    }

    // 정규화
    final minV = smoothed.reduce(math.min);
    final maxV = smoothed.reduce(math.max);
    final range = (maxV - minV).abs();
    if (range < 0.001) return;

    final path = Path();
    final fillPath = Path();
    final baseline = size.height * 0.5;

    for (int i = 0; i < smoothed.length; i++) {
      final x = i / (smoothed.length - 1) * size.width;
      final norm = (smoothed[i] - minV) / range; // 0..1
      final y = baseline + (norm - 0.5) * size.height * 0.6;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, baseline);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, baseline);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.nodes != nodes || old.color != color;
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
                  child: Container(color: accentColor.withOpacity(0.45)),
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
            _CurveChip('MED', route.mediumCurveKm, accentColor.withOpacity(0.6)),
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

// ── 스탯 아이템 ───────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  const _StatItem({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
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
  const _HintBadge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
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
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.2),
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
