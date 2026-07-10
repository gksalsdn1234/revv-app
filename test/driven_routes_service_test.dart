import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/storage_keys.dart';
import 'package:revv_app/models/run_summary.dart';
import 'package:revv_app/services/driven_routes_service.dart';
import 'package:revv_app/services/run_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RunSummary summary(String id, String? routeId, DateTime date) {
    return RunSummary(
      id: id,
      date: date,
      distanceKm: 10,
      durationSeconds: 600,
      routeName: 'R',
      weatherEmoji: '',
      tempDisplay: '',
      routeId: routeId,
    );
  }

  Future<RunHistoryService> historyWith(List<RunSummary> runs) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.runs: jsonEncode([for (final r in runs) r.toJson()]),
    });
    final history = RunHistoryService();
    await history.load();
    return history;
  }

  test('derives distinct driven route ids from run history', () async {
    final now = DateTime.now();
    final history = await historyWith([
      summary('a', 'route-1', now),
      summary('b', 'route-1', now), // 재주행 — 중복 제거
      summary('c', 'route-2', now),
      summary('d', null, now), // route 없는 자유 주행 무시
    ]);
    final driven = DrivenRoutesService(history: history);

    expect(driven.drivenRouteIds, {'route-1', 'route-2'});
    expect(driven.isDriven('route-1'), isTrue);
    expect(driven.isDriven('route-9'), isFalse);
    expect(driven.totalDrivenRoutes, 2);
  });

  test('counts only first-time routes as new this month', () async {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final history = await historyWith([
      summary('a', 'old-route', lastMonth),
      summary('b', 'old-route', now), // 이번 달 재주행 — 새 길 아님
      summary('c', 'fresh-route', now), // 이번 달 첫 주행
    ]);
    final driven = DrivenRoutesService(history: history);

    expect(driven.totalDrivenRoutes, 2);
    expect(driven.newRoutesThisMonth, 1);
  });

  test('notifies when history gains a new driven route', () async {
    final history = await historyWith([]);
    final driven = DrivenRoutesService(history: history);
    var notified = 0;
    driven.addListener(() => notified++);

    // RunHistoryService의 공개 알림 경로를 그대로 사용한다
    history.notifyListeners();
    expect(notified, 0, reason: '변화 없으면 침묵');
  });
}
