class MapboxService {
  static const accessToken =
      'pk.eyJ1IjoibWluZ3dvbyIsImEiOiJjbW1kdnp2bTUwM3VuMnJuMzRzeGdienVvIn0.CXykIJuDYcPt99tQJQnRhQ';

  /// 크루즈 모드 — 아웃도어
  static const cruiseStyle = 'mapbox://styles/mapbox/outdoors-v12';

  /// 스프린트 모드 — weatherIcon 끝이 'n'이면 밤, 'd'면 낮
  static String sprintStyle(String weatherIcon) {
    final isNight = weatherIcon.endsWith('n');
    return isNight
        ? 'mapbox://styles/mapbox/navigation-night-v1'
        : 'mapbox://styles/mapbox/navigation-day-v1';
  }
}
