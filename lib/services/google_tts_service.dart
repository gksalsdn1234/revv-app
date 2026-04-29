import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

class GoogleTtsService {
  GoogleTtsService._();
  static final GoogleTtsService _instance = GoogleTtsService._();
  factory GoogleTtsService() => _instance;

  static const String defaultVoiceName = 'ko-KR-Chirp3-HD-Leda';

  static const List<Map<String, String>> fallbackVoices = [
    {
      'name': 'ko-KR-Chirp3-HD-Leda',
      'locale': 'ko-KR',
      'label': 'Leda · Premium HD',
    },
    {
      'name': 'ko-KR-Chirp3-HD-Autonoe',
      'locale': 'ko-KR',
      'label': 'Autonoe · Premium HD',
    },
    {
      'name': 'ko-KR-Chirp3-HD-Aoede',
      'locale': 'ko-KR',
      'label': 'Aoede · Premium HD',
    },
    {
      'name': 'ko-KR-Chirp3-HD-Charon',
      'locale': 'ko-KR',
      'label': 'Charon · Premium HD',
    },
    {
      'name': 'ko-KR-Wavenet-D',
      'locale': 'ko-KR',
      'label': 'Wavenet-D · Classic',
    },
  ];

  List<Map<String, String>> _cachedVoices = const [];

  Future<List<Map<String, String>>> fetchVoices() async {
    if (_cachedVoices.isNotEmpty) return _cachedVoices;
    try {
      final data = await SupabaseService().invokeFunction(
        'list-google-tts-voices',
      );
      final raw = (data?['voices'] as List?) ?? const [];
      final voices = raw
          .whereType<Map>()
          .map(
            (item) => <String, String>{
              'name': item['name']?.toString() ?? '',
              'locale': item['locale']?.toString() ?? 'ko-KR',
              'label':
                  item['label']?.toString() ??
                  item['name']?.toString() ??
                  'Google Korean Voice',
            },
          )
          .where((item) => (item['name'] ?? '').isNotEmpty)
          .toList();
      if (voices.isNotEmpty) {
        _cachedVoices = voices;
        return _cachedVoices;
      }
    } catch (e) {
      debugPrint('[GoogleTTS] 음성 목록 실패: $e');
    }
    _cachedVoices = fallbackVoices;
    return _cachedVoices;
  }

  Future<Uint8List?> synthesize(
    String text, {
    required String voiceName,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final data = await SupabaseService().invokeFunction(
        'synthesize-tts',
        body: {'text': trimmed, 'voiceName': voiceName},
      );
      final base64Audio = data?['audioContent'] as String?;
      if (base64Audio == null || base64Audio.isEmpty) return null;
      return base64Decode(base64Audio);
    } catch (e) {
      debugPrint('[GoogleTTS] 합성 실패: $e');
      return null;
    }
  }
}
