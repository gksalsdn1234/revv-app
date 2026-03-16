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
import 'sprint_screen.dart';
import 'routes_screen.dart';
import 'trip_planner_screen.dart';
import 'obd_screen.dart';
import 'history_screen.dart';

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

  void _goSprint() async {
    final route = context.read<RouteService>().selectedRoute;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      _SprintRoute(SprintScreen(selectedRoute: route)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = context.watch<RouteService>().selectedRoute;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              const HudBar(),
              Expanded(
                child: Row(
                  children: [
                    // ── 왼쪽 레일 ──
                    _LeftRail(onSprint: _goSprint),
                    // ── 지도 ──
                    Expanded(
                      child: Stack(
                        children: [
                          MapWidget(
                            isSprintMode: false,
                            navPolyline: _navPolyline,
                            routePolyline: selectedRoute?.nodes,
                          ),
                          if (_nearRouteStart && selectedRoute != null)
                            Positioned(
                              top: 12,
                              left: 8,
                              right: 8,
                              child: _NearStartBanner(
                                routeName: selectedRoute.name,
                                onSprint: _goSprint,
                              ),
                            ),
                          // 선택된 루트명
                          if (selectedRoute != null)
                            Positioned(
                              bottom: 12,
                              left: 8,
                              right: 8,
                              child: _RouteChip(route: selectedRoute),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const JarvisPanel(),
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

// ── 왼쪽 세로 레일 ──────────────────────────────────────────
class _LeftRail extends StatelessWidget {
  final VoidCallback onSprint;
  const _LeftRail({required this.onSprint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.red.withValues(alpha: 0.12))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
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
          Container(height: 1, color: AppColors.red.withValues(alpha: 0.1), margin: const EdgeInsets.symmetric(vertical: 8)),
          // 메뉴 아이템
          _RailItem(
            icon: Icons.route_outlined,
            label: '루트',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen())),
          ),
          _RailItem(
            icon: Icons.map_outlined,
            label: '여정',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TripPlannerScreen())),
          ),
          _RailItem(
            icon: Icons.speed_outlined,
            label: 'OBD',
            onTap: () => OBDScreen.show(context),
          ),
          _RailItem(
            icon: Icons.history,
            label: '기록',
            onTap: () => HistoryScreen.show(context),
          ),
          _RailItem(
            icon: Icons.chat_bubble_outline,
            label: 'AI',
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: AppColors.panel,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              builder: (_) => const JarvisPanel(),
            ),
          ),
          const Spacer(),
          // SPRINT 버튼
          GestureDetector(
            onTap: onSprint,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
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
          // 마이크
          Container(
            color: AppColors.panel,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Center(child: MicButton()),
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
          style: GoogleFonts.orbitron(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        Text('km/h', style: GoogleFonts.rajdhani(fontSize: 8, color: AppColors.gray, letterSpacing: 1)),
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
        Text(temp, style: GoogleFonts.rajdhani(fontSize: 10, color: AppColors.gray)),
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
              Icon(icon, size: 18, color: AppColors.gray),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray,
                  letterSpacing: 1,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(
            '${route.name}  ·  ${route.distanceDisplay}',
            style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
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
