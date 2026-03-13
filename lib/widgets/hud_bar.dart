import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/location_service.dart';
import 'corner_brackets.dart';

class HudBar extends StatefulWidget {
  const HudBar({super.key});

  @override
  State<HudBar> createState() => _HudBarState();
}

class _HudBarState extends State<HudBar> {
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
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(
          bottom: BorderSide(color: AppColors.red.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          const RevvLogo(size: 18),
          const SizedBox(width: 6),
          Text(
            'v1.26',
            style: GoogleFonts.rajdhani(
              fontSize: 9,
              color: AppColors.red.withOpacity(0.5),
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.wb_sunny_outlined,
                  size: 14, color: AppColors.white.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(
                '-2°C',
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _time,
                style: GoogleFonts.orbitron(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SprintHudBar extends StatefulWidget {
  const SprintHudBar({super.key});

  @override
  State<SprintHudBar> createState() => _SprintHudBarState();
}

class _SprintHudBarState extends State<SprintHudBar> {
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
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.red, width: 2)),
      ),
      child: Row(
        children: [
          const RevvLogo(size: 16),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'SPRINT',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'v1.26',
            style: GoogleFonts.rajdhani(
              fontSize: 9,
              color: AppColors.red.withOpacity(0.6),
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Consumer<LocationService>(
            builder: (_, loc, __) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  loc.hasPermission ? loc.speedKmh.toStringAsFixed(0) : '—',
                  style: GoogleFonts.orbitron(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'KM/H',
                  style: GoogleFonts.rajdhani(
                    fontSize: 9,
                    color: AppColors.gray,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            _time,
            style: GoogleFonts.orbitron(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
