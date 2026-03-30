import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../models/run_session.dart';
import '../services/driving_context_service.dart';
import '../services/imu_service.dart';
import '../services/location_service.dart';
import '../models/obd_data.dart';
import '../services/obd_service.dart';
import '../services/run_session_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../theme/colors.dart';
import 'run_card_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// DriveScreen — 미니멀 HUD 모드 (루트 시작점 근거리 진입 시)
// SprintScreen처럼 세션 lifecycle 동일, 단 TBT/맵 없음
// ──────────────────────────────────────────────────────────────────────────────

class DriveScreen extends StatefulWidget {
  final RevvRoute? selectedRoute;
  final void Function(RunSession?)? onEnd;

  const DriveScreen({super.key, this.selectedRoute, this.onEnd});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen>
    with TickerProviderStateMixin {
  // ── Services ──
  LocationService? _locationService;
  RunSessionService? _runSessionService;
  DrivingContextService? _drivingCtxService;

  // ── State ──
  double _speedKmh = 0;
  double _currentG = 0;
  double _lateralG = 0;
  double _longitudinalG = 0;
  DriveMode _driveMode = DriveMode.cruise;
  double _routeProgressPct = 0;
  bool _sessionStarted = false;
  DateTime? _startTime;
  Timer? _clockTimer;
  Duration _elapsed = Duration.zero;

  // ── Animation controllers ──
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _entryCtrl.forward();

    _startTime = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed = DateTime.now().difference(_startTime!));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sessionStarted) return;
    _sessionStarted = true;

    _locationService = context.read<LocationService>();
    _runSessionService = context.read<RunSessionService>();
    _drivingCtxService = context.read<DrivingContextService>();

    _locationService!.addListener(_onLocation);
    _drivingCtxService!.addListener(_onDriveMode);
    context.read<ImuService>().addListener(_onImu);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final weather = context.read<WeatherService>();
      _runSessionService!.startSession(
        widget.selectedRoute,
        weatherEmoji: weather.weatherEmoji,
        tempDisplay: weather.tempDisplay,
        weatherDesc: weather.weatherDesc,
      );
      try {
        if (context.read<OBDService>().isConnected) {
          context.read<OBDService>().startRunTracking();
        }
      } catch (_) {}
    });
  }

  void _onLocation() {
    if (!mounted) return;
    final loc = _locationService!;
    final spd = loc.speedKmh.clamp(0.0, 999.0);
    if ((spd - _speedKmh).abs() > 0.5) {
      setState(() => _speedKmh = spd);
    }
    _runSessionService?.recordPosition(loc.lat, loc.lng, spd);
    _runSessionService?.recordDriveMode(_driveMode.name);

    // Route progress tracking
    if (widget.selectedRoute != null) {
      final pos = LatLng(loc.lat, loc.lng);
      final nodes = widget.selectedRoute!.nodes;
      double minDist = double.infinity;
      int closestIdx = 0;
      for (int i = 0; i < nodes.length; i++) {
        final d = RevvRoute.haversineKm(pos, nodes[i]);
        if (d < minDist) {
          minDist = d;
          closestIdx = i;
        }
        if (minDist < 0.05) break;
      }
      final newPct =
          nodes.length > 1 ? closestIdx / (nodes.length - 1) : 0.0;
      if ((newPct - _routeProgressPct).abs() > 0.005) {
        setState(() => _routeProgressPct = newPct);
      }
    }
  }

  void _onDriveMode() {
    if (!mounted) return;
    final mode = _drivingCtxService?.mode ?? DriveMode.cruise;
    if (mode != _driveMode) setState(() => _driveMode = mode);
  }

  void _onImu() {
    if (!mounted) return;
    final imu = context.read<ImuService>();
    final lat = imu.lateralG;
    final lon = imu.longitudinalG;
    final total = math.sqrt(lat * lat + lon * lon);
    if ((total - _currentG).abs() > 0.02 ||
        (lat - _lateralG).abs() > 0.02 ||
        (lon - _longitudinalG).abs() > 0.02) {
      setState(() {
        _currentG = total;
        _lateralG = lat;
        _longitudinalG = lon;
      });
    }
  }

  void _endRun() {
    _locationService?.removeListener(_onLocation);
    _drivingCtxService?.removeListener(_onDriveMode);
    try {
      context.read<ImuService>().removeListener(_onImu);
    } catch (_) {}

    final imu = context.read<ImuService>();
    OBDRunSummary? obdSummary;
    try {
      obdSummary = context.read<OBDService>().stopRunTracking();
    } catch (_) {}

    final session = _runSessionService?.stopSession(
      maxLateralG: imu.maxLateralG,
      maxLonG: imu.maxLonG,
      obdSummary: obdSummary,
    );
    imu.resetMaxG();

    if (!mounted) return;
    if (widget.onEnd != null) {
      widget.onEnd!(session);
      return;
    }
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => RunCardScreen(session: session),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _entryCtrl.dispose();
    _locationService?.removeListener(_onLocation);
    _drivingCtxService?.removeListener(_onDriveMode);
    try {
      context.read<ImuService>().removeListener(_onImu);
    } catch (_) {}
    super.dispose();
  }

  // ── Helpers ──
  String get _elapsedDisplay {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${_elapsed.inHours > 0 ? '${_elapsed.inHours}:' : ''}$m:$s';
  }

  String _driveModeLabel(DriveMode mode) {
    switch (mode) {
      case DriveMode.sport:
        return 'SPORT';
      case DriveMode.winding:
        return 'WINDING';
      default:
        return 'CRUISE';
    }
  }

  Color _driveModeColor(DriveMode mode) {
    switch (mode) {
      case DriveMode.sport:
        return AppColors.red;
      case DriveMode.winding:
        return AppColors.orange;
      default:
        return AppColors.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imu = context.watch<ImuService>();
    final obd = context.watch<OBDService>();
    final settings = context.watch<SettingsService>();
    final useImperial = settings.distUnit == 'imperial';

    final displaySpeed = useImperial ? (_speedKmh * 0.621371) : _speedKmh;
    final speedUnit = useImperial ? 'MPH' : 'KM/H';

    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: Container(
          color: AppColors.bg,
          child: SafeArea(
            child: Column(
              children: [
                // ── Top bar ──────────────────────────────────────────
                _TopBar(
                  elapsed: _elapsedDisplay,
                  driveMode: _driveMode,
                  modeLabel: _driveModeLabel(_driveMode),
                  modeColor: _driveModeColor(_driveMode),
                  routeName: widget.selectedRoute?.name,
                ),
                // ── Route progress ───────────────────────────────────
                if (widget.selectedRoute != null)
                  _RouteProgressBar(progress: _routeProgressPct),
                const SizedBox(height: 8),
                // ── Speed ────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        _SpeedDisplay(speed: displaySpeed, unit: speedUnit),
                        const SizedBox(height: 32),
                        // ── G-force circle + readouts ─────────────────
                        _GForceSection(
                          lateralG: _lateralG,
                          longitudinalG: _longitudinalG,
                          currentG: _currentG,
                          maxLateralG: imu.maxLateralG,
                          maxLonG: imu.maxLonG,
                        ),
                        const SizedBox(height: 24),
                        // ── OBD adaptive section ──────────────────────
                        AnimatedSize(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          child: obd.isConnected && obd.data != null
                              ? _OBDSection(data: obd.data!)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── END button ───────────────────────────────────────
                _EndButton(onTap: _endRun),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String elapsed;
  final DriveMode driveMode;
  final String modeLabel;
  final Color modeColor;
  final String? routeName;

  const _TopBar({
    required this.elapsed,
    required this.driveMode,
    required this.modeLabel,
    required this.modeColor,
    this.routeName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Elapsed time
          Text(
            elapsed,
            style: GoogleFonts.orbitron(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          // Route name (truncated)
          if (routeName != null) ...[
            Flexible(
              child: Text(
                routeName!,
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHint,
                  letterSpacing: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
          ],
          // DriveMode badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: modeColor.withValues(alpha: 0.4)),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: GoogleFonts.orbitron(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: modeColor,
                letterSpacing: 1.5,
              ),
              child: Text(modeLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteProgressBar extends StatelessWidget {
  final double progress;
  const _RouteProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(height: 3, color: AppColors.surface),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.red, AppColors.orange],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(progress * 100).toStringAsFixed(0)}% COMPLETE',
            style: GoogleFonts.rajdhani(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textHint,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedDisplay extends StatelessWidget {
  final double speed;
  final String unit;
  const _SpeedDisplay({required this.speed, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          speed.toStringAsFixed(0),
          style: GoogleFonts.orbitron(
            fontSize: 96,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          unit,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textHint,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}

// ── G-Force circle + readouts ─────────────────────────────────────────────────

class _GForceSection extends StatelessWidget {
  final double lateralG;
  final double longitudinalG;
  final double currentG;
  final double maxLateralG;
  final double maxLonG;

  const _GForceSection({
    required this.lateralG,
    required this.longitudinalG,
    required this.currentG,
    required this.maxLateralG,
    required this.maxLonG,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Circle
        SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(
            painter: _GForcePainter(
              lateralG: lateralG,
              longitudinalG: longitudinalG,
              totalG: currentG,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Readouts row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GReadout(
              label: 'LAT',
              value: lateralG.abs().toStringAsFixed(2),
              maxValue: maxLateralG.toStringAsFixed(2),
              color: AppColors.orange,
            ),
            Container(
              width: 1,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              color: AppColors.divider,
            ),
            _GReadout(
              label: 'LON',
              value: longitudinalG.abs().toStringAsFixed(2),
              maxValue: maxLonG.toStringAsFixed(2),
              color: AppColors.cyan,
            ),
          ],
        ),
      ],
    );
  }
}

class _GReadout extends StatelessWidget {
  final String label;
  final String value;
  final String maxValue;
  final Color color;

  const _GReadout({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textHint,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.orbitron(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'MAX $maxValue',
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textHint,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ── G-Force CustomPainter ─────────────────────────────────────────────────────

class _GForcePainter extends CustomPainter {
  final double lateralG;
  final double longitudinalG;
  final double totalG;

  const _GForcePainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.totalG,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 8;
    final maxG = 1.2;

    // ── Background rings ──
    final bgPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final frac in [0.33, 0.67, 1.0]) {
      canvas.drawCircle(Offset(cx, cy), r * frac, bgPaint);
    }

    // ── Crosshairs ──
    final crossPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), crossPaint);

    // ── Glow dot ──
    final clampedX = (lateralG / maxG).clamp(-1.0, 1.0);
    final clampedY = (longitudinalG / maxG).clamp(-1.0, 1.0);
    final dotX = cx + clampedX * r;
    final dotY = cy - clampedY * r; // Y inverted: accel forward = up

    final intensity = (totalG / maxG).clamp(0.0, 1.0);
    final dotColor = Color.lerp(AppColors.cyan, AppColors.red, intensity)!;
    final dotRadius = 7.0 + intensity * 4;

    // Glow
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotRadius + 6,
      Paint()
        ..color = dotColor.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Dot
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotRadius,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(_GForcePainter old) =>
      old.lateralG != lateralG ||
      old.longitudinalG != longitudinalG ||
      old.totalG != totalG;
}

// ── OBD Section ───────────────────────────────────────────────────────────────

class _OBDSection extends StatelessWidget {
  final OBDData data;
  const _OBDSection({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _OBDStat(
            label: 'RPM',
            value: data.rpm != null ? '${data.rpm}' : '—',
            color: AppColors.red,
          ),
          _OBDStat(
            label: 'THROTTLE',
            value: data.throttlePct != null
                ? '${data.throttlePct!.toStringAsFixed(0)}%'
                : '—',
            color: AppColors.orange,
          ),
          _OBDStat(
            label: 'COOLANT',
            value: data.coolantTempC != null ? '${data.coolantTempC}°C' : '—',
            color: AppColors.cyan,
          ),
        ],
      ),
    );
  }
}

class _OBDStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _OBDStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.orbitron(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textHint,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

// ── END button ────────────────────────────────────────────────────────────────

class _EndButton extends StatefulWidget {
  final VoidCallback onTap;
  const _EndButton({required this.onTap});

  @override
  State<_EndButton> createState() => _EndButtonState();
}

class _EndButtonState extends State<_EndButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.red.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Center(
            child: Text(
              'END DRIVE',
              style: GoogleFonts.orbitron(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.red,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
