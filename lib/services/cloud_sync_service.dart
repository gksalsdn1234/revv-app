import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/run_summary.dart';
import '../models/revv_route.dart';

enum SyncStatus { idle, syncing, done, error }

/// Firebase Firestore 동기화 서비스 (싱글턴)
///
/// 구조:
///   users/{uid}/runs/{runId}  →  RunSummary 문서
///
/// 전략: 오프라인 우선 (로컬 shared_prefs가 주, Firestore가 백업)
///   - save() 직후 백그라운드 업로드
///   - 앱 시작 시 클라우드 → 로컬 병합 (기기 교체/재설치 복원)
class CloudSyncService extends ChangeNotifier {
  static final CloudSyncService _instance = CloudSyncService._();
  factory CloudSyncService() => _instance;
  CloudSyncService._();

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  bool _ready = false;
  bool get isReady => _ready;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  // ── 초기화 (main.dart에서 Firebase.initializeApp 이후 호출) ──
  Future<void> init() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      _ready = true;
      notifyListeners();
      debugPrint('[CloudSync] 초기화 완료 — uid: $uid');
    } catch (e) {
      _ready = false;
      debugPrint('[CloudSync] 초기화 실패: $e');
    }
  }

  // ── Firestore 컬렉션 참조 ─────────────────────────────────
  CollectionReference<Map<String, dynamic>>? get _runsRef {
    final id = uid;
    if (id == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .collection('runs');
  }

  // ── 단건 업로드 ────────────────────────────────────────────
  /// 런 저장 직후 백그라운드에서 호출 — 실패해도 로컬에는 영향 없음
  Future<void> uploadRun(RunSummary summary) async {
    if (!_ready) return;
    try {
      await _runsRef?.doc(summary.id).set({
        ...summary.toJson(),
        '_updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[CloudSync] 업로드 완료 — ${summary.id}');
    } catch (e) {
      debugPrint('[CloudSync] 업로드 실패: $e');
    }
  }

  // ── 클라우드 → 로컬 병합 ───────────────────────────────────
  /// 앱 시작 시 호출 — 로컬에 없는 클라우드 런을 반환
  Future<List<RunSummary>> fetchMissingRuns(Set<String> localIds) async {
    if (!_ready) return [];
    _setStatus(SyncStatus.syncing);
    try {
      final snap = await _runsRef
          ?.orderBy('date', descending: true)
          .limit(200)
          .get();

      if (snap == null || snap.docs.isEmpty) {
        _setStatus(SyncStatus.done);
        return [];
      }

      final missing = snap.docs
          .where((d) => !localIds.contains(d.id))
          .map((d) {
            try {
              return RunSummary.fromJson(
                Map<String, dynamic>.from(d.data())
                  ..remove('_updatedAt'),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<RunSummary>()
          .toList();

      _setStatus(SyncStatus.done);
      debugPrint('[CloudSync] 클라우드에서 ${missing.length}개 신규 런 수신');
      return missing;
    } catch (e) {
      debugPrint('[CloudSync] fetch 실패: $e');
      _setStatus(SyncStatus.error);
      return [];
    }
  }

  // ── 전체 업로드 (로컬 → 클라우드 일괄) ──────────────────────
  /// 처음 클라우드 연결 시 기존 로컬 데이터를 한 번에 업로드
  Future<void> uploadAll(List<RunSummary> runs) async {
    if (!_ready || runs.isEmpty) return;
    _setStatus(SyncStatus.syncing);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref = _runsRef;
      if (ref == null) return;
      for (final run in runs) {
        batch.set(ref.doc(run.id), {
          ...run.toJson(),
          '_updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      _setStatus(SyncStatus.done);
      debugPrint('[CloudSync] 일괄 업로드 ${runs.length}개 완료');
    } catch (e) {
      debugPrint('[CloudSync] 일괄 업로드 실패: $e');
      _setStatus(SyncStatus.error);
    }
  }

  // ── 발견 루트 Firestore 저장/로드 ─────────────────────────────
  CollectionReference<Map<String, dynamic>>? get _discoveredRef {
    final id = uid;
    if (id == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .collection('discovered_routes');
  }

  /// 루트 풀 배치 저장 (최대 25개)
  Future<void> saveDiscoveredRoutes(List<RevvRoute> routes) async {
    if (!_ready) return;
    final ref = _discoveredRef;
    if (ref == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final r in routes) {
        batch.set(ref.doc(r.id), {
          ...r.toJson(),
          '_savedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      debugPrint('[CloudSync] 루트 풀 저장 완료 — ${routes.length}개');
    } catch (e) {
      debugPrint('[CloudSync] 루트 풀 저장 실패: $e');
    }
  }

  /// 저장된 루트 풀 로드 (앱 시작 시 사전 표시용)
  Future<List<RevvRoute>> loadDiscoveredRoutes() async {
    if (!_ready) return [];
    final ref = _discoveredRef;
    if (ref == null) return [];
    try {
      final snap = await ref
          .orderBy('windingScore', descending: true)
          .limit(25)
          .get();
      return snap.docs
          .map((d) {
            try {
              return RevvRoute.fromJson(
                Map<String, dynamic>.from(d.data())..remove('_savedAt'),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<RevvRoute>()
          .toList();
    } catch (e) {
      debugPrint('[CloudSync] 루트 풀 로드 실패: $e');
      return [];
    }
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    notifyListeners();
  }
}
