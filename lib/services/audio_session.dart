import 'package:flutter_tts/flutter_tts.dart';

/// Platform channel seam for iOS TTS audio session configuration.
typedef SetIosAudioCategory =
    Future<Object?> Function(
      IosTextToSpeechAudioCategory category,
      List<IosTextToSpeechAudioCategoryOptions> options,
      IosTextToSpeechAudioMode mode,
    );

/// Platform channel seam for `AVAudioSession.setActive`.
typedef SetSharedAudioSession = Future<Object?> Function(bool active);

/// Shared "speak over music" session: keep other audio playing and duck it.
///
/// [setSharedInstance]로 세션을 **활성화**까지 해야 한다. flutter_tts는 카테고리만
/// 설정하고 `setActive`는 하지 않아서, 폰 스피커에서는 우연히 들리지만 카플레이
/// 처럼 다른 세션 주인이 있는 경로에서는 발화가 통째로 사라진다.
Future<void> configureMusicDuckingAudioSession({
  required SetIosAudioCategory setIosAudioCategory,
  SetSharedAudioSession? setSharedInstance,
}) async {
  await setIosAudioCategory(IosTextToSpeechAudioCategory.playback, const [
    IosTextToSpeechAudioCategoryOptions.duckOthers,
    IosTextToSpeechAudioCategoryOptions.mixWithOthers,
  ], IosTextToSpeechAudioMode.voicePrompt);
  await setSharedInstance?.call(true);
}
