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
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const RevvLogo(size: 20),
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: 13,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '-2°C',
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _time,
                style: GoogleFonts.orbitron(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
          const RevvLogo(size: 18),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.redDim,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.red, width: 1),
            ),
            child: Text(
              'SPRINT',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: AppColors.red,
                letterSpacing: 2,
              ),
            ),
          ),
          const Spacer(),
          Consumer<LocationService>(
            builder: (_, loc, _) => Column(
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
              color: AppColors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
