import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/run_history_service.dart';
import '../theme/colors.dart';

// ── 드라이버 레벨 데이터 ──────────────────────────────────────────
class _Level {
  final String title;
  final String emoji;
  final double minKm;
  final double maxKm;
  final Color color;
  const _Level({
    required this.title,
    required this.emoji,
    required this.minKm,
    required this.maxKm,
    required this.color,
  });
}

const _levels = [
  _Level(title: '뉴비',       emoji: '🌱', minKm: 0,    maxKm: 100,   color: Color(0xFF60A5FA)),
  _Level(title: '익스플로러', emoji: '🗺️', minKm: 100,  maxKm: 500,   color: Color(0xFF34D399)),
  _Level(title: '스포츠',     emoji: '⚡', minKm: 500,  maxKm: 2000,  color: Color(0xFFF59E0B)),
  _Level(title: '마스터',     emoji: '🔥', minKm: 2000, maxKm: 5000,  color: Color(0xFFF97316)),
  _Level(title: '레전드',     emoji: '👑', minKm: 5000, maxKm: 99999, color: Color(0xFFEF4444)),
];

_Level _getLevel(double km) {
  for (final l in _levels.reversed) {
    if (km >= l.minKm) return l;
  }
  return _levels.first;
}

// ── 마일스톤 ─────────────────────────────────────────────────────
const _milestones = [100.0, 500.0, 1000.0, 5000.0];
const _milestoneLabels = ['100km 🏁', '500km ⚡', '1000km 🔥', '5000km 👑'];

// ══════════════════════════════════════════════════════════════════
// DriverLevelSheet — 바텀시트로 표시되는 드라이버 프로필 카드
// ══════════════════════════════════════════════════════════════════
class DriverLevelSheet extends StatelessWidget {
  const DriverLevelSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const DriverLevelSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hist = context.watch<RunHistoryService>();
    final totalKm = hist.totalDistanceKm;
    final totalRuns = hist.totalRuns;
    final bestG = hist.bestMaxG;
    final level = _getLevel(totalKm);

    // 현재 레벨 내 진행률
    final progress = level.maxKm >= 99999
        ? 1.0
        : ((totalKm - level.minKm) / (level.maxKm - level.minKm)).clamp(0.0, 1.0);
    final nextKm = level.maxKm >= 99999 ? null : level.maxKm;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: level.color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 드래그 핸들 ──
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── 레벨 헤더 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(level.emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DRIVER LEVEL',
                      style: GoogleFonts.orbitron(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textHint,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      level.title.toUpperCase(),
                      style: GoogleFonts.orbitron(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: level.color,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // 총 km 뱃지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: level.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: level.color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${totalKm.toStringAsFixed(0)} km',
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: level.color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── 경험치 바 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${level.minKm.toInt()} km',
                      style: GoogleFonts.rajdhani(
                          fontSize: 10, color: AppColors.textHint),
                    ),
                    if (nextKm != null)
                      Text(
                        '다음 레벨까지 ${(nextKm - totalKm).toInt()} km',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary),
                      )
                    else
                      Text(
                        '최고 레벨 달성! 🎉',
                        style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [level.color, level.color.withValues(alpha: 0.6)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                                color: level.color.withValues(alpha: 0.4),
                                blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // ── 통계 3칸 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _StatCell(label: 'TOTAL RUNS', value: '$totalRuns', icon: '🏎️'),
                _StatCell(
                  label: 'TOTAL KM',
                  value: totalKm.toStringAsFixed(1),
                  icon: '📍',
                ),
                _StatCell(
                  label: 'BEST G',
                  value: bestG != null ? '${bestG.toStringAsFixed(2)}G' : '—',
                  icon: '⚡',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // ── 마일스톤 배지 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MILESTONES',
                  style: GoogleFonts.orbitron(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHint,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(_milestones.length, (i) {
                    final done = totalKm >= _milestones[i];
                    return _MilestoneBadge(
                        label: _milestoneLabels[i], achieved: done);
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  const _StatCell({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.orbitron(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: AppColors.textHint,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneBadge extends StatelessWidget {
  final String label;
  final bool achieved;
  const _MilestoneBadge({required this.label, required this.achieved});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: achieved
            ? AppColors.red.withValues(alpha: 0.15)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: achieved ? AppColors.red.withValues(alpha: 0.5) : Colors.white12,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: achieved ? Colors.white : AppColors.textHint,
        ),
      ),
    );
  }
}
