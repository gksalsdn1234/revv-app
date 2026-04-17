import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/composite_route.dart';
import '../models/revv_route.dart';
import '../theme/colors.dart';
import '../widgets/mini_elev_chart.dart';

class RoutePreviewScreen extends StatelessWidget {
  final RevvRoute? route;
  final CompositeRoute? compositeRoute;

  const RoutePreviewScreen({
    super.key,
    this.route,
    this.compositeRoute,
  }) : assert(route != null || compositeRoute != null);

  RevvRoute get _displayRoute => compositeRoute?.toRouteProjection() ?? route!;

  @override
  Widget build(BuildContext context) {
    final displayRoute = _displayRoute;
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
                  compositeRoute != null ? 'COMPOSITE ROUTE' : displayRoute.difficultyLabel,
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
                  compositeRoute != null
                      ? '재미 ${compositeRoute!.funScore.toStringAsFixed(1)} / 흐름 ${compositeRoute!.flowScore.toStringAsFixed(2)} / stop ${compositeRoute!.stopSignCount}'
                      : '와인딩 ${displayRoute.windingScore.toStringAsFixed(1)} / 커브 ${displayRoute.sharpCurveCount}개 / ${displayRoute.distanceFromUserDisplay}',
                  style: GoogleFonts.rajdhani(fontSize: 14, color: Colors.white70),
                ),
                if (compositeRoute == null && displayRoute.primaryReason?.isNotEmpty == true) ...[
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
                if (compositeRoute == null) ...[
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
                          label: displayRoute.routeCharacter.replaceAll('_', ' ').toUpperCase(),
                        ),
                      if (displayRoute.stopSignCount > 0 || displayRoute.trafficSignalCount > 0)
                        _MetaChip(
                          label:
                              'STOP ${displayRoute.stopSignCount} · SIGNAL ${displayRoute.trafficSignalCount}',
                        ),
                    ],
                  ),
                ],
                if (compositeRoute == null && displayRoute.cautionNote?.isNotEmpty == true) ...[
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
                MiniElevSection(
                  route: displayRoute,
                  lineColor: AppColors.red,
                ),
                if (compositeRoute != null) ...[
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
                    compositeRoute!.baseRoute,
                    ...compositeRoute!.chainedSegments,
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
                  if (compositeRoute!.connectorLegs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Connector ${compositeRoute!.connectorLegs.first.distanceKm.toStringAsFixed(1)} km · ${compositeRoute!.estimatedDurationMinutes} min est',
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
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color? color;

  const _MetaChip({
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.white.withValues(alpha: 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: color == null ? 1 : 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color ?? Colors.white24,
        ),
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
