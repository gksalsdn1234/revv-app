import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/run_history_service.dart';
import '../services/challenge_service.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  static void show(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const RankingScreen(),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<Map<String, dynamic>>? _topRoutes;
  bool _loadingRoutes = true;
  String? _routeError;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadTopRoutes();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadTopRoutes() async {
    setState(() { _loadingRoutes = true; _routeError = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('routes')
          .orderBy('runCount', descending: true)
          .limit(20)
          .get();
      if (mounted) {
        setState(() {
          _topRoutes = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
          _loadingRoutes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loadingRoutes = false; _routeError = '데이터 로드 실패'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── 헤더 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'RANKING',
                    style: GoogleFonts.orbitron(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      color: Colors.white, letterSpacing: 4,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.emoji_events_rounded,
                      color: AppColors.red, size: 22),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── 탭 ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: TabBar(
                controller: _tab,
                indicatorColor: AppColors.red,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 2,
                labelStyle: GoogleFonts.rajdhani(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontSize: 13),
                unselectedLabelColor: AppColors.gray,
                labelColor: Colors.white,
                dividerColor: Colors.transparent,
                tabs: const [Tab(text: 'ROUTES'), Tab(text: 'MY STATS')],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _RoutesTab(
                    routes: _topRoutes,
                    loading: _loadingRoutes,
                    error: _routeError,
                    onRefresh: _loadTopRoutes,
                  ),
                  const _MyStatsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Routes Tab — 커뮤니티 인기 루트 랭킹
// ══════════════════════════════════════════════════════════════════
class _RoutesTab extends StatelessWidget {
  final List<Map<String, dynamic>>? routes;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  const _RoutesTab({
    required this.routes,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2));
    }

    final empty = routes == null || routes!.isEmpty;
    if (error != null || empty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined, color: AppColors.gray, size: 40),
            const SizedBox(height: 12),
            Text(
              empty ? '아직 커뮤니티 루트가 없어요\n루트 탐색 후 주행하면 등록돼요' : error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                  fontSize: 14, color: AppColors.gray, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRefresh,
              child: Text('새로고침',
                  style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: AppColors.red,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.red,
      backgroundColor: AppColors.panel,
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: routes!.length,
        itemBuilder: (_, i) =>
            _RouteRankCard(rank: i + 1, data: routes![i]),
      ),
    );
  }
}

class _RouteRankCard extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> data;
  const _RouteRankCard({required this.rank, required this.data});

  Color get _rankColor {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return AppColors.gray;
  }

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '이름 없음';
    final score = (data['windingScore'] as num?)?.toDouble() ?? 0.0;
    final runCount = (data['runCount'] as num?)?.toInt() ?? 0;
    final distKm = (data['distanceKm'] as num?)?.toDouble() ?? 0.0;
    final isLoop = data['isLoop'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: rank <= 3
              ? _rankColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          // 순위
          SizedBox(
            width: 34,
            child: Text(
              rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '#$rank',
              style: GoogleFonts.orbitron(
                fontSize: rank <= 3 ? 20 : 11,
                fontWeight: FontWeight.w700,
                color: _rankColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          // 루트 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name + (isLoop ? '  🔄' : ''),
                  style: GoogleFonts.rajdhani(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '${distKm.toStringAsFixed(0)} km',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: AppColors.gray),
                    ),
                    const SizedBox(width: 8),
                    _DifficultyPill(score: score),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // runCount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$runCount',
                style: GoogleFonts.orbitron(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: runCount > 0 ? AppColors.red : AppColors.gray,
                ),
              ),
              Text(
                '주행',
                style: GoogleFonts.rajdhani(
                    fontSize: 10, color: AppColors.gray, letterSpacing: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DifficultyPill extends StatelessWidget {
  final double score;
  const _DifficultyPill({required this.score});

  Color get _color {
    if (score >= 8.0) return const Color(0xFFE040FB);
    if (score >= 5.5) return AppColors.red;
    if (score >= 3.5) return const Color(0xFFF59E0B);
    if (score >= 2.0) return const Color(0xFF4CAF50);
    return AppColors.gray;
  }

  String get _label {
    if (score >= 8.0) return 'EXTREME';
    if (score >= 5.5) return 'HARD';
    if (score >= 3.5) return 'MEDIUM';
    if (score >= 2.0) return 'EASY';
    return 'SCENIC';
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: _color.withValues(alpha: 0.4)),
        ),
        child: Text(
          _label,
          style: GoogleFonts.rajdhani(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: _color, letterSpacing: 1,
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
// My Stats Tab — 챌린지 + 개인 통계
// ══════════════════════════════════════════════════════════════════
class _MyStatsTab extends StatelessWidget {
  const _MyStatsTab();

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RunHistoryService>();
    final runs = history.history;
    final ch = ChallengeService();

    final monthKm = ch.monthlyKm(runs);
    final weekKm = ch.weeklyKm(runs);
    final monthPct = ch.monthlyProgress(runs);
    final weekPct = ch.weeklyProgress(runs);
    final streak = ch.currentStreak(runs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _SectionLabel('이번 달 챌린지'),
        const SizedBox(height: 10),
        _ChallengeCard(
          title: '월간 목표',
          current: monthKm,
          goal: ChallengeService.monthlyGoalKm,
          progress: monthPct,
          icon: Icons.calendar_month_rounded,
        ),
        const SizedBox(height: 8),
        _ChallengeCard(
          title: '주간 목표',
          current: weekKm,
          goal: ChallengeService.weeklyGoalKm,
          progress: weekPct,
          icon: Icons.calendar_today_rounded,
        ),
        const SizedBox(height: 24),
        _SectionLabel('내 통계'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatCell(
              label: '총 거리',
              value: history.totalDistanceKm.toStringAsFixed(0),
              unit: 'km',
              icon: Icons.route_outlined,
            ),
            _StatCell(
              label: '총 드라이브',
              value: '${history.totalRuns}',
              unit: '회',
              icon: Icons.directions_car_rounded,
            ),
            _StatCell(
              label: '최고 횡G',
              value: history.bestMaxG?.toStringAsFixed(2) ?? '—',
              unit: history.bestMaxG != null ? 'G' : '',
              icon: Icons.speed_rounded,
            ),
            _StatCell(
              label: '연속 드라이브',
              value: '$streak',
              unit: '일',
              icon: Icons.local_fire_department_rounded,
              highlight: streak >= 3,
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.rajdhani(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: AppColors.gray, letterSpacing: 3,
        ),
      );
}

class _ChallengeCard extends StatelessWidget {
  final String title;
  final double current;
  final double goal;
  final double progress;
  final IconData icon;

  const _ChallengeCard({
    required this.title,
    required this.current,
    required this.goal,
    required this.progress,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: done
              ? AppColors.red.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: done ? AppColors.red : AppColors.gray, size: 15),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.rajdhani(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              if (done)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text('DONE',
                      style: GoogleFonts.orbitron(
                          fontSize: 8, color: AppColors.red,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                  done ? AppColors.red : const Color(0xFF4CAF50)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${current.toStringAsFixed(0)} km',
                style: GoogleFonts.orbitron(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              Text(
                '목표 ${goal.toStringAsFixed(0)} km',
                style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.gray),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool highlight;

  const _StatCell({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: highlight
                ? AppColors.red.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 13,
                    color: highlight ? AppColors.red : AppColors.gray),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.rajdhani(
                      fontSize: 10, color: AppColors.gray, letterSpacing: 1),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.orbitron(
                      fontSize: 22, fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                const SizedBox(width: 3),
                Text(unit,
                    style: GoogleFonts.rajdhani(
                        fontSize: 12, color: AppColors.gray)),
              ],
            ),
          ],
        ),
      );
}
