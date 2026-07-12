import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/theme/text_styles.dart';
import 'package:revv_app/ui/route_share_card_content.dart';
import 'package:revv_app/ui/route_share_card_widget.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppText.forceSystemFonts = true;
  });

  tearDownAll(() {
    AppText.forceSystemFonts = false;
  });

  testWidgets('route invite card uses the fixed 4:5 renderer and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestHost(
        child: SizedBox(
          width: RouteShareCardWidget.logicalWidth,
          height: RouteShareCardWidget.logicalHeight,
          child: RouteShareCardWidget(content: _content()),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(RouteShareCardWidget)),
      const Size(360, 450),
    );
    expect(find.bySemanticsLabel('Route invitation card'), findsOneWidget);
    expect(find.bySemanticsLabel('Route silhouette'), findsOneWidget);
    expect(find.text('Drive together this weekend?'), findsOneWidget);
    expect(find.text(_content().routeName), findsOneWidget);
    expect(find.text('84 km'), findsOneWidget);
    expect(find.text('1h 24m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route invite card stays intact when constrained and localized', (
    tester,
  ) async {
    final korean = _content(
      language: AppLanguage.korean,
      name: '북한강 능선 스위퍼와 호숫길 주말 드라이브',
      meetingArea: DriveInviteMeetingArea.easternTownships,
    );
    final french = _content(
      language: AppLanguage.french,
      name: 'Boucle des grands virages des Laurentides',
      meetingArea: DriveInviteMeetingArea.easternTownships,
    );

    for (final content in [korean, french]) {
      await tester.pumpWidget(
        _TestHost(
          textScaleFactor: 1.3,
          child: SizedBox(
            width: 280,
            height: 350,
            child: RouteShareCardWidget(content: content),
          ),
        ),
      );

      expect(find.text(content.routeName), findsOneWidget);
      expect(find.text(content.schedule), findsOneWidget);
      expect(find.text(content.meetingAreaLabel!), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('route invite card exports a 1080 by 1350 PNG', (tester) async {
    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      _TestHost(
        child: SizedBox(
          width: RouteShareCardWidget.logicalWidth,
          height: RouteShareCardWidget.logicalHeight,
          child: RepaintBoundary(
            key: repaintKey,
            child: RouteShareCardWidget(content: _content()),
          ),
        ),
      ),
    );

    final bytes = await tester.runAsync(
      () => exportRouteShareCardPngBytes(repaintKey),
    );
    expect(bytes, isNotNull);
    final png = bytes!;
    expect(
      png.take(8),
      orderedEquals(const <int>[137, 80, 78, 71, 13, 10, 26, 10]),
    );
    final evidenceWritten = await tester.runAsync(() async {
      final evidence = File('.omo/evidence/task-4-drive-invite-share-card.png');
      await evidence.parent.create(recursive: true);
      await evidence.writeAsBytes(png, flush: true);
      return evidence.exists();
    });
    expect(evidenceWritten, isTrue);

    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
      final frame = await codec.getNextFrame();
      return (codec: codec, image: frame.image);
    });
    expect(decoded, isNotNull);
    expect(decoded!.image.width, 1080);
    expect(decoded.image.height, 1350);
    decoded.image.dispose();
    decoded.codec.dispose();
    expect(tester.takeException(), isNull);
  });
}

class _TestHost extends StatelessWidget {
  final Widget child;
  final double textScaleFactor;

  const _TestHost({required this.child, this.textScaleFactor = 1});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: child),
        ),
      ),
    );
  }
}

RouteShareCardContent _content({
  AppLanguage language = AppLanguage.english,
  String name = 'Lakeside Sweepers',
  DriveInviteMeetingArea? meetingArea = DriveInviteMeetingArea.oldPort,
}) {
  var draft = DriveInviteDraft.forLanguage(language);
  draft = draft.withMeetingArea(meetingArea);
  return buildRouteShareCardContent(
    route: RevvRoute(
      id: 'route-1',
      name: name,
      nodes: const [
        LatLng(45.50, -73.57),
        LatLng(45.52, -73.56),
        LatLng(45.51, -73.53),
        LatLng(45.54, -73.54),
      ],
      distanceKm: 84,
      windingScore: 5,
      starRating: 4,
      sharpCurveCount: 12,
      centerPoint: const LatLng(45.51, -73.55),
      distanceFromUser: 25,
      mediumCurveKm: 1.2,
      elevationDelta: 72,
      isLoop: true,
    ),
    draft: draft,
    language: language,
  );
}
