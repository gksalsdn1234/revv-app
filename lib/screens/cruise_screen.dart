import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../widgets/map_widget.dart';
import '../widgets/jarvis_panel.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/route_service.dart';
import '../services/directions_service.dart';
import '../models/run_session.dart';
import 'sprint_screen.dart';
import 'run_card_screen.dart';
import 'routes_screen.dart';
import 'obd_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'analysis_screen.dart';
import 'ranking_screen.dart';
import '../widgets/driver_level_card.dart';

PageRouteBuilder<T> _slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, __, ___) => page,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 280),
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

class CruiseScreen extends StatefulWidget {
  const CruiseScreen({super.key});

  @override
  State<CruiseScreen> createState() => _CruiseScreenState();
}

class _CruiseScreenState extends State<CruiseScreen> {
  List<LatLng>? _navPolyline;
  RevvRoute? _lastFetchedRoute;
  bool _nearRouteStart = false;
  LocationService? _locationService;
  int _activeTab = 0;

  // ── Sprint 오버레이 상태 ──
  bool _isSprinting = false;
  bool _showCurveHeatmap = false;
  RevvRoute? _sprintRoute;
  List<LatLng>? _sprintNavPolyline;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loc = context.read<LocationService>();
      _locationService = loc;
      await loc.requestPermission();
      if (loc.hasPermission) {
        await loc.startTracking();
        if (mounted) context.read<WeatherService>().fetchWeather(loc.lat, loc.lng);
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

  @override
  void dispose() {
    _locationService?.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    final route = context.read<RouteService>().selectedRoute;
    if (route == null) return;
    if (route != _lastFetchedRoute) {
      _lastFetchedRoute = route;
      _fetchNavRoute(route);
    }
    final loc = context.read<LocationService>();
    final dist = RevvRoute.haversineKm(LatLng(loc.lat, loc.lng), route.nodes.first);
    final isNear = dist < 0.3;
    if (isNear != _nearRouteStart) {
      setState(() => _nearRouteStart = isNear);
    }
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
    if (_isSprinting) return;
    final routeSvc = context.read<RouteService>();
    final route = routeSvc.sprintRoute ?? routeSvc.selectedRoute;
    setState(() {
      _isSprinting = true;
      _sprintRoute = route;
      _sprintNavPolyline = null;
    });
  }

  void _onSprintEnd(RunSession? session) {
    setState(() {
      _isSprinting = false;
      _sprintRoute = null;
      _sprintNavPolyline = null;
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
        onObd: () { Navigator.pop(context); OBDScreen.show(context); },
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
        onDriverLevel: () { Navigator.pop(context); DriverLevelSheet.show(context); },
        onAnalysis: () { Navigator.pop(context); AnalysisScreen.show(context); },
        onSettings: () { Navigator.pop(context); SettingsScreen.show(context); },
        onRanking: () { Navigator.pop(context); RankingScreen.show(context); },
        onMic: () { Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠ context.watch<RouteService>() → context.select 로 교체:
    // watch는 RouteService의 모든 변경(loading, connecting 등)마다 CruiseScreen 전체 rebuild
    // → 스프린트 중 SprintScreen + MapWidget까지 연쇄 rebuild → platform view 충돌 유발
    // select는 필요한 속성만 감시 → 불필요한 rebuild 차단
    final selectedRoute = context.select<RouteService, RevvRoute?>((r) => r.selectedRoute);
    final sprintRequested = context.select<RouteService, bool>((r) => r.sprintRequested);

    if (sprintRequested && !_isSprinting) {
      context.read<RouteService>().clearSprintRequest();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goSprint();
      });
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
                      isSprintMode: _isSprinting,
                      navPolyline: _isSprinting ? _sprintNavPolyline : _navPolyline,
                      routePolyline: _isSprinting
                          ? _sprintRoute?.nodes
                          : selectedRoute?.nodes,
                      showCurveHeatmap: !_isSprinting && _showCurveHeatmap && selectedRoute != null,
                    ),
                  ),
                ),
              ),
            ),

            // ── 상단 플로팅 HUD ──
            if (!_isSprinting)
              Positioned(
                key: const ValueKey('top-hud'),
                top: MediaQuery.of(context).padding.top + 10,
                left: 14,
                right: 14,
                child: const _TopFloatingHud(),
              ),

            // ── 속도 게이지 (좌하단 플로팅) ──
            if (!_isSprinting)
              Positioned(
                key: const ValueKey('speed-gauge'),
                bottom: 80 + MediaQuery.of(context).padding.bottom + 18,
                left: 14,
                child: const _SpeedGauge(),
              ),

            // ── 루트 시작 근접 배너 ──
            if (!_isSprinting && _nearRouteStart && selectedRoute != null)
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
            if (!_isSprinting && selectedRoute != null)
              Positioned(
                key: const ValueKey('route-card'),
                bottom: 74 + MediaQuery.of(context).padding.bottom,
                left: 0,
                right: 0,
                child: _RouteSelectedCard(
                  route: selectedRoute,
                  onGo: _goSprint,
                  onDismiss: () => context.read<RouteService>().deselectRoute(),
                ),
              ),

            // ── Sprint 오버레이 ──
            if (_isSprinting)
              Positioned.fill(
                key: const ValueKey('sprint-overlay'),
                child: SprintScreen(
                  selectedRoute: _sprintRoute,
                  onEnd: _onSprintEnd,
                  onNavPolylineChanged: (poly) {
                    if (mounted) setState(() => _sprintNavPolyline = poly);
                  },
                ),
              ),

            // ── 커브 히트맵 토글 버튼 ──
            if (!_isSprinting && selectedRoute != null)
              Positioned(
                key: const ValueKey('heatmap-btn'),
                right: 14,
                bottom: 84 + MediaQuery.of(context).padding.bottom,
                child: _TapScale(
                  onTap: () => setState(() => _showCurveHeatmap = !_showCurveHeatmap),
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
                      boxShadow: _showCurveHeatmap
                          ? [BoxShadow(color: AppColors.red.withValues(alpha: 0.4), blurRadius: 12)]
                          : [],
                    ),
                    child: const Icon(Icons.thermostat_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),

            // ── 하단 탭바 ──
            if (!_isSprinting)
              Positioned(
                key: const ValueKey('bottom-nav'),
                bottom: 0,
                left: 0,
                right: 0,
                child: _BottomNavBar(
                  activeTab: _activeTab,
                  onRoutes: () {
                    setState(() => _activeTab = 0);
                    Navigator.push(context, _slideUpRoute(const RoutesScreen()));
                  },
                  onGo: _goSprint,
                  onLog: () {
                    setState(() => _activeTab = 3);
                    Navigator.push(context, _slideUpRoute(const HistoryScreen()));
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
        const Spacer(),
        Consumer<WeatherService>(
          builder: (_, w, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(w.weatherEmoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  w.tempDisplay,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                Container(
                  width: 1, height: 13,
                  color: Colors.white.withValues(alpha: 0.15),
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                ),
                Text(
                  _time,
                  style: GoogleFonts.orbitron(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
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
// 속도 게이지 — 원형, 항상 좌하단
// ══════════════════════════════════════════════════════════════════
class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge();

  @override
  Widget build(BuildContext context) {
    return Consumer<LocationService>(
      builder: (_, loc, __) {
        final speed = loc.hasPermission ? loc.speedKmh.toStringAsFixed(0) : '--';
        return Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.18),
                blurRadius: 20,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                speed,
                style: GoogleFonts.orbitron(
                  fontSize: 23, fontWeight: FontWeight.w900,
                  color: Colors.white, height: 1.0,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'km/h',
                style: GoogleFonts.rajdhani(
                  fontSize: 8, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, letterSpacing: 1,
                ),
              ),
            ],
          ),
        );
      },
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
  const _RouteSelectedCard({required this.route, required this.onGo, required this.onDismiss});

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
    _slide = Tween(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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
      case 4: return const Color(0xFFEF4444);
      case 3: return const Color(0xFFF97316);
      case 2: return const Color(0xFFF59E0B);
      case 1: return const Color(0xFF22C55E);
      default: return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectingRoutes = context.select<RouteService, List<RevvRoute>>((r) => r.connectingRoutes);
    final diffColor = _diffColor(widget.route.difficultyLevel);
    final hasChain = connectingRoutes.isNotEmpty;
    final totalChainKm = widget.route.distanceKm +
        connectingRoutes.fold<double>(0, (s, r) => s + r.distanceKm);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Dismissible(
          key: ValueKey('route-card-${widget.route.id}'),
          direction: DismissDirection.down,
          onDismissed: (_) => widget.onDismiss(),
          child: _buildCard(context, diffColor, hasChain, totalChainKm, connectingRoutes),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, Color diffColor, bool hasChain,
      double totalChainKm, List<RevvRoute> connectingRoutes) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: diffColor.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 28, offset: const Offset(0, 8)),
          BoxShadow(color: diffColor.withValues(alpha: 0.1), blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 3, color: diffColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 10, 12),
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: diffColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.route.difficultyLabel,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 9, fontWeight: FontWeight.w800,
                                  color: diffColor, letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.route.name,
                                style: GoogleFonts.orbitron(
                                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
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
                            _StatChip(icon: Icons.straighten, value: widget.route.distanceDisplay),
                            const SizedBox(width: 12),
                            _StatChip(icon: Icons.schedule, value: widget.route.durationDisplay),
                            if (widget.route.windingDensityPct > 0) ...[
                              const SizedBox(width: 12),
                              _StatChip(
                                icon: Icons.turn_right,
                                value: '${widget.route.windingDensityPct.toStringAsFixed(0)}%',
                                color: diffColor,
                              ),
                            ],
                          ],
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
                          width: 76,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.red.withValues(alpha: 0.55),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'GO',
                              style: GoogleFonts.orbitron(
                                fontSize: 16, fontWeight: FontWeight.w900,
                                color: Colors.white, letterSpacing: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (hasChain) ...[
                        const SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            final rs = context.read<RouteService>();
                            final allNodes = <LatLng>[...widget.route.nodes, ...rs.connectingRoutes.expand((r) => r.nodes)];
                            rs.requestSprint(
                              route: widget.route.copyWith(
                                id: '${widget.route.id}_chain',
                                name: '${widget.route.name} +${rs.connectingRoutes.length}',
                                nodes: allNodes,
                                distanceKm: totalChainKm,
                              ),
                            );
                          },
                          child: Container(
                            width: 76,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.link, size: 9, color: AppColors.red),
                                const SizedBox(width: 3),
                                Text(
                                  '${totalChainKm.toStringAsFixed(0)}km',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white,
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
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white70),
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
          style: GoogleFonts.rajdhani(
            fontSize: 12, fontWeight: FontWeight.w600, color: c,
          ),
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
  late final AnimationController _pulseCtrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);

    _slide = Tween(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _pulse = Tween<double>(begin: 0.35, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0808),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // 펄싱 도트
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Opacity(
                  opacity: _pulse.value,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.red.withValues(alpha: _pulse.value * 0.8),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시작 지점 근처',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.red, letterSpacing: 1,
                      ),
                    ),
                    Text(
                      widget.routeName,
                      style: GoogleFonts.orbitron(
                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
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
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    'START',
                    style: GoogleFonts.orbitron(
                      fontSize: 11, fontWeight: FontWeight.w900,
                      color: Colors.white, letterSpacing: 2,
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
  final VoidCallback onRoutes;
  final VoidCallback onGo;
  final VoidCallback onLog;
  final VoidCallback onMore;

  const _BottomNavBar({
    required this.activeTab,
    required this.onRoutes,
    required this.onGo,
    required this.onLog,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2101012),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SizedBox(
        height: 64 + bottomPad,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NavItem(
              icon: Icons.route_outlined,
              activeIcon: Icons.route,
              label: 'ROUTES',
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
                            color: AppColors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xF2101012), width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.red.withValues(alpha: 0.65),
                                blurRadius: 22,
                                spreadRadius: 3,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: AppColors.red.withValues(alpha: 0.2),
                                blurRadius: 44,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.navigation_rounded, size: 20, color: Colors.white),
                              Text(
                                'GO',
                                style: GoogleFonts.orbitron(
                                  fontSize: 9, fontWeight: FontWeight.w900,
                                  color: Colors.white, letterSpacing: 2,
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
              label: 'LOG',
              active: activeTab == 3,
              onTap: onLog,
            ),
            _NavItem(
              icon: Icons.more_horiz,
              activeIcon: Icons.more_horiz,
              label: 'MORE',
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
                  color: active ? AppColors.red : Colors.white30,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 8, fontWeight: FontWeight.w700,
                  color: active ? AppColors.red : Colors.white30,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: active ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.red,
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

  const _MoreSheet({
    required this.onObd,
    required this.onAi,
    required this.onDriverLevel,
    required this.onAnalysis,
    required this.onSettings,
    required this.onRanking,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131315),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          _MoreItem(
            icon: Icons.speed_rounded,
            label: 'OBD 진단',
            sub: '실시간 차량 데이터',
            onTap: onObd,
          ),
          _MoreItem(
            icon: Icons.auto_awesome_rounded,
            label: 'Jarvis AI',
            sub: '드라이빙 브리핑',
            onTap: onAi,
          ),
          _MoreItem(
            icon: Icons.emoji_events_rounded,
            label: '드라이버 프로필',
            sub: '레벨 · 마일스톤 · 통계',
            onTap: onDriverLevel,
          ),
          _MoreItem(
            icon: Icons.analytics_rounded,
            label: '드라이버 분석',
            sub: 'AI 주행 데이터 분석',
            onTap: onAnalysis,
          ),
          _MoreItem(
            icon: Icons.mic_rounded,
            label: '마이크',
            sub: '음성 명령',
            onTap: onMic,
          ),
          _MoreItem(
            icon: Icons.emoji_events_rounded,
            label: '랭킹',
            sub: '인기 루트 · 챌린지 · 내 기록',
            onTap: onRanking,
          ),
          _MoreItem(
            icon: Icons.settings_rounded,
            label: '설정',
            sub: '앱 환경설정',
            onTap: onSettings,
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
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 21, color: AppColors.red),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                    ),
                  ),
                  Text(
                    sub,
                    style: GoogleFonts.rajdhani(
                      fontSize: 11, color: Colors.white38,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}
