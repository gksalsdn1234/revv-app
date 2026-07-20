import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/place_search_service.dart';
import 'package:revv_app/widgets/place_search_sheet.dart';

void main() {
  testWidgets('place search has no fixed regional preset chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceSearchSheet(
            language: AppLanguage.english,
            service: _DisabledPlaceSearchService(),
            proximity: const LatLng(45.5017, -73.5673),
            allowMapPin: false,
          ),
        ),
      ),
    );

    expect(find.byKey(plannerPlaceSearchFieldKey), findsOneWidget);
    expect(find.text('Montreal'), findsNothing);
    expect(find.text('Laurentians'), findsNothing);
    expect(find.text('Toronto'), findsNothing);
    expect(find.text('Vancouver'), findsNothing);
  });

  testWidgets('an older search response cannot replace newer results', (
    tester,
  ) async {
    final service = _DelayedPlaceSearchService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceSearchSheet(
            language: AppLanguage.english,
            service: service,
            proximity: const LatLng(45.5017, -73.5673),
            allowMapPin: false,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(plannerPlaceSearchFieldKey), 'Tor');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byKey(plannerPlaceSearchFieldKey), 'Toronto');
    await tester.pump(const Duration(milliseconds: 350));

    service.complete('Toronto', 'Toronto');
    await tester.pump();
    expect(find.text('Toronto'), findsAtLeastNWidgets(1));

    service.complete('Tor', 'Old Toronto result');
    await tester.pump();
    expect(find.text('Toronto'), findsAtLeastNWidgets(1));
    expect(find.text('Old Toronto result'), findsNothing);
  });
}

class _DisabledPlaceSearchService extends PlaceSearchService {
  @override
  bool get isEnabled => false;
}

class _DelayedPlaceSearchService extends PlaceSearchService {
  final Map<String, Completer<List<PlaceResult>>> _requests = {};

  @override
  bool get isEnabled => true;

  @override
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? proximity,
    String language = 'en',
  }) {
    return (_requests[query] ??= Completer<List<PlaceResult>>()).future;
  }

  void complete(String query, String name) {
    _requests[query]!.complete([
      PlaceResult(
        name: name,
        address: '',
        point: const LatLng(43.6532, -79.3832),
      ),
    ]);
  }
}
