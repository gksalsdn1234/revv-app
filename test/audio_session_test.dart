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
      final activations = <bool>[];

      await configureMusicDuckingAudioSession(
        setIosAudioCategory:
            (capturedCategory, capturedOptions, capturedMode) async {
              category = capturedCategory;
              options = capturedOptions;
              mode = capturedMode;
              return null;
            },
        setSharedInstance: (active) async {
          // 카테고리 설정 뒤에 활성화되어야 한다.
          expect(category, isNotNull);
          activations.add(active);
          return null;
        },
      );

      expect(category, IosTextToSpeechAudioCategory.playback);
      expect(options, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ]);
      expect(mode, IosTextToSpeechAudioMode.voicePrompt);
      expect(activations, [true]);
    },
  );

  test(
    'session activation stays optional for callers without the seam',
    () async {
      await configureMusicDuckingAudioSession(
        setIosAudioCategory: (_, _, _) async => null,
      );
    },
  );
}
