import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/screens/lean_run_summary_screen.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('review home button calls the app home handler', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var homeRequested = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
        ],
        child: MaterialApp(
          home: LeanRunSummaryScreen.history(
            summary: RunSummary(
              id: 'review-home',
              date: DateTime(2026, 7, 21),
              distanceKm: 8,
              durationSeconds: 900,
              routeName: 'Review route',
              weatherEmoji: '',
              tempDisplay: '',
            ),
            onReturnHome: () => homeRequested = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final homeButton = find.text('Home');
    await tester.ensureVisible(homeButton);
    await tester.tap(homeButton);
    await tester.pump();

    expect(homeRequested, isTrue);
  });
}
