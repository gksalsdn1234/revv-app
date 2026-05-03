import '../models/revv_route.dart';
import '../ui/route_detail_copy.dart';
import '../ui/route_geometry_insight.dart';
import '../ui/route_reading_context.dart';
import 'supabase_service.dart';
import 'weather_service.dart';

class RouteBriefService {
  static const _fallback = '좋은 와인딩 루트예요. 현재 노면 상태 확인하고 출발하세요.';

  Future<String> getBriefing({
    required RevvRoute route,
    required WeatherService weather,
  }) async {
    final copy = RouteDetailCopy.fromRoute(route);
    final geometry = RouteGeometryInsight.fromRoute(route);
    final reading = RouteReadingContext.fromRoute(route);
    try {
      final data = await SupabaseService().invokeFunction(
        'call-ai',
        body: {
          'model': 'claude-sonnet-4-6',
          'maxTokens': 150,
          'system':
              '너는 REVV 앱의 AI 코파일럿이야. 드라이버에게 루트를 소개할 때 실제 좌표 기반 분석을 먼저 반영해. '
              '2~3문장으로 짧게, 같은 단어 반복 없이, 과속을 부추기지 말고, 마지막엔 안전한 진입 팁을 한 줄로 말해.',
          'messages': [
            {
              'role': 'user',
              'content':
                  '''루트 정보:
- 이름: ${route.name}
- 거리: ${route.distanceKm.toStringAsFixed(1)}km
- 와인딩 점수: ${route.windingScore.toStringAsFixed(0)}점
- 급커브: ${route.sharpCurveCount}개
- 커브 집중 구간: ${(route.tightCurveKm + route.mediumCurveKm).toStringAsFixed(1)}km
- 최대 연속 흐름: ${route.maxContinuousKm.toStringAsFixed(1)}km
- stop/sign: ${route.stopSignCount + route.trafficSignalCount}개
- 별점: ${route.starRating}/5
- 좌표 기반 분석: ${geometry.briefContext}
- 도로/지형 맥락: ${reading.briefContext}
- 앱 기본 판단: ${copy.heroReason}
${copy.cautionLine != null ? '- 주의: ${copy.cautionLine}\n' : ''}

현재 날씨:
- 날씨: ${weather.weatherDesc}
- 기온: ${weather.tempCelsius.toStringAsFixed(0)}°C
- 노면: ${weather.roadCondition}

이 루트를 드라이버에게 소개해줘.''',
            },
          ],
        },
      );
      return (data?['text'] as String? ?? '').trim().isNotEmpty
          ? data!['text'] as String
          : copy.heroReason;
    } catch (_) {}
    return copy.heroReason.isNotEmpty ? copy.heroReason : _fallback;
  }
}
