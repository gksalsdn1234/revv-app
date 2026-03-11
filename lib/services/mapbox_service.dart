import 'package:flutter/scheduler.dart';

class MapboxService {
  static const accessToken =
      'pk.eyJ1IjoibWluZ3dvbyIsImEiOiJjbW1kdnp2bTUwM3VuMnJuMzRzeGdienVvIn0.CXykIJuDYcPt99tQJQnRhQ';

  /// 크루즈 모드 — 아웃도어 (지형, 산길, 도로 모두 잘 보임)
  static const cruiseStyle = 'mapbox://styles/mapbox/outdoors-v12';

  /// 스프린트 모드 — 시스템 밝기에 따라 낮/밤 자동 전환
  static String get sprintStyle {
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark
        ? 'mapbox://styles/mapbox/navigation-night-v1'
        : 'mapbox://styles/mapbox/navigation-day-v1';
  }

  // 이전 스타일명 유지 (하위 호환)
  static const darkStyle = cruiseStyle;
  static const navStyle = 'mapbox://styles/mapbox/navigation-night-v1';
}
