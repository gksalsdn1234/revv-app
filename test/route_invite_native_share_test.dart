import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/route_invite_native_share.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'shares one PNG and safe text before deleting the temporary file',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'revv-route-invite-test-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      ShareParams? captured;
      File? sharedFile;
      final share = RouteInviteNativeShare(
        temporaryDirectory: () async => temporaryDirectory,
        systemShare: (params) async {
          captured = params;
          sharedFile = File(params.files!.single.path);
          expect(await sharedFile!.exists(), isTrue);
          return const ShareResult('sent', ShareResultStatus.success);
        },
      );

      final outcome = await share.share(
        RouteInviteSharePayload(
          text:
              'Drive together this weekend?\nhttps://www.google.com/maps/dir/',
          cardPng: Uint8List.fromList(const [137, 80, 78, 71]),
        ),
      );

      expect(outcome, RouteInviteShareOutcome.shared);
      expect(captured!.text, contains('https://www.google.com/maps/dir/'));
      expect(captured!.files, hasLength(1));
      expect(captured!.files!.single.mimeType, 'image/png');
      expect(await sharedFile!.exists(), isFalse);
    },
  );

  test('deletes the temporary PNG when the native share throws', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'revv-route-invite-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    File? sharedFile;
    final share = RouteInviteNativeShare(
      temporaryDirectory: () async => temporaryDirectory,
      systemShare: (params) async {
        sharedFile = File(params.files!.single.path);
        throw StateError('native share failed');
      },
    );

    await expectLater(
      () => share.share(
        RouteInviteSharePayload(
          text: 'Safe route invite',
          cardPng: Uint8List.fromList(const [137, 80, 78, 71]),
        ),
      ),
      throwsStateError,
    );

    expect(await sharedFile!.exists(), isFalse);
  });

  test(
    'keeps the temporary PNG until a cancelled native share completes',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'revv-route-invite-test-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      File? sharedFile;
      final share = RouteInviteNativeShare(
        temporaryDirectory: () async => temporaryDirectory,
        systemShare: (params) async {
          sharedFile = File(params.files!.single.path);
          expect(await sharedFile!.exists(), isTrue);
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );

      final outcome = await share.share(
        RouteInviteSharePayload(
          text: 'Safe route invite',
          cardPng: Uint8List.fromList(const [137, 80, 78, 71]),
        ),
      );

      expect(outcome, RouteInviteShareOutcome.cancelled);
      expect(await sharedFile!.exists(), isFalse);
    },
  );
}
