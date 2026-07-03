import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_detail_screen.dart';
import 'package:revv_app/services/settings_service.dart';

const _route = RevvRoute(
  id: 'turn-route',
  name: '테스트 와인딩',
  nodes: [
    LatLng(45.0000, -73.0000),
    LatLng(45.0010, -73.0000),
    LatLng(45.0010, -72.9985),
    LatLng(45.0024, -72.9985),
    LatLng(45.0024, -72.9970),
  ],
  distanceKm: 1.0,
  windingScore: 7.2,
  starRating: 4,
  sharpCurveCount: 3,
  centerPoint: LatLng(45.0012, -72.9985),
  distanceFromUser: 0.5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('route detail renders turn-by-turn preview', (tester) async {
    final settings = SettingsService();
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: const MaterialApp(home: LeanRouteDetailScreen(route: _route)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('TURN BOOK'), findsOneWidget);
    expect(find.text('4 cues'), findsOneWidget);
    expect(find.text('110m Right Hairpin'), findsOneWidget);
    expect(find.textContaining('Finish'), findsWidgets);
  });
}
