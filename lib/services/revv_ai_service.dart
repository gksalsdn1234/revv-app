import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/secrets.dart';
import '../models/run_session.dart';

class RevvAiService {
  static final RevvAiService _instance = RevvAiService._internal();
  factory RevvAiService() => _instance;
  RevvAiService._internal();

  static const _apiKey = Secrets.anthropicApiKey;
  static const _fallback = '잘 들었어요. 안전하게 달려요.';

  Future<String> ask(
    String userText, {
    double speedKmh = 0,
    String weather = '',
    String roadCondition = '',
  }) async {
    if (userText.isEmpty) return _fallback;

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
          'max_tokens': 100,
          'system':
              '너는 REVV, AI 코드라이버야. 드라이버와 짧게 소통해. 2문장 이내로, 한국어로, 핵심만 말해. 주행 안전을 최우선으로.',
          'messages': [
            {
              'role': 'user',
              'content': '''현재 상태:
- 속도: ${speedKmh.toStringAsFixed(0)}km/h
- 날씨: $weather
- 노면: $roadCondition

드라이버: "$userText"''',
            }
          ],
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return (data['content'][0]['text'] as String).trim();
      }
    } catch (_) {}
    return _fallback;
  }

  /// 주행 종료 후 자동 분석 리포트 생성
  Future<String> analyzeRun(RunSession session) async {
    try {
      final dur = session.duration;
      final durStr = dur.inHours > 0
          ? '${dur.inHours}시간 ${dur.inMinutes % 60}분'
          : dur.inMinutes > 0
              ? '${dur.inMinutes}분 ${dur.inSeconds % 60}초'
              : '${dur.inSeconds}초';

      final totalSecs =
          session.driveModeSeconds.values.fold(0, (a, b) => a + b);

      String modeStr;
      if (totalSecs > 0) {
        final cruise =
            ((session.driveModeSeconds['cruise'] ?? 0) / totalSecs * 100)
                .round();
        final winding =
            ((session.driveModeSeconds['winding'] ?? 0) / totalSecs * 100)
                .round();
        final sport =
            ((session.driveModeSeconds['sport'] ?? 0) / totalSecs * 100)
                .round();
        modeStr =
            'CRUISE ${cruise}% / WINDING ${winding}% / SPORT ${sport}%';
      } else {
        modeStr = '데이터 없음';
      }

      final hasGData = session.maxLateralG > 0.01 || session.maxLonG > 0.01;
      final gStr = hasGData
          ? '최대 횡G ${session.maxLateralG.toStringAsFixed(2)}G / 최대 종G ${session.maxLonG.toStringAsFixed(2)}G / 급조작 ${session.sharpCorners.length}회'
          : 'G포스 데이터 없음 (실기기 필요)';

      final prompt = '''주행 데이터:
- 루트: ${session.routeName}
- 거리: ${session.distanceKm.toStringAsFixed(2)} km
- 주행 시간: $durStr
- 최고 속도: ${session.maxSpeedKmh.toStringAsFixed(1)} km/h
- 평균 속도: ${session.avgSpeedKmh.toStringAsFixed(1)} km/h
- 날씨: ${session.weatherEmoji} ${session.tempDisplay} ${session.weatherDesc}
- G포스: $gStr
- 드라이빙 모드 비율: $modeStr''';

      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5-20251001',
          'max_tokens': 180,
          'system':
              '너는 REVV, AI 코드라이버야. 주행 데이터를 받아 드라이버에게 짧고 솔직한 피드백을 줘. '
              '3문장 이내. 한국어. 구체적인 수치를 인용해. 칭찬과 개선점을 균형있게. '
              '앱스토어 규정상 과속·위험 운전을 조장하는 표현은 절대 쓰지 마.',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return (data['content'][0]['text'] as String).trim();
      }
    } catch (_) {}
    return _buildFallbackAnalysis(session);
  }

  /// 상세 AI 코칭 리포트 — 런카드 "상세 분석" 버튼에서 호출
  /// analyzeRun보다 더 길고 구체적인 섹션별 피드백 생성
  Future<String> analyzeRunDetailed(RunSession session) async {
    try {
      final dur = session.duration;
      final durStr = dur.inHours > 0
          ? '${dur.inHours}시간 ${dur.inMinutes % 60}분'
          : '${dur.inMinutes}분';

      final totalSecs =
          session.driveModeSeconds.values.fold(0, (a, b) => a + b);
      String modeStr;
      if (totalSecs > 0) {
        final cruise = ((session.driveModeSeconds['cruise'] ?? 0) / totalSecs * 100).round();
        final winding = ((session.driveModeSeconds['winding'] ?? 0) / totalSecs * 100).round();
        final sport = ((session.driveModeSeconds['sport'] ?? 0) / totalSecs * 100).round();
        modeStr = 'CRUISE ${cruise}% / WINDING ${winding}% / SPORT ${sport}%';
      } else {
        modeStr = '데이터 없음';
      }

      final hasG = session.maxLateralG > 0.01;
      final sharpCount = session.sharpCorners.length;

      // 드라이빙 스타일 분류
      String styleLabel;
      if (!hasG) {
        styleLabel = '미측정';
      } else if (session.maxLateralG < 0.25) {
        styleLabel = 'CRUISER (0.25G 미만)';
      } else if (session.maxLateralG < 0.45) {
        styleLabel = 'SPORT (0.25~0.45G)';
      } else {
        styleLabel = 'RACER (0.45G 초과)';
      }

      final prompt = '''다음 주행 데이터를 바탕으로 드라이버에게 상세 코칭 리포트를 작성해줘.

[주행 데이터]
- 루트: ${session.routeName}
- 거리: ${session.distanceKm.toStringAsFixed(2)} km / 시간: $durStr
- 최고속도: ${session.maxSpeedKmh.toStringAsFixed(1)} km/h / 평균: ${session.avgSpeedKmh.toStringAsFixed(1)} km/h
- 드라이빙 스타일: $styleLabel
- 최대 횡G: ${hasG ? session.maxLateralG.toStringAsFixed(2) + 'G' : '미측정'}
- 최대 종G: ${hasG ? session.maxLonG.toStringAsFixed(2) + 'G' : '미측정'}
- 급조작 횟수: ${hasG ? '${sharpCount}회 (0.45G 초과)' : '미측정'}
- 드라이빙 모드: $modeStr
- 날씨: ${session.weatherEmoji} ${session.tempDisplay}

[요청 형식]
아래 3개 섹션으로 구성해줘. 각 섹션은 이모지 + 한 줄 제목 + 2~3문장 내용.
1. 💪 오늘의 하이라이트 — 잘한 점
2. 🎯 개선 포인트 — 구체적인 개선 제안
3. 🗺️ 다음 목표 — 다음 드라이브에 도전할 것
총 8~10문장, 한국어, 수치를 적극 활용. 앱스토어 규정상 과속·위험 표현 절대 금지.''';

      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5-20251001',
          'max_tokens': 500,
          'system':
              '너는 REVV, AI 드라이빙 코치야. 주행 데이터를 분석하여 드라이버 성장에 도움이 되는 구체적이고 따뜻한 피드백을 준다. '
              '앱스토어 규정 준수: 과속·위험 운전 조장 표현 절대 금지.',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return (data['content'][0]['text'] as String).trim();
      }
    } catch (_) {}
    return _buildDetailedFallback(session);
  }

  String _buildDetailedFallback(RunSession session) {
    final km = session.distanceKm;
    final sharpCount = session.sharpCorners.length;
    final hasG = session.maxLateralG > 0.01;
    final buf = StringBuffer();
    buf.writeln('💪 오늘의 하이라이트');
    buf.writeln('${km.toStringAsFixed(1)}km 완주, 수고했어요!');
    if (hasG) buf.writeln('최대 횡G ${session.maxLateralG.toStringAsFixed(2)}G를 기록했네요.');
    buf.writeln();
    buf.writeln('🎯 개선 포인트');
    if (sharpCount > 3) {
      buf.writeln('급조작이 ${sharpCount}회 감지됐어요. 코너 진입 전 미리 속도를 조정해보세요.');
    } else {
      buf.writeln('코너링이 안정적이에요. 루트 변경으로 새로운 코너를 경험해보세요.');
    }
    buf.writeln();
    buf.writeln('🗺️ 다음 목표');
    buf.writeln('같은 루트를 다시 달리면 더 자연스러운 흐름을 느낄 수 있어요. 도전해보세요!');
    return buf.toString();
  }

  /// API 실패 시 로컬 폴백 분석
  String _buildFallbackAnalysis(RunSession session) {
    final km = session.distanceKm;
    final min = session.duration.inMinutes;
    final totalSecs =
        session.driveModeSeconds.values.fold(0, (a, b) => a + b);
    final sportSecs = session.driveModeSeconds['sport'] ?? 0;
    final sportPct =
        totalSecs > 0 ? (sportSecs / totalSecs * 100).round() : 0;

    if (sportPct >= 30) {
      return '${km.toStringAsFixed(1)}km, ${min}분 — 오늘 꽤 격한 드라이빙이었네요. SPORT 모드가 ${sportPct}%였어요. 다음엔 조금 여유있게 달려봐요.';
    }
    if (km >= 30) {
      return '${km.toStringAsFixed(1)}km, ${min}분 — 오늘 긴 코스 수고했어요. 꾸준히 달리는 것 자체가 실력이에요.';
    }
    if (km >= 10) {
      return '${km.toStringAsFixed(1)}km 완주. 이 코스 마음에 드셨나요? 같은 코스를 반복하면 더 자연스러워져요.';
    }
    return '짧지만 의미있는 드라이브였어요. 다음엔 조금 더 멀리 나가봐요.';
  }
}
