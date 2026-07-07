import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
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

/// PTT 시작 시 무전기 "삐릭" 피드백. 실패는 조용히 무시(보조 신호).
abstract class WalkieChirp {
  Future<void> play();
  Future<void> dispose();
}

// ⚠️ 출시 전 삭제 필수 (RELEASE BLOCKER): 현재 assets/sounds/beep.mp3 는
// myinstants F1 라디오 클립(F1 방송 원본 오디오)이라 상업 배포 라이선스가 없다.
// 개인 테스트 용도로만 사용 중. App Store 제출 전에 반드시 오리지널 합성음으로
// 교체하거나 이 chirp 자체를 제거할 것. (Codex/민우 릴리즈 체크리스트 항목)
class BeepWalkieChirp implements WalkieChirp {
  final AudioPlayer _player = AudioPlayer(playerId: 'walkie-chirp');
  bool _configured = false;

  @override
  Future<void> play() async {
    try {
      if (!_configured) {
        // playAndRecord: 비프 재생 직후 곧바로 녹음이 시작되므로 세션을
        // 재생 전용(playback)으로 잡으면 마이크가 못 켜진다. 둘 다 되는
        // 카테고리로 통일하고, 음악 위 덕킹 + 스피커 출력을 유지한다.
        await _player.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playAndRecord,
              options: const {
                AVAudioSessionOptions.duckOthers,
                AVAudioSessionOptions.mixWithOthers,
                AVAudioSessionOptions.defaultToSpeaker,
                AVAudioSessionOptions.allowBluetooth,
              },
            ),
            android: const AudioContextAndroid(
              usageType: AndroidUsageType.assistanceSonification,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
          ),
        );
        // 저지연 모드 + 소스 사전 로드 — 누를 때마다 로드하는 지연 제거.
        await _player.setPlayerMode(PlayerMode.lowLatency);
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setVolume(0.3); // 무전 톤은 배경 신호 — 작게
        await _player.setSource(AssetSource('sounds/beep.mp3'));
        _configured = true;
      }
      // 이미 로드된 소스를 처음부터 즉시 재생.
      await _player.seek(Duration.zero);
      await _player.resume();
    } catch (_) {
      // 효과음 실패는 무전 동작을 막지 않는다.
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}

class PttServiceWalkieController implements WalkiePttController {
  PttServiceWalkieController(this._service, {WalkieChirp? chirp})
    : _chirp = chirp;

  factory PttServiceWalkieController.production() {
    return PttServiceWalkieController(
      PttService(
        transport: RealtimePttTransport(),
        recorder: RecordPcmPttRecorder(),
        codec: const PassthroughPttAudioCodec(),
        playback: FlutterSoundPttPlayback(),
        briefingState: const IdleBriefingState(),
      ),
      chirp: BeepWalkieChirp(),
    );
  }

  final PttService _service;
  final WalkieChirp? _chirp;
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
    // 누르는 즉시 삐릭 — 전송 준비와 병렬로(대기하지 않음).
    unawaited(_chirp?.play());
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
    await _chirp?.dispose();
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
