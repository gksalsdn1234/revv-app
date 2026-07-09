import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/drive_dynamics_tracker.dart';

void main() {
  test('counts one hard brake when braking lasts at least 0.4 seconds', () {
    final tracker = DriveDynamicsTracker();

    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.36,
      elapsed: Duration.zero,
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.36,
      elapsed: const Duration(milliseconds: 200),
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.36,
      elapsed: const Duration(milliseconds: 400),
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.5,
      elapsed: const Duration(milliseconds: 700),
    );

    final summary = tracker.summarize();

    expect(summary.hardBrakeCount, 1);
  });

  test('ignores hard brake shorter than 0.4 seconds', () {
    final tracker = DriveDynamicsTracker();

    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.36,
      elapsed: Duration.zero,
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.36,
      elapsed: const Duration(milliseconds: 300),
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: 0,
      elapsed: const Duration(milliseconds: 500),
    );

    final summary = tracker.summarize();

    expect(summary.hardBrakeCount, 0);
  });

  test('debounces abrupt steering spikes for 0.8 seconds', () {
    final tracker = DriveDynamicsTracker();

    tracker.addSample(lateralG: 0, longitudinalG: 0, elapsed: Duration.zero);
    tracker.addSample(
      lateralG: 0.3,
      longitudinalG: 0,
      elapsed: const Duration(milliseconds: 200),
    );
    tracker.addSample(
      lateralG: -0.3,
      longitudinalG: 0,
      elapsed: const Duration(milliseconds: 400),
    );
    tracker.addSample(
      lateralG: 0.4,
      longitudinalG: 0,
      elapsed: const Duration(milliseconds: 1200),
    );

    final summary = tracker.summarize();

    expect(summary.harshSteerCount, 2);
  });

  test('calculates smooth ratio from non-event sample time', () {
    final tracker = DriveDynamicsTracker();

    tracker.addSample(lateralG: 0, longitudinalG: 0, elapsed: Duration.zero);
    tracker.addSample(
      lateralG: 0,
      longitudinalG: 0,
      elapsed: const Duration(milliseconds: 500),
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.4,
      elapsed: const Duration(milliseconds: 1000),
    );
    tracker.addSample(
      lateralG: 0,
      longitudinalG: -0.4,
      elapsed: const Duration(milliseconds: 1500),
    );

    final summary = tracker.summarize();

    expect(summary.hardBrakeCount, 1);
    expect(summary.smoothRatio, closeTo(1 / 3, 0.01));
    expect(summary.sampleSeconds, 2);
  });

  test('approximates p95 lateral g without retaining raw samples', () {
    final tracker = DriveDynamicsTracker();

    for (var i = 0; i < 95; i++) {
      tracker.addSample(
        lateralG: 0.2,
        longitudinalG: 0,
        elapsed: Duration(milliseconds: i * 100),
      );
    }
    for (var i = 95; i < 100; i++) {
      tracker.addSample(
        lateralG: 0.8,
        longitudinalG: 0,
        elapsed: Duration(milliseconds: i * 100),
      );
    }

    final summary = tracker.summarize();

    expect(summary.p95LateralG, closeTo(0.2, 0.02));
  });
}
