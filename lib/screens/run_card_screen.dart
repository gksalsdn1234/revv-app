// ignore_for_file: unused_element, unused_element_parameter

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../models/revv_route.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import '../services/run_history_service.dart';
import '../services/revv_ai_service.dart';
import '../services/saved_route_service.dart';
import '../services/obd_service.dart';
import '../widgets/corner_brackets.dart';
import '../widgets/revv_ui.dart';
import '../widgets/sprint_toggle.dart';
import '../services/mapbox_service.dart';
import '../services/pr_service.dart';
import 'cruise_screen.dart';
import 'history_screen.dart';
import '../ui/ux_contracts.dart';

// ── Mapbox Static 이미지 URL 생성 ────────────────────────────────
List<LatLng> _samplePath(List<LatLng> pts, int max) {
  if (pts.length <= max) return pts;
  final step = (pts.length - 1) / (max - 1);
  return List.generate(max, (i) => pts[(i * step).round()]);
}

void _encodeInt(StringBuffer buf, int v) {
  var n = v < 0 ? ~(v << 1) : v << 1;
  while (n >= 0x20) {
    buf.writeCharCode(((n & 0x1f) | 0x20) + 63);
    n >>= 5;
  }
  buf.writeCharCode(n + 63);
}

String _encodePolyline(List<LatLng> pts) {
  final buf = StringBuffer();
  int prevLat = 0, prevLng = 0;
  for (final p in pts) {
    final lat = (p.lat * 1e5).round();
    final lng = (p.lng * 1e5).round();
    _encodeInt(buf, lat - prevLat);
    _encodeInt(buf, lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return buf.toString();
}

/// GPS 경로 → Mapbox Static Images URL
/// 경로가 없으면 null 반환
String? _buildMapUrl(List<LatLng>? path) {
  if (path == null || path.length < 2) return null;
  final sampled = _samplePath(path, 50);
  final encoded = Uri.encodeComponent(_encodePolyline(sampled));
  return 'https://api.mapbox.com/styles/v1/mingwoo/cmmk93np3003301rzajll6msm/static/'
      'path-4+e03030($encoded)/auto/600x340@2x'
      '?padding=60&access_token=${MapboxService.accessToken}';
}

String? _buildSessionMapUrl(RunSession? session) {
  if (session == null) return null;
  final gpsUrl = _buildMapUrl(session.gpsPath);
  if (gpsUrl != null) return gpsUrl;

  // GPS 샘플이 너무 적을 때는 선택한 루트 형상을 대신 보여준다.
  final routeNodes = session.route?.nodes;
  if (routeNodes != null && routeNodes.length >= 2) {
    return _buildMapUrl(routeNodes);
  }
  return null;
}

class RunCardScreen extends StatefulWidget {
  final RunSession? session;
  const RunCardScreen({super.key, this.session});

  @override
  State<RunCardScreen> createState() => _RunCardScreenState();
}

class _RunCardScreenState extends State<RunCardScreen> {
  RunSummary? _saved;
  final GlobalKey _summaryKey = GlobalKey();
  bool _sharing = false;
  String? _jarvisAnalysis;
  bool _jarvisLoading = false;
  String? _saveError;
  String? _analysisError;
  bool _detailSheetOpen = false;
  String? _mapUrl;
  NewPrFlags? _prFlags;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 지도 URL 먼저 계산 (네트워크 이미지 사전 캐시 시작)
      final url = _buildSessionMapUrl(widget.session);
      if (url != null && mounted) {
        setState(() => _mapUrl = url);
        precacheImage(NetworkImage(url), context);
      }
      await _saveSession();
      await _runJarvisAnalysis();
    });
  }

  Future<void> _saveSession() async {
    final s = widget.session;
    if (s == null) return;
    try {
      final history = context.read<RunHistoryService>();
      final summary = await history.save(s);
      final detail = RunTelemetryDetail.fromSession(summary.id, s);
      await history.saveDetail(detail);
      if (mounted) {
        setState(() {
          _saved = summary;
          _saveError = null;
        });
      }
      // PR 체크는 보조 기능이다. 실패해도 RunCard 표시를 막지 않는다.
      try {
        final flags = await PrService().checkAndUpdate(s);
        if (mounted && flags.any) setState(() => _prFlags = flags);
      } catch (e) {
        debugPrint('[RunCard] PR check failed: $e');
      }
    } catch (e) {
      debugPrint('[RunCard] save failed: $e');
      if (mounted) {
        setState(() => _saveError = '기록 저장에 실패했어요. 이번 요약은 화면에서만 볼 수 있어요.');
      }
    }
  }

  Future<void> _runJarvisAnalysis() async {
    final s = widget.session;
    if (s == null) return;
    if (mounted) {
      setState(() {
        _jarvisLoading = true;
        _analysisError = null;
      });
    }
    try {
      final obdConnected = context.read<OBDService>().isConnected;
      final result = await RevvAiService().analyzeRun(
        s,
        useHighQuality: obdConnected,
      );
      if (mounted) {
        setState(() {
          _jarvisAnalysis = result;
          _analysisError = null;
        });
      }
    } catch (e) {
      debugPrint('[RunCard] Jarvis analysis failed: $e');
      if (mounted) {
        setState(() => _analysisError = 'AI 분석 연결이 불안정해서 기본 요약을 표시해요.');
      }
    } finally {
      if (mounted) setState(() => _jarvisLoading = false);
    }
  }

  void _openDetailedAnalysis() {
    if (_detailSheetOpen) return;
    final s = widget.session;
    if (s == null) return;
    final obdConnected = context.read<OBDService>().isConnected;
    setState(() => _detailSheetOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _DetailedAnalysisSheet(session: s, obdConnected: obdConnected),
    ).then((_) {
      if (mounted) setState(() => _detailSheetOpen = false);
    });
  }

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final session = widget.session;
      // AI 캡션 + 이미지 캡처 병렬 실행
      final captionFuture = session != null
          ? RevvAiService().generateShareCaption(session)
          : Future.value('REVV — 드라이브 완주 🏁');

      // 지도 이미지 캐시 보장 후 캡처
      if (_mapUrl != null) {
        await precacheImage(NetworkImage(_mapUrl!), context);
      }
      final boundary =
          _summaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/revv_run_card.png');
      await file.writeAsBytes(pngBytes);

      final caption = await captionFuture;
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], text: caption);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 실패: $e'), backgroundColor: AppColors.red),
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
    final s = widget.session;
    final reviewSummary = s != null ? resolveRunReviewSummary(s) : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RunReviewHeader(
                  summary: reviewSummary,
                  routeName: s?.routeName ?? '자유 드라이빙',
                ),
                const SizedBox(height: 16),
                RepaintBoundary(
                  key: _summaryKey,
                  child: _HeroReviewCard(
                    session: s,
                    reviewSummary: reviewSummary,
                    visitCount: visitCount,
                    jarvisAnalysis: _jarvisAnalysis,
                    jarvisLoading: _jarvisLoading,
                    mapUrl: _mapUrl,
                    prFlags: _prFlags,
                  ),
                ),
                if (_saveError != null || _analysisError != null) ...[
                  const SizedBox(height: 12),
                  _RunCardNotice(
                    message: [
                      _saveError,
                      _analysisError,
                    ].whereType<String>().join('\n'),
                  ),
                ],
                const SizedBox(height: 14),
                _QuickStatsSection(session: s, reviewSummary: reviewSummary),
                if (s?.obdSummary?.hasData == true) ...[
                  const SizedBox(height: 14),
                  _SupportSection(
                    title: 'OBD 요약',
                    child: _ObdSection(obd: s!.obdSummary!),
                  ),
                ],
                if (s != null) ...[
                  const SizedBox(height: 14),
                  _SupportSection(
                    title: '주행 맵',
                    child: _GpsMapCard(session: s, mapUrl: _mapUrl),
                  ),
                ],
                const SizedBox(height: 18),
                _ReviewActions(
                  primaryLabel: reviewSummary?.primaryActionLabel ?? '기록 보기',
                  onPrimary: () {
                    if (s?.route != null) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const CruiseScreen()),
                      );
                      return;
                    }
                    HistoryScreen.show(context);
                  },
                  onShare: _shareCard,
                  sharing: _sharing,
                  onDetail: s != null ? _openDetailedAnalysis : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RunReviewHeader extends StatelessWidget {
  final RunReviewSummary? summary;
  final String routeName;

  const _RunReviewHeader({required this.summary, required this.routeName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 주행 요약',
          style: AppText.inter(size: 28, weight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          routeName,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _RunCardNotice extends StatelessWidget {
  final String message;

  const _RunCardNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: const EdgeInsets.all(14),
      color: AppColors.warning.withValues(alpha: 0.08),
      borderOpacity: 0.28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppText.body(
                size: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroReviewCard extends StatelessWidget {
  final RunSession? session;
  final RunReviewSummary? reviewSummary;
  final int? visitCount;
  final String? jarvisAnalysis;
  final bool jarvisLoading;
  final String? mapUrl;
  final NewPrFlags? prFlags;

  const _HeroReviewCard({
    required this.session,
    required this.reviewSummary,
    required this.visitCount,
    required this.jarvisAnalysis,
    required this.jarvisLoading,
    required this.mapUrl,
    required this.prFlags,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;

    return RevvGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prFlags?.any == true) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (prFlags!.newBestTime)
                  const _PrBadge(label: '베스트 타임', icon: Icons.timer_rounded),
                if (prFlags!.newBestG)
                  const _PrBadge(label: '최대 G', icon: Icons.show_chart_rounded),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(
            reviewSummary?.headline ?? '오늘 드라이브를 기록했어요.',
            style: AppText.inter(
              size: 24,
              weight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          if (mapUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 190,
                width: double.infinity,
                child: Image.network(
                  mapUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _noGpsPlaceholder(),
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(height: 190, child: _noGpsPlaceholder()),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (visitCount != null && visitCount! > 1)
                _Pill(label: '$visitCount번째 드라이브'),
              _Pill(label: s?.weatherEmoji ?? '🌤 ${s?.tempDisplay ?? '—'}'),
              _Pill(label: s?.durationDisplay ?? '—'),
              if (s != null && s.sharpCorners.isNotEmpty)
                _Pill(label: '급조작 ${s.sharpCorners.length}회'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            jarvisLoading
                ? 'AI가 오늘 드라이브를 정리하고 있어요.'
                : (jarvisAnalysis ?? '다음 드라이브를 더 즐기기 좋은 흐름이었어요.'),
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatsSection extends StatelessWidget {
  final RunSession? session;
  final RunReviewSummary? reviewSummary;

  const _QuickStatsSection({
    required this.session,
    required this.reviewSummary,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final stats =
        reviewSummary?.topStats ??
        [
          s?.distanceKm.toStringAsFixed(1) ?? '—',
          s?.durationDisplay ?? '—',
          s != null && s.maxSpeedKmh > 0
              ? s.maxSpeedKmh.toStringAsFixed(0)
              : '—',
        ];

    return Row(
      children: [
        Expanded(
          child: _MetricCard(label: 'DISTANCE', value: stats[0], unit: 'km'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(label: 'DURATION', value: stats[1], unit: ''),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(label: 'TOP SPEED', value: stats[2], unit: 'km/h'),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label(size: 10, color: AppColors.textHint),
          ),
          const SizedBox(height: 8),
          Text(value, style: AppText.mono(size: 18, weight: FontWeight.w800)),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              unit,
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return RevvPill(label: label, color: AppColors.textSecondary);
  }
}

class _SupportSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SupportSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ReviewActions extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onShare;
  final bool sharing;
  final VoidCallback? onDetail;

  const _ReviewActions({
    required this.primaryLabel,
    required this.onPrimary,
    required this.onShare,
    required this.sharing,
    this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevvPrimaryButton(label: primaryLabel, onPressed: onPrimary),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: sharing ? null : onShare,
              child: Text(
                sharing ? '공유 중...' : '공유하기',
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ),
            if (onDetail != null)
              TextButton(
                onPressed: onDetail,
                child: Text(
                  '상세 AI 분석',
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── 공통 카드 컨테이너 ─────────────────────────────────────────
Widget _cardShell({required Widget child}) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 24),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
    ),
    child: Stack(
      children: [
        child,
        const Positioned.fill(child: CornerBrackets(padding: 4)),
      ],
    ),
  );
}

// 카드 공통 헤더 (REVV 로고 + 북마크)
class _CardHeader extends StatelessWidget {
  final RunSession? session;
  const _CardHeader({this.session});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

// 카드 공통 섹션 타이틀
Widget _sectionTitle(String text) => Center(
  child: Text(
    text,
    style: GoogleFonts.rajdhani(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: AppColors.gray,
      letterSpacing: 5,
    ),
  ),
);

// ══════════════════════════════════════════════════════════════════
// Card 1 — Summary (기존 런카드)
// ══════════════════════════════════════════════════════════════════
class _SummaryCard extends StatelessWidget {
  final RunSession? session;
  final int? visitCount;
  final String? jarvisAnalysis;
  final bool jarvisLoading;
  final String? mapUrl;
  final NewPrFlags? prFlags;
  const _SummaryCard({
    required this.session,
    this.visitCount,
    this.jarvisAnalysis,
    this.jarvisLoading = false,
    this.mapUrl,
    this.prFlags,
  });

  String _fallbackComment() {
    final s = session;
    if (s == null) return '오늘 드라이브 어땠나요?';
    final km = s.distanceKm;
    final min = s.duration.inMinutes;
    final vc = visitCount;
    if (vc != null && vc >= 2) return '이 코스 $vc번째예요. 갈수록 익숙해지는 느낌 어때요?';
    if (km >= 30) {
      return '${km.toStringAsFixed(1)}km, $min분 — 오늘 꽤 긴 코스였네요. 수고했어요.';
    }
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

    return _cardShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(session: session),
          // ── 지도 썸네일 (Mapbox Static) ──
          if (mapUrl != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 130,
                width: double.infinity,
                child: Image.network(
                  mapUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: AppColors.surface,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                : null,
                            strokeWidth: 1.5,
                            color: AppColors.red,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.surface,
                    child: const Center(
                      child: Icon(
                        Icons.map_outlined,
                        color: AppColors.gray,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _sectionTitle("TODAY'S RUN"),
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
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '$visitCount회차',
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
          // ── PR 배지 ──
          if (prFlags != null && prFlags!.any) ...[
            const SizedBox(height: 10),
            Center(
              child: Wrap(
                spacing: 6,
                children: [
                  if (prFlags!.newBestTime)
                    _PrBadge(label: '최단 시간 신기록', icon: Icons.timer_outlined),
                  if (prFlags!.newBestG)
                    _PrBadge(label: '최고 G 신기록', icon: Icons.speed_rounded),
                ],
              ),
            ),
          ],
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
                  _InfoChip(
                    '⚡ ${s.sharpCorners.length}회',
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ],
            ),
          ),
          if (s != null) ...[
            const SizedBox(height: 14),
            _DrivingStyleBadge(maxLateralG: s.maxLateralG),
          ],
          const SizedBox(height: 14),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
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
              border: Border(left: BorderSide(color: AppColors.red, width: 2)),
            ),
            child: Text(
              jarvisLoading
                  ? '분석 중...'
                  : (jarvisAnalysis ?? _fallbackComment()),
              style: GoogleFonts.rajdhani(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: Colors.white.withValues(
                  alpha: jarvisLoading ? 0.3 : 0.65,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Card 2 — Drive Stats
// ══════════════════════════════════════════════════════════════════
class _StatsCard extends StatelessWidget {
  final RunSession? session;
  const _StatsCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return _cardShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(session: session),
          const SizedBox(height: 16),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _sectionTitle('DRIVE STATS'),
          const SizedBox(height: 16),

          // 2×2 스탯 그리드
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'MAX SPEED',
                  value: s != null ? s.maxSpeedKmh.toStringAsFixed(0) : '—',
                  unit: 'km/h',
                  available: s != null && s.maxSpeedKmh > 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBlock(
                  label: 'AVG SPEED',
                  value: s != null ? s.avgSpeedKmh.toStringAsFixed(0) : '—',
                  unit: 'km/h',
                  available: s != null && s.avgSpeedKmh > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'MAX 횡G',
                  value: s != null ? s.maxLateralG.toStringAsFixed(2) : '—',
                  unit: 'G',
                  available: s != null && s.maxLateralG > 0,
                  accentColor: s != null && s.maxLateralG >= 0.45
                      ? AppColors.red
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBlock(
                  label: 'MAX 종G',
                  value: s != null ? s.maxLonG.toStringAsFixed(2) : '—',
                  unit: 'G',
                  available: s != null && s.maxLonG > 0,
                ),
              ),
            ],
          ),

          // 드라이브 모드 분포 바
          if (s != null && s.driveModeSeconds.isNotEmpty) ...[
            const SizedBox(height: 16),
            _DriveModeBar(driveModeSeconds: s.driveModeSeconds),
          ],

          // OBD 요약 (연결 시만)
          if (s?.obdSummary?.hasData == true) ...[
            const SizedBox(height: 16),
            _ObdSection(obd: s!.obdSummary!),
          ],

          const SizedBox(height: 16),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
        ],
      ),
    );
  }
}

// ── 스탯 블록 ────────────────────────────────────────────────────
class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool available;
  final Color? accentColor;
  const _StatBlock({
    required this.label,
    required this.value,
    required this.unit,
    required this.available,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = available ? (accentColor ?? Colors.white) : AppColors.gray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: available ? 0.2 : 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 9,
              color: AppColors.gray,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                available ? value : '—',
                style: GoogleFonts.orbitron(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: c,
                ),
              ),
              if (available) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    color: AppColors.gray,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── 드라이브 모드 분포 바 ─────────────────────────────────────────
class _DriveModeBar extends StatelessWidget {
  final Map<String, int> driveModeSeconds;
  const _DriveModeBar({required this.driveModeSeconds});

  static const _colors = {
    'cruise': Color(0xFF78909C),
    'winding': Color(0xFF00BCD4),
    'sport': Color(0xFFFFA726),
  };
  static const _labels = {
    'cruise': 'CRUISE',
    'winding': 'WINDING',
    'sport': 'SPORT',
  };

  @override
  Widget build(BuildContext context) {
    final total = driveModeSeconds.values.fold(0, (s, v) => s + v);
    if (total == 0) return const SizedBox.shrink();

    final cruise = driveModeSeconds['cruise'] ?? 0;
    final winding = driveModeSeconds['winding'] ?? 0;
    final sport = driveModeSeconds['sport'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'DRIVE MODE',
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            color: AppColors.gray,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                if (cruise > 0)
                  Expanded(
                    flex: cruise,
                    child: Container(color: _colors['cruise']),
                  ),
                if (winding > 0)
                  Expanded(
                    flex: winding,
                    child: Container(color: _colors['winding']),
                  ),
                if (sport > 0)
                  Expanded(
                    flex: sport,
                    child: Container(color: _colors['sport']),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          children: [
            for (final e in [
              ('cruise', cruise),
              ('winding', winding),
              ('sport', sport),
            ])
              if (e.$2 > 0)
                _ModePct(
                  label: _labels[e.$1]!,
                  pct: e.$2 / total,
                  color: _colors[e.$1]!,
                ),
          ],
        ),
      ],
    );
  }
}

class _ModePct extends StatelessWidget {
  final String label;
  final double pct;
  final Color color;
  const _ModePct({required this.label, required this.pct, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ${(pct * 100).round()}%',
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── OBD 요약 섹션 ────────────────────────────────────────────────
class _ObdSection extends StatelessWidget {
  final OBDRunSummary obd;
  const _ObdSection({required this.obd});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(width: 2, height: 10, color: AppColors.red),
            const SizedBox(width: 6),
            Text(
              'OBD',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                color: AppColors.red,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (obd.maxRpm != null) _ObdChip('MAX RPM', '${obd.maxRpm}'),
            if (obd.avgFuelRateLph != null)
              _ObdChip(
                'AVG 연료',
                '${obd.avgFuelRateLph!.toStringAsFixed(1)} L/h',
              ),
            if (obd.maxCoolantTempC != null)
              _ObdChip('냉각수', '${obd.maxCoolantTempC}°C'),
            if (obd.startFuelLevelPct != null && obd.endFuelLevelPct != null)
              _ObdChip(
                '연료 소모',
                '${(obd.startFuelLevelPct! - obd.endFuelLevelPct!).toStringAsFixed(1)}%',
              ),
          ],
        ),
      ],
    );
  }
}

class _ObdChip extends StatelessWidget {
  final String label;
  final String value;
  const _ObdChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 8,
              color: AppColors.gray,
              letterSpacing: 1,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.orbitron(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Card 3 — GPS Route Map
// ══════════════════════════════════════════════════════════════════
class _GpsMapCard extends StatelessWidget {
  final RunSession? session;
  final String? mapUrl;
  const _GpsMapCard({required this.session, this.mapUrl});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final hasPath = s != null && s.gpsPath.length >= 2;

    return _cardShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(session: session),
          const SizedBox(height: 16),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _sectionTitle('GPS ROUTE'),
          const SizedBox(height: 12),

          // ── 지도 (Mapbox Static, 오프라인 시 CustomPaint fallback) ──
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: mapUrl != null
                  ? Image.network(
                      mapUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, prog) {
                        if (prog == null) return child;
                        return Container(
                          color: AppColors.surface,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.red,
                              value: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded /
                                        prog.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => hasPath
                          ? CustomPaint(
                              painter: _GpsPathPainter(
                                path: s.gpsPath,
                                corners: s.sharpCorners,
                              ),
                            )
                          : _noGpsPlaceholder(),
                    )
                  : hasPath
                  ? CustomPaint(
                      painter: _GpsPathPainter(
                        path: s.gpsPath,
                        corners: s.sharpCorners,
                      ),
                    )
                  : _noGpsPlaceholder(),
            ),
          ),

          // ── 범례 ──
          if (hasPath || mapUrl != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              children: [
                if (hasPath)
                  _MapLegend(color: const Color(0xFF4CAF50), label: '출발'),
                _MapLegend(color: AppColors.red, label: '경로'),
                if (s != null && s.sharpCorners.isNotEmpty)
                  _MapLegend(
                    color: const Color(0xFFF59E0B),
                    label: '급조작 ${s.sharpCorners.length}곳',
                  ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: AppColors.red.withValues(alpha: 0.2)),
        ],
      ),
    );
  }
}

Widget _noGpsPlaceholder() => Container(
  color: AppColors.surface,
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.location_off_outlined, color: AppColors.gray, size: 28),
      const SizedBox(height: 6),
      Text(
        'GPS 경로 없음',
        style: GoogleFonts.rajdhani(fontSize: 12, color: AppColors.gray),
      ),
    ],
  ),
);

// ── PR(신기록) 배지 ────────────────────────────────────────────────
class _PrBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PrBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFFD700).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFFFFD700)),
        const SizedBox(width: 5),
        Text(
          '🏆  $label',
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFD700),
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

class _MapLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MapLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── GPS 경로 CustomPainter ────────────────────────────────────────
// GPS 좌표를 캔버스에 맞게 정규화해서 그림
// y-flip: 위도 증가 = 화면 위 방향 (스크린 y는 아래 증가)
class _GpsPathPainter extends CustomPainter {
  final List<LatLng> path;
  final List<SharpCorner> corners;
  const _GpsPathPainter({required this.path, required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) {
      if (path.length == 1) {
        canvas.drawCircle(
          Offset(size.width / 2, size.height / 2),
          4,
          Paint()..color = Colors.lightBlueAccent,
        );
      }
      return;
    }

    // 바운딩 박스
    double minLat = path.first.lat, maxLat = path.first.lat;
    double minLng = path.first.lng, maxLng = path.first.lng;
    for (final p in path) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    if (latRange < 1e-9 && lngRange < 1e-9) return;

    const pad = 20.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    // 비율 유지 스케일
    final scaleX = lngRange > 1e-9 ? w / lngRange : double.infinity;
    final scaleY = latRange > 1e-9 ? h / latRange : double.infinity;
    final scale = math.min(scaleX, scaleY);

    final drawW = lngRange > 1e-9 ? lngRange * scale : 0.0;
    final drawH = latRange > 1e-9 ? latRange * scale : 0.0;
    final offX = pad + (w - drawW) / 2;
    final offY = pad + (h - drawH) / 2;

    Offset toOffset(LatLng p) => Offset(
      offX + (p.lng - minLng) * scale,
      size.height - (offY + (p.lat - minLat) * scale), // y-flip
    );

    // 경로 선
    final pathObj = Path()
      ..moveTo(toOffset(path.first).dx, toOffset(path.first).dy);
    for (final p in path.skip(1)) {
      pathObj.lineTo(toOffset(p).dx, toOffset(p).dy);
    }
    canvas.drawPath(
      pathObj,
      Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.85)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 급코너 점 (주황)
    final cornerPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.85);
    for (final c in corners) {
      canvas.drawCircle(toOffset(c.position), 3.5, cornerPaint);
    }

    // 출발점 (초록), 도착점 (빨강) — 급코너 위에 그려 가시성 확보
    canvas.drawCircle(
      toOffset(path.first),
      5.5,
      Paint()..color = const Color(0xFF4CAF50),
    );
    canvas.drawCircle(toOffset(path.last), 5.5, Paint()..color = AppColors.red);
  }

  @override
  bool shouldRepaint(_GpsPathPainter old) =>
      old.path != path || old.corners != corners;
}

// ── 페이지 인디케이터 ─────────────────────────────────────────────
class _PageDots extends StatelessWidget {
  final int current;
  final int total;
  const _PageDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: active ? AppColors.red : Colors.white24,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 공통 서브 위젯
// ══════════════════════════════════════════════════════════════════
class _InfoChip extends StatelessWidget {
  final String text;
  final Color? color;
  const _InfoChip(this.text, {this.color});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.rajdhani(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: color ?? Colors.white.withValues(alpha: 0.6),
    ),
  );
}

class _ChipDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 14,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: Colors.white.withValues(alpha: 0.15),
  );
}

// ══════════════════════════════════════════════════════════════════
// 드라이빙 스타일 배지
// ══════════════════════════════════════════════════════════════════
class _DrivingStyleBadge extends StatelessWidget {
  final double maxLateralG;
  const _DrivingStyleBadge({required this.maxLateralG});

  ({String label, String emoji, String desc, Color color}) _style() {
    if (maxLateralG <= 0.0) {
      return (
        label: 'DATA PENDING',
        emoji: '📡',
        desc: 'IMU 데이터 없음',
        color: const Color(0xFF6B7280),
      );
    } else if (maxLateralG < 0.25) {
      return (
        label: 'CRUISER',
        emoji: '🌊',
        desc: '부드럽고 여유있는 드라이빙',
        color: const Color(0xFF60A5FA),
      );
    } else if (maxLateralG < 0.45) {
      return (
        label: 'SPORT',
        emoji: '⚡',
        desc: '활기차고 다이나믹한 드라이빙',
        color: const Color(0xFFF59E0B),
      );
    } else {
      return (
        label: 'RACER',
        emoji: '🔥',
        desc: '한계를 즐기는 퍼포먼스 드라이빙',
        color: const Color(0xFFEF4444),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: s.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: s.color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DRIVING STYLE',
                      style: GoogleFonts.orbitron(
                        fontSize: 7,
                        fontWeight: FontWeight.w600,
                        color: s.color.withValues(alpha: 0.7),
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
                          color: s.color.withValues(alpha: 0.6),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.label,
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: s.color,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  s.desc,
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

// ══════════════════════════════════════════════════════════════════
// 하단 버튼 바
// ══════════════════════════════════════════════════════════════════
class _BottomButtons extends StatelessWidget {
  final VoidCallback onShare;
  final bool sharing;
  final VoidCallback? onDetail;
  const _BottomButtons({
    required this.onShare,
    required this.sharing,
    this.onDetail,
  });

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
          if (onDetail != null) ...[
            RedGlowButton(label: '🤖 상세 AI 분석', filled: false, onTap: onDetail),
            const SizedBox(height: 10),
          ],
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
  final bool obdConnected;
  const _DetailedAnalysisSheet({
    required this.session,
    this.obdConnected = false,
  });

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
    try {
      final result = await RevvAiService().analyzeRunDetailed(
        widget.session,
        useHighQuality: widget.obdConnected,
      );
      if (mounted) {
        setState(() {
          _report = result;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[RunCard] detailed analysis failed: $e');
      if (mounted) {
        setState(() {
          _report = '상세 AI 분석 연결이 불안정해요. 기본 요약과 주행 기록은 정상적으로 볼 수 있습니다.';
          _loading = false;
        });
      }
    }
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
            width: 36,
            height: 4,
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
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 드라이빙 코치',
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      widget.session.routeName,
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 18, 22, pad.bottom + 24),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                          color: AppColors.red,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : Text(
                      _report ?? '분석 데이터를 불러올 수 없어요.',
                      style: GoogleFonts.rajdhani(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
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
