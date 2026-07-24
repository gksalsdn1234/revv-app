import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'run_share_card_content.dart';

class RunShareCardWidget extends StatelessWidget {
  final RunShareCardContent content;

  const RunShareCardWidget({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: content.presetInfo.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final shortestSide = size.shortestSide;
          final compact = content.presetInfo.isCompact;
          final dense = !compact && shortestSide < 340;
          final padding = _scale(
            shortestSide,
            dense
                ? 0.05
                : compact
                ? 0.064
                : 0.075,
            10,
            34,
          );
          final titleSize = _scale(
            shortestSide,
            dense
                ? 0.082
                : compact
                ? 0.105
                : 0.12,
            dense
                ? 19
                : compact
                ? 20
                : 26,
            dense
                ? 24
                : compact
                ? 30
                : 48,
          );

          return ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.bg,
                gradient: AppColors.cockpitBackgroundGradient(),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(child: _ShareCardBackdrop()),
                  Padding(
                    padding: EdgeInsets.all(padding),
                    child: _ShareCardLayout(
                      content: content,
                      compact: compact,
                      dense: dense,
                      titleSize: titleSize,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<Uint8List> exportRunShareCardPngBytes(
  GlobalKey repaintKey, {
  double pixelRatio = 3,
}) async {
  final context = repaintKey.currentContext;
  if (context == null) {
    throw StateError('Share card is not mounted.');
  }

  final renderObject = context.findRenderObject();
  if (renderObject is! RenderRepaintBoundary ||
      !renderObject.attached ||
      !renderObject.hasSize) {
    throw StateError('Share card must be laid out before export.');
  }

  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('Share card PNG encoding failed.');
  }

  return byteData.buffer.asUint8List();
}

Future<File> exportRunShareCardPngFile({
  required GlobalKey repaintKey,
  required Directory directory,
  String fileName = 'revv-share-card.png',
  double pixelRatio = 3,
}) async {
  final bytes = await exportRunShareCardPngBytes(
    repaintKey,
    pixelRatio: pixelRatio,
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}/$fileName');
  return file.writeAsBytes(bytes, flush: true);
}

class _ShareCardLayout extends StatelessWidget {
  final RunShareCardContent content;
  final bool compact;
  final bool dense;
  final double titleSize;

  const _ShareCardLayout({
    required this.content,
    required this.compact,
    required this.dense,
    required this.titleSize,
  });

  @override
  Widget build(BuildContext context) {
    final story = content.preset == ShareCardPreset.story;
    final hasPath =
        content.pathPreview != null && content.pathPreview!.length > 1;
    final hero = compact ? null : content.heroMetric;
    final footer = content.footer.trim();
    final showBottomMeta = !compact && !dense && (hero != null || footer.isNotEmpty);

    // Story path box adapts to the route's own aspect so a wide route does not
    // reserve a tall box full of dead space.
    double storyPathAspect = 1.02;
    final preview = content.pathPreview;
    if (story && preview != null && preview.length > 1) {
      var minX = preview.first.x, maxX = preview.first.x;
      var minY = preview.first.y, maxY = preview.first.y;
      for (final point in preview.skip(1)) {
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
      }
      final spanX = maxX - minX;
      final spanY = maxY - minY;
      if (spanX > 0.001 && spanY > 0.001) {
        storyPathAspect = (spanX / spanY).clamp(0.9, 1.6);
      }
    }

    final pathArea = hasPath
        ? _PathPreview(points: content.pathPreview!)
        : const _EmptyPathPreview();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardKicker(content: content, compact: compact),
        SizedBox(height: dense ? 8 : 10),
        Text(
          content.title,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: AppText.display(
            size: titleSize,
            weight: FontWeight.w700,
            height: 0.95,
            color: AppColors.textPrimary,
          ),
        ),
        if (!compact && !dense && content.subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            content.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 14,
              weight: FontWeight.w700,
              color: AppColors.textPrimary.withValues(alpha: 0.72),
            ),
          ),
        ],
        if (story)
          // Bottom-aligned inside a bounded slot: the path keeps the route's
          // aspect when there is room and shrinks instead of overflowing when
          // there is not. Card text sizes are absolute, so the narrow preview
          // width has meaningfully less room than the exported width.
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AspectRatio(aspectRatio: storyPathAspect, child: pathArea),
            ),
          )
        else
          Expanded(
            flex: hasPath ? (compact ? 4 : 6) : (compact ? 3 : 5),
            child: pathArea,
          ),
        if (showBottomMeta) ...[
          SizedBox(height: story ? 18 : 10),
          _BottomMeta(hero: hero, footer: footer, story: story),
        ],
        SizedBox(height: dense ? 8 : 12),
        _SpecTable(
          metrics: content.metricChips
              .take(
                compact
                    ? 4
                    : dense
                    ? 3
                    : 5,
              )
              .toList(),
          compact: compact,
          dense: dense,
        ),
        if (story) const Spacer(flex: 2),
      ],
    );
  }
}

class _CardKicker extends StatelessWidget {
  final RunShareCardContent content;
  final bool compact;

  const _CardKicker({required this.content, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'REVV',
          style: AppText.technicalLabel(
            size: compact ? 10 : 11,
            color: AppColors.red,
            letterSpacing: 2.4,
          ),
        ),
        Expanded(
          child: Text(
            content.dateLabel.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppText.technicalLabel(
              size: compact ? 9 : 10,
              color: AppColors.textHint,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// The hero number and the weather footnote share one baseline row so neither
/// needs its own line of the card.
class _BottomMeta extends StatelessWidget {
  final RunShareCardMetric? hero;
  final String footer;
  final bool story;

  const _BottomMeta({
    required this.hero,
    required this.footer,
    required this.story,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hero != null) ...[
          Text(
            hero!.value,
            style: AppText.mono(
              size: story ? 44 : 38,
              weight: FontWeight.w800,
              color: AppColors.red,
            ),
          ),
          const SizedBox(width: 10),
          // Both labels must be able to shrink: the hero number is fixed width,
          // so on the narrow presets an unconstrained label overflows the row
          // and the card exports with the striped overflow banner baked in.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                hero!.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ),
        ],
        const Spacer(),
        if (footer.isNotEmpty)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.stoneMuted,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Hairline spec sheet: value over label per column, thin rules instead of
/// pill chips.
class _SpecTable extends StatelessWidget {
  final List<RunShareCardMetric> metrics;
  final bool compact;
  final bool dense;

  const _SpecTable({
    required this.metrics,
    required this.compact,
    required this.dense,
  });

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final valueSize = compact
        ? 13.0
        : dense
        ? 15.0
        : 19.0;
    final labelSize = compact ? 7.5 : 8.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 1,
          color: AppColors.outlineVariant.withValues(alpha: 0.32),
        ),
        SizedBox(height: dense || compact ? 8 : 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: compact ? 26 : 32,
                  margin: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 14,
                  ),
                  color: AppColors.outlineVariant.withValues(alpha: 0.22),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        metrics[i].value,
                        maxLines: 1,
                        style: AppText.mono(
                          size: valueSize,
                          weight: FontWeight.w800,
                          color: AppColors.cream,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metrics[i].label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.technicalLabel(
                        size: labelSize,
                        color: AppColors.textHint,
                        letterSpacing: 0.9,
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

/// The route draws directly on the card background — no framed inner box.
class _PathPreview extends StatelessWidget {
  final List<RunSharePathPoint> points;

  const _PathPreview({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PathPreviewPainter(points),
      child: const SizedBox.expand(),
    );
  }
}

class _EmptyPathPreview extends StatelessWidget {
  const _EmptyPathPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'ROUTE PREVIEW',
        style: AppText.technicalLabel(
          size: 10,
          color: AppColors.stoneMuted,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}

class _ShareCardBackdrop extends StatelessWidget {
  const _ShareCardBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ShareCardBackdropPainter());
  }
}

class _ShareCardBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width * 1.05, -size.height * 0.08);
    final glowRadius = size.width * 0.75;
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        glowCenter,
        glowRadius,
        [
          AppColors.red.withValues(alpha: 0.14),
          AppColors.red.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(glowCenter, glowRadius, glowPaint);

    final gridPaint = Paint()
      ..color = AppColors.outlineVariant.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShareCardBackdropPainter oldDelegate) => false;
}

class _PathPreviewPainter extends CustomPainter {
  final List<RunSharePathPoint> points;

  const _PathPreviewPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final inset = (size.shortestSide * 0.10).clamp(8.0, 26.0);
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    // Contain-fit the data bounding box: preserve the route's aspect while
    // filling the available area.
    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final point in points.skip(1)) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    final spanX = math.max(maxX - minX, 0.001);
    final spanY = math.max(maxY - minY, 0.001);
    final scale = math.min(rect.width / spanX, rect.height / spanY);
    final drawOrigin = Offset(
      rect.center.dx - spanX * scale / 2,
      rect.center.dy - spanY * scale / 2,
    );

    final offsets = _offsetsFor(rect, drawOrigin, minX, minY, scale);
    final path = _pathFor(offsets);

    // Soft red halo (real blur), then the cream line on top.
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.red.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    _paintCornerTicks(canvas, offsets);

    _paintEndpoint(canvas, offsets.first, AppColors.success, 5.0);
    _paintEndpoint(canvas, offsets.last, AppColors.red, 5.5);
  }

  /// Red ticks at sharp direction changes — the visual counterpart of the
  /// corner count in the spec sheet.
  void _paintCornerTicks(Canvas canvas, List<Offset> offsets) {
    if (offsets.length < 3) return;
    final tickPaint = Paint()..color = AppColors.red;
    Offset? lastTick;
    for (var i = 1; i < offsets.length - 1; i++) {
      final incoming = offsets[i] - offsets[i - 1];
      final outgoing = offsets[i + 1] - offsets[i];
      if (incoming.distance < 1 || outgoing.distance < 1) continue;
      final turn =
          (math.atan2(outgoing.dy, outgoing.dx) -
                  math.atan2(incoming.dy, incoming.dx))
              .abs();
      final normalized = turn > math.pi ? 2 * math.pi - turn : turn;
      if (normalized < math.pi * 0.16) continue;
      if (lastTick != null && (offsets[i] - lastTick).distance < 18) continue;
      canvas.drawCircle(offsets[i], 3.0, tickPaint);
      lastTick = offsets[i];
    }
  }

  void _paintEndpoint(Canvas canvas, Offset center, Color color, double radius) {
    canvas.drawCircle(center, radius + 2.5, Paint()..color = AppColors.bg);
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  List<Offset> _offsetsFor(
    Rect rect,
    Offset drawOrigin,
    double minX,
    double minY,
    double scale,
  ) {
    final offsets = [
      for (final point in points)
        drawOrigin +
            Offset((point.x - minX) * scale, (point.y - minY) * scale),
    ];
    final first = offsets.first;
    final last = offsets.last;
    if ((last - first).distance >= 1) return offsets;

    final center = rect.center;
    final half = rect.shortestSide * 0.12;
    return [
      Offset(center.dx - half, center.dy),
      Offset(center.dx + half, center.dy),
    ];
  }

  Path _pathFor(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    if (offsets.length == 2) {
      path.lineTo(offsets.last.dx, offsets.last.dy);
      return path;
    }

    for (var i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i == 0 ? 0 : i - 1];
      final p1 = offsets[i];
      final p2 = offsets[i + 1];
      final p3 = offsets[i + 2 < offsets.length ? i + 2 : offsets.length - 1];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _PathPreviewPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

double _scale(double base, double factor, double min, double max) {
  return (base * factor).clamp(min, max).toDouble();
}
