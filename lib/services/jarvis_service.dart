import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'google_tts_service.dart';
import 'settings_service.dart';
import 'weather_service.dart';

enum SpeechPriority { low, normal, high, critical }

class _SpeechItem {
  final String text;
  final SpeechPriority priority;

  const _SpeechItem(this.text, this.priority);
}

class TtsVoiceOption {
  final String name;
  final String locale;

  const TtsVoiceOption({
    required this.name,
    required this.locale,
  });

  String get id => '$name|$locale';

  String get displayLabel {
    final cleanLocale = locale.replaceAll('_', '-');
    return '$name · $cleanLocale';
  }
}

double ttsPresetToJarvisRate(String preset) {
  switch (preset) {
    case 'balanced':
      return 0.38;
    case 'brisk':
      return 0.44;
    case 'relaxed':
    default:
      return 0.33;
  }
}

double ttsPresetToTurnRate(String preset) {
  switch (preset) {
    case 'balanced':
      return 0.48;
    case 'brisk':
      return 0.56;
    case 'relaxed':
    default:
      return 0.42;
  }
}

double ttsPresetToGooglePlaybackRate(String preset) {
  switch (preset) {
    case 'balanced':
      return 0.94;
    case 'brisk':
      return 1.0;
    case 'relaxed':
    default:
      return 0.88;
  }
}

class JarvisService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _cloudPlayer = AudioPlayer();
  final GoogleTtsService _googleTts = GoogleTtsService();
  final List<_SpeechItem> _queue = [];

  bool isSpeaking = false;
  String? lastSpoken;
  bool _isMuted = false;
  bool _isDisposed = false;
  bool _isTransitioning = false;
  String _ratePreset = 'relaxed';
  String _ttsEngine = 'google';
  List<TtsVoiceOption> _deviceVoices = const [];
  TtsVoiceOption? _selectedDeviceVoice;
  List<TtsVoiceOption> _googleVoices = const [];
  TtsVoiceOption? _selectedGoogleVoice;
  int _cloudSpeakToken = 0;

  String get ttsEngine => _ttsEngine;
  List<TtsVoiceOption> get availableVoices => _ttsEngine == 'google'
      ? List.unmodifiable(_googleVoices)
      : List.unmodifiable(_deviceVoices);
  TtsVoiceOption? get selectedVoice =>
      _ttsEngine == 'google' ? _selectedGoogleVoice : _selectedDeviceVoice;
  List<TtsVoiceOption> get deviceVoices => List.unmodifiable(_deviceVoices);
  List<TtsVoiceOption> get googleVoices => List.unmodifiable(_googleVoices);
  TtsVoiceOption? get selectedDeviceVoice => _selectedDeviceVoice;
  TtsVoiceOption? get selectedGoogleVoice => _selectedGoogleVoice;
  bool get usesGoogleTts => _ttsEngine == 'google';
  Map<String, String>? get currentVoiceMap => _selectedDeviceVoice == null
      ? null
      : {
          'name': _selectedDeviceVoice!.name,
          'locale': _selectedDeviceVoice!.locale,
        };

  JarvisService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(ttsPresetToJarvisRate(_ratePreset));
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.85);
    await _loadDeviceVoices();

    await _cloudPlayer.setReleaseMode(ReleaseMode.stop);
    _cloudPlayer.onPlayerComplete.listen((_) {
      if (_isDisposed) return;
      isSpeaking = false;
      notifyListeners();
      if (!_isTransitioning) {
        _processQueue();
      }
    });

    _tts.setStartHandler(() {
      if (_isDisposed) return;
      isSpeaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      if (_isDisposed) return;
      isSpeaking = false;
      notifyListeners();
      if (!_isTransitioning) {
        _processQueue();
      }
    });
    _tts.setCancelHandler(() {
      if (_isDisposed) return;
      isSpeaking = false;
      notifyListeners();
      if (!_isTransitioning) {
        _processQueue();
      }
    });
  }

  Future<void> _loadDeviceVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      final voices = raw
          .whereType<Map>()
          .map((item) => Map<String, String>.from(item))
          .where((voice) {
            final locale = (voice['locale'] ?? '').toLowerCase();
            return locale.startsWith('ko');
          })
          .map(
            (voice) => TtsVoiceOption(
              name: voice['name'] ?? 'Korean Voice',
              locale: voice['locale'] ?? 'ko-KR',
            ),
          )
          .toList()
        ..sort((a, b) {
          final aScore = _voiceScore(a);
          final bScore = _voiceScore(b);
          if (aScore != bScore) return bScore.compareTo(aScore);
          return a.displayLabel.compareTo(b.displayLabel);
        });
      _deviceVoices = voices;
      if (_selectedDeviceVoice == null && voices.isNotEmpty) {
        await _selectDeviceVoice(voices.first, notify: false);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[TTS] 음성 목록 로드 실패: $e');
    }
  }

  Future<void> _loadGoogleVoices() async {
    try {
      final raw = await _googleTts.fetchVoices();
      final voices = raw
          .map(
            (item) => TtsVoiceOption(
              name: item['name'] ?? GoogleTtsService.defaultVoiceName,
              locale: item['locale'] ?? 'ko-KR',
            ),
          )
          .toList()
        ..sort((a, b) {
          final aScore = _voiceScore(a);
          final bScore = _voiceScore(b);
          if (aScore != bScore) return bScore.compareTo(aScore);
          return a.displayLabel.compareTo(b.displayLabel);
        });
      _googleVoices = voices;
      if (_selectedGoogleVoice == null && voices.isNotEmpty) {
        _selectedGoogleVoice = voices.first;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[GoogleTTS] 음성 목록 로드 실패: $e');
    }
  }

  int _voiceScore(TtsVoiceOption voice) {
    final locale = voice.locale.toLowerCase();
    final name = voice.name.toLowerCase();
    var score = 0;
    if (locale == 'ko-kr' || locale == 'ko_kr') score += 40;
    if (name.contains('premium') || name.contains('enhanced')) score += 24;
    if (name.contains('neural') || name.contains('natural')) score += 18;
    if (name.contains('yuna') || name.contains('sora') || name.contains('suji')) {
      score += 8;
    }
    return score;
  }

  Future<void> _selectDeviceVoice(
    TtsVoiceOption voice, {
    bool notify = true,
  }) async {
    try {
      await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      _selectedDeviceVoice = voice;
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('[TTS] 음성 적용 실패: ${voice.displayLabel} ($e)');
    }
  }

  Future<void> applySettings(SettingsService settings) async {
    setMuted(settings.ttsMuted);
    final nextRatePreset = settings.ttsRatePreset;
    if (_ratePreset != nextRatePreset) {
      _ratePreset = nextRatePreset;
      try {
        await _tts.setSpeechRate(ttsPresetToJarvisRate(_ratePreset));
      } catch (e) {
        debugPrint('[TTS] 속도 적용 실패: $e');
      }
    }

    final nextEngine = settings.ttsEngine;
    if (_ttsEngine != nextEngine) {
      _ttsEngine = nextEngine;
      await _cloudPlayer.stop();
    }

    if (_deviceVoices.isEmpty) {
      await _loadDeviceVoices();
    }

    final preferred = _deviceVoices.cast<TtsVoiceOption?>().firstWhere(
      (voice) =>
          voice != null &&
          voice.name == settings.ttsVoiceName &&
          voice.locale == settings.ttsVoiceLocale,
      orElse: () => null,
    );
    final target =
        preferred ?? (_deviceVoices.isNotEmpty ? _deviceVoices.first : null);
    if (target != null &&
        (_selectedDeviceVoice?.name != target.name ||
            _selectedDeviceVoice?.locale != target.locale)) {
      await _selectDeviceVoice(target, notify: false);
    }

    if (_ttsEngine == 'google') {
      if (_googleVoices.isEmpty) {
        await _loadGoogleVoices();
      }
      final preferredGoogle = _googleVoices.cast<TtsVoiceOption?>().firstWhere(
        (voice) => voice != null && voice.name == settings.googleTtsVoiceName,
        orElse: () => null,
      );
      _selectedGoogleVoice = preferredGoogle ??
          (_googleVoices.isNotEmpty ? _googleVoices.first : null);
    }
    notifyListeners();
  }

  void setMuted(bool value) {
    if (_isMuted == value) return;
    _isMuted = value;
    if (_isMuted) {
      _queue.clear();
      _tts.stop();
      _cloudSpeakToken++;
      _cloudPlayer.stop();
      isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> speak(
    String text, {
    SpeechPriority priority = SpeechPriority.normal,
  }) async {
    final trimmed = text.trim();
    if (_isMuted || trimmed.isEmpty || _isDisposed) return;

    switch (priority) {
      case SpeechPriority.critical:
        await _interruptAndSpeak(trimmed, priority);
        return;
      case SpeechPriority.high:
        _queue.removeWhere(
          (item) =>
              item.priority == SpeechPriority.low ||
              item.priority == SpeechPriority.normal,
        );
        if (!isSpeaking && _queue.isEmpty) {
          await _startSpeaking(_SpeechItem(trimmed, priority));
        } else {
          _queue.add(_SpeechItem(trimmed, priority));
        }
        return;
      case SpeechPriority.normal:
        _queue.removeWhere((item) => item.priority == SpeechPriority.normal);
        if (!isSpeaking && _queue.isEmpty) {
          await _startSpeaking(_SpeechItem(trimmed, priority));
        } else {
          _queue.add(_SpeechItem(trimmed, priority));
        }
        return;
      case SpeechPriority.low:
        if (isSpeaking || _queue.isNotEmpty) return;
        await _startSpeaking(_SpeechItem(trimmed, priority));
        return;
    }
  }

  Future<void> _interruptAndSpeak(String text, SpeechPriority priority) async {
    _queue.removeWhere((item) => item.priority == SpeechPriority.critical);
    if (isSpeaking) {
      _isTransitioning = true;
      _cloudSpeakToken++;
      if (_ttsEngine == 'google') {
        await _cloudPlayer.stop();
      } else {
        await _tts.stop();
      }
      isSpeaking = false;
      _isTransitioning = false;
    }
    await _startSpeaking(_SpeechItem(text, priority));
  }

  Future<void> _startSpeaking(_SpeechItem item) async {
    if (_isMuted || _isDisposed) return;
    lastSpoken = item.text;
    isSpeaking = true;
    notifyListeners();
    try {
      _isTransitioning = true;
      if (_ttsEngine == 'google' && item.priority != SpeechPriority.critical) {
        await _speakWithGoogle(item.text);
      } else {
        await _tts.speak(item.text);
      }
    } catch (_) {
      isSpeaking = false;
      debugPrint('[TTS] 발화 실패: ${item.text}');
      notifyListeners();
      _processQueue();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _speakWithGoogle(String text) async {
    final voiceName =
        _selectedGoogleVoice?.name ?? GoogleTtsService.defaultVoiceName;
    final requestToken = ++_cloudSpeakToken;
    final bytes = await _googleTts.synthesize(text, voiceName: voiceName);
    if (bytes == null || bytes.isEmpty) {
      debugPrint('[GoogleTTS] 합성 실패, 로컬 TTS로 fallback');
      await _tts.speak(text);
      return;
    }
    if (_isDisposed || _isMuted || requestToken != _cloudSpeakToken) return;

    await _cloudPlayer.setPlaybackRate(ttsPresetToGooglePlaybackRate(_ratePreset));
    await _cloudPlayer.play(BytesSource(bytes), volume: 1.0);
  }

  void _processQueue() {
    if (_isMuted || _isDisposed || isSpeaking || _queue.isEmpty) return;
    final nextIndex = _nextQueueIndex();
    final next = _queue.removeAt(nextIndex);
    _startSpeaking(next);
  }

  int _nextQueueIndex() {
    int bestIndex = 0;
    for (int i = 1; i < _queue.length; i++) {
      if (_queue[i].priority.index > _queue[bestIndex].priority.index) {
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> speakWeatherBrief(WeatherService weather) async {
    await speak(weather.weatherBriefLine, priority: SpeechPriority.low);
  }

  @override
  void dispose() {
    _isDisposed = true;
    isSpeaking = false;
    _tts.stop();
    _cloudPlayer.dispose();
    super.dispose();
  }
}
