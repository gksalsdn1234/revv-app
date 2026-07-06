import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import '../services/drive_planner_service.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../services/route_loading_policy.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../widgets/copilot_start_sheet.dart';
import '../widgets/map_widget.dart';
import '../widgets/revv_ui.dart';
import 'lean_drive_screen.dart';

typedef DrivePlannerOriginResolver =
    Future<LatLng?> Function(BuildContext context);

List<PlanMapMarker> buildPlanMapMarkers({
  required LatLng origin,
  required LatLng destination,
  required DrivePlan plan,
}) {
  return [
    PlanMapMarker(point: origin, kind: PlanMapMarkerKind.origin),
    PlanMapMarker(point: destination, kind: PlanMapMarkerKind.destination),
    for (final leg in plan.legs)
      if (leg.kind == DrivePlanLegKind.winding && leg.nodes.isNotEmpty) ...[
        PlanMapMarker(
          point: leg.nodes.first,
          kind: PlanMapMarkerKind.windingStart,
        ),
        PlanMapMarker(point: leg.nodes.last, kind: PlanMapMarkerKind.windingEnd),
      ],
  ];
}

const _plannerRegions = [
  _PlannerRegion('montreal', 'Montreal', LatLng(45.5017, -73.5673)),
  _PlannerRegion('laurentians', 'Laurentians', LatLng(45.9000, -74.1600)),
  _PlannerRegion('toronto', 'Toronto', LatLng(43.6532, -79.3832)),
  _PlannerRegion('vancouver', 'Vancouver', LatLng(49.2827, -123.1207)),
];

class LeanDrivePlannerScreen extends StatefulWidget {
  final DrivePlannerService? planner;
  final PlaceSearchService? placeSearch;
  final DrivePlannerOriginResolver? originResolver;

  /// 테스트 주입용 초기 도착 희망 시각 (프로덕션에서는 사용하지 않음)
  final TimeOfDay? initialArriveBy;

  const LeanDrivePlannerScreen({
    super.key,
    this.planner,
    this.placeSearch,
    this.originResolver,
    this.initialArriveBy,
  });

  @override
  State<LeanDrivePlannerScreen> createState() => _LeanDrivePlannerScreenState();
}

class _LeanDrivePlannerScreenState extends State<LeanDrivePlannerScreen> {
  static const _defaultOrigin = LatLng(45.5017, -73.5673);
  static const _requestTimeout = Duration(seconds: 20);

  late final DrivePlannerService _planner =
      widget.planner ?? DrivePlannerService();
  late final PlaceSearchService _placeSearch =
      widget.placeSearch ?? PlaceSearchService();
  LatLng _origin = _defaultOrigin;
  LatLng? _destination;
  String? _destinationName;
  LatLng _mapCenter = _plannerRegions.first.point;
  int _mapFocusSignal = 0;
  DriveBudget _budget = DriveBudget.short;
  List<DrivePlanOption>? _options;
  DrivePlanOptionKind _selectedKind = DrivePlanOptionKind.standard;
  late TimeOfDay? _arriveBy = widget.initialArriveBy;
  bool _loadingOrigin = true;
  bool _planning = false;
  String? _status;
  Timer? _planDebounce;
  int _planRequestId = 0;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  _PinPickTarget? _pinPickTarget;

  DrivePlan? get _plan {
    final options = _options;
    if (options == null || options.isEmpty) return null;
    return options
        .firstWhere(
          (option) => option.kind == _selectedKind,
          orElse: () => options.first,
        )
        .plan;
  }

  DateTime? get _arriveByDateTime {
    final arriveBy = _arriveBy;
    if (arriveBy == null) return null;
    final now = DateTime.now();
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      arriveBy.hour,
      arriveBy.minute,
    );
    // 이미 지난 시각이면 다음 날로 해석 (야간 계획 대비)
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  DrivePlanOption? get _recommendedOption {
    final options = _options;
    final arriveBy = _arriveByDateTime;
    if (options == null || options.isEmpty || arriveBy == null) return null;
    return recommendOptionForArrival(
      options,
      now: DateTime.now(),
      arriveBy: arriveBy,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadOrigin());
  }

  @override
  void dispose() {
    _planDebounce?.cancel();
    _sheetController.dispose();
    super.dispose();
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
    _scheduleBuildPlan();
  }

  static Future<LatLng?> _defaultOriginResolver(BuildContext context) async {
    final location = context.read<LocationService>();
    await location.requestPermission();
    await location.startTracking();
    return location.ensureLiveLocation();
  }

  Future<void> _buildPlan() async {
    final destination = _destination;
    if (destination == null || _loadingOrigin) return;
    final language = context.read<SettingsService>().appLanguage;
    final requestId = ++_planRequestId;
    setState(() {
      _planning = true;
      _status = null;
      _options = null;
    });
    try {
      final options = await _planner
          .buildPlanOptions(
            DrivePlanRequest(
              origin: _origin,
              destination: destination,
              windingBudgetMinutes: _budgetMinutes(_budget),
            ),
          )
          .timeout(_requestTimeout);
      if (!mounted || requestId != _planRequestId) return;
      setState(() {
        _options = options.isEmpty ? null : options;
        _selectedKind = DrivePlanOptionKind.standard;
        _status = options.isEmpty
            ? _copy(
                language,
                ko: '이 조건으로 여정을 만들지 못했어요.',
                en: 'Could not build a plan for this route.',
                fr: 'Impossible de créer ce trajet.',
              )
            : null;
      });
      // 도착 시각이 있으면 완주 가능한 최대 와인딩 옵션을 자동 선택
      final recommended = _recommendedOption;
      if (recommended != null && mounted) {
        setState(() => _selectedKind = recommended.kind);
      }
      _snapResultsSheetOpen();
    } catch (_) {
      if (!mounted || requestId != _planRequestId) return;
      setState(() {
        _status = _copy(
          language,
          ko: '여정 계산이 오래 걸려 중단했어요. 다시 시도해 주세요.',
          en: 'Planning took too long. Try again.',
          fr: 'Le calcul a pris trop de temps. Réessayez.',
        );
      });
    } finally {
      if (mounted && requestId == _planRequestId) {
        setState(() => _planning = false);
      }
    }
  }

  void _scheduleBuildPlan() {
    _planDebounce?.cancel();
    if (_destination == null || _loadingOrigin) return;
    _planDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_buildPlan());
    });
  }

  Future<void> _pickArriveBy() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _arriveBy ?? TimeOfDay.now(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _arriveBy = picked;
      final recommended = _recommendedOption;
      if (recommended != null) _selectedKind = recommended.kind;
    });
    _scheduleBuildPlan();
  }

  void _clearArriveBy() {
    setState(() => _arriveBy = null);
    _scheduleBuildPlan();
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
    final destination = _destination;
    if (plan == null || destination == null) return;
    final language = context.read<SettingsService>().appLanguage;
    final waypoints = plan.waypoints.length <= 2
        ? const <LatLng>[]
        : plan.waypoints.sublist(1, plan.waypoints.length - 1);
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': _coord(_origin),
      'destination': _coord(destination),
      if (waypoints.isNotEmpty) 'waypoints': waypoints.map(_coord).join('|'),
      'travelmode': 'driving',
    });
    final appUri = buildGoogleMapsAppUri(
      origin: _origin,
      destination: destination,
      waypoints: waypoints,
    );
    var launched = false;
    try {
      launched = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(
          webUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      launched = false;
    }
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppCopy.navigationOpenFailed(language))),
    );
  }

  int get _selectedOptionBudget {
    final options = _options;
    if (options == null || options.isEmpty) return _budgetMinutes(_budget);
    return options
        .firstWhere(
          (option) => option.kind == _selectedKind,
          orElse: () => options.first,
        )
        .budgetMinutes;
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

  List<PlanMapMarker> get _planMarkers {
    final plan = _plan;
    final destination = _destination;
    if (plan == null || destination == null) return const [];
    return buildPlanMapMarkers(
      origin: _origin,
      destination: destination,
      plan: plan,
    );
  }

  List<LatLng> _planPolyline(DrivePlanLegKind kind) {
    final plan = _plan;
    if (plan == null) return const [];
    return [
      for (final leg in plan.legs)
        if (leg.kind == kind) ...leg.nodes,
    ];
  }

  Future<void> _openOriginPicker() async {
    final choice = await showModalBottomSheet<_OriginChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OriginPickerSheet(
        language: context.read<SettingsService>().appLanguage,
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _OriginChoice.currentLocation) {
      setState(() {
        _pinPickTarget = null;
        _loadingOrigin = true;
        _options = null;
        _status = null;
      });
      unawaited(_loadOrigin());
      return;
    }
    _startPinPicking(_PinPickTarget.origin);
  }

  Future<void> _openDestinationSearch() async {
    final language = context.read<SettingsService>().appLanguage;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlaceSearchSheet(
        language: language,
        service: _placeSearch,
        proximity: _origin,
        selected: _destination,
      ),
    );
    if (!mounted || result == null) return;
    if (result is _MapPinSelection) {
      _startPinPicking(_PinPickTarget.destination);
      return;
    }
    if (result is! PlaceResult) return;
    setState(() {
      _destination = result.point;
      _destinationName = result.name;
      _mapCenter = result.point;
      _mapFocusSignal++;
      _options = null;
      _status = null;
    });
    _scheduleBuildPlan();
  }

  void _startPinPicking(_PinPickTarget target) {
    setState(() => _pinPickTarget = target);
  }

  void _confirmPinPick() {
    final target = _pinPickTarget;
    if (target == null) return;
    final language = context.read<SettingsService>().appLanguage;
    setState(() {
      if (target == _PinPickTarget.origin) {
        _origin = _mapCenter;
      } else {
        _destination = _mapCenter;
        _destinationName = _mapPinLabel(language);
      }
      _pinPickTarget = null;
      _options = null;
      _status = null;
    });
    _scheduleBuildPlan();
  }

  void _snapResultsSheetOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sheetController.isAttached || _sheetController.size >= 0.42) {
        return;
      }
      unawaited(
        _sheetController.animateTo(
          0.42,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final options = _options;
    final plan = _plan;
    final status = _status;
    final recommended = _recommendedOption;
    final arriveBy = _arriveByDateTime;
    final pinPicking = _pinPickTarget != null;
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
              curveHeatmap: false,
              planMarkers: _planMarkers,
              cameraTarget: _mapCenter,
              cameraTargetSignal: _mapFocusSignal,
              onCameraCenterChanged: (point) => _mapCenter = point,
            ),
          ),
          _PlannerSheet(
            controller: _sheetController,
            language: language,
            destination: _destination,
            destinationName: _destinationName,
            loadingOrigin: _loadingOrigin,
            budget: _budget,
            arriveByTime: _arriveBy,
            planning: _planning,
            status: status,
            options: options,
            plan: plan,
            recommended: recommended,
            arriveBy: arriveBy,
            selectedKind: _selectedKind,
            selectedOptionBudget: _selectedOptionBudget,
            canStart: _firstWindingRoute != null,
            onOrigin: _openOriginPicker,
            onSearchDestination: _openDestinationSearch,
            onBudget: (value) {
              setState(() {
                _budget = value;
                _options = null;
                _status = null;
              });
              _scheduleBuildPlan();
            },
            onPickArriveBy: _pickArriveBy,
            onClearArriveBy: _clearArriveBy,
            onSelectedOption: (kind) => setState(() => _selectedKind = kind),
            onStart: _startFirstWinding,
            onNavigate: _openExternalNavigation,
          ),
          if (pinPicking)
            const Center(
              child: Icon(
                Icons.location_pin,
                color: AppColors.primaryContainer,
                size: 40,
              ),
            ),
          if (pinPicking)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              child: RevvPrimaryButton(
                label: _copy(
                  language,
                  ko: '이 지점으로',
                  en: 'Use this spot',
                  fr: 'Utiliser ce point',
                ),
                icon: Icons.check_rounded,
                onPressed: _confirmPinPick,
              ),
            ),
        ],
      ),
    );
  }
}

enum _PinPickTarget { origin, destination }

class _MapPinSelection {
  const _MapPinSelection();
}

class _PlannerSheet extends StatelessWidget {
  final DraggableScrollableController controller;
  final AppLanguage language;
  final LatLng? destination;
  final String? destinationName;
  final bool loadingOrigin;
  final DriveBudget budget;
  final TimeOfDay? arriveByTime;
  final bool planning;
  final String? status;
  final List<DrivePlanOption>? options;
  final DrivePlan? plan;
  final DrivePlanOption? recommended;
  final DateTime? arriveBy;
  final DrivePlanOptionKind selectedKind;
  final int selectedOptionBudget;
  final bool canStart;
  final VoidCallback onOrigin;
  final VoidCallback onSearchDestination;
  final ValueChanged<DriveBudget> onBudget;
  final VoidCallback onPickArriveBy;
  final VoidCallback onClearArriveBy;
  final ValueChanged<DrivePlanOptionKind> onSelectedOption;
  final VoidCallback onStart;
  final VoidCallback onNavigate;

  const _PlannerSheet({
    required this.controller,
    required this.language,
    required this.destination,
    required this.destinationName,
    required this.loadingOrigin,
    required this.budget,
    required this.arriveByTime,
    required this.planning,
    required this.status,
    required this.options,
    required this.plan,
    required this.recommended,
    required this.arriveBy,
    required this.selectedKind,
    required this.selectedOptionBudget,
    required this.canStart,
    required this.onOrigin,
    required this.onSearchDestination,
    required this.onBudget,
    required this.onPickArriveBy,
    required this.onClearArriveBy,
    required this.onSelectedOption,
    required this.onStart,
    required this.onNavigate,
  });

  bool get _hasResult => options != null && plan != null;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: 0.42,
      minChildSize: 0.18,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.18, 0.42, 0.85],
      builder: (context, scrollController) {
        final bottomPadding = MediaQuery.paddingOf(context).bottom;
        return RevvGlassCard(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          padding: EdgeInsets.zero,
          radius: 18,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  children: [
                    const _SheetHandle(),
                    if (planning)
                      _PlanningCard(language: language, framed: false)
                    else if (status != null)
                      _StateCard(title: status!, body: _retryCopy(language))
                    else if (_hasResult)
                      KeyedSubtree(
                        key: const Key('planner-results-sheet'),
                        child: _ResultSheetBody(
                          language: language,
                          destinationName: destinationName,
                          options: options!,
                          plan: plan!,
                          recommended: recommended,
                          arriveBy: arriveBy,
                          selectedKind: selectedKind,
                          selectedOptionBudget: selectedOptionBudget,
                          onSearchDestination: onSearchDestination,
                          onSelectedOption: onSelectedOption,
                        ),
                      )
                    else
                      _InputSheetBody(
                        language: language,
                        destination: destination,
                        destinationName: destinationName,
                        loadingOrigin: loadingOrigin,
                        budget: budget,
                        arriveBy: arriveByTime,
                        onOrigin: onOrigin,
                        onSearchDestination: onSearchDestination,
                        onBudget: onBudget,
                        onPickArriveBy: onPickArriveBy,
                        onClearArriveBy: onClearArriveBy,
                      ),
                  ],
                ),
              ),
              if (_hasResult)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
                  child: Row(
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
                          onPressed: canStart ? onStart : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Tooltip(
                        message: _copy(
                          language,
                          ko: '외부 내비',
                          en: 'Open nav',
                          fr: 'Navigation',
                        ),
                        child: OutlinedButton(
                          onPressed: onNavigate,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColors.outline.withValues(alpha: 0.28),
                            ),
                            foregroundColor: AppColors.textPrimary,
                            minimumSize: const Size(52, 52),
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.navigation_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.outlineVariant.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _InputSheetBody extends StatelessWidget {
  final AppLanguage language;
  final LatLng? destination;
  final String? destinationName;
  final bool loadingOrigin;
  final DriveBudget budget;
  final VoidCallback onOrigin;
  final VoidCallback onSearchDestination;
  final ValueChanged<DriveBudget> onBudget;
  final TimeOfDay? arriveBy;
  final VoidCallback onPickArriveBy;
  final VoidCallback onClearArriveBy;

  const _InputSheetBody({
    required this.language,
    required this.destination,
    required this.destinationName,
    required this.loadingOrigin,
    required this.budget,
    required this.onOrigin,
    required this.onSearchDestination,
    required this.onBudget,
    required this.arriveBy,
    required this.onPickArriveBy,
    required this.onClearArriveBy,
  });

  @override
  Widget build(BuildContext context) {
    final hasDestination = destination != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onSearchDestination,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasDestination
                        ? destinationName ?? _mapPinLabel(language)
                        : _copy(
                            language,
                            ko: '어디로 갈까요?',
                            en: 'Where to?',
                            fr: 'Destination ?',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      size: 17,
                      weight: FontWeight.w900,
                      color: hasDestination
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _BudgetRow(
          language: language,
          budget: budget,
          arriveBy: arriveBy,
          onBudget: onBudget,
          onPickArriveBy: onPickArriveBy,
          onClearArriveBy: onClearArriveBy,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onOrigin,
          icon: const Icon(Icons.my_location_rounded, size: 16),
          label: Text(
            loadingOrigin
                ? _copy(
                    language,
                    ko: '출발: 확인 중 ▾',
                    en: 'From: locating ▾',
                    fr: 'Départ : position ▾',
                  )
                : _copy(
                    language,
                    ko: '출발: 현위치 ▾',
                    en: 'From: current ▾',
                    fr: 'Départ : position ▾',
                  ),
            style: AppText.body(
              size: 12,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final AppLanguage language;
  final DriveBudget budget;
  final TimeOfDay? arriveBy;
  final ValueChanged<DriveBudget> onBudget;
  final VoidCallback onPickArriveBy;
  final VoidCallback onClearArriveBy;

  const _BudgetRow({
    required this.language,
    required this.budget,
    required this.arriveBy,
    required this.onBudget,
    required this.onPickArriveBy,
    required this.onClearArriveBy,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          const Icon(
            Icons.timer_outlined,
            color: AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 8),
          for (final item in const [
            DriveBudget.short,
            DriveBudget.medium,
            DriveBudget.long,
          ]) ...[
            _BudgetPill(
              label: _compactBudgetLabel(item, language),
              selected: budget == item,
              onTap: () => onBudget(item),
            ),
            const SizedBox(width: 6),
          ],
          if (arriveBy == null)
            IconButton(
              tooltip: _copy(
                language,
                ko: '도착 시각',
                en: 'Arrive by',
                fr: 'Arrivée',
              ),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.schedule_rounded, size: 20),
              color: AppColors.textPrimary,
              onPressed: onPickArriveBy,
            )
          else
            InputChip(
              label: Text('~${_formatTimeOfDay(arriveBy!)}'),
              onPressed: onPickArriveBy,
              onDeleted: onClearArriveBy,
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surface.withValues(alpha: 0.9),
              labelStyle: AppText.body(size: 12, weight: FontWeight.w900),
              side: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultSheetBody extends StatelessWidget {
  final AppLanguage language;
  final String? destinationName;
  final List<DrivePlanOption> options;
  final DrivePlan plan;
  final DrivePlanOption? recommended;
  final DateTime? arriveBy;
  final DrivePlanOptionKind selectedKind;
  final int selectedOptionBudget;
  final VoidCallback onSearchDestination;
  final ValueChanged<DrivePlanOptionKind> onSelectedOption;

  const _ResultSheetBody({
    required this.language,
    required this.destinationName,
    required this.options,
    required this.plan,
    required this.recommended,
    required this.arriveBy,
    required this.selectedKind,
    required this.selectedOptionBudget,
    required this.onSearchDestination,
    required this.onSelectedOption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _planHeader(plan, language),
          style: AppText.body(size: 19, weight: FontWeight.w900, height: 1.1),
        ),
        const SizedBox(height: 12),
        _PlanOptionStrip(
          options: options,
          selected: selectedKind,
          recommended: recommended?.kind,
          language: language,
          onSelected: onSelectedOption,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                destinationName ?? _mapPinLabel(language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 13, weight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: onSearchDestination,
              child: Text(
                _copy(language, ko: '변경', en: 'Change', fr: 'Modifier'),
              ),
            ),
          ],
        ),
        Divider(
          height: 18,
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
        if (arriveBy != null && recommended == null)
          _ArrivalInfeasibleCard(
            options: options,
            arriveBy: arriveBy!,
            language: language,
          ),
        _PlanResultCard(
          plan: plan,
          language: language,
          targetMinutes: selectedOptionBudget,
        ),
      ],
    );
  }
}

class _PlaceSearchSheet extends StatefulWidget {
  final AppLanguage language;
  final PlaceSearchService service;
  final LatLng proximity;
  final LatLng? selected;

  const _PlaceSearchSheet({
    required this.language,
    required this.service,
    required this.proximity,
    required this.selected,
  });

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_search(query));
    });
  }

  Future<void> _search(String query) async {
    if (!widget.service.isEnabled) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _hasSearched = true;
      });
      return;
    }

    setState(() {
      _searching = true;
      _hasSearched = true;
    });
    final results = await widget.service.searchPlaces(
      query,
      proximity: widget.proximity,
      language: _languageCode(widget.language),
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: RevvGlassCard(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        radius: 18,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _copy(
                        widget.language,
                        ko: '장소 검색',
                        en: 'Place search',
                        fr: 'Recherche de lieu',
                      ),
                      style: AppText.body(size: 18, weight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textHint,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('planner-place-search-field'),
                controller: _controller,
                enabled: widget.service.isEnabled,
                autofocus: widget.service.isEnabled,
                onChanged: _onQueryChanged,
                style: AppText.body(weight: FontWeight.w800),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _copy(
                    widget.language,
                    ko: '목적지 이름 입력',
                    en: 'Search by destination name',
                    fr: 'Nom de la destination',
                  ),
                  hintStyle: AppText.body(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surface.withValues(alpha: 0.88),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.28),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.28),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.red),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, const _MapPinSelection()),
                icon: const Icon(Icons.location_pin, size: 18),
                label: Text(
                  _copy(
                    widget.language,
                    ko: '지도 핀으로 지정',
                    en: 'Use map pin',
                    fr: 'Utiliser le repère',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.28),
                  ),
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: _buildResults(),
              ),
              const SizedBox(height: 10),
              _RegionStrip(
                language: widget.language,
                selected: widget.selected,
                onSelected: (region) => Navigator.pop(
                  context,
                  PlaceResult(
                    name: region.title,
                    address: '',
                    point: region.point,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!widget.service.isEnabled || (_hasSearched && _results.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _copy(
            widget.language,
            ko: '찾지 못했어요 — 지도 핀으로 지정할 수도 있어요',
            en: 'No place found — you can also set it with the map pin',
            fr: 'Aucun lieu trouvé — vous pouvez aussi utiliser le repère',
          ),
          style: AppText.body(size: 13, color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: AppColors.outlineVariant.withValues(alpha: 0.18),
      ),
      itemBuilder: (context, index) {
        final result = _results[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.place_rounded,
            color: AppColors.primaryContainer,
          ),
          title: Text(
            result.name,
            style: AppText.body(size: 14, weight: FontWeight.w900),
          ),
          subtitle: result.address.isEmpty
              ? null
              : Text(
                  result.address,
                  style: AppText.body(size: 12, color: AppColors.textSecondary),
                ),
          onTap: () => Navigator.pop(context, result),
        );
      },
    );
  }
}

enum _OriginChoice { currentLocation, mapPin }

class _OriginPickerSheet extends StatelessWidget {
  final AppLanguage language;

  const _OriginPickerSheet({required this.language});

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      radius: 18,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location_rounded),
              title: Text(
                _copy(language, ko: '현위치', en: 'Current', fr: 'Position'),
                style: AppText.body(weight: FontWeight.w900),
              ),
              onTap: () =>
                  Navigator.pop(context, _OriginChoice.currentLocation),
            ),
            ListTile(
              leading: const Icon(Icons.location_pin),
              title: Text(
                _copy(language, ko: '지도 핀', en: 'Map pin', fr: 'Repère'),
                style: AppText.body(weight: FontWeight.w900),
              ),
              onTap: () => Navigator.pop(context, _OriginChoice.mapPin),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BudgetPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: AppColors.primaryContainer,
      backgroundColor: AppColors.surface.withValues(alpha: 0.88),
      labelStyle: AppText.body(
        size: 12,
        weight: FontWeight.w900,
        color: selected ? AppColors.onPrimary : AppColors.textPrimary,
      ),
      side: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
    );
  }
}

class _RegionStrip extends StatelessWidget {
  final AppLanguage language;
  final LatLng? selected;
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
          final selectedPoint = selected;
          final active =
              selectedPoint != null &&
              region.point.lat == selectedPoint.lat &&
              region.point.lng == selectedPoint.lng;
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

  const _PlanResultCard({
    required this.plan,
    required this.language,
    required this.targetMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.usesApproximateTransit) ...[
          Text(
            _copy(
              language,
              ko: '대략 경로 · 실제 내비에서 도로 경로를 확인하세요',
              en: 'Approximate route · confirm roads in navigation',
              fr: 'Trajet approximatif · vérifiez dans la navigation',
            ),
            style: AppText.body(size: 12, color: AppColors.warning),
          ),
          const SizedBox(height: 12),
        ],
        ...plan.legs.map((leg) => _TimelineLeg(leg: leg, language: language)),
        const SizedBox(height: 10),
        _PlanHonestyLine(
          plan: plan,
          language: language,
          targetMinutes: targetMinutes,
        ),
      ],
    );
  }
}

class _TimelineLeg extends StatelessWidget {
  final DrivePlanLeg leg;
  final AppLanguage language;

  const _TimelineLeg({required this.leg, required this.language});

  @override
  Widget build(BuildContext context) {
    final title = switch (leg.kind) {
      DrivePlanLegKind.winding =>
        '${leg.route == null ? _copy(language, ko: '와인딩 루트', en: 'Winding route', fr: 'Route sinueuse') : routeDisplayName(leg.route!, language: language)} ${_minutes(language, leg.estimatedMinutes)}',
      DrivePlanLegKind.rest => _copy(
        language,
        ko: '휴식 ${leg.estimatedMinutes}분',
        en: 'Rest ${leg.estimatedMinutes} min',
        fr: 'Pause ${leg.estimatedMinutes} min',
      ),
      DrivePlanLegKind.transit => _copy(
        language,
        ko: '이동 ${leg.estimatedMinutes}분',
        en: 'Transit ${leg.estimatedMinutes} min',
        fr: 'Liaison ${leg.estimatedMinutes} min',
      ),
    };
    final icon = switch (leg.kind) {
      DrivePlanLegKind.winding => Icons.route_rounded,
      DrivePlanLegKind.rest => Icons.local_cafe_rounded,
      DrivePlanLegKind.transit => Icons.near_me_rounded,
    };
    final color = switch (leg.kind) {
      DrivePlanLegKind.winding => AppColors.primaryContainer,
      DrivePlanLegKind.rest => AppColors.warning,
      DrivePlanLegKind.transit => AppColors.cyan,
    };
    final dotColor = switch (leg.kind) {
      DrivePlanLegKind.winding => AppColors.red,
      DrivePlanLegKind.transit => const Color(0xFF6DA3FF),
      DrivePlanLegKind.rest => null,
    };
    final dotKey = switch (leg.kind) {
      DrivePlanLegKind.winding => const Key('timeline-dot-winding'),
      DrivePlanLegKind.transit => const Key('timeline-dot-transit'),
      DrivePlanLegKind.rest => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              key: dotKey,
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(icon, size: 17, color: color),
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

class _PlanOptionStrip extends StatelessWidget {
  final List<DrivePlanOption> options;
  final DrivePlanOptionKind selected;
  final DrivePlanOptionKind? recommended;
  final AppLanguage language;
  final ValueChanged<DrivePlanOptionKind> onSelected;

  const _PlanOptionStrip({
    required this.options,
    required this.selected,
    required this.recommended,
    required this.language,
    required this.onSelected,
  });

  String _optionLabel(DrivePlanOption option) {
    final name = switch (option.kind) {
      DrivePlanOptionKind.light => _copy(
        language,
        ko: '가볍게',
        en: 'Shorter',
        fr: 'Court',
      ),
      DrivePlanOptionKind.standard => _copy(
        language,
        ko: '기본',
        en: 'Standard',
        fr: 'Standard',
      ),
      DrivePlanOptionKind.extended => _copy(
        language,
        ko: '길게',
        en: 'Longer',
        fr: 'Long',
      ),
    };
    return '$name ${option.plan.totalMinutes}${_copy(language, ko: '분', en: 'm', fr: 'min')}';
  }

  @override
  Widget build(BuildContext context) {
    // 옵션이 3개뿐이라 lazy build 없이 전부 렌더 (오프스크린 칩 접근성 보장)
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final option in options) ...[
            _optionChip(option),
            if (option != options.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _optionChip(DrivePlanOption option) {
    final active = option.kind == selected;
    final isRecommended = option.kind == recommended;
    return ChoiceChip(
      avatar: isRecommended
          ? const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: AppColors.gold,
            )
          : null,
      label: Text(
        isRecommended
            ? '${_optionLabel(option)} · ${_copy(language, ko: '추천', en: 'Fits', fr: 'Adapté')}'
            : _optionLabel(option),
      ),
      selected: active,
      onSelected: (_) => onSelected(option.kind),
      selectedColor: AppColors.primaryContainer,
      backgroundColor: AppColors.panel2.withValues(alpha: 0.92),
      labelStyle: AppText.body(
        size: 12,
        weight: FontWeight.w800,
        color: active ? AppColors.onPrimary : AppColors.textPrimary,
      ),
    );
  }
}

class _ArrivalInfeasibleCard extends StatelessWidget {
  final List<DrivePlanOption> options;
  final DateTime arriveBy;
  final AppLanguage language;

  const _ArrivalInfeasibleCard({
    required this.options,
    required this.arriveBy,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final availableMinutes = arriveBy.difference(DateTime.now()).inMinutes;
    final lightest = options.reduce(
      (a, b) => a.plan.totalMinutes <= b.plan.totalMinutes ? a : b,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _StateCard(
        title: _copy(
          language,
          ko: '희망 시각까지 맞는 여정이 없어요',
          en: 'No plan fits the arrival time',
          fr: 'Aucun trajet ne convient à cette heure',
        ),
        body: _copy(
          language,
          ko: '남은 시간 $availableMinutes분, 가장 가벼운 여정도 ${lightest.plan.totalMinutes}분이 필요해요. 도착 시각을 늦추거나 목적지를 조정해 보세요.',
          en: '$availableMinutes min left, but the lightest plan needs ${lightest.plan.totalMinutes} min. Push the arrival time or adjust the destination.',
          fr: '$availableMinutes min restantes, mais le trajet le plus court demande ${lightest.plan.totalMinutes} min. Décalez l’arrivée ou ajustez la destination.',
        ),
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
            ko: '와인딩 ${plan.windingMinutes}/$targetMinutes분',
            en: 'Winding ${plan.windingMinutes}/$targetMinutes min',
            fr: 'Sinueux ${plan.windingMinutes}/$targetMinutes min',
          )
        : _copy(
            language,
            ko: '와인딩 ${plan.windingMinutes}/$targetMinutes분',
            en: 'Winding ${plan.windingMinutes}/$targetMinutes min',
            fr: 'Sinueux ${plan.windingMinutes}/$targetMinutes min',
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

class _PlanningCard extends StatelessWidget {
  final AppLanguage language;
  final bool framed;

  const _PlanningCard({required this.language, this.framed = true});

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          _copy(language, ko: '계산 중', en: 'Planning', fr: 'Calcul'),
          style: AppText.body(weight: FontWeight.w900),
        ),
      ],
    );
    if (!framed) return content;
    return RevvGlassCard(child: content);
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

String _mapPinLabel(AppLanguage language) {
  return _copy(
    language,
    ko: '지도에서 선택한 지점',
    en: 'Picked on map',
    fr: 'Point sur la carte',
  );
}

String _compactBudgetLabel(DriveBudget budget, AppLanguage language) {
  return switch (budget) {
    DriveBudget.short => _copy(language, ko: '30분', en: '30m', fr: '30 min'),
    DriveBudget.medium => _copy(language, ko: '1시간', en: '1h', fr: '1 h'),
    DriveBudget.long => _copy(language, ko: '2시간+', en: '2h+', fr: '2 h+'),
    DriveBudget.any => _copy(language, ko: '전체', en: 'Any', fr: 'Tout'),
  };
}

Uri buildGoogleMapsAppUri({
  required LatLng origin,
  required LatLng destination,
  required List<LatLng> waypoints,
}) {
  return Uri(
    scheme: 'comgooglemapsurl',
    host: 'www.google.com',
    path: '/maps/dir/',
    queryParameters: {
      'api': '1',
      'saddr': _coord(origin),
      'daddr': _coord(destination),
      if (waypoints.isNotEmpty) 'waypoints': waypoints.map(_coord).join('|'),
      'directionsmode': 'driving',
    },
  );
}

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _planHeader(DrivePlan plan, AppLanguage language) {
  final eta = DateTime.now().add(Duration(minutes: plan.totalMinutes));
  return _copy(
    language,
    ko: '도착 ~${_formatClock(eta)} · ${plan.totalMinutes}분 · 와인딩 ${plan.windingMinutes}분',
    en: 'Arrive ~${_formatClock(eta)} · ${plan.totalMinutes} min · Winding ${plan.windingMinutes} min',
    fr: 'Arrivée ~${_formatClock(eta)} · ${plan.totalMinutes} min · Sinueux ${plan.windingMinutes} min',
  );
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

String _languageCode(AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => 'ko',
    AppLanguage.english => 'en',
    AppLanguage.french => 'fr',
  };
}

String _copy(
  AppLanguage language, {
  String? ko,
  required String en,
  required String fr,
}) {
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
