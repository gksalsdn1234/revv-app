import 'dart:async';
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

  // DriveMode — Consumer<DrivingContextService> 대신 State로 관리
  DriveMode _driveMode = DriveMode.cruise;
  DrivingContextService? _drivingCtxService;

  // 루트 진행률 (0.0 ~ 1.0)
  double _routeProgressPct = 0.0;

  @override
  void initState() {
    super.initState();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // value=1.0 → opacity=0.45(max), value=0.0 → opacity=0.0(invisible)
    // FadeTransition은 paint-only(RenderAnimatedOpacity) — layout 미개입
    _flashAnim = Tween<double>(begin: 0.0, end: 0.45).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
    );
  }

  // value를 1.0으로 점프 후 reverse() — forward(from:0)의 isAnimating 타이밍 이슈 회피
  void _triggerGFlash() {
    _flashCtrl.value = 1.0;
    _flashCtrl.reverse();
  }

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
      _drivingCtxService = context.read<DrivingContextService>();
      _drivingCtxService!.addListener(_onDriveMode);
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

  void _onDriveMode() {
    if (!mounted) return;
    final mode = _drivingCtxService?.mode ?? DriveMode.cruise;
    if (mode != _driveMode) setState(() => _driveMode = mode);
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _tbtService?.toggleMute();
    context.read<SettingsService>().setTtsMuted(_isMuted);
  }

  void _onImu() {
    if (!mounted) return;
    final imu = context.read<ImuService>();
    final g = imu.lateralG.abs();

    // 플래시 트리거 (setState 없이 AnimationController만 건드림)
    if (g >= _flashThreshold && _lastFlashG < _flashThreshold) {
      _triggerGFlash();
    }
    _lastFlashG = g;

    // G미터 UI 제거됨 — 플래시만 사용
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
    _drivingCtxService?.removeListener(_onDriveMode);
    _tbtService?.stop();
    _flashCtrl.dispose();
    super.dispose();
  }

  // ── 메인 빌드: 풀스크린 네비게이션 + 오버레이 ──────────────
  // Consumer<DrivingContextService> 완전 제거 — _driveMode 로컬 State 사용
  // (Consumer rebuild이 build/layout 충돌 유발 → !_debugDoingThisLayout 해결)
  Widget _buildSprintBody(BuildContext context) {
    final tbtTop = (_tbtService?.upcomingStep != null) ? 76.0 : 16.0;
    // ⚠ ValueKey 필수:
    // Stack 자식 리스트에 if 조건부 위젯이 있으면 Flutter가 INDEX 기반으로 매칭.
    // 조건 변경 시 인덱스가 밀려서 서로 다른 타입끼리 매칭 → render object 교체
    // → !_debugDoingThisLayout / "no size" / RenderBox not laid out 등 유발.
    // ValueKey로 각 위젯의 정체성을 보장 → 인덱스 무관하게 정확히 매칭.
    return Stack(
      children: [
        // ── 지도 (독립 모드만 — 오버레이 모드는 CruiseScreen 지도 사용) ──
        if (widget.onEnd == null)
          Positioned.fill(
            key: const ValueKey('sprint-map'),
            child: RepaintBoundary(
              child: MapWidget(
                isSprintMode: true,
                navPolyline: _navPolyline,
                routePolyline: widget.selectedRoute?.nodes,
              ),
            ),
          ),

        // ── 드라이브 모드 테두리 글로우 ──
        if (_driveMode != DriveMode.cruise)
          Positioned.fill(
            key: const ValueKey('drive-glow'),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _driveMode.color.withValues(alpha: 0.6),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

        // ── 상단: 턴바이턴 배너 ──
        if (_tbtService != null && _tbtService!.upcomingStep != null)
          Positioned(
            key: const ValueKey('nav-banner'),
            top: 0, left: 0, right: 0,
            child: _NavBanner(
              step: _tbtService!.upcomingStep!,
              distanceM: _tbtDistM,
              muted: _tbtService!.muted,
              onToggleMute: _tbtService!.toggleMute,
            ),
          ),

        // ── 상단 우측: 드라이브 모드 배지 ──
        if (_driveMode != DriveMode.cruise)
          Positioned(
            key: const ValueKey('mode-badge'),
            top: tbtTop,
            right: 14,
            child: _ModeBadge(mode: _driveMode),
          ),

        // ── 상단 좌측: 경과/거리 pill ──
        Positioned(
          key: const ValueKey('live-stat'),
          top: tbtTop,
          left: 14,
          child: const _LiveStatHUD(),
        ),

        // ── 루트 이동 중 안내 ──
        if (!_onRoute && _navPolyline != null && widget.selectedRoute != null)
          Positioned(
            key: const ValueKey('nav-status'),
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
            key: const ValueKey('route-msg'),
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
          Positioned(
            key: const ValueKey('off-route'),
            top: 0, left: 0, right: 0,
            child: const _OffRouteBanner(),
          ),

        // ── 하단 좌측: 커브 예고 아이콘 ──
        if (_tbtService != null)
          Positioned(
            key: const ValueKey('curve-icon'),
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
            key: const ValueKey('route-progress'),
            bottom: 68,
            left: 0,
            right: 0,
            child: _RouteProgressBar(pct: _routeProgressPct),
          ),

        // ── 하단 바: 음소거 + 마이크 + 런 종료 ──
        Positioned(
          key: const ValueKey('bottom-bar'),
          bottom: 0, left: 0, right: 0,
          child: _SprintBottomBar(
            onEnd: _endRun,
            modeColor: _driveMode.color,
            muted: _isMuted,
            onToggleMute: _toggleMute,
          ),
        ),
      ],
    );
  }

  // G-Force 레드 플래시 오버레이
  Widget _buildFlashOverlay() {
    // ⚠️ Flutter issue #120874 fix (final):
    // AnimatedBuilder + Container → FadeTransition + DecoratedBox 로 교체
    //
    // FadeTransition → RenderAnimatedOpacity: paint-only, layout 미개입
    // → !_debugDoingThisLayout assertion 원천 차단
    //
    // _flashCtrl.value=1.0 → reverse() 방식:
    //   forward(from:0) 는 value setter가 동기적으로 notifyListeners()를 호출하는 시점에
    //   isAnimating=false 상태 → AnimatedBuilder가 opacity=0으로 빌드 (타이밍 버그)
    //   reverse()는 이미 value=1.0인 상태에서 시작 → 첫 프레임부터 opacity=0.45 보장
    return Positioned.fill(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _flashAnim,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x8AE53935), // red ~54% (0.45 * 1.2 ≈ 0.54)
                  Color(0x22E53935), // red ~13% (0.45 * 0.3 ≈ 0.135)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand() 필수:
    // 오버레이 모드에서 CruiseScreen Stack이 StackFit.loose(기본값) 이므로
    // non-Positioned 자식인 SprintScreen에 loose constraints가 전달됨.
    // body Stack의 자식이 전부 Positioned → loose 환경에서 Stack 크기 = 0×0
    // → Positioned.fill이 0×0을 채우려 하면 RenderDecoratedBox layout 실패.
    // SizedBox.expand()는 loose constraints에서도 강제로 최대 크기(fullscreen)를 사용.
    final body = SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(child: _buildSprintBody(context)),
          _buildFlashOverlay(), // Positioned.fill 반환
        ],
      ),
    );

    if (widget.onEnd != null) {
      // ⚠ Material(color: transparent) 제거:
      // _RenderInkFeatures.hitTestSelf()=true → 투명해도 모든 터치 흡수
      // → 아래 CruiseScreen MapWidget 터치 불가 + hit test "no size" 에러 유발.
      // RedGlowButton은 자체 로컬 Material 사용 → 상위 Material 불필요.
      return PopScope(
        canPop: false,
        child: body,
      );
    }
    return PopScope(
      canPop: false,
      child: Scaffold(backgroundColor: AppColors.bg, body: body),
    );
  }
}

// ── 라이브 스탯 HUD ──────────────────────────────────────────
// ⚠️ Timer.periodic + setState() 패턴 제거:
//    매초 setState()가 호출되면 Flutter layout 단계와 충돌 →
//    !_debugDoingThisLayout assertion 유발 가능.
//    → StatelessWidget + context.watch<RunSessionService>() 로 교체.
//    RunSessionService.recordPosition()이 GPS 업데이트마다 notifyListeners()
//    (addPostFrameCallback 경유, 프레임 간 안전) → 화면 자동 갱신.
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
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
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
    // ⚠ AnimatedContainer 제거:
    // implicit animation이 layout 단계에서 크기를 변경하면
    // 부모 Stack의 Positioned relayout과 충돌 → !_debugDoingThisLayout.
    // 색상 변경은 즉시 적용 (시각적 차이 거의 없음).
    return Container(
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
// ⚠️ LayoutBuilder + AnimatedContainer 조합이 Flutter 3.x에서
//    rapid rebuild 시 !_debugDoingThisLayout assertion을 유발할 수 있음.
//    → CustomPainter로 교체: layout 단계 없이 paint 단계에서만 그림.
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
    return SizedBox(
      height: 3,
      width: double.infinity,
      child: CustomPaint(
        painter: _ProgressBarPainter(
          pct: pct.clamp(0.0, 1.0),
          color: _color,
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double pct;
  final Color color;
  const _ProgressBarPainter({required this.pct, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // 배경 트랙
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    // 진행 바
    if (pct > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * pct, size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.pct != pct || old.color != color;
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
    // ⚠ SizedBox.shrink() ↔ Container 타입 스위칭 제거 (→ hit test "no size" 방지)
    // 항상 IgnorePointer(child: Container) 반환.
    // 표시 안할 때: ignoring=true + opacity=0 → 보이지 않고 터치 무시.
    // IgnorePointer.ignoring=true → RenderIgnorePointer.hitTest()가 super 호출 없이
    // 즉시 false 반환 → 내부 render object의 size 검사 없음.
    final bool show = s != null &&
        s.type != 'depart' &&
        s.type != 'arrive' &&
        s.modifier != null &&
        s.modifier != 'straight';

    final sev = show ? _severity(s!.modifier) : (label: '', color: Colors.transparent);

    return IgnorePointer(
      ignoring: !show,
      child: Opacity(
        opacity: show ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sev.color.withValues(alpha: 0.5), width: 1),
            boxShadow: [
              BoxShadow(color: sev.color.withValues(alpha: 0.2), blurRadius: 10),
            ],
          ),
          child: show
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s!.icon, color: sev.color, size: 28),
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
                )
              : const SizedBox.shrink(),
        ),
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
