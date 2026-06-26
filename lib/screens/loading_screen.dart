import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'lean_home_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _contentCtrl;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _logoFade  = CurvedAnimation(parent: _logoCtrl,    curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic),
    );
    _contentFade = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeIn);

    _logoCtrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      _contentCtrl.forward();

      await _requestPermissions();
      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LeanHomeScreen()),
        );
      }
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await [Permission.locationWhenInUse].request();
    if (kDebugMode) {
      for (final e in statuses.entries) {
        debugPrint('[LoadingScreen] ${e.key} → ${e.value}');
      }
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              // ── F1 lights ──────────────────────────────────
              const Spacer(),
              FadeTransition(
                opacity: _logoFade,
                child: const _F1LightsRow(),
              ),
              const SizedBox(height: 32),

              // ── REVV wordmark ──────────────────────────────
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: RichText(
                    text: TextSpan(
                      style: AppText.display(
                        size: 88,
                        weight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                      children: const [
                        TextSpan(
                          text: 'RE',
                          style: TextStyle(color: AppColors.cream),
                        ),
                        TextSpan(
                          text: 'VV',
                          style: TextStyle(
                            color: AppColors.red,
                            shadows: [
                              Shadow(color: AppColors.redGlow, blurRadius: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Red underline ──────────────────────────────
              FadeTransition(
                opacity: _logoFade,
                child: Container(
                  height: 2,
                  width: 56,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.redGlow,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Tagline ────────────────────────────────────
              FadeTransition(
                opacity: _logoFade,
                child: Text(
                  'FIND THE ROAD · RUN THE LAP',
                  style: AppText.mono(
                    size: 10,
                    color: AppColors.stone,
                    letterSpacing: 2.5,
                  ),
                ),
              ),

              const Spacer(),

              // ── System checks ──────────────────────────────
              FadeTransition(
                opacity: _contentFade,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppColors.cream.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  child: const Column(
                    children: [
                      _CheckRow(label: 'GPS',      status: 'ACQUIRING'),
                      SizedBox(height: 10),
                      _CheckRow(label: 'IMU',      status: 'READY',    ok: true),
                      SizedBox(height: 10),
                      _CheckRow(label: 'LOCATION', status: 'CHECKING'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── F1 lights row ────────────────────────────────────────

class _F1LightsRow extends StatelessWidget {
  const _F1LightsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final lit = i < 4;
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit ? AppColors.red : AppColors.surface,
              boxShadow: lit
                  ? [BoxShadow(color: AppColors.redGlow, blurRadius: 12)]
                  : null,
              border: lit
                  ? null
                  : Border.all(
                      color: AppColors.cream.withValues(alpha: 0.12),
                    ),
            ),
          ),
        );
      }),
    );
  }
}

// ── System check row ─────────────────────────────────────

class _CheckRow extends StatelessWidget {
  final String label;
  final String status;
  final bool ok;

  const _CheckRow({
    required this.label,
    required this.status,
    this.ok = false,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = ok ? AppColors.success : AppColors.stone;
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: ok
                ? [BoxShadow(color: dotColor.withValues(alpha: 0.6), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppText.mono(size: 10, color: AppColors.stone, letterSpacing: 1.2),
          ),
        ),
        Text(
          status,
          style: AppText.mono(
            size: 10,
            weight: FontWeight.w700,
            color: ok ? AppColors.success : AppColors.stoneMuted,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}


