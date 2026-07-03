import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:revv_app/theme/text_styles.dart';
import 'package:revv_app/ui/run_share_card_content.dart';
import 'package:revv_app/ui/run_share_card_widget.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppText.forceSystemFonts = true;
  });

  tearDownAll(() {
    AppText.forceSystemFonts = false;
  });

  testWidgets('ride share card renders square layout', (tester) async {
    await tester.pumpWidget(
      _TestHost(
        child: SizedBox.square(
          dimension: 320,
          child: RunShareCardWidget(content: _content()),
        ),
      ),
    );

    expect(find.text('Forest Sweep'), findsOneWidget);
    expect(find.text('Jun 30, 2026'), findsOneWidget);
    expect(find.textContaining('REVV'), findsWidgets);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('12.3 km'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('12m 34s'), findsOneWidget);
    expect(find.text('SQUARE'), findsOneWidget);
    expect(
      tester.getSize(find.byType(RunShareCardWidget)),
      const Size(320, 320),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ride share card truncates long route names without overflow', (
    tester,
  ) async {
    final longRouteName =
        'North Cascades Forest Switchback Ridge Connector With A Very Long '
        'Unofficial Local Segment Name That Should Never Break Share Layouts';

    await tester.pumpWidget(
      _TestHost(
        child: SizedBox.square(
          dimension: 260,
          child: RunShareCardWidget(
            content: _content(
              title: longRouteName,
              subtitle: 'Long route check',
            ),
          ),
        ),
      ),
    );

    final titleText = tester.widget<Text>(find.text(longRouteName));
    expect(titleText.overflow, TextOverflow.ellipsis);
    expect(titleText.maxLines, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ride share card exports png bytes', (tester) async {
    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      _TestHost(
        child: SizedBox.square(
          dimension: 320,
          child: RepaintBoundary(
            key: repaintKey,
            child: RunShareCardWidget(content: _content()),
          ),
        ),
      ),
    );

    final export = await tester.runAsync(() async {
      final file = await exportRunShareCardPngFile(
        repaintKey: repaintKey,
        directory: Directory('.omo/evidence/revv-ride-data-sharing'),
        fileName: 'task-13-share-card.png',
        pixelRatio: 2,
      );
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return (file: file, bytes: bytes, codec: codec, frame: frame);
    });
    expect(export, isNotNull);
    final file = export!.file;
    final bytes = export.bytes;
    final codec = export.codec;
    final frame = export.frame;
    final image = frame.image;

    expect(file.path, endsWith('task-13-share-card.png'));
    expect(bytes.length, greaterThan(0));
    expect(image.width, 640);
    expect(image.height, 640);
    expect(tester.takeException(), isNull);
    image.dispose();
    codec.dispose();
  });

  testWidgets('ride share card export fails before layout', (tester) async {
    final repaintKey = GlobalKey();

    await expectLater(
      exportRunShareCardPngBytes(repaintKey),
      throwsA(isA<StateError>()),
    );
  });
}

class _TestHost extends StatelessWidget {
  final Widget child;

  const _TestHost({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: child),
      ),
    );
  }
}

RunShareCardContent _content({
  String title = 'Forest Sweep',
  String subtitle = 'Jun 30, 2026 - REVV recap',
}) {
  return RunShareCardContent(
    preset: ShareCardPreset.square,
    presetInfo: const ShareCardPresetInfo(
      preset: ShareCardPreset.square,
      label: 'Square',
      aspectRatio: 1,
      isCompact: false,
      background: ShareCardBackground.solid,
    ),
    title: title,
    subtitle: subtitle,
    routeName: title,
    dateLabel: 'Jun 30, 2026',
    metricChips: const [
      RunShareCardMetric(label: 'Distance', value: '12.3 km'),
      RunShareCardMetric(label: 'Duration', value: '12m 34s'),
      RunShareCardMetric(label: 'REVV Score', value: '68'),
      RunShareCardMetric(label: 'Winding', value: '43%'),
      RunShareCardMetric(label: 'Smoothness', value: '80'),
    ],
    metricList: const [
      RunShareCardMetric(label: 'Distance', value: '12.3 km'),
      RunShareCardMetric(label: 'Duration', value: '12m 34s'),
      RunShareCardMetric(label: 'REVV Score', value: '68'),
      RunShareCardMetric(label: 'Winding', value: '43%'),
      RunShareCardMetric(label: 'Smoothness', value: '80'),
    ],
    pathPreview: const [
      RunSharePathPoint(x: 0.06, y: 0.78),
      RunSharePathPoint(x: 0.18, y: 0.62),
      RunSharePathPoint(x: 0.34, y: 0.68),
      RunSharePathPoint(x: 0.46, y: 0.38),
      RunSharePathPoint(x: 0.62, y: 0.44),
      RunSharePathPoint(x: 0.74, y: 0.22),
      RunSharePathPoint(x: 0.90, y: 0.30),
    ],
    footer: 'sunny 22 C',
  );
}
