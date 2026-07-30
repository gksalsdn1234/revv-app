import '../core/app_language.dart';
import '../models/run_session.dart';
import '../models/run_summary.dart';
import 'app_copy.dart';

class CopilotRunStat {
  final String label;
  final String value;

  const CopilotRunStat(this.label, this.value);
}

/// What the "next" card's button actually does.
enum CopilotNextAction {
  /// Open the route finder on a specific route — used when the driver left a
  /// known route unfinished.
  retryRoute,

  /// Open the route finder to pick something new.
  findRoute,
}

class CopilotRunSummaryCopy {
  /// One coach-voice observation: something the driver could not see from the
  /// seat, plus the one thing to do about it. This replaces the old headline,
  /// which restated facts the driver already knew.
  final String coachNote;
  final String summaryLine;
  final String nextSuggestion;
  final CopilotNextAction nextAction;
  final String nextActionLabel;

  /// Route to reopen when [nextAction] is [CopilotNextAction.retryRoute].
  final String? nextRouteId;
  final List<CopilotRunStat> notableStats;

  const CopilotRunSummaryCopy({
    required this.coachNote,
    required this.summaryLine,
    required this.nextSuggestion,
    required this.nextAction,
    required this.nextActionLabel,
    required this.nextRouteId,
    required this.notableStats,
  });

  factory CopilotRunSummaryCopy.fromSession(
    RunSession session, {
    RunSummary? summary,
    AppLanguage? language,
  }) {
    final signals = _RunSignals.of(session);
    final lang = language ?? AppLanguage.korean;
    final retry = signals.isPartial && session.route != null;
    return CopilotRunSummaryCopy(
      coachNote: _coachNote(signals, lang),
      summaryLine: _summaryLine(signals, session.routeName, lang),
      nextSuggestion: _nextSuggestion(signals, lang),
      nextAction: retry
          ? CopilotNextAction.retryRoute
          : CopilotNextAction.findRoute,
      nextActionLabel: retry
          ? AppCopy.t(
              lang,
              ko: '이 루트 다시 열기',
              en: 'Open this route again',
              fr: 'Rouvrir cet itinéraire',
            )
          : AppCopy.t(
              lang,
              ko: '다음 루트 찾기',
              en: 'Find the next route',
              fr: 'Trouver le prochain itinéraire',
            ),
      nextRouteId: retry ? session.route?.id : null,
      notableStats: [
        CopilotRunStat(
          AppCopy.t(lang, ko: '거리', en: 'Distance', fr: 'Distance'),
          '${session.distanceKm.toStringAsFixed(2)} km',
        ),
        CopilotRunStat(
          AppCopy.t(lang, ko: '시간', en: 'Time', fr: 'Temps'),
          session.durationDisplay,
        ),
        CopilotRunStat(
          AppCopy.t(lang, ko: '커브 이벤트', en: 'Curve events', fr: 'Événements'),
          AppCopy.t(
            lang,
            ko: '${signals.cornerCount}회',
            en: '${signals.cornerCount}',
            fr: '${signals.cornerCount}',
          ),
        ),
      ],
    );
  }
}

/// Derived shape/rhythm signals for one run. Reads more than distance and a raw
/// corner count so the copy has several independent axes to vary on. No signal
/// exposes a raw g-force, a peak/record framing, or speed as the headline fact.
class _RunSignals {
  final bool hasRoute;
  final double distanceKm;
  final int cornerCount;

  /// Corners driven with meaningful lateral load. Threshold is internal — the
  /// count is described qualitatively, the g-value is never shown.
  final int committedCorners;

  /// Corners per km. Separates a tight technical road from a long cruise that
  /// happens to have a few bends.
  final double cornerDensity;

  /// Share of corners that fall in the back half of the drive by time. High
  /// means the road built toward its corners rather than front-loading them.
  final double lateCornerShare;

  /// Fraction of the route actually driven, when on a known route.
  final double? completion;

  const _RunSignals({
    required this.hasRoute,
    required this.distanceKm,
    required this.cornerCount,
    required this.committedCorners,
    required this.cornerDensity,
    required this.lateCornerShare,
    required this.completion,
  });

  static const _committedLateralG = 0.40;

  bool get isCheckDrive => distanceKm < 0.3;
  bool get isDense => cornerDensity >= 1.5;
  bool get isLateHeavy => cornerCount >= 4 && lateCornerShare >= 0.6;
  bool get isCommitted => committedCorners >= 3;
  bool get isPartial => (completion ?? 1.0) < 0.35;
  bool get isCalm => cornerCount <= 1;

  factory _RunSignals.of(RunSession session) {
    final corners = session.sharpCorners;
    final cornerCount = corners.length;
    final distanceKm = session.distanceKm;

    final committed = corners
        .where((c) => c.lateralG.abs() >= _committedLateralG)
        .length;

    final density = distanceKm > 0 ? cornerCount / distanceKm : 0.0;

    // Late share by time, using each corner's timestamp against the run window.
    var lateShare = 0.0;
    if (cornerCount > 0) {
      final start = session.startTime.millisecondsSinceEpoch;
      final end = session.endTime.millisecondsSinceEpoch;
      final span = end - start;
      if (span > 0) {
        final lateCount = corners.where((c) {
          final t = c.time.millisecondsSinceEpoch;
          return (t - start) / span >= 0.5;
        }).length;
        lateShare = lateCount / cornerCount;
      }
    }

    double? completion;
    final route = session.route;
    if (route != null && route.distanceKm > 0) {
      completion = (distanceKm / route.distanceKm).clamp(0.0, 1.0);
    }

    return _RunSignals(
      hasRoute: route != null,
      distanceKm: distanceKm,
      cornerCount: cornerCount,
      committedCorners: committed,
      cornerDensity: density,
      lateCornerShare: lateShare,
      completion: completion,
    );
  }
}

/// Coach voice: tell the driver something they could not see from the seat,
/// then give them one thing to do with it. Never a compliment on pace, never a
/// record — the coaching is about reading the road, not attacking it.
String _coachNote(_RunSignals s, AppLanguage lang) {
  if (s.isCheckDrive) {
    return AppCopy.t(
      lang,
      ko: '너무 짧아서 읽을 게 없어요. 체크 주행으로만 저장할게요.',
      en: 'Too short to read anything from. Saving it as a check drive.',
      fr: 'Trop court pour en tirer quelque chose. Enregistré comme test.',
    );
  }

  if (s.isPartial) {
    final pct = ((s.completion ?? 0) * 100).round();
    return AppCopy.t(
      lang,
      ko: '이 루트의 $pct%만 봤어요. 굽이가 몰린 구간은 아직 나오지도 않았어요.',
      en: 'You only saw $pct% of this route. The section where it tightens up is still ahead.',
      fr: 'Vous n’avez vu que $pct% de cet itinéraire. La partie sinueuse reste à venir.',
    );
  }

  if (s.isLateHeavy) {
    return AppCopy.t(
      lang,
      ko: '코너가 후반에 몰려 있어요. 앞 절반은 길을 읽는 구간으로 쓰고, 뒤쪽에 집중하면 되는 루트예요.',
      en: 'The corners bunch up in the back half. Use the first half to read the road and save your attention for later.',
      fr: 'Les virages se concentrent en seconde moitié. Servez-vous du début pour lire la route.',
    );
  }

  if (s.isDense) {
    final perKm = s.cornerDensity.toStringAsFixed(1);
    return AppCopy.t(
      lang,
      ko: 'km당 코너 $perKm개. 펴지는 구간이 거의 없어요. 시선을 한 코너 더 앞에 두면 훨씬 수월해져요.',
      en: '$perKm corners per km — it barely straightens out. Look one corner further ahead and it gets much easier.',
      fr: '$perKm virages par km, presque aucun répit. Regardez un virage plus loin.',
    );
  }

  if (s.isCommitted) {
    return AppCopy.t(
      lang,
      ko: '코너 ${s.cornerCount}개 중 ${s.committedCorners}개가 확실히 물렸어요. 나머지는 흐름으로 넘기고 그 몇 개에 집중하는 길이에요.',
      en: '${s.committedCorners} of ${s.cornerCount} corners really loaded up. The rest you can flow through — those few are where the road asks for you.',
      fr: '${s.committedCorners} virages sur ${s.cornerCount} ont vraiment chargé. Le reste se passe en fluidité.',
    );
  }

  if (!s.hasRoute) {
    return AppCopy.t(
      lang,
      ko: '루트 없이 달렸어요. 추천 루트로 달리면 같은 길을 다음에 어떻게 읽었는지 비교할 수 있어요.',
      en: 'You drove this one off-route. On a picked route we can compare how you read the same road next time.',
      fr: 'Trajet hors itinéraire. Sur une route choisie, on pourra comparer la prochaine fois.',
    );
  }

  if (s.isCalm) {
    return AppCopy.t(
      lang,
      ko: '거의 곧게 뻗은 길이었어요. 굽은 길을 찾아내는 게 이 앱이 제일 잘하는 일이에요.',
      en: 'That road ran almost straight. Finding the bent ones is what this app is actually for.',
      fr: 'Route presque droite. Trouver les routes sinueuses, c’est là que l’app sert.',
    );
  }

  return AppCopy.t(
    lang,
    ko: '코너가 고르게 퍼져 있는 루트예요. 리듬을 잡고 반복해서 읽기 좋은 길이에요.',
    en: 'The corners sit evenly across this one — a good road to settle into a rhythm and read repeatedly.',
    fr: 'Les virages sont répartis régulièrement — une bonne route pour installer un rythme.',
  );
}

/// A short character line for the slot under the route title. Deliberately
/// carries no distance, duration or corner count: those numbers sit in the stat
/// tiles a few pixels below, and repeating them was this screen's worst
/// duplication.
String _summaryLine(_RunSignals s, String routeName, AppLanguage lang) {
  if (s.isCheckDrive) {
    return AppCopy.t(
      lang,
      ko: '체크 주행',
      en: 'Check drive',
      fr: 'Trajet de test',
    );
  }
  if (s.isPartial) {
    return AppCopy.t(
      lang,
      ko: '앞 구간만 · 미완주',
      en: 'Opening stretch only · unfinished',
      fr: 'Début seulement · inachevé',
    );
  }
  if (s.cornerCount == 0) {
    return AppCopy.t(
      lang,
      ko: '잔잔하게 흐른 주행',
      en: 'Calm, steady going',
      fr: 'Trajet calme et régulier',
    );
  }
  if (s.isLateHeavy) {
    return AppCopy.t(
      lang,
      ko: '후반으로 갈수록 촘촘해지는 리듬',
      en: 'A rhythm that tightens toward the finish',
      fr: 'Un rythme qui se resserre vers la fin',
    );
  }
  if (s.isCommitted) {
    return AppCopy.t(
      lang,
      ko: '묵직하게 물리는 코너 위주',
      en: 'Built around committed corners',
      fr: 'Construit autour de virages engagés',
    );
  }
  if (s.isDense) {
    return AppCopy.t(
      lang,
      ko: '쉴 틈 없이 이어지는 테크니컬 구간',
      en: 'Technical, one corner after another',
      fr: 'Technique, virage après virage',
    );
  }
  if (!s.hasRoute) {
    return AppCopy.t(
      lang,
      ko: '루트 없이 달린 주행',
      en: 'Driven off-route',
      fr: 'Trajet hors itinéraire',
    );
  }
  return AppCopy.t(
    lang,
    ko: '고르게 퍼진 코너 리듬',
    en: 'Corners spread evenly',
    fr: 'Virages répartis régulièrement',
  );
}

String _nextSuggestion(_RunSignals s, AppLanguage lang) {
  if (!s.hasRoute) {
    return AppCopy.t(
      lang,
      ko: '다음엔 추천 루트를 선택하면 커브 리듬까지 함께 비교할 수 있어요.',
      en: 'Next time, pick a recommended route to compare curve rhythm.',
      fr: 'La prochaine fois, choisissez une route pour comparer le rythme.',
    );
  }
  if (s.isPartial) {
    return AppCopy.t(
      lang,
      ko: '이번엔 앞부분만 달렸어요. 다음엔 시작점부터 들어가 완주해보세요.',
      en: 'Only the opening was driven. Start from the entry next time to finish it.',
      fr: 'Seul le début a été roulé. Repartez du départ pour le terminer.',
    );
  }
  if (s.isCommitted || s.isDense) {
    return AppCopy.t(
      lang,
      ko: '이 리듬이 좋았다면, 다음 추천에서 비슷한 기술적 루트를 우선 비교해볼게요.',
      en: 'If that rhythm landed, next picks can prioritize similar technical routes.',
      fr: 'Si ce rythme vous a plu, les prochaines suggestions viseront des routes techniques.',
    );
  }
  if (s.isCalm) {
    return AppCopy.t(
      lang,
      ko: '더 물리는 코너를 원하면, 다음 추천에서 와인딩이 강한 후보를 섞어볼게요.',
      en: 'Want more corner load? Next picks can mix in more winding candidates.',
      fr: 'Envie de plus de virages ? On ajoutera des routes plus sinueuses.',
    );
  }
  return AppCopy.t(
    lang,
    ko: '다음엔 이 루트와 비슷한 추천 후보 중 더 긴 흐름을 비교해보세요.',
    en: 'Next, compare a similar recommended route with a longer flow section.',
    fr: 'Comparez ensuite une route similaire avec une section plus longue.',
  );
}
