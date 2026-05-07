import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../services/imu_service.dart';
import '../services/location_service.dart';
import '../services/run_session_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/route_drive_cue.dart';
import '../widgets/map_widget.dart';
import 'lean_run_summary_screen.dart';

class LeanDriveScreen extends StatefulWidget {
  final RevvRoute route;

  const LeanDriveScreen({super.key, required this.route});

  @override
  State<LeanDriveScreen> createState() => _LeanDriveScreenState();
}

class _LeanDriveScreenState extends State<LeanDriveScreen> {
  LocationService? _location;
  RunSessionService? _session;
  bool _started = false;
  DateTime? _startedAt;
  Timer? _clock;
  Duration _elapsed = Duration.zero;
  double _speedKmh = 0;
  double _lateralG = 0;
  double _longitudinalG = 0;
  double _progress = 0;
  double _remainingKm = 0;
  DriveCurveCue? _cue;
  DriveRouteStatus _routeStatus = DriveRouteStatus.approachingStart;
  String? _routeEventMessage;
  DateTime? _routeEventUntil;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _location = context.read<LocationService>();
    _session = context.read<RunSessionService>();
    _location!.addListener(_onLocation);
    context.read<ImuService>().addListener(_onImu);
    _startDrive();
  }

  Future<void> _startDrive() async {
    await _location?.requestPermission();
    await _location?.startTracking();
    _startedAt = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
    _session?.startSession(widget.route);
    _onLocation();
  }

  void _onLocation() {
    final loc = _location;
    if (!mounted || loc == null) return;
    final position = loc.bestKnownLatLng;
    final speed = loc.speedKmh.clamp(0.0, 260.0);
    if (position != null) {
      _session?.recordPosition(
        position.lat,
        position.lng,
        speed,
        lateralG: _lateralG,
        longitudinalG: _longitudinalG,
        driveMode: 'cruise',
      );
      _session?.recordSharpCorner(position.lat, position.lng, _lateralG);
      final routeState = readDriveRouteState(position, widget.route.nodes);
      final nextEvent = _routeEventFor(_routeStatus, routeState.status);
      setState(() {
        _speedKmh = speed;
        _progress = routeState.progress;
        _remainingKm = routeState.remainingKm;
        _cue = routeState.cue;
        _routeStatus = routeState.status;
        if (nextEvent != null) {
          _routeEventMessage = nextEvent;
          _routeEventUntil = DateTime.now().add(const Duration(seconds: 4));
        } else if (_routeEventUntil?.isBefore(DateTime.now()) ?? false) {
          _routeEventMessage = null;
          _routeEventUntil = null;
        }
      });
      return;
    }
    setState(() => _speedKmh = speed);
  }

  void _onImu() {
    if (!mounted) return;
    final imu = context.read<ImuService>();
    final nextLat = imu.lateralG;
    final nextLon = imu.longitudinalG;
    if ((nextLat - _lateralG).abs() < 0.02 &&
        (nextLon - _longitudinalG).abs() < 0.02) {
      return;
    }
    setState(() {
      _lateralG = nextLat;
      _longitudinalG = nextLon;
    });
  }

  void _endDrive() {
    _location?.removeListener(_onLocation);
    try {
      context.read<ImuService>().removeListener(_onImu);
    } catch (_) {}
    final imu = context.read<ImuService>();
    final run = _session?.stopSession(
      maxLateralG: imu.maxLateralG,
      maxLonG: imu.maxLonG,
    );
    imu.resetMaxG();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LeanRunSummaryScreen(session: run)),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _location?.removeListener(_onLocation);
    try {
      context.read<ImuService>().removeListener(_onImu);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imu = context.watch<ImuService>();
    final cue = _cue;
    final routeEvent = _routeEventUntil?.isAfter(DateTime.now()) == true
        ? _routeEventMessage
        : null;
    final remainingKm = _remainingKm > 0
        ? _remainingKm
        : widget.route.distanceKm;
    final settings = context.watch<SettingsService>();
    final totalG = math.sqrt(
      _lateralG * _lateralG + _longitudinalG * _longitudinalG,
    );
    final peakG = math.max(imu.maxLateralG, imu.maxLonG);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              isSprintMode: true,
              routePolyline: widget.route.nodes,
              routeFocusMode: true,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  _DriveTopBar(
                    routeName: widget.route.name,
                    progress: _progress,
                  ),
                  const SizedBox(height: 10),
                  _NextCurveBanner(
                    cue: cue,
                    status: _routeStatus,
                    eventMessage: routeEvent,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _CompactSpeedPill(speedKmh: _speedKmh),
                      const SizedBox(width: 8),
                      _CompactGInstrument(
                        lateralG: _lateralG,
                        longitudinalG: _longitudinalG,
                        totalG: totalG,
                        peakG: peakG,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _DriveControlStrip(
                    remainingKm: remainingKm,
                    elapsed: _formatDuration(_elapsed),
                    muted: settings.ttsMuted,
                    onToggleMute: () =>
                        settings.setTtsMuted(!settings.ttsMuted),
                    onEnd: _endDrive,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _routeEventFor(DriveRouteStatus previous, DriveRouteStatus next) {
  if (previous == next) return null;
  if (previous == DriveRouteStatus.offRoute &&
      next == DriveRouteStatus.onRoute) {
    return '다시 루트 진입';
  }
  if (next == DriveRouteStatus.offRoute) return '루트에서 벗어남';
  if (next == DriveRouteStatus.approachingStart) return '시작점으로 이동 중';
  if (next == DriveRouteStatus.completed) return '루트 완료 지점';
  return null;
}

class _DriveTopBar extends StatelessWidget {
  final String routeName;
  final double progress;

  const _DriveTopBar({required this.routeName, required this.progress});

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  routeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 16,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                style: AppText.technicalLabel(
                  size: 12,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.surface,
              color: AppColors.primaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextCurveBanner extends StatelessWidget {
  final DriveCurveCue? cue;
  final DriveRouteStatus status;
  final String? eventMessage;

  const _NextCurveBanner({
    required this.cue,
    required this.status,
    required this.eventMessage,
  });

  @override
  Widget build(BuildContext context) {
    final data = cue;
    final severityColor = _severityColor(data?.severity ?? 0);
    final fallback = _fallbackCue(status);
    return _DriveGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eventMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: severityColor.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                eventMessage!,
                style: AppText.technicalLabel(size: 10, color: severityColor),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: severityColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  data?.icon ?? fallback.icon,
                  color: severityColor,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  data?.label ?? fallback.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 25,
                    height: 1.02,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                data == null
                    ? fallback.distance
                    : _formatMeters(data.distanceM),
                style: AppText.display(
                  size: data == null ? 28 : 34,
                  height: 0.96,
                  color: severityColor,
                  letterSpacing: -1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.route_rounded, color: AppColors.textHint, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  data?.detail ?? fallback.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FallbackCue {
  final String label;
  final String detail;
  final IconData icon;
  final String distance;

  const _FallbackCue({
    required this.label,
    required this.detail,
    required this.icon,
    required this.distance,
  });
}

_FallbackCue _fallbackCue(DriveRouteStatus status) {
  switch (status) {
    case DriveRouteStatus.approachingStart:
      return const _FallbackCue(
        label: '시작점으로 이동',
        detail: '루트 시작점 근처에서 커브 안내를 시작합니다.',
        icon: Icons.flag_rounded,
        distance: 'START',
      );
    case DriveRouteStatus.offRoute:
      return const _FallbackCue(
        label: '복귀 대기',
        detail: '지도 라인 가까이 이동하면 안내를 이어갑니다.',
        icon: Icons.near_me_disabled_rounded,
        distance: 'REJOIN',
      );
    case DriveRouteStatus.completed:
      return const _FallbackCue(
        label: '루트 완료',
        detail: '주행 종료 후 기록을 저장할 수 있어요.',
        icon: Icons.done_rounded,
        distance: 'DONE',
      );
    case DriveRouteStatus.onRoute:
      return const _FallbackCue(
        label: '흐름 구간',
        detail: '30-800m 안에 큰 기준 커브가 없어요. 루트 흐름을 유지합니다.',
        icon: Icons.timeline_rounded,
        distance: 'CLEAR',
      );
  }
}

class _CompactSpeedPill extends StatelessWidget {
  final double speedKmh;

  const _CompactSpeedPill({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPEED',
            style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                speedKmh.toStringAsFixed(0),
                style: AppText.display(
                  size: 30,
                  height: 0.9,
                  color: AppColors.primaryContainer,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'km/h',
                  style: AppText.body(
                    size: 10,
                    weight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactGInstrument extends StatelessWidget {
  final double lateralG;
  final double longitudinalG;
  final double totalG;
  final double peakG;

  const _CompactGInstrument({
    required this.lateralG,
    required this.longitudinalG,
    required this.totalG,
    required this.peakG,
  });

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      width: 158,
      child: Row(
        children: [
          _GDot(lateralG: lateralG, longitudinalG: longitudinalG),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'G METER',
                  style: AppText.technicalLabel(
                    size: 9,
                    color: AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalG.toStringAsFixed(2),
                  style: AppText.display(
                    size: 28,
                    height: 0.9,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'PK ${peakG.toStringAsFixed(2)}',
                  style: AppText.technicalLabel(
                    size: 9,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GDot extends StatelessWidget {
  final double lateralG;
  final double longitudinalG;

  const _GDot({required this.lateralG, required this.longitudinalG});

  @override
  Widget build(BuildContext context) {
    final dx = lateralG.clamp(-0.8, 0.8) / 0.8;
    final dy = -longitudinalG.clamp(-0.8, 0.8) / 0.8;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface.withValues(alpha: 0.74),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.46),
              ),
            ),
            child: const SizedBox.expand(),
          ),
          Center(
            child: Container(
              width: 1,
              height: 34,
              color: AppColors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          Center(
            child: Container(
              width: 34,
              height: 1,
              color: AppColors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          Align(
            alignment: Alignment(dx, dy),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryContainer,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryContainer.withValues(alpha: 0.44),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveControlStrip extends StatelessWidget {
  final double remainingKm;
  final String elapsed;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onEnd;

  const _DriveControlStrip({
    required this.remainingKm,
    required this.elapsed,
    required this.muted,
    required this.onToggleMute,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      child: Row(
        children: [
          _StripMetric(label: '남은 거리', value: _formatKm(remainingKm)),
          const SizedBox(width: 14),
          _StripMetric(label: '경과', value: elapsed),
          const Spacer(),
          IconButton(
            onPressed: onToggleMute,
            icon: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: muted ? AppColors.textHint : AppColors.primaryContainer,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surface.withValues(alpha: 0.74),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              onPressed: onEnd,
              icon: const Icon(Icons.stop_rounded, size: 20),
              label: Text(
                '종료',
                style: AppText.body(
                  size: 15,
                  weight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StripMetric extends StatelessWidget {
  final String label;
  final String value;

  const _StripMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppText.body(
            size: 15,
            weight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DriveGlass extends StatelessWidget {
  final Widget child;
  final double? width;

  const _DriveGlass({required this.child, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

Color _severityColor(int severity) {
  if (severity >= 3) return AppColors.danger;
  if (severity >= 2) return AppColors.warning;
  return AppColors.primaryContainer;
}

String _formatMeters(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)}km';
  return '${meters.round()}m';
}

String _formatKm(double km) {
  if (km >= 10) return '${km.toStringAsFixed(0)}km';
  if (km >= 1) return '${km.toStringAsFixed(1)}km';
  return '${(km * 1000).round()}m';
}

String _formatDuration(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
