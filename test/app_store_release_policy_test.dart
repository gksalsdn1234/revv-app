import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App Store release policy', () {
    test('ships no unlicensed walkie beep implementation or package', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final controller = File(
        'lib/labs/walkie/walkie_ptt_controller.dart',
      ).readAsStringSync();

      expect(File('assets/sounds/beep.mp3').existsSync(), isFalse);
      expect(pubspec, isNot(contains('audioplayers:')));
      expect(pubspec, isNot(contains('assets/sounds/beep.mp3')));
      expect(controller, isNot(contains('BeepWalkieChirp')));
      expect(controller, isNot(contains('WalkieChirp')));
      expect(controller, isNot(contains("sounds/beep.mp3")));
    });

    test('native launch screen is the only startup loading identity', () {
      final storyboard = File(
        'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      expect(storyboard, isNot(contains('image="LaunchImage"')));
      expect(storyboard, contains('userLabel="Launch F1 Lights"'));
      expect(storyboard, contains('userLabel="Launch Logo RE"'));
      expect(storyboard, contains('userLabel="Launch Logo VV"'));
      expect(storyboard, isNot(contains('Find the road.')));
      expect(storyboard, isNot(contains('Start the drive.')));
      expect(main, contains('home: const LeanAppShellScreen()'));
      expect(main, isNot(contains('LoadingScreen')));

      for (final locale in ['en', 'fr', 'ko']) {
        final strings = File('ios/Runner/$locale.lproj/LaunchScreen.strings');
        expect(strings.existsSync(), isTrue, reason: '$locale launch copy');
        expect(strings.readAsStringSync(), contains('launch-tagline.text'));
        expect(strings.readAsStringSync(), contains('launch-title.text'));
        expect(strings.readAsStringSync(), isNot(contains(RegExp(r'[가-힣]'))));
      }
    });

    test('permission copy is concise and localized by iOS', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final shell = File(
        'lib/screens/lean_app_shell_screen.dart',
      ).readAsStringSync();

      expect(infoPlist, isNot(contains('NSSpeechRecognitionUsageDescription')));
      expect(infoPlist, isNot(contains('<string>audio</string>')));
      expect(infoPlist, isNot(contains(' / REVV')));
      expect(infoPlist, contains('NSMotionUsageDescription'));
      expect(infoPlist, contains('<key>CFBundleLocalizations</key>'));
      expect(shell, contains('settingsLanguageDetail'));
      expect(shell, isNot(contains('onChanged: settings.setAppLanguage')));

      for (final locale in ['en', 'fr', 'ko']) {
        final strings = File('ios/Runner/$locale.lproj/InfoPlist.strings');
        expect(strings.existsSync(), isTrue, reason: '$locale localization');
        expect(
          strings.readAsStringSync(),
          contains('NSLocationWhenInUseUsageDescription'),
        );
        expect(
          strings.readAsStringSync(),
          contains('NSMotionUsageDescription'),
        );
      }
    });

    test('privacy manifest covers product interaction telemetry', () {
      final manifest = File(
        'ios/Runner/PrivacyInfo.xcprivacy',
      ).readAsStringSync();

      expect(
        manifest,
        contains('NSPrivacyCollectedDataTypeProductInteraction'),
      );
    });

    test('every shipped App Store icon is opaque', () {
      final icons = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'));

      expect(icons, isNotEmpty);
      for (final icon in icons) {
        final result = Process.runSync('sips', ['-g', 'hasAlpha', icon.path]);
        expect(result.exitCode, 0, reason: icon.path);
        expect(result.stdout, contains('hasAlpha: no'), reason: icon.path);
      }
    });

    test(
      'bottom navigation selection and visible build metadata stay current',
      () {
        final shell = File(
          'lib/screens/lean_app_shell_screen.dart',
        ).readAsStringSync();

        expect(
          shell,
          contains('final color = active ? AppColors.red : AppColors.stone;'),
        );
        expect(shell, contains('PackageInfo.fromPlatform()'));
        expect(shell, isNot(contains('1.38.0+42')));
      },
    );

    test('map controls do not overlap Mapbox ornaments', () {
      final mapWidget = File('lib/widgets/map_widget.dart').readAsStringSync();
      final shell = File(
        'lib/screens/lean_app_shell_screen.dart',
      ).readAsStringSync();

      expect(mapWidget, contains('_configureMapOrnaments'));
      expect(mapWidget, contains('mbx.ScaleBarSettings(enabled: false)'));
      expect(mapWidget, contains('_scheduleDifficultyLines'));
      expect(mapWidget, contains('mbx.OrnamentPosition.TOP_LEFT'));
      expect(mapWidget, contains('marginTop: 400'));
      expect(shell, contains('https://www.openstreetmap.org/copyright'));
      expect(shell, contains('LinkTarget.blank'));
      expect(shell, contains('link: true'));
      expect(shell, contains('linkUrl: _openStreetMapCopyrightUri'));
      expect(shell, contains('AppCopy.mapDataCreditsDetail(language)'));
    });

    test('release target matches the phone-first reviewed UI surface', () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();

      expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2";')));
      expect(
        RegExp(r'TARGETED_DEVICE_FAMILY = 1;').allMatches(project).length,
        3,
      );
    });

    test('transient drive recovery is excluded from device backups', () {
      final androidManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final recoveryStore = File(
        'lib/services/run_recovery_store.dart',
      ).readAsStringSync();

      expect(androidManifest, contains('android:allowBackup="false"'));
      expect(recoveryStore, contains('getTemporaryDirectory'));
      expect(
        recoveryStore,
        isNot(contains('getApplicationDocumentsDirectory')),
      );
    });

    test('Android release builds never reuse the debug signing identity', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
      expect(gradle, contains('REVV_ANDROID_KEYSTORE_PATH'));
      expect(gradle, contains('REVV_ANDROID_KEY_ALIAS'));
    });

    test('metered Edge requests are bounded before JSON parsing', () {
      final callAi = File(
        'supabase/functions/call-ai/index.ts',
      ).readAsStringSync();
      final security = File(
        'supabase/functions/_shared/security.ts',
      ).readAsStringSync();

      expect(callAi, contains('readJsonWithLimit(req, maxRequestBytes)'));
      expect(callAi, isNot(contains('await req.json()')));
      expect(
        security,
        contains('rateLimitKeys(verifiedSub, forwardedFor, secret)'),
      );
      expect(
        security,
        contains('if (!response.ok) return false;'),
        reason: 'database rate-limit errors must fail closed',
      );
    });

    test('account deletion only confirms an explicit server success', () {
      final service = File(
        'lib/services/supabase_service.dart',
      ).readAsStringSync();

      expect(service, isNot(contains('accountMissing')));
      expect(
        service,
        contains(
          'if (currentUid == null || currentUid != pendingUid) {\n'
          '      return false;',
        ),
      );
      expect(
        service,
        isNot(
          contains(
            'await prefs.remove(StorageKeys.pendingAccountDeletionUid);',
          ),
        ),
      );
    });

    test('account deletion Edge function is gateway-bound and idempotent', () {
      final config = File('supabase/config.toml').readAsStringSync();
      final function = File(
        'supabase/functions/delete-account/index.ts',
      ).readAsStringSync();

      expect(config, contains('[functions.delete-account]\nverify_jwt = true'));
      expect(function, contains('gatewayVerifiedJwtSub'));
      expect(function, isNot(contains('verifiedJwtSub')));
      expect(function, contains('response.status !== 404'));
    });
  });
}
