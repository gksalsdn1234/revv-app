import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_finder_screen.dart';
import 'package:revv_app/services/route_loading_policy.dart';
import 'package:revv_app/services/settings_service.dart';

void main() {
  const forbiddenWords = ['MAX', 'BEST', 'PEAK', '어택', '스릴', '경쟁'];

  Future<void> pumpStateCard(
    WidgetTester tester,
    RouteFinderStateKind kind, {
    VoidCallback? onAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteFinderStateCard(
            kind: kind,
            language: AppLanguage.korean,
            onAction: onAction ?? () {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpCoverageCard(
    WidgetTester tester, {
    bool requested = false,
    bool requesting = false,
    VoidCallback? onRequest,
    VoidCallback? onBrowseMontreal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteCoverageBoundaryCard(
            language: AppLanguage.korean,
            requested: requested,
            requesting: requesting,
            onRequest: onRequest ?? () {},
            onBrowseMontreal: onBrowseMontreal ?? () {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpWithSettings(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  void expectSafeCopy(List<String> values) {
    for (final value in values) {
      for (final forbidden in forbiddenWords) {
        expect(value, isNot(contains(forbidden)));
      }
    }
  }

  testWidgets('temporary location denial renders retry permission action', (
    tester,
  ) async {
    var tapped = false;

    await pumpStateCard(
      tester,
      RouteFinderStateKind.temporaryLocationDenied,
      onAction: () => tapped = true,
    );

    const expected = ['위치 권한이 꺼져 있어요', '위치 다시 허용'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expectSafeCopy(expected);

    await tester.tap(find.text(expected[1]));
    expect(tapped, isTrue);
  });

  testWidgets('permanent location denial renders settings action', (
    tester,
  ) async {
    await pumpStateCard(tester, RouteFinderStateKind.permanentlyLocationDenied);

    const expected = ['설정에서 위치 권한을 켜주세요', '설정 열기'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets('empty routes state nudges region presets', (tester) async {
    await pumpStateCard(tester, RouteFinderStateKind.emptyRoutes);

    const expected = ['이 반경엔 아직 발견된 루트가 없어요', '지역 프리셋'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('반경을 넓히거나'), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets('load failure renders retry action without backend terms', (
    tester,
  ) async {
    await pumpStateCard(tester, RouteFinderStateKind.loadFailed);

    const expected = ['루트를 불러오지 못했어요', '다시 찾기'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('Supabase'), findsNothing);
    expect(find.textContaining('HTTP'), findsNothing);
    expectSafeCopy(expected);
  });

  testWidgets('cached routes state explains saved data and offers picks', (
    tester,
  ) async {
    await pumpStateCard(tester, RouteFinderStateKind.cachedRoutes);

    const expected = ['저장된 루트를 먼저 보여드려요', '추천 보기'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('저장된 커브길'), findsOneWidget);
    expectSafeCopy(expected);
  });

  testWidgets(
    'coverage boundary card renders demand request and Montreal cue',
    (tester) async {
      var requestTapped = false;
      var browseTapped = false;

      await pumpCoverageCard(
        tester,
        onRequest: () => requestTapped = true,
        onBrowseMontreal: () => browseTapped = true,
      );

      const expected = ['지금은 몬트리올 일대의 루트를 제공해요', '우리 지역 알림 받기', '몬트리올 보기'];
      expect(find.text(expected[0]), findsOneWidget);
      expect(find.text(expected[1]), findsOneWidget);
      expect(find.text(expected[2]), findsOneWidget);
      expect(find.textContaining('이 지역은 준비 중'), findsOneWidget);
      expectSafeCopy(expected);

      await tester.tap(find.text(expected[1]));
      await tester.tap(find.text(expected[2]));

      expect(requestTapped, isTrue);
      expect(browseTapped, isTrue);
    },
  );

  testWidgets('coverage boundary card renders completed request state', (
    tester,
  ) async {
    await pumpCoverageCard(tester, requested: true);

    expect(find.text('알림 신청됨'), findsOneWidget);
    expect(find.text('우리 지역 알림 받기'), findsNothing);
  });

  testWidgets(
    'drive budget strip renders duration chips and changes selection',
    (tester) async {
      DriveBudget selected = DriveBudget.any;

      await pumpWithSettings(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DriveBudgetChoiceStrip(
            budget: selected,
            routes: const [],
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      );

      expect(find.text('Any'), findsOneWidget);
      expect(find.text('~30 min'), findsOneWidget);
      expect(find.text('~1 hour'), findsOneWidget);
      expect(find.text('2h+'), findsOneWidget);

      await tester.tap(find.text('~30 min'));
      await tester.pump();

      expect(selected, DriveBudget.short);
    },
  );

  testWidgets('route duration meta renders estimate and chain segment count', (
    tester,
  ) async {
    final route = RevvRoute(
      id: 'combo:a:b',
      name: 'North + Valley',
      nodes: const [LatLng(45.0, -73.0), LatLng(45.02, -73.02)],
      distanceKm: 36,
      windingScore: 6.2,
      starRating: 4,
      sharpCurveCount: 10,
      centerPoint: const LatLng(45.01, -73.01),
      distanceFromUser: 8,
      tightCurveKm: 2,
      mediumCurveKm: 2,
      maxContinuousKm: 1.4,
    );

    await pumpWithSettings(
      tester,
      RouteDurationMeta(route: route, language: AppLanguage.korean),
    );

    expect(find.text('~46분 · 2개 코스 연결'), findsOneWidget);
  });

  testWidgets('drive budget empty card nudges other duration or radius', (
    tester,
  ) async {
    await pumpWithSettings(
      tester,
      DriveBudgetEmptyCard(language: AppLanguage.korean, onAction: () {}),
    );

    const expected = ['이 분량에 맞는 루트가 아직 없어요', '전체 분량'];
    expect(find.text(expected[0]), findsOneWidget);
    expect(find.text(expected[1]), findsOneWidget);
    expect(find.textContaining('다른 분량'), findsOneWidget);
    expect(find.textContaining('반경/지역'), findsOneWidget);
    expectSafeCopy(expected);
  });
}
