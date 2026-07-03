import 'package:revv_app/models/run_session.dart';
import 'package:revv_app/services/run_session_service.dart';

import '../fixtures/gps/replay_fixtures.dart';

class GpsReplayHarness {
  GpsReplayHarness({DateTime? startTime}) {
    _clock = _ReplayClock(startTime ?? DateTime.parse('2026-07-02T12:00:00Z'));
    service = RunSessionService(clock: () => _clock.now);
  }

  late final _ReplayClock _clock;
  late final RunSessionService service;
  double _maxLateralG = 0;
  double _maxLongitudinalG = 0;

  DateTime get now => _clock.now;

  void start() {
    service.startSession(null);
  }

  void advance(Duration duration) {
    _clock.advance(duration);
  }

  void replay(GpsReplayFixture fixture, {int startIndex = 0, int? endIndex}) {
    final end = endIndex ?? fixture.samples.length;
    for (var i = startIndex; i < end; i++) {
      final sample = fixture.samples[i];
      _clock.setElapsed(Duration(milliseconds: sample.tMs));
      if (sample.lateralG.abs() > _maxLateralG) {
        _maxLateralG = sample.lateralG.abs();
      }
      if (sample.longitudinalG.abs() > _maxLongitudinalG) {
        _maxLongitudinalG = sample.longitudinalG.abs();
      }
      service.recordPosition(
        sample.lat,
        sample.lng,
        sample.speedKmh,
        lateralG: sample.lateralG,
        longitudinalG: sample.longitudinalG,
        driveMode: sample.driveMode,
      );
      if (sample.lateralG.abs() >= 0.45) {
        service.recordSharpCorner(
          sample.lat,
          sample.lng,
          sample.lateralG,
          speedKmh: sample.speedKmh,
          driveMode: sample.driveMode,
        );
      }
    }
  }

  RunSession stop() {
    final session = service.stopSession(
      maxLateralG: _maxLateralG,
      maxLonG: _maxLongitudinalG,
    );
    if (session == null) {
      throw StateError('Expected replayed session to stop with data.');
    }
    return session;
  }
}

class _ReplayClock {
  _ReplayClock(this._start) : now = _start;

  final DateTime _start;
  DateTime now;

  void setElapsed(Duration elapsed) {
    now = _start.add(elapsed);
  }

  void advance(Duration duration) {
    now = now.add(duration);
  }
}
