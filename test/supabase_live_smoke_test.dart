import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/supabase_config.dart';
import 'package:revv_app/services/supabase_service.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final config = SupabaseConfig(url: _supabaseUrl, anonKey: _supabaseAnonKey);

  test(
    'live supabase smoke: init and find_curvy_roads returns Montreal routes',
    () async {
      expect(
        config.isConfigured,
        isTrue,
        reason: 'SUPABASE_URL and SUPABASE_ANON_KEY dart-defines are required',
      );

      final service = SupabaseService();
      await service.init(config: config);

      expect(service.isReady, isTrue);
      expect(service.uid, isNotNull);

      final routes = await service.findCurvyRoads(
        lat: 45.4627167,
        lng: -73.62658,
        radiusM: 50000,
        maxResults: 10,
      );

      expect(routes, isNotEmpty);
      expect(routes.length, greaterThanOrEqualTo(5));
      expect(
        routes.any((route) => route.distanceFromUser > 0),
        isTrue,
      );
    },
    skip: !config.isConfigured,
  );
}
