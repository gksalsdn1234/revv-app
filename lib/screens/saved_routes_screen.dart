import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/run_history_service.dart';
import '../services/saved_route_service.dart';
import '../theme/colors.dart';
import '../ui/ux_contracts.dart';
import 'route_detail_screen.dart';

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
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: Text(
          'SAVED ROUTES',
          style: GoogleFonts.orbitron(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: Consumer2<SavedRouteService, RunHistoryService>(
        builder: (context, saved, history, _) {
          final routes = _visibleRoutes(saved.routes, history);
          if (routes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '아직 저장한 루트가 없어요.\nRoutes에서 마음에 드는 코스를 저장해두면 여기서 다시 꺼내볼 수 있어요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    height: 1.4,
                    color: Colors.white70,
                  ),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SavedHeader(
                count: routes.length,
                sortMode: _sortMode,
                filterMode: _filterMode,
                query: _query,
                onChanged: (mode) => setState(() => _sortMode = mode),
                onFilterChanged: (mode) => setState(() => _filterMode = mode),
                onQueryChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              ...routes.map(
                (route) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SavedRouteCard(
                    route: route,
                    visitCount: history.visitCount(route.id),
                    lastRun: _lastRunForRoute(history, route.id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<RevvRoute> _sortRoutes(
    List<RevvRoute> input,
    RunHistoryService history,
  ) {
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

  List<RevvRoute> _visibleRoutes(
    List<RevvRoute> input,
    RunHistoryService history,
  ) {
    final filtered = input.where((route) {
      final matchesQuery =
          _query.trim().isEmpty ||
          route.name.toLowerCase().contains(_query.trim().toLowerCase()) ||
          (route.primaryReason ?? '').toLowerCase().contains(
            _query.trim().toLowerCase(),
          );
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

  DateTime? _lastRunForRoute(RunHistoryService history, String routeId) {
    for (final run in history.history) {
      if (run.routeId == routeId) return run.date;
    }
    return null;
  }
}

class _SavedHeader extends StatelessWidget {
  final int count;
  final _SavedSortMode sortMode;
  final _SavedFilterMode filterMode;
  final String query;
  final ValueChanged<_SavedSortMode> onChanged;
  final ValueChanged<_SavedFilterMode> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  const _SavedHeader({
    required this.count,
    required this.sortMode,
    required this.filterMode,
    required this.query,
    required this.onChanged,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count개 저장됨',
                      style: GoogleFonts.rajdhani(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '커뮤니티 피드 없이, 다시 열어보기 쉬운 내 루트 라이브러리예요.',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: TextEditingController(text: query)
              ..selection = TextSelection.collapsed(offset: query.length),
            onChanged: onQueryChanged,
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: '루트 이름이나 추천 이유로 검색',
              hintStyle: GoogleFonts.rajdhani(
                fontSize: 14,
                color: Colors.white38,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white54,
                size: 18,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.red),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SortChip(
                label: '최근 저장',
                active: sortMode == _SavedSortMode.recent,
                onTap: () => onChanged(_SavedSortMode.recent),
              ),
              _SortChip(
                label: '추천순',
                active: sortMode == _SavedSortMode.quality,
                onTap: () => onChanged(_SavedSortMode.quality),
              ),
              _SortChip(
                label: '짧은 순',
                active: sortMode == _SavedSortMode.distance,
                onTap: () => onChanged(_SavedSortMode.distance),
              ),
              _SortChip(
                label: '전체',
                active: filterMode == _SavedFilterMode.all,
                onTap: () => onFilterChanged(_SavedFilterMode.all),
              ),
              _SortChip(
                label: '주행한 루트',
                active: filterMode == _SavedFilterMode.ridden,
                onTap: () => onFilterChanged(_SavedFilterMode.ridden),
              ),
              _SortChip(
                label: '아직 안 탄 루트',
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

class _SortChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppColors.red.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.red : Colors.white12),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SavedRouteCard extends StatelessWidget {
  final RevvRoute route;
  final int visitCount;
  final DateTime? lastRun;

  const _SavedRouteCard({
    required this.route,
    required this.visitCount,
    required this.lastRun,
  });

  @override
  Widget build(BuildContext context) {
    final qualityLabel = describeRouteQuality(
      route.qualityLabel.isNotEmpty ? route.qualityLabel : 'keep',
    );
    final characterLabel = describeRouteCharacter(
      route.routeCharacter.isNotEmpty ? route.routeCharacter : 'mixed_touring',
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    context.read<SavedRouteService>().toggle(route),
                icon: const Icon(Icons.favorite_rounded, color: AppColors.red),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            route.primaryReason ?? '다시 달리기 좋은 저장 루트예요.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              height: 1.3,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SavedChip(label: qualityLabel),
              _SavedChip(label: characterLabel),
              _SavedChip(label: route.distanceDisplay),
              _SavedChip(label: route.durationDisplay),
              _SavedChip(label: '$visitCount회 주행'),
              if (lastRun != null) _SavedChip(label: _dateLabel(lastRun!)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    context.read<RouteService>().selectRoute(route);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RouteDetailScreen(routeId: route.id),
                      ),
                    );
                  },
                  child: Text(
                    '자세히 보기',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                  ),
                  onPressed: () {
                    context.read<RouteService>().selectRoute(route);
                    context.read<RouteService>().requestSprint(route: route);
                    Navigator.pop(context);
                  },
                  child: Text(
                    '바로 달리기',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime date) {
    return '최근 ${date.month}/${date.day}';
  }
}

class _SavedChip extends StatelessWidget {
  final String label;

  const _SavedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
