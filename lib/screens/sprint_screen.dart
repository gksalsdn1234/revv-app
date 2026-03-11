import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../widgets/hud_bar.dart';
import '../widgets/map_widget.dart';
import '../widgets/sprint_toggle.dart';
import '../widgets/mic_button.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/run_session_service.dart';
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
