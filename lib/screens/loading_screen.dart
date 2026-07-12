import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import 'lean_app_shell_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _logoCtrl;
  late AnimationController _contentCtrl;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _contentFade;
  PermissionStatus? _locationPermission;
  bool _gpsReady = false;
  bool _gpsChecked = false;
  Completer<void>? _permissionDecision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoScale = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));
    _contentFade = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeIn);

    _logoCtrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      _contentCtrl.forward();

      await _requestPermissions();
      if (!mounted) return;

      if (_locationPermission?.isPermanentlyDenied ?? false) {
        _permissionDecision = Completer<void>();
        await _permissionDecision!.future;
        _permissionDecision = null;
      }
      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LeanAppShellScreen()),
        );
      }
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await [Permission.locationWhenInUse].request();
    if (mounted) {
      setState(() {
        _locationPermission = statuses[Permission.locationWhenInUse];
      });
    }
    if (!mounted) return;
    if (_locationPermission?.isGranted ?? false) {
      final fix = await context.read<LocationService>().ensureLiveLocation(
        timeout: const Duration(seconds: 3),
      );
      if (mounted) {
        setState(() {
          _gpsReady = fix != null;
          _gpsChecked = true;
        });
      }
    }
    if (kDebugMode) {
      for (final e in statuses.entries) {
        debugPrint('[LoadingScreen] ${e.key} → ${e.value}');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logoCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _openLocationSettings() async {
    await openAppSettings();
    await _refreshPermissionAfterSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionAfterSettings());
    }
  }

  Future<void> _refreshPermissionAfterSettings() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() => _locationPermission = status);
    if (status.isGranted) {
      _permissionDecision?.complete();
    }
  }

  void _continueAfterPermissionNotice() {
    if (!(_permissionDecision?.isCompleted ?? true)) {
      _permissionDecision!.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final locationPermission = _locationPermission;
    final locationReady = locationPermission?.isGranted ?? false;
    final locationStatus = locationPermission == null
        ? AppCopy.loadingScanning(language)
        : locationReady
        ? AppCopy.loadingReady(language)
        : AppCopy.permissionNeeded(language);
    final gpsStatus = !locationReady
        ? locationStatus
        : _gpsChecked && _gpsReady
        ? AppCopy.loadingReady(language)
        : AppCopy.loadingScanning(language);
    final permanentlyDenied = locationPermission?.isPermanentlyDenied ?? false;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 620;
            final tight = constraints.maxHeight < 520;
            final logoSize = tight ? 58.0 : (compact ? 72.0 : 88.0);
            final topGap = tight ? 22.0 : (compact ? 34.0 : 0.0);
            final lightGap = tight ? 18.0 : (compact ? 24.0 : 32.0);
            final bottomGap = tight ? 8.0 : 16.0;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 24 : 32),
              child: Column(
                children: [
                  SizedBox(height: topGap),
                  if (!compact) const Spacer(),
                  FadeTransition(
                    opacity: _logoFade,
                    child: const _F1LightsRow(),
                  ),
                  SizedBox(height: lightGap),
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: RichText(
                        text: TextSpan(
                          style: AppText.display(
                            size: logoSize,
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
                                  Shadow(
                                    color: AppColors.redGlow,
                                    blurRadius: 24,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                          BoxShadow(color: AppColors.redGlow, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  FadeTransition(
                    opacity: _logoFade,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppCopy.loadingTagline(language).toUpperCase(),
                        style: AppText.mono(
                          size: 10,
                          color: AppColors.stone,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  FadeTransition(
                    opacity: _logoFade,
                    child: Text(
                      AppCopy.t(
                        language,
                        ko: '도로를 찾고\n주행을 시작하세요.',
                        en: 'Find the road.\nStart the drive.',
                        fr: 'Trouvez la route.\nLancez le run.',
                      ),
                      textAlign: TextAlign.center,
                      style: AppText.rajdhani(
                        size: tight ? 30 : 36,
                        weight: FontWeight.w800,
                        height: 0.96,
                        color: AppColors.cream,
                      ),
                    ),
                  ),
                  if (!tight) const Spacer() else const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _contentFade,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? 12 : 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: AppColors.cream.withValues(alpha: 0.07),
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          _CheckRow(
                            label: AppCopy.loadingGps(language),
                            status: gpsStatus,
                            ok: _gpsReady,
                          ),
                          SizedBox(height: compact ? 8 : 10),
                          _CheckRow(
                            label: AppCopy.loadingImu(language),
                            status: AppCopy.loadingScanning(language),
                          ),
                          SizedBox(height: compact ? 8 : 10),
                          _CheckRow(
                            label: AppCopy.loadingLocation(language),
                            status: locationStatus,
                            ok: locationReady,
                          ),
                          if (permanentlyDenied) ...[
                            SizedBox(height: compact ? 8 : 10),
                            TextButton(
                              onPressed: _openLocationSettings,
                              child: Text(AppCopy.openSettings(language)),
                            ),
                            TextButton(
                              onPressed: _continueAfterPermissionNotice,
                              child: Text(AppCopy.continueAnyway(language)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: bottomGap),
                ],
              ),
            );
          },
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
                  : Border.all(color: AppColors.cream.withValues(alpha: 0.12)),
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

  const _CheckRow({required this.label, required this.status, this.ok = false});

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
                ? [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppText.mono(
              size: 10,
              color: AppColors.stone,
              letterSpacing: 1.2,
            ),
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
