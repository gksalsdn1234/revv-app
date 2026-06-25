import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/corner_brackets.dart';
import '../widgets/revv_ui.dart';
import 'cruise_screen.dart';
import 'calibration_screen.dart';

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

      // 클라우드 함수 설정이 없거나 TTS 엔진 초기화 중인 환경에서 시작 크래시를 피하기 위해
      // 첫 진입 자동 음성 안내는 하지 않는다. 날씨는 CruiseScreen 진입 후 갱신한다.

      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final calibDone = prefs.getBool(kCalibrationDoneKey) ?? false;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                calibDone ? const CruiseScreen() : const CalibrationScreen(),
          ),
        );
      }
    });
  }

  /// 위치 + 마이크 권한 요청 — 이미 허용됐으면 즉시 반환
  Future<Map<Permission, PermissionStatus>> _requestPermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.microphone,
    ].request();
    for (final entry in statuses.entries) {
      debugPrint('[LoadingScreen] ${entry.key} → ${entry.value}');
    }
    return statuses;
  }

  Future<void> _showPermissionIntroIfNeeded() async {
    final location = await Permission.locationWhenInUse.status;
    final mic = await Permission.microphone.status;
    if (!mounted || (location.isGranted && mic.isGranted)) return;
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
    final mic = statuses[Permission.microphone];
    if ((location?.isGranted ?? false) && (mic?.isGranted ?? false)) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PermissionResultSheet(
        locationGranted: location?.isGranted ?? false,
        microphoneGranted: mic?.isGranted ?? false,
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
                  // Sub text
                  FadeTransition(
                    opacity: _subOpacity,
                    child: Text(
                      'AI CO-DRIVER',
                      style: AppText.label(
                        size: 11,
                        color: AppColors.textHint,
                        letterSpacing: 8,
                      ),
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
        style: GoogleFonts.orbitron(fontSize: 72, fontWeight: FontWeight.w900),
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
              '시작 전 권한 안내',
              style: AppText.body(
                size: 22,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '권한은 필요한 기능에만 사용해요. 거부해도 앱은 계속 열리지만 일부 기능이 제한됩니다.',
              style: AppText.body(
                size: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const _PermissionReasonTile(
              icon: Icons.location_on_rounded,
              title: '위치',
              body: '현재 위치 주변 루트 탐색, 시작점 거리 계산, 주행 기록 저장에 사용합니다.',
            ),
            const _PermissionReasonTile(
              icon: Icons.mic_rounded,
              title: '마이크',
              body: '코파일럿 음성 명령에만 사용합니다. 꺼도 루트 탐색과 주행은 가능합니다.',
            ),
            const SizedBox(height: 16),
            RevvPrimaryButton(
              label: '권한 설정 계속',
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
  final bool microphoneGranted;
  final VoidCallback onSettings;
  final VoidCallback onContinue;

  const _PermissionResultSheet({
    required this.locationGranted,
    required this.microphoneGranted,
    required this.onSettings,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
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
              locationBlocked ? '위치 권한이 필요해요' : '음성 기능은 나중에 켤 수 있어요',
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              locationBlocked
                  ? '주변 루트 탐색은 위치 권한이 있어야 정확히 동작합니다. 설정에서 위치 권한을 켜면 바로 다시 찾을 수 있어요.'
                  : microphoneGranted
                  ? '필수 권한이 준비됐어요.'
                  : '마이크 권한이 없어도 루트 탐색과 주행은 가능합니다. 음성 명령만 비활성화돼요.',
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
                      label: '설정 열기',
                      onPressed: onSettings,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: RevvPrimaryButton(
                    label: locationBlocked ? '일단 계속' : '계속',
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
