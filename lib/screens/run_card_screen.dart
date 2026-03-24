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
  bool _detailSheetOpen = false;

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

  void _openDetailedAnalysis() {
    if (_detailSheetOpen) return;
    final s = widget.session;
    if (s == null) return;
    setState(() => _detailSheetOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailedAnalysisSheet(session: s),
    ).then((_) {
      if (mounted) setState(() => _detailSheetOpen = false);
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

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'REVV — ${widget.session?.routeName ?? "드라이브"} 완주 🚗',
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
              _BottomButtons(
                onShare: _shareCard,
                sharing: _sharing,
                onDetail: widget.session != null ? _openDetailedAnalysis : null,
              ),
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
                    if (s != null && s.sharpCorners.isNotEmpty) ...[
                      _ChipDivider(),
                      _InfoChip('⚡ ${s.sharpCorners.length}회', color: const Color(0xFFF59E0B)),
                    ],
                  ],
                ),
              ),
              // ── 드라이빙 스타일 배지 ──
              if (s != null) ...[
                const SizedBox(height: 14),
                _DrivingStyleBadge(maxLateralG: s.maxLateralG),
              ],
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
  final Color? color;
  const _InfoChip(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? Colors.white.withOpacity(0.6),
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

// ══════════════════════════════════════════════════════════════════
// 드라이빙 스타일 분석 배지
// ══════════════════════════════════════════════════════════════════
class _DrivingStyleBadge extends StatelessWidget {
  final double maxLateralG;
  const _DrivingStyleBadge({required this.maxLateralG});

  _StyleInfo _getStyle() {
    if (maxLateralG <= 0.0) {
      return _StyleInfo(
        label: 'DATA PENDING',
        emoji: '📡',
        desc: 'IMU 데이터 없음',
        color: const Color(0xFF6B7280),
      );
    } else if (maxLateralG < 0.25) {
      return _StyleInfo(
        label: 'CRUISER',
        emoji: '🌊',
        desc: '부드럽고 여유있는 드라이빙',
        color: const Color(0xFF60A5FA),
      );
    } else if (maxLateralG < 0.45) {
      return _StyleInfo(
        label: 'SPORT',
        emoji: '⚡',
        desc: '활기차고 다이나믹한 드라이빙',
        color: const Color(0xFFF59E0B),
      );
    } else {
      return _StyleInfo(
        label: 'RACER',
        emoji: '🔥',
        desc: '한계를 즐기는 퍼포먼스 드라이빙',
        color: const Color(0xFFEF4444),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _getStyle();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: style.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: style.color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(style.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DRIVING STYLE',
                      style: GoogleFonts.orbitron(
                        fontSize: 7,
                        fontWeight: FontWeight.w600,
                        color: style.color.withOpacity(0.7),
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (maxLateralG > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        'MAX ${maxLateralG.toStringAsFixed(2)}G',
                        style: GoogleFonts.rajdhani(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: style.color.withOpacity(0.6),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  style.label,
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: style.color,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  style.desc,
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleInfo {
  final String label;
  final String emoji;
  final String desc;
  final Color color;
  const _StyleInfo({
    required this.label,
    required this.emoji,
    required this.desc,
    required this.color,
  });
}

class _BottomButtons extends StatelessWidget {
  final VoidCallback onShare;
  final bool sharing;
  final VoidCallback? onDetail;
  const _BottomButtons({required this.onShare, required this.sharing, this.onDetail});

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
          const SizedBox(height: 10),
          if (onDetail != null)
            RedGlowButton(
              label: '🤖 상세 AI 분석',
              filled: false,
              onTap: onDetail,
            ),
          if (onDetail != null) const SizedBox(height: 10),
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

// ══════════════════════════════════════════════════════════════════
// 상세 AI 코칭 리포트 바텀시트
// ══════════════════════════════════════════════════════════════════
class _DetailedAnalysisSheet extends StatefulWidget {
  final RunSession session;
  const _DetailedAnalysisSheet({required this.session});

  @override
  State<_DetailedAnalysisSheet> createState() => _DetailedAnalysisSheetState();
}

class _DetailedAnalysisSheetState extends State<_DetailedAnalysisSheet> {
  String? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final result = await RevvAiService().analyzeRunDetailed(widget.session);
    if (mounted) setState(() { _report = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF131315),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.red),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 드라이빙 코치',
                      style: GoogleFonts.orbitron(
                        fontSize: 12, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: 1,
                      ),
                    ),
                    Text(
                      widget.session.routeName,
                      style: GoogleFonts.rajdhani(
                        fontSize: 11, color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.07), height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 18, 22, pad.bottom + 24),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2),
                      ),
                    )
                  : Text(
                      _report ?? '분석 데이터를 불러올 수 없어요.',
                      style: GoogleFonts.rajdhani(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.65,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
