import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/run_summary.dart';
import '../services/run_history_service.dart';
import '../widgets/corner_brackets.dart';
import '../widgets/hud_bar.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static void show(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const HudBar(),
            // ── 헤더 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios,
                        size: 16, color: AppColors.gray),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'RUN HISTORY',
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
            // ── 통계 바 ──
            Consumer<RunHistoryService>(
              builder: (_, svc, __) => _StatsBar(svc: svc),
            ),
            const SizedBox(height: 4),
            Divider(
                color: AppColors.red.withValues(alpha: 0.12),
                height: 1),
            // ── 리스트 ──
            Expanded(
              child: Consumer<RunHistoryService>(
                builder: (_, svc, __) {
                  final history = svc.history;
                  if (history.isEmpty) {
                    return const _EmptyState();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: history.length,
                    itemBuilder: (ctx, i) {
                      final run = history[i];
                      final visitCount = svc.visitCount(run.routeId);
                      return _RunTile(
                        run: run,
                        visitCount: visitCount,
                        index: i,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 상단 통계 바 ────────────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final RunHistoryService svc;
  const _StatsBar({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: AppColors.red.withValues(alpha: 0.18)),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              _StatItem(
                label: 'TOTAL RUNS',
                value: '${svc.totalRuns}',
                unit: '회',
              ),
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: AppColors.red.withValues(alpha: 0.2),
              ),
              _StatItem(
                label: 'TOTAL DIST',
                value: svc.totalDistanceKm.toStringAsFixed(1),
                unit: 'km',
              ),
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: AppColors.red.withValues(alpha: 0.2),
              ),
              _StatItem(
                label: 'AVG DIST',
                value: svc.totalRuns > 0
                    ? (svc.totalDistanceKm / svc.totalRuns)
                        .toStringAsFixed(1)
                    : '—',
                unit: svc.totalRuns > 0 ? 'km' : '',
              ),
            ],
          ),
          const Positioned.fill(child: CornerBrackets(padding: 0)),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _StatItem(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.gray,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.orbitron(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  color: AppColors.gray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ── 런 타일 ─────────────────────────────────────────────────────
class _RunTile extends StatelessWidget {
  final RunSummary run;
  final int visitCount;
  final int index;
  const _RunTile(
      {required this.run,
      required this.visitCount,
      required this.index});

  String _formatDate(DateTime d) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[d.weekday - 1];
    return '${d.month}월 ${d.day}일 $wd';
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppColors.red.withValues(alpha: 0.14),
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 날짜 / 시간 행 ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _formatDate(run.date),
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatTime(run.date),
                      style: GoogleFonts.orbitron(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // ── 거리 + 루트명 ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      run.distanceKm.toStringAsFixed(1),
                      style: GoogleFonts.orbitron(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'km',
                      style: GoogleFonts.orbitron(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gray,
                      ),
                    ),
                    const Spacer(),
                    // ── 루트명 + 회차 배지 ──
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            run.routeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          if (visitCount >= 2) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                    color: AppColors.red
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                '${visitCount}회차',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.red,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ── 하단 칩 ──
                Row(
                  children: [
                    _Chip('⏱ ${run.durationDisplay}'),
                    const SizedBox(width: 10),
                    _Chip('${run.weatherEmoji} ${run.tempDisplay}'),
                  ],
                ),
              ],
            ),
            const Positioned.fill(
                child: CornerBrackets(
                    padding: 4,
                    lineLength: 8,
                    color: Color(0x28E3000F))),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

// ── 빈 상태 ──────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.flag_outlined,
            size: 48,
            color: AppColors.red.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'NO RUNS YET',
            style: GoogleFonts.orbitron(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.2),
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SPRINT 버튼으로 첫 드라이브를 시작해 보세요',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              color: AppColors.gray,
            ),
          ),
        ],
      ),
    );
  }
}
