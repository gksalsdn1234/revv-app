import 'dart:io';
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
                ? 0.045
                : compact
                ? 0.064
                : 0.07,
            10,
            28,
          );
          final titleSize = _scale(
            shortestSide,
            dense
                ? 0.074
                : compact
                ? 0.105
                : 0.11,
            dense
                ? 18
                : compact
                ? 20
                : 24,
            dense
                ? 22
                : compact
                ? 30
                : 42,
          );

          return ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.bg,
                gradient: AppColors.cockpitBackgroundGradient(),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.28),
                ),
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
                      chipSpacing: _scale(shortestSide, 0.026, 8, 12),
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
  final double chipSpacing;

  const _ShareCardLayout({
    required this.content,
    required this.compact,
    required this.dense,
    required this.titleSize,
    required this.chipSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final hasPath =
        content.pathPreview != null && content.pathPreview!.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardKicker(content: content, compact: compact),
        SizedBox(
          height: dense
              ? 6
              : compact
              ? 8
              : 12,
        ),
        Text(
          content.title,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: AppText.display(
            size: titleSize,
            weight: FontWeight.w900,
            height: 0.92,
            color: AppColors.textPrimary,
          ),
        ),
        if (!compact && !dense && content.subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            content.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        SizedBox(
          height: dense
              ? 6
              : compact
              ? 10
              : 14,
        ),
        if (hasPath)
          Expanded(
            flex: compact ? 4 : 6,
            child: _PathPreview(points: content.pathPreview!, compact: compact),
          )
        else
          Expanded(
            flex: compact ? 3 : 5,
            child: _EmptyPathPreview(compact: compact),
          ),
        SizedBox(
          height: dense
              ? 6
              : compact
              ? 10
              : 14,
        ),
        _MetricChips(
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
          spacing: chipSpacing,
        ),
        if (!compact && !dense && content.footer.trim().isNotEmpty) ...[
          const Spacer(flex: 1),
          Text(
            content.footer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.stoneMuted,
              letterSpacing: 1.1,
            ),
          ),
        ],
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
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            content.dateLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.technicalLabel(
              size: compact ? 9 : 10,
              color: AppColors.textHint,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _PathPreview extends StatelessWidget {
  final List<RunSharePathPoint> points;
  final bool compact;

  const _PathPreview({required this.points, required this.compact});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: CustomPaint(
        painter: _PathPreviewPainter(points),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EmptyPathPreview extends StatelessWidget {
  final bool compact;

  const _EmptyPathPreview({required this.compact});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.16),
        ),
      ),
      child: Center(
        child: Text(
          'ROUTE PREVIEW',
          style: AppText.technicalLabel(
            size: compact ? 9 : 10,
            color: AppColors.stoneMuted,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _MetricChips extends StatelessWidget {
  final List<RunShareCardMetric> metrics;
  final bool compact;
  final double spacing;

  const _MetricChips({
    required this.metrics,
    required this.compact,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    // 내보내기 캔버스는 높이가 고정 — 언어별 라벨 길이와 무관하게
    // 칩을 한 줄로 유지하고 넘치면 통째로 축소한다 (줄바꿈 = 세로 overflow)
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            _MetricChip(metric: metrics[i], compact: compact),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final RunShareCardMetric metric;
  final bool compact;

  const _MetricChip({required this.metric, required this.compact});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 92 : 132),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cream.withValues(alpha: compact ? 0.10 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.cream.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 11,
            vertical: compact ? 6 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  metric.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.technicalLabel(
                    size: compact ? 8 : 9,
                    color: AppColors.textHint,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(
                    size: compact ? 10 : 12,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
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
    final redPaint = Paint()
      ..color = AppColors.red.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.18),
      Offset(size.width * 0.92, size.height * 0.02),
      redPaint,
    );

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

    final inset = size.shortestSide * 0.14;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    final offsets = _offsetsFor(rect);
    final path = _pathFor(offsets);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.red.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(offsets.first, 4.5, Paint()..color = AppColors.success);
    canvas.drawCircle(offsets.last, 4.5, Paint()..color = AppColors.red);
  }

  List<Offset> _offsetsFor(Rect rect) {
    final offsets = [for (final point in points) _pointFor(rect, point)];
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

  Offset _pointFor(Rect rect, RunSharePathPoint point) {
    return Offset(
      rect.left + rect.width * point.x,
      rect.top + rect.height * point.y,
    );
  }

  @override
  bool shouldRepaint(covariant _PathPreviewPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

double _scale(double base, double factor, double min, double max) {
  return (base * factor).clamp(min, max).toDouble();
}
