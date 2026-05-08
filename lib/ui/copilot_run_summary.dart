import '../models/run_session.dart';
import '../models/run_summary.dart';

class CopilotRunStat {
  final String label;
  final String value;

  const CopilotRunStat(this.label, this.value);
}

class CopilotRunSummaryCopy {
  final String headline;
  final String summaryLine;
  final String nextSuggestion;
  final List<CopilotRunStat> notableStats;

  const CopilotRunSummaryCopy({
    required this.headline,
    required this.summaryLine,
    required this.nextSuggestion,
    required this.notableStats,
  });

  factory CopilotRunSummaryCopy.fromSession(
    RunSession session, {
    RunSummary? summary,
  }) {
    final routeName = session.routeName;
    final sharpCount = session.sharpCorners.length;
    final peakG = session.maxLateralG.abs() >= session.maxLonG.abs()
        ? session.maxLateralG.abs()
        : session.maxLonG.abs();

    return CopilotRunSummaryCopy(
      headline: _headline(session, sharpCount, peakG),
      summaryLine: _summaryLine(session, routeName, sharpCount),
      nextSuggestion: _nextSuggestion(session, sharpCount, peakG),
      notableStats: [
        CopilotRunStat('거리', '${session.distanceKm.toStringAsFixed(2)} km'),
        CopilotRunStat('시간', session.durationDisplay),
        CopilotRunStat('커브 이벤트', '$sharpCount회'),
        CopilotRunStat('최고 G', peakG.toStringAsFixed(2)),
      ],
    );
  }
}

String _headline(RunSession session, int sharpCount, double peakG) {
  if (session.distanceKm < 0.3) return '짧은 체크 주행으로 기록했어요.';
  if (session.route != null && sharpCount >= 3) return '루트 리듬과 G 피크가 함께 남았어요.';
  if (session.route != null) return '오늘 루트 리듬을 기록했어요.';
  if (peakG >= 0.45) return '짧지만 반응이 선명한 주행이었어요.';
  return '가볍게 흐름을 확인한 주행이었어요.';
}

String _summaryLine(RunSession session, String routeName, int sharpCount) {
  final avg = session.avgSpeedKmh > 0
      ? '평균 ${session.avgSpeedKmh.toStringAsFixed(0)}km/h'
      : '평균 속도 없음';
  final eventText = sharpCount == 0 ? '큰 G 이벤트 없이' : 'G 이벤트 $sharpCount회와 함께';
  return '$routeName에서 ${session.distanceKm.toStringAsFixed(1)}km를 $eventText 기록했어요. $avg 기준으로 복원됩니다.';
}

String _nextSuggestion(RunSession session, int sharpCount, double peakG) {
  if (session.route == null) return '다음엔 추천 루트를 선택하면 커브 리듬까지 함께 비교할 수 있어요.';
  if (session.distanceKm < session.route!.distanceKm * 0.35) {
    return '이번엔 일부만 달렸어요. 다음엔 시작점부터 들어가 완료율을 높여보세요.';
  }
  if (sharpCount >= 3 || peakG >= 0.45) {
    return '다음 추천에서는 비슷한 리듬의 후보를 우선 비교해볼 수 있어요.';
  }
  return '다음엔 이 루트와 비슷하지만 조금 더 긴 흐름 후보를 비교해보세요.';
}
