import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/colors.dart';
import '../models/poi.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/home_location_service.dart';
import '../services/poi_service.dart';
import '../widgets/corner_brackets.dart';

class TripPlannerScreen extends StatefulWidget {
  const TripPlannerScreen({super.key});

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  PoiCategory _selectedCategory = PoiCategory.cafe;
  List<Poi> _pois = [];
  bool _loading = false;
  Poi? _selectedPoi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _selectedPoi = null;
      _pois = [];
    });
    final loc = context.read<LocationService>();
    final results = await PoiService.search(
      loc.lat,
      loc.lng,
      _selectedCategory,
    );
    if (mounted) setState(() {
      _pois = results;
      _loading = false;
    });
  }

  Future<void> _navigate(Poi poi) async {
    final home = context.read<HomeLocationService>().home;
    final loc = context.read<LocationService>();

    // Google Maps: origin → POI → home (if set)
    String url;
    if (home != null) {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&origin=${loc.lat},${loc.lng}'
          '&destination=${home.lat},${home.lng}'
          '&waypoints=${poi.lat},${poi.lng}'
          '&travelmode=driving';
    } else {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&origin=${loc.lat},${loc.lng}'
          '&destination=${poi.lat},${poi.lng}'
          '&travelmode=driving';
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _setHomeHere() async {
    final loc = context.read<LocationService>();
    await context
        .read<HomeLocationService>()
        .setHomeFromCurrentLocation(loc.lat, loc.lng);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '현재 위치를 집으로 저장했어요.',
            style: GoogleFonts.rajdhani(fontSize: 14),
          ),
          backgroundColor: AppColors.panel,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeLocationService>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              homeSet: home.isSet,
              onSetHome: _setHomeHere,
            ),
            const SizedBox(height: 16),
            // 카테고리 칩 선택
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: PoiCategory.values.map((cat) {
                  final selected = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedCategory = cat);
                        _search();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.red
                              : AppColors.panel,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selected
                                ? AppColors.red
                                : AppColors.red.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          '${cat.emoji} ${cat.label}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : AppColors.gray,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            // 결과 목록
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.red))
                  : _pois.isEmpty
                      ? Center(
                          child: Text(
                            '근처에 ${_selectedCategory.label}을 찾지 못했어요',
                            style: GoogleFonts.rajdhani(
                              fontSize: 14,
                              color: AppColors.gray,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _pois.length,
                          itemBuilder: (_, i) => _PoiTile(
                            poi: _pois[i],
                            homeSet: home.isSet,
                            onTap: () => _navigate(_pois[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool homeSet;
  final VoidCallback onSetHome;
  const _Header({required this.homeSet, required this.onSetHome});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '어디 들를까요?',
                style: GoogleFonts.orbitron(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                homeSet
                    ? '들를 곳 선택 → 집까지 경로를 안내해 드려요'
                    : '들를 곳 선택 후 내비게이션으로 연결해 드려요',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  color: AppColors.gray,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Row(
              children: [
                if (!homeSet)
                  GestureDetector(
                    onTap: onSetHome,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.red.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '🏠 집 설정',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          color: AppColors.gray,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close,
                      color: AppColors.gray, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PoiTile extends StatelessWidget {
  final Poi poi;
  final bool homeSet;
  final VoidCallback onTap;
  const _PoiTile(
      {required this.poi, required this.homeSet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.red.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Text(poi.category.emoji,
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${poi.distanceKm.toStringAsFixed(1)} km 거리',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    homeSet ? '여기 → 집' : '여기로',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
