import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/revv_route.dart';
import '../services/elevation_service.dart';
import '../theme/colors.dart';

/// 루트 카드 하단에 붙이는 미니 고도 프로파일 섹션.
/// ElevationService를 통해 비동기로 데이터를 가져오며,
/// didUpdateWidget에서 route.id가 바뀌면 재요청한다.
class MiniElevSection extends StatefulWidget {
  final RevvRoute route;
  final Color lineColor;

  const MiniElevSection({
    super.key,
    required this.route,
    required this.lineColor,
  });

  @override
  State<MiniElevSection> createState() => _MiniElevSectionState();
}

class _MiniElevSectionState extends State<MiniElevSection> {
  List<double>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch(widget.route);
  }

  @override
  void didUpdateWidget(MiniElevSection old) {
    super.didUpdateWidget(old);
    if (old.route.id != widget.route.id) {
      setState(() { _profile = null; _loading = true; });
      _fetch(widget.route);
    }
  }

  Future<void> _fetch(RevvRoute route) async {
    final result = await ElevationService().fetchElevation(route.id, route.nodes);
    if (!mounted) return;
    setState(() { _profile = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: SizedBox(
          height: 30,
          child: Center(
            child: SizedBox(
              width: 11, height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: AppColors.red),
            ),
          ),
        ),
      );
    }

    final p = _profile;
    if (p == null || p.length < 2) return const SizedBox.shrink();

    // elevationGainM / lossM / max 계산 (RevvRoute getter 활용)
    final r = widget.route.copyWith(elevationProfile: p);
    final gainM = r.elevationGainM;
    final lossM = r.elevationLossM;
    final maxM  = r.maxElevationM;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 고도 스탯 칩 행
          Row(
            children: [
              _EChip('↑ ${gainM.toStringAsFixed(0)}m', const Color(0xFF22C55E)),
              const SizedBox(width: 10),
              _EChip('↓ ${lossM.toStringAsFixed(0)}m', const Color(0xFF3B82F6)),
              const SizedBox(width: 10),
              _EChip('${maxM.toStringAsFixed(0)}m 최고', AppColors.textHint),
            ],
          ),
          const SizedBox(height: 5),
          // 미니 차트
          SizedBox(
            height: 30,
            child: CustomPaint(
              painter: _MiniElevPainter(profile: p, color: widget.lineColor),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EChip extends StatelessWidget {
  final String text;
  final Color color;
  const _EChip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _MiniElevPainter extends CustomPainter {
  final List<double> profile;
  final Color color;
  const _MiniElevPainter({required this.profile, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (profile.length < 2) return;

    final minE  = profile.reduce(math.min);
    final maxE  = profile.reduce(math.max);
    final range = (maxE - minE).clamp(10.0, double.infinity);

    final pts = <Offset>[];
    for (int i = 0; i < profile.length; i++) {
      final x = size.width * i / (profile.length - 1);
      final y = size.height * (1 - (profile[i] - minE) / range);
      pts.add(Offset(x, y));
    }

    // 그라디언트 fill
    final fill = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { fill.lineTo(p.dx, p.dy); }
    fill
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // 선
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { line.lineTo(p.dx, p.dy); }
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: 0.78)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MiniElevPainter old) =>
      old.profile != profile || old.color != color;
}
