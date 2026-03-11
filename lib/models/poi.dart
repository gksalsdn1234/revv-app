class Poi {
  final String name;
  final double lat;
  final double lng;
  final PoiCategory category;
  final double distanceKm;

  const Poi({
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
    required this.distanceKm,
  });
}

enum PoiCategory {
  cafe('☕', '카페', 'amenity', 'cafe'),
  restaurant('🍽', '맛집', 'amenity', 'restaurant'),
  fastFood('🍔', '패스트푸드', 'amenity', 'fast_food'),
  viewpoint('🌄', '뷰포인트', 'tourism', 'viewpoint'),
  gasStation('⛽', '주유소', 'amenity', 'fuel');

  final String emoji;
  final String label;
  final String osmKey;
  final String osmValue;

  const PoiCategory(this.emoji, this.label, this.osmKey, this.osmValue);
}
