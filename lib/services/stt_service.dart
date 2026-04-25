import 'package:speech_to_text/speech_to_text.dart';

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  String _lastWords = '';
  String? _lastFailureReason;

  // ── 항상 듣기 상태 ─────────────────────────────────────────
  bool _alwaysOn = false;
  bool _processing = false; // AI 처리 중 — 재시작 억제
  void Function(String)? _alwaysOnCallback;

  bool get isListening => _stt.isListening;
  bool get alwaysOn => _alwaysOn;
  bool get isAvailable => _initialized;
  String? get lastFailureReason => _lastFailureReason;
  String get permissionStatusLabel =>
      _initialized ? '마이크 사용 가능' : '마이크 권한 확인 필요';

  Future<bool> _init() async {
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onError: (error) {
        _lastFailureReason = error.errorMsg;
      },
      onStatus: (status) {
        // 항상듣기 모드: 음성 인식 완료 후 자동 재시작
        if (status == 'done' && _alwaysOn && !_processing) {
          Future.delayed(const Duration(milliseconds: 400), _listenOnce);
        }
      },
    );
    if (!_initialized) {
      _lastFailureReason = '마이크 권한이 없거나 음성 인식을 시작할 수 없어요.';
    } else {
      _lastFailureReason = null;
    }
    return _initialized;
  }

  // ── 일반 PTT ──────────────────────────────────────────────
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

  // ── 항상 듣기 ─────────────────────────────────────────────
  Future<void> startAlwaysListening(void Function(String) onResult) async {
    _alwaysOn = true;
    _alwaysOnCallback = onResult;
    await _listenOnce();
  }

  void stopAlwaysListening() {
    _alwaysOn = false;
    _alwaysOnCallback = null;
    _processing = false;
    _stt.stop();
  }

  /// AI 처리 중 표시 — true일 때 자동 재시작 억제, false 되면 재시작
  void setProcessing(bool v) {
    _processing = v;
    if (!v && _alwaysOn) {
      Future.delayed(const Duration(milliseconds: 300), _listenOnce);
    }
  }

  Future<void> _listenOnce() async {
    if (!_alwaysOn || _processing || _stt.isListening) return;
    final ok = await _init();
    if (!ok) return;
    _lastWords = '';
    await _stt.listen(
      localeId: 'ko_KR',
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _alwaysOnCallback?.call(result.recognizedWords.trim());
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 2),
    );
  }
}
