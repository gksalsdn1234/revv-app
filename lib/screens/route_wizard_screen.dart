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
import '../services/waypoint_optimizer.dart';
import '../theme/text_styles.dart';
import '../widgets/revv_ui.dart';

/// 루트 계획 마법사 — Tesla-style 트립 플래너
class RouteWizardSheet extends StatefulWidget {
  const RouteWizardSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const RouteWizardSheet(),
    );
  }

  @override
  State<RouteWizardSheet> createState() => _RouteWizardSheetState();
}

enum _Step { routeType, distance, multiSelect, planning, tripPlan, building }

class _RouteWizardSheetState extends State<RouteWizardSheet> {
  _Step _step = _Step.routeType;

  // 설정
  bool _isLoop = false;
  bool _isMulti = false;
  int _targetKm = 50;

  // 다중 선택 모드
  final Set<String> _selectedIds = {};

  // 플랜 데이터
  RevvRoute? _selectedRoute;
  List<Poi> _preStopCandidates = [];
  List<Poi> _postStopCandidates = [];
  List<Poi> _routePois = [];
  int _preStopIdx = -1; // -1 = 없음
  int _postStopIdx = -1; // -1 = 없음
  String? _error;

  Poi? get _preStop =>
      _preStopIdx >= 0 && _preStopIdx < _preStopCandidates.length
      ? _preStopCandidates[_preStopIdx]
      : null;

  Poi? get _postStop =>
      _postStopIdx >= 0 && _postStopIdx < _postStopCandidates.length
      ? _postStopCandidates[_postStopIdx]
      : null;

  // ── 플랜 생성 ────────────────────────────────────────────

  Future<void> _generatePlan() async {
    setState(() {
      _step = _Step.planning;
      _error = null;
    });

    final loc = context.read<LocationService>();
    final routeSvc = context.read<RouteService>();
    final center = LatLng(loc.lat, loc.lng);

    // 1. 루트 선택
    RevvRoute? route;
    if (_isLoop) {
      route = await RouteBuilderService.buildLoop(
        center: center,
        targetKm: _targetKm,
        candidates: routeSvc.routes,
      );
    } else {
      if (routeSvc.routes.isNotEmpty) {
        final pool = routeSvc.routes.take(3).toList()..shuffle();
        route = pool.first;
      }
    }

    if (route == null) {
      if (mounted) {
        setState(() {
          _error = '루트를 찾지 못했어요. 루트 탐색을 먼저 해주세요.';
          _step = _Step.routeType;
        });
      }
      return;
    }
    _selectedRoute = route;

    // 2. 출발 전 POI (현재 위치 주변 — 카페·맛집 중심)
    final preF = PoiService.searchNearby(
      loc.lat,
      loc.lng,
      radiusM: 5000,
      maxTotal: 6,
    );

    // 3. 루트 후 POI (루트 끝점 주변 — 뷰포인트·카페 중심)
    final end = route.nodes.isNotEmpty ? route.nodes.last : center;
    final postF = PoiService.searchNearby(
      end.lat,
      end.lng,
      radiusM: 8000,
      maxTotal: 6,
    );

    // 4. 루트 중간 주변 POI (지도 핀 추천용)
    final midIdx = route.nodes.length ~/ 2;
    final mid = midIdx < route.nodes.length ? route.nodes[midIdx] : center;
    final midF = PoiService.searchNearby(
      mid.lat,
      mid.lng,
      radiusM: 5000,
      maxTotal: 10,
    );

    final results = await Future.wait([preF, postF, midF]);

    if (mounted) {
      setState(() {
        _preStopCandidates = results[0];
        _postStopCandidates = results[1];
        _routePois = results[2];
        _preStopIdx = -1;
        _postStopIdx = _postStopCandidates.isNotEmpty ? 0 : -1;
        _step = _Step.tripPlan;
      });
    }
  }

  // ── 루트 빌드 & 출발 ──────────────────────────────────────

  Future<void> _launch() async {
    if (_selectedRoute == null) return;
    setState(() => _step = _Step.building);

    final routeSvc = context.read<RouteService>();
    final homeSvc = context.read<HomeLocationService>();
    var builtRoute = _selectedRoute!;

    // 경유지: 루트 끝 → (post-stop) → 집
    final extra = <LatLng>[];
    if (_postStop != null) extra.add(LatLng(_postStop!.lat, _postStop!.lng));
    if (homeSvc.isSet) extra.add(homeSvc.home!);

    if (extra.isNotEmpty) {
      final waypoints = [builtRoute.nodes.last, ...extra];
      final extPath = await DirectionsService.getMultiRoute(waypoints);
      if (extPath.isNotEmpty) {
        final suffix = _postStop != null ? ' → ${_postStop!.name}' : '';
        builtRoute = RevvRoute(
          id: builtRoute.id,
          name: '${builtRoute.name}$suffix',
          nodes: [...builtRoute.nodes, ...extPath],
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

    routeSvc.selectRoute(builtRoute);
    if (mounted) Navigator.pop(context);
  }

  // ── 네비게이션 ────────────────────────────────────────────

  void _next() {
    switch (_step) {
      case _Step.routeType:
        if (_isMulti) {
          setState(() {
            _selectedIds.clear();
            _step = _Step.multiSelect;
          });
        } else {
          setState(() => _step = _Step.distance);
        }
        break;
      case _Step.distance:
        _generatePlan();
        break;
      case _Step.multiSelect:
        _optimizeSelected();
        break;
      default:
        break;
    }
  }

  void _back() {
    switch (_step) {
      case _Step.distance:
        setState(() => _step = _Step.routeType);
        break;
      case _Step.multiSelect:
        setState(() => _step = _Step.routeType);
        break;
      case _Step.tripPlan:
        setState(() => _step = _Step.distance);
        break;
      default:
        break;
    }
  }

  // ── 다중 구간 최적화 + 출발 ───────────────────────────────

  Future<void> _optimizeSelected() async {
    final routeSvc = context.read<RouteService>();
    final loc = context.read<LocationService>();

    final selected = routeSvc.routes
        .where((r) => _selectedIds.contains(r.id))
        .toList();

    if (selected.isEmpty) {
      setState(() => _error = '구간을 1개 이상 선택해주세요.');
      return;
    }

    setState(() {
      _step = _Step.building;
      _error = null;
    });

    final result = await routeSvc.optimizeWaypoints(
      userPos: LatLng(loc.lat, loc.lng),
      segments: selected,
      returnHome: false,
    );

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _error = '최적화에 실패했어요. 다시 시도해주세요.';
        _step = _Step.multiSelect;
      });
      return;
    }

    _launchOptimized(result, routeSvc);
  }

  void _launchOptimized(OptimizedRoute result, RouteService routeSvc) {
    if (!mounted) return;

    // 최적화된 구간들의 노드를 순서대로 이어붙여 하나의 RevvRoute로 만들기
    final allNodes = <LatLng>[];
    double totalScore = 0;
    double totalKm = 0;
    final names = <String>[];

    for (int i = 0; i < result.orderedSegments.length; i++) {
      final seg = result.orderedSegments[i];
      final rev = result.reversed[i];
      final nodes = rev ? seg.nodes.reversed.toList() : seg.nodes;
      allNodes.addAll(nodes);
      totalScore += seg.windingScore;
      totalKm += seg.distanceKm;
      names.add(seg.name);
    }

    // Mapbox로 받은 실제 경로가 있으면 사용
    final finalNodes = result.polyline.isNotEmpty ? result.polyline : allNodes;

    final merged = RevvRoute(
      id: 'multi_${DateTime.now().millisecondsSinceEpoch}',
      name:
          names.take(2).join(' → ') +
          (names.length > 2 ? ' +${names.length - 2}' : ''),
      nodes: finalNodes,
      distanceKm: totalKm,
      windingScore: totalScore / result.orderedSegments.length,
      starRating: RevvRoute.toStarRating(
        totalScore / result.orderedSegments.length,
      ),
      sharpCurveCount: 0,
      centerPoint: finalNodes[finalNodes.length ~/ 2],
      distanceFromUser: 0,
      tightCurveKm: result.orderedSegments.fold(
        0.0,
        (s, r) => s + r.tightCurveKm,
      ),
      mediumCurveKm: result.orderedSegments.fold(
        0.0,
        (s, r) => s + r.mediumCurveKm,
      ),
      maxContinuousKm: result.orderedSegments
          .map((r) => r.maxContinuousKm)
          .reduce((a, b) => a > b ? a : b),
      elevationDelta: 0,
    );

    routeSvc.selectRoute(merged);
    if (mounted) Navigator.pop(context);
  }

  void _cyclePreStop() {
    setState(() {
      _preStopIdx = _preStopIdx >= _preStopCandidates.length - 1
          ? -1
          : _preStopIdx + 1;
    });
  }

  void _cyclePostStop() {
    setState(() {
      _postStopIdx = _postStopIdx >= _postStopCandidates.length - 1
          ? -1
          : _postStopIdx + 1;
    });
  }

  // ── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 16,
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
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            if (_step == _Step.planning || _step == _Step.building) ...[
              const SizedBox(height: 40),
              const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _step == _Step.planning
                      ? '최적의 여정을 구성하고 있어요...'
                      : '루트를 계획하고 있어요...',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    color: AppColors.gray,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ] else ...[
              _buildTitle(),
              const SizedBox(height: 16),
              Flexible(child: SingleChildScrollView(child: _buildContent())),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildNavButtons(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    if (_step == _Step.tripPlan) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘의 드라이브 플랜',
            style: AppText.inter(size: 20, weight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '슬롯을 탭해서 장소를 바꿀 수 있어요',
            style: GoogleFonts.rajdhani(fontSize: 12, color: AppColors.gray),
          ),
        ],
      );
    }
    final titles = {
      _Step.routeType: '어떻게 달릴까요?',
      _Step.distance: '목표 거리를 설정해요',
      _Step.multiSelect: '통과할 구간을 선택해요',
    };
    return Text(
      titles[_step] ?? '',
      style: AppText.inter(size: 20, weight: FontWeight.w900),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case _Step.routeType:
        return _threeChoice();

      case _Step.multiSelect:
        return _buildMultiSelect();

      case _Step.distance:
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
                    color: sel
                        ? AppColors.primaryContainer
                        : AppColors.surfaceHigh.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: sel
                          ? AppColors.primaryContainer
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${km}km',
                        style: GoogleFonts.orbitron(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: sel
                              ? AppColors.onPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        km == 30
                            ? '가볍게'
                            : km == 50
                            ? '적당히'
                            : '롱 크루즈',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          color: sel
                              ? AppColors.onPrimary.withValues(alpha: 0.72)
                              : AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );

      case _Step.tripPlan:
        return _buildTripPlan();

      default:
        return const SizedBox.shrink();
    }
  }

  // ── 트립 플랜 카드 ────────────────────────────────────────

  Widget _buildTripPlan() {
    final route = _selectedRoute;
    if (route == null) return const SizedBox.shrink();
    final homeSvc = context.read<HomeLocationService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 현재 위치
        _fixedNode(icon: '📍', label: '현재 위치'),
        _connector(),

        // Pre-stop 슬롯
        _poiSlot(
          defaultLabel: '출발 전 들를 곳 추가',
          poi: _preStop,
          hasAny: _preStopCandidates.isNotEmpty,
          onTap: _cyclePreStop,
        ),
        _connector(),

        // 루트 카드
        _routeCard(route),
        _connector(),

        // Post-stop 슬롯
        _poiSlot(
          defaultLabel: '루트 후 들를 곳 추가',
          poi: _postStop,
          hasAny: _postStopCandidates.isNotEmpty,
          onTap: _cyclePostStop,
        ),

        // 집 (home 설정된 경우)
        if (homeSvc.isSet) ...[
          _connector(),
          _fixedNode(icon: '🏠', label: '집'),
        ],

        // 루트 주변 추천 POI
        if (_routePois.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('루트 주변 추천'),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _routePois.length,
              itemBuilder: (_, i) => _routePoiChip(_routePois[i]),
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _fixedNode({required String icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _poiSlot({
    required String defaultLabel,
    required Poi? poi,
    required bool hasAny,
    required VoidCallback onTap,
  }) {
    final hasSelection = poi != null;
    return GestureDetector(
      onTap: hasAny ? onTap : null,
      child: RevvGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: hasSelection
            ? AppColors.primaryContainer.withValues(alpha: 0.08)
            : AppColors.bg.withValues(alpha: 0.74),
        child: Row(
          children: [
            Text(
              poi != null ? poi.category.emoji : '➕',
              style: TextStyle(
                fontSize: 20,
                color: hasSelection ? null : Colors.white38,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi != null ? poi.name : defaultLabel,
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasSelection ? Colors.white : Colors.white38,
                    ),
                  ),
                  if (hasSelection)
                    Text(
                      '${(poi.distanceKm * 10).round() / 10}km · ${poi.category.label}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: AppColors.gray,
                      ),
                    )
                  else if (hasAny)
                    Text(
                      '탭해서 추가',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: Colors.white24,
                      ),
                    ),
                ],
              ),
            ),
            if (hasAny)
              const Icon(Icons.swap_horiz, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _routeCard(RevvRoute route) {
    final stars = List.generate(
      route.starRating.round().clamp(1, 5),
      (_) => '⭐',
    ).join();
    return RevvGlassCard(
      padding: const EdgeInsets.all(16),
      color: AppColors.primaryContainer.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Text('🛣', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.name,
                  style: AppText.inter(
                    size: 14,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${route.distanceKm.toStringAsFixed(1)}km',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                    if (stars.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(stars, style: const TextStyle(fontSize: 10)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 18),
      child: Column(
        children: [
          Container(width: 1, height: 10, color: Colors.white12),
          const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white24,
            size: 14,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.gray,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _routePoiChip(Poi poi) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(poi.category.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            poi.name,
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${(poi.distanceKm * 10).round() / 10}km',
            style: GoogleFonts.rajdhani(fontSize: 10, color: AppColors.gray),
          ),
        ],
      ),
    );
  }

  // ── 하단 버튼 ─────────────────────────────────────────────

  Widget _buildNavButtons() {
    final isFirst = _step == _Step.routeType;
    final isLast = _step == _Step.tripPlan || _step == _Step.multiSelect;

    return Row(
      children: [
        if (!isFirst)
          GestureDetector(
            onTap: _back,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Text(
                '이전',
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  color: AppColors.gray,
                ),
              ),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: isLast ? _launch : _next,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  _step == _Step.multiSelect
                      ? '최적 경로 생성  ✨'
                      : isLast
                      ? '출발하기  🚗'
                      : '다음',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 3선택 UI ─────────────────────────────────────────────

  Widget _threeChoice() {
    final modes = [
      (icon: '🛣', label: '단독 파편\n재밌는 도로 하나', isLoop: false, isMulti: false),
      (icon: '🔄', label: '루프 만들기\n여러 구간 이어달리기', isLoop: true, isMulti: false),
      (
        icon: '🗺',
        label: '구간 이어달리기\n최적 경로 자동 계획',
        isLoop: false,
        isMulti: true,
      ),
    ];
    return Row(
      children: modes.map((m) {
        final sel = _isMulti ? m.isMulti : (_isLoop == m.isLoop && !m.isMulti);
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _isLoop = m.isLoop;
              _isMulti = m.isMulti;
            }),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.primaryContainer.withValues(alpha: 0.15)
                    : AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel ? AppColors.primaryContainer : Colors.white12,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(m.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 6),
                  Text(
                    m.label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: sel ? AppColors.primaryContainer : AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 다중 구간 선택 ─────────────────────────────────────────

  Widget _buildMultiSelect() {
    final routes = context.read<RouteService>().routes;

    if (routes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          '주변 루트가 없어요. ROUTES 탭에서 먼저 탐색해주세요.',
          style: GoogleFonts.rajdhani(fontSize: 13, color: AppColors.gray),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_selectedIds.length}개 선택됨  ·  최적 순서는 자동으로 계산돼요',
          style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.gray),
        ),
        const SizedBox(height: 10),
        ...routes.map((r) {
          final selected = _selectedIds.contains(r.id);
          return GestureDetector(
            onTap: () => setState(() {
              if (selected) {
                _selectedIds.remove(r.id);
              } else {
                _selectedIds.add(r.id);
              }
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryContainer.withValues(alpha: 0.1)
                    : AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primaryContainer.withValues(alpha: 0.6)
                      : Colors.white12,
                  width: selected ? 1.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.red : Colors.transparent,
                      border: Border.all(
                        color: selected ? AppColors.red : Colors.white24,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 11, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${r.distanceKm.toStringAsFixed(1)}km  ·  ★${r.windingScore.toStringAsFixed(1)}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            color: AppColors.gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 거리 배지
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${r.distanceFromUser.toStringAsFixed(0)}km',
                      style: GoogleFonts.rajdhani(
                        fontSize: 9,
                        color: AppColors.gray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
