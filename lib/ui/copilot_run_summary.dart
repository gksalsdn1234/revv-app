import '../core/app_language.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import 'app_copy.dart';

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
    AppLanguage? language,
  }) {
    final routeName = session.routeName;
    final sharpCount = session.sharpCorners.length;
    final peakG = session.maxLateralG.abs() >= session.maxLonG.abs()
        ? session.maxLateralG.abs()
        : session.maxLonG.abs();

    return CopilotRunSummaryCopy(
      headline: _headline(session, sharpCount, peakG, language),
      summaryLine: _summaryLine(session, routeName, sharpCount, language),
      nextSuggestion: _nextSuggestion(session, sharpCount, peakG, language),
      notableStats: [
        CopilotRunStat(
          AppCopy.t(
            language ?? AppLanguage.korean,
            ko: '거리',
            en: 'Distance',
            fr: 'Distance',
          ),
          '${session.distanceKm.toStringAsFixed(2)} km',
        ),
        CopilotRunStat(
          AppCopy.t(
            language ?? AppLanguage.korean,
            ko: '시간',
            en: 'Time',
            fr: 'Temps',
          ),
          session.durationDisplay,
        ),
        CopilotRunStat(
          AppCopy.t(
            language ?? AppLanguage.korean,
            ko: '커브 이벤트',
            en: 'Curve events',
            fr: 'Événements',
          ),
          AppCopy.t(
            language ?? AppLanguage.korean,
            ko: '$sharpCount회',
            en: '$sharpCount',
            fr: '$sharpCount',
          ),
        ),
        CopilotRunStat(
          AppCopy.t(
            language ?? AppLanguage.korean,
            ko: '최고 G',
            en: 'Peak G',
            fr: 'G max',
          ),
          peakG.toStringAsFixed(2),
        ),
      ],
    );
  }
}

String _headline(
  RunSession session,
  int sharpCount,
  double peakG,
  AppLanguage? language,
) {
  final lang = language ?? AppLanguage.korean;
  if (session.distanceKm < 0.3) {
    return AppCopy.t(
      lang,
      ko: '짧은 체크 주행으로 기록했어요.',
      en: 'Saved as a short check drive.',
      fr: 'Enregistré comme court trajet de test.',
    );
  }
  if (session.route != null && sharpCount >= 3) {
    return AppCopy.t(
      lang,
      ko: '루트 리듬과 G 피크가 함께 남았어요.',
      en: 'Route rhythm and G peaks were saved.',
      fr: 'Rythme de route et pics G enregistrés.',
    );
  }
  if (session.route != null) {
    return AppCopy.t(
      lang,
      ko: '오늘 루트 리듬을 기록했어요.',
      en: 'Today’s route rhythm was saved.',
      fr: 'Rythme de route enregistré.',
    );
  }
  if (peakG >= 0.45) {
    return AppCopy.t(
      lang,
      ko: '짧지만 반응이 선명한 주행이었어요.',
      en: 'Short drive, clear response.',
      fr: 'Court trajet, réponse nette.',
    );
  }
  return AppCopy.t(
    lang,
    ko: '가볍게 흐름을 확인한 주행이었어요.',
    en: 'A light flow-check drive.',
    fr: 'Un trajet léger pour lire le rythme.',
  );
}

String _summaryLine(
  RunSession session,
  String routeName,
  int sharpCount,
  AppLanguage? language,
) {
  final lang = language ?? AppLanguage.korean;
  final avg = session.avgSpeedKmh > 0
      ? AppCopy.t(
          lang,
          ko: '평균 ${session.avgSpeedKmh.toStringAsFixed(0)}km/h',
          en: 'avg ${session.avgSpeedKmh.toStringAsFixed(0)}km/h',
          fr: 'moyenne ${session.avgSpeedKmh.toStringAsFixed(0)}km/h',
        )
      : AppCopy.t(
          lang,
          ko: '평균 속도 없음',
          en: 'no avg speed',
          fr: 'pas de vitesse moy.',
        );
  final eventText = sharpCount == 0
      ? AppCopy.t(
          lang,
          ko: '큰 G 이벤트 없이',
          en: 'with no major G events',
          fr: 'sans gros événement G',
        )
      : AppCopy.t(
          lang,
          ko: 'G 이벤트 $sharpCount회와 함께',
          en: 'with $sharpCount G events',
          fr: 'avec $sharpCount événements G',
        );
  return AppCopy.t(
    lang,
    ko: '$routeName에서 ${session.distanceKm.toStringAsFixed(1)}km를 $eventText 기록했어요. $avg 기준으로 복원됩니다.',
    en: '$routeName saved ${session.distanceKm.toStringAsFixed(1)}km $eventText. Rebuilt around $avg.',
    fr: '$routeName a enregistré ${session.distanceKm.toStringAsFixed(1)}km $eventText. Résumé avec $avg.',
  );
}

String _nextSuggestion(
  RunSession session,
  int sharpCount,
  double peakG,
  AppLanguage? language,
) {
  final lang = language ?? AppLanguage.korean;
  if (session.route == null) {
    return AppCopy.t(
      lang,
      ko: '다음엔 추천 루트를 선택하면 커브 리듬까지 함께 비교할 수 있어요.',
      en: 'Next time, pick a recommended route to compare curve rhythm.',
      fr: 'La prochaine fois, choisissez une route pour comparer le rythme.',
    );
  }
  if (session.distanceKm < session.route!.distanceKm * 0.35) {
    return AppCopy.t(
      lang,
      ko: '이번엔 일부만 달렸어요. 다음엔 시작점부터 들어가 완료율을 높여보세요.',
      en: 'Only part of the route was driven. Start from the entry next time.',
      fr: 'Une partie seulement a été roulée. Essayez depuis le départ.',
    );
  }
  if (sharpCount >= 3 || peakG >= 0.45) {
    return AppCopy.t(
      lang,
      ko: '다음 추천에서는 비슷한 리듬의 후보를 우선 비교해볼 수 있어요.',
      en: 'Next picks can prioritize routes with a similar rhythm.',
      fr: 'Les prochaines options peuvent viser un rythme similaire.',
    );
  }
  return AppCopy.t(
    lang,
    ko: '다음엔 이 루트와 비슷하지만 조금 더 긴 흐름 후보를 비교해보세요.',
    en: 'Next, compare a similar route with a longer flow section.',
    fr: 'Comparez ensuite une route similaire avec plus de rythme.',
  );
}
