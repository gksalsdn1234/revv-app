import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../widgets/corner_brackets.dart';
import '../widgets/revv_ui.dart';
import 'lean_home_screen.dart';

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
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _sub = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _brackets = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _cursor = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scanAnim = CurvedAnimation(parent: _scan, curve: Curves.easeInOut);
    _lineWidth = CurvedAnimation(parent: _line, curve: Curves.easeOut);
    _subOpacity = CurvedAnimation(parent: _sub, curve: Curves.easeIn);
    _bracketsOpacity = CurvedAnimation(parent: _brackets, curve: Curves.easeIn);

    _scan.forward().then((_) async {
      _cursor.repeat(reverse: true);
      _line.forward();
      await Future.delayed(const Duration(milliseconds: 400));
      _sub.forward();
      _brackets.forward();

      await _showPermissionIntroIfNeeded();
      if (!mounted) return;

      // 권한 요청 (첫 실행 또는 미허용 시)
      final permissions = await _requestPermissions();
      await _showPermissionResultIfNeeded(permissions);

      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LeanHomeScreen()),
        );
      }
    });
  }

  /// MVP에서는 위치 권한만 시작 시 확인한다.
  Future<Map<Permission, PermissionStatus>> _requestPermissions() async {
    final statuses = await [Permission.locationWhenInUse].request();
    if (kDebugMode) {
      for (final entry in statuses.entries) {
        debugPrint('[LoadingScreen] ${entry.key} → ${entry.value}');
      }
    }
    return statuses;
  }

  Future<void> _showPermissionIntroIfNeeded() async {
    final location = await Permission.locationWhenInUse.status;
    if (!mounted || location.isGranted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _PermissionIntroSheet(onContinue: () => Navigator.pop(context)),
    );
  }

  Future<void> _showPermissionResultIfNeeded(
    Map<Permission, PermissionStatus> statuses,
  ) async {
    if (!mounted) return;
    final location = statuses[Permission.locationWhenInUse];
    if (location?.isGranted ?? false) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PermissionResultSheet(
        locationGranted: location?.isGranted ?? false,
        onSettings: () {
          openAppSettings();
          Navigator.pop(context);
        },
        onContinue: () => Navigator.pop(context),
      ),
    );
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
    return Scaffold(
      backgroundColor: const Color(0xFF15161A),
      body: Stack(
        children: [
          // Corner brackets
          Positioned.fill(
            child: FadeTransition(
              opacity: _bracketsOpacity,
              child: const CornerBrackets(padding: 24, lineLength: 20),
            ),
          ),
          // Full layout
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
              child: Column(
                children: [
                  // Build version top-right
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'BUILD 1.38.0',
                        style: AppText.mono(
                          size: 9,
                          color: const Color(0xFF54565C),
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ),
                  // Center: F1 lights + logo + tagline
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // F1 lights panel
                          FadeTransition(
                            opacity: _bracketsOpacity,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C0D10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.cream.withValues(alpha: 0.10),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _F1Light(lit: true),
                                  SizedBox(width: 9),
                                  _F1Light(lit: true),
                                  SizedBox(width: 9),
                                  _F1Light(lit: true),
                                  SizedBox(width: 9),
                                  _F1Light(lit: true),
                                  SizedBox(width: 9),
                                  _F1Light(lit: false),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          // Logo with scan reveal
                          AnimatedBuilder(
                            animation: _scanAnim,
                            builder: (context, _) {
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  // Use the actual Stack width so the scan
                                  // line never overflows the logo bounds.
                                  final stackWidth = constraints.maxWidth;
                                  final scanX = _scanAnim.value * stackWidth;
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRect(
                                        clipper: _ScanClipper(revealX: scanX),
                                        child: _buildLogo(),
                                      ),
                                      if (_scanAnim.value < 1)
                                        Positioned(
                                          left: (scanX - 1).clamp(
                                            0.0,
                                            stackWidth - 2,
                                          ),
                                          child: Container(
                                            width: 2,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryContainer,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors
                                                      .primaryContainer
                                                      .withValues(alpha: 0.6),
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
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          // Tagline
                          FadeTransition(
                            opacity: _subOpacity,
                            child: Text(
                              'Find the road · run the lap',
                              style: AppText.mono(
                                size: 11,
                                color: AppColors.stone,
                                letterSpacing: 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // System checks
                  FadeTransition(
                    opacity: _subOpacity,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: AppColors.cream.withValues(alpha: 0.08),
                          ),
                          bottom: BorderSide(
                            color: AppColors.cream.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: const Column(
                        children: [
                          _SystemCheckRow(
                            label: 'GPS LOCK',
                            status: 'READY',
                            statusColor: AppColors.success,
                            dotColor: AppColors.success,
                          ),
                          SizedBox(height: 11),
                          _SystemCheckRow(
                            label: 'MOTION SENSORS',
                            status: 'CALIBRATED',
                            statusColor: AppColors.success,
                            dotColor: AppColors.success,
                          ),
                          SizedBox(height: 11),
                          _SystemCheckRow(
                            label: 'LOCATION ACCESS',
                            status: 'WHILE DRIVING',
                            statusColor: AppColors.orange,
                            dotColor: AppColors.orange,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Lights Out button
                  FadeTransition(
                    opacity: _subOpacity,
                    child: SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: null,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                        label: Text(
                          'LIGHTS OUT',
                          style: AppText.label(
                            size: 20,
                            weight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  FadeTransition(
                    opacity: _subOpacity,
                    child: Text(
                      'START REVV · GRANTS LOCATION WHILE DRIVING',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(
                        size: 10,
                        color: AppColors.stone,
                        letterSpacing: 1,
                      ),
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

  Widget _buildLogo() {
    return Text(
      'REVV',
      style: AppText.label(
        size: 66,
        weight: FontWeight.w900,
        letterSpacing: 11,
        color: AppColors.cream,
      ),
    );
  }
}

// ── F1 light dot ─────────────────────────────────────────

class _F1Light extends StatelessWidget {
  final bool lit;

  const _F1Light({required this.lit});

  @override
  Widget build(BuildContext context) {
    if (lit) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.24, -0.36),
            colors: [Color(0xFFFF6457), Color(0xFFE2231A)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryContainer.withValues(alpha: 0.65),
              blurRadius: 14,
            ),
          ],
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1C1206),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

// ── System check row ─────────────────────────────────────

class _SystemCheckRow extends StatelessWidget {
  final String label;
  final String status;
  final Color statusColor;
  final Color dotColor;

  const _SystemCheckRow({
    required this.label,
    required this.status,
    required this.statusColor,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: 0.6),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppText.mono(
              size: 11,
              color: const Color(0xFFA9A39B),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Text(
          status,
          style: AppText.mono(
            size: 11,
            weight: FontWeight.w700,
            color: statusColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
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

class _PermissionIntroSheet extends StatelessWidget {
  final VoidCallback onContinue;

  const _PermissionIntroSheet({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return SafeArea(
      top: false,
      child: RevvGlassCard(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        radius: 24,
        color: AppColors.panel.withValues(alpha: 0.96),
        glow: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppCopy.permissionIntroTitle(language),
              style: AppText.body(
                size: 22,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppCopy.permissionIntroBody(language),
              style: AppText.body(
                size: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _PermissionReasonTile(
              icon: Icons.location_on_rounded,
              title: AppCopy.location(language),
              body: AppCopy.locationPermissionBody(language),
            ),
            const SizedBox(height: 16),
            RevvPrimaryButton(
              label: AppCopy.continuePermissions(language),
              icon: Icons.verified_user_rounded,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionResultSheet extends StatelessWidget {
  final bool locationGranted;
  final VoidCallback onSettings;
  final VoidCallback onContinue;

  const _PermissionResultSheet({
    required this.locationGranted,
    required this.onSettings,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final locationBlocked = !locationGranted;
    return SafeArea(
      top: false,
      child: RevvGlassCard(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        radius: 24,
        color: AppColors.panel.withValues(alpha: 0.96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locationBlocked
                  ? AppCopy.locationBlockedTitle(language)
                  : AppCopy.permissionsReadyTitle(language),
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              locationBlocked
                  ? AppCopy.locationBlockedBody(language)
                  : AppCopy.permissionsReadyBody(language),
              style: AppText.body(
                size: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (locationBlocked) ...[
                  Expanded(
                    child: RevvGhostButton(
                      label: AppCopy.openSettings(language),
                      onPressed: onSettings,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: RevvPrimaryButton(
                    label: locationBlocked
                        ? AppCopy.continueAnyway(language)
                        : AppCopy.continuePermissions(language),
                    icon: Icons.arrow_forward_rounded,
                    onPressed: onContinue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionReasonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PermissionReasonTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppColors.primaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.body(
                    size: 14,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppText.body(
                    size: 12,
                    height: 1.32,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
