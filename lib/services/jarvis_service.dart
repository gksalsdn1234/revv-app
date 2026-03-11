import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'weather_service.dart';

class JarvisService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  bool isSpeaking = false;
  String? lastSpoken;

  JarvisService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.85);

    _tts.setCompletionHandler(() {
      isSpeaking = false;
      notifyListeners();
    });
  }

  Future<void> speak(String text) async {
    if (isSpeaking) await _tts.stop();
    lastSpoken = text;
    isSpeaking = true;
    notifyListeners();
    await _tts.speak(text);
  }

  Future<void> speakWeatherBrief(WeatherService weather) async {
    await speak(weather.weatherBriefLine);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
