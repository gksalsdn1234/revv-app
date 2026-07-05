import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/ptt_transport.dart';

void main() {
  test('round-trips chunks through the transport contract', () async {
    // Given: two member transports on the same volatile channel.
    final bus = _FakeRealtimeBus();
    final sender = _FakePttTransport(bus: bus, member: true);
    final receiver = _FakePttTransport(bus: bus, member: true);
    await sender.subscribe('channel-1');
    await receiver.subscribe('channel-1');

    // When: one member broadcasts an Opus chunk.
    final received = expectLater(
      receiver.onChunk,
      emits(Uint8List.fromList([1, 2, 3, 4])),
    );
    await sender.sendChunk(Uint8List.fromList([1, 2, 3, 4]));

    // Then: the chunk arrives as bytes and is not stored.
    await received;
    expect(bus.storedChunks, isEmpty);
  });

  test('rejects non-member send attempts fail-closed', () async {
    // Given: a transport that can connect but is not authorized to broadcast.
    final bus = _FakeRealtimeBus();
    final transport = _FakePttTransport(bus: bus, member: false);
    await transport.subscribe('channel-1');

    // When / Then: sending is rejected by the transport seam.
    expect(
      () => transport.sendChunk(Uint8List.fromList([9])),
      throwsA(isA<PttTransportException>()),
    );
    expect(bus.storedChunks, isEmpty);
  });
}

class _FakeRealtimeBus {
  final _controllers = <String, StreamController<Uint8List>>{};
  final storedChunks = <Uint8List>[];

  Stream<Uint8List> stream(String channelId) =>
      _controllers
          .putIfAbsent(channelId, () => StreamController<Uint8List>.broadcast())
          .stream;

  void send(String channelId, Uint8List chunk) {
    _controllers[channelId]?.add(Uint8List.fromList(chunk));
  }
}

class _FakePttTransport implements PttTransport {
  _FakePttTransport({required _FakeRealtimeBus bus, required bool member})
    : _bus = bus,
      _member = member;

  final _FakeRealtimeBus _bus;
  final bool _member;
  final _chunks = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  String? _channelId;

  @override
  Stream<Uint8List> get onChunk => _chunks.stream;

  @override
  Future<void> subscribe(String channelId) async {
    _channelId = channelId;
    _subscription = _bus.stream(channelId).listen(_chunks.add);
  }

  @override
  Future<void> sendChunk(Uint8List bytes) async {
    if (!_member) {
      throw const PttTransportException('broadcast rejected');
    }
    final channelId = _channelId;
    if (channelId == null) {
      throw const PttTransportException('not subscribed');
    }
    _bus.send(channelId, bytes);
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _chunks.close();
  }
}
