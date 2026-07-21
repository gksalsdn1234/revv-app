import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../core/storage_keys.dart';
import '../models/revv_route.dart';
import '../models/route_feedback.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import '../services/run_history_service.dart';
import '../services/run_session_service.dart';
import '../services/drive_dynamics_tracker.dart';
import '../services/external_nav.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_run_summary.dart';
import '../ui/run_share_card_content.dart';
import '../ui/run_share_card_widget.dart';
import '../ui/run_share_metrics.dart';
import '../widgets/map_widget.dart';

class LeanRunSummaryScreen extends StatefulWidget {
  final RunSession? session;
  final RunSummary? historySummary;
  final RunTelemetryDetail? historyDetail;
  final Future<File> Function()? shareExporter;
  final Future<void> Function(File file)? sharePresenter;

  const LeanRunSummaryScreen({super.key, required this.session})
    : historySummary = null,
      historyDetail = null,
      shareExporter = null,
      sharePresenter = null;

  const LeanRunSummaryScreen.history({
    super.key,
    required RunSummary summary,
    RunTelemetryDetail? detail,
    this.shareExporter,
    this.sharePresenter,
  }) : session = null,
       historySummary = summary,
       historyDetail = detail;

  @override
  State<LeanRunSummaryScreen> createState() => _LeanRunSummaryScreenState();
}

class _LeanRunSummaryScreenState extends State<LeanRunSummaryScreen> {
  Future<RunSummary?>? _saveFuture;
  String? _selectedFeedback;
  bool _feedbackSaved = false;
  bool _shareExporting = false;
  final Set<String> _expandedLogSections = {'pace'};

  // ── 리플레이 ──
  int _replayIndex = 0;
  bool _replayPlaying = false;
  Timer? _replayTimer;

  @override
  void initState() {
    super.initState();
    _saveFuture = widget.historySummary == null
        ? _save()
        : Future.value(widget.historySummary);
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
    RunSessionService? sessions;
    try {
      sessions = context.read<RunSessionService>();
    } on ProviderNotFoundException {
      sessions = null;
    }
    final summary = await history.saveSession(session);
    await sessions?.clearRecovery();
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

  Future<void> _exportShareCard(GlobalKey repaintKey) async {
    if (_shareExporting) return;
    setState(() => _shareExporting = true);
    try {
      final exporter = widget.shareExporter;
      final file = exporter == null
          ? await exportRunShareCardPngFile(
              repaintKey: repaintKey,
              directory: Directory.systemTemp,
              fileName: 'revv-share-card.png',
            )
          : await exporter();
      // 시스템 공유 시트가 성공 피드백 그 자체 — 경로 스낵바는 띄우지 않는다
      final presenter = widget.sharePresenter ?? _presentSystemShareSheet;
      await presenter(file);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppCopy.t(
              context.read<SettingsService>().appLanguage,
              ko: '공유 카드를 만들지 못했어요',
              en: 'Could not prepare share card',
              fr: 'Impossible de préparer la carte',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _shareExporting = false);
    }
  }

  static Future<void> _presentSystemShareSheet(File file) {
    return SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
  }

  Future<void> _navigateHome(AppLanguage language) async {
    // async gap 전에 context 의존값을 캡처한다 (lint: use_build_context_synchronously)
    final current = context.read<LocationService>().bestKnownLatLng;
    final prefs = await SharedPreferences.getInstance();
    final homeLat = prefs.getDouble(StorageKeys.homeLat);
    final homeLng = prefs.getDouble(StorageKeys.homeLng);
    final destination = homeLat == null || homeLng == null
        ? null
        : LatLng(homeLat, homeLng);
    if (destination == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppCopy.t(
                language,
                ko: '집 위치를 먼저 설정하세요',
                en: 'Set your home location first',
                fr: 'Définissez d’abord votre domicile',
              ),
            ),
          ),
        );
      }
      return;
    }
    final appUri = buildGoogleMapsAppUri(
      origin: current,
      destination: destination,
      waypoints: const [],
    );
    final webUri = buildGoogleMapsDirectionsUri(
      origin: current,
      destination: destination,
      waypoints: const [],
    );
    final launched = await launchExternalNavigationWithFallback(
      primaryUri: appUri,
      fallbackUri: webUri,
      launcher: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
    );
  }

  void _showSharePreview({
    required RunSummary summary,
    required RunTelemetryDetail? detail,
    required RunSession? session,
    required AppLanguage language,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharePreviewSheet(
        summary: summary,
        detail: detail,
        session: session,
        language: language,
        exporting: _shareExporting,
        onExport: _exportShareCard,
      ),
    );
  }

  // ── 리플레이 제어 ──
  void _startReplay(List<LatLng> path) {
    if (path.length < 2) return;
    setState(() {
      _replayIndex = 0;
      _replayPlaying = true;
    });
    _runReplayTimer(path);
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
    setState(() => _replayPlaying = true);
    _runReplayTimer(path);
  }

  void _runReplayTimer(List<LatLng> path) {
    _replayTimer?.cancel();
    final intervalMs = math.max(40, 12000 ~/ path.length);
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
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: FutureBuilder<RunSummary?>(
          future: _saveFuture,
          builder: (context, snapshot) {
            final summary = widget.historySummary ?? snapshot.data;
            final copy = session == null
                ? null
                : CopilotRunSummaryCopy.fromSession(
                    session,
                    summary: summary,
                    language: language,
                  );
            final detail = session == null
                ? widget.historyDetail
                : RunTelemetryDetail.fromSession(
                    summary?.id ?? 'preview',
                    session,
                  );
            final dynamicsSummary = _dynamicsSummary(session, detail);
            final shareMetrics = buildRunShareMetrics(
              session: session,
              summary: summary,
              detail: detail,
              language: language,
            );
            final storedFeedback = summary == null
                ? null
                : context.watch<RunHistoryService>().feedbackForRun(summary.id);
            final selectedFeedback =
                storedFeedback?.feedbackType ?? _selectedFeedback;
            final feedbackSaved = storedFeedback != null || _feedbackSaved;
            final waiting = snapshot.connectionState != ConnectionState.done;
            return Stack(
              children: [
                Column(
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

                            const SizedBox(height: 20),

                            // ── RUN COMPLETE banner ──
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                16,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Checkered top stripe
                                  SizedBox(
                                    height: 8,
                                    width: double.infinity,
                                    child: CustomPaint(
                                      painter: _SummaryCheckeredPainter(
                                        tileSize: 8,
                                        lightColor: AppColors.cream,
                                        darkColor: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    AppCopy.t(
                                      language,
                                      ko: summary == null ? '주행 완료' : '주행 리포트',
                                      en: summary == null
                                          ? 'RUN COMPLETE'
                                          : 'RUN REPORT',
                                      fr: summary == null
                                          ? 'Course terminée'
                                          : 'RAPPORT',
                                    ),
                                    style: AppText.mono(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      color: AppColors.primaryContainer,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    summary?.routeName ??
                                        copy?.headline ??
                                        AppCopy.t(
                                          language,
                                          ko: '저장할 주행이 없어요',
                                          en: 'No drive to save',
                                          fr: 'Aucun trajet à sauvegarder',
                                        ),
                                    style: AppText.label(
                                      size: 32,
                                      weight: FontWeight.w800,
                                      color: AppColors.cream,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    session == null
                                        ? historySummaryLine(summary, language)
                                        : copy?.summaryLine ?? '',
                                    style: AppText.mono(
                                      size: 11,
                                      weight: FontWeight.w700,
                                      color: AppColors.stone,
                                    ),
                                  ),
                                  if (dynamicsSummary != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      dynamicsSummaryLine(
                                        language,
                                        dynamicsSummary,
                                      ),
                                      key: const ValueKey(
                                        'dynamics-summary-line',
                                      ),
                                      style: AppText.mono(
                                        size: 11,
                                        weight: FontWeight.w700,
                                        color: AppColors.stone,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            if (session != null || summary != null) ...[
                              const SizedBox(height: 14),
                              _RunHeadlineStats(
                                metrics: shareMetrics,
                                language: language,
                              ),
                            ],

                            // ── 상세 스탯 ──
                            if (session != null || summary != null) ...[
                              const SizedBox(height: 24),
                              _RevvRecapSection(
                                metrics: shareMetrics,
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

                            if (session != null) ...[
                              const SizedBox(height: 14),
                              _SessionLogSection(
                                session: session,
                                summary: summary,
                                detail: detail,
                                metrics: shareMetrics,
                                feedbackType: selectedFeedback,
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
                                selected: selectedFeedback,
                                saved: feedbackSaved,
                                language: language,
                                onSelected: summary == null
                                    ? null
                                    : (type) => _saveFeedback(summary, type),
                              ),
                            ],
                            if (session == null && summary != null) ...[
                              const SizedBox(height: 14),
                              _SavedRunReportSection(
                                summary: summary,
                                detail: detail,
                                metrics: shareMetrics,
                                language: language,
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
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: summary == null
                                  ? null
                                  : () => _showSharePreview(
                                      summary: summary,
                                      detail: detail,
                                      session: session,
                                      language: language,
                                    ),
                              icon: _shareExporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.ios_share_rounded),
                              label: Text(
                                AppCopy.t(
                                  language,
                                  ko: '공유 카드 만들기',
                                  en: 'Share ride card',
                                  fr: 'Partager la carte',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  unawaited(_navigateHome(language)),
                              icon: const Icon(
                                Icons.assistant_direction_rounded,
                              ),
                              label: Text(
                                AppCopy.t(
                                  language,
                                  ko: '집까지 안내',
                                  en: 'Navigate home',
                                  fr: 'Guidage retour',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
                                style: AppText.label(
                                  size: 17,
                                  weight: FontWeight.w800,
                                  color: AppColors.onPrimary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SharePreviewSheet extends StatefulWidget {
  final RunSummary summary;
  final RunTelemetryDetail? detail;
  final RunSession? session;
  final AppLanguage language;
  final bool exporting;
  final Future<void> Function(GlobalKey repaintKey) onExport;

  const _SharePreviewSheet({
    required this.summary,
    required this.detail,
    required this.session,
    required this.language,
    required this.exporting,
    required this.onExport,
  });

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final GlobalKey _repaintKey = GlobalKey();
  ShareCardPreset _preset = ShareCardPreset.square;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final content = buildRunShareCardContent(
      preset: _preset,
      summary: widget.summary,
      detail: widget.detail,
      session: widget.session,
      language: widget.language,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.cream.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppCopy.sharePreview(widget.language),
                        style: AppText.label(
                          size: 18,
                          weight: FontWeight.w800,
                          color: AppColors.cream,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppCopy.cancel(widget.language),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.cream,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final preset in ShareCardPreset.values) ...[
                      Expanded(
                        child: _SharePresetButton(
                          label: _sharePresetLabel(preset, widget.language),
                          selected: preset == _preset,
                          onTap: () => setState(() => _preset = preset),
                        ),
                      ),
                      if (preset != ShareCardPreset.values.last)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _exporting || widget.exporting
                        ? null
                        : () async {
                            setState(() => _exporting = true);
                            try {
                              await widget.onExport(_repaintKey);
                            } finally {
                              if (mounted) setState(() => _exporting = false);
                            }
                          },
                    icon: _exporting || widget.exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(AppCopy.exportCard(widget.language)),
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final previewWidth = constraints.maxWidth
                        .clamp(0.0, 360.0)
                        .toDouble();
                    return Center(
                      child: SizedBox(
                        width: previewWidth,
                        child: RepaintBoundary(
                          key: _repaintKey,
                          child: RunShareCardWidget(content: content),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SharePresetButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SharePresetButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? AppColors.primaryContainer
            : AppColors.surfaceLowest,
        foregroundColor: selected ? AppColors.onPrimary : AppColors.cream,
        side: BorderSide(
          color: selected
              ? AppColors.primaryContainer
              : AppColors.cream.withValues(alpha: 0.22),
        ),
      ),
      child: Text(label),
    );
  }
}

String _sharePresetLabel(ShareCardPreset preset, AppLanguage language) {
  return switch (preset) {
    ShareCardPreset.story => AppCopy.sharePresetStory(language),
    ShareCardPreset.square => AppCopy.sharePresetSquare(language),
    ShareCardPreset.sticker => AppCopy.sharePresetSticker(language),
  };
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
                          color: AppColors.ink.withValues(alpha: 0.82),
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
                        color: AppColors.ink.withValues(alpha: 0.82),
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
                              ko: '$sharpCount 코너 이벤트',
                              en: '$sharpCount corner events',
                              fr: '$sharpCount événements',
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

class _RunHeadlineStats extends StatelessWidget {
  final RunShareMetrics metrics;
  final AppLanguage language;

  const _RunHeadlineStats({required this.metrics, required this.language});

  @override
  Widget build(BuildContext context) {
    final displayed = {
      for (final metric in metrics.defaultShareMetrics) metric.id: metric.value,
    };
    return Row(
      children: [
        Expanded(
          child: _HeadlineStat(
            label: AppCopy.shareMetricLabel(language, 'distance'),
            value: displayed['distance'] ?? '0.0 km',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _HeadlineStat(
            label: AppCopy.shareMetricLabel(language, 'duration'),
            value: displayed['duration'] ?? '0s',
          ),
        ),
      ],
    );
  }
}

class _HeadlineStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeadlineStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.mono(
              size: 9,
              letterSpacing: 1.2,
              color: AppColors.stone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppText.label(
              size: 27,
              weight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevvRecapSection extends StatelessWidget {
  final RunShareMetrics metrics;
  final AppLanguage language;

  const _RevvRecapSection({required this.metrics, required this.language});

  @override
  Widget build(BuildContext context) {
    final displayed = {
      for (final metric in metrics.defaultShareMetrics) metric.id: metric.value,
    };
    final stats = <_StatItem>[
      if (displayed['revvScore'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'revvScore'),
          value: value,
          accent: true,
        ),
      if (displayed['winding'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'winding'),
          value: value,
          accent: true,
        ),
      if (displayed['flow'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'flow'),
          value: value,
          accent: false,
        ),
      if (displayed['technical'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'technical'),
          value: value,
          accent: false,
        ),
      if (displayed['smoothness'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'smoothness'),
          value: value,
          accent: false,
        ),
      _StatItem(
        label: AppCopy.shareMetricLabel(language, 'distance'),
        value: displayed['distance'] ?? '0.0 km',
        accent: false,
      ),
      _StatItem(
        label: AppCopy.shareMetricLabel(language, 'duration'),
        value: displayed['duration'] ?? '0s',
        accent: false,
      ),
      if (displayed['cornerEvents'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'cornerEvents'),
          value: value,
          accent: true,
        ),
      if (displayed['route'] case final value?)
        _StatItem(
          label: AppCopy.shareMetricLabel(language, 'route'),
          value: value,
          accent: false,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_circle_rounded,
                color: AppColors.primaryContainer,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                AppCopy.t(
                  language,
                  ko: 'REVV 리캡',
                  en: 'REVV Recap',
                  fr: 'REVV Recap',
                ),
                style: AppText.mono(
                  size: 10,
                  letterSpacing: 1.5,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
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
          ),
        ],
      ),
    );
  }
}

class _SavedRunReportSection extends StatelessWidget {
  final RunSummary summary;
  final RunTelemetryDetail? detail;
  final RunShareMetrics metrics;
  final AppLanguage language;

  const _SavedRunReportSection({
    required this.summary,
    required this.detail,
    required this.metrics,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final analytics = detail?.analytics ?? const <String, dynamic>{};
    final sampleCount =
        _analyticsInt(analytics, 'sampleCount') ?? summary.telemetrySampleCount;
    final gpsPointCount = _analyticsInt(analytics, 'gpsPointCount');
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 16),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppCopy.t(
              language,
              ko: '저장된 리포트',
              en: 'Saved report',
              fr: 'Rapport sauvegardé',
            ),
            style: AppText.mono(
              size: 10,
              letterSpacing: 1.5,
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          if (kDebugMode) ...[
            _SavedRunReportRow(
              label: 'DETAIL DATA',
              value: AppCopy.t(
                language,
                ko: detail == null ? '요약만 있음' : '상세 불러옴',
                en: detail == null ? 'Summary only' : 'Detail loaded',
                fr: detail == null ? 'Résumé seul' : 'Détail chargé',
              ),
            ),
            _SavedRunReportRow(label: 'SAMPLES', value: '$sampleCount'),
            if (gpsPointCount != null)
              _SavedRunReportRow(label: 'GPS POINTS', value: '$gpsPointCount'),
          ],
          _SavedRunReportRow(
            label: 'BRAKE / ACCEL',
            value:
                '${summary.brakingEventCount} / ${summary.accelerationEventCount}',
          ),
          _SavedRunReportRow(
            label: AppCopy.t(
              language,
              ko: '공개 기본값',
              en: 'PUBLIC DEFAULT',
              fr: 'PUBLIC PAR DÉFAUT',
            ),
            value: AppCopy.t(
              language,
              ko: '비공개 속도 데이터 숨김',
              en: 'Private speed data hidden',
              fr: 'Données de vitesse masquées',
            ),
          ),
          if (kDebugMode)
            _SavedRunReportRow(
              label: 'REPORT METRICS',
              value: '${metrics.defaultShareMetrics.length}',
            ),
        ],
      ),
    );
  }
}

class _SavedRunReportRow extends StatelessWidget {
  final String label;
  final String value;

  const _SavedRunReportRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.technicalLabel(
                size: 9,
                letterSpacing: 1,
                color: AppColors.stone,
              ),
            ),
          ),
          Text(
            value,
            style: AppText.body(
              size: 14,
              weight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionLogSection extends StatelessWidget {
  final RunSession session;
  final RunSummary? summary;
  final RunTelemetryDetail? detail;
  final RunShareMetrics metrics;
  final String? feedbackType;
  final bool waiting;
  final AppLanguage language;
  final Set<String> expandedKeys;
  final ValueChanged<String> onToggle;

  const _SessionLogSection({
    required this.session,
    required this.summary,
    required this.detail,
    required this.metrics,
    required this.feedbackType,
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
      detail: detail,
      metrics: metrics,
      feedbackType: feedbackType,
      waiting: waiting,
      language: language,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
      decoration: BoxDecoration(
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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
                  style: AppText.mono(
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
                style: AppText.mono(
                  size: 8,
                  letterSpacing: 0.8,
                  color: AppColors.stone,
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
              color: expanded ? AppColors.creamMuted : AppColors.cream,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: expanded
                    ? section.accent.withValues(alpha: 0.34)
                    : AppColors.ink.withValues(alpha: 0.10),
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
                            style: AppText.label(
                              size: 14,
                              weight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            section.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.mono(
                              size: 11,
                              weight: FontWeight.w700,
                              color: AppColors.stone,
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
              style: AppText.mono(
                size: 8,
                letterSpacing: 0.8,
                color: AppColors.stone,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: AppText.mono(
                size: 12,
                weight: FontWeight.w700,
                color: AppColors.ink,
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
  required RunTelemetryDetail? detail,
  required RunShareMetrics metrics,
  required String? feedbackType,
  required bool waiting,
  required AppLanguage language,
}) {
  final analytics = detail?.analytics ?? const <String, dynamic>{};
  final displayed = {
    for (final metric in metrics.defaultShareMetrics) metric.id: metric.value,
  };
  final sampleCount =
      _analyticsInt(analytics, 'sampleCount') ??
      summary?.telemetrySampleCount ??
      session.telemetrySamples.length;
  final gpsPointCount =
      _analyticsInt(analytics, 'gpsPointCount') ?? session.gpsPath.length;
  final movingSampleCount = _analyticsInt(analytics, 'movingSampleCount') ?? 0;
  final brakingEvents =
      _analyticsInt(analytics, 'brakingEventCount') ??
      summary?.brakingEventCount ??
      0;
  final accelerationEvents =
      _analyticsInt(analytics, 'accelerationEventCount') ??
      summary?.accelerationEventCount ??
      0;
  final windingSampleCount =
      _analyticsInt(analytics, 'windingSampleCount') ?? 0;
  final windingPct =
      _analyticsDouble(analytics, 'windingSamplePct') ??
      summary?.windingSamplePct ??
      0;
  final routeCompletionPct =
      _analyticsDouble(analytics, 'routeCompletionPct') ??
      summary?.routeCompletionPct?.toDouble();
  final route = session.route;
  final sharpRows = session.sharpCorners.take(6).map((event) {
    return _SessionLogRow(
      _formatClock(event.time),
      _modeLabel(event.driveMode, language),
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
          AppCopy.t(language, ko: '시간', en: 'DURATION', fr: 'DURÉE'),
          session.durationDisplay,
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '평균 속도', en: 'AVG SPEED', fr: 'MOYENNE'),
          displayed['avgSpeed'] ?? '—',
        ),
        if (kDebugMode)
          _SessionLogRow(
            AppCopy.t(
              language,
              ko: 'GPS 포인트',
              en: 'GPS POINTS',
              fr: 'POINTS GPS',
            ),
            '$gpsPointCount',
          ),
        if (kDebugMode)
          _SessionLogRow(
            AppCopy.t(
              language,
              ko: '텔레메트리 샘플',
              en: 'TELEMETRY',
              fr: 'TÉLÉMÉTRIE',
            ),
            '$sampleCount',
          ),
      ],
    ),
    _SessionLogGroup(
      key: 'flow',
      icon: Icons.timeline_rounded,
      title: AppCopy.t(language, ko: '흐름', en: 'Flow', fr: 'Flow'),
      summary: displayed['flow'] == null ? '—' : 'Score ${displayed['flow']}',
      accent: AppColors.primaryContainer,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '흐름 점수', en: 'FLOW SCORE', fr: 'SCORE FLOW'),
          displayed['flow'] ?? '—',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '이동 샘플',
            en: 'MOVING SAMPLES',
            fr: 'ÉCHANT. MOUV.',
          ),
          '$movingSampleCount / $sampleCount',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '이동 시간',
            en: 'MOVING TIME',
            fr: 'TEMPS MOUV.',
          ),
          _formatAnalyticsDuration(analytics, 'movingDurationSeconds'),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '정지 시간', en: 'IDLE TIME', fr: 'ARRÊT'),
          _formatAnalyticsDuration(analytics, 'idleDurationSeconds'),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '와인딩 시간', en: 'WINDING TIME', fr: 'VIRAGE'),
          _formatCompactDuration(session.driveModeSeconds['winding'] ?? 0),
        ),
      ],
    ),
    _SessionLogGroup(
      key: 'smoothness',
      icon: Icons.waves_rounded,
      title: AppCopy.t(language, ko: '스무스니스', en: 'Smoothness', fr: 'Fluidité'),
      summary: displayed['smoothness'] == null
          ? '—'
          : 'Score ${displayed['smoothness']}',
      accent: AppColors.success,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '스무스니스', en: 'SMOOTHNESS', fr: 'FLUIDITÉ'),
          displayed['smoothness'] ?? '—',
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
        _SessionLogRow(
          AppCopy.t(language, ko: '샤프 이벤트', en: 'SHARP EVENTS', fr: 'BRUSQUE'),
          '${_analyticsInt(analytics, 'sharpEventCount') ?? session.sharpCorners.length}',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '종G 흐름',
            en: 'LONG G RANGE',
            fr: 'PLAGE G LONG',
          ),
          _formatG(_analyticsDouble(analytics, 'p95AbsLongitudinalG')),
        ),
      ],
    ),
    _SessionLogGroup(
      key: 'gforce',
      icon: Icons.graphic_eq_rounded,
      title: AppCopy.t(
        language,
        ko: '핸들링 분석',
        en: 'Handling notes',
        fr: 'Notes de tenue',
      ),
      summary: session.sharpCorners.isEmpty
          ? AppCopy.t(
              language,
              ko: '안정된 리듬',
              en: 'Steady rhythm',
              fr: 'Rythme stable',
            )
          : AppCopy.t(
              language,
              ko: '${session.sharpCorners.length}개 코너 이벤트',
              en: '${session.sharpCorners.length} corner events',
              fr: '${session.sharpCorners.length} événements',
            ),
      accent: AppColors.gold,
      rows: [
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '횡G 범위',
            en: 'LAT G RANGE',
            fr: 'PLAGE G LAT',
          ),
          _formatG(
            _analyticsDouble(analytics, 'maxLateralG') ?? session.maxLateralG,
          ),
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '종G 범위',
            en: 'LONG G RANGE',
            fr: 'PLAGE G LONG',
          ),
          _formatG(
            _analyticsDouble(analytics, 'maxLongitudinalG') ?? session.maxLonG,
          ),
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '횡G 평균 범위',
            en: 'LAT G FLOW',
            fr: 'FLUX G LAT',
          ),
          '${_formatG(_analyticsDouble(analytics, 'avgAbsLateralG'))} / '
          '${_formatG(_analyticsDouble(analytics, 'p95AbsLateralG'))}',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '종G 평균 범위',
            en: 'LONG G FLOW',
            fr: 'FLUX G LONG',
          ),
          '${_formatG(_analyticsDouble(analytics, 'avgAbsLongitudinalG'))} / '
          '${_formatG(_analyticsDouble(analytics, 'p95AbsLongitudinalG'))}',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '와인딩 샘플',
            en: 'WINDING SAMPLES',
            fr: 'ÉCHANT. VIRAGE',
          ),
          '$windingSampleCount / $sampleCount · ${windingPct.round()}%',
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
                  ko: '특별한 코너 이벤트가 기록되지 않았습니다.',
                  en: 'No notable corner events were detected.',
                  fr: 'Aucun événement notable détecté.',
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
        ko: '루트 컨텍스트',
        en: 'Route context',
        fr: 'Route',
      ),
      summary: route?.name ?? session.routeName,
      accent: AppColors.success,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '루트', en: 'ROUTE', fr: 'ROUTE'),
          route?.name ?? session.routeName,
        ),
        if (kDebugMode)
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
              : '${route.distanceKm.toStringAsFixed(1)} km · ${routeCompletionPct?.round() ?? 0}%',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '커브 스타일', en: 'CURVE STYLE', fr: 'STYLE'),
          route == null
              ? '—'
              : '${route.curveStyle} · ${route.sharpCurveCount} curves',
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '타이트/미디엄',
            en: 'TIGHT / MEDIUM',
            fr: 'SERRÉ / MOY.',
          ),
          route == null
              ? '—'
              : '${route.tightCurveKm.toStringAsFixed(1)} / ${route.mediumCurveKm.toStringAsFixed(1)} km',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '고도', en: 'ELEVATION', fr: 'ALTITUDE'),
          route == null || route.elevationDelta == 0
              ? '—'
              : '${route.elevationDelta.toStringAsFixed(0)} m',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '연속 와인딩', en: 'CONTINUOUS', fr: 'CONTINU'),
          route == null
              ? '—'
              : '${route.maxContinuousKm.toStringAsFixed(1)} km',
        ),
      ],
    ),
    _SessionLogGroup(
      key: 'weather',
      icon: Icons.cloud_rounded,
      title: AppCopy.t(
        language,
        ko: '날씨/컨텍스트',
        en: 'Weather & context',
        fr: 'Météo / contexte',
      ),
      summary: '${session.weatherEmoji} ${session.tempDisplay}'.trim(),
      accent: AppColors.gold,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '날씨', en: 'WEATHER', fr: 'MÉTÉO'),
          '${session.weatherEmoji} ${session.tempDisplay} · ${session.weatherDesc}',
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '노면', en: 'SURFACE', fr: 'SURFACE'),
          route?.surfaceSummary.isEmpty ?? true ? '—' : route!.surfaceSummary,
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '도로 클래스', en: 'ROAD CLASS', fr: 'CLASSE'),
          route?.roadClassBucket.isEmpty ?? true ? '—' : route!.roadClassBucket,
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '루트 품질', en: 'ROUTE QUALITY', fr: 'QUALITÉ'),
          route?.qualityLabel.isEmpty ?? true ? '—' : route!.qualityLabel,
        ),
      ],
    ),
    if (kDebugMode)
      _SessionLogGroup(
        key: 'quality',
        icon: Icons.sensors_rounded,
        title: AppCopy.t(
          language,
          ko: '수집 품질',
          en: 'Collection quality',
          fr: 'Qualité collecte',
        ),
        summary: '$sampleCount samples · $gpsPointCount GPS',
        accent: AppColors.primaryContainer,
        rows: [
          _SessionLogRow(
            AppCopy.t(language, ko: '샘플', en: 'SAMPLES', fr: 'ÉCHANT.'),
            '$sampleCount',
          ),
          _SessionLogRow(
            AppCopy.t(
              language,
              ko: 'GPS 포인트',
              en: 'GPS POINTS',
              fr: 'POINTS GPS',
            ),
            '$gpsPointCount',
          ),
          _SessionLogRow(
            AppCopy.t(language, ko: '상세 데이터', en: 'DETAIL DATA', fr: 'DÉTAIL'),
            AppCopy.t(
              language,
              ko: detail == null ? '요약만 있음' : '불러옴',
              en: detail == null ? 'Summary only' : 'Loaded',
              fr: detail == null ? 'Résumé seul' : 'Chargé',
            ),
          ),
          _SessionLogRow(
            AppCopy.t(language, ko: '저장 상태', en: 'SAVE STATE', fr: 'ÉTAT'),
            waiting
                ? AppCopy.t(
                    language,
                    ko: '저장 중',
                    en: 'Saving',
                    fr: 'Sauvegarde',
                  )
                : summary == null
                ? AppCopy.t(
                    language,
                    ko: '요약 없음',
                    en: 'No summary',
                    fr: 'Sans résumé',
                  )
                : AppCopy.t(
                    language,
                    ko: '저장 완료',
                    en: 'Saved',
                    fr: 'Sauvegardé',
                  ),
          ),
        ],
      ),
    _SessionLogGroup(
      key: 'privacy',
      icon: Icons.lock_outline_rounded,
      title: AppCopy.t(
        language,
        ko: '프라이버시/공유',
        en: 'Privacy & share',
        fr: 'Confidentialité',
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
      accent: AppColors.success,
      rows: [
        _SessionLogRow(
          AppCopy.t(language, ko: '공개 기본값', en: 'PUBLIC DEFAULT', fr: 'PUBLIC'),
          AppCopy.t(
            language,
            ko: '비공개 속도 데이터 숨김',
            en: 'Private speed data hidden',
            fr: 'Données de vitesse masquées',
          ),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '좌표', en: 'COORDINATES', fr: 'COORD.'),
          AppCopy.t(
            language,
            ko: '원본 좌표 숨김',
            en: 'Raw coordinates hidden',
            fr: 'Coordonnées brutes masquées',
          ),
        ),
        _SessionLogRow(
          AppCopy.t(language, ko: '루트 노드', en: 'ROUTE NODES', fr: 'NOEUDS'),
          AppCopy.t(
            language,
            ko: '루트 노드 숨김',
            en: 'Route nodes hidden',
            fr: 'Nœuds de route masqués',
          ),
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '루트 피드백',
            en: 'ROUTE FEEDBACK',
            fr: 'RETOUR ROUTE',
          ),
          feedbackType == null ? '—' : _feedbackLabel(feedbackType, language),
        ),
        _SessionLogRow(
          AppCopy.t(
            language,
            ko: '공유 지표',
            en: 'SHARE METRICS',
            fr: 'MÉTRIQUES',
          ),
          '${metrics.defaultShareMetrics.length}',
        ),
      ],
    ),
  ];
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
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: item.accent
              ? AppColors.primaryContainer.withValues(alpha: 0.40)
              : AppColors.ink.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            item.label,
            style: AppText.mono(
              size: 9,
              letterSpacing: 1.2,
              color: item.accent ? AppColors.primaryContainer : AppColors.stone,
            ),
          ),
          Text(
            item.value,
            style: AppText.label(
              size: 20,
              weight: FontWeight.w800,
              color: item.accent ? AppColors.primaryContainer : AppColors.ink,
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

String historySummaryLine(RunSummary? summary, AppLanguage language) {
  if (summary == null) {
    return AppCopy.t(
      language,
      ko: '저장되기 전에 세션이 종료되었습니다.',
      en: 'Session ended before it was created.',
      fr: 'La session s’est terminée avant sa création.',
    );
  }
  final date =
      '${summary.date.year}-${summary.date.month.toString().padLeft(2, '0')}-${summary.date.day.toString().padLeft(2, '0')}';
  return '$date · ${summary.distanceKm.toStringAsFixed(1)} km · ${summary.durationDisplay}';
}

DriveDynamicsSummary? _dynamicsSummary(
  RunSession? session,
  RunTelemetryDetail? detail,
) {
  final samples = session?.telemetrySamples ?? detail?.samples ?? const [];
  if (samples.isEmpty) return null;
  return DriveDynamicsTracker.summarizeSamples(samples);
}

String dynamicsSummaryLine(AppLanguage language, DriveDynamicsSummary summary) {
  if (!summary.hasEvents) {
    return AppCopy.t(
      language,
      ko: '부드러운 주행이었어요',
      en: 'Smooth drive',
      fr: 'Conduite fluide',
    );
  }
  final smoothPct = (summary.smoothRatio * 100).round();
  return AppCopy.t(
    language,
    ko: '부드러움 $smoothPct% · 급제동 ${summary.hardBrakeCount}회 · 급조작 ${summary.harshSteerCount}회',
    en: 'Smoothness $smoothPct% · Hard brakes ${summary.hardBrakeCount} · Abrupt steering ${summary.harshSteerCount}',
    fr: 'Fluidité $smoothPct % · Freinages brusques ${summary.hardBrakeCount} · Coups de volant ${summary.harshSteerCount}',
  );
}

int? _analyticsInt(Map<String, dynamic> analytics, String key) {
  final value = analytics[key];
  if (value is! num || !value.isFinite) return null;
  return value.round();
}

double? _analyticsDouble(Map<String, dynamic> analytics, String key) {
  final value = analytics[key];
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

String _formatG(double? value) {
  if (value == null || value == 0) return '—';
  return value.abs().toStringAsFixed(2);
}

String _formatAnalyticsDuration(Map<String, dynamic> analytics, String key) {
  final seconds = _analyticsInt(analytics, key);
  if (seconds == null) return '—';
  return _formatCompactDuration(seconds);
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
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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
            style: AppText.mono(
              size: 9,
              letterSpacing: 1.6,
              color: AppColors.stone,
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
                    style: AppText.mono(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.stone,
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
    'sport' => AppColors.orange,
    'attack' => AppColors.gold,
    'simulation' => AppColors.textHint,
    _ => AppColors.textSecondary,
  };
}

String _modeLabel(String mode, AppLanguage language) {
  return switch (mode) {
    'cruise' => AppCopy.t(language, ko: '크루즈', en: 'Cruise', fr: 'Cruise'),
    'winding' => AppCopy.t(language, ko: '와인딩', en: 'Winding', fr: 'Virage'),
    'sport' => AppCopy.t(language, ko: '스포츠', en: 'Sport', fr: 'Sport'),
    'attack' => AppCopy.t(language, ko: '집중', en: 'Focus', fr: 'Focus'),
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
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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
                  style: AppText.mono(
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
                    color: AppColors.stone,
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
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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
                  style: AppText.label(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.ink,
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
                      : AppColors.creamMuted,
                  side: BorderSide(
                    color: active
                        ? AppColors.primaryContainer
                        : AppColors.ink.withValues(alpha: 0.14),
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
                    color: active ? AppColors.onPrimary : AppColors.stone,
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
            en: 'No drive data was available, so no summary was created.',
            fr: 'Aucune donnée de trajet, aucun résumé créé.',
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
        color: AppColors.creamRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.10)),
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
            const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.label(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(size: 11, color: AppColors.stone),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCheckeredPainter extends CustomPainter {
  final double tileSize;
  final Color lightColor;
  final Color darkColor;

  const _SummaryCheckeredPainter({
    required this.tileSize,
    required this.lightColor,
    required this.darkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()..color = lightColor;
    final paintDark = Paint()..color = darkColor;
    final cols = (size.width / tileSize).ceil() + 1;
    final rows = (size.height / tileSize).ceil() + 1;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(col * tileSize, row * tileSize, tileSize, tileSize),
          isLight ? paintLight : paintDark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SummaryCheckeredPainter old) =>
      old.tileSize != tileSize ||
      old.lightColor != lightColor ||
      old.darkColor != darkColor;
}
