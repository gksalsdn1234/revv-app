import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_quality_profile.dart';

enum CopilotStartChoice { start, simulate }

Future<CopilotStartChoice?> showCopilotStartSheet(
  BuildContext context, {
  required RevvRoute route,
}) {
  return showModalBottomSheet<CopilotStartChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _CopilotStartSheet(route: route),
  );
}

class _CopilotStartSheet extends StatelessWidget {
  final RevvRoute route;

  const _CopilotStartSheet({required this.route});

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final profile = RouteQualityProfile.fromRoute(route, language: language);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
      language: language,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xF20F1214),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.34),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppCopy.copilotStartCheck(language),
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                route.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 23,
                  height: 1.05,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _AdviceLine(icon: Icons.flag_rounded, text: briefing.startAdvice),
              const SizedBox(height: 8),
              _AdviceLine(
                icon: Icons.psychology_rounded,
                text: briefing.primaryAdvice,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: briefing.decisionChips
                    .map((chip) => _Chip(label: chip))
                    .toList(),
              ),
              const SizedBox(height: 18),
              if (route.distanceFromUser >= 1.0) ...[
                Row(
                  children: [
                    Expanded(
                      child: _NavAppButton(
                        label: 'Google Maps',
                        icon: Icons.map_rounded,
                        onTap: () => _openGoogleMaps(context, route),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _NavAppButton(
                        label: 'Waze',
                        icon: Icons.navigation_rounded,
                        onTap: () => _openWaze(context, route),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.42,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(
                        AppCopy.cancel(language),
                        style: AppText.body(size: 14, weight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, CopilotStartChoice.start),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(
                        route.distanceFromUser >= 1.0
                            ? AppCopy.startHere(language)
                            : briefing.nextActionLabel,
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          size: 14,
                          weight: FontWeight.w900,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, CopilotStartChoice.simulate),
                  icon: const Icon(Icons.science_rounded, size: 17),
                  label: Text(AppCopy.testDriveNow(language)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryContainer,
                    side: BorderSide(
                      color: AppColors.primaryContainer.withValues(alpha: 0.28),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: AppText.body(size: 13, weight: FontWeight.w900),
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

Future<void> _openGoogleMaps(BuildContext context, RevvRoute route) async {
  context.read<RouteService>().beginGuideToStart(route);
  final start = _routeStart(route);
  final appUri = Uri.parse(
    'comgooglemaps://?daddr=${start.lat},${start.lng}&directionsmode=driving',
  );
  final webUri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${start.lat},${start.lng}',
    'travelmode': 'driving',
  });
  await _launchNavigationUri(context, appUri: appUri, fallbackUri: webUri);
}

Future<void> _openWaze(BuildContext context, RevvRoute route) async {
  context.read<RouteService>().beginGuideToStart(route);
  final start = _routeStart(route);
  final appUri = Uri.parse('waze://?ll=${start.lat},${start.lng}&navigate=yes');
  final webUri = Uri.https('waze.com', '/ul', {
    'll': '${start.lat},${start.lng}',
    'navigate': 'yes',
  });
  await _launchNavigationUri(context, appUri: appUri, fallbackUri: webUri);
}

Future<void> _launchNavigationUri(
  BuildContext context, {
  required Uri appUri,
  required Uri fallbackUri,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final language = context.read<SettingsService>().appLanguage;
  final launchedApp = await launchUrl(
    appUri,
    mode: LaunchMode.externalApplication,
  );
  if (launchedApp) {
    _returnToHomeAfterNavigationLaunch(navigator);
    return;
  }

  final launchedWeb = await launchUrl(
    fallbackUri,
    mode: LaunchMode.externalApplication,
  );
  if (launchedWeb) {
    _returnToHomeAfterNavigationLaunch(navigator);
    return;
  }
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
  );
}

void _returnToHomeAfterNavigationLaunch(NavigatorState navigator) {
  if (navigator.canPop()) {
    navigator.popUntil((route) => route.isFirst);
  }
}

LatLng _routeStart(RevvRoute route) {
  if (route.nodes.isNotEmpty) return route.nodes.first;
  return route.centerPoint;
}

class _NavAppButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _NavAppButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryContainer,
        side: BorderSide(
          color: AppColors.primaryContainer.withValues(alpha: 0.38),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: AppText.body(size: 13, weight: FontWeight.w900),
      ),
    );
  }
}

class _AdviceLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdviceLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryContainer, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: AppText.body(
              size: 13,
              height: 1.35,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppText.body(
          size: 11,
          weight: FontWeight.w900,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
