import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'route_share_card_content.dart';

/// A privacy-safe, pre-drive invitation card.
///
/// The caller owns the [RepaintBoundary]. At [logicalWidth] × [logicalHeight],
/// [exportRouteShareCardPngBytes] emits the social-card format (1080 × 1350).
class RouteShareCardWidget extends StatelessWidget {
  static const logicalWidth = 360.0;
  static const logicalHeight = 450.0;
  static const exportPixelRatio = 3.0;

  final RouteShareCardContent content;

  const RouteShareCardWidget({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Route invitation card',
      child: AspectRatio(
        aspectRatio: logicalWidth / logicalHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = (constraints.maxWidth / logicalWidth).clamp(
              0.64,
              1.4,
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(22 * scale),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: AppColors.bg),
                child: Stack(
                  children: [
                    const Positioned.fill(child: _DarkBackdrop()),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20 * scale,
                        20 * scale,
                        20 * scale,
                        18 * scale,
                      ),
                      child: _RouteShareCardLayout(
                        content: content,
                        scale: scale,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Exports the fixed 4:5 card boundary at 3× for a 1080 × 1350 PNG.
///
/// Keeping the sizing check here prevents a preview-sized card from silently
/// becoming a low-resolution share attachment.
Future<Uint8List> exportRouteShareCardPngBytes(GlobalKey repaintKey) async {
  final context = repaintKey.currentContext;
  if (context == null) {
    throw StateError('Route invite card is not mounted.');
  }

  final renderObject = context.findRenderObject();
  if (renderObject is! RenderRepaintBoundary ||
      !renderObject.attached ||
      !renderObject.hasSize) {
    throw StateError('Route invite card must be laid out before export.');
  }
  if (renderObject.size !=
      const Size(
        RouteShareCardWidget.logicalWidth,
        RouteShareCardWidget.logicalHeight,
      )) {
    throw StateError(
      'Route invite card export requires a '
      '${RouteShareCardWidget.logicalWidth.toInt()}×'
      '${RouteShareCardWidget.logicalHeight.toInt()} boundary.',
    );
  }

  final image = await renderObject.toImage(
    pixelRatio: RouteShareCardWidget.exportPixelRatio,
  );
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Route invite card PNG encoding failed.');
    }
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

class _RouteShareCardLayout extends StatelessWidget {
  final RouteShareCardContent content;
  final double scale;

  const _RouteShareCardLayout({required this.content, required this.scale});

  @override
  Widget build(BuildContext context) {
    final tags = content.tags.take(2).toList(growable: false);
    final hasElevation = content.elevationLabel.isNotEmpty;
    final hasCurveMix = content.curveMix.isNotEmpty;
    final labels = RouteShareCardLabels.of(content.language);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'REVV',
              style: AppText.technicalLabel(
                size: 9.5 * scale,
                color: AppColors.red,
                letterSpacing: 2.2 * scale,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                content.schedule.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.technicalLabel(
                  size: 8 * scale,
                  color: AppColors.textHint,
                  letterSpacing: 1.1 * scale,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10 * scale),
        Text(
          content.headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.display(
            size: 22 * scale,
            weight: FontWeight.w700,
            height: 1.0,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 10 * scale),
        // Route panel with silhouette
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.16),
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  // Reserve the tag strip: a dense route fills this panel edge
                  // to edge and would otherwise run underneath the tags.
                  child: Padding(
                    padding: EdgeInsets.only(top: tags.isEmpty ? 0 : 30 * scale),
                    child: Semantics(
                      label: 'Route silhouette',
                      image: true,
                      child: ExcludeSemantics(
                        child: _Silhouette(
                          points: content.silhouette,
                          onDark: true,
                          stroke: 3.6 * scale,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10 * scale,
                  top: 9 * scale,
                  child: Row(
                    children: [
                      for (final tag in tags) ...[
                        _OutlineTag(label: tag.label, onDark: true, scale: scale),
                        SizedBox(width: 5 * scale),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12 * scale),
        _SpecRow(
          onDark: true,
          scale: scale,
          cells: [
            (value: content.distanceLabel, label: labels.distance),
            (value: content.durationLabel, label: labels.duration),
            (value: '${content.cornerCount}', label: labels.corners),
            if (hasElevation)
              (value: content.elevationLabel, label: labels.elevation),
          ],
        ),
        if (hasCurveMix) ...[
          SizedBox(height: 14 * scale),
          _CurveMixBar(
            segments: content.curveMix,
            scale: scale,
            title: labels.curveMix,
          ),
        ],
        SizedBox(height: 12 * scale),
        if (content.meetingAreaLabel != null)
          Text(
            '${labels.meet.toUpperCase()} · '
            '${content.meetingAreaLabel!.toUpperCase()}',
            style: AppText.technicalLabel(
              size: 8 * scale,
              color: AppColors.stoneMuted,
              letterSpacing: 1.2 * scale,
            ),
          ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────── Shared painters

class _DarkBackdrop extends StatelessWidget {
  const _DarkBackdrop();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DarkBackdropPainter());
}

class _DarkBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 1.05, -size.height * 0.06);
    final r = size.width * 0.85;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, [
          AppColors.red.withValues(alpha: 0.16),
          AppColors.red.withValues(alpha: 0.0),
        ]),
    );
    final grid = Paint()
      ..color = AppColors.outlineVariant.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _DarkBackdropPainter old) => false;
}

// Route line with corner ticks.
class _Silhouette extends StatelessWidget {
  final List<RouteShareCardPathPoint> points;
  final bool onDark;
  final double stroke;
  final double scale;

  const _Silhouette({
    required this.points,
    required this.onDark,
    required this.scale,
    this.stroke = 4.0,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SilhouettePainter(points, onDark, stroke),
        child: const SizedBox.expand(),
      );
}

class _SilhouettePainter extends CustomPainter {
  final List<RouteShareCardPathPoint> points;
  final bool onDark;
  final double stroke;

  const _SilhouettePainter(this.points, this.onDark, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final inset = (size.shortestSide * 0.08).clamp(6.0, 22.0);
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final p in points.skip(1)) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final spanX = math.max(maxX - minX, 0.001);
    final spanY = math.max(maxY - minY, 0.001);
    final scale = math.min(rect.width / spanX, rect.height / spanY);
    final origin = Offset(
      rect.center.dx - spanX * scale / 2,
      rect.center.dy - spanY * scale / 2,
    );
    final offsets = [
      for (final p in points)
        origin + Offset((p.x - minX) * scale, (p.y - minY) * scale),
    ];

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i == 0 ? 0 : i - 1];
      final p1 = offsets[i];
      final p2 = offsets[i + 1];
      final p3 = offsets[i + 2 < offsets.length ? i + 2 : offsets.length - 1];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    if (onDark) {
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.red.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 2
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = onDark ? AppColors.cream : AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Corner ticks
    final tick = Paint()..color = AppColors.red;
    Offset? last;
    for (var i = 1; i < offsets.length - 1; i++) {
      final a = offsets[i] - offsets[i - 1];
      final b = offsets[i + 1] - offsets[i];
      if (a.distance < 1 || b.distance < 1) continue;
      final turn =
          (math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)).abs();
      final n = turn > math.pi ? 2 * math.pi - turn : turn;
      if (n < math.pi * 0.13) continue;
      if (last != null && (offsets[i] - last).distance < 16) continue;
      canvas.drawCircle(offsets[i], stroke * 0.72, tick);
      last = offsets[i];
    }

    void endpoint(Offset c, Color color, double r) {
      canvas.drawCircle(
        c,
        r + 2.2,
        Paint()..color = onDark ? AppColors.bg : AppColors.cream,
      );
      canvas.drawCircle(c, r, Paint()..color = color);
    }

    endpoint(offsets.first, AppColors.success, stroke * 1.05);
    endpoint(offsets.last, AppColors.red, stroke * 1.15);
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter old) =>
      old.points != points || old.onDark != onDark;
}

// Value-over-label column set separated by hairlines.
class _SpecRow extends StatelessWidget {
  final List<({String value, String label})> cells;
  final bool onDark;
  final double scale;

  const _SpecRow({
    required this.cells,
    required this.onDark,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final line = (onDark ? AppColors.outlineVariant : AppColors.ink)
        .withValues(alpha: onDark ? 0.3 : 0.18);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: line),
        SizedBox(height: 9 * scale),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 28 * scale,
                  margin: EdgeInsets.symmetric(horizontal: 11 * scale),
                  color: line,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        cells[i].value,
                        maxLines: 1,
                        style: AppText.mono(
                          size: 16 * scale,
                          weight: FontWeight.w800,
                          color: onDark ? AppColors.cream : AppColors.ink,
                        ),
                      ),
                    ),
                    SizedBox(height: 3 * scale),
                    Text(
                      cells[i].label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.technicalLabel(
                        size: 8 * scale,
                        color: onDark ? AppColors.textHint : AppColors.stone,
                        letterSpacing: 0.9 * scale,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// Curve-mix bar and legend.
class _CurveMixBar extends StatelessWidget {
  final List<RouteCurveMixSegment> segments;
  final double scale;
  final String title;

  const _CurveMixBar({
    required this.segments,
    required this.scale,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final colorMap = <RouteCurveKind, Color>{
      RouteCurveKind.hairpin: const Color(0xFFE2231A),
      RouteCurveKind.switchback: const Color(0xFFE8833A),
      RouteCurveKind.sweeper: const Color(0xFF1FA85F),
      RouteCurveKind.straight: const Color(0xFF6E6A63),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppText.technicalLabel(
            size: 8.5 * scale,
            color: AppColors.textHint,
            letterSpacing: 1.5 * scale,
          ),
        ),
        SizedBox(height: 7 * scale),
        CustomPaint(
          size: Size(double.infinity, 6 * scale),
          painter: _CurveMixBarPainter(segments, colorMap),
        ),
        SizedBox(height: 9 * scale),
        Row(
          children: [
            for (final seg in segments)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 5 * scale,
                          height: 5 * scale,
                          decoration: BoxDecoration(
                            color: colorMap[seg.kind],
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 4 * scale),
                        Flexible(
                          child: Text(
                            seg.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.technicalLabel(
                              size: 7.5 * scale,
                              color: AppColors.textHint,
                              letterSpacing: 0.4 * scale,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      '${(seg.share * 100).round()}%',
                      style: AppText.mono(
                        size: 12 * scale,
                        weight: FontWeight.w800,
                        color: AppColors.cream,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CurveMixBarPainter extends CustomPainter {
  final List<RouteCurveMixSegment> segments;
  final Map<RouteCurveKind, Color> colorMap;

  const _CurveMixBarPainter(this.segments, this.colorMap);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.share);
    const gap = 2.0;
    final usable = size.width - gap * (segments.length - 1);
    var x = 0.0;
    for (final seg in segments) {
      final w = usable * (seg.share / total);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, w, size.height),
          Radius.circular(3 * size.height / 6),
        ),
        Paint()..color = colorMap[seg.kind]!,
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CurveMixBarPainter old) => false;
}

// Outline tag for curve types.
class _OutlineTag extends StatelessWidget {
  final String label;
  final bool onDark;
  final double scale;

  const _OutlineTag({
    required this.label,
    required this.onDark,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          border: Border.all(
            color: (onDark ? AppColors.outlineVariant : AppColors.ink)
                .withValues(alpha: 0.35),
          ),
          borderRadius: BorderRadius.circular(3 * scale),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppText.technicalLabel(
            size: 8 * scale,
            color: onDark ? AppColors.textSecondary : AppColors.stone,
            letterSpacing: 1.1 * scale,
          ),
        ),
      );
}
