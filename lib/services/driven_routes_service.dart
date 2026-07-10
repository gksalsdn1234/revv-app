import 'package:flutter/foundation.dart';

import '../models/revv_route.dart';
import 'run_history_service.dart';

/// 달린 루트의 집합 — 정복 지도의 데이터 소스.
///
/// RunHistoryService(로컬 + 클라우드 동기화 결과)를 그대로 파생한다.
/// 별도 저장소를 만들지 않는 이유: runs가 이미 "달렸다"의 단일 진실이고,
/// 여기서는 그 위의 뷰만 제공한다 (북극성: 완벽한 DB 금지).
class DrivenRoutesService extends ChangeNotifier {
  DrivenRoutesService({required RunHistoryService history})
    : _history = history {
    _history.addListener(_recompute);
    _recompute();
  }

  final RunHistoryService _history;
  Set<String> _drivenIds = const {};
  Set<String> _thisMonthNewIds = const {};

  Set<String> get drivenRouteIds => _drivenIds;

  bool isDriven(String? routeId) =>
      routeId != null && _drivenIds.contains(routeId);

  int drivenCountOf(Iterable<RevvRoute> routes) =>
      routes.where((route) => _drivenIds.contains(route.id)).length;

  /// 이번 달 처음 달린 루트 수 (이전 달에 달린 적 없는 route_id만).
  int get newRoutesThisMonth => _thisMonthNewIds.length;

  /// 누적 달린 루트 수 (distinct route_id).
  int get totalDrivenRoutes => _drivenIds.length;

  void _recompute() {
    final now = DateTime.now();
    final driven = <String>{};
    final before = <String>{};
    final thisMonth = <String>{};
    for (final run in _history.history) {
      final id = run.routeId;
      if (id == null || id.isEmpty) continue;
      driven.add(id);
      final sameMonth = run.date.year == now.year && run.date.month == now.month;
      if (sameMonth) {
        thisMonth.add(id);
      } else if (run.date.isBefore(DateTime(now.year, now.month))) {
        before.add(id);
      }
    }
    final thisMonthNew = thisMonth.difference(before);
    if (setEquals(driven, _drivenIds) &&
        setEquals(thisMonthNew, _thisMonthNewIds)) {
      return;
    }
    _drivenIds = driven;
    _thisMonthNewIds = thisMonthNew;
    notifyListeners();
  }

  @override
  void dispose() {
    _history.removeListener(_recompute);
    super.dispose();
  }
}
