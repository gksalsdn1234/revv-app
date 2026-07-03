import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../services/route_loading_policy.dart';
import '../core/app_links.dart';
import '../models/revv_route.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
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
import 'lean_drive_planner_screen.dart';
import 'lean_route_finder_screen.dart';
import 'lean_run_summary_screen.dart';

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
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
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
    await _openRouteNavigation(
      ctx,
      route,
      appUri: (start) => Uri.parse(
        'comgooglemaps://?daddr=${start.lat},${start.lng}&directionsmode=driving',
      ),
      webUri: (start) => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '${start.lat},${start.lng}',
        'travelmode': 'driving',
      }),
    );
  }

  Future<void> _openWazeForRoute(BuildContext ctx, RevvRoute route) async {
    await _openRouteNavigation(
      ctx,
      route,
      appUri: (start) =>
          Uri.parse('waze://?ll=${start.lat},${start.lng}&navigate=yes'),
      webUri: (start) => Uri.https('waze.com', '/ul', {
        'll': '${start.lat},${start.lng}',
        'navigate': 'yes',
      }),
    );
  }

  Future<void> _openRouteNavigation(
    BuildContext ctx,
    RevvRoute route, {
    required Uri Function(LatLng start) appUri,
    required Uri Function(LatLng start) webUri,
  }) async {
    ctx.read<RouteService>().beginGuideToStart(route);
    final start = route.nodes.isNotEmpty
        ? route.nodes.first
        : route.centerPoint;
    await _launchExternalNavigation(appUri(start), webUri(start));
  }

  Future<void> _launchExternalNavigation(Uri appUri, Uri webUri) async {
    final messenger = ScaffoldMessenger.of(context);
    final language = context.read<SettingsService>().appLanguage;
    final launchedApp = await launchUrl(
      appUri,
      mode: LaunchMode.externalApplication,
    );
    if (launchedApp) return;
    final launchedWeb = await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
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
        onPrivacy: _openPrivacyPolicy,
      ),
    );
  }

  void _showHistorySheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const HistorySheet(),
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
    final readyCount = routes.routes.length;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'REVV',
                    style: AppText.label(
                      size: 24,
                      weight: FontWeight.w900,
                      letterSpacing: 3,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 5,
                    height: 18,
                    color: AppColors.primaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LeanLanguageToggle(
                              language: language,
                              onChanged: settings.setAppLanguage,
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () =>
                                  settings.setTtsMuted(!settings.ttsMuted),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppColors.ink.withValues(alpha: 0.07),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.ink.withValues(
                                      alpha: 0.14,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  settings.ttsMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: 16,
                                  color: settings.ttsMuted
                                      ? AppColors.stone
                                      : AppColors.primaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _LeanStatusDot(
                              active: supabase.isCloudAvailable,
                              label: supabase.isCloudAvailable
                                  ? 'SYNCED'
                                  : 'LOCAL',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.ink,
                              ),
                              child: CustomPaint(
                                painter: _CheckeredPainter(
                                  tileSize: 7,
                                  color: AppColors.cream,
                                ),
                                size: const Size(double.infinity, 10),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'READY TO RUN',
                                        style: AppText.mono(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          letterSpacing: 2,
                                          color: AppColors.primaryContainer,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$readyCount ROUTES NEARBY',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: AppText.mono(
                                            size: 10,
                                            color: AppColors.stone,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    AppCopy.t(
                                      language,
                                      ko: '도로를 찾고\n주행을 시작하세요.',
                                      en: 'Find the road.\nStart the drive.',
                                      fr: 'Trouvez la route.\nLancez le run.',
                                    ),
                                    style: AppText.rajdhani(
                                      size: 40,
                                      weight: FontWeight.w800,
                                      height: 0.95,
                                      color: AppColors.cream,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            AppColors.primaryContainer,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const LeanRouteFinderScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 20,
                                      ),
                                      label: Text(
                                        AppCopy.routeFinder(
                                          language,
                                        ).toUpperCase(),
                                        style: AppText.label(
                                          size: 19,
                                          weight: FontWeight.w800,
                                          letterSpacing: 1.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 46,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.cream,
                                        side: BorderSide(
                                          color: AppColors.cream.withValues(
                                            alpha: 0.28,
                                          ),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const LeanDrivePlannerScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.alt_route_rounded,
                                        size: 19,
                                      ),
                                      label: Text(
                                        AppCopy.t(
                                          language,
                                          ko: '목적지까지 여정 만들기',
                                          en: 'Plan to destination',
                                          fr: 'Planifier la destination',
                                        ).toUpperCase(),
                                        style: AppText.label(
                                          size: 14,
                                          weight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          color: AppColors.cream,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (routes.pendingGuideRoute != null) ...[
                        const SizedBox(height: 14),
                        _GuideToStartCard(
                          route: routes.pendingGuideRoute!,
                          current: location.bestKnownLatLng,
                          onGoogle: () => _openGoogleMapsForRoute(
                            context,
                            routes.pendingGuideRoute!,
                          ),
                          onWaze: () => _openWazeForRoute(
                            context,
                            routes.pendingGuideRoute!,
                          ),
                          onStart: () => unawaited(
                            _startFromGuideCard(routes.pendingGuideRoute!),
                          ),
                          onCancel: () {
                            _guidePromptShown = false;
                            routes.clearGuideToStart();
                          },
                        ),
                      ],
                      if (lastRun != null) ...[
                        const SizedBox(height: 20),
                        _SectionHeader(
                          label: AppCopy.t(
                            language,
                            ko: 'RECENT RUNS',
                            en: 'RECENT RUNS',
                            fr: 'RUNS RÉCENTS',
                          ),
                          trailing: 'All ${history.totalRuns} →',
                          onTap: () => _showHistorySheet(context),
                        ),
                        const SizedBox(height: 10),
                        _LastRunCard(run: lastRun, language: language),
                      ],
                      if (history.totalRuns > 0) ...[
                        const SizedBox(height: 16),
                        _StatsLine(history: history),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _RaceBottomNav(
                current: _RaceTab.home,
                language: language,
                onHome: _primeLocation,
                onHistory: () => _showHistorySheet(context),
                onSettings: () => _showSettingsSheet(context),
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
    final hasCornerEvents = run.sharpCornersCount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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
                style: AppText.mono(
                  size: 9,
                  letterSpacing: 1.6,
                  color: AppColors.stone,
                ),
              ),
              const Spacer(),
              Text(
                relDate,
                style: AppText.mono(
                  size: 9,
                  letterSpacing: 1.2,
                  color: AppColors.stone,
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
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RunPill(label: distText),
              const SizedBox(width: 7),
              _RunPill(label: run.durationDisplay),
              if (hasCornerEvents) ...[
                const SizedBox(width: 7),
                _RunPill(
                  label: AppCopy.t(
                    language,
                    ko: '${run.sharpCornersCount} 코너',
                    en: '${run.sharpCornersCount} corners',
                    fr: '${run.sharpCornersCount} virages',
                  ),
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
            ? AppColors.primaryContainer.withValues(alpha: 0.10)
            : AppColors.creamMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent
              ? AppColors.primaryContainer.withValues(alpha: 0.28)
              : AppColors.ink.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        label,
        style: AppText.mono(
          size: 11,
          weight: FontWeight.w700,
          color: accent ? AppColors.primaryContainer : AppColors.ink,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  const _SectionHeader({required this.label, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppText.mono(
            size: 10,
            letterSpacing: 1.8,
            color: AppColors.stone,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          GestureDetector(
            onTap: onTap,
            child: Text(
              trailing!,
              style: AppText.label(
                size: 14,
                weight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.primaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}

enum _RaceTab { home, history, settings }

class _RaceBottomNav extends StatelessWidget {
  final _RaceTab current;
  final AppLanguage language;
  final VoidCallback onHome;
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  const _RaceBottomNav({
    required this.current,
    required this.language,
    required this.onHome,
    required this.onHistory,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 15),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.ink.withValues(alpha: 0.12),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RaceNavItem(
              icon: Icons.home_outlined,
              label: AppCopy.homeNav(language),
              active: current == _RaceTab.home,
              onTap: onHome,
            ),
          ),
          Expanded(
            child: _RaceNavItem(
              icon: Icons.history_rounded,
              label: AppCopy.history(language),
              active: current == _RaceTab.history,
              onTap: onHistory,
            ),
          ),
          Expanded(
            child: _RaceNavItem(
              icon: Icons.settings_outlined,
              label: AppCopy.settingsNav(language),
              active: current == _RaceTab.settings,
              onTap: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RaceNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.ink : AppColors.stone;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(
                size: 12,
                weight: FontWeight.w800,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ],
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
    final parts = ['${history.totalRuns} runs', kmText];

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.mono(size: 10, letterSpacing: 1.4, color: AppColors.stone),
    );
  }
}

typedef HistoryReportOpener =
    Future<void> Function(
      BuildContext context,
      RunSummary summary,
      RunTelemetryDetail? detail,
    );

class HistorySheet extends StatelessWidget {
  final HistoryReportOpener? onOpenReport;

  const HistorySheet({super.key, this.onOpenReport});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RunHistoryService>();
    final runs = history.history;
    final bestRevv = runs.fold<int?>(
      null,
      (best, run) => run.revvScore == null
          ? best
          : best == null || run.revvScore! > best
          ? run.revvScore
          : best,
    );

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.84,
        minChildSize: 0.46,
        maxChildSize: 0.94,
        builder: (context, controller) {
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            decoration: const BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: ListView(
              controller: controller,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'HISTORY',
                  style: AppText.technicalLabel(
                    size: 10,
                    letterSpacing: 2,
                    color: AppColors.stone,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Season log',
                  style: AppText.display(
                    size: 40,
                    height: 0.94,
                    weight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _HistoryMetric(
                      label: 'RUNS',
                      value: '${history.totalRuns}',
                    ),
                    _HistoryMetric(
                      label: 'KM TOTAL',
                      value: history.totalDistanceKm.toStringAsFixed(0),
                    ),
                    _HistoryMetric(
                      label: 'AVG KM',
                      value: history.totalRuns == 0
                          ? '--'
                          : (history.totalDistanceKm / history.totalRuns)
                                .toStringAsFixed(1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _HistoryMetric(
                      label: 'TIME',
                      value: _compactDuration(
                        runs.fold<int>(
                          0,
                          (sum, run) => sum + run.durationSeconds,
                        ),
                      ),
                    ),
                    _HistoryMetric(
                      label: 'REVV',
                      value: bestRevv == null ? '--' : '$bestRevv',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _MiniDistanceChart(runs: runs.take(8).toList()),
                const SizedBox(height: 22),
                Text(
                  'Recent',
                  style: AppText.label(
                    size: 18,
                    weight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                if (runs.isEmpty)
                  Text(
                    'No runs yet',
                    style: AppText.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.stone,
                    ),
                  )
                else
                  for (var i = 0; i < runs.length && i < 12; i++)
                    _HistoryRunRow(
                      rank: i + 1,
                      run: runs[i],
                      onTap: () => _openRunReport(context, runs[i]),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _compactDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}H ${minutes}M';
    return '${minutes}M';
  }

  Future<void> _openRunReport(BuildContext context, RunSummary run) async {
    final history = context.read<RunHistoryService>();
    final navigator = Navigator.of(context);
    navigator.pop();
    final detail = await history.loadDetail(run.id);
    if (!navigator.mounted) return;
    if (onOpenReport != null) {
      await onOpenReport!(navigator.context, run, detail);
      return;
    }
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              LeanRunSummaryScreen.history(summary: run, detail: detail),
        ),
      ),
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppText.technicalLabel(
                size: 8,
                letterSpacing: 1.2,
                color: AppColors.stoneMuted,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.display(
                size: 24,
                height: 0.9,
                weight: FontWeight.w900,
                color: AppColors.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDistanceChart extends StatelessWidget {
  final List<RunSummary> runs;

  const _MiniDistanceChart({required this.runs});

  @override
  Widget build(BuildContext context) {
    final values = runs.map((run) => run.distanceKm).toList();
    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    return Container(
      height: 96,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DISTANCE · LAST RUNS',
            style: AppText.technicalLabel(
              size: 9,
              letterSpacing: 1.2,
              color: AppColors.stone,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final value
                    in values.isEmpty ? const [0.4, 0.7, 0.5] : values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FractionallySizedBox(
                        heightFactor: (value / maxValue).clamp(0.16, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
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

class _HistoryRunRow extends StatelessWidget {
  final int rank;
  final RunSummary run;
  final VoidCallback onTap;

  const _HistoryRunRow({
    required this.rank,
    required this.run,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final peak = run.peakG;
    final metrics = [
      '${run.distanceKm.toStringAsFixed(1)}KM',
      run.durationDisplay.toUpperCase(),
      if (run.revvScore != null) 'REVV ${run.revvScore}',
      if (run.windingSamplePct != null)
        'WINDING ${run.windingSamplePct!.round()}%',
      if (run.sharpCornersCount > 0) '${run.sharpCornersCount} CURVES',
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.ink.withValues(alpha: 0.10)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: AppText.display(
                  size: 24,
                  height: 1,
                  weight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const _RouteGlyph(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.routeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      size: 15,
                      weight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metrics.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.technicalLabel(
                      size: 9,
                      letterSpacing: 0.3,
                      color: AppColors.stone,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  peak == null ? '--' : peak.toStringAsFixed(2),
                  style: AppText.display(
                    size: 24,
                    height: 1,
                    weight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  _shortDate(run.date).toUpperCase(),
                  style: AppText.technicalLabel(
                    size: 9,
                    letterSpacing: 0.5,
                    color: AppColors.stoneMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime date) {
    final now = DateTime.now();
    final days = now.difference(date).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yday';
    return '${date.month}/${date.day}';
  }
}

class _RouteGlyph extends StatelessWidget {
  const _RouteGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.creamMuted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: CustomPaint(painter: _RouteGlyphPainter()),
    );
  }
}

class _RouteGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.32,
        size.width * 0.58,
        size.height * 0.50,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.68,
        size.width * 0.82,
        size.height * 0.22,
      );
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.72),
      2.4,
      Paint()..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 설정 시트 ─────────────────────────────────────────────

class _SettingsSheet extends StatelessWidget {
  final VoidCallback onToggleCloud;
  final VoidCallback onDeleteHistory;
  final VoidCallback onPrivacy;

  const _SettingsSheet({
    required this.onToggleCloud,
    required this.onDeleteHistory,
    required this.onPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final history = context.watch<RunHistoryService>();
    final language = settings.appLanguage;
    final runCount = history.history.length;
    final profileMeta = runCount == 0
        ? AppCopy.noSavedRuns(language)
        : () {
            final memberSince = _profileStartMonth(history.history, language);
            return AppCopy.profileRunsMeta(language, runCount, memberSince);
          }();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SingleChildScrollView(
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
                        AppCopy.settingsGarage(language).toUpperCase(),
                        style: AppText.technicalLabel(
                          size: 10,
                          letterSpacing: 1.8,
                          color: AppColors.stone,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'R',
                            style: AppText.display(
                              size: 22,
                              weight: FontWeight.w900,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppCopy.anonymousDriver(language),
                                style: AppText.label(
                                  size: 20,
                                  weight: FontWeight.w900,
                                  color: AppColors.cream,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profileMeta,
                                style: AppText.technicalLabel(
                                  size: 10,
                                  letterSpacing: 0.5,
                                  color: AppColors.stoneMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _SettingsGroupLabel(
                  label: AppCopy.settingsUnitsDisplay(language).toUpperCase(),
                ),
                _SettingsSegmentTile(
                  label: AppCopy.settingsDistance(language),
                  left: 'KM',
                  right: 'MI',
                  leftActive: settings.distUnit != 'mi',
                  onLeft: () => settings.setDistUnit('km'),
                  onRight: () => settings.setDistUnit('mi'),
                ),
                _SettingsInfoTile(
                  label: AppCopy.settingsLanguage(language),
                  value: language.label,
                ),
                const SizedBox(height: 10),
                _SettingsGroupLabel(
                  label: AppCopy.settingsDrive(language).toUpperCase(),
                ),
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
                _SettingsInfoTile(
                  label: AppCopy.settingsCloudSync(language),
                  value: AppCopy.cloudSyncDetail(language),
                ),
                _SettingsToggleRow(
                  label: AppCopy.settingsVoiceGuidance(language),
                  detail: AppCopy.voiceGuidanceDetail(language),
                  active: !settings.ttsMuted,
                  onTap: () => settings.setTtsMuted(!settings.ttsMuted),
                ),
                _SettingsToggleRow(
                  label: AppCopy.settingsCurveAlerts(language),
                  detail: AppCopy.curveAlertsDetail(language),
                  active: true,
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                _SettingsGroupLabel(
                  label: AppCopy.settingsData(language).toUpperCase(),
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
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  label: AppCopy.privacyPolicy(language),
                  onTap: () {
                    Navigator.pop(context);
                    onPrivacy();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 14),
                  child: Text(
                    'REVV · BUILD 1.38.0+42',
                    style: AppText.technicalLabel(
                      size: 10,
                      letterSpacing: 1,
                      color: AppColors.stoneMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _profileStartMonth(List<RunSummary> history, AppLanguage language) {
  var firstRun = history.first.date;
  for (final run in history.skip(1)) {
    if (run.date.isBefore(firstRun)) firstRun = run.date;
  }
  final month = switch (language) {
    AppLanguage.french => const [
      'JANV',
      'FÉVR',
      'MARS',
      'AVR',
      'MAI',
      'JUIN',
      'JUIL',
      'AOÛT',
      'SEPT',
      'OCT',
      'NOV',
      'DÉC',
    ][firstRun.month - 1],
    AppLanguage.english => const [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ][firstRun.month - 1],
    _ => '${firstRun.year}.${firstRun.month.toString().padLeft(2, '0')}',
  };
  return language == AppLanguage.korean ? month : '$month ${firstRun.year}';
}

class _SettingsGroupLabel extends StatelessWidget {
  final String label;

  const _SettingsGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: AppText.technicalLabel(
            size: 9,
            letterSpacing: 1.6,
            color: AppColors.stone,
          ),
        ),
      ),
    );
  }
}

class _SettingsSegmentTile extends StatelessWidget {
  final String label;
  final String left;
  final String right;
  final bool leftActive;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _SettingsSegmentTile({
    required this.label,
    required this.left,
    required this.right,
    required this.leftActive,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.body(
                size: 15,
                weight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.ink.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                _SegmentOption(label: left, active: leftActive, onTap: onLeft),
                _SegmentOption(
                  label: right,
                  active: !leftActive,
                  onTap: onRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegmentOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: AppText.label(
            size: 12,
            weight: FontWeight.w800,
            color: active ? AppColors.cream : AppColors.stone,
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsInfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.body(
                size: 15,
                weight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.body(
                size: 14,
                weight: FontWeight.w700,
                color: AppColors.stone,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.stoneMuted),
        ],
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final String label;
  final String detail;
  final bool active;
  final VoidCallback onTap;

  const _SettingsToggleRow({
    required this.label,
    required this.detail,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppText.technicalLabel(
                      size: 10,
                      color: AppColors.stone,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            _TogglePill(active: active),
          ],
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final bool active;

  const _TogglePill({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 46,
      height: 27,
      padding: const EdgeInsets.all(3),
      alignment: active ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryContainer
            : AppColors.ink.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Container(
        width: 21,
        height: 21,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
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
    final color = danger ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 15,
                  weight: FontWeight.w800,
                  color: color,
                ),
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
            routeDisplayName(route),
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
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: AppText.mono(size: 10, color: AppColors.stone)),
        ],
      ),
    );
  }
}

// ── Checkered flag painter ────────────────────────────────

class _CheckeredPainter extends CustomPainter {
  final double tileSize;
  final Color color;

  const _CheckeredPainter({required this.tileSize, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.9);
    final cols = (size.width / tileSize).ceil() + 1;
    final rows = (size.height / tileSize).ceil() + 1;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        if ((row + col) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(col * tileSize, row * tileSize, tileSize, tileSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckeredPainter oldDelegate) =>
      tileSize != oldDelegate.tileSize || color != oldDelegate.color;
}
