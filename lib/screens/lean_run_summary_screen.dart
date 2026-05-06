import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
