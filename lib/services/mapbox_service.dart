class MapboxService {
  static const accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static bool get isConfigured => accessToken.isNotEmpty;

  /// 크루즈 모드 — 아웃도어 (지형, 등고선)
  static const cruiseStyle = 'mapbox://styles/mapbox/outdoors-v12';

  /// 스프린트 모드 — weatherIcon 끝이 'n'이면 밤, 'd'면 낮
  static String sprintStyle(String weatherIcon) {
    return weatherIcon.endsWith('n')
        ? 'mapbox://styles/mapbox/navigation-night-v1'
        : 'mapbox://styles/mapbox/navigation-day-v1';
  }
}
