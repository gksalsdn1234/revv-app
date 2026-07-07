import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/labs/walkie/walkie_ptt_controller.dart';
import 'package:revv_app/services/ptt_service.dart';
import 'package:revv_app/services/ptt_transport.dart';

void main() {
  test('connect subscribes once for the same channel', () async {
    final transport = _FakeTransport();
    final controller = PttServiceWalkieController(_service(transport));

    await controller.connect('channel-1');
    await controller.connect('channel-1');

    expect(transport.subscribedChannels, ['channel-1']);
  });

  test('connect shares the in-flight subscribe for the same channel', () async {
    final transport = _BlockingTransport();
    final controller = PttServiceWalkieController(_service(transport));

    final first = controller.connect('channel-1');
    final second = controller.connect('channel-1');
    await Future<void>.delayed(Duration.zero);

    expect(transport.subscribedChannels, ['channel-1']);

    transport.completeSubscribe();
    await Future.wait([first, second]);
  });

  test('startTalking reuses an auto-connect already in progress', () async {
    final transport = _BlockingTransport();
    final recorder = _FakeRecorder(const []);
    final controller = PttServiceWalkieController(
      _service(transport, recorder: recorder),
    );

    final connecting = controller.connect('channel-1');
    final talking = controller.startTalking('channel-1');
    await Future<void>.delayed(Duration.zero);

    expect(transport.subscribedChannels, ['channel-1']);

    transport.completeSubscribe();
    await Future.wait([connecting, talking]);
    expect(recorder.startCount, 1);
  });

  test('startTalking connects before starting hold', () async {
    final transport = _FakeTransport();
    final recorder = _FakeRecorder([
      Uint8List.fromList([1]),
    ]);
    final controller = PttServiceWalkieController(
      _service(transport, recorder: recorder),
    );

    await controller.startTalking('channel-1');

    expect(transport.subscribedChannels, ['channel-1']);
    expect(recorder.startCount, 1);
  });

  test('disconnect allows a later channel to resubscribe', () async {
    final transport = _FakeTransport();
    final controller = PttServiceWalkieController(_service(transport));

    await controller.connect('channel-1');
    await controller.disconnect();
    await controller.connect('channel-2');

    expect(transport.subscribedChannels, ['channel-1', 'channel-2']);
    expect(transport.channelDisposeCount, 1);
  });
}

PttService _service(_FakeTransport transport, {_FakeRecorder? recorder}) {
  return PttService(
    transport: transport,
    recorder: recorder ?? _FakeRecorder(const []),
    codec: const PassthroughPttAudioCodec(),
    playback: _FakePlayback(),
    briefingState: const IdleBriefingState(),
  );
}

class _FakeTransport implements PttTransport {
  final _chunks = StreamController<Uint8List>.broadcast();
  final _connectionDown = StreamController<void>.broadcast();
  final subscribedChannels = <String>[];
  var channelDisposeCount = 0;

  @override
  Stream<Uint8List> get onChunk => _chunks.stream;

  @override
  Stream<void> get onConnectionDown => _connectionDown.stream;

  @override
  Future<void> subscribe(String channelId) async {
    subscribedChannels.add(channelId);
  }

  @override
  Future<void> sendChunk(Uint8List bytes) async {}

  @override
  Future<void> disposeChannelOnly() async {
    channelDisposeCount += 1;
  }

  @override
  Future<void> dispose() async {
    await _chunks.close();
    await _connectionDown.close();
  }
}

class _BlockingTransport extends _FakeTransport {
  final _subscribeReady = Completer<void>();

  @override
  Future<void> subscribe(String channelId) async {
    subscribedChannels.add(channelId);
    await _subscribeReady.future;
  }

  void completeSubscribe() {
    if (!_subscribeReady.isCompleted) {
      _subscribeReady.complete();
    }
  }
}

class _FakeRecorder implements PttRecorder {
  _FakeRecorder(this._chunks);

  final List<Uint8List> _chunks;
  var startCount = 0;

  @override
  Future<Stream<Uint8List>> start() async {
    startCount += 1;
    return Stream<Uint8List>.fromIterable(_chunks.map(Uint8List.fromList));
  }

  @override
  Future<void> stop() async {}
}

class _FakePlayback implements PttPlayback {
  @override
  Future<void> play(Uint8List pcmOrEncodedBytes) async {}
}
