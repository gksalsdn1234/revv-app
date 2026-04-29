import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/composite_route.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/saved_route_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/route_detail_copy.dart';
import '../ui/ux_contracts.dart';
import '../widgets/mini_elev_chart.dart';
import '../widgets/revv_ui.dart';

class RoutePreviewScreen extends StatefulWidget {
  final RevvRoute? route;
  final CompositeRoute? compositeRoute;

  const RoutePreviewScreen({super.key, this.route, this.compositeRoute})
    : assert(route != null || compositeRoute != null);

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  SprintStartMode _startMode = SprintStartMode.auto;

  RevvRoute get _displayRoute =>
      widget.compositeRoute?.toRouteProjection() ?? widget.route!;

  @override
  Widget build(BuildContext context) {
    final displayRoute = _displayRoute;
    final isSaved = context.watch<SavedRouteService>().isSaved(displayRoute.id);
    final location = context.watch<LocationService>();
    final startNode = displayRoute.nodes.isNotEmpty
        ? displayRoute.nodes.first
        : displayRoute.centerPoint;
    final startDistanceKm = RevvRoute.haversineKm(
      LatLng(location.lat, location.lng),
      startNode,
    );
    final startSummary = buildSprintStartSummary(startDistanceKm, _startMode);
    final copy = RouteDetailCopy.fromRoute(
      displayRoute,
      startDistanceKm: startDistanceKm,
      hasComposite: widget.compositeRoute != null,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: RevvTopBar(
        title: displayRoute.name,
        eyebrow: 'Pre-drive Setup',
        actions: [
          IconButton(
            onPressed: () =>
                context.read<SavedRouteService>().toggle(displayRoute),
            icon: Icon(
              isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isSaved ? AppColors.red : Colors.white54,
            ),
          ),
          IconButton(
            onPressed: () => _shareRoute(displayRoute),
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: RevvCockpitBackground(
        scanlines: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            RevvSectionHeader(
              eyebrow: 'Destination locked',
              title: displayRoute.name,
              trailing: RevvPill(
                label: widget.compositeRoute != null
                    ? 'COMPOSITE'
                    : displayRoute.difficultyLabel.toUpperCase(),
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 18),
            RevvGlassCard(
              padding: EdgeInsets.zero,
              glow: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ROUTE TELEMETRY',
                                style: AppText.technicalLabel(
                                  color: AppColors.primaryContainer,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                displayRoute.distanceKm.toStringAsFixed(1),
                                style: AppText.display(
                                  size: 52,
                                  weight: FontWeight.w900,
                                  color: AppColors.primaryContainer,
                                  letterSpacing: -3,
                                  height: 0.95,
                                ),
                              ),
                              Text(
                                'KILOMETERS',
                                style: AppText.technicalLabel(
                                  size: 10,
                                  color: AppColors.textHint,
                                  letterSpacing: 2.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryContainer.withValues(
                                  alpha: 0.28,
                                ),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.alt_route_rounded,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Text(
                      widget.compositeRoute != null
                          ? '재미 ${widget.compositeRoute!.funScore.toStringAsFixed(1)} / 흐름 ${widget.compositeRoute!.flowScore.toStringAsFixed(2)} / stop ${widget.compositeRoute!.stopSignCount}'
                          : '와인딩 ${displayRoute.windingScore.toStringAsFixed(1)} / 커브 ${displayRoute.sharpCurveCount}개 / ${displayRoute.distanceFromUserDisplay}',
                      style: AppText.body(
                        size: 14,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLowest.withValues(alpha: 0.54),
                      border: Border(
                        top: BorderSide(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.22,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: RevvMetricTile(
                            label: 'curves',
                            value: '${displayRoute.sharpCurveCount}',
                            unit: 'EA',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RevvMetricTile(
                            label: 'winding',
                            value: displayRoute.windingScore.toStringAsFixed(1),
                            accent: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            RevvGlassCard(
              padding: const EdgeInsets.all(16),
              color: AppColors.panel.withValues(alpha: 0.82),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'START MODE',
                    style: AppText.technicalLabel(
                      color: AppColors.primaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StartModeChip(
                        label: '자동',
                        selected: _startMode == SprintStartMode.auto,
                        onTap: () =>
                            setState(() => _startMode = SprintStartMode.auto),
                      ),
                      _StartModeChip(
                        label: '시작점까지 안내',
                        selected: _startMode == SprintStartMode.guideToStart,
                        onTap: () => setState(
                          () => _startMode = SprintStartMode.guideToStart,
                        ),
                      ),
                      _StartModeChip(
                        label: '중간 합류',
                        selected: _startMode == SprintStartMode.joinFromCurrent,
                        onTap: () => setState(
                          () => _startMode = SprintStartMode.joinFromCurrent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      startSummary,
                      style: AppText.body(
                        size: 14,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PreviewDecisionPanel(copy: copy),
            if (widget.compositeRoute == null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    label: displayRoute.qualityLabel.toUpperCase(),
                    color: displayRoute.qualityLabel == 'keep'
                        ? AppColors.success
                        : displayRoute.qualityLabel == 'maybe'
                        ? AppColors.warning
                        : AppColors.danger,
                  ),
                  if (displayRoute.routeCharacter.isNotEmpty)
                    _MetaChip(
                      label: displayRoute.routeCharacter
                          .replaceAll('_', ' ')
                          .toUpperCase(),
                    ),
                  if (displayRoute.stopSignCount > 0 ||
                      displayRoute.trafficSignalCount > 0)
                    _MetaChip(
                      label:
                          'STOP ${displayRoute.stopSignCount} · SIGNAL ${displayRoute.trafficSignalCount}',
                    ),
                ],
              ),
            ],
            if (widget.compositeRoute == null &&
                copy.cautionLine?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              RevvGlassCard(
                padding: const EdgeInsets.all(14),
                color: AppColors.warning.withValues(alpha: 0.08),
                borderOpacity: 0.34,
                child: Text(
                  copy.cautionLine!,
                  style: AppText.body(
                    size: 13,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            RevvGlassCard(
              padding: const EdgeInsets.all(14),
              child: MiniElevSection(
                route: displayRoute,
                lineColor: AppColors.red,
              ),
            ),
            if (widget.compositeRoute != null) ...[
              const SizedBox(height: 16),
              RevvGlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SEGMENTS', style: AppText.technicalLabel(size: 10)),
                    const SizedBox(height: 10),
                    ...[
                      widget.compositeRoute!.baseRoute,
                      ...widget.compositeRoute!.chainedSegments,
                    ].map(
                      (segment) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${segment.name} · ${segment.distanceKm.toStringAsFixed(1)} km',
                          style: AppText.body(
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (widget.compositeRoute!.connectorLegs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Connector ${widget.compositeRoute!.connectorLegs.first.distanceKm.toStringAsFixed(1)} km · ${widget.compositeRoute!.estimatedDurationMinutes} min est',
                          style: AppText.technicalLabel(
                            size: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: RevvGlassCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          radius: 28,
          color: AppColors.bg.withValues(alpha: 0.88),
          child: RevvPrimaryButton(
            label: sprintStartCtaLabel(_startMode),
            icon: Icons.bolt_rounded,
            onPressed: () {
              context.read<RouteService>().requestSprint(
                route:
                    widget.compositeRoute?.toRouteProjection() ?? widget.route,
                startMode: _startMode,
              );
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _shareRoute(RevvRoute route) {
    return SharePlus.instance.share(
      ShareParams(text: RouteDetailCopy.fromRoute(route).shareText),
    );
  }
}

class _PreviewDecisionPanel extends StatelessWidget {
  final RouteDetailCopy copy;

  const _PreviewDecisionPanel({required this.copy});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: RevvGlassCard(
        padding: const EdgeInsets.all(14),
        color: AppColors.panel.withValues(alpha: 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DRIVE DECISION',
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.primaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            ...copy.decisionBullets.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 7),
                      decoration: const BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: AppText.body(
                          size: 13,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color? color;

  const _MetaChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.white.withValues(alpha: 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: color == null ? 0.10 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (color ?? AppColors.outline).withValues(alpha: 0.30),
        ),
      ),
      child: Text(
        label,
        style: AppText.technicalLabel(
          size: 10,
          color: color ?? Colors.white70,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _StartModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StartModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryContainer
              : AppColors.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer
                : AppColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
        child: Text(
          label,
          style: AppText.body(
            size: 13,
            weight: FontWeight.w800,
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
