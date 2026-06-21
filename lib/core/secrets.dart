/// 빌드 시점에 --dart-define 으로 주입되는 API 키 모음.
///
/// 빌드 예시:
///   flutter run \
///     --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
///     --dart-define=OPENWEATHER_API_KEY=...
///
/// VS Code: .vscode/launch.json 의 "args" 에 추가
/// Xcode/Android Studio: Build Configuration 에 추가
class Secrets {
  Secrets._();

  static const anthropicApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  static const openWeatherApiKey = String.fromEnvironment('OPENWEATHER_API_KEY');

  /// 키가 주입됐는지 런타임 체크 (디버그용)
  static bool get hasAnthropicKey => anthropicApiKey.isNotEmpty;
  static bool get hasWeatherKey => openWeatherApiKey.isNotEmpty;
}
