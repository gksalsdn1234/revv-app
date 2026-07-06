import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/ptt_service.dart';
import 'package:revv_app/services/ptt_transport.dart';

void main() {
  test('sends encoded microphone chunks while PTT is held', () async {
    // Given: fake audio seams and a subscribed transport.
    final recorder = _FakeRecorder([
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
    ]);
    final codec = _OffsetCodec();
    final transport = _FakeTransport();
    final service = PttService(
      transport: transport,
      recorder: recorder,
      codec: codec,
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When: the driver holds and releases PTT.
    await service.startHold();
    await service.stopHold();
    await Future<void>.delayed(Duration.zero);

    // Then: chunks are encoded before transport send.
    expect(transport.sentChunks, [
      Uint8List.fromList([2]),
      Uint8List.fromList([3]),
    ]);
    expect(recorder.stopped, isTrue);
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
    transport.receive(Uint8List.fromList([8]));
    await Future<void>.delayed(Duration.zero);

    // Then: playback waits.
    expect(playback.playedChunks, isEmpty);

    // When: the briefing ends.
    briefing.active = false;
    await Future<void>.delayed(Duration.zero);

    // Then: queued walkie audio plays after decode.
    expect(playback.playedChunks, [
      Uint8List.fromList([7]),
    ]);
  });

  test('surfaces transport rejection for non-member sends', () async {
    // Given: transport rejects broadcasts through the same seam as RLS.
    final service = PttService(
      transport: _RejectingTransport(),
      recorder: _FakeRecorder([
        Uint8List.fromList([1]),
      ]),
      codec: _OffsetCodec(),
      playback: _FakePlayback(),
      briefingState: _FakeBriefingState(),
    );
    await service.subscribe('channel-1');

    // When / Then: hold start fails closed instead of swallowing the denial.
    await expectLater(
      service.startHold(),
      throwsA(isA<PttTransportException>()),
    );
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
    expect(player.streamBufferSize, PttChunkSpec.frameBytes);
    expect(player.fedChunks, [
      Uint8List.fromList([1, 0]),
      Uint8List.fromList([2, 0]),
    ]);

    await playback.dispose();
    expect(player.closeCalls, 1);
  });
}

class _FakeTransport implements PttTransport {
  final _chunks = StreamController<Uint8List>.broadcast();
  final sentChunks = <Uint8List>[];

  @override
  Stream<Uint8List> get onChunk => _chunks.stream;

  @override
  Future<void> subscribe(String channelId) async {}

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
  Future<void> dispose() => _chunks.close();
}

class _RejectingTransport extends _FakeTransport {
  @override
  Future<void> sendChunk(Uint8List bytes) async {
    throw const PttTransportException('broadcast rejected');
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
