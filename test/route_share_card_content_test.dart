import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/route_share_card_content.dart';

RevvRoute _route({
  String name = 'Lakeside Sweepers',
  List<LatLng>? nodes,
  List<String> roadNames = const ['Chemin Confidential'],
  List<String> nearbyPoiNames = const ['Café du Parc'],
}) {
  return RevvRoute(
    id: 'route-1',
    name: name,
    nodes:
        nodes ??
        const [
          LatLng(45.5017123, -73.5678901),
          LatLng(45.5117123, -73.5578901),
          LatLng(45.5067123, -73.5478901),
        ],
    distanceKm: 84,
    windingScore: 9,
    starRating: 5,
    sharpCurveCount: 0,
    centerPoint: const LatLng(45.5099123, -73.5578901),
    distanceFromUser: 25,
    tightCurveKm: 0.2,
    mediumCurveKm: 8.1,
    elevationDelta: 64,
    isLoop: true,
    routeCharacter: 'fast_sweeper',
    roadNames: roadNames,
    nearbyPoiNames: nearbyPoiNames,
    speedLimitSummary: '181 km/h',
  );
}

void main() {
  group('DriveInviteDraft', () {
    test('uses a localized time-TBD schedule by default', () {
      // Given: each supported display language.
      const expected = {
        AppLanguage.korean: '이번 주말 · 시간 미정',
        AppLanguage.english: 'This weekend · time TBD',
        AppLanguage.french: 'Ce week-end · heure à confirmer',
      };

      // When: a new invite draft is started.
      final drafts = {
        for (final language in AppLanguage.values)
          language: DriveInviteDraft.forLanguage(language),
      };

      // Then: it has no selected area and shows the local schedule copy.
      for (final language in AppLanguage.values) {
        expect(drafts[language]!.schedule, expected[language]);
        expect(drafts[language]!.meetingArea, isNull);
      }
    });

    test('keeps an enum-selected meeting area ephemeral and nullable', () {
      // Given: a new English invite draft.
      final draft = DriveInviteDraft.forLanguage(AppLanguage.english);

      // When: the sender selects an approved area, then clears it.
      final selected = draft.withMeetingArea(DriveInviteMeetingArea.oldPort);
      final cleared = selected.withMeetingArea(null);

      // Then: only a closed meeting-area value can enter the draft.
      expect(selected.meetingArea, DriveInviteMeetingArea.oldPort);
      expect(cleared.meetingArea, isNull);
      expect(selected.schedule, 'This weekend · time TBD');
    });

    test('has no free-form meeting-area input API', () {
      // Given: a new English invite draft.
      final draft = DriveInviteDraft.forLanguage(AppLanguage.english);

      // When: its selector is bound to the closed enum function type.
      final DriveInviteDraft Function(DriveInviteMeetingArea?) selectArea =
          draft.withMeetingArea;

      // Then: strings cannot be supplied through the public draft API.
      expect(
        selectArea(DriveInviteMeetingArea.westIsland).meetingArea,
        DriveInviteMeetingArea.westIsland,
      );
    });

    test('localizes every closed meeting-area choice in card content', () {
      // Given: each supported locale and the entire closed area enum.
      const areas = DriveInviteMeetingArea.values;

      // When: content is built for each selected area.
      final cards = <RouteShareCardContent>[
        for (final language in AppLanguage.values)
          for (final area in areas)
            buildRouteShareCardContent(
              route: _route(),
              draft: DriveInviteDraft.forLanguage(
                language,
              ).withMeetingArea(area),
              language: language,
            ),
      ];

      // Then: every selected enum has localized derived copy, not sender text.
      for (final card in cards) {
        expect(card.meetingAreaLabel, isNotNull);
      }
      expect(cards.first.meetingAreaLabel, '올드 포트 근처');
      expect(cards[areas.length].meetingAreaLabel, 'Near Old Port');
      expect(cards[areas.length * 2].meetingAreaLabel, 'Près du Vieux-Port');
    });
  });

  group('RouteShareCardContent', () {
    test('builds an abstract pre-drive card from the public allowlist', () {
      // Given: a route with validated derived characteristics and a selected area.
      final draft = DriveInviteDraft.forLanguage(
        AppLanguage.english,
      ).withMeetingArea(DriveInviteMeetingArea.oldPort);

      // When: its sender-facing card content is built.
      final content = buildRouteShareCardContent(
        route: _route(),
        draft: draft,
        language: AppLanguage.english,
      );

      // Then: only display facts, abstract geometry, and two tags are exposed.
      expect(content.routeName, 'REVV route');
      expect(content.distanceLabel, '84 km');
      expect(content.durationLabel, '1h 24m');
      expect(content.schedule, 'This weekend · time TBD');
      expect(content.meetingArea, DriveInviteMeetingArea.oldPort);
      expect(content.meetingAreaLabel, 'Near Old Port');
      expect(content.tags.length, lessThanOrEqualTo(2));
      expect(content.silhouette, hasLength(3));
      expect(content.silhouette.first.x, 0);
      // Shape-preserving normalization centers in unit square; y no longer spans 0..1 independently.
      expect(content.silhouette.first.y, closeTo(0.8567, 0.0001));
      expect(content.footer, 'REVV');
    });

    test('never exposes route internals or user-specific data in visible text', () {
      // Given: a route whose raw fields contain deliberately unsafe public copy.
      final route = _route(
        name:
            'Café du Parc · EXTREME · 181 km/h · 0 curves · 45.5017123, -73.5678901',
      );

      // When: a card is built without a selected meeting area.
      final content = buildRouteShareCardContent(
        route: route,
        draft: DriveInviteDraft.forLanguage(AppLanguage.english),
        language: AppLanguage.english,
      );
      final visibleText = content.visibleText.join('\n').toLowerCase();

      // Then: the public surface contains none of the forbidden source values.
      for (final forbidden in const [
        'extreme',
        '181 km/h',
        '0 curves',
        '45.5017',
        '-73.5678',
        'chemin confidentiel',
        'café du parc',
        '25 km',
        'to start',
      ]) {
        expect(visibleText, isNot(contains(forbidden)));
      }
      expect(content.meetingArea, isNull);
      expect(content.meetingAreaLabel, isNull);
    });

    test('uses a neutral route title even when raw names look safe', () {
      // Given: raw names that look safe and unsafe but are not public card input.
      const rawNames = [
        'Lakeside Sweepers',
        'Café du Parc',
        '123 Main Street',
        'driver@example.com',
        '45.501, -73.568',
      ];

      // When: public invite cards are built.
      final cards = [
        for (final name in rawNames)
          buildRouteShareCardContent(
            route: _route(name: name),
            language: AppLanguage.english,
          ),
      ];

      // Then: every route uses the neutral title and none of the raw names leak.
      for (var index = 0; index < cards.length; index++) {
        expect(cards[index].routeName, 'REVV route');
        expect(
          cards[index].visibleText.join(' '),
          isNot(contains(rawNames[index])),
        );
      }
    });

    test('replaces unsafe route names with a localized neutral title', () {
      // Given: raw names that are not suitable for a public route card.
      const unsafeNames = [
        '123 Main Street',
        'My home',
        '416-555-1212',
        'driver@example.com',
        '45.501, -73.568',
        'Café du Parc',
      ];
      const fallback = {
        AppLanguage.korean: 'REVV 루트',
        AppLanguage.english: 'REVV route',
        AppLanguage.french: 'Itinéraire REVV',
      };

      // When: content is built in each supported locale.
      final cards = [
        for (final language in AppLanguage.values)
          for (final name in unsafeNames)
            buildRouteShareCardContent(
              route: _route(name: name),
              language: language,
            ),
      ];

      // Then: every unsafe title becomes the localized neutral fallback.
      for (var index = 0; index < cards.length; index++) {
        final language = AppLanguage.values[index ~/ unsafeNames.length];
        expect(cards[index].routeName, fallback[language]);
      }
    });

    test('keeps the public silhouette bounded and translation-invariant', () {
      // Given: the same route shape at two different absolute locations.
      // The translation is longitude-only: the shape-preserving normalization
      // applies a latitude-dependent aspect correction (cos midLat), so only a
      // same-latitude move keeps the silhouette bit-identical. Latitude moves
      // still leak no absolute coordinate — they only change the aspect scale.
      const localNodes = [
        LatLng(1.125, 2.25),
        LatLng(1.875, 3.75),
        LatLng(1.5, 4.25),
      ];
      const translatedNodes = [
        LatLng(1.125, -70.75),
        LatLng(1.875, -69.25),
        LatLng(1.5, -68.75),
      ];

      // When: public card content is built for both routes.
      final original = buildRouteShareCardContent(
        route: _route(nodes: localNodes),
      );
      final translated = buildRouteShareCardContent(
        route: _route(nodes: translatedNodes),
      );
      final capped = buildRouteShareCardContent(
        route: _route(
          nodes: [
            for (var index = 0; index < 121; index++)
              LatLng(index.toDouble(), (index * 2).toDouble()),
          ],
        ),
      );

      // Then: no absolute coordinate survives; only a bounded same-shape line remains.
      expect(original.silhouette.length, lessThanOrEqualTo(120));
      expect(capped.silhouette, hasLength(120));
      expect(translated.silhouette.length, original.silhouette.length);
      for (var index = 0; index < original.silhouette.length; index++) {
        final first = original.silhouette[index];
        final second = translated.silhouette[index];
        expect(first.x, inInclusiveRange(0, 1));
        expect(first.y, inInclusiveRange(0, 1));
        expect(second.x, closeTo(first.x, 0.000001));
        expect(second.y, closeTo(first.y, 0.000001));
      }
    });

    test('keeps all localized card surfaces inside the same allowlist', () {
      // Given: the same route in every supported language.
      final route = _route();

      // When: sender card content is built for each locale.
      final cards = [
        for (final language in AppLanguage.values)
          buildRouteShareCardContent(route: route, language: language),
      ];

      // Then: every locale has safe core content and no home-distance copy.
      for (final card in cards) {
        expect(card.schedule, isNotEmpty);
        expect(card.routeName, switch (AppLanguage.values[cards.indexOf(
          card,
        )]) {
          AppLanguage.korean => 'REVV 루트',
          AppLanguage.english => 'REVV route',
          AppLanguage.french => 'Itinéraire REVV',
        });
        expect(card.distanceLabel, '84 km');
        expect(card.durationLabel, '1h 24m');
        expect(card.tags.length, lessThanOrEqualTo(2));
        expect(card.visibleText.join(' '), isNot(contains('25 km')));
      }
    });

    test('prints a redacted manual-QA visible-text fixture', () {
      // Given: a representative English route invite.
      final content = buildRouteShareCardContent(
        route: _route(),
        draft: DriveInviteDraft.forLanguage(
          AppLanguage.english,
        ).withMeetingArea(DriveInviteMeetingArea.oldPort),
        language: AppLanguage.english,
      );

      // When: its visible card copy is inspected.
      final visibleText = content.visibleText.join(' | ');
      // ignore: avoid_print
      print('MANUAL_QA_VISIBLE_TEXT: $visibleText');

      // Then: the evidence is a public, redacted card surface only.
      expect(visibleText, contains('REVV route'));
      expect(visibleText, isNot(contains('45.5017')));
    });
  });
}
