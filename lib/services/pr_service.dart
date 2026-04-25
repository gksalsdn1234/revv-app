import 'package:flutter/foundation.dart';
import '../models/run_session.dart';
import 'supabase_service.dart';

class NewPrFlags {
  final bool newBestTime;
  final bool newBestG;
  const NewPrFlags({this.newBestTime = false, this.newBestG = false});
  bool get any => newBestTime || newBestG;
}

class PrService {
  static final PrService _instance = PrService._();
  factory PrService() => _instance;
  PrService._();

  Future<NewPrFlags> checkAndUpdate(RunSession session) async {
    final routeId = session.route?.id;
    if (routeId == null) return const NewPrFlags();

    final sync = SupabaseService();
    if (!sync.isReady) return const NewPrFlags();
    final uid = sync.uid;
    if (uid == null) return const NewPrFlags();

    try {
      final records = await sync.fetchRouteRecords();
      final existing = records[routeId];

      final timeSeconds = session.duration.inSeconds;
      final maxG = session.maxLateralG;

      final oldBestTime = existing?['best_time_seconds'] as int?;
      final oldBestG = (existing?['best_max_g'] as num?)?.toDouble();

      final newBestTime =
          timeSeconds >= 60 &&
          (oldBestTime == null || timeSeconds < oldBestTime);
      final newBestG = maxG > 0.1 && (oldBestG == null || maxG > oldBestG);

      await sync.upsertRouteRecord(
        routeId: routeId,
        bestTimeSeconds: newBestTime
            ? timeSeconds
            : (oldBestTime ?? timeSeconds),
        bestMaxG: newBestG ? maxG : (oldBestG ?? maxG),
        runCount: ((existing?['run_count'] as num?)?.toInt() ?? 0) + 1,
        lastRunAt: DateTime.now(),
      );

      debugPrint(
        '[PR] ${routeId.substring(0, 8)}… 기록 — time:$newBestTime G:$newBestG',
      );
      return NewPrFlags(newBestTime: newBestTime, newBestG: newBestG);
    } catch (e) {
      debugPrint('[PR] 기록 업데이트 실패: $e');
      return const NewPrFlags();
    }
  }
}
