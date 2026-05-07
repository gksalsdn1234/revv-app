import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/route_feedback.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/run_telemetry_detail.dart';
import '../services/run_history_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

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

  @override
  void initState() {
    super.initState();
    _saveFuture = _save();
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<RunSummary?>(
            future: _saveFuture,
            builder: (context, snapshot) {
              final summary = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RUN SAVED',
                    style: AppText.technicalLabel(
                      size: 12,
                      letterSpacing: 3,
                      color: AppColors.primaryContainer,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    session == null ? '저장할 주행이 없어요' : '주행 기록 저장 완료',
                    style: AppText.display(
                      size: 42,
                      height: 0.96,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session == null
                        ? '세션이 만들어지기 전에 종료됐습니다. 홈으로 돌아가 다시 시작해 주세요.'
                        : '목록은 가볍게, 텔레메트리 상세는 별도로 저장했습니다.',
                    style: AppText.body(
                      size: 14,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (session != null)
                    _SummaryGrid(
                      items: [
                        _SummaryItem(
                          label: '거리',
                          value: '${session.distanceKm.toStringAsFixed(2)} km',
                        ),
                        _SummaryItem(
                          label: '시간',
                          value: session.durationDisplay,
                        ),
                        _SummaryItem(
                          label: '평균',
                          value:
                              '${session.avgSpeedKmh.toStringAsFixed(0)} km/h',
                        ),
                        _SummaryItem(
                          label: '최고 G',
                          value: session.maxLateralG.toStringAsFixed(2),
                        ),
                      ],
                    ),
                  if (session != null) ...[
                    const SizedBox(height: 16),
                    _RouteFeedbackCard(
                      enabled: summary != null,
                      selected: _selectedFeedback,
                      saved: _feedbackSaved,
                      onSelected: summary == null
                          ? null
                          : (type) => _saveFeedback(summary, type),
                    ),
                  ],
                  const Spacer(),
                  _SaveStateCard(
                    summary: summary,
                    waiting: snapshot.connectionState != ConnectionState.done,
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
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home_rounded),
                      label: Text(
                        '홈으로',
                        style: AppText.body(
                          size: 17,
                          weight: FontWeight.w900,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});
}

class _SummaryGrid extends StatelessWidget {
  final List<_SummaryItem> items;

  const _SummaryGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.45,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.panel.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.label,
                    style: AppText.technicalLabel(
                      size: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                  Text(
                    item.value,
                    style: AppText.body(
                      size: 22,
                      weight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FeedbackOption {
  final String type;
  final String label;
  final IconData icon;

  const _FeedbackOption({
    required this.type,
    required this.label,
    required this.icon,
  });
}

const _feedbackOptions = [
  _FeedbackOption(
    type: 'liked',
    label: '좋았음',
    icon: Icons.thumb_up_alt_rounded,
  ),
  _FeedbackOption(type: 'not_for_me', label: '별로', icon: Icons.tune_rounded),
  _FeedbackOption(
    type: 'unsafe_or_closed',
    label: '위험/폐쇄',
    icon: Icons.warning_amber_rounded,
  ),
  _FeedbackOption(
    type: 'hide_route',
    label: '다시 추천 안 함',
    icon: Icons.visibility_off_rounded,
  ),
];

class _RouteFeedbackCard extends StatelessWidget {
  final bool enabled;
  final String? selected;
  final bool saved;
  final ValueChanged<String>? onSelected;

  const _RouteFeedbackCard({
    required this.enabled,
    required this.selected,
    required this.saved,
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
                  saved ? '피드백 저장됨' : '이 루트 어땠나요?',
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
                  option.label,
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

class _SaveStateCard extends StatelessWidget {
  final RunSummary? summary;
  final bool waiting;

  const _SaveStateCard({required this.summary, required this.waiting});

  @override
  Widget build(BuildContext context) {
    final label = waiting
        ? '저장 중'
        : summary == null
        ? '세션 없음'
        : '로컬 저장 완료';
    final saved = summary;
    final detail = saved == null
        ? '주행 데이터가 없어서 기록을 만들지 않았습니다.'
        : '${saved.routeName} · 클라우드는 가능할 때 백그라운드 업로드';
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
