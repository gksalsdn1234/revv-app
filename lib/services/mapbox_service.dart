class MapboxService {
  static const accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static bool get isConfigured => accessToken.isNotEmpty;

  /// 크루즈 모드 — REVV Signature v1 (다크 아스팔트, 도로 위계 반전:
  /// 지방도가 주인공). dark-v11 기반, Styles API로 생성 (2026-07-09).
  static const cruiseStyle = 'mapbox://styles/mingwoo/cmrd3w7yt005f01qo8l1f4anc';

  /// 스프린트 모드 — weatherIcon 끝이 'n'이면 밤, 'd'면 낮
  static String sprintStyle(String weatherIcon) {
    return weatherIcon.endsWith('n')
        ? 'mapbox://styles/mapbox/navigation-night-v1'
        : 'mapbox://styles/mapbox/navigation-day-v1';
  }
}
