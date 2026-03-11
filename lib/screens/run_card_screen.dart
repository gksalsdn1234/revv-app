import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../services/run_history_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveSession());
  }

  Future<void> _saveSession() async {
    final s = widget.session;
    if (s == null) return;
    final summary =
        await context.read<RunHistoryService>().save(s);
    if (mounted) setState(() => _saved = summary);
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
              _RunCard(session: widget.session, visitCount: visitCount),
              const Expanded(child: SizedBox()),
              _BottomButtons(),
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
  const _RunCard({required this.session, this.visitCount});

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
              const Center(child: RevvLogo(size: 14)),
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
              Text(
                'JARVIS',
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                  letterSpacing: 4,
                ),
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
                  _jarvisComment(),
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withOpacity(0.65),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          RedGlowButton(
            label: '📤 공유하기',
            filled: true,
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
