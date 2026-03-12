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
import 'run_card_screen.dart';

class SprintScreen extends StatefulWidget {
  final RevvRoute? selectedRoute;
  const SprintScreen({super.key, this.selectedRoute});

  @override
  State<SprintScreen> createState() => _SprintScreenState();
}

class _SprintScreenState extends State<SprintScreen> {
  LocationService? _locationService;
  RunSessionService? _runSessionService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_locationService == null) {
      _locationService = context.read<LocationService>();
      _runSessionService = context.read<RunSessionService>();
      final weather = context.read<WeatherService>();
      _runSessionService!.startSession(
        widget.selectedRoute,
        weatherEmoji: weather.weatherEmoji,
        tempDisplay: weather.tempDisplay,
        weatherDesc: weather.weatherDesc,
      );
      _locationService!.addListener(_onLocation);
    }
  }

  void _onLocation() {
    final loc = _locationService;
    if (loc == null) return;
    _runSessionService?.recordPosition(loc.lat, loc.lng, loc.speedKmh);
  }

  void _endRun() {
    _locationService?.removeListener(_onLocation);
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
                child: MapWidget(
                  isSprintMode: true,
                  routePolyline: widget.selectedRoute?.nodes,
                ),
              ),
              _SprintBottomBar(onEnd: _endRun),
            ],
          ),
        ),
      ),
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
            onTap: () => obd.connect(),
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

        // 연결됨 — 데이터 표시
        return Container(
          color: AppColors.bg,
          child: Column(
            children: [
              // 상단 행: RPM + 연료
              _OBDRow(data: data),
              // 구분선
              Container(height: 1, color: AppColors.red.withOpacity(0.12)),
            ],
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
  const _SprintBottomBar({required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(
          top: BorderSide(color: AppColors.red.withOpacity(0.4), width: 1.5),
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
