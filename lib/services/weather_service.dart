import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class WeatherService extends ChangeNotifier {
  String weatherDesc = '맑음';
  double tempCelsius = 0;
  String weatherIcon = '01d';
  String roadCondition = 'DRY';
  bool isLoading = false;
  bool _isOffline = false;

  bool get isOffline => _isOffline;

  Timer? _refreshTimer;

  Future<void> fetchWeather(double lat, double lng) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getWeather')
          .call<Map>({'lat': lat, 'lng': lng});

      final data = result.data;
      weatherDesc = data['weather'][0]['description'] as String;
      tempCelsius = (data['main']['temp'] as num).toDouble();
      weatherIcon = data['weather'][0]['icon'] as String;
      roadCondition = _inferRoadCondition(data);
      _isOffline = false;
    } catch (_) {
      _isOffline = true;
    }

    isLoading = false;
    notifyListeners();

    // 10분마다 자동 갱신
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(minutes: 10), () {
      fetchWeather(lat, lng);
    });
  }

  String _inferRoadCondition(Map data) {
    final id = data['weather'][0]['id'] as int;
    if (id >= 600 && id < 700) return 'ICY'; // 눈
    if (id >= 500 && id < 600) return 'WET'; // 비
    if (id >= 700 && id < 800) return 'FOGGY'; // 안개/먼지
    if (tempCelsius < -5) return 'ICY';
    if (tempCelsius < 0) return 'COLD';
    return 'DRY';
  }

  String get weatherEmoji {
    final icon = weatherIcon;
    if (icon.startsWith('01')) return '☀️';
    if (icon.startsWith('02') ||
        icon.startsWith('03') ||
        icon.startsWith('04')) {
      return '☁️';
    }
    if (icon.startsWith('09') || icon.startsWith('10')) return '🌧';
    if (icon.startsWith('11')) return '⛈';
    if (icon.startsWith('13')) return '🌨';
    if (icon.startsWith('50')) return '🌫';
    return '🌤';
  }

  String get tempDisplay => '${tempCelsius.toStringAsFixed(0)}°C';

  String get weatherBriefLine {
    if (_isOffline) return '날씨 정보 없음';
    switch (roadCondition) {
      case 'WET':
        return '노면이 젖어있어요. 타이어 그립 주의하세요.';
      case 'ICY':
        return '노면 결빙 가능성 있어요. 브레이킹 거리 늘려주세요.';
      case 'FOGGY':
        return '안개 구간이에요. 전조등 켜고 차간거리 유지하세요.';
      case 'COLD':
        return '기온 영하예요. 타이어 워밍업 필요합니다.';
      default:
        return '오늘 노면 상태 좋아요. 드라이빙 즐기세요.';
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
