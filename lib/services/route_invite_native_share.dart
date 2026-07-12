import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef RouteInviteSystemShare =
    Future<ShareResult> Function(ShareParams params);
typedef RouteInviteTemporaryDirectory = Future<Directory> Function();
typedef RouteInviteCardWriter = Future<void> Function(File file, Uint8List png);

/// The only delivery payload that leaves the invite-preview flow.
///
/// Its text has already passed the card-content allowlist. Route geometry is
/// permitted only inside the separately constructed Google Maps HTTPS URL in
/// that final text. This boundary never receives a route, meeting-area
/// selection, or telemetry object.
class RouteInviteSharePayload {
  final String text;
  final Uint8List cardPng;

  const RouteInviteSharePayload({required this.text, required this.cardPng});
}

enum RouteInviteShareOutcome { shared, cancelled, unavailable }

/// Writes one ephemeral card attachment and opens exactly one native share
/// sheet. The file remains available until the platform call completes, then
/// is removed on both completion and failure.
class RouteInviteNativeShare {
  final RouteInviteTemporaryDirectory _temporaryDirectory;
  final RouteInviteSystemShare _systemShare;
  final RouteInviteCardWriter _cardWriter;
  final Random _random;

  RouteInviteNativeShare({
    RouteInviteTemporaryDirectory temporaryDirectory = getTemporaryDirectory,
    RouteInviteSystemShare systemShare = _shareWithSystemSheet,
    RouteInviteCardWriter cardWriter = _writePngFile,
    Random? random,
  }) : _temporaryDirectory = temporaryDirectory,
       _systemShare = systemShare,
       _cardWriter = cardWriter,
       _random = random ?? Random.secure();

  Future<RouteInviteShareOutcome> share(RouteInviteSharePayload payload) async {
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/revv-route-invite-${_nextFileNonce()}.png',
    );

    try {
      await _cardWriter(file, payload.cardPng);
      final result = await _systemShare(
        ShareParams(
          text: payload.text,
          files: [XFile(file.path, mimeType: 'image/png')],
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => RouteInviteShareOutcome.shared,
        ShareResultStatus.dismissed => RouteInviteShareOutcome.cancelled,
        ShareResultStatus.unavailable => RouteInviteShareOutcome.unavailable,
      };
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  String _nextFileNonce() {
    final high = _random.nextInt(1 << 32).toRadixString(16);
    final low = _random.nextInt(1 << 32).toRadixString(16);
    return '$high$low';
  }
}

Future<void> _writePngFile(File file, Uint8List png) {
  return file.writeAsBytes(png, flush: true);
}

Future<ShareResult> _shareWithSystemSheet(ShareParams params) {
  return SharePlus.instance.share(params);
}
