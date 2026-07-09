import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import '../services/drive_planner_service.dart';
import '../services/external_nav.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../services/recommendation_log_service.dart';
import '../services/route_loading_policy.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../widgets/copilot_start_sheet.dart';
import '../widgets/journey_sheet.dart';
import '../widgets/map_widget.dart';
import '../widgets/place_search_sheet.dart';
import '../widgets/revv_ui.dart';
import 'lean_drive_screen.dart';

typedef DrivePlannerOriginResolver =
    Future<LatLng?> Function(BuildContext context);

List<PlanMapMarker> buildPlanMapMarkers({
  required LatLng origin,
  required LatLng destination,
  required DrivePlan plan,
}) {
  return buildJourneyPlanMapMarkers(
    origin: origin,
    destination: destination,
    plan: plan,
  );
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
  final DrivePlan? initialPlan;
  final List<RevvRoute> initialRoutes;
  final LatLng? initialOrigin;
  final LatLng? initialDestination;
  final String? initialDestinationName;
  final RecommendationLogService? recommendationLogService;

  /// 테스트 주입용 초기 도착 희망 시각 (프로덕션에서는 사용하지 않음)
  final TimeOfDay? initialArriveBy;

  const LeanDrivePlannerScreen({
    super.key,
    this.planner,
    this.placeSearch,
    this.originResolver,
    this.initialPlan,
    this.initialRoutes = const [],
    this.initialOrigin,
    this.initialDestination,
    this.initialDestinationName,
    this.recommendationLogService,
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
  late final RecommendationLogService _recommendationLog =
      widget.recommendationLogService ?? RecommendationLogService();
  LatLng _origin = _defaultOrigin;
  LatLng? _destination;
  String? _destinationName;
  LatLng _mapCenter = _plannerRegions.first.point;
  int _mapFocusSignal = 0;
  DriveBudget _budget = DriveBudget.medium;
  List<DrivePlanOption>? _options;
  List<FreeRoamOption>? _freeRoamOptions;
  DrivePlanOptionKind _selectedKind = DrivePlanOptionKind.standard;
  int _selectedFreeRoamIndex = 0;
  bool _freeRoamActive = false;
  late TimeOfDay? _arriveBy = widget.initialArriveBy;
  bool _loadingOrigin = true;
  bool _planning = false;
  String? _status;
  Timer? _planDebounce;
  int _planRequestId = 0;
  String? _lastShownSignature;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final DraggableScrollableController _journeySheetController =
      DraggableScrollableController();
  _PinPickTarget? _pinPickTarget;

  bool get _usesInjectedRoutes => widget.initialRoutes.isNotEmpty;

  DrivePlan? get _plan {
    final freeOptions = _freeRoamOptions;
    if (_freeRoamActive && freeOptions != null && freeOptions.isNotEmpty) {
      final index = _selectedFreeRoamIndex
          .clamp(0, freeOptions.length - 1)
          .toInt();
      return freeOptions[index].plan;
    }
    final options = _options;
    if (options == null || options.isEmpty) return null;
    return options
        .firstWhere(
          (option) => option.kind == _selectedKind,
          orElse: () => options.first,
        )
        .plan;
  }

  LatLng? get _planDestination {
    if (_freeRoamActive && _plan != null) return _origin;
    return _destination;
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
    final initialPlan = widget.initialPlan;
    if (initialPlan != null) {
      _origin = widget.initialOrigin ?? initialPlan.waypoints.first;
      _destination = widget.initialDestination ?? initialPlan.waypoints.last;
      _destinationName = widget.initialDestinationName;
      _mapCenter = _destination ?? _origin;
      _options = [
        DrivePlanOption(
          kind: DrivePlanOptionKind.standard,
          budgetMinutes: initialPlan.windingMinutes,
          plan: initialPlan,
        ),
      ];
      _loadingOrigin = false;
      unawaited(_logShownOnce(mode: 'chain', options: _options!));
      _snapResultsSheetOpen();
      return;
    }
    unawaited(_loadOrigin());
  }

  @override
  void dispose() {
    _planDebounce?.cancel();
    _sheetController.dispose();
    _journeySheetController.dispose();
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
      _freeRoamOptions = null;
      _freeRoamActive = false;
    });
    try {
      final options = _usesInjectedRoutes
          ? await _buildInjectedRouteOptions(destination)
          : await _planner
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
      final recommended = _usesInjectedRoutes ? null : _recommendedOption;
      if (recommended != null && mounted) {
        setState(() => _selectedKind = recommended.kind);
      }
      if (options.isNotEmpty) {
        unawaited(_logShownOnce(mode: 'destination', options: options));
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

  Future<void> _buildFreeRoamPlan() async {
    if (_loadingOrigin) return;
    final language = context.read<SettingsService>().appLanguage;
    final requestId = ++_planRequestId;
    setState(() {
      _planning = true;
      _status = null;
      _options = null;
      _freeRoamOptions = null;
      _freeRoamActive = true;
      _selectedFreeRoamIndex = 0;
    });
    try {
      final options = await _planner
          .buildFreeRoamOptions(
            origin: _origin,
            totalBudgetMinutes: _budgetMinutes(_budget),
          )
          .timeout(_requestTimeout);
      if (!mounted || requestId != _planRequestId) return;
      setState(() {
        _freeRoamOptions = options.isEmpty ? null : options;
        _status = options.isEmpty
            ? _copy(
                language,
                ko: '이 시간 안에 추천 루프를 만들지 못했어요.',
                en: 'Could not build a loop for this time.',
                fr: 'Impossible de créer une boucle pour cette durée.',
              )
            : null;
      });
      if (options.isNotEmpty) {
        unawaited(_logShownOnce(mode: 'free', freeRoamOptions: options));
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
    if (_loadingOrigin) return;
    if (!_freeRoamActive && _destination == null) return;
    _planDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(_freeRoamActive ? _buildFreeRoamPlan() : _buildPlan());
    });
  }

  Future<List<DrivePlanOption>> _buildInjectedRouteOptions(
    LatLng destination,
  ) async {
    final plan = await _planner
        .buildPlanFromRoutes(
          origin: _origin,
          routes: widget.initialRoutes,
          destination: destination,
        )
        .timeout(_requestTimeout);
    return [
      DrivePlanOption(
        kind: DrivePlanOptionKind.standard,
        budgetMinutes: plan.windingMinutes,
        plan: plan,
      ),
    ];
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
    unawaited(
      _recommendationLog.logChosen(
        mode: _recommendationMode,
        routeId: route.id,
        optionKind: _freeRoamActive ? 'free' : _selectedKind.key,
        origin: _origin,
        budgetMinutes: _selectedOptionBudget,
      ),
    );
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
    final destination = _planDestination;
    if (plan == null || destination == null) return;
    final language = context.read<SettingsService>().appLanguage;
    final waypoints = selectHandoffWaypoints(legs: plan.legs);
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': googleMapsCoord(_origin),
      'destination': googleMapsCoord(destination),
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map(googleMapsCoord).join('|'),
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

  Future<void> _logShownOnce({
    required String mode,
    List<DrivePlanOption>? options,
    List<FreeRoamOption>? freeRoamOptions,
  }) async {
    final destinationOptions = options ?? const <DrivePlanOption>[];
    final freeOptions = freeRoamOptions ?? const <FreeRoamOption>[];
    final budgetMinutes = mode == 'chain'
        ? destinationOptions.first.budgetMinutes
        : _budgetMinutes(_budget);
    final signature = _shownSignature(mode, budgetMinutes);
    if (_lastShownSignature == signature) return;
    _lastShownSignature = signature;
    final routeIds = mode == 'free'
        ? _freeRoamRouteIds(freeOptions)
        : _windingRouteIds(destinationOptions);
    await _recommendationLog.logShown(
      mode: mode,
      routeIds: routeIds,
      origin: _origin,
      budgetMinutes: budgetMinutes,
    );
  }

  String get _recommendationMode => _freeRoamActive
      ? 'free'
      : widget.initialPlan == null
      ? 'destination'
      : 'chain';

  String _shownSignature(String mode, int budgetMinutes) {
    final destination = _destination;
    final destinationKey = destination == null
        ? 'none'
        : '${destination.lat.toStringAsFixed(5)},${destination.lng.toStringAsFixed(5)}';
    return '$mode:$destinationKey:$budgetMinutes';
  }

  int get _selectedOptionBudget {
    final freeOptions = _freeRoamOptions;
    if (_freeRoamActive && freeOptions != null && freeOptions.isNotEmpty) {
      final index = _selectedFreeRoamIndex
          .clamp(0, freeOptions.length - 1)
          .toInt();
      return freeOptions[index].budgetMinutes;
    }
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

  List<List<LatLng>> get _transitPolylines =>
      _planPolylines(DrivePlanLegKind.transit);

  List<List<LatLng>> get _windingPolylines =>
      _planPolylines(DrivePlanLegKind.winding);

  List<PlanMapMarker> get _planMarkers {
    final plan = _plan;
    final destination = _planDestination;
    if (plan == null || destination == null) return const [];
    return buildPlanMapMarkers(
      origin: _origin,
      destination: destination,
      plan: plan,
    );
  }

  List<List<LatLng>> _planPolylines(DrivePlanLegKind kind) {
    final plan = _plan;
    if (plan == null) return const [];
    return [
      for (final leg in plan.legs)
        if (leg.kind == kind && leg.nodes.isNotEmpty) leg.nodes,
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
        _freeRoamOptions = null;
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
      builder: (context) => PlaceSearchSheet(
        language: language,
        service: _placeSearch,
        proximity: _origin,
        selected: _destination,
      ),
    );
    if (!mounted || result == null) return;
    if (result is PlaceSearchMapPinSelection) {
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
      _freeRoamOptions = null;
      _freeRoamActive = false;
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
        _freeRoamActive = false;
      }
      _pinPickTarget = null;
      _options = null;
      _freeRoamOptions = null;
      _status = null;
    });
    _scheduleBuildPlan();
  }

  void _snapResultsSheetOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _journeySheetController.isAttached
          ? _journeySheetController
          : _sheetController;
      if (!controller.isAttached || controller.size >= 0.42) {
        return;
      }
      unawaited(
        controller.animateTo(
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
    final freeRoamOptions = _freeRoamOptions;
    final plan = _plan;
    final status = _status;
    final recommended = _recommendedOption;
    final arriveBy = _arriveByDateTime;
    final pinPicking = _pinPickTarget != null;
    final hasResult =
        ((options != null && options.isNotEmpty) ||
            (freeRoamOptions != null && freeRoamOptions.isNotEmpty)) &&
        plan != null;
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
              navPolylines: _transitPolylines,
              routePolylines: _windingPolylines,
              curveHeatmap: false,
              planMarkers: _planMarkers,
              cameraTarget: _mapCenter,
              cameraTargetSignal: _mapFocusSignal,
              onCameraCenterChanged: (point) => _mapCenter = point,
            ),
          ),
          if (hasResult)
            JourneySheet(
              controller: _journeySheetController,
              language: language,
              destinationName: _destinationName,
              options: options,
              freeRoamOptions: freeRoamOptions,
              plan: plan,
              recommended: recommended,
              arriveBy: arriveBy,
              selectedKind: _selectedKind,
              selectedFreeRoamIndex: _selectedFreeRoamIndex,
              selectedOptionBudget: _selectedOptionBudget,
              canStart: _firstWindingRoute != null,
              onSearchDestination: _openDestinationSearch,
              onSelectedOption: (kind) => setState(() => _selectedKind = kind),
              onSelectedFreeRoam: (index) =>
                  setState(() => _selectedFreeRoamIndex = index),
              onStart: _startFirstWinding,
              onNavigate: _openExternalNavigation,
            )
          else
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
              onOrigin: _openOriginPicker,
              onSearchDestination: _openDestinationSearch,
              onBudget: (value) {
                setState(() {
                  _budget = value;
                  _options = null;
                  _freeRoamOptions = null;
                  _status = null;
                });
                _scheduleBuildPlan();
              },
              onPickArriveBy: _pickArriveBy,
              onClearArriveBy: _clearArriveBy,
              onFreeRoam: _buildFreeRoamPlan,
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

List<String> _windingRouteIds(Iterable<DrivePlanOption> options) {
  final routeIds = <String>{};
  for (final option in options) {
    for (final leg in option.plan.legs) {
      if (leg.kind == DrivePlanLegKind.winding) {
        final id = leg.route?.id;
        if (id != null && id.isNotEmpty) routeIds.add(id);
      }
    }
  }
  return routeIds.toList();
}

List<String> _freeRoamRouteIds(Iterable<FreeRoamOption> options) {
  final routeIds = <String>{};
  for (final option in options) {
    for (final leg in option.plan.legs) {
      if (leg.kind == DrivePlanLegKind.winding) {
        final id = leg.route?.id;
        if (id != null && id.isNotEmpty) routeIds.add(id);
      }
    }
  }
  return routeIds.toList();
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
  final VoidCallback onOrigin;
  final VoidCallback onSearchDestination;
  final ValueChanged<DriveBudget> onBudget;
  final VoidCallback onPickArriveBy;
  final VoidCallback onClearArriveBy;
  final VoidCallback onFreeRoam;

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
    required this.onOrigin,
    required this.onSearchDestination,
    required this.onBudget,
    required this.onPickArriveBy,
    required this.onClearArriveBy,
    required this.onFreeRoam,
  });

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
                      JourneyPlanningCard(language: language, framed: false)
                    else if (status != null)
                      JourneyStateCard(
                        title: status!,
                        body: journeyRetryCopy(language),
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
                        onFreeRoam: onFreeRoam,
                      ),
                  ],
                ),
              ),
              SizedBox(height: bottomPadding),
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
  final VoidCallback onFreeRoam;

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
    required this.onFreeRoam,
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
        if (!hasDestination) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('free-roam-button'),
            onPressed: loadingOrigin ? null : onFreeRoam,
            icon: const Icon(Icons.explore_rounded, size: 18),
            label: Text(
              _copy(
                language,
                ko: '그냥 추천받아 달리기',
                en: 'Surprise me',
                fr: 'Itinéraire surprise',
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(
                color: AppColors.outline.withValues(alpha: 0.28),
              ),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
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

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _copy(
  AppLanguage language, {
  String? ko,
  required String en,
  required String fr,
}) {
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
