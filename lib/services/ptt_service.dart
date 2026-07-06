import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';

import 'audio_session.dart';
import 'ptt_transport.dart';

abstract class PttRecorder {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

abstract class PttAudioCodec {
  Future<Uint8List> encode(Uint8List pcmOrEncodedBytes);
  Future<Uint8List> decode(Uint8List opusBytes);
}

abstract class PttPlayback {
  Future<void> play(Uint8List pcmOrEncodedBytes);
}

abstract class BriefingState {
  bool get isBriefingActive;
  Stream<bool> get onBriefingActiveChanged;
}

class PttService {
  PttService({
    required PttTransport transport,
    required PttRecorder recorder,
    required PttAudioCodec codec,
    required PttPlayback playback,
    required BriefingState briefingState,
  }) : _transport = transport,
       _recorder = recorder,
       _codec = codec,
       _playback = playback,
       _briefingState = briefingState {
    _briefingSubscription = _briefingState.onBriefingActiveChanged.listen((
      active,
    ) {
      if (!active) unawaited(_drainPlaybackQueue());
    });
  }

  final PttTransport _transport;
  final PttRecorder _recorder;
  final PttAudioCodec _codec;
  final PttPlayback _playback;
  final BriefingState _briefingState;
  final Queue<Uint8List> _playbackQueue = Queue<Uint8List>();

  StreamSubscription<Uint8List>? _incomingSubscription;
  StreamSubscription<bool>? _briefingSubscription;
  Future<void> _playbackDrain = Future<void>.value();

  Future<void> subscribe(String channelId) async {
    await _transport.subscribe(channelId);
    await _incomingSubscription?.cancel();
    _incomingSubscription = _transport.onChunk.listen((chunk) async {
      final decoded = await _codec.decode(chunk);
      _playbackQueue.add(decoded);
      if (!_briefingState.isBriefingActive) {
        await _drainPlaybackQueue();
      }
    });
  }

  Future<void> startHold() async {
    final stream = await _recorder.start();
    await for (final chunk in stream) {
      await _sendRecordedChunk(chunk);
    }
  }

  Future<void> stopHold() async {
    await _recorder.stop();
  }

  Future<void> _sendRecordedChunk(Uint8List chunk) async {
    final encoded = await _codec.encode(chunk);
    await _transport.sendChunk(encoded);
  }

  Future<void> _drainPlaybackQueue() {
    _playbackDrain = _playbackDrain.then((_) async {
      while (!_briefingState.isBriefingActive && _playbackQueue.isNotEmpty) {
        await _playback.play(_playbackQueue.removeFirst());
      }
    });
    return _playbackDrain;
  }

  Future<void> dispose() async {
    await _incomingSubscription?.cancel();
    await _briefingSubscription?.cancel();
    await _recorder.stop();
    await _transport.dispose();
  }
}

class RecordOpusPttRecorder implements PttRecorder {
  RecordOpusPttRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<Stream<Uint8List>> start() async {
    // record.hasPermission()은 확인 겸 OS 마이크 권한 요청을 띄운다.
    // 이게 없으면 첫 녹음이 조용히 실패한다.
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw StateError('microphone permission denied');
    }
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        sampleRate: PttChunkSpec.sampleRate,
        bitRate: PttChunkSpec.bitRate,
        numChannels: PttChunkSpec.channels,
        streamBufferSize: PttChunkSpec.pcmFrameBytes,
      ),
    );
  }

  @override
  Future<void> stop() => _recorder.stop().then((_) {});

  Future<void> dispose() => _recorder.dispose();
}

class PassthroughPttAudioCodec implements PttAudioCodec {
  const PassthroughPttAudioCodec();

  @override
  Future<Uint8List> encode(Uint8List pcmOrEncodedBytes) async =>
      Uint8List.fromList(pcmOrEncodedBytes);

  @override
  Future<Uint8List> decode(Uint8List opusBytes) async =>
      Uint8List.fromList(opusBytes);
}

class FlutterSoundPttPlayback implements PttPlayback {
  FlutterSoundPttPlayback({
    FlutterSoundPlayer? player,
    SetIosAudioCategory? setIosAudioCategory,
  }) : _player = player ?? FlutterSoundPlayer(),
       _setIosAudioCategory = setIosAudioCategory;

  final FlutterSoundPlayer _player;
  final SetIosAudioCategory? _setIosAudioCategory;
  var _opened = false;

  @override
  Future<void> play(Uint8List pcmOrEncodedBytes) async {
    await _ensureOpen();
    await _player.startPlayer(
      codec: Codec.opusOGG,
      fromDataBuffer: pcmOrEncodedBytes,
    );
  }

  Future<void> _ensureOpen() async {
    if (_opened) return;
    final setIosAudioCategory = _setIosAudioCategory;
    if (setIosAudioCategory != null) {
      await configureMusicDuckingAudioSession(
        setIosAudioCategory: setIosAudioCategory,
      );
    }
    await _player.openPlayer();
    _opened = true;
  }

  Future<void> dispose() async {
    if (!_opened) return;
    await _player.closePlayer();
    _opened = false;
  }
}
