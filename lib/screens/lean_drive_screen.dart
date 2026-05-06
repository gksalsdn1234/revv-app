import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../services/imu_service.dart';
import '../services/location_service.dart';
import '../services/run_session_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
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
  _CurveCue? _cue;

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
      final routeState = _readRouteState(position, widget.route.nodes);
      setState(() {
        _speedKmh = speed;
        _progress = routeState.progress;
        _cue = routeState.cue;
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
    final totalG = math.sqrt(
      _lateralG * _lateralG + _longitudinalG * _longitudinalG,
    );

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
                    elapsed: _formatDuration(_elapsed),
                    progress: _progress,
                  ),
                  const Spacer(),
                  _CurveCard(cue: cue),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SpeedCard(speedKmh: _speedKmh),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GCard(
                          lateralG: _lateralG,
                          longitudinalG: _longitudinalG,
                          totalG: totalG,
                          peakG: math.max(imu.maxLateralG, imu.maxLonG),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      onPressed: _endDrive,
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(
                        '주행 종료',
                        style: AppText.body(
                          size: 17,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
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

class _DriveTopBar extends StatelessWidget {
  final String routeName;
  final String elapsed;
  final double progress;

  const _DriveTopBar({
    required this.routeName,
    required this.elapsed,
    required this.progress,
  });

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
                elapsed,
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

class _CurveCard extends StatelessWidget {
  final _CurveCue? cue;

  const _CurveCard({required this.cue});

  @override
  Widget build(BuildContext context) {
    final data = cue;
    return _DriveGlass(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              data?.icon ?? Icons.timeline_rounded,
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data?.label ?? '흐름 구간',
                  style: AppText.body(
                    size: 18,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data?.detail ?? '당분간 큰 커브 없이 루트 흐름을 유지합니다.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  final double speedKmh;

  const _SpeedCard({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPEED',
            style: AppText.technicalLabel(size: 10, color: AppColors.textHint),
          ),
          const SizedBox(height: 4),
          Text(
            speedKmh.toStringAsFixed(0),
            style: AppText.display(
              size: 48,
              height: 0.92,
              color: AppColors.primaryContainer,
            ),
          ),
          Text(
            'km/h',
            style: AppText.body(
              size: 12,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GCard extends StatelessWidget {
  final double lateralG;
  final double longitudinalG;
  final double totalG;
  final double peakG;

  const _GCard({
    required this.lateralG,
    required this.longitudinalG,
    required this.totalG,
    required this.peakG,
  });

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'G METER',
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.textHint,
                ),
              ),
              const Spacer(),
              Text(
                'PK ${peakG.toStringAsFixed(2)}',
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                totalG.toStringAsFixed(2),
                style: AppText.display(
                  size: 34,
                  height: 0.94,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'LAT ${lateralG.toStringAsFixed(2)}\nLON ${longitudinalG.toStringAsFixed(2)}',
                  style: AppText.body(
                    size: 10,
                    height: 1.45,
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

class _RouteState {
  final double progress;
  final _CurveCue? cue;

  const _RouteState({required this.progress, required this.cue});
}

class _CurveCue {
  final String label;
  final String detail;
  final IconData icon;

  const _CurveCue({
    required this.label,
    required this.detail,
    required this.icon,
  });
}

_RouteState _readRouteState(LatLng position, List<LatLng> nodes) {
  if (nodes.length < 3) return const _RouteState(progress: 0, cue: null);

  double closestDistance = double.infinity;
  int closest = 0;
  for (int i = 0; i < nodes.length; i++) {
    final distance = RevvRoute.haversineKm(position, nodes[i]);
    if (distance < closestDistance) {
      closestDistance = distance;
      closest = i;
    }
  }

  final progress = nodes.length > 1 ? closest / (nodes.length - 1) : 0.0;
  double distanceM = closestDistance * 1000;

  for (int i = math.max(1, closest + 1); i < nodes.length - 1; i++) {
    if (i > closest + 90) {
      break;
    }
    if (i > closest + 1) {
      distanceM += RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
    }
    final turn = _turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]);
    final absTurn = turn.abs();
    if (absTurn < 18) {
      continue;
    }

    final direction = turn >= 0 ? '우측' : '좌측';
    final intensity = absTurn >= 68
        ? '헤어핀'
        : absTurn >= 42
        ? '급커브'
        : absTurn >= 26
        ? '중간 커브'
        : '완만한 커브';
    final icon = turn >= 0
        ? Icons.turn_slight_right_rounded
        : Icons.turn_slight_left_rounded;
    final nextGap = _nextCurveGapM(nodes, i);
    final detail = nextGap == null
        ? '약 ${distanceM.round()}m 앞'
        : '약 ${distanceM.round()}m 앞 · 다음 커브 ${nextGap.round()}m';
    return _RouteState(
      progress: progress,
      cue: _CurveCue(
        label: '$direction $intensity',
        detail: detail,
        icon: icon,
      ),
    );
  }

  return _RouteState(progress: progress, cue: null);
}

double? _nextCurveGapM(List<LatLng> nodes, int fromIndex) {
  double distanceM = 0;
  for (int i = fromIndex + 1; i < nodes.length - 1; i++) {
    distanceM += RevvRoute.haversineKm(nodes[i - 1], nodes[i]) * 1000;
    if (_turnDegrees(nodes[i - 1], nodes[i], nodes[i + 1]).abs() >= 18) {
      return distanceM;
    }
    if (distanceM > 900) {
      return null;
    }
  }
  return null;
}

double _turnDegrees(LatLng a, LatLng b, LatLng c) {
  final inBearing = _bearingDegrees(a, b);
  final outBearing = _bearingDegrees(b, c);
  var delta = outBearing - inBearing;
  while (delta > 180) {
    delta -= 360;
  }
  while (delta < -180) {
    delta += 360;
  }
  return delta;
}

double _bearingDegrees(LatLng from, LatLng to) {
  final lat1 = from.lat * math.pi / 180;
  final lat2 = to.lat * math.pi / 180;
  final dLng = (to.lng - from.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String _formatDuration(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
