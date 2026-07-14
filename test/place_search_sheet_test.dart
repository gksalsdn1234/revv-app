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
}

class _DisabledPlaceSearchService extends PlaceSearchService {
  @override
  bool get isEnabled => false;
}
