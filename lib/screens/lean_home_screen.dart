import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../core/app_links.dart';
import '../models/revv_route.dart';
import '../models/run_summary.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/run_history_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../widgets/copilot_start_sheet.dart';
import 'lean_drive_screen.dart';
import 'lean_route_finder_screen.dart';

class LeanHomeScreen extends StatefulWidget {
  const LeanHomeScreen({super.key});

  @override
  State<LeanHomeScreen> createState() => _LeanHomeScreenState();
}

class _LeanHomeScreenState extends State<LeanHomeScreen>
    with WidgetsBindingObserver {
  bool _checkingGuideReturn = false;
  bool _guidePromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_primeLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkPendingGuideReturn());
    }
  }

  Future<void> _primeLocation() async {
    final location = context.read<LocationService>();
    await location.requestPermission();
    await location.startTracking();
    if (!mounted) return;
    await _checkPendingGuideReturn();
  }

  Future<void> _checkPendingGuideReturn() async {
    if (_checkingGuideReturn || !mounted) return;
    final routes = context.read<RouteService>();
    final route = routes.pendingGuideRoute;
    if (route == null) return;

    _checkingGuideReturn = true;
    try {
      final location = context.read<LocationService>();
      final current = await location.ensureLiveLocation();
      if (!mounted) return;
      final start = route.nodes.isNotEmpty
          ? route.nodes.first
          : route.centerPoint;
      final distanceKm = current == null
          ? route.distanceFromUser
          : RevvRoute.haversineKm(current, start);

      final shouldPrompt =
          distanceKm <= 0.8 ||
          DateTime.now()
                  .difference(routes.pendingGuideStartedAt ?? DateTime.now())
                  .inMinutes >=
              2;
      if (!shouldPrompt || _guidePromptShown) return;
      _guidePromptShown = true;

      final startChoice = await showCopilotStartSheet(
        context,
        route: route.copyWith(distanceFromUser: distanceKm),
      );
      if (!mounted) return;
      if (startChoice != null) {
        routes.clearGuideToStart();
        _guidePromptShown = false;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LeanDriveScreen(
              route: route,
              simulated: startChoice == CopilotStartChoice.simulate,
            ),
          ),
        );
      }
    } finally {
      _checkingGuideReturn = false;
    }
  }

  Future<void> _startFromGuideCard(RevvRoute route) async {
    final startChoice = await showCopilotStartSheet(context, route: route);
    if (!mounted || startChoice == null) return;
    context.read<RouteService>().clearGuideToStart();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(
          route: route,
          simulated: startChoice == CopilotStartChoice.simulate,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRunData(BuildContext ctx) async {
    final language = ctx.read<SettingsService>().appLanguage;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(
          AppCopy.deleteRunsTitle(language),
          style: AppText.body(size: 20, weight: FontWeight.w900),
        ),
        content: Text(
          AppCopy.deleteRunsBody(language),
          style: AppText.body(size: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppCopy.cancel(language)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppCopy.delete(language)),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    final deleted = await ctx.read<RunHistoryService>().deleteAllRunData();
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? AppCopy.deleteRunsDone(language)
              : AppCopy.deleteRunsFailed(language),
        ),
      ),
    );
  }

  Future<void> _toggleCloudRunStorage(BuildContext ctx) async {
    final settings = ctx.read<SettingsService>();
    final history = ctx.read<RunHistoryService>();
    final language = settings.appLanguage;
    final next = !settings.cloudRunStorageEnabled;
    await settings.setCloudRunStorageEnabled(next);
    if (!next) {
      await history.purgePendingUploads();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(AppCopy.pendingUploadsCleared(language))),
      );
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final messenger = ScaffoldMessenger.of(context);
    final language = context.read<SettingsService>().appLanguage;
    final uri = AppLinks.privacyPolicyUri;
    if (uri == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppCopy.privacyMissing(language))),
      );
      return;
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        messenger.showSnackBar(
          SnackBar(content: Text(AppCopy.privacyOpenFailed(language))),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppCopy.privacyOpenFailed(language))),
      );
    }
  }

  Future<void> _openGoogleMapsForRoute(
    BuildContext ctx,
    RevvRoute route,
  ) async {
    ctx.read<RouteService>().beginGuideToStart(route);
    final start = route.nodes.isNotEmpty ? route.nodes.first : route.centerPoint;
    final appUri = Uri.parse(
      'comgooglemaps://?daddr=${start.lat},${start.lng}&directionsmode=driving',
    );
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${start.lat},${start.lng}',
      'travelmode': 'driving',
    });
    await _launchExternalNavigation(appUri, webUri);
  }

  Future<void> _openWazeForRoute(BuildContext ctx, RevvRoute route) async {
    ctx.read<RouteService>().beginGuideToStart(route);
    final start = route.nodes.isNotEmpty ? route.nodes.first : route.centerPoint;
    final appUri = Uri.parse('waze://?ll=${start.lat},${start.lng}&navigate=yes');
    final webUri = Uri.https('waze.com', '/ul', {
      'll': '${start.lat},${start.lng}',
      'navigate': 'yes',
    });
    await _launchExternalNavigation(appUri, webUri);
  }

  Future<void> _launchExternalNavigation(Uri appUri, Uri webUri) async {
    final messenger = ScaffoldMessenger.of(context);
    final language = context.read<SettingsService>().appLanguage;
    final launchedApp = await launchUrl(appUri, mode: LaunchMode.externalApplication);
    if (launchedApp) return;
    final launchedWeb = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (launchedWeb) return;
    messenger.showSnackBar(
      SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
    );
  }

  void _showSettingsSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(
        onToggleCloud: () => unawaited(_toggleCloudRunStorage(ctx)),
        onDeleteHistory: () => _confirmDeleteRunData(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationService>();
    final routes = context.watch<RouteService>();
    final history = context.watch<RunHistoryService>();
    final settings = context.watch<SettingsService>();
    final supabase = context.watch<SupabaseService>();
    final language = settings.appLanguage;
    final lastRun = history.history.isNotEmpty ? history.history.first : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 헤더 ──
              Row(
                children: [
                  Text(
                    'REVV',
                    style: AppText.technicalLabel(
                      size: 16,
                      letterSpacing: 6,
                      color: AppColors.primaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'v1.38.0+42',
                    style: AppText.technicalLabel(
                      size: 9,
                      letterSpacing: 1.3,
                      color: AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  _LeanLanguageToggle(
                    language: language,
                    onChanged: settings.setAppLanguage,
                  ),
                  const SizedBox(width: 8),
                  // 음성 토글
                  GestureDetector(
                    onTap: () => settings.setTtsMuted(!settings.ttsMuted),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.panel.withValues(alpha: 0.78),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Icon(
                        settings.ttsMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        size: 16,
                        color: settings.ttsMuted
                            ? AppColors.textHint
                            : AppColors.primaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _LeanStatusDot(
                    active: supabase.isCloudAvailable,
                    label: supabase.isCloudAvailable ? 'CLOUD' : 'LOCAL',
                  ),
                ],
              ),

              const Spacer(),

              // ── 타이틀 ──
              Text(
                AppCopy.homeTitle(language),
                style: AppText.display(
                  size: 48,
                  height: 0.92,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 28),

              // ── 루트 찾기 버튼 ──
              _LeanPrimaryButton(
                label: AppCopy.routeFinder(language),
                icon: Icons.travel_explore_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LeanRouteFinderScreen(),
                    ),
                  );
                },
              ),

              // ── 시작점 안내 카드 ──
              if (routes.pendingGuideRoute != null) ...[
                const SizedBox(height: 14),
                _GuideToStartCard(
                  route: routes.pendingGuideRoute!,
                  current: location.bestKnownLatLng,
                  onGoogle: () => _openGoogleMapsForRoute(
                    context,
                    routes.pendingGuideRoute!,
                  ),
                  onWaze: () =>
                      _openWazeForRoute(context, routes.pendingGuideRoute!),
                  onStart: () =>
                      unawaited(_startFromGuideCard(routes.pendingGuideRoute!)),
                  onCancel: () {
                    _guidePromptShown = false;
                    routes.clearGuideToStart();
                  },
                ),
              ],

              // ── 마지막 주행 카드 ──
              if (lastRun != null) ...[
                const SizedBox(height: 14),
                _LastRunCard(run: lastRun, language: language),
              ],

              const Spacer(),

              // ── 통계 한 줄 ──
              if (history.totalRuns > 0) ...[
                _StatsLine(history: history),
                const SizedBox(height: 16),
              ],

              // ── 푸터 ──
              Row(
                children: [
                  _HomeIconButton(
                    icon: Icons.my_location_rounded,
                    onTap: _primeLocation,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _openPrivacyPolicy,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textHint,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      AppCopy.privacyPolicy(language),
                      style: AppText.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _HomeIconButton(
                    icon: Icons.settings_outlined,
                    onTap: () => _showSettingsSheet(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 마지막 주행 카드 ──────────────────────────────────────

class _LastRunCard extends StatelessWidget {
  final RunSummary run;
  final AppLanguage language;

  const _LastRunCard({required this.run, required this.language});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(run.date);
    final relDate = _relativeDate(diff, language);
    final distText = '${run.distanceKm.toStringAsFixed(1)} km';
    final hasG = run.maxLateralG != null && run.maxLateralG! > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppCopy.t(
                  language,
                  ko: 'LAST DRIVE',
                  en: 'LAST DRIVE',
                  fr: 'DERNIER TRAJET',
                ),
                style: AppText.technicalLabel(
                  size: 9,
                  letterSpacing: 1.6,
                  color: AppColors.textHint,
                ),
              ),
              const Spacer(),
              Text(
                relDate,
                style: AppText.technicalLabel(
                  size: 9,
                  letterSpacing: 1.2,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            run.routeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 17,
              weight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RunPill(label: distText),
              const SizedBox(width: 7),
              _RunPill(label: run.durationDisplay),
              if (hasG) ...[
                const SizedBox(width: 7),
                _RunPill(
                  label: '${run.maxLateralG!.toStringAsFixed(2)}G',
                  accent: true,
                ),
              ],
              if (run.weatherEmoji.isNotEmpty) ...[
                const SizedBox(width: 7),
                _RunPill(label: run.weatherEmoji),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _relativeDate(Duration diff, AppLanguage language) {
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return AppCopy.t(
        language,
        ko: m < 2 ? '방금' : '$m분 전',
        en: m < 2 ? 'just now' : '${m}m ago',
        fr: m < 2 ? 'à l\'instant' : 'il y a ${m}min',
      );
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return AppCopy.t(
        language,
        ko: '$h시간 전',
        en: '${h}h ago',
        fr: 'il y a ${h}h',
      );
    }
    final d = diff.inDays;
    if (d == 1) {
      return AppCopy.t(language, ko: '어제', en: 'yesterday', fr: 'hier');
    }
    return AppCopy.t(
      language,
      ko: '$d일 전',
      en: '${d}d ago',
      fr: 'il y a ${d}j',
    );
  }
}

class _RunPill extends StatelessWidget {
  final String label;
  final bool accent;

  const _RunPill({required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.primaryContainer.withValues(alpha: 0.14)
            : AppColors.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent
              ? AppColors.primaryContainer.withValues(alpha: 0.28)
              : AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: AppText.body(
          size: 11,
          weight: FontWeight.w900,
          color: accent ? AppColors.primaryContainer : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── 통계 한 줄 ────────────────────────────────────────────

class _StatsLine extends StatelessWidget {
  final RunHistoryService history;

  const _StatsLine({required this.history});

  @override
  Widget build(BuildContext context) {
    final totalKm = history.totalDistanceKm;
    final kmText = totalKm >= 1000
        ? '${(totalKm / 1000).toStringAsFixed(1)}k km'
        : '${totalKm.toStringAsFixed(1)} km';
    final bestG = history.bestMaxG;
    final parts = [
      '${history.totalRuns} runs',
      kmText,
      if (bestG != null && bestG > 0) 'Best ${bestG.toStringAsFixed(2)}G',
    ];

    return Text(
      parts.join(' · '),
      style: AppText.technicalLabel(
        size: 10,
        letterSpacing: 1.4,
        color: AppColors.textHint,
      ),
    );
  }
}

// ── 푸터 아이콘 버튼 ──────────────────────────────────────

class _HomeIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HomeIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.panel.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

// ── 설정 시트 ─────────────────────────────────────────────

class _SettingsSheet extends StatelessWidget {
  final VoidCallback onToggleCloud;
  final VoidCallback onDeleteHistory;

  const _SettingsSheet({
    required this.onToggleCloud,
    required this.onDeleteHistory,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final language = settings.appLanguage;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF20F1214),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      AppCopy.t(
                        language,
                        ko: 'SETTINGS',
                        en: 'SETTINGS',
                        fr: 'RÉGLAGES',
                      ),
                      style: AppText.technicalLabel(
                        size: 10,
                        letterSpacing: 1.8,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 클라우드 저장 토글
              _SettingsTile(
                icon: settings.cloudRunStorageEnabled
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                label: settings.cloudRunStorageEnabled
                    ? AppCopy.cloudOff(language)
                    : AppCopy.cloudOn(language),
                onTap: () {
                  Navigator.pop(context);
                  onToggleCloud();
                },
              ),
              // 기록 삭제
              _SettingsTile(
                icon: Icons.delete_outline_rounded,
                label: AppCopy.deleteHistory(language),
                danger: true,
                onTap: () {
                  Navigator.pop(context);
                  onDeleteHistory();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: AppText.body(
                size: 15,
                weight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 시작점 안내 카드 ──────────────────────────────────────

class _GuideToStartCard extends StatelessWidget {
  final RevvRoute route;
  final LatLng? current;
  final VoidCallback onGoogle;
  final VoidCallback onWaze;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const _GuideToStartCard({
    required this.route,
    required this.current,
    required this.onGoogle,
    required this.onWaze,
    required this.onStart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final start = route.nodes.isNotEmpty
        ? route.nodes.first
        : route.centerPoint;
    final distanceKm = current == null
        ? route.distanceFromUser
        : RevvRoute.haversineKm(current!, start);
    final distanceText = distanceKm < 1
        ? '${(distanceKm * 1000).round()}m'
        : '${distanceKm.toStringAsFixed(1)}km';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.08),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_rounded,
                color: AppColors.primaryContainer,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppCopy.guidingToStart(language),
                  style: AppText.body(
                    size: 14,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                distanceText,
                style: AppText.technicalLabel(
                  size: 11,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            route.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TinyActionButton(
                  label: 'Google',
                  icon: Icons.map_rounded,
                  onTap: onGoogle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TinyActionButton(
                  label: 'Waze',
                  icon: Icons.navigation_rounded,
                  onTap: onWaze,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TinyActionButton(
                  label: AppCopy.start(language),
                  icon: Icons.play_arrow_rounded,
                  onTap: onStart,
                  primary: true,
                ),
              ),
              IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textHint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TinyActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _TinyActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: primary
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 15),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: AppText.body(size: 12, weight: FontWeight.w900),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 15),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.48),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: AppText.body(size: 12, weight: FontWeight.w900),
              ),
            ),
    );
  }
}

// ── 공통 위젯 ─────────────────────────────────────────────

class _LeanLanguageToggle extends StatelessWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  const _LeanLanguageToggle({required this.language, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLanguage.values
            .map(
              (item) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: item == language
                        ? AppColors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.shortLabel,
                    style: AppText.technicalLabel(
                      size: 9,
                      color: item == language
                          ? AppColors.onPrimary
                          : AppColors.textHint,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LeanStatusDot extends StatelessWidget {
  final bool active;
  final String label;

  const _LeanStatusDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: AppText.technicalLabel(size: 10, color: color)),
        ],
      ),
    );
  }
}

class _LeanPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LeanPrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 66,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(
          label,
          style: AppText.body(
            size: 18,
            weight: FontWeight.w900,
            color: AppColors.onPrimary,
          ),
        ),
      ),
    );
  }
}
