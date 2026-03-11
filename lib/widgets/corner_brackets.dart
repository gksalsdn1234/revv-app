import 'package:flutter/material.dart';
import '../theme/colors.dart';

class CornerBrackets extends StatelessWidget {
  final double padding;
  final double lineLength;
  final double lineWidth;
  final Color color;

  const CornerBrackets({
    super.key,
    this.padding = 8,
    this.lineLength = 14,
    this.lineWidth = 1.5,
    this.color = const Color(0x80E3000F),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _BracketPainter(
          padding: padding,
          lineLength: lineLength,
          lineWidth: lineWidth,
          color: color,
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final double padding;
  final double lineLength;
  final double lineWidth;
  final Color color;

  const _BracketPainter({
    required this.padding,
    required this.lineLength,
    required this.lineWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;

    final p = padding;
    final l = lineLength;

    // Top-left
    canvas.drawLine(Offset(p, p), Offset(p + l, p), paint);
    canvas.drawLine(Offset(p, p), Offset(p, p + l), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - p, p), Offset(size.width - p - l, p), paint);
    canvas.drawLine(Offset(size.width - p, p), Offset(size.width - p, p + l), paint);
    // Bottom-left
    canvas.drawLine(Offset(p, size.height - p), Offset(p + l, size.height - p), paint);
    canvas.drawLine(Offset(p, size.height - p), Offset(p, size.height - p - l), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width - p, size.height - p), Offset(size.width - p - l, size.height - p), paint);
    canvas.drawLine(Offset(size.width - p, size.height - p), Offset(size.width - p, size.height - p - l), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}

class RevvLogo extends StatelessWidget {
  final double size;
  const RevvLogo({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Orbitron',
          fontSize: size,
          fontWeight: FontWeight.w900,
          package: 'google_fonts',
        ),
        children: [
          const TextSpan(
            text: 'RE',
            style: TextStyle(color: AppColors.white),
          ),
          TextSpan(
            text: 'VV',
            style: TextStyle(
              color: AppColors.red,
              shadows: [
                Shadow(color: AppColors.red, blurRadius: 20),
                Shadow(color: AppColors.redGlow, blurRadius: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
