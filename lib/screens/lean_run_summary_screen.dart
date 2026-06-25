import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import '../services/run_history_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_run_summary.dart';
import '../ui/run_report_metrics.dart';
import '../widgets/map_widget.dart';

class LeanRunSummaryScreen extends StatefulWidget {
  final RunSession? session;

  const LeanRunSummaryScreen({super.key, required this.session});

  @override
  State<LeanRunSummaryScreen> createState() => _LeanRunSummaryScreenState();
}

class _LeanRunSummaryScreenState extends State<LeanRunSummaryScreen> {
  Future<RunSummary?>? _saveFuture;
  String? _selectedFeedback;
  bool _feedbackSaved = false;
  final Set<String> _expandedLogSections = {'pace'};

  // ── 리플레이 ──
  int _replayIndex = 0;
  bool _replayPlaying = false;
  Timer? _replayTimer;

  @override
  void initState() {
    super.initState();
    _saveFuture = _save();
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    super.dispose();
  }

  Future<RunSummary?> _save() async {
    final session = widget.session;
    if (session == null) return null;
    final history = context.read<RunHistoryService>();
    final summary = await history.save(session);
    final detail = RunTelemetryDetail.fromSession(summary.id, session);
    unawaited(history.saveDetail(detail));
    return summary;
  }

  Future<void> _saveFeedback(RunSummary summary, String feedbackType) async {
    final feedback = RouteFeedback(
      id: '${summary.id}_$feedbackType',
      runId: summary.id,
      routeId: summary.routeId,
      routeName: summary.routeName,
      feedbackType: feedbackType,
      createdAt: DateTime.now(),
    );
    await context.read<RunHistoryService>().saveFeedback(feedback);
    if (!mounted) return;
    setState(() {
      _selectedFeedback = feedbackType;
      _feedbackSaved = true;
    });
  }

  // ── 리플레이 제어 ──
  void _startReplay(List<LatLng> path) {
    if (path.length < 2) return;
    _replayTimer?.cancel();
    final intervalMs = math.max(40, 12000 ~/ path.length);
    setState(() {
      _replayIndex = 0;
      _replayPlaying = true;
    });
    _replayTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      final next = _replayIndex + 1;
      if (next >= path.length) {
        _replayTimer?.cancel();
        setState(() => _replayPlaying = false);
        return;
      }
      setState(() => _replayIndex = next);
    });
  }

  void _pauseReplay() {
    _replayTimer?.cancel();
    if (mounted) setState(() => _replayPlaying = false);
  }

  void _resumeReplay(List<LatLng> path) {
    if (path.length < 2 || _replayIndex >= path.length - 1) {
      _startReplay(path);
      return;
    }
    _replayTimer?.cancel();
    final intervalMs = math.max(40, 12000 ~/ path.length);
    setState(() => _replayPlaying = true);
    _replayTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      final next = _replayIndex + 1;
      if (next >= path.length) {
        _replayTimer?.cancel();
        setState(() => _replayPlaying = false);
        return;
      }
      setState(() => _replayIndex = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final language = context.watch<SettingsService>().appLanguage;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<RunSummary?>(
          future: _saveFuture,
          builder: (context, snapshot) {
            final summary = snapshot.data;
            final copy = session == null
                ? null
                : CopilotRunSummaryCopy.fromSession(
                    session,
                    summary: summary,
                    language: language,
                  );
            final waiting = snapshot.connectionState != ConnectionState.done;
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 지도 리플레이 ──
                        if (session != null)
                          _MapReplaySection(
                            session: session,
                            replayIndex: _replayIndex,
                            replayPlaying: _replayPlaying,
                            onPlay: () {
                              if (_replayPlaying) {
                                _pauseReplay();
                              } else {
                                _resumeReplay(session.gpsPath);
                              }
                            },
                            onRestart: () => _startReplay(session.gpsPath),
                            language: language,
                          ),

                        const SizedBox(height: 24),

                        // ── 헤더 ──
                        Text(
                          'COPILOT SUMMARY',
                          style: AppText.technicalLabel(
                            size: 12,
                            letterSpacing: 3,
                            color: AppColors.primaryContainer,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          session == null
                              ? AppCopy.t(
                                  language,
                                  ko: '저장할 주행이 없어요',
                                  en: 'No drive to save',
                                  fr: 'Aucun trajet à sauvegarder',
                                )
                              : copy?.headline ??
                                    AppCopy.t(
                                      language,
                                      ko: '오늘 주행 요약',
                                      en: "Today's drive summary",
                                      fr: 'Résumé du trajet',
                                    ),
                          style: AppText.display(
                            size: 38,
                            height: 0.96,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          session == null
                              ? AppCopy.t(
                                  language,
                                  ko: '세션이 만들어지기 전에 종료됐습니다.',
                                  en: 'Session ended before it was created.',
                                  fr: 'Session terminée trop tôt.',
                                )
                              : copy?.summaryLine ?? '',
                          style: AppText.body(
                            size: 13,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),

                        // ── 상세 스탯 ──
                        if (session != null) ...[
                          const SizedBox(height: 24),
                          _DetailedStatsSection(
                            session: session,
                            language: language,
                          ),
                        ],

                        // ── 드라이브 모드 바 ──
                        if (session != null &&
                            session.driveModeSeconds.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _DriveModeBar(
                            modes: session.driveModeSeconds,
                            language: language,
                          ),
                        ],

                        if (session != null &&
                            session.telemetrySamples.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _WindingReviewCard(
                            session: session,
                            language: language,
                          ),
                        ],

                        if (session != null) ...[
                          const SizedBox(height: 14),
                          _SessionLogSection(
                            session: session,
                            summary: summary,
                            waiting: waiting,
                            language: language,
                            expandedKeys: _expandedLogSections,
                            onToggle: (key) {
                              setState(() {
                                if (_expandedLogSections.contains(key)) {
                                  _expandedLogSections.remove(key);
                                } else {
                                  _expandedLogSections.add(key);
                                }
                              });
                            },
                          ),
                        ],

                        if (session != null && copy != null) ...[
                          const SizedBox(height: 16),
                          _CopilotNextCard(text: copy.nextSuggestion),
                          const SizedBox(height: 16),
                          _RouteFeedbackCard(
                            enabled: summary != null,
                            selected: _selectedFeedback,
                            saved: _feedbackSaved,
                            language: language,
                            onSelected: summary == null
                                ? null
                                : (type) => _saveFeedback(summary, type),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    children: [
                      _SaveStateCard(
                        summary: summary,
                        waiting: waiting,
                        language: language,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryContainer,
                            foregroundColor: AppColors.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          onPressed: () => Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst),
                          icon: const Icon(Icons.home_rounded),
                          label: Text(
                            AppCopy.t(
                              language,
                              ko: '홈으로',
                              en: 'Home',
                              fr: 'Accueil',
                            ),
                            style: AppText.body(
                              size: 17,
                              weight: FontWeight.w900,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── 지도 리플레이 섹션 ─────────────────────────────────────

class _MapReplaySection extends StatelessWidget {
  final RunSession session;
  final int replayIndex;
  final bool replayPlaying;
  final VoidCallback onPlay;
  final VoidCallback onRestart;
  final AppLanguage language;

  const _MapReplaySection({
    required this.session,
    required this.replayIndex,
    required this.replayPlaying,
    required this.onPlay,
    required this.onRestart,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final path = session.gpsPath;
    final hasPath = path.length >= 2;
    final replayPos = hasPath ? path[replayIndex] : null;
    final progress = hasPath ? replayIndex / (path.length - 1) : 0.0;
    final sharpCount = session.sharpCorners.length;
    final atEnd = hasPath && replayIndex >= path.length - 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 230,
        child: Stack(
          children: [
            // ── 지도 ──
            if (hasPath)
              Positioned.fill(
                child: MapWidget(
                  isSprintMode: true,
                  routePolyline: path,
                  routeFocusMode: true,
                  simulatedPosition: replayPos,
                ),
              )
            else
              Positioned.fill(
                child: Container(
                  color: AppColors.panel,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.gps_off_rounded,
                          color: AppColors.textHint,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppCopy.t(
                            language,
                            ko: 'GPS 경로 없음',
                            en: 'No GPS path',
                            fr: 'Pas de tracé GPS',
                          ),
                          style: AppText.body(
                            size: 13,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── 프로그레스 바 (리플레이 진행 중일 때) ──
            if (hasPath && (replayPlaying || replayIndex > 0))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: AppColors.primaryContainer.withValues(alpha: 0.72),
                ),
              ),

            // ── 컨트롤 오버레이 ──
            Positioned(
              bottom: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  // 재생/일시정지 버튼
                  if (hasPath)
                    GestureDetector(
                      onTap: onPlay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD00F1214),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primaryContainer.withValues(
                              alpha: 0.32,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              replayPlaying
                                  ? Icons.pause_rounded
                                  : atEnd
                                  ? Icons.replay_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppColors.primaryContainer,
                              size: 15,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              replayPlaying
                                  ? AppCopy.t(
                                      language,
                                      ko: '일시정지',
                                      en: 'PAUSE',
                                      fr: 'PAUSE',
                                    )
                                  : AppCopy.t(
                                      language,
                                      ko: '리플레이',
                                      en: 'REPLAY',
                                      fr: 'RELECTURE',
                                    ),
                              style: AppText.technicalLabel(
                                size: 10,
                                color: AppColors.primaryContainer,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  // 급조작 뱃지
                  if (sharpCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xD00F1214),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: AppColors.warning,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppCopy.t(
                              language,
                              ko: '$sharpCount G이벤트',
                              en: '$sharpCount G events',
                              fr: '$sharpCount événements G',
                            ),
                            style: AppText.technicalLabel(
                              size: 10,
                              color: AppColors.warning,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 상세 스탯 섹션 ────────────────────────────────────────

class _DetailedStatsSection extends StatelessWidget {
  final RunSession session;
  final AppLanguage language;

  const _DetailedStatsSection({required this.session, required this.language});

  @override
  Widget build(BuildContext context) {
    final peakG = session.maxLateralG.abs() >= session.maxLonG.abs()
        ? session.maxLateralG.abs()
        : session.maxLonG.abs();
    final sharpCount = session.sharpCorners.length;
    final routeDistanceKm = session.route?.distanceKm;
    final completionPct = routeCompletionPercent(
      drivenKm: session.distanceKm,
      routeDistanceKm: routeDistanceKm,
    );

    final stats = [
      _StatItem(
        label: AppCopy.t(language, ko: '거리', en: 'DISTANCE', fr: 'DISTANCE'),
        value: '${session.distanceKm.toStringAsFixed(2)} km',
        accent: false,
      ),
      _StatItem(
        label: AppCopy.t(language, ko: '시간', en: 'TIME', fr: 'DURÉE'),
        value: session.durationDisplay,
        accent: false,
      ),
      _StatItem(
        label: AppCopy.t(
          language,
          ko: '최고 속도',
          en: 'MAX SPEED',
          fr: 'VITESSE MAX',
        ),
        value: session.maxSpeedKmh > 0
            ? '${session.maxSpeedKmh.toStringAsFixed(0)} km/h'
            : '—',
        accent: false,
      ),
      _StatItem(
        label: AppCopy.t(
          language,
          ko: '평균 속도',
          en: 'AVG SPEED',
          fr: 'VITESSE MOY.',
        ),
        value: session.avgSpeedKmh > 0
            ? '${session.avgSpeedKmh.toStringAsFixed(0)} km/h'
            : '—',
        accent: false,
      ),
      _StatItem(
        label: AppCopy.t(language, ko: '피크 G', en: 'PEAK G', fr: 'G MAX'),
        value: peakG > 0 ? peakG.toStringAsFixed(2) : '—',
        accent: peakG >= 0.4,
      ),
      _StatItem(
        label: AppCopy.t(
          language,
          ko: '커브 이벤트',
          en: 'CURVE EVENTS',
          fr: 'ÉVÉNEMENTS',
        ),
        value: AppCopy.t(
          language,
          ko: sharpCount > 0 ? '$sharpCount회' : '없음',
          en: sharpCount > 0 ? '$sharpCount' : '—',
          fr: sharpCount > 0 ? '$sharpCount' : '—',
        ),
        accent: sharpCount > 0,
      ),
      if (completionPct != null)
        _StatItem(
          label: AppCopy.t(
            language,
            ko: '완주율',
            en: 'COMPLETION',
            fr: 'COMPLÉTION',
          ),
          value: '$completionPct%',
          accent: completionPct >= 80,
        ),
      if (session.telemetrySamples.isNotEmpty)
        _StatItem(
          label: AppCopy.t(language, ko: '샘플', en: 'SAMPLES', fr: 'ÉCHANT.'),
          value: '${session.telemetrySamples.length}',
          accent: false,
        ),
      if ((session.driveModeSeconds['winding'] ?? 0) > 0)
        _StatItem(
          label: AppCopy.t(language, ko: '와인딩', en: 'WINDING', fr: 'VIRAGE'),
          value: _formatCompactDuration(
            session.driveModeSeconds['winding'] ?? 0,
          ),
          accent: true,
        ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.55,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: stats.length,
      itemBuilder: (_, i) => _StatTile(item: stats[i]),
    );
  }
}

class _WindingReviewCard extends StatelessWidget {
  final RunSession session;
  final AppLanguage language;

  const _WindingReviewCard({required this.session, required this.language});

  @override
  Widget build(BuildContext context) {
    final samples = session.telemetrySamples;
    final absLatG = samples.map((s) => s.lateralG.abs()).toList()..sort();
    final p95LatG = _percentile(absLatG, 0.95);
    final avgLatG = _avg(absLatG);
    final brakingEvents = samples
        .where((s) => s.longitudinalG <= -0.30 && s.speedKmh >= 8)
        .length;
    final windingSamples = samples
        .where((s) => s.lateralG.abs() >= 0.18 && s.speedKmh >= 12)
        .length;
    final windingPct = samples.isEmpty
        ? 0
        : (windingSamples / samples.length * 100).round();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timeline_rounded,
                color: AppColors.primaryContainer,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                AppCopy.t(
                  language,
                  ko: '와인딩 리뷰 데이터',
                  en: 'Winding review data',
                  fr: 'Données virage',
                ),
                style: AppText.technicalLabel(
                  size: 10,
                  letterSpacing: 1.4,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ReviewChip(
                label: AppCopy.t(
                  language,
                  ko: '평균 횡G',
                  en: 'AVG LAT G',
                  fr: 'G LAT MOY.',
                ),
                value: avgLatG.toStringAsFixed(2),
              ),
              _ReviewChip(
                label: AppCopy.t(
                  language,
                  ko: '95% 횡G',
                  en: 'P95 LAT G',
                  fr: 'G LAT P95',
                ),
                value: p95LatG.toStringAsFixed(2),
              ),
              _ReviewChip(
                label: AppCopy.t(
                  language,
                  ko: '와인딩 비율',
                  en: 'WINDING',
                  fr: 'VIRAGE',
                ),
                value: '$windingPct%',
              ),
              _ReviewChip(
                label: AppCopy.t(
                  language,
                  ko: '제동 이벤트',
                  en: 'BRAKING',
                  fr: 'FREINAGE',
                ),
                value: '$brakingEvents',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionLogSection extends StatelessWidget {
  final RunSession session;
  final RunSummary? summary;
  final bool waiting;
  final AppLanguage language;
  final Set<String> expandedKeys;
  final ValueChanged<String> onToggle;

  const _SessionLogSection({
    required this.session,
    required this.summary,
    required this.waiting,
    required this.language,
    required this.expandedKeys,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final sections = _sessionLogGroups(
      session: session,
      summary: summary,
      waiting: waiting,
      language: language,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.primaryContainer,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppCopy.t(
                    language,
                    ko: '세션 로그',
                    en: 'SESSION LOG',
                    fr: 'JOURNAL SESSION',
                  ),
                  style: AppText.technicalLabel(
                    size: 10,
                    letterSpacing: 1.5,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ),
              Text(
                AppCopy.t(
                  language,
                  ko: '탭해서 펼치기',
                  en: 'TAP TO EXPAND',
                  fr: 'TOUCHER',
                ),
                style: AppText.technicalLabel(
                  size: 8,
                  letterSpacing: 0.8,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sections.map(
            (section) => _SessionLogAccordion(
              section: section,
              expanded: expandedKeys.contains(section.key),
              onTap: () => onToggle(section.key),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionLogGroup {
  final String key;
  final IconData icon;
  final String title;
  final String summary;
  final Color accent;
  final List<_SessionLogRow> rows;

  const _SessionLogGroup({
    required this.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.accent,
    required this.rows,
  });
}

class _SessionLogRow {
  final String label;
  final String value;

  const _SessionLogRow(this.label, this.value);
}

class _SessionLogAccordion extends StatelessWidget {
  final _SessionLogGroup section;
  final bool expanded;
  final VoidCallback onTap;

  const _SessionLogAccordion({
    required this.section,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: expanded
                  ? AppColors.surface.withValues(alpha: 0.72)
                  : AppColors.surface.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: expanded
                    ? section.accent.withValues(alpha: 0.34)
                    : AppColors.outlineVariant.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: section.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: section.accent.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Icon(
                        section.icon,
                        color: section.accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(
                              size: 14,
                              weight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            section.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(
                              size: 11,
                              weight: FontWeight.w800,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: section.accent,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: section.rows
                          .map((row) => _SessionLogDetailRow(row: row))
                          .toList(),
                    ),
                  ),
                  crossFadeState: expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                  sizeCurve: Curves.easeOutCubic,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionLogDetailRow extends StatelessWidget {
  final _SessionLogRow row;

  const _SessionLogDetailRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              row.label,
              style: AppText.technicalLabel(
                size: 8,
                letterSpacing: 0.8,
                color: AppColors.textHint,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: AppText.body(
                size: 12,
                height: 1.24,
                weight: FontWeight.w900,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<_SessionLogGroup> _sessionLogGroups({
  required RunSession session,
  required RunSummary? summary,
  required bool waiting,
  required AppLanguage language,
}) {
  final samples = session.telemetrySamples;
  final absLatG = samples.map((s) => s.lateralG.abs()).toList()..sort();
  final absLonG = samples.map((s) => s.longitudinalG.abs()).toList()..sort();
  final brakingEvents = samples
      .where((s) => s.longitudinalG <= -0.30 && s.speedKmh >= 8)
      .length;
  final accelerationEvents = samples
      .where((s) => s.longitudinalG >= 0.25 && s.speedKmh >= 8)
      .length;
  final windingSamples = samples
      .where((s) => s.lateralG.abs() >= 0.18 && s.speedKmh >= 12)
      .length;
  final windingPct = samples.isEmpty
      ? 0
      : (windingSamples / samples.length * 100).round();
  final peakG = math.max(session.maxLateralG.abs(), session.maxLonG.abs());
  final route = session.route;
  final completionPct = routeCompletionPercent(
    drivenKm: session.distanceKm,
    routeDistanceKm: route?.distanceKm,
  );
  final path = session.gpsPath;
  final startPoint = path.isEmpty ? null : path.first;
  final endPoint = path.length < 2 ? null : path.last;
  final sharpRows = session.sharpCorners.take(6).map((event) {
    return _SessionLogRow(
      _formatClock(event.time),
      '${event.lateralG.toStringAsFixed(2)}G · '
      '${event.speedKmh.toStringAsFixed(0)} km/h · '
      '${_modeLabel(event.driveMode, language)} · '
      '${_formatCoordinate(event.position)}',
    );
  }).toList();

  return [
    _SessionLogGroup(
      key: 'pace',
      icon: Icons.speed_rounded,
      title: AppCopy.t(language, ko: '주행 흐름', en: 'Pace log', fr: 'Rythme'),
      summary:
          '${session.distanceKm.toStringAsFixed(2)} km · ${session.durationDisplay}',
      accent: AppColors.primaryContainer,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '시작', en: 'START', fr: 'DÉPART'),
          _formatDateTime(session.startTime),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '종료', en: 'END', fr: 'FIN'),
          _formatDateTime(session.endTime),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '총 거리', en: 'DISTANCE', fr: 'DISTANCE'),
          '${session.distanceKm.toStringAsFixed(2)} km',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '평균/최고 속도', en: 'AVG / MAX', fr: 'MOY / MAX'),
          '${session.avgSpeedKmh.toStringAsFixed(0)} / ${session.maxSpeedKmh.toStringAsFixed(0)} km/h',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: 'GPS 포인트',
            en: 'GPS POINTS',
            fr: 'POINTS GPS',
          ),
          '${path.length}',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '텔레메트리 샘플',
            en: 'TELEMETRY',
            fr: 'TÉLÉMÉTRIE',
          ),
          '${samples.length}',
        ),
      ],
    ),
    _SessionLogGroup(
      key: 'gforce',
      icon: Icons.graphic_eq_rounded,
      title: AppCopy.t(
        language,
        ko: 'G-Force 분석',
        en: 'G-Force analysis',
        fr: 'Analyse G',
      ),
      summary: peakG > 0 ? 'Peak ${peakG.toStringAsFixed(2)}G' : 'No G peak',
      accent: peakG >= 0.4 ? AppColors.warning : AppColors.gold,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '최대 횡G', en: 'MAX LAT G', fr: 'G LAT MAX'),
          session.maxLateralG > 0
              ? session.maxLateralG.toStringAsFixed(2)
              : '—',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '최대 종G', en: 'MAX LONG G', fr: 'G LONG MAX'),
          session.maxLonG > 0 ? session.maxLonG.toStringAsFixed(2) : '—',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '평균/95% 횡G',
            en: 'AVG / P95 LAT',
            fr: 'LAT MOY / P95',
          ),
          '${_avg(absLatG).toStringAsFixed(2)} / ${_percentile(absLatG, 0.95).toStringAsFixed(2)}',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '평균/95% 종G',
            en: 'AVG / P95 LONG',
            fr: 'LONG MOY / P95',
          ),
          '${_avg(absLonG).toStringAsFixed(2)} / ${_percentile(absLonG, 0.95).toStringAsFixed(2)}',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '와인딩 샘플',
            en: 'WINDING SAMPLES',
            fr: 'ÉCHANT. VIRAGE',
          ),
          '$windingSamples / ${samples.length} · $windingPct%',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '제동/가속 이벤트',
            en: 'BRAKE / ACCEL',
            fr: 'FREIN / ACCEL',
          ),
          '$brakingEvents / $accelerationEvents',
        ),
      ],
    ),
    _SessionLogGroup(
      key: 'events',
      icon: Icons.bolt_rounded,
      title: AppCopy.t(
        language,
        ko: '코너 이벤트',
        en: 'Corner events',
        fr: 'Événements',
      ),
      summary: AppCopy.t(
        language,
        ko: '${session.sharpCorners.length}개 기록',
        en: '${session.sharpCorners.length} logged',
        fr: '${session.sharpCorners.length} notés',
      ),
      accent: session.sharpCorners.isEmpty
          ? AppColors.textHint
          : AppColors.warning,
      rows: sharpRows.isEmpty
          ? [
              _SessionLogRow(
                AppCopy.t(language, ko: '기록', en: 'LOG', fr: 'JOURNAL'),
                AppCopy.t(
                  language,
                  ko: '0.45G 이상 코너 이벤트가 없었습니다.',
                  en: 'No corner events above 0.45G.',
                  fr: 'Aucun événement au-dessus de 0.45G.',
                ),
              ),
            ]
          : [
              ...sharpRows,
              if (session.sharpCorners.length > sharpRows.length)
                _SessionLogRow(
                  AppCopy.t(language, ko: '더 있음', en: 'MORE', fr: 'PLUS'),
                  '+${session.sharpCorners.length - sharpRows.length}',
                ),
            ],
    ),
    _SessionLogGroup(
      key: 'route',
      icon: Icons.route_rounded,
      title: AppCopy.t(
        language,
        ko: '루트/위치',
        en: 'Route & position',
        fr: 'Route',
      ),
      summary: route?.name ?? session.routeName,
      accent: AppColors.success,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '루트', en: 'ROUTE', fr: 'ROUTE'),
          route?.name ?? session.routeName,
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '루트 ID', en: 'ROUTE ID', fr: 'ID ROUTE'),
          route?.id ?? '—',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '루트 거리/완주율',
            en: 'ROUTE / DONE',
            fr: 'ROUTE / FAIT',
          ),
          route == null
              ? '—'
              : '${route.distanceKm.toStringAsFixed(1)} km · ${completionPct == null ? '—' : '$completionPct%'}',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '커브 스타일', en: 'CURVE STYLE', fr: 'STYLE'),
          route == null
              ? '—'
              : '${route.curveStyle} · ${route.sharpCurveCount} curves',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '시작 좌표', en: 'START GPS', fr: 'GPS DÉPART'),
          startPoint == null ? '—' : _formatCoordinate(startPoint),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '종료 좌표', en: 'END GPS', fr: 'GPS FIN'),
          endPoint == null ? '—' : _formatCoordinate(endPoint),
        ),
      ],
    ),
    _SessionLogGroup(
      key: 'storage',
      icon: Icons.cloud_done_rounded,
      title: AppCopy.t(
        language,
        ko: '날씨/저장',
        en: 'Weather & storage',
        fr: 'Météo / stockage',
      ),
      summary: waiting
          ? AppCopy.t(language, ko: '저장 중', en: 'Saving', fr: 'Sauvegarde')
          : summary == null
          ? AppCopy.t(
              language,
              ko: '로컬 세션',
              en: 'Local session',
              fr: 'Session locale',
            )
          : 'ID ${summary.id}',
      accent: waiting ? AppColors.warning : AppColors.success,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '날씨', en: 'WEATHER', fr: 'MÉTÉO'),
          '${session.weatherEmoji} ${session.tempDisplay} · ${session.weatherDesc}',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '저장 상태', en: 'SAVE STATE', fr: 'ÉTAT'),
          waiting
              ? AppCopy.t(language, ko: '저장 중', en: 'Saving', fr: 'Sauvegarde')
              : summary == null
              ? AppCopy.t(
                  language,
                  ko: '요약 없음',
                  en: 'No summary',
                  fr: 'Sans résumé',
                )
              : AppCopy.t(language, ko: '저장 완료', en: 'Saved', fr: 'Sauvegardé'),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '런 ID', en: 'RUN ID', fr: 'ID RUN'),
          summary?.id ?? '—',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '샘플 저장', en: 'DETAIL SAMPLES', fr: 'ÉCHANT.'),
          '${samples.length}',
        ),
      ],
    ),
  ];
}

class _ReviewChip extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 134,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.technicalLabel(
              size: 8,
              letterSpacing: 0.8,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppText.body(
              size: 16,
              weight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final bool accent;

  const _StatItem({
    required this.label,
    required this.value,
    required this.accent,
  });
}

class _StatTile extends StatelessWidget {
  final _StatItem item;

  const _StatTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: item.accent
              ? AppColors.primaryContainer.withValues(alpha: 0.24)
              : AppColors.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            item.label,
            style: AppText.technicalLabel(
              size: 9,
              letterSpacing: 1.2,
              color: item.accent
                  ? AppColors.primaryContainer
                  : AppColors.textHint,
            ),
          ),
          Text(
            item.value,
            style: AppText.body(
              size: 20,
              weight: FontWeight.w900,
              color: item.accent
                  ? AppColors.primaryContainer
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCompactDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (minutes > 0) {
    return '${minutes}m ${remainder.toString().padLeft(2, '0')}s';
  }
  return '${seconds}s';
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute:$second';
}

String _formatClock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatCoordinate(LatLng point) {
  return '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}';
}

double _avg(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

double _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) return 0;
  final index = ((sortedValues.length - 1) * percentile).round();
  return sortedValues[index.clamp(0, sortedValues.length - 1)];
}

// ── 드라이브 모드 바 ──────────────────────────────────────

class _DriveModeBar extends StatelessWidget {
  final Map<String, int> modes;
  final AppLanguage language;

  const _DriveModeBar({required this.modes, required this.language});

  @override
  Widget build(BuildContext context) {
    final total = modes.values.fold(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();

    final order = ['simulation', 'cruise', 'winding', 'sport', 'attack'];
    final sorted = order
        .where((k) => modes.containsKey(k) && modes[k]! > 0)
        .map((k) => MapEntry(k, modes[k]!))
        .toList();
    // Add any keys not in the ordered list
    for (final entry in modes.entries) {
      if (!order.contains(entry.key) && entry.value > 0) {
        sorted.add(entry);
      }
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppCopy.t(
              language,
              ko: 'DRIVE MODE',
              en: 'DRIVE MODE',
              fr: 'MODE CONDUITE',
            ),
            style: AppText.technicalLabel(
              size: 9,
              letterSpacing: 1.6,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 10),
          // 프로그레스 바
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Row(
                children: sorted.map((entry) {
                  final frac = entry.value / total;
                  return Expanded(
                    flex: (frac * 1000).round(),
                    child: Container(color: _modeColor(entry.key)),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 레전드
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: sorted.map((entry) {
              final pct = (entry.value / total * 100).round();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _modeColor(entry.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_modeLabel(entry.key, language)} $pct%',
                    style: AppText.body(
                      size: 11,
                      weight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

Color _modeColor(String mode) {
  return switch (mode) {
    'cruise' => AppColors.primaryContainer,
    'winding' => AppColors.warning,
    'sport' => const Color(0xFFFF9800),
    'attack' => AppColors.danger,
    'simulation' => AppColors.textHint,
    _ => AppColors.textSecondary,
  };
}

String _modeLabel(String mode, AppLanguage language) {
  return switch (mode) {
    'cruise' => AppCopy.t(language, ko: '크루즈', en: 'Cruise', fr: 'Cruise'),
    'winding' => AppCopy.t(language, ko: '와인딩', en: 'Winding', fr: 'Virage'),
    'sport' => AppCopy.t(language, ko: '스포츠', en: 'Sport', fr: 'Sport'),
    'attack' => AppCopy.t(language, ko: '어택', en: 'Attack', fr: 'Attaque'),
    'simulation' => AppCopy.t(language, ko: '시뮬레이션', en: 'Sim', fr: 'Sim'),
    _ => mode,
  };
}

// ── 기존 위젯들 ───────────────────────────────────────────

class _FeedbackOption {
  final String type;
  final IconData icon;

  const _FeedbackOption({required this.type, required this.icon});
}

const _feedbackOptions = [
  _FeedbackOption(type: 'liked', icon: Icons.thumb_up_alt_rounded),
  _FeedbackOption(type: 'too_short', icon: Icons.short_text_rounded),
  _FeedbackOption(type: 'flow_broken', icon: Icons.sync_problem_rounded),
  _FeedbackOption(type: 'hide_route', icon: Icons.visibility_off_rounded),
];

class _CopilotNextCard extends StatelessWidget {
  final String text;

  const _CopilotNextCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.psychology_rounded,
            color: AppColors.primaryContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppCopy.t(
                    context.watch<SettingsService>().appLanguage,
                    ko: '다음 추천 힌트',
                    en: 'Next suggestion',
                    fr: 'Prochaine suggestion',
                  ),
                  style: AppText.technicalLabel(
                    size: 10,
                    color: AppColors.primaryContainer,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: AppText.body(
                    size: 13,
                    height: 1.36,
                    weight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteFeedbackCard extends StatelessWidget {
  final bool enabled;
  final String? selected;
  final bool saved;
  final AppLanguage language;
  final ValueChanged<String>? onSelected;

  const _RouteFeedbackCard({
    required this.enabled,
    required this.selected,
    required this.saved,
    required this.language,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_rounded,
                color: AppColors.primaryContainer,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  saved
                      ? AppCopy.t(
                          language,
                          ko: '피드백 저장됨',
                          en: 'Feedback saved',
                          fr: 'Retour enregistré',
                        )
                      : AppCopy.t(
                          language,
                          ko: '이 루트 어땠나요?',
                          en: 'How was this route?',
                          fr: 'Comment était cette route ?',
                        ),
                  style: AppText.body(
                    size: 14,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _feedbackOptions.map((option) {
              final active = selected == option.type;
              return OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: active
                      ? AppColors.onPrimary
                      : AppColors.textSecondary,
                  backgroundColor: active
                      ? AppColors.primaryContainer
                      : AppColors.surface.withValues(alpha: 0.72),
                  side: BorderSide(
                    color: active
                        ? AppColors.primaryContainer
                        : AppColors.outlineVariant.withValues(alpha: 0.34),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                ),
                onPressed: enabled ? () => onSelected?.call(option.type) : null,
                icon: Icon(option.icon, size: 16),
                label: Text(
                  _feedbackLabel(option.type, language),
                  style: AppText.body(
                    size: 12,
                    weight: FontWeight.w900,
                    color: active
                        ? AppColors.onPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

String _feedbackLabel(String type, AppLanguage language) {
  return switch (type) {
    'liked' => AppCopy.t(language, ko: '좋았음', en: 'Liked it', fr: 'Bien'),
    'too_short' => AppCopy.t(
      language,
      ko: '너무 짧음',
      en: 'Too short',
      fr: 'Trop court',
    ),
    'flow_broken' => AppCopy.t(
      language,
      ko: '흐름 끊김',
      en: 'Flow broke',
      fr: 'Rythme cassé',
    ),
    'hide_route' => AppCopy.t(
      language,
      ko: '다시 추천 안 함',
      en: "Don't suggest again",
      fr: 'Ne plus proposer',
    ),
    _ => type,
  };
}

class _SaveStateCard extends StatelessWidget {
  final RunSummary? summary;
  final bool waiting;
  final AppLanguage language;

  const _SaveStateCard({
    required this.summary,
    required this.waiting,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final label = waiting
        ? AppCopy.t(language, ko: '저장 중', en: 'Saving', fr: 'Sauvegarde')
        : summary == null
        ? AppCopy.t(
            language,
            ko: '세션 없음',
            en: 'No session',
            fr: 'Aucune session',
          )
        : AppCopy.t(
            language,
            ko: '로컬 저장 완료',
            en: 'Saved locally',
            fr: 'Sauvegardé localement',
          );
    final saved = summary;
    final detail = saved == null
        ? AppCopy.t(
            language,
            ko: '주행 데이터가 없어서 기록을 만들지 않았습니다.',
            en: 'No drive data was available, so no record was created.',
            fr: 'Aucune donnée de trajet, aucun historique créé.',
          )
        : AppCopy.t(
            language,
            ko: '${saved.routeName} · 클라우드는 가능할 때 백그라운드 업로드',
            en: '${saved.routeName} · cloud uploads in the background when available',
            fr: '${saved.routeName} · upload cloud en arrière-plan si possible',
          );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          if (waiting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryContainer,
              ),
            )
          else
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primaryContainer,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.body(
                    size: 14,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
