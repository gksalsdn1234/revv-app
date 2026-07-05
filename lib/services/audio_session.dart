import 'package:flutter_tts/flutter_tts.dart';

/// Platform channel seam for iOS TTS audio session configuration.
typedef SetIosAudioCategory =
    Future<Object?> Function(
      IosTextToSpeechAudioCategory category,
      List<IosTextToSpeechAudioCategoryOptions> options,
      IosTextToSpeechAudioMode mode,
    );

/// Shared "speak over music" session: keep other audio playing and duck it.
Future<void> configureMusicDuckingAudioSession({
  required SetIosAudioCategory setIosAudioCategory,
}) async {
  await setIosAudioCategory(IosTextToSpeechAudioCategory.playback, const [
    IosTextToSpeechAudioCategoryOptions.duckOthers,
    IosTextToSpeechAudioCategoryOptions.mixWithOthers,
  ], IosTextToSpeechAudioMode.voicePrompt);
}
