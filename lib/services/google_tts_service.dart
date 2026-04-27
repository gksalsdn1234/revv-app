import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

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

  final FirebaseFunctions _fn = FirebaseFunctions.instance;
  List<Map<String, String>> _cachedVoices = const [];

  Future<List<Map<String, String>>> fetchVoices() async {
    if (_cachedVoices.isNotEmpty) return _cachedVoices;
    try {
      final result = await _fn.httpsCallable('listGoogleTtsVoices').call<Map>();
      final raw = (result.data['voices'] as List?) ?? const [];
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
      final result = await _fn.httpsCallable('synthesizeTts').call<Map>({
        'text': trimmed,
        'voiceName': voiceName,
      });
      final base64Audio = result.data['audioContent'] as String?;
      if (base64Audio == null || base64Audio.isEmpty) return null;
      return base64Decode(base64Audio);
    } catch (e) {
      debugPrint('[GoogleTTS] 합성 실패: $e');
      return null;
    }
  }
}
