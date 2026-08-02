import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/imu_service.dart';
import '../services/location_service.dart';
import '../services/route_geometry_matcher.dart';
import '../services/route_loading_policy.dart';
import '../services/route_turn_service.dart';
import '../services/run_session_service.dart';
import '../services/settings_service.dart';
import '../services/ptt_service.dart';
import '../services/supabase_service.dart';
import '../services/voice_briefing_service.dart';
import '../services/crew_channel_service.dart';
import '../labs/walkie/walkie_ptt_controller.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/route_drive_cue.dart';
import '../widgets/map_widget.dart';
import 'lean_run_summary_screen.dart';

/// 크루 워키토키는 이 dev 플래그가 켜진 빌드에서만 주행화면에 노출된다.
/// 플래그 off(프로덕션 기본)면 아래 PTT 오버레이는 생성되지 않는다.
const bool _revvWalkieLabEnabled = bool.fromEnvironment('REVV_WALKIE_LAB');

typedef DriveRouteNodesLoader = Future<List<LatLng>> Function(String routeId);

class LeanDriveScreen extends StatefulWidget {
  final RevvRoute route;
  final bool simulated;

  /// 테스트 주입용 — 참여 상태 크루 서비스/컨트롤러를 넣어 PTT를 노출시킨다.
  /// 프로덕션에서는 null → Provider에서 읽고, 플래그 off면 무시된다.
  final CrewChannelService? crewChannelOverride;
  final WalkiePttController? pttControllerOverride;
  final bool walkieEnabledOverride;
  final VoiceBriefingService? voiceOverride;
  final DriveRouteNodesLoader? routeNodesLoader;
  final RouteTurnService? routeTurnService;

  const LeanDriveScreen({
    super.key,
    required this.route,
    this.simulated = false,
    this.crewChannelOverride,
    this.pttControllerOverride,
    this.walkieEnabledOverride = _revvWalkieLabEnabled,
    this.voiceOverride,
    this.routeNodesLoader,
    this.routeTurnService,
  });

  @override
  State<LeanDriveScreen> createState() => _LeanDriveScreenState();
}

class _LeanDriveScreenState extends State<LeanDriveScreen> {
  LocationService? _location;
  RunSessionService? _session;
  ImuService? _imuService;
  SettingsService? _settings;
  late final VoiceBriefingService _voice;
  late final RouteTurnService _turnService;
  bool _started = false;
  DateTime? _startedAt;
  Timer? _clock;
  Timer? _simulationTimer;
  Timer? _gpsWatchdog;
  Duration _elapsed = Duration.zero;
  int _simulationIndex = 0;
  double _simMaxLateralG = 0;
  double _simMaxLongitudinalG = 0;
  double _speedKmh = 0;
  double _lateralG = 0;
  double _longitudinalG = 0;
  double _progress = 0;
  double _remainingKm = 0;
  LatLng? _drivePosition;
  double? _navigationBearing;
  List<LatLng>? _matchedRouteNodes;
  bool _matchingRouteGeometry = false;
  DriveCurveCue? _cue;
  DriveRhythmBrief? _rhythmBrief;
  TurnByTurnState? _turnByTurn;
  NavStepProgress? _navStepProgress;
  List<NavStep> _navSteps = const [];
  DriveRouteStatus _routeStatus = DriveRouteStatus.approachingStart;
  String? _routeEventMessage;
  DateTime? _routeEventUntil;
  DateTime? _lastGpsUpdateAt;
  bool _gpsWeak = false;

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceOverride ?? VoiceBriefingService();
    _turnService = widget.routeTurnService ?? RouteTurnService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _session = context.read<RunSessionService>();
    _settings = context.read<SettingsService>();
    _imuService = context.read<ImuService>();
    if (!widget.simulated) {
      _location = context.read<LocationService>();
      _location!.addListener(_onLocation);
      _imuService!.addListener(_onImu);
    }
    _startDrive();
  }

  Future<void> _startDrive() async {
    if (!widget.simulated) {
      await _location?.requestPermission();
      if (!mounted) return;
      _startGpsWatchdog();
      await _location?.startTracking();
      if (!mounted) return;
    }
    final language = _settings?.appLanguage ?? AppLanguage.korean;
    _voice.announceStart(language, muted: _settings?.ttsMuted ?? true);
    await _hydrateSparseRouteNodes();
    primeRouteCueGeometry(_activeRouteNodes, routeId: widget.route.id);
    unawaited(_loadRouteTurns(_activeRouteNodes));
    unawaited(_prepareMatchedRouteGeometry());
    if (!mounted) return;
    _startedAt = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
    _session?.startSession(widget.route);
    unawaited(WakelockPlus.enable());
    if (widget.simulated) {
      _startSimulation();
    } else {
      _onLocation();
    }
  }

  void _startSimulation() {
    final nodes = _activeRouteNodes;
    if (nodes.isEmpty) {
      _applyDriveSample(
        widget.route.centerPoint,
        0,
        lateralG: 0,
        longitudinalG: 0,
        driveMode: 'simulation',
      );
      return;
    }

    final step = math.max(1, nodes.length ~/ 180);
    _applySimulatedNode(nodes.first);
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      _simulationIndex = math.min(_simulationIndex + step, nodes.length - 1);
      _applySimulatedNode(nodes[_simulationIndex]);
      if (_simulationIndex >= nodes.length - 1) {
        _simulationTimer?.cancel();
      }
    });
  }

  void _applySimulatedNode(LatLng position) {
    final phase = _simulationIndex / 4.0;
    final curvePressure = (_cue?.severity ?? _rhythmBrief?.severity ?? 0.25)
        .clamp(0.0, 1.0);
    final lateralG = math.sin(phase) * (0.16 + curvePressure * 0.42);
    final longitudinalG = math.cos(phase / 2) * 0.08;
    final speed = (42 + (1 - curvePressure) * 22 + math.sin(phase / 3) * 7)
        .clamp(24.0, 92.0);
    _simMaxLateralG = math.max(_simMaxLateralG, lateralG.abs());
    _simMaxLongitudinalG = math.max(_simMaxLongitudinalG, longitudinalG.abs());
    _applyDriveSample(
      position,
      speed,
      lateralG: lateralG,
      longitudinalG: longitudinalG,
      driveMode: 'simulation',
    );
  }

  void _onLocation() {
    final loc = _location;
    if (!mounted || loc == null) return;
    final position = loc.bestKnownLatLng;
    final timestamp = loc.currentPosition?.timestamp;
    if (timestamp != null) {
      _lastGpsUpdateAt = timestamp;
    }
    final speed = loc.speedKmh.clamp(0.0, 260.0);
    _imuService?.updateSpeedKmh(speed);
    if (position != null) {
      _applyDriveSample(
        position,
        speed,
        lateralG: _lateralG,
        longitudinalG: _longitudinalG,
        driveMode: 'cruise',
        heading: loc.heading,
        trustedSpeedMps: loc.trustedSpeedMps,
      );
      return;
    }
    setState(() => _speedKmh = speed);
  }

  void _startGpsWatchdog() {
    _gpsWatchdog?.cancel();
    _lastGpsUpdateAt = _location?.currentPosition?.timestamp ?? DateTime.now();
    final permanentlyDenied =
        _location?.permissionStatus.isPermanentlyDenied ?? false;
    if (mounted && _gpsWeak != permanentlyDenied) {
      setState(() => _gpsWeak = permanentlyDenied);
    }
    _gpsWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      final lastUpdate = _lastGpsUpdateAt;
      final weak = lastUpdate == null ||
          DateTime.now().difference(lastUpdate) >= const Duration(seconds: 8);
      if (mounted && weak != _gpsWeak) {
        setState(() => _gpsWeak = weak);
      }
    });
  }

  void _applyDriveSample(
    LatLng position,
    double speed, {
    required double lateralG,
    required double longitudinalG,
    required String driveMode,
    double? heading,
    double? trustedSpeedMps,
  }) {
    _session?.recordPosition(
      position.lat,
      position.lng,
      speed,
      lateralG: lateralG,
      longitudinalG: longitudinalG,
      driveMode: driveMode,
    );
    _session?.recordSharpCorner(position.lat, position.lng, lateralG);
    final language = _settings?.appLanguage ?? AppLanguage.korean;
    final routeState = readDriveRouteState(
      position,
      _activeRouteNodes,
      language: language,
      routeId: widget.route.id,
    );
    final navStepProgress = nextStepProgressWithRouteCueGeometry(
      position,
      _activeRouteNodes,
      _navSteps,
      routeId: widget.route.id,
    );
    final voiceCurveCue = readVoiceCurveCue(
      position,
      _activeRouteNodes,
      trustedSpeedMps: trustedSpeedMps,
      language: language,
      routeId: widget.route.id,
    );
    _voice.onCoPilotCue(
      navStep: navStepProgress?.step,
      navDistanceM: navStepProgress?.aheadM,
      curveCue: voiceCurveCue,
      trustedSpeedMps: trustedSpeedMps,
      language: language,
      muted: _settings?.ttsMuted ?? true,
    );
    final turnByTurn = readTurnByTurnState(
      position,
      _activeRouteNodes,
      language: language,
      routeId: widget.route.id,
    );
    final nextEvent = _routeEventFor(_routeStatus, routeState.status, language);
    final nextBearing = _nextNavigationBearing(position, heading);
    _handleRouteStatusTransition(
      previous: _routeStatus,
      next: routeState.status,
      position: position,
      language: language,
      muted: _settings?.ttsMuted ?? true,
    );
    if (!mounted) return;
    setState(() {
      _drivePosition = position;
      _navigationBearing = nextBearing;
      _speedKmh = speed;
      _lateralG = lateralG;
      _longitudinalG = longitudinalG;
      _progress = routeState.progress;
      _remainingKm = routeState.remainingKm;
      _cue = routeState.cue;
      _rhythmBrief = routeState.rhythmBrief;
      _turnByTurn = turnByTurn;
      _navStepProgress = navStepProgress;
      _routeStatus = routeState.status;
      if (nextEvent != null) {
        _routeEventMessage = nextEvent;
        _routeEventUntil = DateTime.now().add(const Duration(seconds: 4));
      } else if (_routeEventUntil?.isBefore(DateTime.now()) ?? false) {
        _routeEventMessage = null;
        _routeEventUntil = null;
      }
    });
  }

  Future<void> _loadRouteTurns(List<LatLng> nodes) async {
    final steps = await _turnService.fetchSteps(nodes);
    if (!mounted || steps.isEmpty) return;
    setState(() => _navSteps = steps);
  }

  void _handleRouteStatusTransition({
    required DriveRouteStatus previous,
    required DriveRouteStatus next,
    required LatLng position,
    required AppLanguage language,
    required bool muted,
  }) {
    if (previous == next) return;
    final rejoin = nearestRoutePoint(position, _activeRouteNodes);
    _voice.onRouteStatusChange(
      previous: previous,
      next: next,
      language: language,
      muted: muted,
      rejoinBearing: rejoin == null
          ? _navigationBearing
          : _bearingBetween(position, rejoin),
    );
    if (next != DriveRouteStatus.offRoute) return;
    if (rejoin == null) return;
    unawaited(_recalculateRouteTurns(position, rejoin));
  }

  Future<void> _recalculateRouteTurns(LatLng position, LatLng rejoin) async {
    final steps = await _turnService.recalculateSteps(
      current: position,
      rejoin: rejoin,
    );
    if (!mounted || steps.isEmpty) return;
    setState(() => _navSteps = steps);
  }

  double? _nextNavigationBearing(LatLng position, double? heading) {
    final previous = _drivePosition;
    if (previous != null &&
        RevvRoute.haversineKm(previous, position) >= 0.004) {
      return _bearingBetween(previous, position);
    }
    if (heading != null && heading >= 0) return _normalizeBearing(heading);
    return _navigationBearing;
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.lat * math.pi / 180;
    final lat2 = to.lat * math.pi / 180;
    final dLng = (to.lng - from.lng) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return _normalizeBearing(math.atan2(y, x) * 180 / math.pi);
  }

  double _normalizeBearing(double value) {
    final normalized = value % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  void _onImu() {
    if (!mounted) return;
    final imu = _imuService;
    if (imu == null) return;
    final nextLat = imu.lateralG;
    final nextLon = imu.longitudinalG;
    if ((nextLat - _lateralG).abs() < 0.02 &&
        (nextLon - _longitudinalG).abs() < 0.02) {
      return;
    }
    // GPS(1Hz)보다 50Hz로 선행 호출해 GPS 틱 사이 G 피크도 기록
    final pos = _drivePosition;
    if (pos != null) {
      _session?.recordSharpCorner(pos.lat, pos.lng, nextLat);
    }
    setState(() {
      _lateralG = nextLat;
      _longitudinalG = nextLon;
    });
  }

  List<LatLng> get _activeRouteNodes {
    final matched = _matchedRouteNodes;
    if (matched != null && matched.length >= 2) return matched;
    return widget.route.nodes;
  }

  Future<void> _prepareMatchedRouteGeometry() async {
    if (_matchingRouteGeometry || widget.route.nodes.length < 2) return;
    _matchingRouteGeometry = true;
    final matched = await RouteGeometryMatcher.instance.matchRoute(
      widget.route,
    );
    if (!mounted) return;
    _matchingRouteGeometry = false;
    if (matched.length < 2 || _sameRouteNodes(matched, widget.route.nodes)) {
      return;
    }
    setState(() => _matchedRouteNodes = matched);
    primeRouteCueGeometry(_activeRouteNodes, routeId: widget.route.id);
  }

  Future<void> _hydrateSparseRouteNodes() async {
    if (_averageRouteNodeSpacingM(widget.route.nodes) <= 120) return;
    final loader =
        widget.routeNodesLoader ?? SupabaseService().fetchRouteNodes;
    final nodes = await loader(widget.route.id).catchError((_) => const <LatLng>[]);
    if (!mounted || nodes.length < 2 || _sameRouteNodes(nodes, widget.route.nodes)) {
      return;
    }
    setState(() => _matchedRouteNodes = nodes);
    primeRouteCueGeometry(_activeRouteNodes, routeId: widget.route.id);
  }

  bool _sameRouteNodes(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i].lat - b[i].lat).abs() > 0.000001 ||
          (a[i].lng - b[i].lng).abs() > 0.000001) {
        return false;
      }
    }
    return true;
  }

  void _endDrive() {
    _simulationTimer?.cancel();
    _gpsWatchdog?.cancel();
    _location?.removeListener(_onLocation);
    _imuService?.removeListener(_onImu);
    final imu = _imuService;
    final run = _session?.stopSession(
      maxLateralG: widget.simulated ? _simMaxLateralG : (imu?.maxLateralG ?? 0),
      maxLonG: widget.simulated ? _simMaxLongitudinalG : (imu?.maxLonG ?? 0),
    );
    unawaited(WakelockPlus.disable());
    if (!widget.simulated) {
      imu?.resetMaxG();
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LeanRunSummaryScreen(session: run)),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _simulationTimer?.cancel();
    _gpsWatchdog?.cancel();
    _location?.removeListener(_onLocation);
    _imuService?.removeListener(_onImu);
    _voice.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue = _cue;
    final routeEvent = _routeEventUntil?.isAfter(DateTime.now()) == true
        ? _routeEventMessage
        : null;
    final remainingKm = _remainingKm > 0
        ? _remainingKm
        : widget.route.distanceKm;
    final settings = context.watch<SettingsService>();
    final language = settings.appLanguage;
    final totalG = math.sqrt(
      _lateralG * _lateralG + _longitudinalG * _longitudinalG,
    );
    final routeNodes = _activeRouteNodes;
    final routeName = routeDisplayName(widget.route, language: language);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              isSprintMode: true,
              routePolyline: routeNodes,
              routeFocusMode: true,
              navigationBearing: _navigationBearing,
              simulatedPosition: widget.simulated
                  ? (_drivePosition ??
                        (routeNodes.isNotEmpty
                            ? routeNodes.first
                            : widget.route.centerPoint))
                  : null,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  _DriveTopBar(
                    routeName: routeName,
                    progress: _progress,
                    remainingKm: remainingKm,
                    simulated: widget.simulated,
                    language: language,
                  ),
                  const SizedBox(height: 8),
                  if (_gpsWeak)
                    _GpsStatusBanner(
                      language: language,
                      permanentlyDenied:
                          _location?.permissionStatus.isPermanentlyDenied ??
                          false,
                      onOpenSettings: () => openAppSettings(),
                    ),
                  if (_gpsWeak) const SizedBox(height: 8),
                  _NextCurveBanner(
                    cue: cue,
                    rhythmBrief: _rhythmBrief,
                    turnByTurn: _turnByTurn,
                    navStepProgress: _navStepProgress,
                    status: _routeStatus,
                    eventMessage: routeEvent,
                    language: language,
                  ),
                  const Spacer(),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CompactSpeedPill(speedKmh: _speedKmh, language: language),
                      RepaintBoundary(
                        child: widget.simulated
                            ? _CompactGInstrument(
                                lateralG: _lateralG,
                                longitudinalG: _longitudinalG,
                                totalG: totalG,
                                language: language,
                              )
                            : Consumer<ImuService>(
                                builder: (context, imu, _) {
                                  final lG = _lateralG;
                                  final nG = _longitudinalG;
                                  final tG = math.sqrt(lG * lG + nG * nG);
                                  return _CompactGInstrument(
                                    lateralG: lG,
                                    longitudinalG: nG,
                                    totalG: tG,
                                    language: language,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _DriveControlStrip(
                    remainingKm: remainingKm,
                    elapsed: _formatDuration(_elapsed),
                    muted: settings.ttsMuted,
                    language: language,
                    onToggleMute: () =>
                        settings.setTtsMuted(!settings.ttsMuted),
                    onEnd: _endDrive,
                  ),
                ],
              ),
            ),
          ),
          if (widget.walkieEnabledOverride) _walkieAutoConnect(context),
          if (_walkiePttButton(context, language) case final button?)
            Positioned(
              right: 18,
              bottom: MediaQuery.paddingOf(context).bottom + 96,
              child: button,
            ),
        ],
      ),
    );
  }

  Widget _walkieAutoConnect(BuildContext context) {
    final crew =
        widget.crewChannelOverride ?? context.watch<CrewChannelService>();
    final controller =
        widget.pttControllerOverride ?? context.read<WalkiePttController>();
    return _WalkieAutoConnect(
      controller: controller,
      channelId: crew.isJoined ? crew.channelId : null,
    );
  }

  /// 워키토키 플래그가 켜져 있고 채널에 참여 중일 때만 PTT 버튼을 만든다.
  /// 그 외에는 null → 주행화면은 기존과 완전히 동일하다(회귀 0).
  Widget? _walkiePttButton(BuildContext context, AppLanguage language) {
    if (!widget.walkieEnabledOverride) return null;
    final crew =
        widget.crewChannelOverride ?? context.watch<CrewChannelService>();
    final channelId = crew.channelId;
    if (!crew.isJoined || channelId == null) return null;
    final controller =
        widget.pttControllerOverride ?? context.read<WalkiePttController>();
    return ValueListenableBuilder<PttConnectionState>(
      valueListenable: controller.connectionState,
      builder: (context, connectionState, _) => ValueListenableBuilder<bool>(
        valueListenable: controller.channelBusy,
        builder: (context, channelBusy, _) => _DrivePttButton(
          language: language,
          channelBusy: channelBusy,
          micLevel: controller.micLevel,
          connectionState: connectionState,
          onStart: () => controller.startTalking(channelId),
          onStop: () => controller.stopTalking(),
        ),
      ),
    );
  }
}

double _averageRouteNodeSpacingM(List<LatLng> nodes) {
  if (nodes.length < 2) return 0;
  double totalKm = 0;
  for (int i = 1; i < nodes.length; i++) {
    totalKm += RevvRoute.haversineKm(nodes[i - 1], nodes[i]);
  }
  return totalKm * 1000 / (nodes.length - 1);
}

class _WalkieAutoConnect extends StatefulWidget {
  final WalkiePttController controller;
  final String? channelId;

  const _WalkieAutoConnect({required this.controller, required this.channelId});

  @override
  State<_WalkieAutoConnect> createState() => _WalkieAutoConnectState();
}

class _WalkieAutoConnectState extends State<_WalkieAutoConnect> {
  String? _connectedChannelId;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _WalkieAutoConnect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      _sync();
    }
  }

  void _sync() {
    final channelId = widget.channelId;
    if (channelId != null) {
      if (_connectedChannelId == channelId) return;
      _connectedChannelId = channelId;
      unawaited(
        widget.controller.connect(channelId).catchError((_) {
          if (mounted && _connectedChannelId == channelId) {
            _connectedChannelId = null;
          }
        }),
      );
    } else if (_connectedChannelId != null) {
      _connectedChannelId = null;
      unawaited(widget.controller.disconnect().catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DrivePttButton extends StatefulWidget {
  final AppLanguage language;
  final bool channelBusy;
  final ValueListenable<double> micLevel;
  final PttConnectionState connectionState;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  const _DrivePttButton({
    required this.language,
    required this.channelBusy,
    required this.micLevel,
    required this.connectionState,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<_DrivePttButton> createState() => _DrivePttButtonState();
}

class _DrivePttButtonState extends State<_DrivePttButton> {
  bool _talking = false;

  void _begin() {
    if (_disabled) return;
    if (_talking) return;
    setState(() => _talking = true);
    unawaited(widget.onStart());
  }

  void _finish() {
    if (!_talking) return;
    setState(() => _talking = false);
    unawaited(widget.onStop());
  }

  bool get _disabled =>
      widget.channelBusy ||
      widget.connectionState == PttConnectionState.reconnecting;

  @override
  Widget build(BuildContext context) {
    final reconnecting =
        widget.connectionState == PttConnectionState.reconnecting;
    final disabled = _disabled;
    final label = reconnecting
        ? AppCopy.t(
            widget.language,
            ko: '재연결 중…',
            en: 'Reconnecting…',
            fr: 'Reconnexion…',
          )
        : widget.channelBusy
        ? AppCopy.t(widget.language, ko: '수신 중', en: 'RX', fr: 'Réception')
        : _talking
        ? AppCopy.t(widget.language, ko: '말하는 중', en: 'Talking', fr: 'En cours')
        : AppCopy.t(
            widget.language,
            ko: '눌러서 무전',
            en: 'Hold to talk',
            fr: 'Maintenir',
          );
    return GestureDetector(
      onTapDown: disabled ? null : (_) => _begin(),
      onTapUp: disabled ? null : (_) => _finish(),
      onTapCancel: disabled ? null : _finish,
      child: Semantics(
        button: true,
        enabled: !disabled,
        label: label,
        child: ValueListenableBuilder<double>(
          valueListenable: widget.micLevel,
          builder: (context, level, _) {
            final activeLevel = _talking ? level.clamp(0.0, 1.0) : 0.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _talking ? AppColors.red : AppColors.panel2,
                    border: Border.all(
                      color: _talking
                          ? AppColors.red.withValues(
                              alpha: 0.8 + activeLevel * 0.2,
                            )
                          : AppColors.outlineVariant,
                      width: 2 + activeLevel * 4,
                    ),
                    boxShadow: _talking
                        ? [
                            BoxShadow(
                              color: AppColors.red.withValues(
                                alpha: 0.38 + activeLevel * 0.28,
                              ),
                              blurRadius: 20 + activeLevel * 24,
                              spreadRadius: 1 + activeLevel * 5,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mic_rounded,
                        size: 30,
                        color: _talking
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppText.technicalLabel(
                          size: 9,
                          color: _talking
                              ? AppColors.onPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (reconnecting)
                  const Positioned(
                    top: 14,
                    right: 14,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String? _routeEventFor(
  DriveRouteStatus previous,
  DriveRouteStatus next,
  AppLanguage language,
) {
  if (previous == next) return null;
  if (previous == DriveRouteStatus.offRoute &&
      next == DriveRouteStatus.onRoute) {
    return AppCopy.t(
      language,
      ko: '온 루트',
      en: 'On route',
      fr: 'Sur la route',
    );
  }
  if (next == DriveRouteStatus.offRoute) {
    return AppCopy.t(
      language,
      ko: '루트 이탈',
      en: 'Off route',
      fr: 'Hors route',
    );
  }
  if (next == DriveRouteStatus.approachingStart) {
    return AppCopy.t(
      language,
      ko: '시작점으로 이동 중',
      en: 'Going to start',
      fr: 'Vers le départ',
    );
  }
  if (next == DriveRouteStatus.completed) {
    return AppCopy.t(
      language,
      ko: '루트 완료 지점',
      en: 'Route finish',
      fr: 'Fin de route',
    );
  }
  return null;
}

class _DriveTopBar extends StatelessWidget {
  final String routeName;
  final double progress;
  final double remainingKm;
  final bool simulated;
  final AppLanguage language;

  const _DriveTopBar({
    required this.routeName,
    required this.progress,
    required this.remainingKm,
    required this.simulated,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  routeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (simulated) ...[
                const SizedBox(width: 8),
                _TinyHudPill(
                  label: AppCopy.t(language, ko: '테스트', en: 'TEST', fr: 'TEST'),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: AppText.technicalLabel(
                  size: 11,
                  color: AppColors.primaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatKm(remainingKm),
                style: AppText.technicalLabel(
                  size: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: AppColors.surface,
              color: AppColors.primaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsStatusBanner extends StatelessWidget {
  final AppLanguage language;
  final bool permanentlyDenied;
  final VoidCallback onOpenSettings;

  const _GpsStatusBanner({
    required this.language,
    required this.permanentlyDenied,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_not_fixed_rounded, size: 18, color: AppColors.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppCopy.t(
                language,
                ko: permanentlyDenied ? 'GPS 권한이 꺼져 있습니다' : 'GPS 신호 약함',
                en: permanentlyDenied ? 'GPS permission is off' : 'GPS signal weak',
                fr: permanentlyDenied ? 'Autorisation GPS désactivée' : 'Signal GPS faible',
              ),
              style: AppText.body(
                size: 12,
                weight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          if (permanentlyDenied)
            TextButton(
              onPressed: onOpenSettings,
              child: Text(
                AppCopy.t(language, ko: '설정', en: 'Settings', fr: 'Réglages'),
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NextCurveBanner extends StatelessWidget {
  final DriveCurveCue? cue;
  final DriveRhythmBrief? rhythmBrief;
  final TurnByTurnState? turnByTurn;
  final NavStepProgress? navStepProgress;
  final DriveRouteStatus status;
  final String? eventMessage;
  final AppLanguage language;

  const _NextCurveBanner({
    required this.cue,
    required this.rhythmBrief,
    required this.turnByTurn,
    required this.navStepProgress,
    required this.status,
    required this.eventMessage,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final data = cue;
    final rhythm = rhythmBrief;
    final severity = math.max(data?.severity ?? 0, rhythm?.severity ?? 0);
    final severityColor = _severityColor(severity);
    final fallback = _fallbackCue(status, language);
    final turn = turnByTurn?.instruction;
    final nav = navStepProgress;
    final headline = data?.headline ?? fallback.label;
    final rhythmLine = data?.rhythmLine ?? rhythm?.advice ?? fallback.detail;
    return _DriveGlass(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nav != null && nav.aheadM <= 320) ...[
            Row(
              children: [
                const Icon(
                  Icons.assistant_direction_rounded,
                  size: 16,
                  color: AppColors.primaryContainer,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${_paceDistance(nav.aheadM)} · ${nav.step.call(language)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.technicalLabel(
                      size: 12,
                      color: AppColors.primaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
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
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: severityColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  data?.icon ?? fallback.icon,
                  color: severityColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 24,
                        height: 1.02,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      rhythmLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 13,
                        weight: FontWeight.w900,
                        color: severityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (turn != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: severityColor.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                children: [
                  Icon(turn.icon, size: 18, color: severityColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      turn.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 13,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${turnByTurn!.completedInstructions + 1}/${turnByTurn!.totalInstructions}',
                    style: AppText.technicalLabel(
                      size: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _paceDistance(double meters) {
  if (meters >= 1000) return ((meters / 100).round() * 100).toString();
  return ((meters / 10).round() * 10).clamp(0, 990).toString();
}

class _TinyHudPill extends StatelessWidget {
  final String label;

  const _TinyHudPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: AppText.technicalLabel(
          size: 8,
          color: AppColors.primaryContainer,
          letterSpacing: 0.8,
        ),
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

_FallbackCue _fallbackCue(DriveRouteStatus status, AppLanguage language) {
  switch (status) {
    case DriveRouteStatus.approachingStart:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '시작점 이동',
          en: 'To start',
          fr: 'Vers départ',
        ),
        detail: AppCopy.t(
          language,
          ko: '루트 진입 대기',
          en: 'Waiting to enter',
          fr: 'Attente entrée',
        ),
        icon: Icons.flag_rounded,
        distance: 'START',
      );
    case DriveRouteStatus.offRoute:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '루트 이탈',
          en: 'Off route',
          fr: 'Hors route',
        ),
        detail: AppCopy.t(
          language,
          ko: '라인 복귀',
          en: 'Rejoin line',
          fr: 'Rejoindre ligne',
        ),
        icon: Icons.near_me_disabled_rounded,
        distance: 'REJOIN',
      );
    case DriveRouteStatus.completed:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '루트 완료',
          en: 'Route complete',
          fr: 'Route terminée',
        ),
        detail: AppCopy.t(
          language,
          ko: '주행 종료 가능',
          en: 'Ready to finish',
          fr: 'Fin possible',
        ),
        icon: Icons.done_rounded,
        distance: 'DONE',
      );
    case DriveRouteStatus.onRoute:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '흐름 구간',
          en: 'Flow section',
          fr: 'Section fluide',
        ),
        detail: AppCopy.t(
          language,
          ko: '직선 구간',
          en: 'Straight section',
          fr: 'Section droite',
        ),
        icon: Icons.timeline_rounded,
        distance: 'CLEAR',
      );
  }
}

class _CompactSpeedPill extends StatelessWidget {
  final double speedKmh;
  final AppLanguage language;

  const _CompactSpeedPill({required this.speedKmh, required this.language});

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppCopy.t(language, ko: '속도', en: 'SPEED', fr: 'VITESSE'),
            style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: speedKmh),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => Text(
                    value.toStringAsFixed(0),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: AppText.display(
                      size: 40,
                      height: 0.9,
                      color: AppColors.primaryContainer,
                    ),
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
  final AppLanguage language;

  const _CompactGInstrument({
    required this.lateralG,
    required this.longitudinalG,
    required this.totalG,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GDot(lateralG: lateralG, longitudinalG: longitudinalG),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppCopy.t(language, ko: '밸런스', en: 'BALANCE', fr: 'ÉQUILIBRE'),
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
            ],
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
    final totalG = math.sqrt(
      lateralG * lateralG + longitudinalG * longitudinalG,
    );
    final dotColor = totalG > 0.6
        ? AppColors.danger
        : totalG > 0.35
        ? AppColors.orange
        : AppColors.primaryContainer;
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
          AnimatedAlign(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            alignment: Alignment(dx, dy),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.52),
                    blurRadius: 10,
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
  final AppLanguage language;

  const _DriveControlStrip({
    required this.remainingKm,
    required this.elapsed,
    required this.muted,
    required this.onToggleMute,
    required this.onEnd,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    return _DriveGlass(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 82,
            child: _StripMetric(
              label: AppCopy.t(
                language,
                ko: '남은 거리',
                en: 'Remain',
                fr: 'Reste',
              ),
              value: _formatKm(remainingKm),
            ),
          ),
          SizedBox(
            width: 72,
            child: _StripMetric(
              label: AppCopy.t(language, ko: '경과', en: 'Time', fr: 'Temps'),
              value: elapsed,
            ),
          ),
          IconButton(
            tooltip: muted
                ? AppCopy.voiceOn(language)
                : AppCopy.voiceOff(language),
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
          SizedBox(
            height: 48,
            child: _HoldToEndButton(onEnd: onEnd, language: language),
          ),
        ],
      ),
    );
  }
}

class _HoldToEndButton extends StatefulWidget {
  final VoidCallback onEnd;
  final AppLanguage language;

  const _HoldToEndButton({required this.onEnd, required this.language});

  @override
  State<_HoldToEndButton> createState() => _HoldToEndButtonState();
}

class _HoldToEndButtonState extends State<_HoldToEndButton> {
  static const _holdDuration = Duration(milliseconds: 1500);

  Timer? _holdTimer;
  Timer? _hintTimer;
  bool _holding = false;
  bool _showHint = false;

  void _startHold(TapDownDetails _) {
    if (_holdTimer != null) return;
    setState(() {
      _holding = true;
      _showHint = false;
    });
    _holdTimer = Timer(_holdDuration, () {
      _holdTimer = null;
      if (!mounted) return;
      widget.onEnd();
    });
  }

  void _stopHold() {
    final wasHolding = _holdTimer != null;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted) return;
    setState(() {
      _holding = false;
      _showHint = wasHolding;
    });
    if (wasHolding) {
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showHint = false);
      });
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _showHint
        ? AppCopy.t(
            widget.language,
            ko: '길게 눌러 종료',
            en: 'Hold to end',
            fr: 'Maintenez pour finir',
          )
        : AppCopy.t(widget.language, ko: '종료', en: 'End', fr: 'Terminer');
    return GestureDetector(
      onTapDown: _startHold,
      onTapUp: (_) => _stopHold(),
      onTapCancel: _stopHold,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_holding)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: _holdDuration,
                builder: (context, value, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.cream.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stop_rounded, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppText.body(
                      size: 15,
                      weight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
          style: AppText.technicalLabel(size: 11, color: AppColors.textHint),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppText.body(
            size: 20,
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
  final EdgeInsetsGeometry padding;

  const _DriveGlass({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.91),
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
  if (severity >= 1) return AppColors.warning; // 중간 커브 — 옐로우
  return AppColors.primaryContainer;
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
