import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/revv_route.dart';
import '../theme/colors.dart';
import '../widgets/mini_elev_chart.dart';

class RoutePreviewScreen extends StatelessWidget {
  final RevvRoute route;

  const RoutePreviewScreen({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: Text(
          route.name,
          style: GoogleFonts.orbitron(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.difficultyLabel,
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.red,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${route.distanceKm.toStringAsFixed(1)} km',
                  style: GoogleFonts.orbitron(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '와인딩 ${route.windingScore.toStringAsFixed(1)} / 커브 ${route.sharpCurveCount}개 / ${route.distanceFromUserDisplay}',
                  style: GoogleFonts.rajdhani(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                MiniElevSection(
                  route: route,
                  lineColor: AppColors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
