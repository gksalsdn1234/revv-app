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

  tearDown(() {
    SupabaseService().debugResetForTesting();
  });

  test(
    'supabase service distinguishes unavailable guest and identified cloud',
    () {
      final service = SupabaseService()..debugResetForTesting();

      expect(service.cloudSessionState, CloudSessionState.unavailable);
      expect(service.isCloudAvailable, isFalse);
      expect(service.isIdentifiedCloudSession, isFalse);
      expect(service.availabilityLabel, '클라우드 비활성');

      service.debugSetCloudSessionStateForTesting(
        ready: true,
        uid: 'guest-user',
        anonymous: true,
      );
      expect(service.cloudSessionState, CloudSessionState.anonymous);
      expect(service.isCloudAvailable, isTrue);
      expect(service.isIdentifiedCloudSession, isFalse);
      expect(service.availabilityLabel, '게스트 클라우드 연결됨');

      service.debugSetCloudSessionStateForTesting(
        ready: true,
        uid: 'identified-user',
        anonymous: false,
      );
      expect(service.cloudSessionState, CloudSessionState.identified);
      expect(service.isCloudAvailable, isTrue);
      expect(service.isIdentifiedCloudSession, isTrue);
      expect(service.availabilityLabel, '계정 클라우드 연결됨');
    },
  );

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
      expect(routes.any((route) => route.distanceFromUser > 0), isTrue);
    },
    skip: !config.isConfigured,
  );
}
