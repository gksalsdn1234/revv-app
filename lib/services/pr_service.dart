import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/run_session.dart';
import 'cloud_sync_service.dart';

/// 어떤 개인 기록이 갱신되었는지 나타내는 플래그
class NewPrFlags {
  final bool newBestTime;  // 최단 시간 갱신
  final bool newBestG;     // 최고 횡G 갱신
  const NewPrFlags({this.newBestTime = false, this.newBestG = false});
  bool get any => newBestTime || newBestG;
}

/// 루트별 개인 기록(PR) 체크 및 저장 (singleton)
///
/// Firestore: users/{uid}/records/{routeId}
///   bestTimeSeconds: int    — 최단 완주 시간
///   bestMaxG:        double — 최고 횡G
///   runCount:        int    — 이 루트 주행 횟수
///   lastRunAt:       Timestamp
class PrService {
  static final PrService _instance = PrService._();
  factory PrService() => _instance;
  PrService._();

  /// 런 완료 후 호출 — PR 비교 + Firestore 업데이트
  /// 반환값: 어떤 기록이 경신되었는지
  Future<NewPrFlags> checkAndUpdate(RunSession session) async {
    final routeId = session.route?.id;
    if (routeId == null) return const NewPrFlags();

    final sync = CloudSyncService();
    if (!sync.isReady) return const NewPrFlags();
    final uid = sync.uid;
    if (uid == null) return const NewPrFlags();

    try {
      final docRef =
          FirebaseFirestore.instance.doc('users/$uid/records/$routeId');
      final snap = await docRef.get();
      final existing = snap.data();

      final timeSeconds = session.duration.inSeconds;
      final maxG = session.maxLateralG;

      final oldBestTime = existing?['bestTimeSeconds'] as int?;
      final oldBestG = (existing?['bestMaxG'] as num?)?.toDouble();

      // 최단 시간 갱신 (최소 1분 이상 주행만 인정)
      final newBestTime =
          timeSeconds >= 60 && (oldBestTime == null || timeSeconds < oldBestTime);
      // 최고 G 갱신 (0.1G 이상인 경우만)
      final newBestG =
          maxG > 0.1 && (oldBestG == null || maxG > oldBestG);

      await docRef.set({
        'routeId': routeId,
        'bestTimeSeconds':
            newBestTime ? timeSeconds : (oldBestTime ?? timeSeconds),
        if (maxG > 0.1)
          'bestMaxG': newBestG ? maxG : (oldBestG ?? maxG),
        'runCount': FieldValue.increment(1),
        'lastRunAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[PR] ${routeId.substring(0, 8)}… 기록 — time:$newBestTime G:$newBestG');
      return NewPrFlags(newBestTime: newBestTime, newBestG: newBestG);
    } catch (e) {
      debugPrint('[PR] 기록 업데이트 실패: $e');
      return const NewPrFlags();
    }
  }
}
