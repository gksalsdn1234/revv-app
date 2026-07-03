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
  LatLng _destination = _plannerRegions.first.point;
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
      _options = null;
    });
    try {
      final options = await _planner
          .buildPlanOptions(
            DrivePlanRequest(
              origin: _origin,
              destination: _destination,
              windingBudgetMinutes: _budgetMinutes(_budget),
            ),
          )
          .timeout(_requestTimeout);
      if (!mounted) return;
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
  }

  void _clearArriveBy() {
    setState(() => _arriveBy = null);
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
    final appUri = buildGoogleMapsAppUri(
      origin: _origin,
      destination: _destination,
      waypoints: waypoints,
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
      _destinationName = null;
      _mapCenter = region.point;
      _mapFocusSignal++;
      _options = null;
      _status = null;
    });
  }

  Future<void> _openDestinationSearch() async {
    final language = context.read<SettingsService>().appLanguage;
    final result = await showModalBottomSheet<PlaceResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlaceSearchSheet(
        language: language,
        service: _placeSearch,
        proximity: _origin,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _destination = result.point;
      _destinationName = result.name;
      _mapCenter = result.point;
      _mapFocusSignal++;
      _options = null;
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
              cameraTarget: _mapCenter,
              cameraTargetSignal: _mapFocusSignal,
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
                  destinationName: _destinationName,
                  loadingOrigin: _loadingOrigin,
                  budget: _budget,
                  onUsePinAsOrigin: () => setState(() {
                    _origin = _mapCenter;
                    _options = null;
                    _status = null;
                  }),
                  onUsePinAsDestination: () => setState(() {
                    _destination = _mapCenter;
                    _destinationName = null;
                    _options = null;
                    _status = null;
                  }),
                  onSearchDestination: _openDestinationSearch,
                  onBudget: (value) => setState(() {
                    _budget = value;
                    _options = null;
                    _status = null;
                  }),
                  onPlan: _planning || _loadingOrigin ? null : _buildPlan,
                  planning: _planning,
                  arriveBy: _arriveBy,
                  onPickArriveBy: _pickArriveBy,
                  onClearArriveBy: _clearArriveBy,
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
                      ko: '최대 20초 안에 결과를 보여드릴게요.',
                      en: 'This stops after 20 seconds if no plan returns.',
                      fr: 'Le calcul s’arrête après 20 secondes sans résultat.',
                    ),
                  )
                else if (_status != null)
                  _StateCard(title: _status!, body: _retryCopy(language))
                else if (_options != null && _plan != null) ...[
                  _PlanOptionStrip(
                    options: _options!,
                    selected: _selectedKind,
                    recommended: _recommendedOption?.kind,
                    language: language,
                    onSelected: (kind) => setState(() => _selectedKind = kind),
                  ),
                  const SizedBox(height: 10),
                  if (_arriveByDateTime != null && _recommendedOption == null)
                    _ArrivalInfeasibleCard(
                      options: _options!,
                      arriveBy: _arriveByDateTime!,
                      language: language,
                    ),
                  _PlanResultCard(
                    plan: _plan!,
                    language: language,
                    targetMinutes: _selectedOptionBudget,
                    arriveBy: _arriveByDateTime,
                    onStart: _firstWindingRoute == null
                        ? null
                        : _startFirstWinding,
                    onNavigate: _openExternalNavigation,
                  ),
                ],
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
  final String? destinationName;
  final bool loadingOrigin;
  final DriveBudget budget;
  final VoidCallback onUsePinAsOrigin;
  final VoidCallback onUsePinAsDestination;
  final VoidCallback onSearchDestination;
  final ValueChanged<DriveBudget> onBudget;
  final VoidCallback? onPlan;
  final bool planning;
  final TimeOfDay? arriveBy;
  final VoidCallback onPickArriveBy;
  final VoidCallback onClearArriveBy;

  const _PlannerInputCard({
    required this.language,
    required this.origin,
    required this.destination,
    required this.destinationName,
    required this.loadingOrigin,
    required this.budget,
    required this.onUsePinAsOrigin,
    required this.onUsePinAsDestination,
    required this.onSearchDestination,
    required this.onBudget,
    required this.onPlan,
    required this.planning,
    required this.arriveBy,
    required this.onPickArriveBy,
    required this.onClearArriveBy,
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
            value: destinationName ?? _coord(destination),
            action: _copy(
              language,
              ko: '중앙 핀 선택',
              en: 'Set from pin',
              fr: 'Depuis le repère',
            ),
            onTap: onUsePinAsDestination,
            onValueTap: onSearchDestination,
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _copy(
                        language,
                        ko: '도착 희망 시각 (선택)',
                        en: 'Arrive by (optional)',
                        fr: 'Arrivée souhaitée (option)',
                      ),
                      style: AppText.technicalLabel(
                        size: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      arriveBy == null
                          ? _copy(language, ko: '없음', en: 'None', fr: 'Aucune')
                          : _formatTimeOfDay(arriveBy!),
                      style: AppText.body(size: 13, weight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (arriveBy != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.textHint,
                  onPressed: onClearArriveBy,
                ),
              TextButton(
                onPressed: onPickArriveBy,
                child: Text(
                  arriveBy == null
                      ? _copy(
                          language,
                          ko: '시각 선택',
                          en: 'Pick time',
                          fr: 'Choisir',
                        )
                      : _copy(language, ko: '변경', en: 'Change', fr: 'Modifier'),
                ),
              ),
            ],
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

class _PlaceSearchSheet extends StatefulWidget {
  final AppLanguage language;
  final PlaceSearchService service;
  final LatLng proximity;

  const _PlaceSearchSheet({
    required this.language,
    required this.service,
    required this.proximity,
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: _buildResults(),
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

class _PointRow extends StatelessWidget {
  final String label;
  final String value;
  final String action;
  final VoidCallback onTap;
  final VoidCallback? onValueTap;

  const _PointRow({
    required this.label,
    required this.value,
    required this.action,
    required this.onTap,
    this.onValueTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onValueTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
  final DateTime? arriveBy;
  final VoidCallback? onStart;
  final VoidCallback onNavigate;

  const _PlanResultCard({
    required this.plan,
    required this.language,
    required this.targetMinutes,
    required this.arriveBy,
    required this.onStart,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final windingRatio = plan.totalMinutes == 0
        ? 0
        : (plan.windingMinutes / plan.totalMinutes * 100).round();
    final eta = DateTime.now().add(Duration(minutes: plan.totalMinutes));
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
          const SizedBox(height: 4),
          Text(
            _copy(
              language,
              ko: '지금 출발하면 ${_formatClock(eta)} 도착 예상',
              en: 'Leave now to arrive around ${_formatClock(eta)}',
              fr: 'En partant maintenant, arrivée vers ${_formatClock(eta)}',
            ),
            style: AppText.body(size: 12, color: AppColors.textSecondary),
          ),
          if (plan.usesApproximateTransit) ...[
            const SizedBox(height: 4),
            Text(
              _copy(
                language,
                ko: '대략 경로 · 실제 내비에서 도로 경로를 확인하세요',
                en: 'Approximate route · confirm roads in navigation',
                fr: 'Trajet approximatif · vérifiez dans la navigation',
              ),
              style: AppText.body(size: 12, color: AppColors.warning),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
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
