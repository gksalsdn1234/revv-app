import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/screens/lean_route_finder_screen.dart';

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
}
