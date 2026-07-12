import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef RouteInviteSystemShare =
    Future<ShareResult> Function(ShareParams params);
typedef RouteInviteTemporaryDirectory = Future<Directory> Function();

/// The only delivery payload that leaves the invite-preview flow.
///
/// Its text has already passed the card-content allowlist. The PNG is rendered
/// from that same content before delivery, so this boundary never receives a
/// route, meeting-area selection, or telemetry object.
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

  RouteInviteNativeShare({
    RouteInviteTemporaryDirectory temporaryDirectory = getTemporaryDirectory,
    RouteInviteSystemShare systemShare = _shareWithSystemSheet,
  }) : _temporaryDirectory = temporaryDirectory,
       _systemShare = systemShare;

  Future<RouteInviteShareOutcome> share(RouteInviteSharePayload payload) async {
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/revv-route-invite-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(payload.cardPng, flush: true);

    try {
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
}

Future<ShareResult> _shareWithSystemSheet(ShareParams params) {
  return SharePlus.instance.share(params);
}
