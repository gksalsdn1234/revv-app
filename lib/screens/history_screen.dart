import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../models/run_summary.dart';
import '../services/run_history_service.dart';
import '../services/supabase_service.dart';
import '../widgets/revv_ui.dart';

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
      body: Consumer<RunHistoryService>(
        builder: (_, svc, __) {
          final history = svc.history; // 최신순
          return CustomScrollView(
            slivers: [
              // ── 상단 헤더 (SliverAppBar 스타일) ──
              SliverToBoxAdapter(child: _Header(svc: svc)),
              // ── 내용 ──
              if (history.isEmpty)
                const SliverFillRemaining(child: _EmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildTimelineItem(ctx, svc, history, i),
                      childCount: _itemCount(history),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 날짜 그룹 헤더 + 런 카드를 합산한 아이템 수
  int _itemCount(List<RunSummary> history) {
    if (history.isEmpty) return 0;
    final groups = _groupByMonth(history);
    return groups.fold<int>(0, (acc, g) => acc + 1 + g.runs.length);
  }

  Widget _buildTimelineItem(
    BuildContext ctx,
    RunHistoryService svc,
    List<RunSummary> history,
    int idx,
  ) {
    final groups = _groupByMonth(history);
    int cursor = 0;
    for (final group in groups) {
      if (cursor == idx) return _MonthHeader(label: group.label);
      cursor++;
      for (int j = 0; j < group.runs.length; j++) {
        if (cursor == idx) {
          final run = group.runs[j];
          final isLast = j == group.runs.length - 1;
          return _TimelineRunCard(
            run: run,
            visitCount: svc.visitCount(run.routeId),
            isLast: isLast,
          );
        }
        cursor++;
      }
    }
    return const SizedBox.shrink();
  }

  List<_MonthGroup> _groupByMonth(List<RunSummary> history) {
    final Map<String, _MonthGroup> map = {};
    for (final run in history) {
      final key =
          '${run.date.year}-${run.date.month.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => _MonthGroup(_monthLabel(run.date), []));
      map[key]!.runs.add(run);
    }
    return map.values.toList();
  }

  String _monthLabel(DateTime d) {
    const months = [
      '1월',
      '2월',
      '3월',
      '4월',
      '5월',
      '6월',
      '7월',
      '8월',
      '9월',
      '10월',
      '11월',
      '12월',
    ];
    return '${d.year}년  ${months[d.month - 1]}';
  }
}

class _MonthGroup {
  final String label;
  final List<RunSummary> runs;
  _MonthGroup(this.label, this.runs);
}

// ══════════════════════════════════════════════════════════════════
// 헤더 — 뒤로가기 + 타이틀 + 스탯 카드
// ══════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final RunHistoryService svc;
  const _Header({required this.svc});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPad + 12),
          // 뒤로가기 + 타이틀 + 클라우드
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 15,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RUN LOG',
                      style: AppText.inter(size: 24, weight: FontWeight.w900),
                    ),
                    Text(
                      '${svc.totalRuns}회 주행  ·  ${svc.totalDistanceKm.toStringAsFixed(0)} km',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Consumer<SupabaseService>(
                  builder: (_, sync, __) => _SyncBadge(sync: sync),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 스탯 카드 그리드
          _StatsGrid(svc: svc),
          const SizedBox(height: 16),
          // 구분선
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── 스탯 그리드 (2×2) ────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final RunHistoryService svc;
  const _StatsGrid({required this.svc});

  @override
  Widget build(BuildContext context) {
    final avgKm = svc.totalRuns > 0 ? svc.totalDistanceKm / svc.totalRuns : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.flag_rounded,
              label: 'TOTAL RUNS',
              value: '${svc.totalRuns}',
              unit: '회',
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.straighten,
              label: 'TOTAL KM',
              value: svc.totalDistanceKm.toStringAsFixed(0),
              unit: 'km',
              color: AppColors.cyan,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.av_timer,
              label: 'AVG DIST',
              value: avgKm.toStringAsFixed(1),
              unit: 'km',
              color: const Color(0xFFF59E0B),
            ),
          ),
          if (svc.bestMaxG != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.speed,
                label: 'BEST G',
                value: svc.bestMaxG!.toStringAsFixed(2),
                unit: 'G',
                color: const Color(0xFFEF4444),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      color: color.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: AppText.mono(size: 18, weight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 8,
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 월 헤더
// ══════════════════════════════════════════════════════════════════
class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.label(size: 11, color: AppColors.primaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.primaryContainer.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 타임라인 런 카드
// ══════════════════════════════════════════════════════════════════
class _TimelineRunCard extends StatelessWidget {
  final RunSummary run;
  final int visitCount;
  final bool isLast;
  const _TimelineRunCard({
    required this.run,
    required this.visitCount,
    required this.isLast,
  });

  String _weekday(DateTime d) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[d.weekday - 1];
  }

  Color _gColor(double? g) {
    if (g == null || g == 0) return AppColors.textSecondary;
    if (g >= 0.8) return const Color(0xFFEF4444);
    if (g >= 0.5) return const Color(0xFFF97316);
    return const Color(0xFFF59E0B);
  }

  String _gLabel(double? g) {
    if (g == null || g == 0) return '—';
    if (g >= 0.8) return 'HARD';
    if (g >= 0.5) return 'MED';
    return 'EASY';
  }

  @override
  Widget build(BuildContext context) {
    final gColor = _gColor(run.maxLateralG);
    final hasG = run.maxLateralG != null && run.maxLateralG! > 0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 타임라인 선 + 점 ──
          SizedBox(
            width: 52,
            child: Column(
              children: [
                // 상단 선
                Container(
                  width: 1.5,
                  height: 20,
                  color: AppColors.primaryContainer.withValues(alpha: 0.25),
                ),
                // 점
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                // 하단 선
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast
                        ? Colors.transparent
                        : AppColors.primaryContainer.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
          // ── 카드 ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 8),
              child: RevvGlassCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                color: AppColors.panel2.withValues(alpha: 0.88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 날짜 행
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh.withValues(
                              alpha: 0.34,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${run.date.month}/${run.date.day} (${_weekday(run.date)})',
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${run.date.hour.toString().padLeft(2, '0')}:${run.date.minute.toString().padLeft(2, '0')}',
                          style: GoogleFonts.orbitron(
                            fontSize: 10,
                            color: Colors.white30,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        // 날씨
                        Text(
                          '${run.weatherEmoji} ${run.tempDisplay}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 거리 + G 뱃지
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          run.distanceKm.toStringAsFixed(1),
                          style: GoogleFonts.orbitron(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'km',
                          style: GoogleFonts.orbitron(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (hasG)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: gColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: gColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  run.maxLateralG!.toStringAsFixed(2),
                                  style: GoogleFonts.orbitron(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: gColor,
                                  ),
                                ),
                                Text(
                                  _gLabel(run.maxLateralG),
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 7,
                                    fontWeight: FontWeight.w700,
                                    color: gColor,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 루트명 + 소요시간
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            run.routeName,
                            style: GoogleFonts.rajdhani(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          run.durationDisplay,
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // 회차 배지
                        if (visitCount >= 2) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.primaryContainer.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              '$visitCount회차',
                              style: GoogleFonts.rajdhani(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryContainer,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
            size: 52,
            color: AppColors.primaryContainer.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 18),
          Text(
            'NO RUNS YET',
            style: GoogleFonts.orbitron(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.18),
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'GO 버튼으로 첫 드라이브를 시작하세요',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 클라우드 동기화 배지 ─────────────────────────────────────────
class _SyncBadge extends StatelessWidget {
  final SupabaseService sync;
  const _SyncBadge({required this.sync});

  @override
  Widget build(BuildContext context) {
    if (!sync.isReady) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            '오프라인',
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }
    switch (sync.status) {
      case SyncStatus.syncing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.cyan,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '동기화 중',
              style: GoogleFonts.rajdhani(fontSize: 10, color: AppColors.cyan),
            ),
          ],
        );
      case SyncStatus.error:
        return Icon(Icons.cloud_off, size: 13, color: AppColors.red);
      default:
        return Icon(
          Icons.cloud_done_outlined,
          size: 13,
          color: AppColors.cyan.withValues(alpha: 0.7),
        );
    }
  }
}
