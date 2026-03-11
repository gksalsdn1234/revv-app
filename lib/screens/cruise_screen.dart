import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../widgets/hud_bar.dart';
import '../widgets/map_widget.dart';
import '../widgets/jarvis_panel.dart';
import '../widgets/mic_button.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import 'sprint_screen.dart';
import 'routes_screen.dart';
import 'trip_planner_screen.dart';

class CruiseScreen extends StatefulWidget {
  const CruiseScreen({super.key});

  @override
  State<CruiseScreen> createState() => _CruiseScreenState();
}

class _CruiseScreenState extends State<CruiseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loc = context.read<LocationService>();
      await loc.requestPermission();
      if (loc.hasPermission) {
        await loc.startTracking();
        // 날씨 최초 로드
        context.read<WeatherService>().fetchWeather(loc.lat, loc.lng);
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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              const HudBar(),
              const Expanded(child: MapWidget(isSprintMode: false)),
              const JarvisPanel(),
              _CruiseBottomPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CruiseBottomPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(
          top: BorderSide(color: AppColors.red.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 스탯 행 — 컴팩트
          Row(
            children: [
              Consumer<LocationService>(
                builder: (_, loc, __) => _StatChip(
                  icon: Icons.speed,
                  value: loc.hasPermission
                      ? loc.speedKmh.toStringAsFixed(0)
                      : '—',
                  unit: 'km/h',
                ),
              ),
              const SizedBox(width: 8),
              Consumer<WeatherService>(
                builder: (_, w, __) => _StatChip(
                  emoji: w.weatherEmoji,
                  value: w.tempDisplay,
                  unit: w.weatherDesc,
                ),
              ),
              const Spacer(),
              const MicButton(),
            ],
          ),
          const SizedBox(height: 10),
          // 버튼 행
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.route,
                  label: 'ROUTES',
                  filled: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RoutesScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconOnlyButton(
                icon: Icons.place_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TripPlannerScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _ActionButton(
                  icon: Icons.flag,
                  label: 'SPRINT',
                  filled: true,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (context.mounted) {
                      Navigator.pushReplacement(
                          context, _SprintRoute(const SprintScreen()));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String value;
  final String unit;
  const _StatChip({this.icon, this.emoji, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 13, color: AppColors.gray),
        if (emoji != null)
          Text(emoji!, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.orbitron(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          unit,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            color: AppColors.gray,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  const _ActionButton({required this.icon, required this.label, required this.filled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: filled ? AppColors.red : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.6)),
                  ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _IconOnlyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconOnlyButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 40,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border:
                  Border.all(color: AppColors.red.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, size: 18, color: AppColors.gray),
          ),
        ),
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
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
                  child: child,
                ),
                IgnorePointer(
                  child: FadeTransition(
                    opacity: TweenSequence([
                      TweenSequenceItem(
                          tween: Tween(begin: 0.0, end: 0.25), weight: 50),
                      TweenSequenceItem(
                          tween: Tween(begin: 0.25, end: 0.0), weight: 50),
                    ]).animate(animation),
                    child: Container(color: AppColors.red),
                  ),
                ),
              ],
            );
          },
        );
}
