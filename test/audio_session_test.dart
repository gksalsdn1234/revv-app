import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:revv_app/services/audio_session.dart';

void main() {
  test(
    'configures the shared music-ducking TTS session through a seam',
    () async {
      IosTextToSpeechAudioCategory? category;
      List<IosTextToSpeechAudioCategoryOptions>? options;
      IosTextToSpeechAudioMode? mode;

      await configureMusicDuckingAudioSession(
        setIosAudioCategory:
            (capturedCategory, capturedOptions, capturedMode) async {
              category = capturedCategory;
              options = capturedOptions;
              mode = capturedMode;
              return null;
            },
      );

      expect(category, IosTextToSpeechAudioCategory.playback);
      expect(options, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ]);
      expect(mode, IosTextToSpeechAudioMode.voicePrompt);
    },
  );
}
