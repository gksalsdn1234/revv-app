import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../core/app_language.dart';
import '../core/supabase_tables.dart';
import '../ui/app_copy.dart';
import 'supabase_service.dart';

enum CrewChannelFailureKind {
  cloudUnavailable,
  invalidOrExpiredCode,
  rateLimited,
  subscriptionFailed,
  unknown,
}

typedef CrewChannelOnlineMember = ({String memberId, String displayName});

typedef CrewPresenceRecord = ({String memberId, Map<String, dynamic> payload});

class CrewChannelException implements Exception {
  const CrewChannelException(this.kind, {String? detail}) : _detail = detail;

  final CrewChannelFailureKind kind;
  final String? _detail;

  String messageFor(AppLanguage language) {
    return switch (kind) {
      CrewChannelFailureKind.cloudUnavailable => AppCopy.t(
        language,
        ko: '클라우드 연결 후 크루 채널을 사용할 수 있어요.',
        en: 'Crew channels need cloud connection.',
        fr: 'Les canaux de groupe nécessitent la connexion cloud.',
      ),
      CrewChannelFailureKind.invalidOrExpiredCode => AppCopy.t(
        language,
        ko: '참여 코드가 만료되었거나 유효하지 않아요.',
        en: 'This crew code has expired or is not valid.',
        fr: 'Ce code de groupe a expiré ou n’est pas valide.',
      ),
      CrewChannelFailureKind.rateLimited => AppCopy.t(
        language,
        ko: '참여 시도가 너무 많아요. 잠시 후 다시 시도해 주세요.',
        en: 'Too many join attempts. Please wait a moment and try again.',
        fr: 'Trop de tentatives. Attendez un moment puis réessayez.',
      ),
      CrewChannelFailureKind.subscriptionFailed => AppCopy.t(
        language,
        ko: '크루 온라인 상태 연결에 실패했어요.',
        en: 'Could not connect crew online status.',
        fr: 'Impossible de connecter le statut en ligne du groupe.',
      ),
      CrewChannelFailureKind.unknown => AppCopy.t(
        language,
        ko: '크루 채널 작업에 실패했어요.',
        en: 'Crew channel action failed.',
        fr: 'L’action du canal de groupe a échoué.',
      ),
    };
  }

  @override
  String toString() => _detail == null
      ? 'CrewChannelException($kind)'
      : 'CrewChannelException($kind, $_detail)';
}

abstract class CrewPresenceSubscription {
  void onSync(VoidCallback callback);
  Future<void> subscribe();
  Future<void> track(Map<String, dynamic> payload);
  Future<void> untrack();
  Future<void> unsubscribe();
  List<CrewPresenceRecord> presenceState();
}

abstract class CrewChannelSupabase {
  bool get isReady;
  String? get uid;

  Future<Map<String, dynamic>> createChannelRow(String name);
  Future<Map<String, dynamic>> joinCrewChannel(String code, String displayName);
  Future<void> deleteMember(String channelId, String memberId);
  CrewPresenceSubscription openPresence(
    String channelId, {
    required String presenceKey,
  });
}

class CrewChannelService extends ChangeNotifier {
  CrewChannelService({CrewChannelSupabase? supabase})
    : _supabase = supabase ?? SupabaseCrewChannelSupabase();

  final CrewChannelSupabase _supabase;
  CrewPresenceSubscription? _presence;
  String? _channelId;
  String? _memberId;
  String? _code;
  String? _displayName;
  List<CrewChannelOnlineMember> _onlineMembers = const [];

  String? get channelId => _channelId;
  String? get code => _code;
  String? get displayName => _displayName;
  List<CrewChannelOnlineMember> get onlineMembers => _onlineMembers;
  bool get isJoined => _channelId != null;

  Future<String> createChannel({
    required String name,
    String displayName = '',
  }) async {
    _requireReady();
    try {
      final row = await _supabase.createChannelRow(name.trim());
      final createdCode = _readString(row, 'code');
      await joinChannel(createdCode, displayName: displayName);
      return createdCode;
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> joinChannel(String code, {String displayName = ''}) async {
    _requireReady();
    try {
      await leaveChannel();
      final normalizedCode = code.trim().toUpperCase();
      final row = await _supabase.joinCrewChannel(
        normalizedCode,
        _normalizeDisplayName(displayName),
      );
      _channelId = _readString(row, 'channel_id');
      _memberId = _readString(row, 'member_id');
      _displayName = _readString(row, 'display_name');
      _code = normalizedCode;
      await _subscribePresence();
      notifyListeners();
    } catch (error) {
      final mapped = _mapError(error);
      notifyListeners();
      throw mapped;
    }
  }

  Future<void> leaveChannel() async {
    final channelId = _channelId;
    final memberId = _memberId;
    final presence = _presence;
    _presence = null;
    _channelId = null;
    _memberId = null;
    _code = null;
    _displayName = null;
    _onlineMembers = const [];

    if (presence != null) {
      await presence.untrack();
      await presence.unsubscribe();
    }
    if (channelId != null && memberId != null) {
      await _supabase.deleteMember(channelId, memberId);
    }
    notifyListeners();
  }

  Future<void> _subscribePresence() async {
    final channelId = _channelId;
    final memberId = _memberId;
    if (channelId == null || memberId == null) return;
    final presence = _supabase.openPresence(channelId, presenceKey: memberId);
    _presence = presence;
    presence.onSync(_syncPresence);
    await presence.subscribe();
    await presence.track({'display_name': _displayName ?? ''});
    _syncPresence();
  }

  void _syncPresence() {
    final presence = _presence;
    if (presence == null) return;
    final members = <String, CrewChannelOnlineMember>{};
    for (final record in presence.presenceState()) {
      final displayName = record.payload['display_name']?.toString().trim();
      if (displayName == null || displayName.isEmpty) continue;
      members[record.memberId] = (
        memberId: record.memberId,
        displayName: displayName,
      );
    }
    _onlineMembers = List.unmodifiable(members.values);
    notifyListeners();
  }

  void _requireReady() {
    if (!_supabase.isReady || _supabase.uid == null) {
      throw const CrewChannelException(CrewChannelFailureKind.cloudUnavailable);
    }
  }

  static String _normalizeDisplayName(String value) {
    final trimmed = value.trim();
    return trimmed.length <= 24 ? trimmed : trimmed.substring(0, 24);
  }

  static String _readString(Map<String, dynamic> row, String key) {
    final value = row[key]?.toString();
    if (value == null || value.isEmpty) {
      throw CrewChannelException(
        CrewChannelFailureKind.unknown,
        detail: 'missing $key',
      );
    }
    return value;
  }

  static CrewChannelException _mapError(Object error) {
    if (error is CrewChannelException) return error;
    final message = error is PostgrestException
        ? error.message
        : error.toString();
    final code = error is PostgrestException ? error.code : null;
    final lower = message.toLowerCase();
    if (lower.contains('join rate limit exceeded')) {
      return CrewChannelException(
        CrewChannelFailureKind.rateLimited,
        detail: message,
      );
    }
    if (code == '22023' || lower.contains('invalid crew channel code')) {
      return CrewChannelException(
        CrewChannelFailureKind.invalidOrExpiredCode,
        detail: message,
      );
    }
    if (lower.contains('authentication required')) {
      return CrewChannelException(
        CrewChannelFailureKind.cloudUnavailable,
        detail: message,
      );
    }
    return CrewChannelException(
      CrewChannelFailureKind.unknown,
      detail: message,
    );
  }
}

class SupabaseCrewChannelSupabase implements CrewChannelSupabase {
  SupabaseCrewChannelSupabase({SupabaseService? service})
    : _service = service ?? SupabaseService();

  final SupabaseService _service;

  @override
  bool get isReady => _service.isReady && _service.client != null;

  @override
  String? get uid => _service.uid;

  SupabaseClient get _client {
    final client = _service.client;
    if (client == null) {
      throw const CrewChannelException(CrewChannelFailureKind.cloudUnavailable);
    }
    return client;
  }

  @override
  Future<Map<String, dynamic>> createChannelRow(String name) async {
    // owner_id는 서버(create_crew_channel RPC)가 auth.uid()로 채운다 —
    // 클라이언트 uid나 RLS insert WITH CHECK에 의존하지 않는다.
    final row = await _client.rpc(
      'create_crew_channel',
      params: {'name_input': name},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> joinCrewChannel(
    String code,
    String displayName,
  ) async {
    final row = await _client.rpc(
      'join_crew_channel',
      params: {'code_input': code, 'display_name_input': displayName},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<void> deleteMember(String channelId, String memberId) async {
    await _client
        .from(SupabaseTables.crewChannelMembers)
        .delete()
        .eq('channel_id', channelId)
        .eq('member_id', memberId);
  }

  @override
  CrewPresenceSubscription openPresence(
    String channelId, {
    required String presenceKey,
  }) {
    final client = _client;
    final channel = client.channel(
      'crew:$channelId',
      opts: RealtimeChannelConfig(key: presenceKey, private: true),
    );
    return SupabaseCrewPresenceSubscription(channel, client: client);
  }
}

class SupabaseCrewPresenceSubscription implements CrewPresenceSubscription {
  SupabaseCrewPresenceSubscription(
    this._channel, {
    required SupabaseClient client,
  }) : _client = client;

  final RealtimeChannel _channel;
  final SupabaseClient _client;

  @override
  void onSync(VoidCallback callback) {
    _channel.onPresenceSync((_) => callback());
    _channel.onPresenceJoin((_) => callback());
    _channel.onPresenceLeave((_) => callback());
  }

  @override
  Future<void> subscribe() async {
    final token = _client.auth.currentSession?.accessToken;
    if (token != null) {
      await _client.realtime.setAuth(token);
    }

    final completer = Completer<void>();
    _channel.subscribe((status, error) {
      if (completer.isCompleted) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          completer.complete();
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.closed:
        case RealtimeSubscribeStatus.timedOut:
          completer.completeError(
            CrewChannelException(
              CrewChannelFailureKind.subscriptionFailed,
              detail: error?.toString() ?? status.name,
            ),
          );
      }
    });
    await completer.future;
  }

  @override
  Future<void> track(Map<String, dynamic> payload) => _channel.track(payload);

  @override
  Future<void> untrack() => _channel.untrack();

  @override
  Future<void> unsubscribe() => _channel.unsubscribe().then((_) {});

  @override
  List<CrewPresenceRecord> presenceState() {
    return [
      for (final state in _channel.presenceState())
        for (final presence in state.presences)
          (memberId: state.key, payload: presence.payload),
    ];
  }
}
