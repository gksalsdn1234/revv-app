import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import '../services/drive_planner_service.dart';
import '../services/location_service.dart';
import '../services/route_loading_policy.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../widgets/copilot_start_sheet.dart';
import '../widgets/map_widget.dart';
import '../widgets/revv_ui.dart';
import 'lean_drive_screen.dart';
import 'lean_route_finder_screen.dart';

typedef DrivePlannerOriginResolver =
    Future<LatLng?> Function(BuildContext context);

const _plannerRegions = [
  _PlannerRegion('montreal', 'Montreal', LatLng(45.5017, -73.5673)),
  _PlannerRegion('laurentians', 'Laurentians', LatLng(45.9000, -74.1600)),
  _PlannerRegion('toronto', 'Toronto', LatLng(43.6532, -79.3832)),
  _PlannerRegion('vancouver', 'Vancouver', LatLng(49.2827, -123.1207)),
];

class LeanDrivePlannerScreen extends StatefulWidget {
  final DrivePlannerService? planner;
  final DrivePlannerOriginResolver? originResolver;

  const LeanDrivePlannerScreen({super.key, this.planner, this.originResolver});

  @override
  State<LeanDrivePlannerScreen> createState() => _LeanDrivePlannerScreenState();
}

class _LeanDrivePlannerScreenState extends State<LeanDrivePlannerScreen> {
  static const _defaultOrigin = LatLng(45.5017, -73.5673);
  static const _requestTimeout = Duration(seconds: 12);

  late final DrivePlannerService _planner =
      widget.planner ?? DrivePlannerService();
  LatLng _origin = _defaultOrigin;
  LatLng _destination = _plannerRegions.first.point;
  LatLng _mapCenter = _plannerRegions.first.point;
  DriveBudget _budget = DriveBudget.short;
  DrivePlan? _plan;
  bool _loadingOrigin = true;
  bool _planning = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOrigin());
  }

  Future<void> _loadOrigin() async {
    final point =
        await (widget.originResolver?.call(context) ??
            _defaultOriginResolver(context));
    if (!mounted) return;
    setState(() {
      _origin = point ?? _defaultOrigin;
      _loadingOrigin = false;
    });
  }

  static Future<LatLng?> _defaultOriginResolver(BuildContext context) async {
    final location = context.read<LocationService>();
    await location.requestPermission();
    await location.startTracking();
    return location.ensureLiveLocation();
  }

  Future<void> _buildPlan() async {
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      _planning = true;
      _status = null;
      _plan = null;
    });
    try {
      final plan = await _planner
          .buildPlan(
            DrivePlanRequest(
              origin: _origin,
              destination: _destination,
              windingBudgetMinutes: _budgetMinutes(_budget),
            ),
          )
          .timeout(_requestTimeout);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _status = plan == null
            ? _copy(
                language,
                ko: '이 조건으로 여정을 만들지 못했어요.',
                en: 'Could not build a plan for this route.',
                fr: 'Impossible de créer ce trajet.',
              )
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _copy(
          language,
          ko: '여정 계산이 오래 걸려 중단했어요. 다시 시도해 주세요.',
          en: 'Planning took too long. Try again.',
          fr: 'Le calcul a pris trop de temps. Réessayez.',
        );
      });
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _startFirstWinding() async {
    final route = _firstWindingRoute;
    if (route == null) return;
    final startChoice = await showCopilotStartSheet(context, route: route);
    if (!mounted || startChoice == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(
          route: route,
          simulated: startChoice == CopilotStartChoice.simulate,
        ),
      ),
    );
  }

  Future<void> _openExternalNavigation() async {
    final plan = _plan;
    if (plan == null) return;
    final language = context.read<SettingsService>().appLanguage;
    final waypoints = plan.waypoints.length <= 2
        ? const <LatLng>[]
        : plan.waypoints.sublist(1, plan.waypoints.length - 1);
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': _coord(_origin),
      'destination': _coord(_destination),
      if (waypoints.isNotEmpty) 'waypoints': waypoints.map(_coord).join('|'),
      'travelmode': 'driving',
    });
    final appUri = Uri.parse(
      'comgooglemaps://?saddr=${_coord(_origin)}&daddr=${_coord(_destination)}&directionsmode=driving',
    );
    final launchedApp = await launchUrl(
      appUri,
      mode: LaunchMode.externalApplication,
    );
    if (launchedApp) return;
    final launchedWeb = await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
    if (launchedWeb || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
    );
  }

  RevvRoute? get _firstWindingRoute {
    final plan = _plan;
    if (plan == null) return null;
    for (final leg in plan.legs) {
      if (leg.kind == DrivePlanLegKind.winding && leg.route != null) {
        return leg.route;
      }
    }
    return null;
  }

  List<LatLng> get _transitPolyline => _planPolyline(DrivePlanLegKind.transit);

  List<LatLng> get _windingPolyline => _planPolyline(DrivePlanLegKind.winding);

  List<LatLng> _planPolyline(DrivePlanLegKind kind) {
    final plan = _plan;
    if (plan == null) return const [];
    return [
      for (final leg in plan.legs)
        if (leg.kind == kind) ...leg.nodes,
    ];
  }

  void _selectRegion(_PlannerRegion region) {
    setState(() {
      _destination = region.point;
      _mapCenter = region.point;
      _plan = null;
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: RevvTopBar(
        title: _copy(
          language,
          ko: '드라이브 플래너',
          en: 'Drive planner',
          fr: 'Planifier',
        ),
        eyebrow: 'REVV',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              navPolyline: _transitPolyline,
              routePolyline: _windingPolyline,
              recenterSignal: _mapCenter.hashCode,
              onCameraCenterChanged: (point) => _mapCenter = point,
            ),
          ),
          const Center(
            child: Icon(
              Icons.location_pin,
              color: AppColors.primaryContainer,
              size: 40,
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              children: [
                _PlannerInputCard(
                  language: language,
                  origin: _origin,
                  destination: _destination,
                  loadingOrigin: _loadingOrigin,
                  budget: _budget,
                  onUsePinAsOrigin: () => setState(() {
                    _origin = _mapCenter;
                    _plan = null;
                    _status = null;
                  }),
                  onUsePinAsDestination: () => setState(() {
                    _destination = _mapCenter;
                    _plan = null;
                    _status = null;
                  }),
                  onBudget: (value) => setState(() {
                    _budget = value;
                    _plan = null;
                    _status = null;
                  }),
                  onPlan: _planning || _loadingOrigin ? null : _buildPlan,
                  planning: _planning,
                ),
                const SizedBox(height: 10),
                _RegionStrip(
                  language: language,
                  selected: _destination,
                  onSelected: _selectRegion,
                ),
                const SizedBox(height: 10),
                if (_planning)
                  _StateCard(
                    title: _copy(
                      language,
                      ko: '여정 계산 중',
                      en: 'Planning route',
                      fr: 'Calcul du trajet',
                    ),
                    body: _copy(
                      language,
                      ko: '최대 12초 안에 결과를 보여드릴게요.',
                      en: 'This stops after 12 seconds if no plan returns.',
                      fr: 'Le calcul s’arrête après 12 secondes sans résultat.',
                    ),
                  )
                else if (_status != null)
                  _StateCard(title: _status!, body: _retryCopy(language))
                else if (_plan != null)
                  _PlanResultCard(
                    plan: _plan!,
                    language: language,
                    targetMinutes: _budgetMinutes(_budget),
                    onStart: _firstWindingRoute == null
                        ? null
                        : _startFirstWinding,
                    onNavigate: _openExternalNavigation,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannerInputCard extends StatelessWidget {
  final AppLanguage language;
  final LatLng origin;
  final LatLng destination;
  final bool loadingOrigin;
  final DriveBudget budget;
  final VoidCallback onUsePinAsOrigin;
  final VoidCallback onUsePinAsDestination;
  final ValueChanged<DriveBudget> onBudget;
  final VoidCallback? onPlan;
  final bool planning;

  const _PlannerInputCard({
    required this.language,
    required this.origin,
    required this.destination,
    required this.loadingOrigin,
    required this.budget,
    required this.onUsePinAsOrigin,
    required this.onUsePinAsDestination,
    required this.onBudget,
    required this.onPlan,
    required this.planning,
  });

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PointRow(
            label: _copy(language, ko: '출발', en: 'Origin', fr: 'Départ'),
            value: loadingOrigin
                ? _copy(
                    language,
                    ko: '현위치 확인 중',
                    en: 'Reading current location',
                    fr: 'Position en cours',
                  )
                : _coord(origin),
            action: _copy(
              language,
              ko: '핀으로 변경',
              en: 'Use pin',
              fr: 'Utiliser le repère',
            ),
            onTap: onUsePinAsOrigin,
          ),
          const SizedBox(height: 10),
          _PointRow(
            label: _copy(
              language,
              ko: '목적지',
              en: 'Destination',
              fr: 'Destination',
            ),
            value: _coord(destination),
            action: _copy(
              language,
              ko: '중앙 핀 선택',
              en: 'Set from pin',
              fr: 'Depuis le repère',
            ),
            onTap: onUsePinAsDestination,
          ),
          const SizedBox(height: 14),
          Text(
            _copy(
              language,
              ko: '와인딩 예산',
              en: 'Winding budget',
              fr: 'Temps sinueux',
            ),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          DriveBudgetChoiceStrip(
            budget: budget,
            routes: const [],
            onChanged: onBudget,
          ),
          const SizedBox(height: 14),
          RevvPrimaryButton(
            label: planning
                ? _copy(language, ko: '계산 중', en: 'Planning', fr: 'Calcul')
                : _copy(
                    language,
                    ko: '여정 만들기',
                    en: 'Build plan',
                    fr: 'Créer le trajet',
                  ),
            icon: Icons.route_rounded,
            onPressed: onPlan,
          ),
        ],
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  final String label;
  final String value;
  final String action;
  final VoidCallback onTap;

  const _PointRow({
    required this.label,
    required this.value,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.technicalLabel(size: 10)),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppText.body(size: 13, weight: FontWeight.w800),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

class _RegionStrip extends StatelessWidget {
  final AppLanguage language;
  final LatLng selected;
  final ValueChanged<_PlannerRegion> onSelected;

  const _RegionStrip({
    required this.language,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _plannerRegions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final region = _plannerRegions[index];
          final active =
              region.point.lat == selected.lat &&
              region.point.lng == selected.lng;
          return ChoiceChip(
            label: Text(region.title),
            selected: active,
            onSelected: (_) => onSelected(region),
            selectedColor: AppColors.primaryContainer,
            backgroundColor: AppColors.panel2.withValues(alpha: 0.92),
            labelStyle: AppText.body(
              size: 12,
              weight: FontWeight.w800,
              color: active ? AppColors.onPrimary : AppColors.textPrimary,
            ),
          );
        },
      ),
    );
  }
}

class _PlanResultCard extends StatelessWidget {
  final DrivePlan plan;
  final AppLanguage language;
  final int targetMinutes;
  final VoidCallback? onStart;
  final VoidCallback onNavigate;

  const _PlanResultCard({
    required this.plan,
    required this.language,
    required this.targetMinutes,
    required this.onStart,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final windingRatio = plan.totalMinutes == 0
        ? 0
        : (plan.windingMinutes / plan.totalMinutes * 100).round();
    return RevvGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _copy(
              language,
              ko: '여정 타임라인',
              en: 'Plan timeline',
              fr: 'Étapes du trajet',
            ),
            style: AppText.body(size: 18, weight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _copy(
              language,
              ko: '총 ${plan.totalMinutes}분 · 와인딩 $windingRatio%',
              en: '${plan.totalMinutes} min total · $windingRatio% winding',
              fr: '${plan.totalMinutes} min au total · $windingRatio% sinueux',
            ),
            style: AppText.body(size: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ...plan.legs.map((leg) => _TimelineLeg(leg: leg, language: language)),
          const SizedBox(height: 10),
          _PlanHonestyLine(
            plan: plan,
            language: language,
            targetMinutes: targetMinutes,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: RevvPrimaryButton(
                  label: _copy(
                    language,
                    ko: '드라이브 시작',
                    en: 'Start drive',
                    fr: 'Lancer',
                  ),
                  icon: Icons.play_arrow_rounded,
                  onPressed: onStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RevvGhostButton(
                  label: _copy(
                    language,
                    ko: '외부 내비',
                    en: 'Open nav',
                    fr: 'Navigation',
                  ),
                  onPressed: onNavigate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineLeg extends StatelessWidget {
  final DrivePlanLeg leg;
  final AppLanguage language;

  const _TimelineLeg({required this.leg, required this.language});

  @override
  Widget build(BuildContext context) {
    final isWinding = leg.kind == DrivePlanLegKind.winding;
    final title = isWinding
        ? '${leg.route?.name ?? _copy(language, ko: '와인딩 루트', en: 'Winding route', fr: 'Route sinueuse')} ${_minutes(language, leg.estimatedMinutes)}'
        : _copy(
            language,
            ko: '이동 ${leg.estimatedMinutes}분',
            en: 'Transit ${leg.estimatedMinutes} min',
            fr: 'Liaison ${leg.estimatedMinutes} min',
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isWinding ? Icons.route_rounded : Icons.near_me_rounded,
            size: 17,
            color: isWinding ? AppColors.primaryContainer : AppColors.cyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: AppText.body(size: 13, weight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanHonestyLine extends StatelessWidget {
  final DrivePlan plan;
  final AppLanguage language;
  final int targetMinutes;

  const _PlanHonestyLine({
    required this.plan,
    required this.language,
    required this.targetMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final text = plan.windingMinutes == 0
        ? _copy(
            language,
            ko: '이 경로엔 아직 발견된 와인딩이 없어요. 직행 안내로 열 수 있어요.',
            en: 'No discovered winding roads on this route yet. Direct navigation is available.',
            fr: 'Aucune route sinueuse trouvée sur ce trajet. La navigation directe reste disponible.',
          )
        : plan.budgetShortfallMinutes > 0
        ? _copy(
            language,
            ko: '와인딩 ${plan.windingMinutes}분을 채웠어요 (목표 $targetMinutes분)',
            en: '${plan.windingMinutes} min of winding found (target $targetMinutes min)',
            fr: '${plan.windingMinutes} min sinueuses trouvées (objectif $targetMinutes min)',
          )
        : _copy(
            language,
            ko: '목표 와인딩 시간을 채웠어요.',
            en: 'Winding target reached.',
            fr: 'Objectif sinueux atteint.',
          );
    return RevvPill(label: text, color: AppColors.warning);
  }
}

class _StateCard extends StatelessWidget {
  final String title;
  final String body;

  const _StateCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(weight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  body,
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

class _PlannerRegion {
  final String key;
  final String title;
  final LatLng point;

  const _PlannerRegion(this.key, this.title, this.point);
}

int _budgetMinutes(DriveBudget budget) {
  return switch (budget) {
    DriveBudget.any => 60,
    DriveBudget.short => 30,
    DriveBudget.medium => 60,
    DriveBudget.long => 120,
  };
}

String _coord(LatLng point) {
  return '${point.lat.toStringAsFixed(4)},${point.lng.toStringAsFixed(4)}';
}

String _minutes(AppLanguage language, int value) {
  return _copy(language, ko: '$value분', en: '$value min', fr: '$value min');
}

String _retryCopy(AppLanguage language) {
  return _copy(
    language,
    ko: '출발지나 목적지를 조정한 뒤 다시 시도해 주세요.',
    en: 'Adjust the origin or destination and try again.',
    fr: 'Ajustez le départ ou la destination puis réessayez.',
  );
}

String _copy(
  AppLanguage language, {
  String? ko,
  required String en,
  required String fr,
}) {
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
