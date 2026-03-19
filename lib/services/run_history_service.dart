import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/run_summary.dart';
import '../models/run_session.dart';
import 'cloud_sync_service.dart';

class RunHistoryService extends ChangeNotifier {
  static const _key = 'run_history';

  List<RunSummary> _history = [];
  List<RunSummary> get history => List.unmodifiable(_history);

  // ── 로컬 로드 ──────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _history = RunSummary.listFromJson(raw);
      notifyListeners();
    }
  }

  // ── 클라우드 병합 (앱 시작 시 호출) ──────────────────────────
  /// 로컬에 없는 클라우드 런을 가져와 병합 + 로컬에 없는 런을 클라우드에도 업로드
  Future<void> syncWithCloud() async {
    final sync = CloudSyncService();
    if (!sync.isReady) return;

    // 1) 클라우드에만 있는 런 → 로컬 병합
    final localIds = _history.map((r) => r.id).toSet();
    final missing = await sync.fetchMissingRuns(localIds);
    if (missing.isNotEmpty) {
      _history = [..._history, ...missing]
        ..sort((a, b) => b.date.compareTo(a.date));
      await _persist();
      notifyListeners();
    }

    // 2) 로컬에만 있는 런 → 클라우드 업로드 (첫 연결 시 기존 데이터 백업)
    final cloudIds = await _fetchCloudIds(sync);
    final localOnly = _history.where((r) => !cloudIds.contains(r.id)).toList();
    if (localOnly.isNotEmpty) {
      await sync.uploadAll(localOnly);
    }
  }

  Future<Set<String>> _fetchCloudIds(CloudSyncService sync) async {
    // fetchMissingRuns에서 이미 클라우드 ID를 알 수 있지만
    // 여기선 uploadAll 중복 방지용으로 localIds 기준으로 처리
    return {};
  }

  // ── 런 저장 ────────────────────────────────────────────────
  Future<RunSummary> save(RunSession session) async {
    final summary = RunSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: session.startTime,
      distanceKm: session.distanceKm,
      durationSeconds: session.duration.inSeconds,
      routeName: session.routeName,
      routeId: session.route?.id,
      weatherEmoji: session.weatherEmoji,
      tempDisplay: session.tempDisplay,
      maxLateralG: session.maxLateralG > 0 ? session.maxLateralG : null,
    );

    // 로컬 즉시 저장
    _history.insert(0, summary);
    await _persist();
    notifyListeners();

    // 클라우드 백그라운드 업로드 (실패해도 로컬엔 영향 없음)
    CloudSyncService().uploadRun(summary);

    return summary;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RunSummary.listToJson(_history));
  }

  // ── 조회 헬퍼 ──────────────────────────────────────────────

  /// 같은 routeId로 완료한 횟수 (방금 저장한 것 포함)
  int visitCount(String? routeId) {
    if (routeId == null) return 1;
    return _history.where((s) => s.routeId == routeId).length;
  }

  /// 전체 누적 거리 (km)
  double get totalDistanceKm =>
      _history.fold(0, (sum, s) => sum + s.distanceKm);

  /// 전체 드라이브 횟수
  int get totalRuns => _history.length;

  /// 모든 런 중 최대 횡G (실기기 기록이 있는 경우만)
  double? get bestMaxG {
    final gs = _history
        .where((s) => s.maxLateralG != null && s.maxLateralG! > 0)
        .map((s) => s.maxLateralG!)
        .toList();
    if (gs.isEmpty) return null;
    return gs.reduce((a, b) => a > b ? a : b);
  }
}
