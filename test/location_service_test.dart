import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/location_service.dart';

void main() {
  test('trusted speed hysteresis does not toggle on 5 to 7m/s oscillation', () {
    final gate = TrustedSpeedGate();
    final start = DateTime(2026, 8, 2, 12);
    for (var second = 0; second < 6; second++) {
      final now = start.add(Duration(seconds: second));
      gate.update(
        speedMps: second.isEven ? 5 : 7,
        timestamp: now,
        accuracyM: 5,
        now: now,
      );
    }

    expect(gate.isSpeedMode, isFalse);
    expect(gate.speedFor(start.add(const Duration(seconds: 6))), isNull);
  });

  test('stale positions keep distance timing even after speed mode entered', () {
    final gate = TrustedSpeedGate();
    final start = DateTime(2026, 8, 2, 12);
    for (var second = 0; second <= 2; second++) {
      final now = start.add(Duration(seconds: second));
      gate.update(
        speedMps: 8,
        timestamp: now,
        accuracyM: 5,
        now: now,
      );
    }
    expect(gate.isSpeedMode, isTrue);

    final staleNow = start.add(const Duration(seconds: 5));
    gate.update(
      speedMps: 8,
      timestamp: start,
      accuracyM: 5,
      now: staleNow,
    );
    expect(gate.speedFor(staleNow), isNull);
    expect(gate.isSpeedMode, isFalse);
  });
}
