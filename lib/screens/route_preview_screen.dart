import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/composite_route.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../theme/colors.dart';
import '../ui/ux_contracts.dart';
import '../widgets/mini_elev_chart.dart';

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
    final location = context.watch<LocationService>();
    final startNode = displayRoute.nodes.isNotEmpty
        ? displayRoute.nodes.first
        : displayRoute.centerPoint;
    final startDistanceKm = RevvRoute.haversineKm(
      LatLng(location.lat, location.lng),
      startNode,
    );
    final startSummary = buildSprintStartSummary(startDistanceKm, _startMode);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: Text(
          displayRoute.name,
          style: GoogleFonts.orbitron(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.compositeRoute != null
                      ? 'COMPOSITE ROUTE'
                      : displayRoute.difficultyLabel,
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.red,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${displayRoute.distanceKm.toStringAsFixed(1)} km',
                  style: GoogleFonts.orbitron(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.compositeRoute != null
                      ? '재미 ${widget.compositeRoute!.funScore.toStringAsFixed(1)} / 흐름 ${widget.compositeRoute!.flowScore.toStringAsFixed(2)} / stop ${widget.compositeRoute!.stopSignCount}'
                      : '와인딩 ${displayRoute.windingScore.toStringAsFixed(1)} / 커브 ${displayRoute.sharpCurveCount}개 / ${displayRoute.distanceFromUserDisplay}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '출발 방식',
                  style: GoogleFonts.orbitron(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    startSummary,
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      height: 1.35,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _PreviewDecisionPanel(
                  route: displayRoute,
                  startSummary: startSummary,
                ),
                if (widget.compositeRoute == null &&
                    displayRoute.primaryReason?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    displayRoute.primaryReason!,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
                if (widget.compositeRoute == null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        label: displayRoute.qualityLabel.toUpperCase(),
                        color: displayRoute.qualityLabel == 'keep'
                            ? const Color(0xFF22C55E)
                            : displayRoute.qualityLabel == 'maybe'
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFEF4444),
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
                    displayRoute.cautionNote?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    displayRoute.cautionNote!,
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                MiniElevSection(route: displayRoute, lineColor: AppColors.red),
                if (widget.compositeRoute != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'SEGMENTS',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...[
                    widget.compositeRoute!.baseRoute,
                    ...widget.compositeRoute!.chainedSegments,
                  ].map(
                    (segment) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${segment.name} · ${segment.distanceKm.toStringAsFixed(1)} km',
                        style: GoogleFonts.rajdhani(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  if (widget.compositeRoute!.connectorLegs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Connector ${widget.compositeRoute!.connectorLegs.first.distanceKm.toStringAsFixed(1)} km · ${widget.compositeRoute!.estimatedDurationMinutes} min est',
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.panel,
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              context.read<RouteService>().requestSprint(
                route:
                    widget.compositeRoute?.toRouteProjection() ?? widget.route,
                startMode: _startMode,
              );
              Navigator.pop(context);
            },
            child: Text(
              sprintStartCtaLabel(_startMode),
              style: GoogleFonts.rajdhani(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewDecisionPanel extends StatelessWidget {
  final RevvRoute route;
  final String startSummary;

  const _PreviewDecisionPanel({
    required this.route,
    required this.startSummary,
  });

  @override
  Widget build(BuildContext context) {
    final bullets = <String>[
      route.primaryReason ?? '지금 달리기 좋은 루트예요.',
      startSummary,
      if (route.cautionNote?.isNotEmpty == true) route.cautionNote!,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '지금 선택 포인트',
            style: GoogleFonts.orbitron(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          ...bullets
              .take(3)
              .map(
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
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: color == null ? 1 : 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color ?? Colors.white24),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color ?? Colors.white70,
          letterSpacing: 1,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.red.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.red : Colors.white12),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
