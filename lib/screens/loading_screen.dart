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
    final screen = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RevvCockpitBackground(
        scanlines: true,
        child: Stack(
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
                                    AppColors.primaryContainer.withValues(
                                      alpha: 0.04,
                                    ),
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
                                  color: AppColors.primaryContainer,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryContainer
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
                              AppColors.primaryContainer,
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(color: AppColors.redGlow, blurRadius: 8),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _subOpacity,
                    child: Column(
                      children: [
                        Text(
                          'GRID START',
                          style: AppText.technicalLabel(
                            size: 10,
                            color: AppColors.textHint,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Find the road · run the lap',
                          style: AppText.body(
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _GridStartChecks(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return RichText(
      text: TextSpan(
        style: AppText.display(size: 104, weight: FontWeight.w900),
        children: [
          const TextSpan(
            text: 'RE',
            style: TextStyle(color: AppColors.white),
          ),
          TextSpan(
            text: 'VV',
            style: TextStyle(
              color: AppColors.primaryContainer,
              shadows: [
                Shadow(color: AppColors.primaryContainer, blurRadius: 30),
                Shadow(color: AppColors.redGlow, blurRadius: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridStartChecks extends StatelessWidget {
  const _GridStartChecks();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _GridStartCheck(label: 'GPS LOCK', value: 'READY'),
        SizedBox(height: 8),
        _GridStartCheck(label: 'MOTION SENSORS', value: 'CALIBRATED'),
        SizedBox(height: 8),
        _GridStartCheck(label: 'LOCATION ACCESS', value: 'WHILE DRIVING'),
      ],
    );
  }
}

class _GridStartCheck extends StatelessWidget {
  final String label;
  final String value;

  const _GridStartCheck({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cream.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.technicalLabel(
              size: 9,
              letterSpacing: 1.4,
              color: AppColors.textHint,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppText.technicalLabel(
              size: 10,
              letterSpacing: 1.2,
              color: AppColors.primaryContainer,
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
