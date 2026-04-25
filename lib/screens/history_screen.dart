import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/run_summary.dart';
import '../services/run_history_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'saved_routes_screen.dart';

enum _HistoryFilterMode { all, thisMonth, longRun, highG }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static void show(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _showSearch = false;
  bool _showFilters = false;
  String _query = '';
  _HistoryFilterMode _filterMode = _HistoryFilterMode.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cockpitBackgroundGradient(),
        ),
        child: Stack(
          children: [
            const _ArchiveBackdrop(),
            SafeArea(
              bottom: false,
              child: Consumer<RunHistoryService>(
                builder: (context, history, _) {
                  final allRuns = history.history;
                  if (allRuns.isEmpty) {
                    return const _EmptyArchiveState();
                  }

                  final runs = _visibleRuns(allRuns);
                  final hasControls =
                      _showSearch ||
                      _showFilters ||
                      _query.trim().isNotEmpty ||
                      _filterMode != _HistoryFilterMode.all;
                  final hasResults = runs.isNotEmpty;
                  final featured = hasResults ? runs.first : allRuns.first;
                  final recent = hasResults
                      ? runs.skip(1).take(6).toList()
                      : <RunSummary>[];
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: _ArchiveTopBar(
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                          child: _ArchiveTabBar(
                            onSavedRoutes: () =>
                                SavedRoutesScreen.show(context),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                          child: _ArchiveSectionHeader(
                            totalRuns: runs.length,
                            filterActive:
                                _showFilters ||
                                _filterMode != _HistoryFilterMode.all,
                            searchActive:
                                _showSearch || _query.trim().isNotEmpty,
                            onFilterTap: () {
                              setState(() => _showFilters = !_showFilters);
                            },
                            onSearchTap: () {
                              setState(() => _showSearch = !_showSearch);
                            },
                          ),
                        ),
                      ),
                      if (hasControls)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: _HistoryControlPanel(
                              showSearch: _showSearch,
                              showFilters: _showFilters,
                              query: _query,
                              filterMode: _filterMode,
                              onQueryChanged: (value) {
                                setState(() => _query = value);
                              },
                              onFilterChanged: (mode) {
                                setState(() => _filterMode = mode);
                              },
                              onClear: () {
                                setState(() {
                                  _query = '';
                                  _filterMode = _HistoryFilterMode.all;
                                  _showSearch = false;
                                  _showFilters = false;
                                });
                              },
                            ),
                          ),
                        ),
                      if (!hasResults)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _FilteredArchiveEmptyState(),
                        )
                      else ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              hasControls ? 14 : 16,
                              20,
                              0,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final wide = constraints.maxWidth >= 760;
                                final featuredCard = _FeaturedRunCard(
                                  run: featured,
                                  visitCount: history.visitCount(
                                    featured.routeId,
                                  ),
                                  onTap: () => _showRunDetailsSheet(
                                    context,
                                    run: featured,
                                    visitCount: history.visitCount(
                                      featured.routeId,
                                    ),
                                  ),
                                );
                                final metricsCard = _DriveMetricsCard(
                                  runs: runs,
                                  totalDistanceKm: _totalDistanceKm(runs),
                                );

                                if (!wide) {
                                  return Column(
                                    children: [
                                      featuredCard,
                                      const SizedBox(height: 14),
                                      metricsCard,
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 8, child: featuredCard),
                                    const SizedBox(width: 14),
                                    Expanded(flex: 4, child: metricsCard),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
                            child: const _ArchiveSubHeader(),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
                          sliver: SliverList.separated(
                            itemBuilder: (context, index) {
                              final run = recent[index];
                              return _HistoryRowCard(
                                run: run,
                                visitCount: history.visitCount(run.routeId),
                                onTap: () => _showRunDetailsSheet(
                                  context,
                                  run: run,
                                  visitCount: history.visitCount(run.routeId),
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemCount: recent.length,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<RunSummary> _visibleRuns(List<RunSummary> runs) {
    final keyword = _query.trim().toLowerCase();
    final now = DateTime.now();
    return runs.where((run) {
      final matchesQuery =
          keyword.isEmpty ||
          run.routeName.toLowerCase().contains(keyword) ||
          run.weatherEmoji.toLowerCase().contains(keyword) ||
          run.tempDisplay.toLowerCase().contains(keyword);
      final matchesFilter = switch (_filterMode) {
        _HistoryFilterMode.all => true,
        _HistoryFilterMode.thisMonth =>
          run.date.year == now.year && run.date.month == now.month,
        _HistoryFilterMode.longRun => run.distanceKm >= 20,
        _HistoryFilterMode.highG => (run.maxLateralG ?? 0) >= 0.8,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  double _totalDistanceKm(List<RunSummary> runs) {
    return runs.fold(0, (sum, run) => sum + run.distanceKm);
  }
}

class _ArchiveBackdrop extends StatelessWidget {
  const _ArchiveBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryContainer.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: 120,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.warning.withValues(alpha: 0.08),
                    Colors.transparent,
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

class _ArchiveTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _ArchiveTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TopBarIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 20,
                color: AppColors.primaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'REVV',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryContainer,
                  letterSpacing: 3.2,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Archive',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.battery_charging_full_rounded,
          size: 22,
          color: AppColors.primaryContainer,
        ),
      ],
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.panel2.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}

class _ArchiveTabBar extends StatelessWidget {
  final VoidCallback onSavedRoutes;

  const _ArchiveTabBar({required this.onSavedRoutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryContainer.withValues(alpha: 0.18),
                    blurRadius: 16,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Drive History',
                style: AppText.body(
                  size: 13,
                  weight: FontWeight.w900,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: onSavedRoutes,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  'Saved Routes',
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.textHint,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveSectionHeader extends StatelessWidget {
  final int totalRuns;
  final bool filterActive;
  final bool searchActive;
  final VoidCallback onFilterTap;
  final VoidCallback onSearchTap;

  const _ArchiveSectionHeader({
    required this.totalRuns,
    required this.filterActive,
    required this.searchActive,
    required this.onFilterTap,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Logs'.toUpperCase(),
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.primaryContainer,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Recent Runs',
              style: AppText.body(
                size: 26,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const Spacer(),
        _CircleGhostButton(
          icon: Icons.filter_list_rounded,
          active: filterActive,
          onTap: onFilterTap,
        ),
        const SizedBox(width: 8),
        _CircleGhostButton(
          icon: Icons.search_rounded,
          active: searchActive,
          onTap: onSearchTap,
        ),
        if (totalRuns > 0) ...[
          const SizedBox(width: 8),
          _CircleCountBadge(count: totalRuns),
        ],
      ],
    );
  }
}

class _CircleGhostButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _CircleGhostButton({
    required this.icon,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryContainer
                : AppColors.panel2.withValues(alpha: 0.82),
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? AppColors.primaryContainer
                  : AppColors.outlineVariant.withValues(alpha: 0.26),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? AppColors.onPrimary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

class _CircleCountBadge extends StatelessWidget {
  final int count;

  const _CircleCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: AppColors.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: AppText.body(
          size: 13,
          weight: FontWeight.w900,
          color: AppColors.onPrimary,
        ),
      ),
    );
  }
}

class _HistoryControlPanel extends StatelessWidget {
  final bool showSearch;
  final bool showFilters;
  final String query;
  final _HistoryFilterMode filterMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_HistoryFilterMode> onFilterChanged;
  final VoidCallback onClear;

  const _HistoryControlPanel({
    required this.showSearch,
    required this.showFilters,
    required this.query,
    required this.filterMode,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: query)
      ..selection = TextSelection.collapsed(offset: query.length);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel2.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSearch || query.trim().isNotEmpty) ...[
            TextField(
              controller: controller,
              onChanged: onQueryChanged,
              style: AppText.body(
                size: 14,
                weight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '루트명, 날씨, 온도로 기록 검색',
                hintStyle: AppText.body(size: 14, color: AppColors.textHint),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textHint,
                  size: 18,
                ),
                suffixIcon: query.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => onQueryChanged(''),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textHint,
                          size: 18,
                        ),
                      ),
                filled: true,
                fillColor: AppColors.surfaceHigh.withValues(alpha: 0.68),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: AppColors.outlineVariant.withValues(alpha: 0.22),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: AppColors.primaryContainer,
                  ),
                ),
              ),
            ),
            if (showFilters || filterMode != _HistoryFilterMode.all)
              const SizedBox(height: 14),
          ],
          if (showFilters || filterMode != _HistoryFilterMode.all)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HistoryFilterChip(
                  label: '전체',
                  active: filterMode == _HistoryFilterMode.all,
                  onTap: () => onFilterChanged(_HistoryFilterMode.all),
                ),
                _HistoryFilterChip(
                  label: '이번 달',
                  active: filterMode == _HistoryFilterMode.thisMonth,
                  onTap: () => onFilterChanged(_HistoryFilterMode.thisMonth),
                ),
                _HistoryFilterChip(
                  label: '긴 주행',
                  active: filterMode == _HistoryFilterMode.longRun,
                  onTap: () => onFilterChanged(_HistoryFilterMode.longRun),
                ),
                _HistoryFilterChip(
                  label: '강한 G',
                  active: filterMode == _HistoryFilterMode.highG,
                  onTap: () => onFilterChanged(_HistoryFilterMode.highG),
                ),
                if (query.trim().isNotEmpty ||
                    filterMode != _HistoryFilterMode.all)
                  _HistoryFilterChip(
                    label: '초기화',
                    active: false,
                    onTap: onClear,
                    muted: true,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HistoryFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool muted;
  final VoidCallback onTap;

  const _HistoryFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryContainer
                : AppColors.surfaceHigh.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? AppColors.primaryContainer
                  : AppColors.outlineVariant.withValues(alpha: 0.24),
            ),
          ),
          child: Text(
            label,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w800,
              color: active
                  ? AppColors.onPrimary
                  : muted
                  ? AppColors.warning
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedRunCard extends StatelessWidget {
  final RunSummary run;
  final int visitCount;
  final VoidCallback? onTap;

  const _FeaturedRunCard({
    required this.run,
    required this.visitCount,
    this.onTap,
  });

  String get _dateLabel {
    final d = run.date;
    return '${_monthName(d.month)} ${d.day}, ${d.year} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final avgSpeed = run.durationSeconds > 0
        ? run.distanceKm / (run.durationSeconds / 3600)
        : 0.0;
    final gText = run.maxLateralG != null && run.maxLateralG! > 0
        ? run.maxLateralG!.toStringAsFixed(2)
        : '—';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.panel2.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.18),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              SizedBox(
                height: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.surface.withValues(alpha: 0.60),
                        AppColors.surfaceLowest.withValues(alpha: 0.96),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.route_rounded,
                      size: 110,
                      color: AppColors.primaryContainer.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        AppColors.surfaceLowest.withValues(alpha: 0.92),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FeaturedBadge(
                          label: visitCount >= 2
                              ? 'Favorite Return'
                              : 'Recent Peak',
                          color: AppColors.primaryContainer,
                        ),
                        _FeaturedBadge(
                          label: _dateLabel,
                          color: AppColors.textHint,
                          outlined: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      run.routeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 24,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${run.distanceKm.toStringAsFixed(1)} KM • ${run.durationDisplay}',
                      style: AppText.body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _FeaturedMetric(
                            value: avgSpeed.toStringAsFixed(0),
                            label: 'Avg KM/H',
                            accent: AppColors.primaryContainer,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _FeaturedMetric(
                            value: gText,
                            label: 'Max G',
                            accent: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  const _FeaturedBadge({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: outlined
            ? AppColors.panel.withValues(alpha: 0.72)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: outlined
              ? AppColors.outlineVariant.withValues(alpha: 0.24)
              : color.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: AppText.technicalLabel(
          size: 9,
          color: outlined ? AppColors.textHint : color,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _FeaturedMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color accent;

  const _FeaturedMetric({
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: AppText.mono(
              size: 26,
              weight: FontWeight.w900,
              color: accent,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: AppText.technicalLabel(
              size: 8,
              color: AppColors.textHint,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveMetricsCard extends StatelessWidget {
  final List<RunSummary> runs;
  final double totalDistanceKm;

  const _DriveMetricsCard({required this.runs, required this.totalDistanceKm});

  @override
  Widget build(BuildContext context) {
    final totalSeconds = runs.fold<int>(
      0,
      (sum, run) => sum + run.durationSeconds,
    );
    final totalHours = totalSeconds ~/ 3600;
    final totalMinutes = (totalSeconds % 3600) ~/ 60;
    final avgG = _averageG(runs);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Drive Metrics'.toUpperCase(),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.textHint,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          _MetricRow(
            label: 'Total Distance',
            value: '${totalDistanceKm.toStringAsFixed(1)} KM',
          ),
          const SizedBox(height: 18),
          _MetricRow(
            label: 'Active Time',
            value: '${totalHours}h ${totalMinutes.toString().padLeft(2, '0')}m',
          ),
          const SizedBox(height: 18),
          _MetricRow(
            label: 'Avg. Lateral G',
            value: avgG == null ? '—' : avgG.toStringAsFixed(2),
            accent: AppColors.primaryContainer,
          ),
          const SizedBox(height: 22),
          Container(
            height: 1,
            color: AppColors.outlineVariant.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primaryContainer.withValues(alpha: 0.34),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Download Full Log'.toUpperCase(),
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.primaryContainer,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _averageG(List<RunSummary> runs) {
    final values = runs
        .where((run) => run.maxLateralG != null && run.maxLateralG! > 0)
        .map((run) => run.maxLateralG!)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _MetricRow({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppText.body(
            size: 13,
            weight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppText.mono(
            size: 17,
            weight: FontWeight.w800,
            color: accent ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ArchiveSubHeader extends StatelessWidget {
  const _ArchiveSubHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Runs'.toUpperCase(),
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.textHint,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Archive Feed',
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryRowCard extends StatelessWidget {
  final RunSummary run;
  final int visitCount;
  final VoidCallback? onTap;

  const _HistoryRowCard({
    required this.run,
    required this.visitCount,
    this.onTap,
  });

  String get _dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final runDay = DateTime(run.date.year, run.date.month, run.date.day);
    final diff = today.difference(runDay).inDays;
    if (diff == 0) {
      return 'Today • ${run.date.hour.toString().padLeft(2, '0')}:${run.date.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) {
      return 'Yesterday • ${run.date.hour.toString().padLeft(2, '0')}:${run.date.minute.toString().padLeft(2, '0')}';
    }
    return '${_monthName(run.date.month)} ${run.date.day} • ${run.date.hour.toString().padLeft(2, '0')}:${run.date.minute.toString().padLeft(2, '0')}';
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final avgSpeed = run.durationSeconds > 0
        ? run.distanceKm / (run.durationSeconds / 3600)
        : 0.0;
    final gValue = run.maxLateralG ?? 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 92,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.route_rounded,
                        size: 28,
                        color: AppColors.primaryContainer.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                    if (visitCount >= 2)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.panel2.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$visitCount회차',
                            style: AppText.technicalLabel(
                              size: 8,
                              color: AppColors.primaryContainer,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            run.routeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(
                              size: 17,
                              weight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dateLabel,
                          style: AppText.technicalLabel(
                            size: 9,
                            color: AppColors.textHint,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _InlineMetric(
                          icon: Icons.speed_rounded,
                          value: avgSpeed.toStringAsFixed(0),
                          unit: 'KM/H',
                          color: AppColors.textSecondary,
                        ),
                        _InlineMetric(
                          icon: Icons.timer_outlined,
                          value: run.durationDisplay,
                          unit: '',
                          color: AppColors.textSecondary,
                        ),
                        _InlineMetric(
                          icon: Icons.show_chart_rounded,
                          value: gValue > 0 ? gValue.toStringAsFixed(2) : '—',
                          unit: gValue > 0 ? 'G' : '',
                          color: gValue >= 0.8
                              ? AppColors.warning
                              : AppColors.primaryContainer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final Color color;

  const _InlineMetric({
    required this.icon,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          value,
          style: AppText.mono(
            size: 12,
            weight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (unit.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(
            unit,
            style: AppText.technicalLabel(
              size: 8,
              color: color,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyArchiveState extends StatelessWidget {
  const _EmptyArchiveState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_outlined,
              size: 52,
              color: AppColors.primaryContainer.withValues(alpha: 0.24),
            ),
            const SizedBox(height: 18),
            Text(
              'Archive is empty',
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '첫 드라이브를 마치면 최근 주행 기록과 요약 메트릭이 여기에 쌓여요.',
              textAlign: TextAlign.center,
              style: AppText.body(
                size: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilteredArchiveEmptyState extends StatelessWidget {
  const _FilteredArchiveEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 52,
              color: AppColors.primaryContainer.withValues(alpha: 0.24),
            ),
            const SizedBox(height: 18),
            Text(
              '조건에 맞는 기록이 없어요',
              textAlign: TextAlign.center,
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '검색어를 지우거나 필터를 전체로 바꾸면 다른 주행 기록을 다시 볼 수 있어요.',
              textAlign: TextAlign.center,
              style: AppText.body(
                size: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showRunDetailsSheet(
  BuildContext context, {
  required RunSummary run,
  required int visitCount,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RunDetailSheet(run: run, visitCount: visitCount),
  );
}

class _RunDetailSheet extends StatelessWidget {
  final RunSummary run;
  final int visitCount;

  const _RunDetailSheet({required this.run, required this.visitCount});

  @override
  Widget build(BuildContext context) {
    final avgSpeed = run.durationSeconds > 0
        ? run.distanceKm / (run.durationSeconds / 3600)
        : 0.0;
    final gValue = run.maxLateralG ?? 0.0;
    final topInset = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, topInset + 18, 14, 14),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          decoration: BoxDecoration(
            color: AppColors.panel2.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.24),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outline.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Run Detail'.toUpperCase(),
                            style: AppText.technicalLabel(
                              size: 10,
                              color: AppColors.primaryContainer,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            run.routeName,
                            style: AppText.body(
                              size: 24,
                              weight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FeaturedBadge(
                      label: _runDateLabel(run.date),
                      color: AppColors.textHint,
                      outlined: true,
                    ),
                    if (visitCount >= 2)
                      _FeaturedBadge(
                        label: '$visitCount번째 주행',
                        color: AppColors.primaryContainer,
                      ),
                    if (run.weatherEmoji.isNotEmpty ||
                        run.tempDisplay.isNotEmpty)
                      _FeaturedBadge(
                        label:
                            '${run.weatherEmoji.isEmpty ? '날씨 기록' : run.weatherEmoji} ${run.tempDisplay}'
                                .trim(),
                        color: AppColors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MetricPanel(
                        label: '거리',
                        value: run.distanceKm.toStringAsFixed(1),
                        unit: 'KM',
                        accent: AppColors.primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricPanel(
                        label: '시간',
                        value: run.durationDisplay,
                        accent: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MetricPanel(
                        label: '평균 속도',
                        value: avgSpeed.toStringAsFixed(0),
                        unit: 'KM/H',
                        accent: AppColors.primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricPanel(
                        label: '최대 횡G',
                        value: gValue > 0 ? gValue.toStringAsFixed(2) : '—',
                        unit: gValue > 0 ? 'G' : '',
                        accent: gValue >= 0.8
                            ? AppColors.warning
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _RunNoteCard(title: '리뷰', body: _runInsight(run)),
                if (run.sharpCornersCount > 0) ...[
                  const SizedBox(height: 10),
                  _RunNoteCard(
                    title: '급조작 기록',
                    body:
                        '강한 횡가속 구간이 ${run.sharpCornersCount}회 기록됐어요. 코너 진입과 탈출 흐름이 인상적이었던 주행이에요.',
                  ),
                ],
                if (run.startPoint != null || run.endPoint != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.panel.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '기록 좌표'.toUpperCase(),
                          style: AppText.technicalLabel(
                            size: 10,
                            color: AppColors.textHint,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (run.startPoint != null)
                          _CoordinateRow(
                            label: '시작',
                            value:
                                '${run.startPoint!.lat.toStringAsFixed(5)}, ${run.startPoint!.lng.toStringAsFixed(5)}',
                          ),
                        if (run.startPoint != null && run.endPoint != null)
                          const SizedBox(height: 8),
                        if (run.endPoint != null)
                          _CoordinateRow(
                            label: '종료',
                            value:
                                '${run.endPoint!.lat.toStringAsFixed(5)}, ${run.endPoint!.lng.toStringAsFixed(5)}',
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _runInsight(RunSummary run) {
    if (run.maxLateralG != null && run.maxLateralG! >= 0.9) {
      return '코너링 하중이 또렷하게 기록된 세션이에요. 짧아도 강한 리듬감이 남는 주행으로 보여요.';
    }
    if (run.distanceKm >= 25) {
      return '주행 시간이 길고 거리도 충분해서, 흐름을 유지하며 달린 장거리 세션에 가까워요.';
    }
    if (run.sharpCornersCount >= 4) {
      return '짧은 거리 안에 방향 전환이 자주 있었어요. 타이트한 구간을 집중해서 탄 기록으로 보여요.';
    }
    return '부담 없이 다시 꺼내보기 좋은 기록이에요. 다음 비교 주행의 기준 로그로 쓰기 좋아요.';
  }

  String _runDateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _MetricPanel extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color accent;

  const _MetricPanel({
    required this.label,
    required this.value,
    this.unit = '',
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.textHint,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              text: value,
              style: AppText.mono(
                size: 24,
                weight: FontWeight.w900,
                color: accent,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: AppText.technicalLabel(
                      size: 10,
                      color: AppColors.textHint,
                      letterSpacing: 1.2,
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

class _RunNoteCard extends StatelessWidget {
  final String title;
  final String body;

  const _RunNoteCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.primaryContainer,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppText.body(
              size: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateRow extends StatelessWidget {
  final String label;
  final String value;

  const _CoordinateRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: AppText.body(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: AppText.mono(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
