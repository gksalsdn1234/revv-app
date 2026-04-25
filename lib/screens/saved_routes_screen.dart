import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/run_history_service.dart';
import '../services/saved_route_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/ux_contracts.dart';
import 'history_screen.dart';
import 'route_detail_screen.dart';
import 'route_edit_screen.dart';
import 'route_preview_screen.dart';

enum _SavedSortMode { recent, quality, distance }
enum _SavedFilterMode { all, ridden, unridden }

class SavedRoutesScreen extends StatefulWidget {
  const SavedRoutesScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedRoutesScreen()),
    );
  }

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  _SavedSortMode _sortMode = _SavedSortMode.recent;
  _SavedFilterMode _filterMode = _SavedFilterMode.all;
  String _query = '';

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
            const _SavedBackdrop(),
            SafeArea(
              bottom: false,
              child: Consumer2<SavedRouteService, RunHistoryService>(
                builder: (context, saved, history, _) {
                  final routes = _visibleRoutes(saved.routes, history);
                  final featured = routes.isNotEmpty ? routes.first : null;
                  final list = featured == null ? routes : routes.skip(1).toList();

                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: _SavedTopBar(
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                          child: _SavedTabBar(
                            onHistory: () {
                              Navigator.pop(context);
                              HistoryScreen.show(context);
                            },
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                          child: _SavedSectionHeader(
                            count: routes.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: _SavedControlPanel(
                            query: _query,
                            sortMode: _sortMode,
                            filterMode: _filterMode,
                            onQueryChanged: (value) => setState(() => _query = value),
                            onSortChanged: (value) => setState(() => _sortMode = value),
                            onFilterChanged: (value) => setState(() => _filterMode = value),
                          ),
                        ),
                      ),
                      if (routes.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _SavedEmptyState(),
                        )
                      else ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final wide = constraints.maxWidth >= 760;
                                final featuredCard = _SavedFeaturedCard(
                                  route: featured!,
                                  visitCount: history.visitCount(featured.id),
                                  lastRun: _lastRunForRoute(history, featured.id),
                                  onShare: () => _shareRoute(featured),
                                  onPreview: () => _openPreview(context, featured),
                                  onStart: () => _startRoute(context, featured),
                                );
                                final summaryCard = _SavedSummaryCard(
                                  routes: routes,
                                  history: history,
                                );

                                if (!wide) {
                                  return Column(
                                    children: [
                                      featuredCard,
                                      const SizedBox(height: 14),
                                      summaryCard,
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 8, child: featuredCard),
                                    const SizedBox(width: 14),
                                    Expanded(flex: 4, child: summaryCard),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
                            child: const _SavedSubHeader(),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
                          sliver: SliverList.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final route = list[index];
                              return _SavedRouteRowCard(
                                route: route,
                                visitCount: history.visitCount(route.id),
                                lastRun: _lastRunForRoute(history, route.id),
                                onTap: () => _openDetail(context, route),
                                onFavoriteToggle: () => context.read<SavedRouteService>().toggle(route),
                                onStart: () => _startRoute(context, route),
                              );
                            },
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

  List<RevvRoute> _sortRoutes(List<RevvRoute> input, RunHistoryService history) {
    final routes = List<RevvRoute>.from(input);
    switch (_sortMode) {
      case _SavedSortMode.recent:
        return routes;
      case _SavedSortMode.quality:
        routes.sort((a, b) => b.routeRankScore.compareTo(a.routeRankScore));
        return routes;
      case _SavedSortMode.distance:
        routes.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        return routes;
    }
  }

  List<RevvRoute> _visibleRoutes(List<RevvRoute> input, RunHistoryService history) {
    final keyword = _query.trim().toLowerCase();
    final filtered = input.where((route) {
      final matchesQuery = keyword.isEmpty ||
          route.name.toLowerCase().contains(keyword) ||
          (route.primaryReason ?? '').toLowerCase().contains(keyword);
      final visitCount = history.visitCount(route.id);
      final matchesFilter = switch (_filterMode) {
        _SavedFilterMode.all => true,
        _SavedFilterMode.ridden => visitCount > 0,
        _SavedFilterMode.unridden => visitCount == 0,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    return _sortRoutes(filtered, history);
  }

  static DateTime? _lastRunForRoute(RunHistoryService history, String routeId) {
    for (final run in history.history) {
      if (run.routeId == routeId) return run.date;
    }
    return null;
  }

  Future<void> _openEdit(BuildContext context, RevvRoute route) async {
    final svc = context.read<RouteService>();
    final result = await Navigator.push<RouteEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditScreen(
          route: route,
          otherRoutes: svc.routes.where((r) => r.id != route.id).toList(),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    svc.selectRoute(result.route);
    final branch = result.branchRoute;
    if (branch != null) svc.addManualChain(branch);
  }

  void _openPreview(BuildContext context, RevvRoute route) {
    context.read<RouteService>().selectRoute(route);
    context.read<RouteService>().clearCompositeRoute();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoutePreviewScreen(route: route)),
    );
  }

  void _openDetail(BuildContext context, RevvRoute route) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SavedRouteDetailSheet(
        route: route,
        visitCount: context.read<RunHistoryService>().visitCount(route.id),
        lastRun: _lastRunForRoute(context.read<RunHistoryService>(), route.id),
        onPreview: () {
          Navigator.pop(context);
          _openPreview(context, route);
        },
        onEdit: () async {
          Navigator.pop(context);
          await _openEdit(context, route);
        },
        onDetail: () {
          Navigator.pop(context);
          context.read<RouteService>().selectRoute(route);
          context.read<RouteService>().clearCompositeRoute();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RouteDetailScreen(routeId: route.id)),
          );
        },
        onStart: () {
          Navigator.pop(context);
          _startRoute(context, route);
        },
        onShare: () => _shareRoute(route),
      ),
    );
  }

  void _startRoute(BuildContext context, RevvRoute route) {
    context.read<RouteService>().selectRoute(route);
    context.read<RouteService>().clearCompositeRoute();
    context.read<RouteService>().requestSprint(route: route);
    Navigator.pop(context);
  }

  Future<void> _shareRoute(RevvRoute route) {
    final text = StringBuffer()
      ..writeln('REVV 저장 루트')
      ..writeln(route.name)
      ..writeln('${route.distanceDisplay} · ${route.durationDisplay}')
      ..writeln(describeRouteCharacter(route.routeCharacter))
      ..writeln(route.primaryReason ?? '다시 달리기 좋은 저장 루트예요.');
    return Share.share(text.toString().trim());
  }
}

class _SavedBackdrop extends StatelessWidget {
  const _SavedBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryContainer.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -80,
            bottom: 100,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.warning.withValues(alpha: 0.06),
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

class _SavedTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _SavedTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SavedTopBarIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
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
                style: AppText.body(
                  size: 18,
                  weight: FontWeight.w900,
                  color: AppColors.primaryContainer,
                  letterSpacing: 3.0,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Saved',
          style: AppText.body(
            size: 18,
            weight: FontWeight.w800,
            color: AppColors.primaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.bookmark_rounded,
          size: 22,
          color: AppColors.primaryContainer,
        ),
      ],
    );
  }
}

class _SavedTopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SavedTopBarIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
      ),
    );
  }
}

class _SavedTabBar extends StatelessWidget {
  final VoidCallback onHistory;

  const _SavedTabBar({required this.onHistory});

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
            child: InkWell(
              onTap: onHistory,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  'Drive History',
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.textHint,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
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
                'Saved Routes',
                style: AppText.body(
                  size: 13,
                  weight: FontWeight.w900,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSectionHeader extends StatelessWidget {
  final int count;

  const _SavedSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Library'.toUpperCase(),
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.primaryContainer,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Saved Routes',
              style: AppText.body(
                size: 26,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
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
        ),
      ],
    );
  }
}

class _SavedControlPanel extends StatelessWidget {
  final String query;
  final _SavedSortMode sortMode;
  final _SavedFilterMode filterMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_SavedSortMode> onSortChanged;
  final ValueChanged<_SavedFilterMode> onFilterChanged;

  const _SavedControlPanel({
    required this.query,
    required this.sortMode,
    required this.filterMode,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.onFilterChanged,
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
          TextField(
            controller: controller,
            onChanged: onQueryChanged,
            style: AppText.body(
              size: 14,
              weight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '루트 이름이나 추천 이유로 검색',
              hintStyle: AppText.body(size: 14, color: AppColors.textHint),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textHint,
                size: 18,
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
                borderSide: const BorderSide(color: AppColors.primaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ArchiveChip(
                label: '최근 저장',
                active: sortMode == _SavedSortMode.recent,
                onTap: () => onSortChanged(_SavedSortMode.recent),
              ),
              _ArchiveChip(
                label: '추천순',
                active: sortMode == _SavedSortMode.quality,
                onTap: () => onSortChanged(_SavedSortMode.quality),
              ),
              _ArchiveChip(
                label: '짧은 순',
                active: sortMode == _SavedSortMode.distance,
                onTap: () => onSortChanged(_SavedSortMode.distance),
              ),
              _ArchiveChip(
                label: '전체',
                active: filterMode == _SavedFilterMode.all,
                onTap: () => onFilterChanged(_SavedFilterMode.all),
              ),
              _ArchiveChip(
                label: '주행함',
                active: filterMode == _SavedFilterMode.ridden,
                onTap: () => onFilterChanged(_SavedFilterMode.ridden),
              ),
              _ArchiveChip(
                label: '미주행',
                active: filterMode == _SavedFilterMode.unridden,
                onTap: () => onFilterChanged(_SavedFilterMode.unridden),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchiveChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ArchiveChip({
    required this.label,
    required this.active,
    required this.onTap,
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
              color: active ? AppColors.onPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedFeaturedCard extends StatelessWidget {
  final RevvRoute route;
  final int visitCount;
  final DateTime? lastRun;
  final VoidCallback onShare;
  final VoidCallback onPreview;
  final VoidCallback onStart;

  const _SavedFeaturedCard({
    required this.route,
    required this.visitCount,
    required this.lastRun,
    required this.onShare,
    required this.onPreview,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final characterLabel = describeRouteCharacter(
      route.routeCharacter.isNotEmpty ? route.routeCharacter : 'mixed_touring',
    );
    final qualityLabel = describeRouteQuality(
      route.qualityLabel.isNotEmpty ? route.qualityLabel : 'keep',
    );

    return Container(
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
                    AppColors.surface.withValues(alpha: 0.62),
                    AppColors.surfaceLowest.withValues(alpha: 0.96),
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  route.isLoop ? Icons.loop_rounded : Icons.alt_route_rounded,
                  size: 108,
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
                  stops: const [0.0, 0.44, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                _CircleActionButton(icon: Icons.ios_share_rounded, onTap: onShare),
                const SizedBox(width: 8),
                _CircleActionButton(icon: Icons.visibility_rounded, onTap: onPreview),
              ],
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
                    _SavedBadge(label: qualityLabel, color: AppColors.primaryContainer),
                    _SavedBadge(label: characterLabel, color: AppColors.warning),
                    if (route.isLoop)
                      const _SavedBadge(label: 'LOOP', color: AppColors.primaryContainer),
                    if (lastRun != null)
                      _SavedBadge(
                        label: _lastRunLabel(lastRun!),
                        color: AppColors.textHint,
                        outlined: true,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  route.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 24,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  route.primaryReason ?? '다시 꺼내 달리기 좋은 저장 루트예요.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _FeaturedMetricPanel(
                        value: route.distanceKm.toStringAsFixed(0),
                        unit: 'KM',
                        label: 'Distance',
                        accent: AppColors.primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _FeaturedMetricPanel(
                        value: route.durationDisplay,
                        label: 'Duration',
                        accent: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _FeaturedMetricPanel(
                        value: visitCount.toString(),
                        unit: 'RUN',
                        label: 'Visits',
                        accent: AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      '이 루트로 바로 달리기',
                      style: AppText.body(size: 14, weight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _lastRunLabel(DateTime date) => '최근 ${date.month}/${date.day}';
}

class _SavedBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  const _SavedBadge({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: outlined ? AppColors.panel.withValues(alpha: 0.72) : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: outlined ? AppColors.outlineVariant.withValues(alpha: 0.24) : color.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: AppText.technicalLabel(
          size: 9,
          color: outlined ? AppColors.textHint : color,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: 0.82),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.24),
            ),
          ),
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _FeaturedMetricPanel extends StatelessWidget {
  final String value;
  final String label;
  final String unit;
  final Color accent;

  const _FeaturedMetricPanel({
    required this.value,
    required this.label,
    this.unit = '',
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: value,
              style: AppText.mono(
                size: 22,
                weight: FontWeight.w900,
                color: accent,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: AppText.technicalLabel(
                      size: 8,
                      color: AppColors.textHint,
                      letterSpacing: 1.0,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            label.toUpperCase(),
            style: AppText.technicalLabel(
              size: 8,
              color: AppColors.textHint,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSummaryCard extends StatelessWidget {
  final List<RevvRoute> routes;
  final RunHistoryService history;

  const _SavedSummaryCard({
    required this.routes,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final ridden = routes.where((route) => history.visitCount(route.id) > 0).length;
    final avgDistance = routes.isEmpty
        ? 0.0
        : routes.fold<double>(0, (sum, route) => sum + route.distanceKm) / routes.length;
    final loops = routes.where((route) => route.isLoop).length;

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
            'Library Metrics'.toUpperCase(),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.textHint,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          _SummaryRow(label: 'Saved Count', value: '${routes.length}개'),
          const SizedBox(height: 18),
          _SummaryRow(label: 'Driven Before', value: '$ridden개'),
          const SizedBox(height: 18),
          _SummaryRow(
            label: 'Avg Distance',
            value: '${avgDistance.toStringAsFixed(1)} KM',
            accent: AppColors.primaryContainer,
          ),
          const SizedBox(height: 18),
          _SummaryRow(
            label: 'Loop Routes',
            value: '$loops개',
            accent: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.accent,
  });

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

class _SavedSubHeader extends StatelessWidget {
  const _SavedSubHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saved Feed'.toUpperCase(),
          style: AppText.technicalLabel(
            size: 10,
            color: AppColors.textHint,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ready To Reuse',
          style: AppText.body(
            size: 20,
            weight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SavedRouteRowCard extends StatelessWidget {
  final RevvRoute route;
  final int visitCount;
  final DateTime? lastRun;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onStart;

  const _SavedRouteRowCard({
    required this.route,
    required this.visitCount,
    required this.lastRun,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final characterLabel = describeRouteCharacter(
      route.routeCharacter.isNotEmpty ? route.routeCharacter : 'mixed_touring',
    );

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
                        route.isLoop ? Icons.loop_rounded : Icons.route_rounded,
                        size: 28,
                        color: AppColors.primaryContainer.withValues(alpha: 0.55),
                      ),
                    ),
                    if (route.isLoop)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.panel2.withValues(alpha: 0.84),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'LOOP',
                            style: AppText.technicalLabel(
                              size: 8,
                              color: AppColors.warning,
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
                            route.name,
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
                          lastRun == null ? '미주행' : '최근 ${lastRun!.month}/${lastRun!.day}',
                          style: AppText.technicalLabel(
                            size: 9,
                            color: AppColors.textHint,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      route.primaryReason ?? '다시 꺼내 달리기 좋은 저장 루트예요.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _InlineStat(icon: Icons.route_rounded, label: route.distanceDisplay),
                        _InlineStat(icon: Icons.timer_outlined, label: route.durationDisplay),
                        _InlineStat(icon: Icons.waves_rounded, label: characterLabel),
                        _InlineStat(icon: Icons.history_rounded, label: '$visitCount회'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  _MiniCircleButton(
                    icon: Icons.favorite_rounded,
                    color: AppColors.primaryContainer,
                    onTap: onFavoriteToggle,
                  ),
                  const SizedBox(height: 8),
                  _MiniCircleButton(
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.warning,
                    onTap: onStart,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InlineStat({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textHint),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.body(
            size: 12,
            weight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _MiniCircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MiniCircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
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
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.24),
            ),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _SavedRouteDetailSheet extends StatelessWidget {
  final RevvRoute route;
  final int visitCount;
  final DateTime? lastRun;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onDetail;
  final VoidCallback onStart;
  final VoidCallback onShare;

  const _SavedRouteDetailSheet({
    required this.route,
    required this.visitCount,
    required this.lastRun,
    required this.onPreview,
    required this.onEdit,
    required this.onDetail,
    required this.onStart,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final qualityLabel = describeRouteQuality(
      route.qualityLabel.isNotEmpty ? route.qualityLabel : 'keep',
    );
    final characterLabel = describeRouteCharacter(
      route.routeCharacter.isNotEmpty ? route.routeCharacter : 'mixed_touring',
    );

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
                            'Saved Route'.toUpperCase(),
                            style: AppText.technicalLabel(
                              size: 10,
                              color: AppColors.primaryContainer,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            route.name,
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
                    _SavedBadge(label: qualityLabel, color: AppColors.primaryContainer),
                    _SavedBadge(label: characterLabel, color: AppColors.warning),
                    if (route.isLoop)
                      const _SavedBadge(label: 'LOOP', color: AppColors.primaryContainer),
                    if (lastRun != null)
                      _SavedBadge(
                        label: '최근 ${lastRun!.month}/${lastRun!.day}',
                        color: AppColors.textHint,
                        outlined: true,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _SheetMetricCard(
                        label: '거리',
                        value: route.distanceKm.toStringAsFixed(0),
                        unit: 'KM',
                        accent: AppColors.primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SheetMetricCard(
                        label: '예상 시간',
                        value: route.durationDisplay,
                        accent: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SheetMetricCard(
                        label: '주행 횟수',
                        value: '$visitCount',
                        unit: 'RUN',
                        accent: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SheetMetricCard(
                        label: '거리감',
                        value: route.distanceFromUserDisplay,
                        accent: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
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
                        '리뷰'.toUpperCase(),
                        style: AppText.technicalLabel(
                          size: 10,
                          color: AppColors.primaryContainer,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        route.primaryReason ?? '다시 꺼내 달리기 좋은 저장 루트예요.',
                        style: AppText.body(
                          size: 14,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if ((route.cautionNote ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          route.cautionNote!,
                          style: AppText.body(
                            size: 12,
                            height: 1.4,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onPreview,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.outlineVariant.withValues(alpha: 0.3),
                          ),
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('지도에서 보기'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.outlineVariant.withValues(alpha: 0.3),
                          ),
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('편집'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDetail,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.outlineVariant.withValues(alpha: 0.3),
                          ),
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('자세히'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onShare,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.outlineVariant.withValues(alpha: 0.3),
                          ),
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('공유'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      '이 루트로 달리기',
                      style: AppText.body(size: 14, weight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color accent;

  const _SheetMetricCard({
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
                size: 22,
                weight: FontWeight.w900,
                color: accent,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: AppText.technicalLabel(
                      size: 8,
                      color: AppColors.textHint,
                      letterSpacing: 1.0,
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

class _SavedEmptyState extends StatelessWidget {
  const _SavedEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 52,
              color: AppColors.primaryContainer.withValues(alpha: 0.24),
            ),
            const SizedBox(height: 18),
            Text(
              'Saved library is empty',
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Routes 화면에서 마음에 드는 루트를 저장해두면 여기서 바로 다시 보고 달릴 수 있어요.',
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
