import 'package:flutter/foundation.dart';

import '../../services/ptt_service.dart';
import '../../services/ptt_transport.dart';

/// 랩 화면·주행 화면이 공유하는 PTT 조작 인터페이스.
/// 전송/녹음 파이프라인은 [PttService] 뒤에 숨는다.
abstract class WalkiePttController {
  ValueListenable<bool> get channelBusy;
  ValueListenable<double> get micLevel;
  ValueListenable<PttConnectionState> get connectionState;

  /// 채널에 참여하는 즉시 호출 — broadcast 수신을 연다(듣기 전용 포함).
  /// 같은 channelId로 중복 호출해도 안전(멱등).
  Future<void> connect(String channelId);

  /// 방을 떠날 때 호출 — 수신 구독을 닫는다.
  Future<void> disconnect();

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
        recorder: RecordPcmPttRecorder(),
        codec: const PassthroughPttAudioCodec(),
        playback: FlutterSoundPttPlayback(),
        briefingState: const IdleBriefingState(),
      ),
    );
  }

  final PttService _service;
  String? _subscribedChannelId;
  Future<void>? _connecting;
  String? _connectingChannelId;
  bool _talking = false;

  @override
  ValueListenable<bool> get channelBusy => _service.channelBusy;

  @override
  ValueListenable<double> get micLevel => _service.micLevel;

  @override
  ValueListenable<PttConnectionState> get connectionState =>
      _service.connectionState;

  @override
  Future<void> connect(String channelId) {
    if (_subscribedChannelId == channelId) return Future<void>.value();
    final pending = _connecting;
    if (pending != null && _connectingChannelId == channelId) return pending;
    _connectingChannelId = channelId;
    final future = _service
        .subscribe(channelId)
        .then((_) {
          _subscribedChannelId = channelId;
        })
        .whenComplete(() {
          _connecting = null;
          _connectingChannelId = null;
        });
    _connecting = future;
    return future;
  }

  @override
  Future<void> disconnect() async {
    try {
      await _connecting;
    } catch (_) {}
    if (_subscribedChannelId == null) return;
    await _service.unsubscribe();
    _subscribedChannelId = null;
  }

  @override
  Future<void> startTalking(String channelId) async {
    if (_service.channelBusy.value) return;
    if (_talking) return;
    _talking = true;
    try {
      await connect(channelId);
      await _service.startHold();
    } finally {
      _talking = false;
    }
  }

  @override
  Future<void> stopTalking() => _service.stopHold();

  @override
  Future<void> dispose() async {
    await _service.dispose();
  }
}

/// 코너 브리핑 연동이 없는 기본 브리핑 상태 (랩/독립 사용).
class IdleBriefingState implements BriefingState {
  const IdleBriefingState();

  @override
  bool get isBriefingActive => false;

  @override
  Stream<bool> get onBriefingActiveChanged => const Stream<bool>.empty();
}
