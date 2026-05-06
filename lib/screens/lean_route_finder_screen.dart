import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/map_widget.dart';
import 'lean_drive_screen.dart';

class LeanRouteFinderScreen extends StatefulWidget {
  const LeanRouteFinderScreen({super.key});

  @override
  State<LeanRouteFinderScreen> createState() => _LeanRouteFinderScreenState();
}

class _LeanRouteFinderScreenState extends State<LeanRouteFinderScreen> {
  int _selectedIndex = 0;
  int _recenterSignal = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_searchHere());
  }

  Future<void> _searchHere() async {
    final location = context.read<LocationService>();
    await location.requestPermission();
    await location.startTracking();
    final point = await location.ensureLiveLocation();
    if (!mounted || point == null) return;
    final settings = context.read<SettingsService>();
    final routes = context.read<RouteService>();
    routes.searchRadiusKm = settings.searchRadiusKm;
    await routes.fetchRoutes(point.lat, point.lng);
    if (!mounted) return;
    setState(() => _selectedIndex = 0);
    final first = routes.routes.isNotEmpty ? routes.routes.first : null;
    if (first != null) routes.selectRoute(first);
  }

  void _selectIndex(int nextIndex) {
    final routes = context.read<RouteService>().routes;
    if (routes.isEmpty) return;
    final clamped = nextIndex.clamp(0, routes.length - 1);
    setState(() => _selectedIndex = clamped);
    context.read<RouteService>().selectRoute(routes[clamped]);
  }

  void _startDrive(RevvRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeanDriveScreen(route: route)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RouteService>();
    final routes = service.routes;
    final selected = routes.isEmpty
        ? null
        : routes[_selectedIndex.clamp(0, routes.length - 1)];
    final status = service.isLoading
        ? '루트 찾는 중'
        : service.errorMessage ?? service.backgroundStatusMessage;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              routePolyline: selected?.nodes,
              routeFocusMode: selected != null,
              recenterSignal: _recenterSignal,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _LeanRouteTopBar(
                count: routes.length,
                busy: service.isLoading,
                onBack: () => Navigator.pop(context),
                onSearch: _searchHere,
                onRecenter: () => setState(() => _recenterSignal++),
              ),
            ),
          ),
          if (status != null && status.isNotEmpty)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 78,
              left: 24,
              right: 24,
              child: _LeanToast(message: status, busy: service.isLoading),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: MediaQuery.paddingOf(context).bottom + 14,
            child: selected == null
                ? _LeanEmptyTicket(onSearch: _searchHere)
                : _LeanRouteTicket(
                    route: selected,
                    index: _selectedIndex,
                    total: routes.length,
                    onPrev: _selectedIndex > 0
                        ? () => _selectIndex(_selectedIndex - 1)
                        : null,
                    onNext: _selectedIndex < routes.length - 1
                        ? () => _selectIndex(_selectedIndex + 1)
                        : null,
                    onGo: () => _startDrive(selected),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LeanRouteTopBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onRecenter;

  const _LeanRouteTopBar({
    required this.count,
    required this.busy,
    required this.onBack,
    required this.onSearch,
    required this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    return _LeanGlass(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _LeanCircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy ? '루트 탐색 중' : '루트 $count',
              style: AppText.body(
                size: 16,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _LeanTextButton(
            label: '여기서 찾기',
            icon: Icons.my_location_rounded,
            onTap: busy ? null : onSearch,
          ),
          const SizedBox(width: 6),
          _LeanCircleButton(icon: Icons.gps_fixed_rounded, onTap: onRecenter),
        ],
      ),
    );
  }
}

class _LeanRouteTicket extends StatelessWidget {
  final RevvRoute route;
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onGo;

  const _LeanRouteTicket({
    required this.route,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    return _LeanGlass(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LeanCircleButton(
                icon: Icons.chevron_left_rounded,
                onTap: onPrev,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1} / $total · ${_routeTypeLabel(route)}',
                      style: AppText.technicalLabel(
                        size: 10,
                        color: AppColors.primaryContainer,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 18,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LeanCircleButton(
                icon: Icons.chevron_right_rounded,
                onTap: onNext,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(label: '거리', value: route.distanceDisplay),
              const SizedBox(width: 8),
              _Metric(label: '예상', value: route.durationDisplay),
              const SizedBox(width: 8),
              _Metric(label: '커브', value: '${route.sharpCurveCount}'),
              const Spacer(),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onGo,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    '주행 시작',
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w900,
                      color: AppColors.onPrimary,
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
}

class _LeanEmptyTicket extends StatelessWidget {
  final VoidCallback onSearch;

  const _LeanEmptyTicket({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return _LeanGlass(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(
            Icons.route_outlined,
            color: AppColors.primaryContainer,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '지도에서 루트를 불러오지 못했어요.',
              style: AppText.body(
                size: 14,
                weight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _LeanTextButton(
            label: '다시 찾기',
            icon: Icons.refresh_rounded,
            onTap: onSearch,
          ),
        ],
      ),
    );
  }
}

class _LeanToast extends StatelessWidget {
  final String message;
  final bool busy;

  const _LeanToast({required this.message, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _LeanGlass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.primaryContainer,
                ),
              )
            else
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.primaryContainer,
                size: 16,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: AppText.body(
          size: 11,
          weight: FontWeight.w900,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _LeanCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _LeanCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: onTap == null ? AppColors.textHint : AppColors.textPrimary,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _LeanTextButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _LeanTextButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryContainer,
        textStyle: AppText.body(size: 12, weight: FontWeight.w900),
      ),
    );
  }
}

class _LeanGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _LeanGlass({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

String _routeTypeLabel(RevvRoute route) {
  if (route.isLoop) return '루프';
  if (route.maxContinuousKm >= 2.5) return '흐름';
  if (route.curveStyle == 'SWEEPER') return '스위퍼';
  if (route.curveStyle == 'SWITCHBACK') return '타이트';
  return '와인딩';
}
