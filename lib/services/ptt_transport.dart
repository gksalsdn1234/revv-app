import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import 'supabase_service.dart';

abstract class PttTransport {
  Stream<Uint8List> get onChunk;

  Future<void> subscribe(String channelId);
  Future<void> sendChunk(Uint8List bytes);
  Future<void> disposeChannelOnly();
  Future<void> dispose();
}

class PttTransportException implements Exception {
  const PttTransportException(this.message);

  final String message;

  @override
  String toString() => 'PttTransportException: $message';
}

class RealtimePttTransport implements PttTransport {
  RealtimePttTransport({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  static const eventName = 'pcm16_chunk';

  final SupabaseService _supabase;
  final _chunks = StreamController<Uint8List>.broadcast();
  RealtimeChannel? _channel;

  @override
  Stream<Uint8List> get onChunk => _chunks.stream;

  @override
  Future<void> subscribe(String channelId) async {
    await disposeChannelOnly();
    final client = _supabase.client;
    if (!_supabase.isReady || client == null) {
      throw const PttTransportException('Supabase is not ready');
    }

    // private 채널은 realtime 소켓에 세션 토큰이 실려야 RLS 인가를 통과한다.
    // 익명 세션 토큰이 안 실리면 channelError로 구독이 거부된다.
    final token = client.auth.currentSession?.accessToken;
    if (token != null) {
      await client.realtime.setAuth(token);
    }

    final completer = Completer<void>();
    final channel = client.channel(
      'crew:$channelId',
      opts: const RealtimeChannelConfig(ack: true, private: true),
    );
    _channel = channel;

    channel
        .onBroadcast(
          event: eventName,
          callback: (payload) {
            final chunk = payload['chunk'];
            if (chunk is! String) return;
            try {
              _chunks.add(base64Decode(chunk));
            } catch (_) {
              // Malformed broadcast payloads are ignored; transport remains live.
            }
          },
        )
        .subscribe((status, error) {
          if (completer.isCompleted) return;
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              completer.complete();
            case RealtimeSubscribeStatus.channelError:
              completer.completeError(
                PttTransportException('Realtime authorization failed: $error'),
              );
            case RealtimeSubscribeStatus.closed:
              completer.completeError(
                const PttTransportException('Realtime channel closed'),
              );
            case RealtimeSubscribeStatus.timedOut:
              completer.completeError(
                const PttTransportException('Realtime subscription timed out'),
              );
          }
        });

    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw const PttTransportException('Realtime subscription timed out'),
    );
  }

  @override
  Future<void> sendChunk(Uint8List bytes) async {
    final channel = _channel;
    if (channel == null) {
      throw const PttTransportException('PTT channel is not subscribed');
    }

    final response = await channel.sendBroadcastMessage(
      event: eventName,
      payload: {
        'codec': PttChunkSpec.codec,
        'sampleRate': PttChunkSpec.sampleRate,
        'channels': PttChunkSpec.channels,
        'frameMs': PttChunkSpec.frameDuration.inMilliseconds,
        'chunk': base64Encode(bytes),
      },
    );
    if (response != ChannelResponse.ok) {
      throw PttTransportException('Realtime broadcast rejected: $response');
    }
  }

  @override
  Future<void> disposeChannelOnly() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  @override
  Future<void> dispose() async {
    await disposeChannelOnly();
    await _chunks.close();
  }
}

class PttChunkSpec {
  PttChunkSpec._();

  static const codec = 'pcm16';
  static const sampleRate = 16000;
  static const channels = 1;
  static const frameMilliseconds = 20;
  static const frameDuration = Duration(milliseconds: frameMilliseconds);
  static const bytesPerSecond = sampleRate * channels * 2;
  static const frameBytes = bytesPerSecond * frameMilliseconds ~/ 1000;
}
