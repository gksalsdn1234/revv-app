import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/screens/lean_route_detail_screen.dart';
import 'package:revv_app/services/settings_service.dart';

const _origin = LatLng(45, -73);

LatLng _pointM(double x, double y) {
  final lat = _origin.lat + y / 110540;
  final lng = _origin.lng + x / (111320 * math.cos(_origin.lat * math.pi / 180));
  return LatLng(lat, lng);
}

List<LatLng> _denseTurnBookNodes() {
  final nodes = <LatLng>[];
  void appendLine(double fromX, double fromY, double toX, double toY) {
    final lengthM = math.sqrt(
      math.pow(toX - fromX, 2) + math.pow(toY - fromY, 2),
    );
    final steps = math.max(1, (lengthM / 22).ceil());
    for (var step = nodes.isEmpty ? 0 : 1; step <= steps; step++) {
      final progress = step / steps;
      nodes.add(_pointM(
        fromX + (toX - fromX) * progress,
        fromY + (toY - fromY) * progress,
      ));
    }
  }
  void appendArc({
    required double centerX,
    required double centerY,
    required double start,
    required double end,
  }) {
    final count = math.max(1, (20 * (end - start).abs() / 10).ceil());
    for (var step = nodes.isEmpty ? 0 : 1; step <= count; step++) {
      final angle = start + (end - start) * step / count;
      nodes.add(_pointM(
        centerX + 20 * math.cos(angle),
        centerY + 20 * math.sin(angle),
      ));
    }
  }

  appendLine(0, 0, 0, 110);
  appendArc(centerX: 20, centerY: 110, start: math.pi, end: math.pi / 2);
  appendLine(20, 130, 130, 130);
  appendArc(centerX: 130, centerY: 150, start: -math.pi / 2, end: 0);
  appendLine(150, 150, 150, 260);
  appendArc(centerX: 170, centerY: 260, start: math.pi, end: math.pi / 2);
  appendLine(170, 280, 280, 280);
  return nodes;
}

final _route = RevvRoute(
  id: 'turn-route',
  name: '테스트 와인딩',
  nodes: _denseTurnBookNodes(),
  distanceKm: 1.0,
  windingScore: 7.2,
  starRating: 4,
  sharpCurveCount: 3,
  centerPoint: LatLng(45.0012, -72.9985),
  distanceFromUser: 0.5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('route detail renders turn-by-turn preview', (tester) async {
    final settings = SettingsService();
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(home: LeanRouteDetailScreen(route: _route)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('TURN BOOK'), findsOneWidget);
    expect(find.text('4 cues'), findsOneWidget);
    expect(find.text('100m Right Tight'), findsOneWidget);
    expect(find.textContaining('Finish'), findsWidgets);
  });
}
