import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/ui/app_copy.dart';
import 'package:revv_app/widgets/map_widget.dart';
import 'package:revv_app/widgets/route_new_badge.dart';

RevvRoute _generatedRoute({required DateTime? activatedAt}) {
  return RevvRoute(
    id: 'generated-route',
    name: 'Western Ridge',
    nodes: const [LatLng(51, -115), LatLng(51.1, -115.1)],
    distanceKm: 14,
    windingScore: 6,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: const LatLng(51.05, -115.05),
    distanceFromUser: 4,
    isGenerated: true,
    activatedAt: activatedAt,
  );
}

void main() {
  final now = DateTime.utc(2026, 7, 16, 12);

  test('new route copy is concise and localized', () {
    expect(AppCopy.newRouteLabel(AppLanguage.korean), '신규');
    expect(AppCopy.newRouteLabel(AppLanguage.english), 'NEW');
    expect(AppCopy.newRouteLabel(AppLanguage.french), 'NOUVEAU');
    expect(AppCopy.newRouteSemantics(AppLanguage.korean), '신규 루트');
    expect(AppCopy.newRouteSemantics(AppLanguage.english), 'New route');
    expect(AppCopy.newRouteSemantics(AppLanguage.french), 'Nouvel itinéraire');
  });

  testWidgets('new route badge shows through day 29 with localized semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    for (final language in AppLanguage.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 110,
              child: RouteNewBadge(
                route: _generatedRoute(
                  activatedAt: now.subtract(const Duration(days: 29)),
                ),
                language: language,
                now: now,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('route-new-badge')), findsOneWidget);
      expect(find.text(AppCopy.newRouteLabel(language)), findsOneWidget);
      expect(
        find.bySemanticsLabel(AppCopy.newRouteSemantics(language)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('new route badge hides at day 30 and for legacy or null dates', (
    tester,
  ) async {
    final routes = <RevvRoute>[
      _generatedRoute(activatedAt: now.subtract(const Duration(days: 30))),
      _generatedRoute(activatedAt: null),
      _generatedRoute(
        activatedAt: now.subtract(const Duration(days: 29)),
      ).copyWith(isGenerated: false),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (final route in routes)
              RouteNewBadge(
                route: route,
                language: AppLanguage.english,
                now: now,
              ),
          ],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('route-new-badge')), findsNothing);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('map legend explains the cyan casing for new routes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: NewRouteMapLegend(count: 24, language: AppLanguage.korean),
        ),
      ),
    );

    expect(find.text('신규 24개'), findsOneWidget);
    expect(find.text('청록 테두리'), findsOneWidget);
    expect(find.bySemanticsLabel('신규 루트 24개, 청록 테두리'), findsOneWidget);
    semantics.dispose();
  });

  test('map casing GeoJSON includes only eligible new route lines', () {
    final lines = [
      const RouteDifficultyLine(
        routeId: 'new',
        points: [LatLng(51, -115), LatLng(51.1, -115.1)],
        colorArgb: 0xFFFF2E38,
        width: 3,
        opacity: 0.9,
        showNewCasing: true,
      ),
      const RouteDifficultyLine(
        routeId: 'legacy',
        points: [LatLng(50, -114), LatLng(50.1, -114.1)],
        colorArgb: 0xFFFFE94A,
        width: 2,
        opacity: 0.7,
      ),
    ];

    final json = jsonDecode(buildNewRouteCasingGeoJson(lines));
    final features = json['features'] as List<dynamic>;

    expect(features, hasLength(1));
    expect(features.single['properties']['routeId'], 'new');
    expect(lines.first.colorArgb, 0xFFFF2E38);
    expect(lines.last.colorArgb, 0xFFFFE94A);
  });
}
