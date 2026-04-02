import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: Text(
          'ANALYSIS',
          style: GoogleFonts.orbitron(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: Center(
        child: Text(
          '상세 분석 화면은 MVP 안정화 이후 다시 확장할 예정이에요.',
          style: GoogleFonts.rajdhani(fontSize: 16, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
