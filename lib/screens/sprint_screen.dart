import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../widgets/map_widget.dart';
import '../widgets/sprint_toggle.dart';
import '../widgets/mic_button.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/run_session_service.dart';
import '../services/driving_context_service.dart';
import '../services/directions_service.dart';
import '../services/imu_service.dart';
import '../services/turn_by_turn_service.dart';
import '../services/settings_service.dart';
import '../models/nav_step.dart';
import '../models/run_session.dart';
import 'run_card_screen.dart';

class SprintScreen extends StatefulWidget {
  final RevvRoute? selectedRoute;
  final void Function(RunSession? session)? onEnd;
  final void Function(List<LatLng>? poly)? onNavPolylineChanged;

  const SprintScreen({
    super.key,
    this.selectedRoute,
    this.onEnd,
    this.onNavPolylineChanged,
  });

  @override
  State<SprintScreen> createState() => _SprintScreenState();
}

class _SprintScreenState extends State<SprintScreen>
    with SingleTickerProviderStateMixin {
  LocationService? _locationService;
  RunSessionService? _runSessionService;

  List<LatLng>? _navPolyline;
  bool _onRoute = false;
  bool _isOffRoute = false;
  String? _routeStatusMsg;
  TurnByTurnService? _tbtService;
  double _tbtDistM = 0;
  bool _isMuted = false;

  // G-Force 레드 플래시
  late AnimationController _flashCtrl;
  late Animation<double> _flashAnim;
  double _lastFlashG = 0;
  static const double _flashThreshold = 0.65;

  // G-Force 궤적 (trail)
  final List<Offset> _gTrail = [];
  static const int _trailLen = 30;

  @override
  void initState() {
    super.initState();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
    );
  }

  void _triggerGFlash() => _flashCtrl.forward(from: 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_locationService == null) {
      _locationService = context.read<LocationService>();
      _runSessionService = context.read<RunSessionService>();
      final weather = context.read<WeatherService>();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _runSessionService!.startSession(
          widget.selectedRoute,
          weatherEmoji: weather.weatherEmoji,
          tempDisplay: weather.tempDisplay,
          weatherDesc: weather.weatherDesc,
        );
      });

      _locationService!.addListener(_onLocation);
      context.read<ImuService>().addListener(_onImu);
      _isMuted = context.read<SettingsService>().ttsMuted;

      if (widget.selectedRoute != null) _fetchNavRoute();
    }
  }

  Future<void> _fetchNavRoute() async {
    final loc = _locationService!;
    final start = widget.selectedRoute!.nodes.first;
    final result = await DirectionsService.getRouteWithSteps(
      LatLng(loc.lat, loc.lng),
      start,
    );
    if (!mounted) return;
    setState(() => _navPolyline = result.polyline);
    widget.onNavPolylineChanged?.call(result.polyline);
    if (result.steps.isNotEmpty) {
      _tbtService?.stop();
      _tbtService = TurnByTurnService(
        steps: result.steps,
        onUpdate: () { if (mounted) setState(() {}); },
        initialMuted: context.read<SettingsService>().ttsMuted,
      );
    }
  }

  void _onLocation() {
    final loc = _locationService;
    if (loc == null) return;
    _runSessionService?.recordPosition(loc.lat, loc.lng, loc.speedKmh);
    final drivingCtx = context.read<DrivingContextService>();
    _runSessionService?.recordDriveMode(drivingCtx.mode.name);

    if (!_onRoute && widget.selectedRoute != null && _navPolyline != null) {
      final start = widget.selectedRoute!.nodes.first;
      final dist = RevvRoute.haversineKm(LatLng(loc.lat, loc.lng), start);
      if (dist < 0.2) {
        _tbtService?.stop();
        _tbtService = null;
        setState(() {
          _onRoute = true;
          _navPolyline = null;
          _routeStatusMsg = '루트 진입!';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _routeStatusMsg = null);
        });
        return;
      }
    }

    if (_onRoute && widget.selectedRoute != null) {
      final pos = LatLng(loc.lat, loc.lng);
      double minDist = double.infinity;
      for (final node in widget.selectedRoute!.nodes) {
        final d = RevvRoute.haversineKm(pos, node);
        if (d < minDist) minDist = d;
        if (minDist < 0.2) break;
      }
      final wasOff = _isOffRoute;
      final nowOff = minDist > 0.3;
      if (wasOff != nowOff) {
        setState(() {
          _isOffRoute = nowOff;
          if (!nowOff) {
            _routeStatusMsg = '루트로 복귀했어요!';
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _routeStatusMsg = null);
            });
          }
        });
      }
    }

    if (_tbtService != null) {
      _tbtService!.updateLocation(loc.lat, loc.lng);
      final d = _tbtService!.distanceToNextM(loc.lat, loc.lng);
      if ((d - _tbtDistM).abs() > 5) setState(() => _tbtDistM = d);
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _tbtService?.toggleMute();
    context.read<SettingsService>().setTtsMuted(_isMuted);
  }

  void _onImu() {
    if (!mounted) return;
    final imu = context.read<ImuService>();
    final lG = imu.lateralG;
    final nG = imu.longitudinalG;
    final g = lG.abs();

    // 궤적 업데이트
    setState(() {
      _gTrail.add(Offset(lG, nG));
      if (_gTrail.length > _trailLen) _gTrail.removeAt(0);
    });

    // 플래시 트리거
    if (g >= _flashThreshold && _lastFlashG < _flashThreshold) {
      _triggerGFlash();
    }
    _lastFlashG = g;
  }

  void _endRun() {
    _locationService?.removeListener(_onLocation);
    _tbtService?.stop();
    try { context.read<ImuService>().removeListener(_onImu); } catch (_) {}
    final imu = context.read<ImuService>();
    final session = _runSessionService?.stopSession(
      maxLateralG: imu.maxLateralG,
      maxLonG: imu.maxLonG,
    );
    imu.resetMaxG();
    if (!mounted) return;
    if (widget.onEnd != null) {
      widget.onEnd!(session);
      return;
    }
    Navigator.pushReplacement(
      context,
      _RunCardRoute(RunCardScreen(session: session)),
    );
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onLocation);
    _tbtService?.stop();
    _flashCtrl.dispose();
    super.dispose();
  }

  // ── 메인 빌드: 풀스크린 네비게이션 + 오버레이 ──────────────
  Widget _buildSprintBody(BuildContext context) {
    return Consumer<DrivingContextService>(
      builder: (_, ctx, __) => Stack(
        fit: StackFit.expand, // 오버레이 모드에서도 부모 크기 채우기 (RenderBox layout fix)
        children: [
          // ── 지도 (독립 모드만 — 오버레이 모드는 CruiseScreen 지도 사용) ──
          if (widget.onEnd == null)
            Positioned.fill(
              child: MapWidget(
                isSprintMode: true,
                navPolyline: _navPolyline,
                routePolyline: widget.selectedRoute?.nodes,
              ),
            ),

          // ── 드라이브 모드 테두리 글로우 ──
          if (ctx.mode != DriveMode.cruise)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: ctx.mode.color.withValues(alpha: 0.6),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),

          // ── 상단: 턴바이턴 배너 ──
          if (_tbtService != null && _tbtService!.upcomingStep != null)
            Positioned(
              top: 0, left: 0, right: 0,
              child: _NavBanner(
                step: _tbtService!.upcomingStep!,
                distanceM: _tbtDistM,
                muted: _tbtService!.muted,
                onToggleMute: _tbtService!.toggleMute,
              ),
            ),

          // ── 상단 우측: 드라이브 모드 배지 ──
          if (ctx.mode != DriveMode.cruise)
            Positioned(
              top: (_tbtService?.upcomingStep != null) ? 76 : 16,
              right: 14,
              child: _ModeBadge(mode: ctx.mode),
            ),

          // ── 상단 좌측: 경과/거리 pill ──
          Positioned(
            top: (_tbtService?.upcomingStep != null) ? 76 : 16,
            left: 14,
            child: const _LiveStatHUD(),
          ),

          // ── 하단 우측: G-Force 원형 미터 ──
          Positioned(
            bottom: 80, // 바텀바 위
            right: 14,
            child: _GForceMeter(trail: _gTrail),
          ),

          // ── 루트 이동 중 안내 ──
          if (!_onRoute && _navPolyline != null && widget.selectedRoute != null)
            Positioned(
              bottom: 88,
              left: 0, right: 0,
              child: Center(
                child: _StatusPill(
                  text: '🔵  ${widget.selectedRoute!.name} 으로 이동 중',
                  color: Colors.lightBlueAccent,
                ),
              ),
            ),

          // ── 루트 진입 / 복귀 메시지 ──
          if (_routeStatusMsg != null)
            Positioned(
              bottom: 88,
              left: 0, right: 0,
              child: Center(
                child: _StatusPill(
                  text: '🏁  $_routeStatusMsg',
                  color: AppColors.red,
                ),
              ),
            ),

          // ── 루트 이탈 경고 배너 ──
          if (_isOffRoute)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: _OffRouteBanner(),
            ),

          // ── 하단 바: 음소거 + 마이크 + 런 종료 ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _SprintBottomBar(
              onEnd: _endRun,
              modeColor: ctx.mode.color,
              muted: _isMuted,
              onToggleMute: _toggleMute,
            ),
          ),
        ],
      ),
    );
  }

  // G-Force 레드 플래시 오버레이
  Widget _buildFlashOverlay() {
    return AnimatedBuilder(
      animation: _flashAnim,
      builder: (_, __) {
        if (_flashCtrl.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        final opacity = (1 - _flashAnim.value) * 0.45;
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.red.withValues(alpha: opacity * 1.2),
                    AppColors.red.withValues(alpha: opacity * 0.3),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      fit: StackFit.expand,
      children: [
        _buildSprintBody(context),
        _buildFlashOverlay(),
      ],
    );

    if (widget.onEnd != null) {
      return PopScope(
        canPop: false,
        child: Material(color: Colors.transparent, child: body),
      );
    }
    return PopScope(
      canPop: false,
      child: Scaffold(backgroundColor: AppColors.bg, body: body),
    );
  }
}

// ── G-Force 원형 미터 ─────────────────────────────────────────
class _GForceMeter extends StatelessWidget {
  final List<Offset> trail;
  const _GForceMeter({required this.trail});

  @override
  Widget build(BuildContext context) {
    return Consumer<ImuService>(
      builder: (_, imu, __) {
        final lG = imu.lateralG.clamp(-1.5, 1.5);
        final nG = imu.longitudinalG.clamp(-1.5, 1.5);
        final total = math.sqrt(lG * lG + nG * nG);

        final dotColor = _gColor(total);

        return Container(
          width: 164,
          height: 186,
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dotColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              // 원형 + 자동차 + 도트
              SizedBox(
                width: 144,
                height: 144,
                child: CustomPaint(
                  painter: _GForcePainter(
                    lateralG: lG,
                    longitudinalG: nG,
                    trail: trail,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // LAT / LON 수치
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _GLabel(label: 'LAT', value: lG, axis: 'L↔R'),
                    _GLabel(label: 'LON', value: nG, axis: '↑↓', alignRight: true),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  static Color _gColor(double total) {
    if (total > 0.6) return AppColors.red;
    if (total > 0.3) return Colors.orange;
    return Colors.lightBlueAccent;
  }
}

class _GLabel extends StatelessWidget {
  final String label;
  final double value;
  final String axis;
  final bool alignRight;
  const _GLabel({
    required this.label,
    required this.value,
    required this.axis,
    this.alignRight = false,
  });

  Color get _color {
    final abs = value.abs();
    if (abs > 0.6) return AppColors.red;
    if (abs > 0.3) return Colors.orange;
    return Colors.lightBlueAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 8,
            color: AppColors.gray,
            letterSpacing: 1.5,
          ),
        ),
        Text(
          '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}G',
          style: GoogleFonts.orbitron(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      ],
    );
  }
}

// ── G-Force CustomPainter ─────────────────────────────────────
class _GForcePainter extends CustomPainter {
  final double lateralG;
  final double longitudinalG;
  final List<Offset> trail;

  const _GForcePainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.trail,
  });

  static const double _maxG = 1.5;

  Color _dotColor(double total) {
    if (total > 0.6) return AppColors.red;
    if (total > 0.3) return Colors.orange;
    return Colors.lightBlueAccent;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = cx - 4;

    // ── 배경 원 ──
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = const Color(0xFF111111)
        ..style = PaintingStyle.fill,
    );

    // ── 동심원 링 (0.3G, 0.6G, 1.0G) ──
    _drawRing(canvas, cx, cy, r * (0.3 / _maxG), Colors.lightBlueAccent.withValues(alpha: 0.3));
    _drawRing(canvas, cx, cy, r * (0.6 / _maxG), Colors.orange.withValues(alpha: 0.35));
    _drawRing(canvas, cx, cy, r * (1.0 / _maxG), AppColors.red.withValues(alpha: 0.4));

    // ── 링 라벨 ──
    _drawRingLabel(canvas, cx, cy, r * (0.3 / _maxG), '0.3G', Colors.lightBlueAccent.withValues(alpha: 0.55));
    _drawRingLabel(canvas, cx, cy, r * (0.6 / _maxG), '0.6G', Colors.orange.withValues(alpha: 0.6));
    _drawRingLabel(canvas, cx, cy, r * (1.0 / _maxG), '1.0G', AppColors.red.withValues(alpha: 0.65));

    // ── 십자선 ──
    final crossPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), crossPaint);

    // ── 자동차 실루엣 (중앙) ──
    _drawCar(canvas, cx, cy);

    // ── 궤적 (trail) ──
    for (int i = 0; i < trail.length; i++) {
      final t = trail[i];
      final dx = t.dx / _maxG * r;
      final dy = -t.dy / _maxG * r;
      final alpha = (i / trail.length) * 0.5;
      final total = math.sqrt(t.dx * t.dx + t.dy * t.dy);
      canvas.drawCircle(
        Offset(cx + dx, cy + dy),
        2.5,
        Paint()..color = _dotColor(total).withValues(alpha: alpha),
      );
    }

    // ── 현재 G 도트 ──
    final dx = lateralG / _maxG * r;
    final dy = -longitudinalG / _maxG * r;
    final total = math.sqrt(lateralG * lateralG + longitudinalG * longitudinalG);
    final dotColor = _dotColor(total);

    // 글로우
    canvas.drawCircle(
      Offset(cx + dx, cy + dy), 9,
      Paint()..color = dotColor.withValues(alpha: 0.25),
    );
    // 도트
    canvas.drawCircle(
      Offset(cx + dx, cy + dy), 5.5,
      Paint()..color = dotColor,
    );
    // 하이라이트
    canvas.drawCircle(
      Offset(cx + dx - 1.5, cy + dy - 1.5), 1.8,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _drawRing(Canvas canvas, double cx, double cy, double r, Color color) {
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawRingLabel(Canvas canvas, double cx, double cy, double r,
      String label, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx + r + 2, cy - tp.height / 2));
  }

  void _drawCar(Canvas canvas, double cx, double cy) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 차체
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: 12, height: 22),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, paint);
    canvas.drawRRect(body, strokePaint);

    // 지붕 (캐빈)
    final cabin = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 2), width: 9, height: 12),
      const Radius.circular(2),
    );
    canvas.drawRRect(cabin, paint);
    canvas.drawRRect(cabin, strokePaint);

    // 바퀴 4개
    const wheelW = 4.0;
    const wheelH = 5.0;
    for (final pos in [
      Offset(cx - 8, cy - 8),
      Offset(cx + 5, cy - 8),
      Offset(cx - 8, cy + 5),
      Offset(cx + 5, cy + 5),
    ]) {
      final wheel = RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: wheelW, height: wheelH),
        const Radius.circular(1),
      );
      canvas.drawRRect(wheel, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }

    // 전면 표시 (위쪽 = 전진 방향)
    canvas.drawLine(
      Offset(cx - 3, cy - 10),
      Offset(cx + 3, cy - 10),
      Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GForcePainter old) =>
      old.lateralG != lateralG ||
      old.longitudinalG != longitudinalG ||
      old.trail.length != trail.length;
}

// ── 라이브 스탯 HUD ──────────────────────────────────────────
class _LiveStatHUD extends StatefulWidget {
  const _LiveStatHUD();

  @override
  State<_LiveStatHUD> createState() => _LiveStatHUDState();
}

class _LiveStatHUDState extends State<_LiveStatHUD> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<RunSessionService>();
    final dur = session.currentDuration;
    final dist = session.currentDistance;
    final distStr = dist >= 1.0
        ? '${dist.toStringAsFixed(2)} km'
        : '${(dist * 1000).toStringAsFixed(0)} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(icon: Icons.timer_outlined, value: _fmt(dur)),
          const SizedBox(width: 2),
          Container(width: 1, height: 22, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 8)),
          _Pill(icon: Icons.straighten, value: distStr),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String value;
  const _Pill({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: AppColors.gray),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.orbitron(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ── 상태 메시지 pill ─────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 10),
        ],
      ),
      child: Text(
        text,
        style: GoogleFonts.rajdhani(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ── 루트 이탈 경고 배너 ───────────────────────────────────────
class _OffRouteBanner extends StatelessWidget {
  const _OffRouteBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade700, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⚠️  루트를 벗어났어요 — 루트로 돌아가세요',
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 드라이빙 모드 뱃지 ───────────────────────────────────────
class _ModeBadge extends StatelessWidget {
  final DriveMode mode;
  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: mode.color.withValues(alpha: 0.7), width: 1),
        boxShadow: [
          BoxShadow(color: mode.color.withValues(alpha: 0.2), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mode.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          Text(
            mode.label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: mode.color,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 바텀 바 ──────────────────────────────────────────────────
class _SprintBottomBar extends StatelessWidget {
  final VoidCallback onEnd;
  final Color modeColor;
  final bool muted;
  final VoidCallback onToggleMute;
  const _SprintBottomBar({
    required this.onEnd,
    required this.modeColor,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.93),
        border: Border(
          top: BorderSide(color: modeColor.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // 음소거
          _BarBtn(
            icon: muted ? Icons.volume_off : Icons.volume_up,
            color: muted ? AppColors.gray : Colors.lightBlueAccent,
            onTap: onToggleMute,
          ),
          const SizedBox(width: 8),
          const MicButton(),
          const Spacer(),
          // 런 종료 버튼
          RedGlowButton(
            label: '🏁 런 종료',
            filled: true,
            height: 48,
            onTap: onEnd,
          ),
        ],
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BarBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

// ── 턴바이턴 안내 배너 ────────────────────────────────────────
class _NavBanner extends StatelessWidget {
  final NavStep step;
  final double distanceM;
  final bool muted;
  final VoidCallback onToggleMute;
  const _NavBanner({
    required this.step,
    required this.distanceM,
    required this.muted,
    required this.onToggleMute,
  });

  String get _distText {
    if (distanceM >= 1000) return '${(distanceM / 1000).toStringAsFixed(1)} km';
    return '${distanceM.toInt()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.94),
        border: Border(
          bottom: BorderSide(color: Colors.lightBlueAccent.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Icon(step.icon, color: Colors.lightBlueAccent, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.koreanInstruction,
                  style: GoogleFonts.rajdhani(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (step.streetName.isNotEmpty)
                  Text(
                    step.streetName,
                    style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.gray),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _distText,
            style: GoogleFonts.orbitron(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.lightBlueAccent,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onToggleMute,
            child: Icon(
              muted ? Icons.volume_off : Icons.volume_up,
              color: muted ? AppColors.gray : Colors.lightBlueAccent,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunCardRoute extends PageRouteBuilder {
  _RunCardRoute(Widget page)
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, _, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                child: child,
              ),
            );
          },
        );
}
