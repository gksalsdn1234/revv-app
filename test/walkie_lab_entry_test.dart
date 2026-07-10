import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/services/driven_routes_service.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_app_shell_screen.dart';
import 'package:revv_app/services/location_service.dart';
import 'package:revv_app/services/route_service.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:revv_app/services/settings_service.dart';
import 'package:revv_app/services/supabase_service.dart';
import 'package:revv_app/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flag off shows no walkie lab entry', (tester) async {
    await tester.pumpShell(const LeanAppShellScreen());
    await tester.openSettings();

    expect(find.text('Crew voice lab'), findsNothing);
  });

  testWidgets('flag on exposes entry and navigates from settings', (
    tester,
  ) async {
    await tester.pumpShell(
      LeanAppShellScreen(
        walkieLabEntryEnabled: true,
        walkieLabBuilder: (_) => const _EntryProbeScreen(),
      ),
    );
    await tester.openSettings();

    await tester.ensureVisible(find.text('Crew voice lab'));
    await tester.pump();
    await tester.tap(find.text('Crew voice lab'));
    await tester.pumpAndSettle();

    expect(find.text('Walkie entry opened'), findsOneWidget);
  });
}

extension on WidgetTester {
  Future<void> pumpShell(Widget shell) async {
    await binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => binding.setSurfaceSize(null));
    await pumpWidget(
      MultiProvider(
        providers: [
        ChangeNotifierProvider(
          create: (_) => DrivenRoutesService(history: RunHistoryService()),
        ),
          ChangeNotifierProvider(
            create: (_) => DrivenRoutesService(history: RunHistoryService()),
          ),
          ChangeNotifierProvider(create: (_) => RunHistoryService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<LocationService>.value(
            value: _QuietLocationService(),
          ),
          ChangeNotifierProvider(create: (_) => WeatherService()),
          ChangeNotifierProvider(create: (_) => RouteService()),
          ChangeNotifierProvider.value(value: SupabaseService()),
        ],
        child: MaterialApp(home: shell),
      ),
    );
    await pump(const Duration(milliseconds: 100));
  }

  Future<void> openSettings() async {
    await tap(find.text('Settings'));
    await pumpAndSettle();
  }
}

class _QuietLocationService extends LocationService {
  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<LatLng?> ensureLiveLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async => null;
}

class _EntryProbeScreen extends StatelessWidget {
  const _EntryProbeScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Walkie entry opened')));
  }
}
