import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/route_brief_service.dart';
import '../services/weather_service.dart';
import '../widgets/sprint_toggle.dart';
import '../screens/sprint_screen.dart';

class RoutesBottomSheet extends StatefulWidget {
  const RoutesBottomSheet({super.key});

  @override
  State<RoutesBottomSheet> createState() => _RoutesBottomSheetState();
}

class _RoutesBottomSheetState extends State<RoutesBottomSheet> {
  final _briefService = RouteBriefService();
  String _briefText = '';
  bool _briefLoading = false;
  String? _lastBriefRouteId;

  String _displayText = '';
  int _charIndex = 0;
  Timer? _typeTimer;

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBriefing(RevvRoute route) async {
    if (_lastBriefRouteId == route.id) return;
    _lastBriefRouteId = route.id;

    setState(() {
      _briefLoading = true;
      _displayText = '';
      _briefText = '';
    });

    final weather = context.read<WeatherService>();
    final text = await _briefService.getBriefing(route: route, weather: weather);

    if (!mounted) return;
    setState(() {
      _briefText = text;
      _briefLoading = false;
    });
    _startTyping(text);
  }

  void _startTyping(String text) {
    _typeTimer?.cancel();
    _charIndex = 0;
    _displayText = '';
    _typeTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (_charIndex < text.length) {
        if (mounted) setState(() => _displayText += text[_charIndex++]);
      } else {
        _typeTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (context, svc, _) {
        if (svc.selectedRoute != null &&
            svc.selectedRoute!.id != _lastBriefRouteId &&
            !_briefLoading) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _loadBriefing(svc.selectedRoute!));
        }

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(top: BorderSide(color: AppColors.red, width: 2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text('NEARBY ROUTES',
                        style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.red,
                            letterSpacing: 4)),
                    const Spacer(),
                    // 반경 선택 버튼
                    _RadiusSelector(
                      current: svc.searchRadiusKm,
                      onSelect: (km) {
                        final loc = context.read<LocationService>();
                        svc.changeRadius(km, loc.lat, loc.lng);
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 190,
                child: svc.routes.isEmpty
                    ? Center(
                        child: Text(
                          svc.isLoading ? '분석 중...' : '이 근처엔 루트가 없어요.',
                          style: GoogleFonts.rajdhani(
                              fontSize: 13, color: AppColors.gray),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: svc.routes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _RouteCard(
                          route: svc.routes[i],
                          isSelected: svc.selectedRoute?.id == svc.routes[i].id,
                          onTap: () => svc.selectRoute(svc.routes[i]),
                        ),
                      ),
              ),
              if (svc.selectedRoute != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: AppColors.red.withOpacity(0.3))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('REVV',
                          style: GoogleFonts.rajdhani(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.red,
                              letterSpacing: 4)),
                      const SizedBox(height: 6),
                      _briefLoading
                          ? Text('분석 중...',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 15, color: AppColors.gray))
                          : Text(_displayText,
                              style: GoogleFonts.rajdhani(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                      const SizedBox(height: 12),
                      RedGlowButton(
                        label: '이 루트로 달리기',
                        filled: true,
                        height: 44,
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SprintScreen(
                                  selectedRoute: svc.selectedRoute),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RevvRoute route;
  final bool isSelected;
  final VoidCallback onTap;

  const _RouteCard({
    required this.route,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isSelected ? AppColors.red : AppColors.gray;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? AppColors.red.withOpacity(0.8)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 거리 + 소요시간
            Row(
              children: [
                Text(route.distanceDisplay,
                    style: GoogleFonts.rajdhani(fontSize: 10, color: AppColors.gray)),
                const Spacer(),
                Text('약 ${route.durationDisplay}',
                    style: GoogleFonts.rajdhani(fontSize: 10, color: AppColors.gray)),
              ],
            ),
            const SizedBox(height: 4),
            // 루트명
            Text(route.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.orbitron(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 5),
            // 별점
            Text(route.starDisplay,
                style: TextStyle(fontSize: 12, color: accent)),
            const SizedBox(height: 6),
            // TIGHT / MED 칩
            Row(
              children: [
                _CurveChip(
                  label: 'TIGHT',
                  value: '${route.tightCurveKm.toStringAsFixed(1)}k',
                  color: AppColors.red,
                ),
                const SizedBox(width: 4),
                _CurveChip(
                  label: 'MED',
                  value: '${route.mediumCurveKm.toStringAsFixed(1)}k',
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 최장 연속 와인딩
            Row(
              children: [
                Icon(Icons.linear_scale, size: 10, color: accent),
                const SizedBox(width: 3),
                Text(
                  'MAX ${route.maxContinuousKm.toStringAsFixed(1)} km',
                  style: GoogleFonts.rajdhani(fontSize: 10, color: accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusSelector extends StatelessWidget {
  final int current;
  final void Function(int km) onSelect;
  const _RadiusSelector({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [30, 50, 100].map((km) {
        final active = current == km;
        return GestureDetector(
          onTap: () => onSelect(km),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: active ? AppColors.red : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: active
                    ? AppColors.red
                    : AppColors.gray.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Text(
              '${km}km',
              style: GoogleFonts.rajdhani(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.gray,
                letterSpacing: 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CurveChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CurveChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: GoogleFonts.rajdhani(
                  fontSize: 8, color: color, letterSpacing: 1),
            ),
            TextSpan(
              text: value,
              style: GoogleFonts.rajdhani(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
