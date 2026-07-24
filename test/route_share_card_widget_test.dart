import 'dart:io';
import 'dart:math' as math;
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
    expect(find.text('84 km'), findsOneWidget);
    expect(find.text('1h 24m'), findsOneWidget);
    expect(find.text('CURVE MIX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route invite card localizes every visible static label', (
    tester,
  ) async {
    // Given: every supported card language without a selected meeting area.
    const labels = {
      AppLanguage.korean: ('거리', '주행 시간', '코너', '커브 구성'),
      AppLanguage.english: ('DISTANCE', 'DURATION', 'CORNERS', 'CURVE MIX'),
      AppLanguage.french: ('DISTANCE', 'DURÉE', 'VIRAGES', 'TYPE DE VIRAGES'),
    };

    // When: each language is rendered through the card content contract.
    for (final language in AppLanguage.values) {
      final content = _content(language: language, meetingArea: null);
      await tester.pumpWidget(
        _TestHost(
          child: SizedBox(
            width: RouteShareCardWidget.logicalWidth,
            height: RouteShareCardWidget.logicalHeight,
            child: RouteShareCardWidget(content: content),
          ),
        ),
      );

      // Then: every static, visible label matches the card language. The spec
      // row and curve-mix heading render uppercased, so Korean (which has no
      // case) is asserted as-is while the Latin locales are asserted uppercase.
      final (distance, duration, corners, curveMix) = labels[language]!;
      expect(find.text(distance), findsOneWidget);
      expect(find.text(duration), findsOneWidget);
      expect(find.text(corners), findsOneWidget);
      expect(find.text(curveMix), findsOneWidget);
      expect(find.text(content.headline), findsOneWidget);
      expect(find.text('REVV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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

      expect(find.text(content.headline), findsOneWidget);
      expect(find.text(content.schedule.toUpperCase()), findsOneWidget);
      expect(
        find.textContaining(content.meetingAreaLabel!.toUpperCase()),
        findsOneWidget,
      );
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
      final evidenceDirectory = await Directory.systemTemp.createTemp(
        'revv-route-share-card-',
      );
      addTearDown(() => evidenceDirectory.delete(recursive: true));
      final evidence = File('${evidenceDirectory.path}/route-share-card.png');
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

/// Road-resolution winding geometry (~15 m sampling). The curve-mix block only
/// renders for routes that actually contain corners, so a four-point fixture
/// would silently drop it from every assertion below.
List<LatLng> _windingNodes() {
  const mPerDegLat = 111320.0;
  final mPerDegLng = 111320.0 * math.cos(45.5 * math.pi / 180);
  var lat = 45.50;
  var lng = -73.57;
  var bearing = math.pi / 2;
  final out = <LatLng>[LatLng(lat, lng)];

  void addArc(double radiusMeters, double sweepDegrees) {
    final sweep = sweepDegrees * math.pi / 180;
    final arcLength = radiusMeters * sweep.abs();
    final steps = math.max(3, (arcLength / 15).round());
    for (var i = 0; i < steps; i++) {
      final stepLength = arcLength / steps;
      lat += stepLength * math.cos(bearing) / mPerDegLat;
      lng += stepLength * math.sin(bearing) / mPerDegLng;
      bearing += sweep / steps;
      out.add(LatLng(lat, lng));
    }
  }

  for (var i = 0; i < 4; i++) {
    addArc(220, 70);
    addArc(180, -80);
    addArc(60, 95);
    addArc(1200, -40);
    addArc(24, -150);
  }
  return out;
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
      nodes: _windingNodes(),
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
