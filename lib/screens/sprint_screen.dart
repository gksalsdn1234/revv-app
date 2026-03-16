import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../widgets/hud_bar.dart';
import '../widgets/map_widget.dart';
import '../widgets/sprint_toggle.dart';
import '../widgets/mic_button.dart';
import '../models/revv_route.dart';
import '../models/obd_data.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/run_session_service.dart';
import '../services/obd_service.dart';
import '../services/driving_context_service.dart';
import '../services/directions_service.dart';
import '../services/imu_service.dart';
import '../services/turn_by_turn_service.dart';
import '../models/nav_step.dart';
import 'run_card_screen.dart';
import 'obd_screen.dart';

class SprintScreen extends StatefulWidget {
  final RevvRoute? selectedRoute;
  const SprintScreen({super.key, this.selectedRoute});

  @override
  State<SprintScreen> createState() => _SprintScreenState();
}

class _SprintScreenState extends State<SprintScreen> {
  LocationService? _locationService;
  RunSessionService? _runSessionService;

  List<LatLng>? _navPolyline;        // 현재위치 → 루트시작점 경로
  bool _onRoute = false;             // 루트 시작점 진입 여부
  String? _routeStatusMsg;           // "루트 진입!" 표시용
  TurnByTurnService? _tbtService;    // 턴바이턴
  double _tbtDistM = 0;             // 다음 maneuver까지 거리

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_locationService == null) {
      _locationService = context.read<LocationService>();
      _runSessionService = context.read<RunSessionService>();
      final weather = context.read<WeatherService>();
      final weatherEmoji = weather.weatherEmoji;
      final tempDisplay = weather.tempDisplay;
      final weatherDesc = weather.weatherDesc;
      final selectedRoute = widget.selectedRoute;

      // 빌드 완료 후 startSession 호출 (notifyListeners 충돌 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _runSessionService!.startSession(
          selectedRoute,
          weatherEmoji: weatherEmoji,
          tempDisplay: tempDisplay,
          weatherDesc: weatherDesc,
        );
      });

      _locationService!.addListener(_onLocation);

      // 루트가 있으면 진입 경로 즉시 fetch
      if (selectedRoute != null) {
        _fetchNavRoute();
      }
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
    if (result.steps.isNotEmpty) {
      _tbtService?.stop();
      _tbtService = TurnByTurnService(
        steps: result.steps,
        onUpdate: () { if (mounted) setState(() {}); },
      );
    }
  }

  void _onLocation() {
    final loc = _locationService;
    if (loc == null) return;
    _runSessionService?.recordPosition(loc.lat, loc.lng, loc.speedKmh);

    // 루트 시작점 200m 이내 진입 시 nav 경로 숨기기
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

    // 턴바이턴 위치 업데이트
    if (_tbtService != null) {
      _tbtService!.updateLocation(loc.lat, loc.lng);
      final d = _tbtService!.distanceToNextM(loc.lat, loc.lng);
      if ((d - _tbtDistM).abs() > 5) {
        setState(() => _tbtDistM = d);
      }
    }
  }

  void _endRun() {
    _locationService?.removeListener(_onLocation);
    _tbtService?.stop();
    final session = _runSessionService?.stopSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      _RunCardRoute(RunCardScreen(session: session)),
    );
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onLocation);
    _tbtService?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              const SprintHudBar(),
              if (widget.selectedRoute != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: AppColors.panel,
                  child: Text(
                    '${widget.selectedRoute!.name}  ·  ${widget.selectedRoute!.distanceDisplay}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                    ),
                  ),
                ),
              // OBD 데이터 스트립
              const _OBDStrip(),
              Expanded(
                child: Consumer<DrivingContextService>(
                  builder: (_, ctx, __) => Stack(
                    children: [
                      // 지도 + 모드 테두리
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: ctx.mode != DriveMode.cruise
                                ? ctx.mode.color.withValues(alpha: 0.55)
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: MapWidget(
                          isSprintMode: true,
                          navPolyline: _navPolyline,
                          routePolyline: widget.selectedRoute?.nodes,
                        ),
                      ),
                      // 턴바이턴 안내 배너
                      if (_tbtService != null && _tbtService!.upcomingStep != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _NavBanner(
                            step: _tbtService!.upcomingStep!,
                            distanceM: _tbtDistM,
                            muted: _tbtService!.muted,
                            onToggleMute: _tbtService!.toggleMute,
                          ),
                        ),
                      const Positioned(
                        top: 10,
                        left: 12,
                        child: _LiveStatHUD(),
                      ),
                      // G포스 미니 위젯
                      const Positioned(
                        bottom: 12,
                        right: 12,
                        child: _MiniGForce(),
                      ),
                      // 모드 뱃지 (cruise 아닐 때만)
                      if (ctx.mode != DriveMode.cruise)
                        Positioned(
                          top: 10,
                          right: 12,
                          child: _ModeBadge(mode: ctx.mode),
                        ),
                      // 루트 진입 메시지
                      if (_routeStatusMsg != null)
                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.panel.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.red.withValues(alpha: 0.7)),
                              ),
                              child: Text(
                                '🏁  $_routeStatusMsg',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.red,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // nav 중일 때 안내 메시지 (루트 아직 미진입)
                      if (!_onRoute && _navPolyline != null && widget.selectedRoute != null)
                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.panel.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                '🔵  ${widget.selectedRoute!.name} 으로 이동 중',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.lightBlue,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Consumer<DrivingContextService>(
                builder: (_, ctx, __) => _SprintBottomBar(
                  onEnd: _endRun,
                  modeColor: ctx.mode.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<RunSessionService>();
    final duration = session.currentDuration;
    final distKm = session.currentDistance;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HudStat(
            label: '경과',
            value: _formatDuration(duration),
            icon: Icons.timer_outlined,
          ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.white12,
          ),
          _HudStat(
            label: '거리',
            value: distKm >= 1.0
                ? '${distKm.toStringAsFixed(2)} km'
                : '${(distKm * 1000).toStringAsFixed(0)} m',
            icon: Icons.straighten,
          ),
        ],
      ),
    );
  }
}

class _HudStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HudStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: AppColors.gray),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.rajdhani(fontSize: 9, color: AppColors.gray, letterSpacing: 1),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: GoogleFonts.orbitron(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ],
    );
  }
}

// ── OBD 스트립 ───────────────────────────────────────────────

class _OBDStrip extends StatelessWidget {
  const _OBDStrip();

  @override
  Widget build(BuildContext context) {
    return Consumer<OBDService>(
      builder: (context, obd, _) {
        final state = obd.state;
        final data = obd.data;

        // 연결 안 됨: 작은 연결 버튼만 표시
        if (state == OBDState.disconnected || state == OBDState.error) {
          return GestureDetector(
            onTap: () => OBDScreen.show(context),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.bg,
              child: Row(
                children: [
                  Icon(Icons.bluetooth_searching,
                      size: 13,
                      color: state == OBDState.error
                          ? AppColors.red
                          : Colors.white24),
                  const SizedBox(width: 6),
                  Text(
                    state == OBDState.error
                        ? (obd.errorMsg ?? 'OBD 연결 실패 — 탭해서 재시도')
                        : 'OBD 연결하기 — 탭해서 연결',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      color: state == OBDState.error
                          ? AppColors.red
                          : Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 스캔/연결 중
        if (state == OBDState.scanning || state == OBDState.connecting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.bg,
            child: Row(
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.red),
                ),
                const SizedBox(width: 8),
                Text(
                  state == OBDState.scanning ? 'OBD 기기 탐색 중...' : 'OBD 연결 중...',
                  style: GoogleFonts.rajdhani(
                      fontSize: 11, color: AppColors.gray),
                ),
              ],
            ),
          );
        }

        // 연결됨 — 데이터 표시 (탭 → OBD 전체 화면)
        return GestureDetector(
          onTap: () => OBDScreen.show(context),
          child: Container(
            color: AppColors.bg,
            child: Column(
              children: [
                _OBDRow(data: data),
                Container(height: 1, color: AppColors.red.withValues(alpha: 0.12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OBDRow extends StatelessWidget {
  final OBDData? data;
  const _OBDRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // RPM
          _OBDCell(
            label: 'RPM',
            value: data?.rpmDisplay ?? '—',
            highlight: _rpmColor(data?.rpm),
          ),
          _divider(),
          // 연료
          _OBDCell(
            label: '연료',
            value: data?.fuelDisplay ?? '—',
            highlight: _fuelColor(data?.fuelLevelPct),
          ),
          _divider(),
          // 스로틀
          _OBDCell(
            label: '스로틀',
            value: data?.throttleDisplay ?? '—',
          ),
          _divider(),
          // 냉각수
          _OBDCell(
            label: '냉각수',
            value: data?.coolantDisplay ?? '—',
            highlight: _coolantColor(data?.coolantTempC),
          ),
          const Spacer(),
          // 연결 상태 점
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF00FF88),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.white12,
      );

  Color? _rpmColor(int? rpm) {
    if (rpm == null) return null;
    if (rpm > 5000) return AppColors.red;
    if (rpm > 3500) return Colors.orange;
    return null;
  }

  Color? _fuelColor(double? pct) {
    if (pct == null) return null;
    if (pct < 15) return AppColors.red;
    if (pct < 30) return Colors.orange;
    return null;
  }

  Color? _coolantColor(int? temp) {
    if (temp == null) return null;
    if (temp > 105) return AppColors.red;
    if (temp > 95) return Colors.orange;
    return null;
  }
}

class _OBDCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? highlight;
  const _OBDCell({required this.label, required this.value, this.highlight});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            color: AppColors.gray,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.orbitron(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: highlight ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

// ── 바텀 바 ──────────────────────────────────────────────────

class _SprintBottomBar extends StatelessWidget {
  final VoidCallback onEnd;
  final Color modeColor;
  const _SprintBottomBar({required this.onEnd, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(
          top: BorderSide(color: modeColor.withValues(alpha: 0.55), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          const MicButton(),
          const SizedBox(width: 12),
          Expanded(
            child: RedGlowButton(
              label: '🏁 런 종료',
              filled: true,
              height: 48,
              onTap: onEnd,
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
        color: AppColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: mode.color.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mode.emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(
            mode.label,
            style: GoogleFonts.rajdhani(
              fontSize: 11,
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

// ── 미니 G포스 원형 위젯 ─────────────────────────────────────
class _MiniGForce extends StatelessWidget {
  const _MiniGForce();

  @override
  Widget build(BuildContext context) {
    return Consumer<ImuService>(
      builder: (_, imu, __) {
        final lG = imu.lateralG.clamp(-1.5, 1.5);
        final nG = imu.longitudinalG.clamp(-1.5, 1.5);
        final total = math.sqrt(lG * lG + nG * nG);
        final color = total > 0.8
            ? AppColors.red
            : total > 0.4
                ? Colors.orange
                : Colors.white70;
        return Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.red.withValues(alpha: 0.3), width: 1),
          ),
          child: CustomPaint(
            painter: _MiniGForcePainter(lateralG: lG, longitudinalG: nG),
            child: Center(
              child: Text(
                total.toStringAsFixed(2),
                style: GoogleFonts.orbitron(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniGForcePainter extends CustomPainter {
  final double lateralG;
  final double longitudinalG;
  const _MiniGForcePainter({required this.lateralG, required this.longitudinalG});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = cx - 6;

    // 외곽 원
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    // 십자선
    final cross = Paint()..color = Colors.white10..strokeWidth = 0.8;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), cross);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), cross);

    // G 볼
    const maxG = 1.5;
    final dx = lateralG / maxG * r;
    final dy = -longitudinalG / maxG * r; // 가속 = 위
    final total = math.sqrt(lateralG * lateralG + longitudinalG * longitudinalG);
    final dotColor = total > 0.8
        ? AppColors.red
        : total > 0.4
            ? Colors.orange
            : Colors.white70;
    canvas.drawCircle(Offset(cx + dx, cy + dy), 5, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_MiniGForcePainter old) =>
      old.lateralG != lateralG || old.longitudinalG != longitudinalG;
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: Colors.blue.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          Icon(step.icon, color: Colors.lightBlueAccent, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.koreanInstruction,
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
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
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.lightBlueAccent,
            ),
          ),
          const SizedBox(width: 8),
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
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
                child: child,
              ),
            );
          },
        );
}
