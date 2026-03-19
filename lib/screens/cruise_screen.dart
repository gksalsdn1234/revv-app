import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../widgets/hud_bar.dart';
import '../widgets/map_widget.dart';
import '../widgets/jarvis_panel.dart';
import '../widgets/mic_button.dart';
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

class CruiseScreen extends StatefulWidget {
  const CruiseScreen({super.key});

  @override
  State<CruiseScreen> createState() => _CruiseScreenState();
}

class _CruiseScreenState extends State<CruiseScreen> {
  List<LatLng>? _navPolyline;
  RevvRoute? _lastFetchedRoute;
  bool _nearRouteStart = false;
  bool _menuOpen = false;
  LocationService? _locationService;

  // ── Sprint 오버레이 상태 (ANR 방지: MapWidget 하나만 유지) ──
  bool _isSprinting = false;
  RevvRoute? _sprintRoute;
  List<LatLng>? _sprintNavPolyline; // SprintScreen에서 받아온 nav 경로

  @override
  void initState() {
    super.initState();
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

    // 루트 선택 시 내비 경로 한 번만 fetch
    if (route != _lastFetchedRoute) {
      _lastFetchedRoute = route;
      _fetchNavRoute(route);
    }

    // 루트 시작점 근접 감지 (300m)
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

  // Sprint 시작 — Navigator push 없이 오버레이로 전환 (ANR 방지)
  void _goSprint() {
    if (_isSprinting) return;
    final routeSvc = context.read<RouteService>();
    // sprintRoute가 있으면 (CHAIN 전체 코스 등) 우선 사용, 없으면 selectedRoute
    final route = routeSvc.sprintRoute ?? routeSvc.selectedRoute;
    setState(() {
      _isSprinting = true;
      _sprintRoute = route;
      _sprintNavPolyline = null;
      _menuOpen = false;
    });
  }

  // Sprint 종료 콜백 — SprintScreen이 호출
  void _onSprintEnd(RunSession? session) {
    setState(() {
      _isSprinting = false;
      _sprintRoute = null;
      _sprintNavPolyline = null;
    });
    if (session != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RunCardScreen(session: session),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeSvc = context.watch<RouteService>();
    final selectedRoute = routeSvc.selectedRoute;

    // routes_bottom_sheet에서 requestSprint() 호출 감지
    if (routeSvc.sprintRequested && !_isSprinting) {
      routeSvc.clearSprintRequest();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goSprint();
      });
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Stack(
            children: [
              // ── 풀스크린 레이아웃 (MapWidget 항상 하나만 유지) ──
              Column(
                children: [
                  const HudBar(),
                  Expanded(
                    child: MapWidget(
                      isSprintMode: _isSprinting,
                      navPolyline: _isSprinting ? _sprintNavPolyline : _navPolyline,
                      routePolyline: _isSprinting
                          ? _sprintRoute?.nodes
                          : selectedRoute?.nodes,
                    ),
                  ),
                ],
              ),

              // ── 루트 시작점 배너 (Sprint 중에는 숨김) ──
              if (!_isSprinting && _nearRouteStart && selectedRoute != null)
                Positioned(
                  top: 56 + 8,
                  left: 60,
                  right: 12,
                  child: _NearStartBanner(
                    routeName: selectedRoute.name,
                    onSprint: _goSprint,
                  ),
                ),

              // ── 선택된 루트 칩 (Sprint 중에는 숨김) ──
              if (!_isSprinting && selectedRoute != null)
                Positioned(
                  bottom: 80,
                  left: 60,
                  right: 12,
                  child: _RouteChip(route: selectedRoute),
                ),

              // ── 메뉴 오픈 시 딤 (Sprint 중에는 숨김) ──
              if (!_isSprinting && _menuOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _menuOpen = false),
                    child: Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                ),

              // ── 슬라이드 레일 오버레이 (Sprint 중에는 숨김) ──
              if (!_isSprinting) AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: _menuOpen ? 0 : -64,
                top: 0,
                bottom: 0,
                width: 64,
                child: _LeftRail(
                  onSprint: () {
                    setState(() => _menuOpen = false);
                    _goSprint();
                  },
                  onClose: () => setState(() => _menuOpen = false),
                ),
              ),

              // ── 햄버거 메뉴 버튼 (Sprint 중에는 숨김, 메뉴 열리면 레일 밖으로) ──
              if (!_isSprinting) AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                top: 52 + 12,
                left: _menuOpen ? 68 : 12,
                child: GestureDetector(
                  onTap: () => setState(() => _menuOpen = !_menuOpen),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _menuOpen ? Icons.close : Icons.menu,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),

              // ── SprintScreen 오버레이 (ANR 방지: MapWidget 하나만 유지) ──
              if (_isSprinting)
                Positioned.fill(
                  child: SprintScreen(
                    selectedRoute: _sprintRoute,
                    onEnd: _onSprintEnd,
                    onNavPolylineChanged: (poly) {
                      if (mounted) setState(() => _sprintNavPolyline = poly);
                    },
                  ),
                ),

              // ── GO + MIC 버튼 (메뉴 닫혔을 때만, Sprint 중에는 숨김) ──
              if (!_menuOpen && !_isSprinting)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // GO 버튼
                      GestureDetector(
                        onTap: _goSprint,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.redGlow,
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.flag_rounded, size: 16, color: Colors.white),
                              const SizedBox(height: 2),
                              Text(
                                'GO',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // MIC 버튼
                      const MicButton(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearStartBanner extends StatelessWidget {
  final String routeName;
  final VoidCallback onSprint;
  const _NearStartBanner({required this.routeName, required this.onSprint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$routeName 시작 지점 근처예요',
              style: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          GestureDetector(
            onTap: onSprint,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(3)),
              child: Text(
                'SPRINT',
                style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 왼쪽 세로 레일 (슬라이드 오버레이) ──────────────────────
class _LeftRail extends StatelessWidget {
  final VoidCallback onSprint;
  final VoidCallback onClose;
  const _LeftRail({required this.onSprint, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(6, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // 속도
          Consumer<LocationService>(
            builder: (_, loc, __) => _SpeedTile(
              value: loc.hasPermission ? loc.speedKmh.toStringAsFixed(0) : '—',
            ),
          ),
          const SizedBox(height: 4),
          // 날씨
          Consumer<WeatherService>(
            builder: (_, w, __) => _WeatherTile(emoji: w.weatherEmoji, temp: w.tempDisplay),
          ),
          Container(
            height: 1,
            color: AppColors.red.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(vertical: 8),
          ),
          // 메뉴 아이템
          _RailItem(
            icon: Icons.route_outlined,
            label: '루트',
            onTap: () {
              onClose();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen()));
            },
          ),
          _RailItem(
            icon: Icons.map_outlined,
            label: '여정',
            onTap: () {
              onClose();
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RoutesScreen(initialTab: 1)));
            },
          ),
          _RailItem(
            icon: Icons.speed_outlined,
            label: 'OBD',
            onTap: () {
              onClose();
              OBDScreen.show(context);
            },
          ),
          _RailItem(
            icon: Icons.history,
            label: '기록',
            onTap: () {
              onClose();
              HistoryScreen.show(context);
            },
          ),
          _RailItem(
            icon: Icons.chat_bubble_outline,
            label: 'AI',
            onTap: () {
              onClose();
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.panel,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                builder: (_) => const JarvisPanel(),
              );
            },
          ),
          _RailItem(
            icon: Icons.settings_outlined,
            label: '설정',
            onTap: () {
              onClose();
              SettingsScreen.show(context);
            },
          ),
          const Spacer(),
          // GO 버튼 (레일 내 하단)
          GestureDetector(
            onTap: onSprint,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: AppColors.red,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag, size: 18, color: Colors.white),
                  const SizedBox(height: 4),
                  Text(
                    'GO',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 3,
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

class _SpeedTile extends StatelessWidget {
  final String value;
  const _SpeedTile({required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.orbitron(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        Text('km/h', style: GoogleFonts.rajdhani(fontSize: 8, color: AppColors.textSecondary, letterSpacing: 1)),
      ],
    );
  }
}

class _WeatherTile extends StatelessWidget {
  final String emoji;
  final String temp;
  const _WeatherTile({required this.emoji, required this.temp});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        Text(temp, style: GoogleFonts.rajdhani(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RailItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 선택 루트 칩 ─────────────────────────────────────────────
class _RouteChip extends StatelessWidget {
  final RevvRoute route;
  const _RouteChip({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${route.name}  ·  ${route.distanceDisplay}',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}


class _SprintRoute extends PageRouteBuilder {
  _SprintRoute(Widget page)
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (context, animation, _, child) {
            return Stack(
              children: [
                SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                  child: child,
                ),
                IgnorePointer(
                  child: FadeTransition(
                    opacity: TweenSequence([
                      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.25), weight: 50),
                      TweenSequenceItem(tween: Tween(begin: 0.25, end: 0.0), weight: 50),
                    ]).animate(animation),
                    child: Container(color: AppColors.red),
                  ),
                ),
              ],
            );
          },
        );
}
