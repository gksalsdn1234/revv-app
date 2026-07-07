import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/route_loading_policy.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_quality_profile.dart';

enum CopilotStartChoice { start, simulate }

typedef NavigationUrlLauncher = Future<bool> Function(
  Uri url, {
  required LaunchMode mode,
});

Future<bool> _defaultLaunchNavigationUrl(
  Uri url, {
  required LaunchMode mode,
}) {
  return launchUrl(url, mode: mode);
}

Future<CopilotStartChoice?> showCopilotStartSheet(
  BuildContext context, {
  required RevvRoute route,
  NavigationUrlLauncher launchNavigationUrl = _defaultLaunchNavigationUrl,
}) {
  return showModalBottomSheet<CopilotStartChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _CopilotStartSheet(
      route: route,
      launchNavigationUrl: launchNavigationUrl,
    ),
  );
}

class _CopilotStartSheet extends StatelessWidget {
  final RevvRoute route;
  final NavigationUrlLauncher launchNavigationUrl;

  const _CopilotStartSheet({
    required this.route,
    required this.launchNavigationUrl,
  });

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final displayName = routeDisplayName(route, language: language);
    final profile = RouteQualityProfile.fromRoute(route, language: language);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
      language: language,
    );
    final isFar = route.distanceFromUser >= 1.0;

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
              // ── 헤더 ──
              Text(
                AppCopy.copilotStartCheck(language),
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 8),
              // ── 루트 이름 + 시작점 거리 배지 ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 23,
                        height: 1.05,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isFar
                          ? AppColors.warning.withValues(alpha: 0.14)
                          : AppColors.primaryContainer.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isFar
                            ? AppColors.warning.withValues(alpha: 0.30)
                            : AppColors.primaryContainer.withValues(
                                alpha: 0.28,
                              ),
                      ),
                    ),
                    child: Text(
                      route.distanceFromUserDisplay,
                      style: AppText.technicalLabel(
                        size: 10,
                        color: isFar
                            ? AppColors.warning
                            : AppColors.primaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (isFar) ...[
                // ── 멀 때: 내비 우선 ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_car_rounded,
                            color: AppColors.warning,
                            size: 15,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            AppCopy.t(
                              language,
                              ko: '시작점까지 먼저 이동하세요',
                              en: 'Navigate to the start first',
                              fr: 'Allez d\'abord au point de départ',
                            ),
                            style: AppText.body(
                              size: 12,
                              weight: FontWeight.w900,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _NavAppButton(
                              label: 'Google Maps',
                              icon: Icons.map_rounded,
                              onTap: () => _openGoogleMaps(
                                context,
                                route,
                                launchNavigationUrl,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _NavAppButton(
                              label: 'Waze',
                              icon: Icons.navigation_rounded,
                              onTap: () =>
                                  _openWaze(context, route, launchNavigationUrl),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 그래도 바로 시작 — 보조 선택지
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(
                            color: AppColors.outlineVariant.withValues(
                              alpha: 0.38,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          AppCopy.cancel(language),
                          style: AppText.body(
                            size: 13,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, CopilotStartChoice.start),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(
                            color: AppColors.outlineVariant.withValues(
                              alpha: 0.52,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          AppCopy.startHere(language),
                          style: AppText.body(
                            size: 13,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // ── 가까울 때: 바로 시작 ──
                _AdviceLine(
                  icon: Icons.flag_rounded,
                  text: briefing.startAdvice,
                ),
                const SizedBox(height: 8),
                _AdviceLine(
                  icon: Icons.psychology_rounded,
                  text: briefing.primaryAdvice,
                ),
                const SizedBox(height: 14),
                if (briefing.decisionChips.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: briefing.decisionChips
                        .map((chip) => _Chip(label: chip))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
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
                          style: AppText.body(
                            size: 14,
                            weight: FontWeight.w900,
                          ),
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
                          briefing.nextActionLabel,
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
              ],

              // ── Test Drive: 공통 최하단 ──
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, CopilotStartChoice.simulate),
                  icon: const Icon(Icons.science_rounded, size: 15),
                  label: Text(AppCopy.testDriveNow(language)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textHint,
                    textStyle: AppText.body(size: 12, weight: FontWeight.w800),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
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

Future<void> _openGoogleMaps(
  BuildContext context,
  RevvRoute route,
  NavigationUrlLauncher launchNavigationUrl,
) async {
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
  await _launchNavigationUri(
    context,
    appUri: appUri,
    fallbackUri: webUri,
    launchNavigationUrl: launchNavigationUrl,
  );
}

Future<void> _openWaze(
  BuildContext context,
  RevvRoute route,
  NavigationUrlLauncher launchNavigationUrl,
) async {
  context.read<RouteService>().beginGuideToStart(route);
  final start = _routeStart(route);
  final appUri = Uri.parse('waze://?ll=${start.lat},${start.lng}&navigate=yes');
  final webUri = Uri.https('waze.com', '/ul', {
    'll': '${start.lat},${start.lng}',
    'navigate': 'yes',
  });
  await _launchNavigationUri(
    context,
    appUri: appUri,
    fallbackUri: webUri,
    launchNavigationUrl: launchNavigationUrl,
  );
}

Future<void> _launchNavigationUri(
  BuildContext context, {
  required Uri appUri,
  required Uri fallbackUri,
  required NavigationUrlLauncher launchNavigationUrl,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  final language = context.read<SettingsService>().appLanguage;

  var launched = false;
  try {
    launched = await launchNavigationUrl(
      appUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      launched = await launchNavigationUrl(
        fallbackUri,
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {
    launched = false;
  }

  if (launched) return navigator.pop();
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
  );
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
