import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();

  Future<void> playBeep() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/beep.mp3'));
    } catch (_) {}
  }
}
