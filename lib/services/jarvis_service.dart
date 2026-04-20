import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'weather_service.dart';

enum SpeechPriority { low, normal, high, critical }

class _SpeechItem {
  final String text;
  final SpeechPriority priority;

  const _SpeechItem(this.text, this.priority);
}

class JarvisService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  final List<_SpeechItem> _queue = [];

  bool isSpeaking = false;
  String? lastSpoken;
  bool _isMuted = false;
  bool _isDisposed = false;
  bool _isTransitioning = false;

  JarvisService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.85);

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

  void setMuted(bool value) {
    if (_isMuted == value) return;
    _isMuted = value;
    if (_isMuted) {
      _queue.clear();
      _tts.stop();
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
      await _tts.stop();
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
      await _tts.speak(item.text);
    } catch (_) {
      isSpeaking = false;
      debugPrint('[TTS] 발화 실패: ${item.text}');
      notifyListeners();
      _processQueue();
    } finally {
      _isTransitioning = false;
    }
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
    super.dispose();
  }
}
