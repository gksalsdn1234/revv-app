import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../core/app_links.dart';
import '../models/revv_route.dart';
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

  Future<void> _confirmDeleteRunData(BuildContext context) async {
    final language = context.read<SettingsService>().appLanguage;
    final confirmed = await showDialog<bool>(
      context: context,
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
    if (confirmed != true || !context.mounted) return;
    final deleted = await context.read<RunHistoryService>().deleteAllRunData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? AppCopy.deleteRunsDone(language)
              : AppCopy.deleteRunsFailed(language),
        ),
      ),
    );
  }

  Future<void> _toggleCloudRunStorage(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final history = context.read<RunHistoryService>();
    final language = settings.appLanguage;
    final next = !settings.cloudRunStorageEnabled;
    await settings.setCloudRunStorageEnabled(next);
    if (!next) {
      await history.purgePendingUploads();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
    BuildContext context,
    RevvRoute route,
  ) async {
    context.read<RouteService>().beginGuideToStart(route);
    final start = route.nodes.isNotEmpty
        ? route.nodes.first
        : route.centerPoint;
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

  Future<void> _openWazeForRoute(BuildContext context, RevvRoute route) async {
    context.read<RouteService>().beginGuideToStart(route);
    final start = route.nodes.isNotEmpty
        ? route.nodes.first
        : route.centerPoint;
    final appUri = Uri.parse(
      'waze://?ll=${start.lat},${start.lng}&navigate=yes',
    );
    final webUri = Uri.https('waze.com', '/ul', {
      'll': '${start.lat},${start.lng}',
      'navigate': 'yes',
    });
    await _launchExternalNavigation(appUri, webUri);
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

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationService>();
    final routes = context.watch<RouteService>();
    final history = context.watch<RunHistoryService>();
    final settings = context.watch<SettingsService>();
    final supabase = context.watch<SupabaseService>();
    final language = settings.appLanguage;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  const SizedBox(width: 10),
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
                  _LeanStatusDot(
                    active: supabase.isCloudAvailable,
                    label: supabase.isCloudAvailable ? 'CLOUD' : 'LOCAL',
                  ),
                ],
              ),
              const Spacer(),
              Text(
                AppCopy.homeTitle(language),
                style: AppText.display(
                  size: 48,
                  height: 0.92,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppCopy.homeSubtitle(language),
                style: AppText.body(
                  size: 15,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
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
              const SizedBox(height: 18),
              _LeanStatusGrid(
                items: [
                  _LeanStatusItem(
                    label: AppCopy.location(language),
                    value: location.hasPermission
                        ? AppCopy.ready(language)
                        : AppCopy.permissionNeeded(language),
                    active: location.hasPermission,
                  ),
                  _LeanStatusItem(
                    label: AppCopy.routes(language),
                    value: routes.routes.isEmpty
                        ? AppCopy.standby(language)
                        : AppCopy.countRoutes(language, routes.routes.length),
                    active: routes.routes.isNotEmpty,
                  ),
                  _LeanStatusItem(
                    label: AppCopy.history(language),
                    value: AppCopy.countRuns(language, history.totalRuns),
                    active: history.totalRuns > 0,
                  ),
                  _LeanStatusItem(
                    label: AppCopy.cloudRuns(language),
                    value: settings.cloudRunStorageEnabled
                        ? AppCopy.saved(language)
                        : AppCopy.off(language),
                    active: settings.cloudRunStorageEnabled,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _LeanGhostButton(
                      label: AppCopy.refreshLocation(language),
                      icon: Icons.my_location_rounded,
                      onTap: _primeLocation,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LeanGhostButton(
                      label: settings.ttsMuted
                          ? AppCopy.voiceOn(language)
                          : AppCopy.voiceOff(language),
                      icon: settings.ttsMuted
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      onTap: () => settings.setTtsMuted(!settings.ttsMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _LeanGhostButton(
                      label: settings.cloudRunStorageEnabled
                          ? AppCopy.cloudOff(language)
                          : AppCopy.cloudOn(language),
                      icon: settings.cloudRunStorageEnabled
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      onTap: () => unawaited(_toggleCloudRunStorage(context)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LeanGhostButton(
                      label: AppCopy.deleteHistory(language),
                      icon: Icons.delete_outline_rounded,
                      onTap: () => _confirmDeleteRunData(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _openPrivacyPolicy,
                  icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                  label: Text(
                    AppCopy.privacyPolicy(language),
                    style: AppText.body(
                      size: 12,
                      weight: FontWeight.w800,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _LeanGhostButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LeanGhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(
          color: AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: AppText.body(size: 13, weight: FontWeight.w800),
      ),
    );
  }
}

class _LeanStatusItem {
  final String label;
  final String value;
  final bool active;

  const _LeanStatusItem({
    required this.label,
    required this.value,
    required this.active,
  });
}

class _LeanStatusGrid extends StatelessWidget {
  final List<_LeanStatusItem> items;

  const _LeanStatusGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.7,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.panel.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      (item.active
                              ? AppColors.primaryContainer
                              : AppColors.outline)
                          .withValues(alpha: item.active ? 0.26 : 0.14),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: AppText.technicalLabel(
                        size: 10,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  Text(
                    item.value,
                    style: AppText.body(
                      size: 13,
                      weight: FontWeight.w900,
                      color: item.active
                          ? AppColors.primaryContainer
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
