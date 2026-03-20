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

  // G-Force (trail — 호환용)
  final List<Offset> _gTrail = [];

  // 루트 진행률 (0.0 ~ 1.0)
  double _routeProgressPct = 0.0;

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
      final nodes = widget.selectedRoute!.nodes;
      double minDist = double.infinity;
      int closestIdx = 0;
      for (int i = 0; i < nodes.length; i++) {
        final d = RevvRoute.haversineKm(pos, nodes[i]);
        if (d < minDist) { minDist = d; closestIdx = i; }
        if (minDist < 0.05) break;
      }
      final wasOff = _isOffRoute;
      final nowOff = minDist > 0.3;
      final newPct = nodes.length > 1 ? closestIdx / (nodes.length - 1) : 0.0;
      if (wasOff != nowOff || (newPct - _routeProgressPct).abs() > 0.005) {
        setState(() {
          _isOffRoute = nowOff;
          _routeProgressPct = newPct;
          if (!nowOff && wasOff) {
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
      // StackFit.expand 제거 — tight constraints는 부모 Positioned.fill에서 제공
      // StackFit.expand + Consumer<ImuService>(50Hz) 조합이 layout assertion 유발
      builder: (_, ctx, __) => Stack(
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

          // ── 하단 좌측: 커브 예고 아이콘 ──
          if (_tbtService != null)
            Positioned(
              bottom: 84,
              left: 14,
              child: _CurvePreviewIcon(
                step: _tbtService!.upcomingStep,
                distM: _tbtDistM,
              ),
            ),

          // ── 루트 진행률 바 (바텀바 바로 위, 3px) ──
          if (_onRoute && widget.selectedRoute != null)
            Positioned(
              bottom: 68,
              left: 0,
              right: 0,
              child: _RouteProgressBar(pct: _routeProgressPct),
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
    // Positioned.fill을 AnimatedBuilder 바깥에 — Stack 직접 자식으로 배치해야 layout 안전
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _flashAnim,
          builder: (_, __) {
            if (_flashCtrl.status == AnimationStatus.dismissed) {
              return const SizedBox.shrink();
            }
            final opacity = (1 - _flashAnim.value) * 0.45;
            return Container(
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
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Positioned.fill로 자식을 감싸는 방식 — StackFit.expand 대체
    // StackFit.expand는 Consumer<ImuService>(50Hz)와 충돌해 !_debugDoingThisLayout 유발
    final body = Stack(
      children: [
        Positioned.fill(child: _buildSprintBody(context)),
        _buildFlashOverlay(), // 이미 Positioned.fill 반환
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

// ── G-Force 자동차 글로우 미터 ───────────────────────────────
// 자동차 실루엣 중앙 고정, G force 방향으로 외부 글로우가 쏠림
// lateralG > 0 = 오른쪽 코너링 → 차 오른쪽 빛남
// longitudinalG > 0 = 가속 → 차 뒤쪽 빛남  /  < 0 = 제동 → 앞쪽 빛남
class _GForceMeter extends StatelessWidget {
  final List<Offset> trail; // unused but kept for API compatibility
  const _GForceMeter({required this.trail});

  static Color _gColor(double total) {
    if (total > 0.6) return AppColors.red;
    if (total > 0.3) return Colors.orange;
    return Colors.lightBlueAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ImuService>(
      builder: (_, imu, __) {
        final lG = imu.lateralG.clamp(-1.5, 1.5);   // 좌(-) 우(+)
        final nG = imu.longitudinalG.clamp(-1.5, 1.5); // 제동(-) 가속(+)
        final total = math.sqrt(lG * lG + nG * nG);
        final glowColor = _gColor(total);
        final glowAlpha = (total / 1.5).clamp(0.0, 1.0);

        // 글로우 중심: G force 반대 방향으로 이동 (관성 = 차가 그쪽으로 쏠림)
        // 오른쪽 코너링(lG>0) → 차 오른쪽 면이 받는 힘 → 오른쪽 글로우
        final glowOffsetX = lG / 1.5 * 28.0;
        final glowOffsetY = -nG / 1.5 * 32.0; // 가속(+) → 뒤쪽 빛남 → y 위 방향

        return Container(
          width: 130,
          // height 고정 제거 — Column이 내용물 높이에 맞게 자동 결정
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: glowColor.withValues(alpha: 0.2 + glowAlpha * 0.3),
              width: 1,
            ),
            boxShadow: [
              // 외부 컨테이너 글로우
              BoxShadow(
                color: glowColor.withValues(alpha: glowAlpha * 0.25),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // 자동차 + 방향성 글로우
              SizedBox(
                width: 114,
                height: 120,
                child: CustomPaint(
                  painter: _CarGlowPainter(
                    lateralG: lG,
                    longitudinalG: nG,
                    glowColor: glowColor,
                    glowAlpha: glowAlpha,
                    glowOffsetX: glowOffsetX,
                    glowOffsetY: glowOffsetY,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // 합성 G 수치
              Text(
                '${total.toStringAsFixed(2)}G',
                style: GoogleFonts.orbitron(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: glowColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                total > 0.6 ? 'HIGH' : total > 0.3 ? 'MED' : 'LOW',
                style: GoogleFonts.rajdhani(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: glowColor.withValues(alpha: 0.7),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ── 자동차 글로우 CustomPainter ──────────────────────────────
class _CarGlowPainter extends CustomPainter {
  final double lateralG;
  final double longitudinalG;
  final Color glowColor;
  final double glowAlpha;
  final double glowOffsetX;
  final double glowOffsetY;

  const _CarGlowPainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.glowColor,
    required this.glowAlpha,
    required this.glowOffsetX,
    required this.glowOffsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 4; // 약간 아래 중앙

    // ── 방향성 글로우 (차 뒤쪽에 그라디언트 광원) ──
    if (glowAlpha > 0.04) {
      // 글로우 중심 = G force 방향으로 오프셋된 위치
      final glowCx = cx + glowOffsetX;
      final glowCy = cy + glowOffsetY;

      final glowPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            glowColor.withValues(alpha: glowAlpha * 0.7),
            glowColor.withValues(alpha: glowAlpha * 0.3),
            glowColor.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(
          Rect.fromCenter(center: Offset(glowCx, glowCy), width: 90, height: 90),
        );

      canvas.drawOval(
        Rect.fromCenter(center: Offset(glowCx, glowCy), width: 90, height: 90),
        glowPaint,
      );

      // 2차 글로우 (더 크고 흐릿하게)
      final glow2 = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            glowColor.withValues(alpha: glowAlpha * 0.35),
            glowColor.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(center: Offset(glowCx, glowCy), width: 130, height: 130),
        );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(glowCx, glowCy), width: 130, height: 130),
        glow2,
      );
    }

    // ── 자동차 실루엣 ──
    _drawCar(canvas, cx, cy);
  }

  void _drawCar(Canvas canvas, double cx, double cy) {
    // 차체 (top-down)
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: 28,
      height: 52,
    );
    final bodyRRect = RRect.fromRectAndRadius(bodyRect, const Radius.circular(7));

    // 글로우에 반응하는 차체 fill 색상
    final bodyColor = Color.lerp(
      const Color(0xFF2A2A2A),
      glowColor,
      glowAlpha * 0.25,
    )!;

    canvas.drawRRect(
      bodyRRect,
      Paint()..color = bodyColor,
    );
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2 + glowAlpha * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 캐빈 (앞쪽이 위)
    final cabinRect = Rect.fromCenter(
      center: Offset(cx, cy - 4),
      width: 20,
      height: 26,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cabinRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFF1A1A1A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cabinRect, const Radius.circular(5)),
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 앞유리 (상단)
    final windshieldRect = Rect.fromCenter(
      center: Offset(cx, cy - 10),
      width: 16,
      height: 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(windshieldRect, const Radius.circular(2)),
      Paint()..color = Colors.lightBlueAccent.withValues(alpha: 0.18),
    );

    // 바퀴 4개
    const wheelW = 7.0;
    const wheelH = 10.0;
    for (final wPos in [
      Offset(cx - 18, cy - 17), // FL
      Offset(cx + 18, cy - 17), // FR
      Offset(cx - 18, cy + 14), // RL
      Offset(cx + 18, cy + 14), // RR
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: wPos, width: wheelW, height: wheelH),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF333333),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: wPos, width: wheelW, height: wheelH),
          const Radius.circular(2),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    // 헤드라이트 (앞쪽)
    for (final lPos in [Offset(cx - 9, cy - 26), Offset(cx + 9, cy - 26)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: lPos, width: 5, height: 2.5),
          const Radius.circular(1),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    }

    // 테일라이트 (뒤쪽)
    for (final lPos in [Offset(cx - 9, cy + 26), Offset(cx + 9, cy + 26)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: lPos, width: 5, height: 2.5),
          const Radius.circular(1),
        ),
        Paint()..color = AppColors.red.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_CarGlowPainter old) =>
      old.lateralG != lateralG ||
      old.longitudinalG != longitudinalG ||
      old.glowAlpha != glowAlpha;
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

// ── 루트 진행률 바 ────────────────────────────────────────────
// 바텀바 바로 위 3px 슬림 바, 왼→오른쪽으로 채워짐
class _RouteProgressBar extends StatelessWidget {
  final double pct; // 0.0 ~ 1.0
  const _RouteProgressBar({required this.pct});

  Color get _color {
    if (pct > 0.85) return AppColors.red;
    if (pct > 0.5)  return Colors.orange;
    return Colors.lightBlueAccent;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        return SizedBox(
          height: 3,
          child: Stack(
            children: [
              // 배경 트랙
              Container(color: Colors.white.withValues(alpha: 0.08)),
              // 진행 바
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                width: w * pct.clamp(0.0, 1.0),
                color: _color,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 커브 예고 아이콘 ──────────────────────────────────────────
// TBT 배너 없을 때도 항상 표시 — 작은 원형에 방향 아이콘 + 거리 + 강도
class _CurvePreviewIcon extends StatelessWidget {
  final NavStep? step;
  final double distM;
  const _CurvePreviewIcon({required this.step, required this.distM});

  // modifier → 커브 강도 레이블 + 색상
  static ({String label, Color color}) _severity(String? modifier) {
    return switch (modifier) {
      'sharp left' || 'sharp right' => (label: 'SHARP', color: AppColors.red),
      'left' || 'right'             => (label: 'CURVE', color: Colors.orange),
      'slight left' || 'slight right' => (label: 'EASY', color: Colors.lightBlueAccent),
      _                             => (label: '', color: Colors.white38),
    };
  }

  String get _distText {
    if (distM <= 0) return '';
    if (distM >= 1000) return '${(distM / 1000).toStringAsFixed(1)}km';
    return '${distM.toInt()}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = step;
    // depart/arrive/straight는 표시 안함
    if (s == null || s.type == 'depart' || s.type == 'arrive') {
      return const SizedBox.shrink();
    }
    if (s.modifier == null || s.modifier == 'straight') {
      return const SizedBox.shrink();
    }
    final sev = _severity(s.modifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sev.color.withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(color: sev.color.withValues(alpha: 0.2), blurRadius: 10),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, color: sev.color, size: 28),
          if (sev.label.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sev.label,
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: sev.color,
                letterSpacing: 1.5,
              ),
            ),
          ],
          if (_distText.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              _distText,
              style: GoogleFonts.orbitron(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
          ],
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
