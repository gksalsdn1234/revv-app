import 'dart:convert';
import 'package:http/http.dart' as http;

class RevvAiService {
  static final RevvAiService _instance = RevvAiService._internal();
  factory RevvAiService() => _instance;
  RevvAiService._internal();

  static const _apiKey =
      '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';
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
}
