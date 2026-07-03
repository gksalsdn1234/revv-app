import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/ui/copilot_briefing.dart';

RevvRoute _route({
  String id = 'route',
  String name = 'Chemin Test',
  double distanceKm = 14,
  double distanceFromUser = 0.5,
  double tightCurveKm = 0.8,
  double mediumCurveKm = 2.0,
  double maxContinuousKm = 1.6,
  double flowScore = 0.8,
  bool isMajorRoadLike = false,
  bool isBridgeLike = false,
  bool isLoop = false,
}) {
  return RevvRoute(
    id: id,
    name: name,
    nodes: const [LatLng(45.0, -73.0), LatLng(45.1, -73.1)],
    distanceKm: distanceKm,
    windingScore: 6.2,
    starRating: 4,
    sharpCurveCount: 8,
    centerPoint: const LatLng(45.05, -73.05),
    distanceFromUser: distanceFromUser,
    tightCurveKm: tightCurveKm,
    mediumCurveKm: mediumCurveKm,
    maxContinuousKm: maxContinuousKm,
    flowScore: flowScore,
    isMajorRoadLike: isMajorRoadLike,
    isBridgeLike: isBridgeLike,
    isLoop: isLoop,
  );
}

void main() {
  test('start advice changes by start distance', () {
    final near = CopilotRouteBriefing.fromRoute(
      _route(distanceFromUser: 0.4),
      startDistanceKm: 0.4,
    );
    final mid = CopilotRouteBriefing.fromRoute(
      _route(distanceFromUser: 6.2),
      startDistanceKm: 6.2,
    );
    final far = CopilotRouteBriefing.fromRoute(
      _route(distanceFromUser: 12.4),
      startDistanceKm: 12.4,
    );

    expect(near.startAdvice, contains('바로 주행'));
    expect(mid.startAdvice, contains('먼저 이동'));
    expect(far.startAdvice, contains('진입 동선'));
    expect(near.nextActionLabel, '바로 주행 시작');
    expect(mid.nextActionLabel, '시작점까지 이동 후 시작');
    expect(far.nextActionLabel, '지도 확인 후 주행 시작');
  });

  test('route style changes primary advice', () {
    final tight = CopilotRouteBriefing.fromRoute(
      _route(
        distanceFromUser: 24,
        tightCurveKm: 2.0,
        mediumCurveKm: 0.5,
        maxContinuousKm: 1.0,
      ),
    );
    final sweeper = CopilotRouteBriefing.fromRoute(
      _route(
        distanceFromUser: 24,
        tightCurveKm: 0.2,
        mediumCurveKm: 3.0,
        maxContinuousKm: 1.8,
      ),
    );
    final flow = CopilotRouteBriefing.fromRoute(
      _route(
        distanceFromUser: 24,
        tightCurveKm: 0.5,
        mediumCurveKm: 1.5,
        maxContinuousKm: 2.2,
      ),
    );

    expect(tight.primaryAdvice, contains('타이트'));
    expect(sweeper.primaryAdvice, matches(RegExp(r'\d')));
    expect(flow.primaryAdvice, matches(RegExp(r'\d')));
    expect(tight.primaryAdvice, isNot(sweeper.primaryAdvice));
  });

  test('primary advice reuses informative preview copy', () {
    final briefing = CopilotRouteBriefing.fromRoute(
      _route(
        id: 'numeric-preview',
        distanceKm: 18,
        tightCurveKm: 1.4,
        mediumCurveKm: 1.2,
        maxContinuousKm: 2.0,
      ),
    );

    expect(briefing.primaryAdvice, matches(RegExp(r'\d')));
    expect(briefing.primaryAdvice, isNot(matches(RegExp(r'속도|스릴|짜릿|과속'))));
  });

  test('broad and road-risk candidates expose caution explicitly', () {
    final major = CopilotRouteBriefing.fromRoute(
      _route(isMajorRoadLike: true),
      filterStrength: RouteFilterStrength.broad,
    );
    final bridge = CopilotRouteBriefing.fromRoute(
      _route(isBridgeLike: true),
      filterStrength: RouteFilterStrength.broad,
    );

    expect(major.riskAdvice, contains('간선도로'));
    expect(bridge.riskAdvice, contains('브리지'));
  });

  test('headline, primary advice, and risk advice are not duplicated', () {
    final briefing = CopilotRouteBriefing.fromRoute(_route());

    expect(briefing.headline, isNot(briefing.primaryAdvice));
    expect(briefing.primaryAdvice, isNot(briefing.riskAdvice));
    expect(
      briefing.decisionChips.toSet().length,
      briefing.decisionChips.length,
    );
  });

  test('route briefing supports English and French copy', () {
    final english = CopilotRouteBriefing.fromRoute(
      _route(distanceFromUser: 4.2),
      startDistanceKm: 4.2,
      language: AppLanguage.english,
    );
    final french = CopilotRouteBriefing.fromRoute(
      _route(distanceFromUser: 4.2),
      startDistanceKm: 4.2,
      language: AppLanguage.french,
    );

    expect(english.startAdvice, contains('Start is'));
    expect(english.primaryAdvice, matches(RegExp(r'\d')));
    expect(english.primaryAdvice, isNot(contains('좋아요')));
    expect(french.startAdvice, contains('Départ'));
    expect(french.primaryAdvice, matches(RegExp(r'\d')));
    expect(french.nextActionLabel, 'Aller au départ');
  });
}
