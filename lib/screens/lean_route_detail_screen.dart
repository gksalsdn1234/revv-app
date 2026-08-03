import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/revv_route.dart';
import '../core/app_language.dart';
import '../services/external_nav.dart';
import '../services/route_invite_native_share.dart';
import '../services/route_loading_policy.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_detail_copy.dart';
import '../ui/route_drive_cue.dart';
import '../ui/route_quality_profile.dart';
import '../ui/route_share_card_content.dart';
import '../ui/route_share_card_widget.dart';
import '../widgets/copilot_start_sheet.dart';
import '../widgets/route_invite_preview_sheet.dart';
import 'lean_drive_screen.dart';

typedef RouteDetailUrlLauncher =
    Future<bool> Function(Uri url, {LaunchMode mode});

typedef RouteInvitePresenter =
    Future<RouteInviteShareOutcome> Function(RouteInviteSharePayload payload);

class StreetViewTarget {
  final LatLng point;
  final double bearing;

  const StreetViewTarget({required this.point, required this.bearing});
}

StreetViewTarget streetViewTargetForRoute(RevvRoute route) {
  if (route.nodes.isEmpty) {
    return StreetViewTarget(point: route.centerPoint, bearing: 0);
  }
  final index = route.nodes.length ~/ 2;
  final point = route.nodes[index];
  final next = index + 1 < route.nodes.length ? route.nodes[index + 1] : null;
  return StreetViewTarget(
    point: point,
    bearing: next == null ? 0 : _bearingDegrees(point, next),
  );
}

Uri buildStreetViewAppUri(StreetViewTarget target) {
  final point = _streetViewCoord(target.point);
  final bearing = target.bearing.toStringAsFixed(0);
  return Uri.parse('google.streetview:cbll=$point&cbp=0,$bearing,0,0,0');
}

Uri buildStreetViewWebUri(StreetViewTarget target) {
  return Uri.https('www.google.com', '/maps/@', {
    'api': '1',
    'map_action': 'pano',
    'viewpoint': _streetViewCoord(target.point),
    'heading': target.bearing.toStringAsFixed(0),
  });
}

Future<RouteInviteShareOutcome> _presentRouteInvite(
  RouteInviteSharePayload payload,
) {
  return RouteInviteNativeShare().share(payload);
}

class LeanRouteDetailScreen extends StatefulWidget {
  final RevvRoute route;
  final RouteDetailUrlLauncher? urlLauncher;
  final RouteInvitePresenter routeInvitePresenter;
  final RouteInviteCardExporter routeInviteCardExporter;

  const LeanRouteDetailScreen({
    super.key,
    required this.route,
    this.urlLauncher,
    this.routeInvitePresenter = _presentRouteInvite,
    this.routeInviteCardExporter = exportRouteShareCardPngBytes,
  });

  @override
  State<LeanRouteDetailScreen> createState() => _LeanRouteDetailScreenState();
}

class _LeanRouteDetailScreenState extends State<LeanRouteDetailScreen> {
  bool _sharingInvite = false;
  final GlobalKey _stickyStartBarKey = GlobalKey();
  double _stickyStartBarHeight = 0;

  void _measureStickyStartBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderBox =
          _stickyStartBarKey.currentContext?.findRenderObject() as RenderBox?;
      final height = renderBox?.size.height;
      if (height == null || (height - _stickyStartBarHeight).abs() < 0.5) {
        return;
      }
      setState(() => _stickyStartBarHeight = height);
    });
  }

  Future<void> _startDrive(BuildContext context) async {
    final startChoice = await showCopilotStartSheet(
      context,
      route: widget.route,
    );
    if (!context.mounted || startChoice == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(
          route: widget.route,
          simulated: startChoice == CopilotStartChoice.simulate,
        ),
      ),
    );
  }

  Future<void> _openStreetView(BuildContext context) async {
    final language = context.read<SettingsService>().appLanguage;
    final target = streetViewTargetForRoute(widget.route);
    final launcher = widget.urlLauncher ?? launchUrl;
    var launched = false;
    try {
      launched = await launcher(
        buildStreetViewAppUri(target),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        launched = await launcher(
          buildStreetViewWebUri(target),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      launched = false;
    }
    if (launched || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppCopy.t(
            language,
            ko: '로드뷰를 열지 못했어요.',
            en: 'Could not open Street View.',
            fr: 'Impossible d’ouvrir Street View.',
          ),
        ),
      ),
    );
  }

  Future<void> _shareRoute(BuildContext context, AppLanguage language) async {
    if (_sharingInvite) return;
    setState(() => _sharingInvite = true);
    try {
      final preview = await showRouteInvitePreviewSheet(
        context,
        route: widget.route,
        language: language,
        cardExporter: widget.routeInviteCardExporter,
      );
      if (!context.mounted || preview == null) return;

      final outcome = await widget.routeInvitePresenter(
        RouteInviteSharePayload(
          text: _buildRouteInviteText(widget.route, preview.draft, language),
          cardPng: preview.cardPng,
        ),
      );
      if (!context.mounted || outcome == RouteInviteShareOutcome.shared) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome == RouteInviteShareOutcome.cancelled
                ? AppCopy.t(
                    language,
                    ko: '초대 공유를 취소했어요.',
                    en: 'Invite sharing was cancelled.',
                    fr: 'Partage de l’invitation annulé.',
                  )
                : AppCopy.t(
                    language,
                    ko: '이 기기에서는 초대를 공유할 수 없어요.',
                    en: 'Invite sharing is unavailable on this device.',
                    fr: 'Le partage de l’invitation n’est pas disponible sur cet appareil.',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppCopy.t(
              language,
              ko: '루트를 공유하지 못했어요. 다시 시도해 주세요.',
              en: 'Could not share this route. Try again.',
              fr: 'Impossible de partager cette route. Réessayez.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final language = context.watch<SettingsService>().appLanguage;
    final copy = RouteDetailCopy.fromRoute(
      route,
      startDistanceKm: route.distanceFromUser,
      language: language,
    );
    final profile = RouteQualityProfile.fromRoute(route, language: language);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
      language: language,
    );
    final turnPlan = buildTurnByTurnPlan(route.nodes, language: language);
    final cautionBody = _cautionBody(copy);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bottomContentPadding = _stickyStartBarHeight + bottomInset + 28;
    _measureStickyStartBar();

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                              color: AppColors.ink,
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.creamMuted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              AppCopy.t(
                                language,
                                ko: '루트 상세',
                                en: 'ROUTE DETAIL',
                                fr: 'DÉTAIL ROUTE',
                              ),
                              style: AppText.mono(
                                size: 11,
                                color: AppColors.primaryContainer,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const Spacer(),
                            Tooltip(
                              message: AppCopy.t(
                                language,
                                ko: '루트 공유',
                                en: 'Share route',
                                fr: 'Partager la route',
                              ),
                              child: TextButton.icon(
                                onPressed: _sharingInvite
                                    ? null
                                    : () => _shareRoute(context, language),
                                icon: const Icon(
                                  Icons.ios_share_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  AppCopy.t(
                                    language,
                                    ko: '초대',
                                    en: 'Invite',
                                    fr: 'Inviter',
                                  ),
                                  style: AppText.mono(
                                    size: 10,
                                    weight: FontWeight.w800,
                                    color: AppColors.ink,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.ink,
                                  backgroundColor: AppColors.creamMuted,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _RouteShapeHero(route: route),
                        const SizedBox(height: 18),
                        _QuickStatRow(route: route, language: language),
                        if (_hasCurveMix(route)) ...[
                          const SizedBox(height: 12),
                          _CurveMixSection(route: route, language: language),
                        ],
                        if (_routeChainSegmentNames(route).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ChainSegmentsSection(
                            route: route,
                            language: language,
                          ),
                        ],
                        if (_hasElevationProfile(route)) ...[
                          const SizedBox(height: 12),
                          _ElevationProfileSection(
                            route: route,
                            language: language,
                          ),
                        ],
                        if (_hasRoadInfo(route)) ...[
                          const SizedBox(height: 12),
                          _RoadInfoSection(route: route, language: language),
                        ],
                        if (_hasJourneyInfo(route)) ...[
                          const SizedBox(height: 12),
                          _JourneyInfoSection(route: route, language: language),
                        ],
                        const SizedBox(height: 12),
                        _CopilotHeadlineCard(
                          briefing: briefing,
                          language: language,
                        ),
                        const SizedBox(height: 12),
                        _DriveEnvironmentRow(route: route, language: language),
                        const SizedBox(height: 12),
                        _StreetViewButton(
                          language: language,
                          onTap: () => _openStreetView(context),
                        ),
                        const SizedBox(height: 12),
                        _RouteDetailExpansion(
                          briefing: briefing,
                          copy: copy,
                          cautionBody: cautionBody,
                          turnPlan: turnPlan,
                          language: language,
                        ),
                        SizedBox(
                          height: bottomContentPadding,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: bottomInset + 14,
            child: KeyedSubtree(
              key: _stickyStartBarKey,
              child: KeyedSubtree(
                key: const ValueKey('route-detail-sticky-start-bar'),
                child: _StickyStartBar(
                  onStart: () => _startDrive(context),
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatRow extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _QuickStatRow({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final isFar = route.distanceFromUser >= 1.0;
    final curveTile = route.sharpCurveCount > 0
        ? _QuickStatTile(
            icon: Icons.route_rounded,
            label: AppCopy.t(
              language,
              ko: '커브',
              en: 'Curves',
              fr: 'Virages',
            ),
            value: AppCopy.t(
              language,
              ko: '${route.sharpCurveCount}개',
              en: '${route.sharpCurveCount}',
              fr: '${route.sharpCurveCount}',
            ),
          )
        : route.tightCurveKm > 0
        ? _QuickStatTile(
            icon: Icons.route_rounded,
            label: AppCopy.t(
              language,
              ko: '타이트',
              en: 'Tight',
              fr: 'Serrés',
            ),
            value: '${route.tightCurveKm.toStringAsFixed(1)}km',
          )
        : route.maxContinuousKm > 0
        ? _QuickStatTile(
            icon: Icons.timeline_rounded,
            label: AppCopy.t(
              language,
              ko: '연속',
              en: 'Flow',
              fr: 'Enchaîné',
            ),
            value: '${route.maxContinuousKm.toStringAsFixed(1)}km',
          )
        : null;
    return Container(
      key: const ValueKey('route-detail-stat-strip'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: tileWidth,
                child: _QuickStatTile(
                  icon: Icons.straighten_rounded,
                  label: AppCopy.t(
                    language,
                    ko: '거리',
                    en: 'Dist.',
                    fr: 'Dist.',
                  ),
                  value: route.distanceDisplay,
                ),
              ),
              SizedBox(
                width: tileWidth,
                child: _QuickStatTile(
                  icon: Icons.timer_outlined,
                  label: AppCopy.t(language, ko: '예상', en: 'ETA', fr: 'Temps'),
                  value: _driveMinutesLabel(route, language),
                ),
              ),
              if (curveTile != null)
                SizedBox(width: tileWidth, child: curveTile),
              SizedBox(
                width: tileWidth,
                child: _QuickStatTile(
                  icon: Icons.flag_rounded,
                  label: AppCopy.t(language, ko: '집', en: 'Home', fr: 'Maison'),
                  value: route.distanceFromUserDisplay,
                  accent: isFar
                      ? AppColors.warning
                      : AppColors.primaryContainer,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _QuickStatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = AppColors.stone,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(
                      size: 9,
                      weight: FontWeight.w800,
                      color: AppColors.stone,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: AppText.label(
                  size: 18,
                  weight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainSegmentsSection extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _ChainSegmentsSection({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final names = _routeChainSegmentNames(route);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppCopy.t(
              language,
              ko: '${names.length}개 코스 연결',
              en: '${names.length} linked routes',
              fr: '${names.length} routes reliées',
            ),
            style: AppText.mono(
              size: 10,
              color: AppColors.primaryContainer,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < names.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == names.length - 1 ? 0 : 6,
              ),
              child: Row(
                children: [
                  Text(
                    '${index + 1}.',
                    style: AppText.mono(
                      size: 11,
                      weight: FontWeight.w800,
                      color: AppColors.stone,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      names[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 13,
                        weight: FontWeight.w900,
                        color: AppColors.ink,
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

class _ElevationProfileSection extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _ElevationProfileSection({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final profile = route.elevationProfile!;
    final deltaM = _elevationDeltaM(route);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.terrain_rounded,
            title: AppCopy.t(
              language,
              ko: '고도 프로파일',
              en: 'ELEVATION PROFILE',
              fr: 'PROFIL ALTITUDE',
            ),
            trailing: AppCopy.t(
              language,
              ko: '고도차 ${deltaM.toStringAsFixed(0)}m',
              en: 'Delta ${deltaM.toStringAsFixed(0)}m',
              fr: 'Dénivelé ${deltaM.toStringAsFixed(0)}m',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            width: double.infinity,
            child: CustomPaint(
              painter: _ElevationProfilePainter(profile),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurveMixSection extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _CurveMixSection({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final tightKm = route.tightCurveKm.clamp(0, route.distanceKm).toDouble();
    final mediumKm = route.mediumCurveKm
        .clamp(0, math.max(0, route.distanceKm - tightKm))
        .toDouble();
    final gentleKm = math.max(0.0, route.distanceKm - tightKm - mediumKm);
    return Container(
      key: const ValueKey('route-detail-curve-mix'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.show_chart_rounded,
            title: AppCopy.t(
              language,
              ko: '커브 구성',
              en: 'CURVE MIX',
              fr: 'MIX VIRAGES',
            ),
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 13,
              child: Row(
                children: [
                  if (tightKm > 0)
                    _CurveBarSegment(km: tightKm, color: AppColors.red),
                  if (mediumKm > 0)
                    _CurveBarSegment(km: mediumKm, color: AppColors.orange),
                  if (gentleKm > 0)
                    _CurveBarSegment(km: gentleKm, color: AppColors.gold),
                ],
              ),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            AppCopy.t(
              language,
              ko: '타이트 ${route.tightCurveKm.toStringAsFixed(1)}km · 중간 ${route.mediumCurveKm.toStringAsFixed(1)}km · 직선/완만 ${gentleKm.toStringAsFixed(1)}km',
              en: 'Tight ${route.tightCurveKm.toStringAsFixed(1)}km · Medium ${route.mediumCurveKm.toStringAsFixed(1)}km · Straight/gentle ${gentleKm.toStringAsFixed(1)}km',
              fr: 'Serrés ${route.tightCurveKm.toStringAsFixed(1)}km · Moyens ${route.mediumCurveKm.toStringAsFixed(1)}km · Droits/doux ${gentleKm.toStringAsFixed(1)}km',
            ),
            style: AppText.body(
              size: 13,
              height: 1.32,
              weight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          if (route.maxContinuousKm > 0) ...[
            const SizedBox(height: 7),
            Text(
              AppCopy.t(
                language,
                ko: '최장 연속 와인딩 ${route.maxContinuousKm.toStringAsFixed(1)}km',
                en: 'Longest winding flow ${route.maxContinuousKm.toStringAsFixed(1)}km',
                fr: 'Plus long rythme sinueux ${route.maxContinuousKm.toStringAsFixed(1)}km',
              ),
              style: AppText.mono(
                size: 10,
                weight: FontWeight.w800,
                color: AppColors.primaryContainer,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoadInfoSection extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _RoadInfoSection({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final names = _roadInfoNames(route);
    final surface = route.surfaceSummary.trim();
    final speed = route.speedLimitSummary.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.signpost_rounded,
            title: AppCopy.t(
              language,
              ko: '도로 정보',
              en: 'ROAD INFO',
              fr: 'INFOS ROUTE',
            ),
          ),
          const SizedBox(height: 12),
          if (names.isNotEmpty)
            _InfoLine(icon: Icons.alt_route_rounded, text: names.join(' → ')),
          if (surface.isNotEmpty)
            _InfoLine(
              icon: Icons.layers_rounded,
              text: AppCopy.t(
                language,
                ko: '노면 $surface',
                en: 'Surface $surface',
                fr: 'Revêtement $surface',
              ),
            ),
          if (speed.isNotEmpty)
            _InfoLine(
              icon: Icons.speed_rounded,
              last: true,
              text: AppCopy.t(
                language,
                ko: '제한속도 표기 구간 $speed — 현장 표지 기준',
                en: 'Posted speed-limit sections $speed — follow roadside signs',
                fr: 'Sections avec vitesse affichée $speed — suivre les panneaux',
              ),
            ),
        ],
      ),
    );
  }
}

class _JourneyInfoSection extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _JourneyInfoSection({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final pois = _nearbyPoiNames(route);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.explore_rounded,
            title: AppCopy.t(
              language,
              ko: '여정 정보',
              en: 'JOURNEY INFO',
              fr: 'INFOS TRAJET',
            ),
          ),
          const SizedBox(height: 12),
          if (pois.isNotEmpty)
            _JourneyChip(
              text: AppCopy.t(
                language,
                ko: '주변: ${pois.join(' · ')}',
                en: 'Nearby: ${pois.join(' · ')}',
                fr: 'Autour: ${pois.join(' · ')}',
              ),
            ),
          if (route.runCount > 0)
            _JourneyChip(
              text: AppCopy.t(
                language,
                ko: 'REVV 주행 ${route.runCount}회',
                en: 'REVV runs ${route.runCount}',
                fr: 'Trajets REVV ${route.runCount}',
              ),
              accent: AppColors.primaryContainer,
            ),
          if (route.isLoop)
            _JourneyChip(text: 'LOOP', accent: AppColors.gold, last: true),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryContainer, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: AppText.mono(
              size: 10,
              color: AppColors.primaryContainer,
              letterSpacing: 1.6,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppText.mono(
              size: 10,
              weight: FontWeight.w800,
              color: AppColors.stone,
            ),
          ),
      ],
    );
  }
}

class _CurveBarSegment extends StatelessWidget {
  final double km;
  final Color color;

  const _CurveBarSegment({required this.km, required this.color});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: math.max(1, (km * 100).round()),
      child: ColoredBox(color: color, child: const SizedBox.expand()),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool last;

  const _InfoLine({required this.icon, required this.text, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.stone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppText.body(
                size: 13,
                height: 1.34,
                weight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyChip extends StatelessWidget {
  final String text;
  final Color accent;
  final bool last;

  const _JourneyChip({
    required this.text,
    this.accent = AppColors.stone,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Text(
            text,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w900,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _CopilotHeadlineCard extends StatelessWidget {
  final CopilotRouteBriefing briefing;
  final AppLanguage language;

  const _CopilotHeadlineCard({required this.briefing, required this.language});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('route-detail-copilot-headline'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.redSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_rounded,
                size: 20,
                color: AppColors.primaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                AppCopy.t(
                  language,
                  ko: '코파일럿 한 줄 판단',
                  en: 'COPILOT READ',
                  fr: 'LECTURE COPILOTE',
                ),
                style: AppText.mono(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            briefing.primaryAdvice,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 16,
              height: 1.28,
              weight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveEnvironmentRow extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _DriveEnvironmentRow({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final total = route.stopSignCount + route.trafficSignalCount;
    return Container(
      key: const ValueKey('route-detail-drive-environment'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (total == 0 ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              total == 0
                  ? Icons.check_circle_outline_rounded
                  : Icons.traffic_rounded,
              size: 21,
              color: total == 0 ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              total == 0
                  ? AppCopy.t(
                      language,
                      ko: '정지 요소 거의 없음',
                      en: 'Few stop controls',
                      fr: 'Peu d’arrêts',
                    )
                  : AppCopy.t(
                      language,
                      ko: '정지표지 ${route.stopSignCount} · 신호 ${route.trafficSignalCount}',
                      en: 'Stops ${route.stopSignCount} · signals ${route.trafficSignalCount}',
                      fr: 'Stops ${route.stopSignCount} · feux ${route.trafficSignalCount}',
                    ),
              style: AppText.body(
                size: 14,
                height: 1.25,
                weight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreetViewButton extends StatelessWidget {
  final AppLanguage language;
  final VoidCallback onTap;

  const _StreetViewButton({required this.language, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.streetview_rounded, size: 20),
        label: Text(
          AppCopy.t(language, ko: '로드뷰', en: 'Street View', fr: 'Street View'),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryContainer,
          side: BorderSide(
            color: AppColors.primaryContainer.withValues(alpha: 0.30),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: AppText.body(size: 14, weight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _RouteDetailExpansion extends StatelessWidget {
  final CopilotRouteBriefing briefing;
  final RouteDetailCopy copy;
  final String? cautionBody;
  final List<TurnInstruction> turnPlan;
  final AppLanguage language;

  const _RouteDetailExpansion({
    required this.briefing,
    required this.copy,
    required this.cautionBody,
    required this.turnPlan,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('route-detail-expansion'),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.primaryContainer,
          collapsedIconColor: AppColors.stone,
          title: Text(
            AppCopy.t(language, ko: '자세히', en: 'Details', fr: 'Détails'),
            style: AppText.mono(
              size: 10,
              weight: FontWeight.w900,
              color: AppColors.primaryContainer,
              letterSpacing: 1.6,
            ),
          ),
          subtitle: Text(
            briefing.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 13,
              weight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          children: [
            _CopilotJudgementRow(
              label: AppCopy.t(language, ko: '판단', en: 'Read', fr: 'Lecture'),
              text: briefing.primaryAdvice,
            ),
            _CopilotJudgementRow(
              label: AppCopy.t(language, ko: '시작', en: 'Start', fr: 'Départ'),
              text: briefing.startAdvice,
            ),
            if (cautionBody != null)
              _CopilotJudgementRow(
                label: AppCopy.t(language, ko: '주의', en: 'Risk', fr: 'Risque'),
                text: cautionBody!,
              ),
            _CopilotJudgementRow(
              label: AppCopy.t(language, ko: '성향', en: 'Fit', fr: 'Profil'),
              text: briefing.fitLabel,
            ),
            _CopilotJudgementRow(
              label: AppCopy.t(language, ko: '근거', en: 'Why', fr: 'Pourquoi'),
              text: copy.heroReason,
              last: copy.decisionBullets.isEmpty,
            ),
            if (copy.decisionBullets.isNotEmpty)
              _CopilotJudgementRow(
                label: AppCopy.t(language, ko: '선택', en: 'Choice', fr: 'Choix'),
                text: copy.decisionBullets.take(3).join('\n'),
                last: true,
              ),
            const SizedBox(height: 6),
            _TurnPlanPreview(plan: turnPlan, language: language),
          ],
        ),
      ),
    );
  }
}

class _CopilotJudgementRow extends StatelessWidget {
  final String label;
  final String text;
  final bool last;

  const _CopilotJudgementRow({
    required this.label,
    required this.text,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: AppText.mono(
                size: 9,
                color: AppColors.stone,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppText.body(
                size: 13,
                height: 1.36,
                weight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteShapeHero extends StatelessWidget {
  final RevvRoute route;

  const _RouteShapeHero({required this.route});

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return Container(
      key: const ValueKey('route-detail-hero'),
      height: 286,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ink, AppColors.surface, AppColors.surfaceLowest],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RouteShapePainter(route)),
          ),
          Positioned(
            left: 4,
            top: 2,
            right: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.difficultyLabel,
                  style: AppText.mono(
                    size: 10,
                    color: AppColors.primaryContainer,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  routeDisplayName(route, language: language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(
                    size: 32,
                    weight: FontWeight.w900,
                    color: AppColors.cream,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _HeroChip(label: route.difficultyLabel),
                    _HeroChip(label: route.curveStyle),
                    if (route.isLoop) const _HeroChip(label: 'LOOP'),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: _HeroBadge(
              label: AppCopy.t(language, ko: '시작점', en: 'START', fr: 'DÉPART'),
              value: route.distanceFromUserDisplay,
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: _HeroBadge(
              label: AppCopy.t(language, ko: '루트', en: 'ROUTE', fr: 'ROUTE'),
              value: route.distanceDisplay,
              alignRight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnPlanPreview extends StatelessWidget {
  final List<TurnInstruction> plan;
  final AppLanguage language;

  const _TurnPlanPreview({required this.plan, required this.language});

  @override
  Widget build(BuildContext context) {
    final visible = plan.take(5).toList();
    final hiddenCount = plan.length - visible.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.creamMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_rounded,
                color: AppColors.primaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppCopy.t(
                    language,
                    ko: '턴북',
                    en: 'TURN BOOK',
                    fr: 'CARNET VIRAGES',
                  ),
                  style: AppText.mono(
                    size: 10,
                    color: AppColors.primaryContainer,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Text(
                AppCopy.t(
                  language,
                  ko: '${plan.length}개 안내',
                  en: '${plan.length} cues',
                  fr: '${plan.length} repères',
                ),
                style: AppText.mono(size: 9, color: AppColors.stone),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            Text(
              AppCopy.t(
                language,
                ko: '루트 라인을 불러오면 턴 안내가 표시됩니다.',
                en: 'Turn guidance appears once the route line is loaded.',
                fr: 'Les repères apparaissent avec la ligne de route.',
              ),
              style: AppText.body(
                size: 13,
                height: 1.35,
                weight: FontWeight.w700,
                color: AppColors.stone,
              ),
            )
          else
            ...visible.map((instruction) {
              return _TurnPlanRow(instruction: instruction);
            }),
          if (hiddenCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              AppCopy.t(
                language,
                ko: '+$hiddenCount개 더',
                en: '+$hiddenCount more',
                fr: '+$hiddenCount autres',
              ),
              style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }
}

class _TurnPlanRow extends StatelessWidget {
  final TurnInstruction instruction;

  const _TurnPlanRow({required this.instruction});

  @override
  Widget build(BuildContext context) {
    final accent = instruction.finish
        ? AppColors.success
        : _turnSeverityColor(instruction.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Icon(instruction.icon, size: 16, color: accent),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              instruction.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                size: 13,
                weight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '#${instruction.sequence}',
            style: AppText.mono(size: 9, color: AppColors.stone),
          ),
        ],
      ),
    );
  }
}

Color _turnSeverityColor(int severity) {
  if (severity >= 3) return AppColors.primaryContainer;
  if (severity == 2) return AppColors.warning;
  return AppColors.gold;
}

class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.cream.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: AppText.mono(
          size: 9,
          weight: FontWeight.w900,
          color: AppColors.cream,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;
  final String value;
  final bool alignRight;

  const _HeroBadge({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.mono(size: 9, color: AppColors.stone)),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppText.label(
            size: 14,
            weight: FontWeight.w700,
            color: AppColors.cream,
          ),
        ),
      ],
    );
  }
}

class _StickyStartBar extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onBack;

  const _StickyStartBar({required this.onStart, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.ink,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.creamMuted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: onStart,
                child: Text(
                  AppCopy.t(
                    context.watch<SettingsService>().appLanguage,
                    ko: '주행 시작',
                    en: 'Start drive',
                    fr: 'Démarrer',
                  ),
                  style: AppText.label(
                    size: 16,
                    weight: FontWeight.w800,
                    color: AppColors.onPrimary,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteShapePainter extends CustomPainter {
  final RevvRoute route;

  const _RouteShapePainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = route.nodes;
    if (nodes.length < 2) return;

    var minLat = nodes.first.lat;
    var maxLat = nodes.first.lat;
    var minLng = nodes.first.lng;
    var maxLng = nodes.first.lng;
    for (final node in nodes) {
      minLat = math.min(minLat, node.lat);
      maxLat = math.max(maxLat, node.lat);
      minLng = math.min(minLng, node.lng);
      maxLng = math.max(maxLng, node.lng);
    }

    final latSpan = math.max(0.000001, maxLat - minLat);
    final lngSpan = math.max(0.000001, maxLng - minLng);
    final inset = math.min(size.width, size.height) * 0.14;
    final path = Path();

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final x =
          inset + ((node.lng - minLng) / lngSpan) * (size.width - inset * 2);
      final y =
          inset +
          (1 - (node.lat - minLat) / latSpan) * (size.height - inset * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 14;
    final casing = Paint()
      ..color = AppColors.surfaceLowest
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 9;
    final core = Paint()
      ..color = AppColors.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5;
    final glow = Paint()
      ..color = AppColors.primaryContainer.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 22
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawPath(path, glow);
    canvas.drawPath(path.shift(const Offset(0, 4)), shadow);
    canvas.drawPath(path, casing);
    canvas.drawPath(path, core);
  }

  @override
  bool shouldRepaint(covariant _RouteShapePainter oldDelegate) {
    return oldDelegate.route.id != route.id;
  }
}

class _ElevationProfilePainter extends CustomPainter {
  final List<double> profile;

  const _ElevationProfilePainter(this.profile);

  @override
  void paint(Canvas canvas, Size size) {
    final minElevation = profile.reduce(math.min);
    final maxElevation = profile.reduce(math.max);
    final span = math.max(1.0, maxElevation - minElevation);
    const horizontalInset = 4.0;
    const verticalInset = 8.0;
    final chartWidth = size.width - horizontalInset * 2;
    final chartHeight = size.height - verticalInset * 2;
    final path = Path();

    for (var i = 0; i < profile.length; i++) {
      final x = horizontalInset + (i / (profile.length - 1)) * chartWidth;
      final y =
          verticalInset +
          (1 - ((profile[i] - minElevation) / span)) * chartHeight;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width - horizontalInset, size.height - verticalInset)
      ..lineTo(horizontalInset, size.height - verticalInset)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primaryContainer.withValues(alpha: 0.20),
          AppColors.gold.withValues(alpha: 0.05),
        ],
      ).createShader(Offset.zero & size);
    final linePaint = Paint()
      ..color = AppColors.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;
    final guidePaint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(horizontalInset, size.height - verticalInset),
      Offset(size.width - horizontalInset, size.height - verticalInset),
      guidePaint,
    );
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ElevationProfilePainter oldDelegate) {
    return oldDelegate.profile != profile;
  }
}

bool _hasElevationProfile(RevvRoute route) {
  final profile = route.elevationProfile;
  return profile != null && profile.length >= 2;
}

double _elevationDeltaM(RevvRoute route) {
  if (route.elevationDelta > 0) return route.elevationDelta;
  final profile = route.elevationProfile;
  if (profile == null || profile.length < 2) return 0;
  return profile.reduce(math.max) - profile.reduce(math.min);
}

bool _hasCurveMix(RevvRoute route) {
  return route.distanceKm > 0 &&
      (route.tightCurveKm > 0 ||
          route.mediumCurveKm > 0 ||
          route.sharpCurveCount > 0);
}

bool _hasRoadInfo(RevvRoute route) {
  return _roadInfoNames(route).isNotEmpty ||
      route.surfaceSummary.trim().isNotEmpty ||
      route.speedLimitSummary.trim().isNotEmpty;
}

bool _hasJourneyInfo(RevvRoute route) {
  return _nearbyPoiNames(route).isNotEmpty ||
      route.runCount > 0 ||
      route.isLoop;
}

List<String> _roadInfoNames(RevvRoute route) {
  return route.roadNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .take(4)
      .toList(growable: false);
}

List<String> _nearbyPoiNames(RevvRoute route) {
  return route.nearbyPoiNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .take(3)
      .toList(growable: false);
}

String _driveMinutesLabel(RevvRoute route, AppLanguage language) {
  final minutes = estimatedDriveMinutes(route);
  return AppCopy.t(
    language,
    ko: '~$minutes분',
    en: '~$minutes min',
    fr: '~$minutes min',
  );
}

List<String> _routeChainSegmentNames(RevvRoute route) {
  if (!route.id.startsWith('combo:')) return const [];
  final names = route.name
      .split(' + ')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  if (names.length < 2) return const [];
  return names.take(3).toList(growable: false);
}

String _streetViewCoord(LatLng point) {
  return '${point.lat.toStringAsFixed(6)},${point.lng.toStringAsFixed(6)}';
}

double _bearingDegrees(LatLng from, LatLng to) {
  final fromLat = from.lat * math.pi / 180;
  final toLat = to.lat * math.pi / 180;
  final deltaLng = (to.lng - from.lng) * math.pi / 180;
  final y = math.sin(deltaLng) * math.cos(toLat);
  final x =
      math.cos(fromLat) * math.sin(toLat) -
      math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String _buildRouteInviteText(
  RevvRoute route,
  DriveInviteDraft draft,
  AppLanguage language,
) {
  // Route geometry is allowed only in the navigation URI below. The public
  // invitation copy uses the card-content allowlist and never includes the
  // optional meeting area, raw route name, road, POI, or telemetry fields.
  final content = buildRouteShareCardContent(
    route: route,
    draft: draft,
    language: language,
  );
  final details = [
    content.distanceLabel,
    content.durationLabel,
    content.schedule,
  ].join(' · ');
  final mapsLabel = AppCopy.t(
    language,
    ko: 'Google Maps에서 열기',
    en: 'Open in Google Maps',
    fr: 'Ouvrir dans Google Maps',
  );
  return '${content.headline}\n\n${content.routeName}\n$details\n\n$mapsLabel:\n${_routeInviteNavigationUri(route)}\n\n${content.footer}';
}

Uri _routeInviteNavigationUri(RevvRoute route) {
  // This is the approved, navigation-only geometry exception. In particular,
  // meeting areas are not encoded into the Google Maps URL.
  final points = selectRouteHandoffPoints(route.nodes);
  final origin = points.isEmpty ? route.centerPoint : points.first;
  final destination = points.length < 2 ? route.centerPoint : points.last;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': googleMapsCoord(origin),
    'destination': googleMapsCoord(destination),
    if (points.length > 2)
      'waypoints': points
          .sublist(1, points.length - 1)
          .map(googleMapsCoord)
          .join('|'),
    'travelmode': 'driving',
  });
}

String? _cautionBody(RouteDetailCopy copy) {
  final caution = copy.cautionLine?.trim();
  if (caution == null || caution.isEmpty) return null;
  return caution;
}
