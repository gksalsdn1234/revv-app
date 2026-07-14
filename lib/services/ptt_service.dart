import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';

import 'audio_session.dart';
import 'ptt_transport.dart';

enum PttConnectionState { connected, reconnecting, offline }

abstract class PttRecorder {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

abstract class PttAudioCodec {
  Future<Uint8List> encode(Uint8List pcmOrEncodedBytes);
  Future<Uint8List> decode(Uint8List pcmOrEncodedBytes);
}

abstract class PttPlayback {
  Future<void> play(Uint8List pcmOrEncodedBytes);
}

abstract class BriefingState {
  bool get isBriefingActive;
  Stream<bool> get onBriefingActiveChanged;
}

class PttService {
  static const channelBusyWindow = Duration(milliseconds: 350);
  static const _playbackPrebufferBytes = PttChunkSpec.batchBytes * 3;
  static const _maxQueuedPlaybackBytes = PttChunkSpec.batchBytes * 12;
  static const _playbackPrebufferTimeout = Duration(milliseconds: 400);
  static const _utteranceIdleReset = Duration(milliseconds: 600);
  static const _maxReconnectAttempts = 5;

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
      if (!active) _maybeDrainPlaybackQueue();
    });
    _connectionSubscription = _transport.onConnectionDown.listen((_) {
      _handleConnectionDown();
    });
  }

  final PttTransport _transport;
  final PttRecorder _recorder;
  final PttAudioCodec _codec;
  final PttPlayback _playback;
  final BriefingState _briefingState;
  final Queue<Uint8List> _playbackQueue = Queue<Uint8List>();
  final ValueNotifier<bool> channelBusy = ValueNotifier(false);
  final ValueNotifier<double> micLevel = ValueNotifier(0);
  final ValueNotifier<PttConnectionState> connectionState = ValueNotifier(
    PttConnectionState.offline,
  );

  StreamSubscription<Uint8List>? _incomingSubscription;
  StreamSubscription<bool>? _briefingSubscription;
  StreamSubscription<void>? _connectionSubscription;
  Future<void> _playbackDrain = Future<void>.value();
  Future<void>? _holdStarting;
  Timer? _busyTimer;
  Timer? _prebufferTimer;
  Timer? _utteranceTimer;
  String? _channelId;
  var _playbackPrebufferReady = false;
  var _reconnecting = false;
  var _connectEpoch = 0;
  var _disposed = false;

  Future<void> subscribe(String channelId) async {
    _connectEpoch += 1;
    final subscriptionEpoch = _connectEpoch;
    await _transport.subscribe(channelId);
    _channelId = channelId;
    _reconnecting = false;
    connectionState.value = PttConnectionState.connected;
    await _incomingSubscription?.cancel();
    _clearPlaybackQueue();
    _incomingSubscription = _transport.onChunk.listen((chunk) async {
      _markChannelBusy();
      final decoded = await _codec.decode(chunk);
      if (_disposed ||
          _connectEpoch != subscriptionEpoch ||
          _channelId != channelId ||
          decoded.length > _maxQueuedPlaybackBytes) {
        return;
      }
      while (_playbackQueue.isNotEmpty &&
          _queuedPlaybackBytes + decoded.length > _maxQueuedPlaybackBytes) {
        _playbackQueue.removeFirst();
      }
      _playbackQueue.add(decoded);
      _scheduleUtteranceReset();
      _maybeDrainPlaybackQueue();
    });
  }

  Future<void> unsubscribe() async {
    _connectEpoch += 1;
    _channelId = null;
    _reconnecting = false;
    connectionState.value = PttConnectionState.offline;
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    _clearChannelBusy();
    _clearPlaybackQueue();
    await _transport.disposeChannelOnly();
  }

  Future<void> startHold() async {
    final starting = _recorder.start();
    _holdStarting = starting.then<void>((_) {}, onError: (_) {});
    final stream = await starting;
    final pending = <int>[];
    try {
      await for (final chunk in stream) {
        _updateMicLevel(chunk);
        pending.addAll(chunk);
        while (pending.length >= PttChunkSpec.batchBytes) {
          final batch = Uint8List.fromList(
            pending.take(PttChunkSpec.batchBytes).toList(),
          );
          pending.removeRange(0, PttChunkSpec.batchBytes);
          await _sendRecordedChunkSafely(batch);
        }
      }
    } finally {
      if (pending.isNotEmpty) {
        await _sendRecordedChunkSafely(Uint8List.fromList(pending));
      }
    }
  }

  Future<void> stopHold() async {
    try {
      await _holdStarting;
    } catch (_) {}
    await _recorder.stop();
    micLevel.value = 0;
  }

  Future<void> _sendRecordedChunk(Uint8List chunk) async {
    final encoded = await _codec.encode(chunk);
    await _transport.sendChunk(encoded);
  }

  Future<void> _sendRecordedChunkSafely(Uint8List chunk) async {
    try {
      await _sendRecordedChunk(chunk);
    } catch (_) {
      micLevel.value = 0;
    }
  }

  void _updateMicLevel(Uint8List pcm16) {
    if (pcm16.length < 2) {
      micLevel.value = 0;
      return;
    }
    final data = ByteData.sublistView(pcm16);
    var sumSquares = 0.0;
    var samples = 0;
    for (var offset = 0; offset + 1 < pcm16.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      sumSquares += sample * sample;
      samples += 1;
    }
    final rms = math.sqrt(sumSquares / samples) / 32768;
    final perceived = math.pow(rms.clamp(0, 1), 0.6).toDouble();
    micLevel.value = math
        .max(perceived, micLevel.value * 0.8)
        .clamp(0, 1)
        .toDouble();
  }

  void _maybeDrainPlaybackQueue() {
    if (_briefingState.isBriefingActive) return;
    if (!_playbackPrebufferReady &&
        _queuedPlaybackBytes >= _playbackPrebufferBytes) {
      _releasePlaybackPrebuffer();
      return;
    }
    if (_playbackPrebufferReady) {
      unawaited(_drainPlaybackQueue());
    } else {
      _prebufferTimer ??= Timer(
        _playbackPrebufferTimeout,
        _releasePlaybackPrebuffer,
      );
    }
  }

  int get _queuedPlaybackBytes {
    var bytes = 0;
    for (final chunk in _playbackQueue) {
      bytes += chunk.length;
    }
    return bytes;
  }

  void _releasePlaybackPrebuffer() {
    if (_playbackPrebufferReady) return;
    _playbackPrebufferReady = true;
    _prebufferTimer?.cancel();
    _prebufferTimer = null;
    if (!_briefingState.isBriefingActive) {
      unawaited(_drainPlaybackQueue());
    }
  }

  Future<void> _drainPlaybackQueue() {
    if (!_playbackPrebufferReady) return Future<void>.value();
    _playbackDrain = _playbackDrain.then((_) async {
      while (!_briefingState.isBriefingActive && _playbackQueue.isNotEmpty) {
        await _playback.play(_playbackQueue.removeFirst());
      }
    });
    return _playbackDrain;
  }

  void _scheduleUtteranceReset() {
    _utteranceTimer?.cancel();
    _utteranceTimer = Timer(_utteranceIdleReset, _resetPlaybackPrebuffer);
  }

  void _resetPlaybackPrebuffer() {
    _prebufferTimer?.cancel();
    _prebufferTimer = null;
    _utteranceTimer?.cancel();
    _utteranceTimer = null;
    _playbackPrebufferReady = false;
  }

  void _clearPlaybackQueue() {
    _playbackQueue.clear();
    _resetPlaybackPrebuffer();
  }

  void _handleConnectionDown() {
    if (_disposed || _reconnecting) return;
    final channelId = _channelId;
    if (channelId == null) return;
    unawaited(_reconnect(channelId, _connectEpoch));
  }

  Future<void> _reconnect(String channelId, int epoch) async {
    _reconnecting = true;
    connectionState.value = PttConnectionState.reconnecting;
    for (var attempt = 0; attempt < _maxReconnectAttempts; attempt += 1) {
      await Future<void>.delayed(_reconnectDelay(attempt));
      if (_disposed || _connectEpoch != epoch || _channelId != channelId) {
        return;
      }
      try {
        await _transport.subscribe(channelId);
        if (_disposed || _connectEpoch != epoch || _channelId != channelId) {
          return;
        }
        _reconnecting = false;
        connectionState.value = PttConnectionState.connected;
        return;
      } catch (_) {}
    }
    if (!_disposed && _connectEpoch == epoch && _channelId == channelId) {
      _reconnecting = false;
      connectionState.value = PttConnectionState.offline;
    }
  }

  Duration _reconnectDelay(int attempt) {
    final seconds = switch (attempt) {
      0 => 1,
      1 => 2,
      2 => 4,
      _ => 8,
    };
    return Duration(seconds: seconds);
  }

  void _markChannelBusy() {
    channelBusy.value = true;
    _busyTimer?.cancel();
    _busyTimer = Timer(channelBusyWindow, () {
      channelBusy.value = false;
    });
  }

  void _clearChannelBusy() {
    _busyTimer?.cancel();
    _busyTimer = null;
    channelBusy.value = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    _connectEpoch += 1;
    await _incomingSubscription?.cancel();
    await _briefingSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _clearChannelBusy();
    _clearPlaybackQueue();
    await _recorder.stop();
    await _transport.dispose();
    channelBusy.dispose();
    micLevel.dispose();
    connectionState.dispose();
  }
}

class RecordPcmPttRecorder implements PttRecorder {
  RecordPcmPttRecorder({AudioRecorder? recorder})
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
        encoder: AudioEncoder.pcm16bits,
        sampleRate: PttChunkSpec.sampleRate,
        numChannels: PttChunkSpec.channels,
        streamBufferSize: PttChunkSpec.frameBytes,
        echoCancel: true,
        autoGain: true,
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
  Future<Uint8List> decode(Uint8List pcmOrEncodedBytes) async =>
      Uint8List.fromList(pcmOrEncodedBytes);
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
  var _streaming = false;

  @override
  Future<void> play(Uint8List pcmOrEncodedBytes) async {
    await _ensureStreamStarted();
    await _player.feedUint8FromStream(pcmOrEncodedBytes);
  }

  Future<void> _ensureStreamStarted() async {
    if (_streaming) return;
    await _ensureOpen();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: PttChunkSpec.channels,
      sampleRate: PttChunkSpec.sampleRate,
      bufferSize: PttChunkSpec.batchBytes,
    );
    _streaming = true;
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
    _streaming = false;
  }
}
