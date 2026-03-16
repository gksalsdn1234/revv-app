import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/colors.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../services/run_history_service.dart';
import '../services/saved_route_service.dart';
import '../services/revv_ai_service.dart';
import '../widgets/corner_brackets.dart';
import '../widgets/sprint_toggle.dart';
import 'cruise_screen.dart';

class RunCardScreen extends StatefulWidget {
  final RunSession? session;
  const RunCardScreen({super.key, this.session});

  @override
  State<RunCardScreen> createState() => _RunCardScreenState();
}

class _RunCardScreenState extends State<RunCardScreen> {
  RunSummary? _saved;
  final _cardKey = GlobalKey();
  bool _sharing = false;
  String? _jarvisAnalysis;
  bool _jarvisLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _saveSession();
      await _runJarvisAnalysis();
    });
  }

  Future<void> _saveSession() async {
    final s = widget.session;
    if (s == null) return;
    final summary =
        await context.read<RunHistoryService>().save(s);
    if (mounted) setState(() => _saved = summary);
  }

  Future<void> _runJarvisAnalysis() async {
    final s = widget.session;
    if (s == null) return;
    if (mounted) setState(() => _jarvisLoading = true);
    final result = await RevvAiService().analyzeRun(s);
    if (mounted) setState(() {
      _jarvisAnalysis = result;
      _jarvisLoading = false;
    });
  }

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/revv_run_card.png');
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: 'REVV — ${widget.session?.routeName ?? "드라이브"} 완주 🚗',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공유 실패: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RunHistoryService>();
    final visitCount = _saved != null
        ? history.visitCount(_saved!.routeId)
        : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(child: SizedBox()),
              RepaintBoundary(
                key: _cardKey,
                child: _RunCard(
                  session: widget.session,
                  visitCount: visitCount,
                  jarvisAnalysis: _jarvisAnalysis,
                  jarvisLoading: _jarvisLoading,
                ),
              ),
              const Expanded(child: SizedBox()),
              _BottomButtons(onShare: _shareCard, sharing: _sharing),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  final RunSession? session;
  final int? visitCount;
  final String? jarvisAnalysis;
  final bool jarvisLoading;
  const _RunCard({
    required this.session,
    this.visitCount,
    this.jarvisAnalysis,
    this.jarvisLoading = false,
  });

  String _jarvisComment() {
    final s = session;
    if (s == null) return '오늘 드라이브 어땠나요?';
    final km = s.distanceKm;
    final min = s.duration.inMinutes;
    final visits = visitCount;
    if (visits != null && visits >= 2) {
      return '이 코스 ${visits}번째예요. 갈수록 익숙해지는 느낌 어때요?';
    }
    if (km >= 30) return '${km.toStringAsFixed(1)}km, ${min}분 — 오늘 꽤 긴 코스였네요. 수고했어요.';
    if (km >= 10) return '${km.toStringAsFixed(1)}km 드라이브 완료. 이 코스, 마음에 드셨나요?';
    if (km > 0) return '짧지만 좋은 드라이브였어요. 다음엔 조금 더 멀리 나가봐요.';
    return '오늘 드라이브 어땠나요?';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final distanceKm = s?.distanceKm ?? 0;
    final routeName = s?.routeName ?? '자유 드라이빙';
    final weatherEmoji = s?.weatherEmoji ?? '🌤';
    final tempDisplay = s?.tempDisplay ?? '—';
    final durationDisplay = s?.durationDisplay ?? '—';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.red.withOpacity(0.3)),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const RevvLogo(size: 14),
                  if (session?.route != null)
                    Consumer<SavedRouteService>(
                      builder: (ctx, saved, _) {
                        final route = session!.route!;
                        final isSaved = saved.isSaved(route.id);
                        return GestureDetector(
                          onTap: () => saved.toggle(route),
                          child: Row(
                            children: [
                              Icon(
                                isSaved ? Icons.bookmark : Icons.bookmark_border,
                                color: isSaved ? AppColors.red : AppColors.gray,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSaved ? '저장됨' : '루트 저장',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 11,
                                  color: isSaved ? AppColors.red : AppColors.gray,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.red.withOpacity(0.2)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  "TODAY'S RUN",
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.gray,
                    letterSpacing: 5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distanceKm.toStringAsFixed(1),
                      style: GoogleFonts.orbitron(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      ' km',
                      style: GoogleFonts.orbitron(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      routeName,
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gray,
                      ),
                    ),
                    if (visitCount != null && visitCount! >= 2) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                              color: AppColors.red.withOpacity(0.4)),
                        ),
                        child: Text(
                          '${visitCount}회차',
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InfoChip('$weatherEmoji $tempDisplay'),
                    _ChipDivider(),
                    _InfoChip('⏱ $durationDisplay'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Divider(color: AppColors.red.withOpacity(0.2)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'JARVIS',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                      letterSpacing: 4,
                    ),
                  ),
                  if (jarvisLoading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.red, width: 2),
                  ),
                ),
                child: Text(
                  jarvisLoading
                      ? '분석 중...'
                      : (jarvisAnalysis ?? _jarvisComment()),
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withOpacity(
                      jarvisLoading ? 0.3 : 0.65,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.red.withOpacity(0.2)),
            ],
          ),
          const Positioned.fill(child: CornerBrackets(padding: 4)),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  const _InfoChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white.withOpacity(0.6),
      ),
    );
  }
}

class _ChipDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white.withOpacity(0.15),
    );
  }
}

class _BottomButtons extends StatelessWidget {
  final VoidCallback onShare;
  final bool sharing;
  const _BottomButtons({required this.onShare, required this.sharing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          RedGlowButton(
            label: sharing ? '공유 중...' : '📤 공유하기',
            filled: true,
            onTap: sharing ? null : onShare,
          ),
          const SizedBox(height: 12),
          RedGlowButton(
            label: '다시 달리기',
            filled: false,
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const CruiseScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
