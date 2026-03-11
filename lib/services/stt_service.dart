import 'package:speech_to_text/speech_to_text.dart';

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  String _lastWords = '';

  Future<bool> _init() async {
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _initialized;
  }

  Future<void> startListening() async {
    final ok = await _init();
    if (!ok) return;
    _lastWords = '';
    await _stt.listen(
      localeId: 'ko_KR',
      onResult: (result) {
        _lastWords = result.recognizedWords;
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
    );
  }

  Future<String> stopListening() async {
    await _stt.stop();
    await Future.delayed(const Duration(milliseconds: 300));
    return _lastWords.trim();
  }

  bool get isListening => _stt.isListening;
}
