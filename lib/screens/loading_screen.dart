import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../widgets/corner_brackets.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/jarvis_service.dart';
import 'cruise_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _scan;
  late AnimationController _line;
  late AnimationController _sub;
  late AnimationController _brackets;
  late AnimationController _cursor;

  late Animation<double> _scanAnim;
  late Animation<double> _lineWidth;
  late Animation<double> _subOpacity;
  late Animation<double> _bracketsOpacity;

  @override
  void initState() {
    super.initState();

    _scan = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _line = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _sub = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _brackets = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _cursor = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _scanAnim =
        CurvedAnimation(parent: _scan, curve: Curves.easeInOut);
    _lineWidth = CurvedAnimation(parent: _line, curve: Curves.easeOut);
    _subOpacity = CurvedAnimation(parent: _sub, curve: Curves.easeIn);
    _bracketsOpacity =
        CurvedAnimation(parent: _brackets, curve: Curves.easeIn);

    _scan.forward().then((_) async {
      _cursor.repeat(reverse: true);
      _line.forward();
      await Future.delayed(const Duration(milliseconds: 400));
      _sub.forward();
      _brackets.forward();

      // Jarvis 첫 인사 + 날씨 로드
      if (mounted) {
        final loc = context.read<LocationService>();
        final weather = context.read<WeatherService>();
        final jarvis = context.read<JarvisService>();

        jarvis.speak('준비됐어요. 오늘도 안전하게 달려요.');
        weather.fetchWeather(loc.lat, loc.lng);
      }

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CruiseScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _scan.dispose();
    _line.dispose();
    _sub.dispose();
    _brackets.dispose();
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Corner brackets
          Positioned.fill(
            child: FadeTransition(
              opacity: _bracketsOpacity,
              child: const CornerBrackets(padding: 24, lineLength: 20),
            ),
          ),
          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with scan reveal
                AnimatedBuilder(
                  animation: _scanAnim,
                  builder: (context, _) {
                    final scanX = _scanAnim.value * screen.width;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Trail
                        Positioned(
                          left: 0,
                          child: Container(
                            width: scanX,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.red.withOpacity(0.04),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Revealed logo
                        ClipRect(
                          clipper: _ScanClipper(revealX: scanX),
                          child: _buildLogo(),
                        ),
                        // Scan line
                        if (_scanAnim.value < 1)
                          Positioned(
                            left: scanX - 1,
                            child: Container(
                              width: 2,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.red.withOpacity(0.6),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Red underline
                AnimatedBuilder(
                  animation: _lineWidth,
                  builder: (context, _) {
                    final w = _lineWidth.value * 240;
                    return Container(
                      width: w,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.red,
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.redGlow,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Sub text
                FadeTransition(
                  opacity: _subOpacity,
                  child: Text(
                    'AI CO-DRIVER',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.white.withOpacity(0.25),
                      letterSpacing: 8,
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

  Widget _buildLogo() {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.orbitron(
          fontSize: 72,
          fontWeight: FontWeight.w900,
        ),
        children: [
          const TextSpan(
            text: 'RE',
            style: TextStyle(color: AppColors.white),
          ),
          TextSpan(
            text: 'VV',
            style: TextStyle(
              color: AppColors.red,
              shadows: [
                Shadow(color: AppColors.red, blurRadius: 30),
                Shadow(color: AppColors.redGlow, blurRadius: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanClipper extends CustomClipper<Rect> {
  final double revealX;
  const _ScanClipper({required this.revealX});

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, revealX, size.height);

  @override
  bool shouldReclip(_ScanClipper old) => revealX != old.revealX;
}
