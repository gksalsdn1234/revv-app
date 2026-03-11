import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../models/poi.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/route_builder_service.dart';
import '../services/poi_service.dart';
import '../services/home_location_service.dart';
import '../services/directions_service.dart';

/// 루트 계획 마법사 — 바텀시트로 호출
class RouteWizardSheet extends StatefulWidget {
  const RouteWizardSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => const RouteWizardSheet(),
    );
  }

  @override
  State<RouteWizardSheet> createState() => _RouteWizardSheetState();
}

enum _WizardStep { routeType, distance, afterRoute, poi, building, done }

class _RouteWizardSheetState extends State<RouteWizardSheet> {
  _WizardStep _step = _WizardStep.routeType;

  // 선택값
  bool _isLoop = false;
  int _targetKm = 50;
  bool _stopAfter = false;
  PoiCategory? _poiCategory;

  // 결과
  bool _building = false;
  String? _error;

  Future<void> _build() async {
    setState(() {
      _step = _WizardStep.building;
      _building = true;
      _error = null;
    });

    final loc = context.read<LocationService>();
    final routeSvc = context.read<RouteService>();
    final homeSvc = context.read<HomeLocationService>();
    final center = LatLng(loc.lat, loc.lng);

    RevvRoute? builtRoute;

    if (_isLoop) {
      builtRoute = await RouteBuilderService.buildLoop(
        center: center,
        targetKm: _targetKm,
        candidates: routeSvc.routes,
      );
    } else {
      // 단독 파편 — 상위 루트 그대로 사용
      builtRoute = routeSvc.routes.isNotEmpty ? routeSvc.routes.first : null;
    }

    if (builtRoute == null) {
      setState(() {
        _error = '루트를 만들지 못했어요. 루트 목록을 먼저 불러와주세요.';
        _building = false;
        _step = _WizardStep.routeType;
      });
      return;
    }

    // POI + 귀가 경로가 있으면 루트 끝점에서 POI → 집 경로 추가
    if (_stopAfter && _poiCategory != null) {
      final pois = await PoiService.search(
        builtRoute.nodes.last.lat,
        builtRoute.nodes.last.lng,
        _poiCategory!,
        radiusM: 8000,
        maxResults: 1,
      );
      if (pois.isNotEmpty && homeSvc.isSet) {
        final poi = pois.first;
        final home = homeSvc.home!;
        final extra = await DirectionsService.getMultiRoute([
          builtRoute.nodes.last,
          LatLng(poi.lat, poi.lng),
          home,
        ]);
        if (extra.isNotEmpty) {
          // 루트 끝에 귀가 경로 이어붙이기
          final combined = [...builtRoute.nodes, ...extra];
          builtRoute = RevvRoute(
            id: builtRoute.id,
            name: '${builtRoute.name} → ${poi.name}',
            nodes: combined,
            distanceKm: builtRoute.distanceKm,
            windingScore: builtRoute.windingScore,
            starRating: builtRoute.starRating,
            sharpCurveCount: 0,
            centerPoint: builtRoute.centerPoint,
            distanceFromUser: 0,
            tightCurveKm: builtRoute.tightCurveKm,
            mediumCurveKm: builtRoute.mediumCurveKm,
            maxContinuousKm: builtRoute.maxContinuousKm,
            elevationDelta: 0,
          );
        }
      }
    }

    routeSvc.selectedRoute = builtRoute;
    routeSvc.notifyListeners();

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          if (_step == _WizardStep.building) ...[
            const Center(child: CircularProgressIndicator(color: AppColors.red)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '루트를 계획하고 있어요...',
                style: GoogleFonts.rajdhani(fontSize: 14, color: AppColors.gray),
              ),
            ),
          ] else ...[
            _stepTitle(),
            const SizedBox(height: 16),
            _stepContent(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: GoogleFonts.rajdhani(fontSize: 12, color: AppColors.red)),
            ],
            const SizedBox(height: 20),
            _navigationButtons(),
          ],
        ],
      ),
    );
  }

  Widget _stepTitle() {
    final titles = {
      _WizardStep.routeType: '어떻게 달릴까요?',
      _WizardStep.distance: '목표 거리를 설정해요',
      _WizardStep.afterRoute: '루트 끝나면?',
      _WizardStep.poi: '어디 들를까요?',
      _WizardStep.done: '완료',
    };
    return Text(
      titles[_step] ?? '',
      style: GoogleFonts.orbitron(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case _WizardStep.routeType:
        return _twoChoice(
          leftIcon: '🛣',
          leftLabel: '단독 파편\n재밌는 도로 하나',
          rightIcon: '🔄',
          rightLabel: '루프 만들기\n여러 구간 이어달리기',
          leftSelected: !_isLoop,
          onLeft: () => setState(() => _isLoop = false),
          onRight: () => setState(() => _isLoop = true),
        );

      case _WizardStep.distance:
        return Row(
          children: [30, 50, 100].map((km) {
            final sel = _targetKm == km;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _targetKm = km),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.red : AppColors.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sel ? AppColors.red : Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Text('${km}km',
                          style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(km == 30 ? '가볍게' : km == 50 ? '적당히' : '롱 크루즈',
                          style: GoogleFonts.rajdhani(fontSize: 11, color: sel ? Colors.white70 : AppColors.gray)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );

      case _WizardStep.afterRoute:
        return _twoChoice(
          leftIcon: '🏠',
          leftLabel: '바로 귀가\n집으로 돌아가기',
          rightIcon: '📍',
          rightLabel: '어딘가 들르기\n카페, 맛집 등',
          leftSelected: !_stopAfter,
          onLeft: () => setState(() => _stopAfter = false),
          onRight: () => setState(() => _stopAfter = true),
        );

      case _WizardStep.poi:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PoiCategory.values.map((cat) {
            final sel = _poiCategory == cat;
            return GestureDetector(
              onTap: () => setState(() => _poiCategory = cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.red : AppColors.bg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sel ? AppColors.red : Colors.white12),
                ),
                child: Text(
                  '${cat.emoji} ${cat.label}',
                  style: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            );
          }).toList(),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _twoChoice({
    required String leftIcon,
    required String leftLabel,
    required String rightIcon,
    required String rightLabel,
    required bool leftSelected,
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) {
    return Row(
      children: [
        Expanded(child: _ChoiceCard(icon: leftIcon, label: leftLabel, selected: leftSelected, onTap: onLeft)),
        const SizedBox(width: 10),
        Expanded(child: _ChoiceCard(icon: rightIcon, label: rightLabel, selected: !leftSelected, onTap: onRight)),
      ],
    );
  }

  Widget _navigationButtons() {
    final isLast = _step == _WizardStep.afterRoute && !_stopAfter ||
        _step == _WizardStep.poi;

    return Row(
      children: [
        if (_step != _WizardStep.routeType)
          GestureDetector(
            onTap: _back,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: Text('이전', style: GoogleFonts.rajdhani(fontSize: 13, color: AppColors.gray)),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: isLast ? _build : _next,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  isLast ? '루트 만들기' : '다음',
                  style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _next() {
    setState(() {
      switch (_step) {
        case _WizardStep.routeType:
          _step = _isLoop ? _WizardStep.distance : _WizardStep.afterRoute;
          break;
        case _WizardStep.distance:
          _step = _WizardStep.afterRoute;
          break;
        case _WizardStep.afterRoute:
          _step = _stopAfter ? _WizardStep.poi : _WizardStep.afterRoute;
          break;
        default:
          break;
      }
    });
  }

  void _back() {
    setState(() {
      switch (_step) {
        case _WizardStep.distance:
          _step = _WizardStep.routeType;
          break;
        case _WizardStep.afterRoute:
          _step = _isLoop ? _WizardStep.distance : _WizardStep.routeType;
          break;
        case _WizardStep.poi:
          _step = _WizardStep.afterRoute;
          break;
        default:
          break;
      }
    });
  }
}

class _ChoiceCard extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceCard({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.red.withOpacity(0.15) : AppColors.bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? AppColors.red : Colors.white12, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
