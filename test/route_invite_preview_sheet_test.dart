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
    DriveInviteDraft? sharedDraft;
    await _pumpLauncher(
      tester,
      onOpen: () async {
        sharedDraft = await showRouteInvitePreviewSheet(
          tester.element(find.byType(ElevatedButton)),
          route: _route,
          language: AppLanguage.english,
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
    expect(find.text('This weekend · time TBD'), findsOneWidget);
    expect(find.text('No meeting area'), findsOneWidget);
    expect(find.text('Share invite'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-invite-draft')));
    await tester.pumpAndSettle();

    expect(sharedDraft, isNotNull);
    expect(sharedDraft!.meetingArea, isNull);
    expect(sharedDraft!.schedule, 'This weekend · time TBD');
  });

  testWidgets('switches the optional meeting area before sharing', (
    tester,
  ) async {
    DriveInviteDraft? sharedDraft;
    await _pumpLauncher(
      tester,
      onOpen: () async {
        sharedDraft = await showRouteInvitePreviewSheet(
          tester.element(find.byType(ElevatedButton)),
          route: _route,
          language: AppLanguage.english,
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

    expect(sharedDraft!.meetingArea, DriveInviteMeetingArea.oldPort);
  });

  testWidgets('dismisses without returning a draft', (tester) async {
    DriveInviteDraft? returnedDraft = DriveInviteDraft.forLanguage(
      AppLanguage.english,
    );
    await _pumpLauncher(
      tester,
      onOpen: () async {
        returnedDraft = await showRouteInvitePreviewSheet(
          tester.element(find.byType(ElevatedButton)),
          route: _route,
          language: AppLanguage.english,
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('open-invite-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dismiss-invite-preview')));
    await tester.pumpAndSettle();

    expect(returnedDraft, isNull);
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
