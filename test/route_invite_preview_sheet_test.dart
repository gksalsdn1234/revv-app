import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/ui/route_share_card_content.dart';
import 'package:revv_app/widgets/route_invite_preview_sheet.dart';

final _route = RevvRoute(
  id: 'invite-preview-route',
  name: 'Private route name',
  nodes: const [
    LatLng(45.5017, -73.5673),
    LatLng(45.5117, -73.5573),
    LatLng(45.5217, -73.5773),
  ],
  distanceKm: 84,
  windingScore: 6.6,
  starRating: 4,
  sharpCurveCount: 12,
  elevationDelta: 62,
  centerPoint: const LatLng(45.5117, -73.5573),
  distanceFromUser: 8,
  isLoop: true,
  mediumCurveKm: 1.2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens a safe default card and returns the default draft', (
    tester,
  ) async {
    RouteInvitePreviewResult? sharedInvite;
    await _pumpLauncher(
      tester,
      onOpen: () async {
        sharedInvite = await showRouteInvitePreviewSheet(
          tester.element(find.byType(ElevatedButton)),
          route: _route,
          language: AppLanguage.english,
          cardExporter: (_) async =>
              Uint8List.fromList(const [137, 80, 78, 71]),
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('open-invite-preview')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('route-invite-preview-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-invite-card-preview')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('route-invite-card-preview')),
          matching: find.byType(RepaintBoundary),
        ),
      ),
      const Size(360, 450),
    );
    // 카드는 일정을 테크니컬 라벨(대문자)로 그린다 — 초안 데이터는 원문 그대로.
    expect(find.text('THIS WEEKEND · TIME TBD'), findsOneWidget);
    expect(find.text('No meeting area'), findsOneWidget);
    expect(find.text('Share invite'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-invite-draft')));
    await tester.pumpAndSettle();

    expect(sharedInvite, isNotNull);
    expect(sharedInvite!.draft.meetingArea, isNull);
    expect(sharedInvite!.draft.schedule, 'This weekend · time TBD');
    expect(sharedInvite!.cardPng, orderedEquals(const [137, 80, 78, 71]));
  });

  testWidgets('switches the optional meeting area before sharing', (
    tester,
  ) async {
    RouteInvitePreviewResult? sharedInvite;
    await _pumpLauncher(
      tester,
      onOpen: () async {
        sharedInvite = await showRouteInvitePreviewSheet(
          tester.element(find.byType(ElevatedButton)),
          route: _route,
          language: AppLanguage.english,
          cardExporter: (_) async =>
              Uint8List.fromList(const [137, 80, 78, 71]),
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('open-invite-preview')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('invite-meeting-area-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near Old Port').last);
    await tester.pumpAndSettle();

    expect(find.text('Near Old Port'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('share-invite-draft')));
    await tester.pumpAndSettle();

    expect(sharedInvite!.draft.meetingArea, DriveInviteMeetingArea.oldPort);
  });

  testWidgets('dismisses without returning a draft', (tester) async {
    RouteInvitePreviewResult? returnedInvite;
    await _pumpLauncher(
      tester,
      onOpen: () async {
        returnedInvite = await showRouteInvitePreviewSheet(
          tester.element(find.byType(ElevatedButton)),
          route: _route,
          language: AppLanguage.english,
          cardExporter: (_) async =>
              Uint8List.fromList(const [137, 80, 78, 71]),
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('open-invite-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dismiss-invite-preview')));
    await tester.pumpAndSettle();

    expect(returnedInvite, isNull);
    expect(
      find.byKey(const ValueKey('route-invite-preview-sheet')),
      findsNothing,
    );
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required Future<void> Function() onOpen,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsService>.value(
      value: SettingsService(),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-invite-preview'),
              onPressed: onOpen,
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
