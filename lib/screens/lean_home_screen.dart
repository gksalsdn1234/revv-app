import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/run_history_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'lean_route_finder_screen.dart';

class LeanHomeScreen extends StatefulWidget {
  const LeanHomeScreen({super.key});

  @override
  State<LeanHomeScreen> createState() => _LeanHomeScreenState();
}

class _LeanHomeScreenState extends State<LeanHomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_primeLocation());
  }

  Future<void> _primeLocation() async {
    final location = context.read<LocationService>();
    await location.requestPermission();
    await location.startTracking();
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationService>();
    final routes = context.watch<RouteService>();
    final history = context.watch<RunHistoryService>();
    final settings = context.watch<SettingsService>();
    final supabase = context.watch<SupabaseService>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'REVV',
                    style: AppText.technicalLabel(
                      size: 16,
                      letterSpacing: 6,
                      color: AppColors.primaryContainer,
                    ),
                  ),
                  const Spacer(),
                  _LeanStatusDot(
                    active: supabase.isCloudAvailable,
                    label: supabase.isCloudAvailable ? 'CLOUD' : 'LOCAL',
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '루트 찾고\n바로 달리기',
                style: AppText.display(
                  size: 48,
                  height: 0.92,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '필수 주행 플로우만 남긴 lean MVP입니다. 지도, 루트 선택, 주행, 저장만 확인합니다.',
                style: AppText.body(
                  size: 15,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              _LeanPrimaryButton(
                label: '루트 찾기',
                icon: Icons.travel_explore_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LeanRouteFinderScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              _LeanStatusGrid(
                items: [
                  _LeanStatusItem(
                    label: '위치',
                    value: location.hasPermission ? '준비됨' : '권한 필요',
                    active: location.hasPermission,
                  ),
                  _LeanStatusItem(
                    label: '루트',
                    value: routes.routes.isEmpty
                        ? '대기'
                        : '${routes.routes.length}개',
                    active: routes.routes.isNotEmpty,
                  ),
                  _LeanStatusItem(
                    label: '기록',
                    value: '${history.totalRuns}회',
                    active: history.totalRuns > 0,
                  ),
                  _LeanStatusItem(
                    label: '음성',
                    value: settings.ttsMuted ? '꺼짐' : '켜짐',
                    active: !settings.ttsMuted,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _LeanGhostButton(
                      label: '위치 다시 확인',
                      icon: Icons.my_location_rounded,
                      onTap: _primeLocation,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LeanGhostButton(
                      label: settings.ttsMuted ? '음성 켜기' : '음성 끄기',
                      icon: settings.ttsMuted
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      onTap: () => settings.setTtsMuted(!settings.ttsMuted),
                    ),
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

class _LeanStatusDot extends StatelessWidget {
  final bool active;
  final String label;

  const _LeanStatusDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: AppText.technicalLabel(size: 10, color: color)),
        ],
      ),
    );
  }
}

class _LeanPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LeanPrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 66,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(
          label,
          style: AppText.body(
            size: 18,
            weight: FontWeight.w900,
            color: AppColors.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _LeanGhostButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LeanGhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(
          color: AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: AppText.body(size: 13, weight: FontWeight.w800),
      ),
    );
  }
}

class _LeanStatusItem {
  final String label;
  final String value;
  final bool active;

  const _LeanStatusItem({
    required this.label,
    required this.value,
    required this.active,
  });
}

class _LeanStatusGrid extends StatelessWidget {
  final List<_LeanStatusItem> items;

  const _LeanStatusGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.7,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.panel.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      (item.active
                              ? AppColors.primaryContainer
                              : AppColors.outline)
                          .withValues(alpha: item.active ? 0.26 : 0.14),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: AppText.technicalLabel(
                        size: 10,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  Text(
                    item.value,
                    style: AppText.body(
                      size: 13,
                      weight: FontWeight.w900,
                      color: item.active
                          ? AppColors.primaryContainer
                          : AppColors.textSecondary,
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
