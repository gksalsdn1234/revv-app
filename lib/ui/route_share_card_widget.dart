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
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  border: Border.all(
                    color: AppColors.ink.withValues(alpha: 0.10),
                  ),
                ),
                child: Stack(
                  children: [
                    const Positioned.fill(child: _PaperGrain()),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24 * scale,
                        21 * scale,
                        24 * scale,
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
    final meetingArea = content.meetingAreaLabel?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker(schedule: content.schedule, scale: scale),
        SizedBox(height: 17 * scale),
        Text(
          content.headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.technicalLabel(
            size: 10 * scale,
            color: AppColors.stone,
            letterSpacing: 1.05 * scale,
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          content.routeName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.display(
            size: 30 * scale,
            weight: FontWeight.w800,
            color: AppColors.ink,
            height: 0.94,
          ),
        ),
        if (tags.isNotEmpty) ...[
          SizedBox(height: 11 * scale),
          Wrap(
            spacing: 7 * scale,
            runSpacing: 5 * scale,
            children: [
              for (final tag in tags) _Tag(label: tag.label, scale: scale),
            ],
          ),
        ],
        SizedBox(height: 14 * scale),
        Expanded(
          child: Semantics(
            label: 'Route silhouette',
            image: true,
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _RouteSilhouettePainter(content.silhouette),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        SizedBox(height: 12 * scale),
        _Metrics(
          distance: content.distanceLabel,
          duration: content.durationLabel,
          scale: scale,
        ),
        SizedBox(height: 12 * scale),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _MeetingArea(areaLabel: meetingArea, scale: scale),
            ),
            SizedBox(width: 12 * scale),
            Text(
              content.footer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.technicalLabel(
                size: 11 * scale,
                color: AppColors.red,
                letterSpacing: 1.6 * scale,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Kicker extends StatelessWidget {
  final String schedule;
  final double scale;

  const _Kicker({required this.schedule, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'REVV',
          style: AppText.technicalLabel(
            size: 12 * scale,
            color: AppColors.red,
            letterSpacing: 1.7 * scale,
          ),
        ),
        SizedBox(width: 10 * scale),
        Expanded(
          child: Text(
            schedule,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.technicalLabel(
              size: 9 * scale,
              color: AppColors.stone,
              letterSpacing: 0.45 * scale,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final double scale;

  const _Tag({required this.label, required this.scale});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 9 * scale,
          vertical: 5 * scale,
        ),
        child: Text(
          label,
          style: AppText.body(
            size: 10 * scale,
            weight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  final String distance;
  final String duration;
  final double scale;

  const _Metrics({
    required this.distance,
    required this.duration,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(label: 'DISTANCE', value: distance, scale: scale),
        ),
        Container(
          height: 31 * scale,
          width: 1,
          color: AppColors.ink.withValues(alpha: 0.12),
        ),
        Expanded(
          child: _Metric(label: 'DRIVE TIME', value: duration, scale: scale),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final double scale;

  const _Metric({
    required this.label,
    required this.value,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.technicalLabel(
              size: 8 * scale,
              color: AppColors.stone,
              letterSpacing: 1.05 * scale,
            ),
          ),
          SizedBox(height: 1 * scale),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.display(
              size: 23 * scale,
              weight: FontWeight.w800,
              color: AppColors.ink,
              height: 0.95,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingArea extends StatelessWidget {
  final String? areaLabel;
  final double scale;

  const _MeetingArea({required this.areaLabel, required this.scale});

  @override
  Widget build(BuildContext context) {
    final visibleArea = areaLabel;
    if (visibleArea == null || visibleArea.isEmpty) {
      return Text(
        'OPEN INVITE',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.technicalLabel(
          size: 8 * scale,
          color: AppColors.stone,
          letterSpacing: 1.05 * scale,
        ),
      );
    }

    return Text(
      visibleArea,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.body(
        size: 11 * scale,
        weight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}

class _PaperGrain extends StatelessWidget {
  const _PaperGrain();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PaperGrainPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RouteSilhouettePainter extends CustomPainter {
  final List<RouteShareCardPathPoint> points;

  const _RouteSilhouettePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final inset = (size.shortestSide * 0.075).clamp(10.0, 28.0);
    final routeBounds = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final guidePaint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.075)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(routeBounds.left, routeBounds.center.dy),
      Offset(routeBounds.right, routeBounds.center.dy),
      guidePaint,
    );

    if (points.length < 2) return;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final offset = Offset(
        routeBounds.left + point.x * routeBounds.width,
        routeBounds.top + point.y * routeBounds.height,
      );
      if (index == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.red.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final start = _offsetFor(routeBounds, points.first);
    final end = _offsetFor(routeBounds, points.last);
    canvas.drawCircle(start, 5, Paint()..color = AppColors.creamRaised);
    canvas.drawCircle(
      start,
      3.3,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(end, 5.5, Paint()..color = AppColors.red);
  }

  Offset _offsetFor(Rect bounds, RouteShareCardPathPoint point) {
    return Offset(
      bounds.left + point.x * bounds.width,
      bounds.top + point.y * bounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteSilhouettePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _PaperGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.ink.withValues(alpha: 0.028);
    const spacing = 18.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (
        var y = (x / spacing).round().isEven ? 6.0 : 15.0;
        y < size.height;
        y += spacing
      ) {
        canvas.drawCircle(Offset(x, y), 0.7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGrainPainter oldDelegate) => false;
}
