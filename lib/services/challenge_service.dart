import '../models/run_summary.dart';

/// 드라이브 챌린지 — 주간/월간 목표 거리 (로컬 계산, Firestore 불필요)
class ChallengeService {
  static final ChallengeService _instance = ChallengeService._();
  factory ChallengeService() => _instance;
  ChallengeService._();

  static const double monthlyGoalKm = 500.0;
  static const double weeklyGoalKm = 100.0;

  /// 이번 달 누적 거리
  double monthlyKm(List<RunSummary> history) {
    final now = DateTime.now();
    return history
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .fold(0.0, (sum, r) => sum + r.distanceKm);
  }

  /// 이번 주 누적 거리 (월요일 기준)
  double weeklyKm(List<RunSummary> history) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start =
        DateTime(weekStart.year, weekStart.month, weekStart.day);
    return history
        .where((r) => r.date.isAfter(start))
        .fold(0.0, (sum, r) => sum + r.distanceKm);
  }

  /// 월간 목표 달성률 0.0–1.0
  double monthlyProgress(List<RunSummary> history) =>
      (monthlyKm(history) / monthlyGoalKm).clamp(0.0, 1.0);

  /// 주간 목표 달성률 0.0–1.0
  double weeklyProgress(List<RunSummary> history) =>
      (weeklyKm(history) / weeklyGoalKm).clamp(0.0, 1.0);

  /// 연속 드라이브 일수 (오늘 또는 어제 기준, 끊기면 0)
  int currentStreak(List<RunSummary> history) {
    if (history.isEmpty) return 0;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    // 고유 드라이브 날짜 내림차순 정렬
    final runDays = history
        .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (runDays.isEmpty) return 0;
    // 오늘 또는 어제에 주행 없으면 스트릭 없음
    if (runDays.first.difference(todayDay).inDays.abs() > 1) return 0;

    int streak = 0;
    DateTime check = runDays.first;
    for (final day in runDays) {
      if (day == check) {
        streak++;
        check = check.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }
}
