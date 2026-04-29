import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/drive_thresholds.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../models/chain_candidate.dart';
import '../models/composite_route.dart';
import '../models/revv_route.dart';
import '../widgets/map_widget.dart';
import '../widgets/jarvis_panel.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/route_service.dart';
import '../services/directions_service.dart';
import '../services/settings_service.dart';
import '../services/audio_service.dart';
import '../services/stt_service.dart';
import '../services/jarvis_service.dart';
import '../services/local_command_service.dart';
import '../models/run_session.dart';
import '../ui/revv_copy.dart';
import 'sprint_screen.dart';
import 'drive_screen.dart';
import 'run_card_screen.dart';
import 'routes_screen.dart';
import 'obd_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'analysis_screen.dart';
import 'ranking_screen.dart';
import '../widgets/driver_level_card.dart';
import '../widgets/revv_ui.dart';
import 'garage_screen.dart';
import 'saved_routes_screen.dart';

PageRouteBuilder<T> _slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 280),
  transitionsBuilder: (_, anim, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

TextStyle _techUiStyle({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w700,
  Color color = Colors.white,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.orbitron(
    textStyle: TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFamilyFallback: const ['Noto Sans KR', 'Apple SD Gothic Neo'],
    ),
  );
}

class CruiseScreen extends StatefulWidget {
  const CruiseScreen({super.key});

  @override
  State<CruiseScreen> createState() => _CruiseScreenState();
}

enum _RidePhase { idle, routeSelected, nearStart, sprinting, driving }

class _CruiseScreenState extends State<CruiseScreen>
    with WidgetsBindingObserver {
  List<LatLng>? _navPolyline;
  RevvRoute? _lastFetchedRoute;
  _RidePhase _phase = _RidePhase.idle;
  LocationService? _locationService;
  int _activeTab = 0;

  bool _showCurveHeatmap = false;
  RevvRoute? _sprintRoute;
  List<LatLng>? _sprintNavPolyline;
  bool _sprintRouteFocus = false;

  RevvRoute? _driveRoute;
  SprintStartMode _activeStartMode = SprintStartMode.auto;
  String? _lastPhaseSyncedRouteId;
  bool? _lastAlwaysListenWanted;
  bool _sprintLaunchQueued = false;

  // ── 항상 듣기 상태 ──
  bool _alwaysListening = false;
  int _recenterSignal = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loc = context.read<LocationService>();
      _locationService = loc;
      await loc.requestPermission();
      if (loc.hasPermission) {
        await loc.startTracking();
        if (mounted) {
          context.read<WeatherService>().fetchWeather(loc.lat, loc.lng);
        }
        loc.addListener(_onLocationChanged);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('위치 권한이 필요해요. 설정에서 허용해주세요.'),
              backgroundColor: AppColors.red,
            ),
          );
        }
      }
    });
  }

  void _syncAlwaysListen() {
    final want = context.read<SettingsService>().alwaysListen;
    if (want == _alwaysListening) return;
    _alwaysListening = want;
    if (want) {
      SttService().startAlwaysListening(_onAlwaysListenResult);
    } else {
      SttService().stopAlwaysListening();
    }
    if (mounted) setState(() {});
  }

  static const _wakeWords = ['레브', '래브', 'revv', 'revy', '레비', '래비'];

  Future<void> _onAlwaysListenResult(String text) async {
    // 웨이크워드 "레브" 없으면 무시
    final lower = text.toLowerCase();
    if (!_wakeWords.any((w) => lower.contains(w))) return;

    if (!mounted) return;
    // 웨이크워드 감지 즉시 신호음
    AudioService().playBeep();
    SttService().setProcessing(true);

    final jarvis = context.read<JarvisService>();

    // 1. 로컬 인텐트 처리 (무료, 즉시 응답)
    final localResponse = LocalCommandService.handle(context, text);
    if (localResponse != null) {
      if (mounted) jarvis.speak(localResponse);
      SttService().setProcessing(false);
      return;
    }

    // 2. 항상 듣기에서는 로컬 명령만 허용
    // 민감한 주행 텔레메트리가 원격 AI로 전송되지 않도록 차단한다.
    if (mounted) {
      jarvis.speak('항상 듣기에서는 로컬 명령만 처리해요. 복잡한 요청은 버튼을 눌러서 실행해 주세요.');
    }
    SttService().setProcessing(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wantListen = context.read<SettingsService>().alwaysListen;
    if (!wantListen) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      SttService().stopAlwaysListening();
      if (mounted) setState(() => _alwaysListening = false);
    } else if (state == AppLifecycleState.resumed && !_alwaysListening) {
      SttService().startAlwaysListening(_onAlwaysListenResult);
      if (mounted) setState(() => _alwaysListening = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SttService().stopAlwaysListening();
    _locationService?.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    final route = context.read<RouteService>().selectedRoute;
    if (route == null) {
      _syncBrowsePhase(null);
      return;
    }
    if (route != _lastFetchedRoute) {
      _lastFetchedRoute = route;
      _fetchNavRoute(route);
    }
    final loc = context.read<LocationService>();
    final dist = RevvRoute.haversineKm(
      LatLng(loc.lat, loc.lng),
      route.nodes.first,
    );
    final isNear = dist < kRouteStartNearKm;
    _syncBrowsePhase(route, isNearOverride: isNear);
  }

  void _syncBrowsePhase(RevvRoute? route, {bool? isNearOverride}) {
    if (_phase == _RidePhase.sprinting || _phase == _RidePhase.driving) return;
    final nextPhase = route == null
        ? _RidePhase.idle
        : (isNearOverride ?? _phase == _RidePhase.nearStart)
        ? _RidePhase.nearStart
        : _RidePhase.routeSelected;
    if (nextPhase != _phase && mounted) {
      setState(() => _phase = nextPhase);
    }
  }

  void _enterSprint() {
    _phase = _RidePhase.sprinting;
  }

  void _enterDrive() {
    _phase = _RidePhase.driving;
  }

  void _exitRide() {
    final selectedRoute = context.read<RouteService>().selectedRoute;
    _phase = selectedRoute == null ? _RidePhase.idle : _RidePhase.routeSelected;
  }

  void _queuePhaseSync(RevvRoute? selectedRoute) {
    final routeSyncKey = selectedRoute == null
        ? null
        : '${selectedRoute.id}:${selectedRoute.nodes.length}';
    if (_lastPhaseSyncedRouteId == routeSyncKey) return;
    _lastPhaseSyncedRouteId = routeSyncKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = _locationService;
      final isNear =
          selectedRoute != null &&
          loc != null &&
          selectedRoute.nodes.isNotEmpty &&
          RevvRoute.haversineKm(
                LatLng(loc.lat, loc.lng),
                selectedRoute.nodes.first,
              ) <
              kRouteStartNearKm;
      _syncBrowsePhase(selectedRoute, isNearOverride: isNear);
    });
  }

  void _queueAlwaysListenSync(bool wantAlwaysListen) {
    if (_lastAlwaysListenWanted == wantAlwaysListen) return;
    _lastAlwaysListenWanted = wantAlwaysListen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncAlwaysListen();
    });
  }

  void _queueSprintLaunch() {
    if (_sprintLaunchQueued) return;
    _sprintLaunchQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sprintLaunchQueued = false;
      if (!mounted) return;
      context.read<RouteService>().clearSprintRequest();
      _goSprint();
    });
  }

  Future<void> _fetchNavRoute(RevvRoute route) async {
    final loc = context.read<LocationService>();
    final polyline = await DirectionsService.getRoute(
      LatLng(loc.lat, loc.lng),
      route.nodes.first,
    );
    if (!mounted) return;
    setState(() => _navPolyline = polyline);
  }

  void _goSprint() {
    if (_phase == _RidePhase.sprinting || _phase == _RidePhase.driving) return;
    final routeSvc = context.read<RouteService>();
    final route = routeSvc.sprintRoute ?? routeSvc.selectedRoute;
    final startMode = routeSvc.sprintStartMode;

    if (route != null) {
      final loc = context.read<LocationService>();
      final dist = RevvRoute.haversineKm(
        LatLng(loc.lat, loc.lng),
        route.nodes.first,
      );

      if (startMode == SprintStartMode.joinFromCurrent) {
        setState(() {
          _enterDrive();
          _driveRoute = route;
          _sprintRouteFocus = true;
          _activeStartMode = startMode;
        });
        return;
      }

      // 루트 시작점까지 거리 계산 → auto일 때 500m 이내면 DRIVE/NAV 선택 시트
      if (startMode == SprintStartMode.auto && dist <= kAutoSprintTriggerKm) {
        _showDriveOrNavSheet(route);
        return;
      }
    }

    setState(() {
      _enterSprint();
      _sprintRoute = route;
      _sprintNavPolyline = null;
      _sprintRouteFocus = false;
      _activeStartMode = startMode;
    });
  }

  void _showDriveOrNavSheet(RevvRoute route) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DriveOrNavSheet(
        route: route,
        onDrive: () {
          Navigator.pop(context);
          setState(() {
            _enterDrive();
            _driveRoute = route;
            _sprintRouteFocus = true;
            _activeStartMode = SprintStartMode.auto;
          });
        },
        onNav: () {
          Navigator.pop(context);
          setState(() {
            _enterSprint();
            _sprintRoute = route;
            _sprintNavPolyline = null;
            _sprintRouteFocus = false;
            _activeStartMode = SprintStartMode.auto;
          });
        },
      ),
    );
  }

  void _onSprintEnd(RunSession? session) {
    setState(() {
      _exitRide();
      _sprintRoute = null;
      _sprintNavPolyline = null;
      _sprintRouteFocus = false;
      _activeStartMode = SprintStartMode.auto;
    });
    if (session != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RunCardScreen(session: session)),
      );
    }
  }

  void _onDriveEnd(RunSession? session) {
    setState(() {
      _exitRide();
      _driveRoute = null;
      _activeStartMode = SprintStartMode.auto;
    });
    if (session != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RunCardScreen(session: session)),
      );
    }
  }

  void _openMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MoreSheet(
        onObd: () {
          Navigator.pop(context);
          OBDScreen.show(context);
        },
        onAi: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            backgroundColor: AppColors.panel,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (_) => const JarvisPanel(),
          );
        },
        onDriverLevel: () {
          Navigator.pop(context);
          DriverLevelSheet.show(context);
        },
        onAnalysis: () {
          Navigator.pop(context);
          AnalysisScreen.show(context);
        },
        onSettings: () {
          Navigator.pop(context);
          SettingsScreen.show(context);
        },
        onRanking: () {
          Navigator.pop(context);
          RankingScreen.show(context);
        },
        onMic: () {
          Navigator.pop(context);
        },
        onGarage: () {
          Navigator.pop(context);
          GarageScreen.show(context);
        },
        onSavedRoutes: () {
          Navigator.pop(context);
          SavedRoutesScreen.show(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠ context.watch<RouteService>() → context.select 로 교체:
    // watch는 RouteService의 모든 변경(loading, connecting 등)마다 CruiseScreen 전체 rebuild
    // → 스프린트 중 SprintScreen + MapWidget까지 연쇄 rebuild → platform view 충돌 유발
    // select는 필요한 속성만 감시 → 불필요한 rebuild 차단
    final selectedRoute = context.select<RouteService, RevvRoute?>(
      (r) => r.selectedRoute,
    );
    final sprintRequested = context.select<RouteService, bool>(
      (r) => r.sprintRequested,
    );
    // 항상듣기 설정 변화 감지 → 즉시 동기화
    final alwaysListen = context.select<SettingsService, bool>(
      (s) => s.alwaysListen,
    );

    _queuePhaseSync(selectedRoute);
    _queueAlwaysListenSync(alwaysListen);

    if (sprintRequested &&
        _phase != _RidePhase.sprinting &&
        _phase != _RidePhase.driving) {
      _queueSprintLaunch();
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        // ⚠ ValueKey 필수:
        // Stack 자식 리스트에 if 조건부 위젯이 있으면 Flutter가 INDEX 기반으로 매칭.
        // _isSprinting / selectedRoute / _nearRouteStart 변경 시 인덱스가 밀려서
        // 서로 다른 타입끼리 매칭 → RenderDecoratedBox not laid out / no size 에러.
        // ValueKey로 각 위젯의 정체성을 보장.
        body: Stack(
          children: [
            // ── 풀스크린 맵 ──
            // ClipRect + SizedBox.expand: platform view layout 변경이
            // 상위 Stack으로 전파되는 것을 차단 → !_debugDoingThisLayout 방지
            Positioned.fill(
              key: const ValueKey('cruise-map'),
              child: ClipRect(
                child: SizedBox.expand(
                  child: RepaintBoundary(
                    child: MapWidget(
                      isSprintMode:
                          _phase == _RidePhase.sprinting ||
                          _phase == _RidePhase.driving,
                      navPolyline: _phase == _RidePhase.sprinting
                          ? (_sprintRouteFocus ? null : _sprintNavPolyline)
                          : _navPolyline,
                      routePolyline: _phase == _RidePhase.sprinting
                          ? _sprintRoute?.nodes
                          : _phase == _RidePhase.driving
                          ? _driveRoute?.nodes
                          : selectedRoute?.nodes,
                      showCurveHeatmap:
                          _phase != _RidePhase.sprinting &&
                          _phase != _RidePhase.driving &&
                          _showCurveHeatmap &&
                          selectedRoute != null,
                      routeFocusMode:
                          (_phase == _RidePhase.sprinting &&
                              _sprintRouteFocus) ||
                          _phase == _RidePhase.driving,
                      recenterSignal: _recenterSignal,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.bg.withValues(alpha: 0.26),
                        Colors.transparent,
                        Colors.transparent,
                        AppColors.bg.withValues(alpha: 0.42),
                      ],
                      stops: const [0.0, 0.18, 0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // ── 상단 크루즈 앱바 ──
            if (_phase != _RidePhase.sprinting && _phase != _RidePhase.driving)
              Positioned(
                key: const ValueKey('top-bar'),
                top: 0,
                left: 0,
                right: 0,
                child: const _CruiseTopBar(),
              ),

            // ── 활성 루트 pill ──
            if (_phase == _RidePhase.idle)
              Positioned(
                key: const ValueKey('active-routes-pill'),
                top: MediaQuery.of(context).padding.top + 72,
                left: 0,
                right: 0,
                child: const Center(child: _ActiveRoutesPill()),
              ),

            // ── 루트 시작 근접 배너 ──
            if (_phase == _RidePhase.nearStart && selectedRoute != null)
              Positioned(
                key: const ValueKey('near-start'),
                top: MediaQuery.of(context).padding.top + 70,
                left: 14,
                right: 14,
                child: _NearStartBanner(
                  routeName: selectedRoute.name,
                  onSprint: _goSprint,
                ),
              ),

            // ── 루트 선택 카드 (하단 탭바 바로 위) ──
            if (_phase == _RidePhase.routeSelected && selectedRoute != null)
              Positioned(
                key: const ValueKey('route-card'),
                bottom: 96 + MediaQuery.of(context).padding.bottom,
                left: 12,
                right: 12,
                child: _RouteSelectedCard(
                  route: selectedRoute,
                  onGo: _goSprint,
                  onDismiss: () => context.read<RouteService>().deselectRoute(),
                ),
              ),

            // ── Sprint 오버레이 ──
            if (_phase == _RidePhase.sprinting)
              Positioned.fill(
                key: const ValueKey('sprint-overlay'),
                child: SprintScreen(
                  selectedRoute: _sprintRoute,
                  startMode: _activeStartMode,
                  onEnd: _onSprintEnd,
                  onNavPolylineChanged: (poly) {
                    if (mounted) setState(() => _sprintNavPolyline = poly);
                  },
                  onRouteFocusChanged: (focused) {
                    if (mounted) setState(() => _sprintRouteFocus = focused);
                  },
                ),
              ),

            // ── Drive 오버레이 (미니멀 HUD) ──
            if (_phase == _RidePhase.driving)
              Positioned.fill(
                key: const ValueKey('drive-overlay'),
                child: DriveScreen(
                  selectedRoute: _driveRoute,
                  startMode: _activeStartMode,
                  onEnd: _onDriveEnd,
                ),
              ),

            // ── 우측 맵 컨트롤 ──
            if (_phase == _RidePhase.idle)
              Positioned(
                key: const ValueKey('map-controls'),
                right: 14,
                top: MediaQuery.of(context).size.height * 0.42,
                child: _MapControlRail(
                  onRecenter: () async {
                    final loc = context.read<LocationService>();
                    await loc.ensureLiveLocation();
                    if (!mounted) return;
                    setState(() => _recenterSignal++);
                  },
                ),
              ),

            // ── 커브 히트맵 토글 버튼 ──
            if (_phase == _RidePhase.idle)
              Positioned(
                key: const ValueKey('idle-prompt'),
                left: 14,
                right: 14,
                bottom: 82 + MediaQuery.of(context).padding.bottom,
                child: const _RecommendedRoutesSheet(),
              ),

            if (_phase == _RidePhase.routeSelected && selectedRoute != null)
              Positioned(
                key: const ValueKey('heatmap-btn'),
                right: 14,
                bottom: 214 + MediaQuery.of(context).padding.bottom,
                child: _TapScale(
                  onTap: () =>
                      setState(() => _showCurveHeatmap = !_showCurveHeatmap),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _showCurveHeatmap
                          ? AppColors.red.withValues(alpha: 0.9)
                          : Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _showCurveHeatmap
                            ? AppColors.red
                            : Colors.white.withValues(alpha: 0.15),
                      ),
                      boxShadow: const [],
                    ),
                    child: const Icon(
                      Icons.thermostat_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // ── 항상듣기 인디케이터 ──
            if (_phase != _RidePhase.sprinting &&
                _phase != _RidePhase.driving &&
                _alwaysListening)
              Positioned(
                key: const ValueKey('always-listen-dot'),
                top: MediaQuery.of(context).padding.top + 14,
                right: 14,
                child: const _AlwaysListenDot(),
              ),

            // ── 하단 탭바 ──
            if (_phase != _RidePhase.sprinting && _phase != _RidePhase.driving)
              Positioned(
                key: const ValueKey('bottom-nav'),
                bottom: 0,
                left: 0,
                right: 0,
                child: _BottomNavBar(
                  activeTab: _activeTab,
                  goLabel: _phase == _RidePhase.idle
                      ? RevvCopy.routeFinder
                      : RevvCopy.startDrive,
                  goIcon: _phase == _RidePhase.idle
                      ? Icons.search_rounded
                      : Icons.navigation_rounded,
                  onRoutes: () {
                    setState(() => _activeTab = 0);
                    Navigator.push(
                      context,
                      _slideUpRoute(const RoutesScreen()),
                    );
                  },
                  onGo: () {
                    if (_phase == _RidePhase.idle) {
                      setState(() => _activeTab = 0);
                      Navigator.push(
                        context,
                        _slideUpRoute(const RoutesScreen()),
                      );
                      return;
                    }
                    _goSprint();
                  },
                  onLog: () {
                    setState(() => _activeTab = 3);
                    Navigator.push(
                      context,
                      _slideUpRoute(const HistoryScreen()),
                    );
                  },
                  onMore: () {
                    setState(() => _activeTab = 4);
                    _openMore();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 탭 스케일 피드백 — 모든 버튼에 재사용
// ══════════════════════════════════════════════════════════════════
class _TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _TapScale({required this.child, this.onTap});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
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
        child: widget.child,
      ),
    );
  }
}

class _CruiseTopBar extends StatelessWidget {
  const _CruiseTopBar();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.60),
        border: Border(
          bottom: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.20),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.06),
            blurRadius: 15,
          ),
        ],
      ),
      child: Row(
        children: [
          Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 20,
                color: AppColors.primaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'REVV',
                style: AppText.body(
                  size: 18,
                  weight: FontWeight.w900,
                  color: AppColors.primaryContainer,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'GPS LOCK',
                  style: AppText.technicalLabel(
                    size: 9,
                    color: AppColors.primaryContainer,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryContainer,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryContainer.withValues(
                          alpha: 0.8,
                        ),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.battery_charging_full_rounded,
            size: 20,
            color: AppColors.primaryContainer,
          ),
        ],
      ),
    );
  }
}

class _ActiveRoutesPill extends StatelessWidget {
  const _ActiveRoutesPill();

  @override
  Widget build(BuildContext context) {
    final count = context.select<RouteService, int>((r) => r.routes.length);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.30),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.alt_route_rounded,
            size: 16,
            color: AppColors.onPrimary,
          ),
          const SizedBox(width: 8),
          Text(
            count == 0 ? '주변 루트 찾는 중' : '추천 루트 $count개',
            style: AppText.technicalLabel(
              size: 11,
              color: AppColors.onPrimary,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapControlRail extends StatelessWidget {
  final Future<void> Function() onRecenter;

  const _MapControlRail({required this.onRecenter});

  @override
  Widget build(BuildContext context) {
    return _TapScale(
      onTap: onRecenter,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location_rounded,
          color: AppColors.onPrimary,
          size: 22,
        ),
      ),
    );
  }
}

class _RecommendedRoutesSheet extends StatelessWidget {
  const _RecommendedRoutesSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (_, svc, _) {
        final selectedRoute = svc.selectedRoute;
        final feed = <RevvRoute>[
          ?selectedRoute,
          ...svc.routes.where((route) => route.id != selectedRoute?.id),
        ];
        final routes = feed.take(6).toList();
        return RevvGlassCard(
          padding: EdgeInsets.zero,
          radius: 20,
          color: AppColors.panel2.withValues(alpha: 0.95),
          glow: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '추천 피드',
                            style: AppText.technicalLabel(
                              size: 10,
                              color: AppColors.primaryContainer,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '근처에서 바로 달릴 루트',
                            style: AppText.body(
                              size: 20,
                              weight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          _slideUpRoute(const RoutesScreen()),
                        );
                      },
                      child: Text(
                        'VIEW ALL',
                        style: AppText.technicalLabel(
                          size: 10,
                          color: AppColors.primaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 166,
                child: routes.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              svc.isLoadingInitial
                                  ? '현재 위치 기준으로 루트를 분석하는 중이에요.'
                                  : svc.routeDataStatusTitle ??
                                        '아직 추천 루트가 없어요.',
                              style: AppText.body(
                                size: 14,
                                weight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              svc.routeDataStatusBody ??
                                  '루트 찾기에서 지도를 움직여 다시 찾거나 탐색 반경을 넓혀보세요.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(
                                size: 12,
                                height: 1.3,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _MiniDataSourcePill(
                              label: svc.routeDataSourceLabel,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        scrollDirection: Axis.horizontal,
                        itemCount: routes.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _RecommendedRouteCard(
                          route: routes[i],
                          onTap: () {
                            svc.selectRoute(routes[i]);
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniDataSourcePill extends StatelessWidget {
  final String label;

  const _MiniDataSourcePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.storage_rounded,
            size: 12,
            color: AppColors.textHint,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.body(
              size: 11,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedRouteCard extends StatelessWidget {
  final RevvRoute route;
  final VoidCallback onTap;

  const _RecommendedRouteCard({required this.route, required this.onTap});

  Color _accent() {
    switch (route.difficultyLevel) {
      case 4:
        return const Color(0xFFEF4444);
      case 3:
        return const Color(0xFFF97316);
      case 2:
        return const Color(0xFFF59E0B);
      case 1:
        return const Color(0xFF22C55E);
      default:
        return AppColors.primaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return _TapScale(
      onTap: onTap,
      child: Container(
        width: 248,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 92,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.70),
                    AppColors.surfaceLowest,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${route.starRating.toStringAsFixed(1)} ★',
                        style: AppText.technicalLabel(
                          size: 9,
                          color: AppColors.primaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${route.distanceDisplay} • ${route.curveStyle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.technicalLabel(
                            size: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.primaryContainer,
                      ),
                    ],
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

// ══════════════════════════════════════════════════════════════════
// 상단 플로팅 HUD — 투명 필 오버레이 (Timer로 매초 갱신)
// ══════════════════════════════════════════════════════════════════
class _TopFloatingHud extends StatefulWidget {
  const _TopFloatingHud();

  @override
  State<_TopFloatingHud> createState() => _TopFloatingHudState();
}

class _TopFloatingHudState extends State<_TopFloatingHud> {
  late String _time;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _time = _formatted();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _time = _formatted());
    });
  }

  String _formatted() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: RevvGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.panel.withValues(alpha: 0.78),
            child: Consumer<LocationService>(
              builder: (_, loc, _) => Row(
                children: [
                  const Icon(
                    Icons.navigation_rounded,
                    size: 14,
                    color: AppColors.primaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CRUISE READY',
                          style: AppText.technicalLabel(
                            size: 9,
                            color: AppColors.primaryContainer,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          loc.hasPermission
                              ? 'GPS ${loc.speedKmh.toStringAsFixed(0)} km/h'
                              : 'GPS waiting',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Consumer<WeatherService>(
          builder: (_, w, _) => RevvGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: AppColors.panel.withValues(alpha: 0.82),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(w.weatherEmoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  w.tempDisplay,
                  style: AppText.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Container(
                  width: 1,
                  height: 13,
                  color: Colors.white.withValues(alpha: 0.15),
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                ),
                Text(
                  _time,
                  style: _techUiStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 루트 선택 카드 — 하단 탭바 위 플로팅
// ══════════════════════════════════════════════════════════════════
class _RouteSelectedCard extends StatefulWidget {
  final RevvRoute route;
  final VoidCallback onGo;
  final VoidCallback onDismiss;
  const _RouteSelectedCard({
    required this.route,
    required this.onGo,
    required this.onDismiss,
  });

  @override
  State<_RouteSelectedCard> createState() => _RouteSelectedCardState();
}

class _RouteSelectedCardState extends State<_RouteSelectedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 260),
      vsync: this,
    );
    _slide = Tween(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _diffColor(int level) {
    switch (level) {
      case 4:
        return const Color(0xFFEF4444);
      case 3:
        return const Color(0xFFF97316);
      case 2:
        return const Color(0xFFF59E0B);
      case 1:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectingRoutes = context.select<RouteService, List<ChainCandidate>>(
      (r) => r.connectingRoutes,
    );
    final selectedCompositeRoute = context
        .select<RouteService, CompositeRoute?>((r) => r.selectedCompositeRoute);
    final diffColor = _diffColor(widget.route.difficultyLevel);
    final hasChain = connectingRoutes.isNotEmpty;
    final totalChainKm =
        selectedCompositeRoute?.totalDistanceKm ?? widget.route.distanceKm;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Dismissible(
          key: ValueKey('route-card-${widget.route.id}'),
          direction: DismissDirection.down,
          onDismissed: (_) => widget.onDismiss(),
          child: _buildCard(
            context,
            diffColor,
            hasChain,
            totalChainKm,
            connectingRoutes,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    Color diffColor,
    bool hasChain,
    double totalChainKm,
    List<ChainCandidate> connectingRoutes,
  ) {
    return RevvGlassCard(
      padding: EdgeInsets.zero,
      color: AppColors.panel.withValues(alpha: 0.92),
      glow: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 3, color: diffColor.withValues(alpha: 0.9)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: diffColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.route.difficultyLabel,
                                style: AppText.technicalLabel(
                                  size: 10,
                                  color: diffColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.route.name,
                                style: AppText.body(
                                  size: 20,
                                  weight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.4,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            _StatChip(
                              icon: Icons.straighten,
                              value: widget.route.distanceDisplay,
                            ),
                            const SizedBox(width: 10),
                            _StatChip(
                              icon: Icons.schedule,
                              value: widget.route.durationDisplay,
                            ),
                            if (widget.route.windingDensityPct > 0) ...[
                              const SizedBox(width: 10),
                              _StatChip(
                                icon: Icons.turn_right,
                                value:
                                    '${widget.route.windingDensityPct.toStringAsFixed(0)}%',
                                color: diffColor,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '지도에서 선택한 루트예요. 바로 주행하거나 루트 찾기에서 편집할 수 있어요.',
                          style: AppText.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TapScale(
                        onTap: widget.onGo,
                        child: Container(
                          width: 92,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryContainer.withValues(
                                  alpha: 0.24,
                                ),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '주행',
                              style: AppText.body(
                                size: 14,
                                weight: FontWeight.w900,
                                color: AppColors.onPrimary,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (hasChain) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            final rs = context.read<RouteService>();
                            rs.requestSprint(
                              route: rs.selectedCompositeRoute
                                  ?.toRouteProjection(),
                            );
                          },
                          child: Container(
                            width: 92,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.link,
                                  size: 10,
                                  color: AppColors.primaryContainer,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${totalChainKm.toStringAsFixed(0)}km',
                                  style: AppText.technicalLabel(
                                    size: 10,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 6),
                  _TapScale(
                    onTap: widget.onDismiss,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.72),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.24,
                          ),
                        ),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── 미니 고도 프로파일 ──────────────────────────────
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _StatChip({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: c),
        const SizedBox(width: 3),
        Text(
          value,
          style: AppText.body(size: 12, weight: FontWeight.w600, color: c),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 루트 시작 근접 배너 — 진입 슬라이드 + 펄싱 도트
// ══════════════════════════════════════════════════════════════════
class _NearStartBanner extends StatefulWidget {
  final String routeName;
  final VoidCallback onSprint;
  const _NearStartBanner({required this.routeName, required this.onSprint});

  @override
  State<_NearStartBanner> createState() => _NearStartBannerState();
}

class _NearStartBannerState extends State<_NearStartBanner>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slide = Tween(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: RevvGlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          color: AppColors.panel.withValues(alpha: 0.92),
          glow: true,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.warning.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'START POINT LOCKED',
                      style: AppText.technicalLabel(
                        size: 9,
                        color: AppColors.warning,
                      ),
                    ),
                    Text(
                      widget.routeName,
                      style: AppText.body(
                        size: 18,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _TapScale(
                onTap: widget.onSprint,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'ENTER',
                    style: AppText.body(
                      size: 13,
                      weight: FontWeight.w900,
                      color: AppColors.onPrimary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 하단 네비게이션 바 — 가운데 GO 원형 버튼 히어로
// ══════════════════════════════════════════════════════════════════
class _BottomNavBar extends StatelessWidget {
  final int activeTab;
  final String goLabel;
  final IconData goIcon;
  final VoidCallback onRoutes;
  final VoidCallback onGo;
  final VoidCallback onLog;
  final VoidCallback onMore;

  const _BottomNavBar({
    required this.activeTab,
    required this.goLabel,
    required this.goIcon,
    required this.onRoutes,
    required this.onGo,
    required this.onLog,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return RevvGlassCard(
      padding: EdgeInsets.zero,
      radius: 30,
      color: AppColors.bg.withValues(alpha: 0.86),
      child: SizedBox(
        height: 64 + bottomPad,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NavItem(
              icon: Icons.route_outlined,
              activeIcon: Icons.route,
              label: '루트',
              active: activeTab == 0,
              onTap: onRoutes,
            ),
            // GO 히어로 버튼
            Expanded(
              child: _TapScale(
                onTap: onGo,
                child: SizedBox(
                  height: 64,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: -18,
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.bg, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryContainer.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 22,
                                spreadRadius: 3,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: AppColors.primaryContainer.withValues(
                                  alpha: 0.2,
                                ),
                                blurRadius: 44,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                goIcon,
                                size: 20,
                                color: AppColors.onPrimary,
                              ),
                              Text(
                                goLabel,
                                style: AppText.technicalLabel(
                                  size: goLabel.length > 4 ? 7 : 9,
                                  color: AppColors.onPrimary,
                                  letterSpacing: goLabel.length > 4 ? 0.4 : 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _NavItem(
              icon: Icons.history,
              activeIcon: Icons.history,
              label: RevvCopy.runHistory,
              active: activeTab == 3,
              onTap: onLog,
            ),
            _NavItem(
              icon: Icons.more_horiz,
              activeIcon: Icons.more_horiz,
              label: '메뉴',
              active: activeTab == 4,
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _TapScale(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  active ? activeIcon : icon,
                  key: ValueKey(active),
                  size: 23,
                  color: active ? AppColors.primaryContainer : Colors.white30,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.technicalLabel(
                  size: 9,
                  color: active ? AppColors.primaryContainer : Colors.white30,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: active ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// MORE 바텀시트
// ══════════════════════════════════════════════════════════════════
class _MoreSheet extends StatelessWidget {
  final VoidCallback onObd;
  final VoidCallback onAi;
  final VoidCallback onDriverLevel;
  final VoidCallback onAnalysis;
  final VoidCallback onSettings;
  final VoidCallback onRanking;
  final VoidCallback onMic;
  final VoidCallback onGarage;
  final VoidCallback onSavedRoutes;

  const _MoreSheet({
    required this.onObd,
    required this.onAi,
    required this.onDriverLevel,
    required this.onAnalysis,
    required this.onSettings,
    required this.onRanking,
    required this.onMic,
    required this.onGarage,
    required this.onSavedRoutes,
  });

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: EdgeInsets.zero,
      radius: 24,
      color: AppColors.panel.withValues(alpha: 0.96),
      glow: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outline.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SYSTEM ACCESS',
                        style: AppText.technicalLabel(
                          size: 10,
                          color: AppColors.primaryContainer,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '메뉴',
                        style: AppText.body(
                          size: 22,
                          weight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _MoreItem(
            icon: Icons.speed_rounded,
            label: 'OBD 진단',
            sub: '연결하면 RPM과 차량 상태 분석 정확도가 올라가요',
            onTap: onObd,
          ),
          _MoreItem(
            icon: Icons.directions_car_rounded,
            label: 'Garage Pro',
            sub: '차량 정보를 넣으면 G미터 기준이 더 정확해져요',
            onTap: onGarage,
          ),
          _MoreItem(
            icon: Icons.favorite_rounded,
            label: RevvCopy.savedRoutes,
            sub: '좋아하는 코스를 다시 열고 바로 달려요',
            onTap: onSavedRoutes,
          ),
          _MoreItem(
            icon: Icons.settings_rounded,
            label: RevvCopy.vehicleSettings,
            sub: '음성 안내·탐색 반경·주행 화면 조정',
            onTap: onSettings,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '처음엔 루트 찾기와 주행 시작만 써도 충분해요. 차량/OBD 설정은 나중에 정확도를 높이고 싶을 때 열면 됩니다.',
                style: AppText.body(
                  size: 13,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }
}

class _MoreItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _MoreItem({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: AppColors.primaryContainer),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    sub,
                    style: AppText.body(size: 11, color: AppColors.textHint),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// DriveOrNav 선택 시트 — 루트 시작점 3km 이내 시 표시
// ══════════════════════════════════════════════════════════════════
class _DriveOrNavSheet extends StatelessWidget {
  final RevvRoute route;
  final VoidCallback onDrive;
  final VoidCallback onNav;

  const _DriveOrNavSheet({
    required this.route,
    required this.onDrive,
    required this.onNav,
  });

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: EdgeInsets.zero,
      radius: 24,
      color: AppColors.panel.withValues(alpha: 0.96),
      glow: true,
      margin: EdgeInsets.zero,
      borderOpacity: 0.28,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              route.name,
              style: AppText.technicalLabel(
                size: 11,
                color: AppColors.primaryContainer,
                letterSpacing: 1.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '루트 시작점 근처예요. 어떻게 시작할까요?',
              style: AppText.body(size: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SheetOptionBtn(
                    icon: Icons.speed,
                    title: 'DRIVE',
                    subtitle: '미니멀 HUD\nG포스 + 속도',
                    color: AppColors.cyan,
                    onTap: onDrive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetOptionBtn(
                    icon: Icons.navigation,
                    title: 'NAV',
                    subtitle: '풀 내비게이션\n턴바이턴 안내',
                    color: AppColors.red,
                    onTap: onNav,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOptionBtn extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SheetOptionBtn({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SheetOptionBtn> createState() => _SheetOptionBtnState();
}

class _SheetOptionBtnState extends State<_SheetOptionBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.color.withValues(alpha: 0.34)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 22, color: widget.color),
              const SizedBox(height: 8),
              Text(
                widget.title,
                style: AppText.technicalLabel(
                  size: 13,
                  color: widget.color,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: AppText.body(
                  size: 11,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 항상듣기 인디케이터 — 우상단 pulsing dot
// ══════════════════════════════════════════════════════════════════
class _AlwaysListenDot extends StatefulWidget {
  const _AlwaysListenDot();

  @override
  State<_AlwaysListenDot> createState() => _AlwaysListenDotState();
}

class _AlwaysListenDotState extends State<_AlwaysListenDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulse = Tween(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.cyan.withValues(alpha: _pulse.value * 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withValues(alpha: _pulse.value),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'LISTENING',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.cyan.withValues(alpha: _pulse.value),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
