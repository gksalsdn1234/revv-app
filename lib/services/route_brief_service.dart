import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/revv_route.dart';
import 'weather_service.dart';

class RouteBriefService {
  static const _apiKey =
      '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';
  static const _fallback = '좋은 와인딩 루트예요. 현재 노면 상태 확인하고 출발하세요.';

  Future<String> getBriefing({
    required RevvRoute route,
    required WeatherService weather,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-6',
          'max_tokens': 150,
          'system':
              '너는 REVV 앱의 AI 코파일럿이야. 드라이버에게 루트를 소개할 때: 2~3문장으로 짧고 임팩트 있게, 수치를 활용해서 구체적으로, 현재 날씨/노면 상태 반영, 마지막엔 한 줄 드라이빙 팁, 한국어로, 절대 길게 말하지 마.',
          'messages': [
            {
              'role': 'user',
              'content': '''루트 정보:
- 이름: ${route.name}
- 거리: ${route.distanceKm.toStringAsFixed(1)}km
- 와인딩 점수: ${route.windingScore.toStringAsFixed(0)}점
- 급커브: ${route.sharpCurveCount}개
- 별점: ${route.starRating}/5

현재 날씨:
- 날씨: ${weather.weatherDesc}
- 기온: ${weather.tempCelsius.toStringAsFixed(0)}°C
- 노면: ${weather.roadCondition}

이 루트를 드라이버에게 소개해줘.'''
            }
          ],
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return (data['content'][0]['text'] as String).trim();
      }
    } catch (_) {}
    return _fallback;
  }
}
