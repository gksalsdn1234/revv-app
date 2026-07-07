import 'package:flutter/foundation.dart';

import '../models/revv_route.dart';
import 'supabase_service.dart';

typedef RecommendationLogInsert =
    Future<void> Function(Map<String, Object?> payload);

class RecommendationLogService {
  final SupabaseService _supabase;
  final RecommendationLogInsert? _insertForTesting;
  final bool Function()? _isCloudAvailableForTesting;

  RecommendationLogService({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService(),
      _insertForTesting = null,
      _isCloudAvailableForTesting = null;

  @visibleForTesting
  RecommendationLogService.forTesting({
    required RecommendationLogInsert insert,
    bool Function()? isCloudAvailable,
  }) : _supabase = SupabaseService(),
       _insertForTesting = insert,
       // 테스트 시임은 명시적으로 끄지 않는 한 클라우드 가용으로 간주한다 —
       // 실제 싱글턴(테스트 환경에서 항상 미초기화)으로 폴백하면 전부 no-op이 된다.
       _isCloudAvailableForTesting = isCloudAvailable ?? (() => true);

  Future<void> logShown({
    required String mode,
    required List<String> routeIds,
    LatLng? origin,
    int? budgetMinutes,
  }) {
    final payload = <String, Object?>{
      'event': 'shown',
      'mode': mode,
      'route_ids': routeIds,
    };
    if (origin != null) payload['origin_geohash4'] = _originBucket(origin);
    if (budgetMinutes != null) payload['budget_minutes'] = budgetMinutes;
    return _insert(payload);
  }

  Future<void> logChosen({
    required String mode,
    required String routeId,
    String? optionKind,
    LatLng? origin,
    int? budgetMinutes,
  }) {
    final payload = <String, Object?>{
      'event': 'chosen',
      'mode': mode,
      'route_ids': [routeId],
    };
    if (optionKind != null) payload['option_kind'] = optionKind;
    if (origin != null) payload['origin_geohash4'] = _originBucket(origin);
    if (budgetMinutes != null) payload['budget_minutes'] = budgetMinutes;
    return _insert(payload);
  }

  Future<void> _insert(Map<String, Object?> payload) async {
    final cloudAvailable =
        _isCloudAvailableForTesting?.call() ?? _supabase.isCloudAvailable;
    if (!cloudAvailable) return;
    try {
      final insert = _insertForTesting;
      if (insert != null) {
        await insert(payload);
        return;
      }
      final client = _supabase.client;
      if (client == null) return;
      await client.from('recommendation_logs').insert(payload);
    } catch (error) {
      debugPrint('[RecommendationLog] insert failed: $error');
    }
  }
}

String _originBucket(LatLng origin) {
  return '${origin.lat.toStringAsFixed(1)},${origin.lng.toStringAsFixed(1)}';
}
