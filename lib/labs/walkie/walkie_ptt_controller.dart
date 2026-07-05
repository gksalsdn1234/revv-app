import 'dart:async';

import '../../services/ptt_service.dart';
import '../../services/ptt_transport.dart';

/// 랩 화면·주행 화면이 공유하는 PTT 조작 인터페이스.
/// 전송/녹음 파이프라인은 [PttService] 뒤에 숨는다.
abstract class WalkiePttController {
  Future<void> startTalking(String channelId);
  Future<void> stopTalking();
  Future<void> dispose();
}

class PttServiceWalkieController implements WalkiePttController {
  PttServiceWalkieController(this._service);

  factory PttServiceWalkieController.production() {
    return PttServiceWalkieController(
      PttService(
        transport: RealtimePttTransport(),
        recorder: RecordOpusPttRecorder(),
        codec: const PassthroughPttAudioCodec(),
        playback: FlutterSoundPttPlayback(),
        briefingState: const IdleBriefingState(),
      ),
    );
  }

  final PttService _service;
  String? _subscribedChannelId;
  bool _talking = false;

  @override
  Future<void> startTalking(String channelId) async {
    if (_talking) return;
    _talking = true;
    try {
      if (_subscribedChannelId != channelId) {
        await _service.subscribe(channelId);
        _subscribedChannelId = channelId;
      }
      await _service.startHold();
    } finally {
      _talking = false;
    }
  }

  @override
  Future<void> stopTalking() => _service.stopHold();

  @override
  Future<void> dispose() => _service.dispose();
}

/// 코너 브리핑 연동이 없는 기본 브리핑 상태 (랩/독립 사용).
class IdleBriefingState implements BriefingState {
  const IdleBriefingState();

  @override
  bool get isBriefingActive => false;

  @override
  Stream<bool> get onBriefingActiveChanged => const Stream<bool>.empty();
}
