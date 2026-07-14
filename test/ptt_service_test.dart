import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/ptt_service.dart';
import 'package:revv_app/services/ptt_transport.dart';

void main() {
  test(
    'batches microphone frames and flushes the final partial batch',
    () async {
      // Given: seven 20ms PCM frames and a subscribed transport.
      final recorder = _FakeRecorder([
        for (var i = 0; i < 7; i += 1) _frame(i),
      ]);
      final transport = _FakeTransport();
      final service = PttService(
        transport: transport,
        recorder: recorder,
        codec: const PassthroughPttAudioCodec(),
        playback: _FakePlayback(),
        briefingState: _FakeBriefingState(),
      );
      await service.subscribe('channel-1');

      // When: the driver holds and releases PTT.
      await service.startHold();
      await service.stopHold();
      await Future<void>.delayed(Duration.zero);

      // Then: transport sees one 100ms batch and one flushed 40ms tail.
      expect(transport.sentChunks.length, 2);
      expect(transport.sentChunks[0].length, PttChunkSpec.batchBytes);
      expect(transport.sentChunks[1].length, PttChunkSpec.frameBytes * 2);
      expect(recorder.stopped, isTrue);
    },
  );

  test('updates micLevel from PCM frames and resets after stopHold', () async {
    // Given: silence followed by a loud PCM16 frame.
    final recorder = _FakeRecorder([_pcm16Frame(0), _pcm16Frame(32767)]);
    final service = PttService(
      transport: _FakeTransport(),
      recorder: recorder,
      codec: const PassthroughPttAudioCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );

    // When: the driver holds and releases PTT.
    await service.startHold();

    // Then: the transmitted PCM drove a visible microphone level.
    expect(service.micLevel.value, greaterThan(0.8));

    await service.stopHold();
    expect(service.micLevel.value, 0);
  });

  test('queues incoming walkie audio until briefing finishes', () async {
    // Given: a briefing is currently active.
    final transport = _FakeTransport();
    final playback = _FakePlayback();
    final briefing = _FakeBriefingState()..active = true;
    final service = PttService(
      transport: transport,
      recorder: _FakeRecorder(const []),
      codec: _OffsetCodec(),
      playback: playback,
      briefingState: briefing,
    );
    await service.subscribe('channel-1');

    // When: a chunk arrives during the briefing.
    transport.receive(_batch(8));
    await Future<void>.delayed(Duration.zero);

    // Then: playback waits.
    expect(playback.playedChunks, isEmpty);

    // When: the briefing ends.
    briefing.active = false;
    await Future<void>.delayed(Duration.zero);

    // Then: queued walkie audio still waits for the jitter prebuffer.
    expect(playback.playedChunks, isEmpty);

    // When: the prebuffer fills.
    transport.receive(_batch(9));
    transport.receive(_batch(10));
    await Future<void>.delayed(Duration.zero);

    // Then: queued walkie audio plays after decode.
    expect(playback.playedChunks.length, 3);
    expect(playback.playedChunks.first.first, 7);
  });

  test('prebuffers playback until three batches arrive', () async {
    // Given: a subscribed service listening for walkie audio.
    final transport = _FakeTransport();
    final playback = _FakePlayback();
    final service = PttService(
      transport: transport,
      recorder: _FakeRecorder(const []),
      codec: const PassthroughPttAudioCodec(),
      playback: playback,
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When: the first batch arrives.
    transport.receive(_batch(1));
    await Future<void>.delayed(Duration.zero);

    // Then: playback waits for jitter protection.
    expect(playback.playedChunks, isEmpty);

    // When: three batches are buffered.
    transport.receive(_batch(2));
    transport.receive(_batch(3));
    await Future<void>.delayed(Duration.zero);

    // Then: playback starts.
    expect(playback.playedChunks.length, 3);
    await service.dispose();
  });

  test(
    'bounds queued incoming audio while a briefing blocks playback',
    () async {
      final transport = _FakeTransport();
      final playback = _FakePlayback();
      final briefing = _FakeBriefingState()..active = true;
      final service = PttService(
        transport: transport,
        recorder: _FakeRecorder(const []),
        codec: const PassthroughPttAudioCodec(),
        playback: playback,
        briefingState: briefing,
      );
      await service.subscribe('channel-1');

      for (var seed = 0; seed < 20; seed += 1) {
        transport.receive(_batch(seed));
      }
      await Future<void>.delayed(Duration.zero);
      expect(playback.playedChunks, isEmpty);

      briefing.active = false;
      await Future<void>.delayed(Duration.zero);

      expect(playback.playedChunks.length, 12);
      expect(playback.playedChunks.first.first, 8);
      expect(playback.playedChunks.last.first, 19);
      await service.dispose();
    },
  );

  test('marks the channel busy briefly after an incoming chunk', () async {
    // Given: a subscribed service listening for remote walkie audio.
    final transport = _FakeTransport();
    final service = PttService(
      transport: transport,
      recorder: _FakeRecorder(const []),
      codec: _OffsetCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When: a remote chunk arrives.
    transport.receive(_batch(8));
    await Future<void>.delayed(Duration.zero);

    // Then: the half-duplex guard is active, then expires.
    expect(service.channelBusy.value, isTrue);

    await Future<void>.delayed(
      PttService.channelBusyWindow + const Duration(milliseconds: 10),
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.channelBusy.value, isFalse);
  });

  test('stopHold waits for recorder start before stopping', () async {
    // Given: recorder.start has been called but has not completed yet.
    final recorder = _DelayedStartRecorder();
    final service = PttService(
      transport: _FakeTransport(),
      recorder: recorder,
      codec: _OffsetCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );

    final hold = service.startHold();
    await Future<void>.delayed(Duration.zero);

    // When: release arrives before the microphone stream is ready.
    final stop = service.stopHold();
    await Future<void>.delayed(Duration.zero);
    expect(recorder.stopAfterStart, isNull);

    recorder.completeStart();
    await stop;
    await hold;

    // Then: recorder.stop ran after start completed.
    expect(recorder.stopAfterStart, isTrue);
  });

  test('continues the send loop when a broadcast send fails', () async {
    // Given: transport rejects broadcasts through the same seam as RLS.
    final transport = _RejectingTransport();
    final service = PttService(
      transport: transport,
      recorder: _FakeRecorder([for (var i = 0; i < 7; i += 1) _frame(i)]),
      codec: const PassthroughPttAudioCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When: broadcast sends fail while holding PTT.
    await service.startHold();

    // Then: both batches were attempted and the loop did not throw.
    expect(transport.sendAttempts, 2);
  });

  testWidgets('reconnects on connectionDown and returns to connected', (
    tester,
  ) async {
    // Given: a subscribed service whose next reconnect succeeds.
    final transport = _ReconnectTransport();
    final service = PttService(
      transport: transport,
      recorder: _FakeRecorder(const []),
      codec: const PassthroughPttAudioCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When: the transport reports a dropped channel.
    transport.connectionDown();
    await tester.pump();

    // Then: state enters reconnecting, retries after backoff, and recovers.
    expect(service.connectionState.value, PttConnectionState.reconnecting);
    await tester.pump(const Duration(seconds: 1));
    expect(transport.subscribedChannels, ['channel-1', 'channel-1']);
    expect(service.connectionState.value, PttConnectionState.connected);
  });

  testWidgets('goes offline after five failed reconnect attempts', (
    tester,
  ) async {
    // Given: a subscribed service whose reconnect attempts fail.
    final transport = _ReconnectTransport(failuresBeforeSuccess: 99);
    final service = PttService(
      transport: transport,
      recorder: _FakeRecorder(const []),
      codec: const PassthroughPttAudioCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When: all retry backoffs are exhausted.
    transport.connectionDown();
    await tester.pump();
    await tester.pump(const Duration(seconds: 23));

    // Then: the service stops retrying and exposes offline.
    expect(transport.subscribedChannels.length, 6);
    expect(service.connectionState.value, PttConnectionState.offline);
  });

  test('feeds PCM chunks into one flutter sound stream', () async {
    // Given: a playback adapter backed by a fake FlutterSound player.
    final player = _FakeFlutterSoundPlayer();
    final playback = FlutterSoundPttPlayback(player: player);

    // When: two received chunks are played.
    await playback.play(Uint8List.fromList([1, 0]));
    await playback.play(Uint8List.fromList([2, 0]));

    // Then: the stream player is opened once and chunks are fed continuously.
    expect(player.openCalls, 1);
    expect(player.startStreamCalls, 1);
    expect(player.startPlayerCalls, 0);
    expect(player.streamCodec, Codec.pcm16);
    expect(player.streamInterleaved, isTrue);
    expect(player.streamChannels, PttChunkSpec.channels);
    expect(player.streamSampleRate, PttChunkSpec.sampleRate);
    expect(player.streamBufferSize, PttChunkSpec.batchBytes);
    expect(player.fedChunks, [
      Uint8List.fromList([1, 0]),
      Uint8List.fromList([2, 0]),
    ]);

    await playback.dispose();
    expect(player.closeCalls, 1);
  });
}

Uint8List _frame(int seed) {
  return Uint8List(PttChunkSpec.frameBytes)
    ..fillRange(0, PttChunkSpec.frameBytes, seed);
}

Uint8List _pcm16Frame(int sample) {
  final bytes = Uint8List(PttChunkSpec.frameBytes);
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset < bytes.length; offset += 2) {
    data.setInt16(offset, sample, Endian.little);
  }
  return bytes;
}

Uint8List _batch(int seed) {
  return Uint8List(PttChunkSpec.batchBytes)
    ..fillRange(0, PttChunkSpec.batchBytes, seed);
}

class _FakeTransport implements PttTransport {
  final _chunks = StreamController<Uint8List>.broadcast();
  final _connectionDown = StreamController<void>.broadcast();
  final sentChunks = <Uint8List>[];
  final subscribedChannels = <String>[];

  @override
  Stream<Uint8List> get onChunk => _chunks.stream;

  @override
  Stream<void> get onConnectionDown => _connectionDown.stream;

  @override
  Future<void> subscribe(String channelId) async {
    subscribedChannels.add(channelId);
  }

  @override
  Future<void> sendChunk(Uint8List bytes) async {
    sentChunks.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> disposeChannelOnly() async {}

  void receive(Uint8List bytes) {
    _chunks.add(bytes);
  }

  @override
  Future<void> dispose() async {
    await _chunks.close();
    await _connectionDown.close();
  }
}

class _RejectingTransport extends _FakeTransport {
  var sendAttempts = 0;

  @override
  Future<void> sendChunk(Uint8List bytes) async {
    sendAttempts += 1;
    throw const PttTransportException('broadcast rejected');
  }
}

class _ReconnectTransport extends _FakeTransport {
  _ReconnectTransport({this.failuresBeforeSuccess = 0});

  final int failuresBeforeSuccess;
  var _reconnectAttempts = 0;

  @override
  Future<void> subscribe(String channelId) async {
    subscribedChannels.add(channelId);
    if (subscribedChannels.length > 1 &&
        _reconnectAttempts < failuresBeforeSuccess) {
      _reconnectAttempts += 1;
      throw const PttTransportException('reconnect failed');
    }
  }

  void connectionDown() {
    _connectionDown.add(null);
  }
}

class _FakeRecorder implements PttRecorder {
  _FakeRecorder(this._chunks);

  final List<Uint8List> _chunks;
  bool stopped = false;

  @override
  Future<Stream<Uint8List>> start() async =>
      Stream<Uint8List>.fromIterable(_chunks.map(Uint8List.fromList));

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

class _DelayedStartRecorder implements PttRecorder {
  final _start = Completer<Stream<Uint8List>>();
  var started = false;
  bool? stopAfterStart;

  @override
  Future<Stream<Uint8List>> start() async {
    final stream = await _start.future;
    started = true;
    return stream;
  }

  void completeStart() {
    _start.complete(const Stream<Uint8List>.empty());
  }

  @override
  Future<void> stop() async {
    stopAfterStart = started;
  }
}

class _OffsetCodec implements PttAudioCodec {
  @override
  Future<Uint8List> encode(Uint8List pcmOrEncodedBytes) async =>
      Uint8List.fromList(pcmOrEncodedBytes.map((byte) => byte + 1).toList());

  @override
  Future<Uint8List> decode(Uint8List pcmOrEncodedBytes) async =>
      Uint8List.fromList(pcmOrEncodedBytes.map((byte) => byte - 1).toList());
}

class _FakePlayback implements PttPlayback {
  final playedChunks = <Uint8List>[];

  @override
  Future<void> play(Uint8List pcmOrEncodedBytes) async {
    playedChunks.add(Uint8List.fromList(pcmOrEncodedBytes));
  }
}

class _FakeFlutterSoundPlayer extends FlutterSoundPlayer {
  int openCalls = 0;
  int closeCalls = 0;
  int startStreamCalls = 0;
  int startPlayerCalls = 0;
  Codec? streamCodec;
  bool? streamInterleaved;
  int? streamChannels;
  int? streamSampleRate;
  int? streamBufferSize;
  final fedChunks = <Uint8List>[];

  @override
  Future<FlutterSoundPlayer?> openPlayer({bool isBGService = false}) async {
    openCalls += 1;
    return this;
  }

  @override
  Future<void> startPlayerFromStream({
    required Codec codec,
    required bool interleaved,
    required int numChannels,
    required int sampleRate,
    required int bufferSize,
    TWhenFinished? onBufferUnderflow,
  }) async {
    startStreamCalls += 1;
    streamCodec = codec;
    streamInterleaved = interleaved;
    streamChannels = numChannels;
    streamSampleRate = sampleRate;
    streamBufferSize = bufferSize;
  }

  @override
  Future<int> feedUint8FromStream(Uint8List buffer) async {
    fedChunks.add(Uint8List.fromList(buffer));
    return buffer.length;
  }

  @override
  Future<Duration?> startPlayer({
    Codec codec = Codec.aacADTS,
    String? fromURI,
    Uint8List? fromDataBuffer,
    int sampleRate = 16000,
    int numChannels = 1,
    TWhenFinished? whenFinished,
  }) async {
    startPlayerCalls += 1;
    return Duration.zero;
  }

  @override
  Future<void> closePlayer() async {
    closeCalls += 1;
  }
}

class _FakeBriefingState implements BriefingState {
  final _changes = StreamController<bool>.broadcast();
  var _active = false;

  @override
  bool get isBriefingActive => _active;

  set active(bool value) {
    _active = value;
    _changes.add(value);
  }

  @override
  Stream<bool> get onBriefingActiveChanged => _changes.stream;
}
