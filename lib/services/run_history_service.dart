import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/run_summary.dart';
import '../models/run_session.dart';

class RunHistoryService extends ChangeNotifier {
  static const _key = 'run_history';

  List<RunSummary> _history = [];
  List<RunSummary> get history => List.unmodifiable(_history);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _history = RunSummary.listFromJson(raw);
      notifyListeners();
    }
  }

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
    );
    _history.insert(0, summary);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RunSummary.listToJson(_history));
    notifyListeners();
    return summary;
  }

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
}
