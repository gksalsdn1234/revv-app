import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_language.dart';
import 'package:revv_app/services/crew_channel_service.dart';
import 'package:supabase/supabase.dart';

void main() {
  test(
    'createChannel creates a channel, joins it, and returns the code',
    () async {
      final supabase = _FakeCrewSupabase();
      final service = CrewChannelService(supabase: supabase);

      final code = await service.createChannel(
        name: '  Sunday crew  ',
        displayName: '  Min  ',
      );

      expect(code, 'ABCD2345');
      expect(supabase.createdName, 'Sunday crew');
      expect(supabase.joinedCode, 'ABCD2345');
      expect(supabase.joinedDisplayName, 'Min');
      expect(service.channelId, 'channel-1');
      expect(service.displayName, 'Min');
    },
  );

  test('joinChannel calls the RPC and tracks only the display name', () async {
    final supabase = _FakeCrewSupabase();
    final service = CrewChannelService(supabase: supabase);

    await service.joinChannel(' abcd2345 ', displayName: ' Driver ');

    expect(supabase.joinedCode, 'ABCD2345');
    expect(supabase.joinedDisplayName, 'Driver');
    expect(supabase.subscriptions.single.trackedPayload, {
      'display_name': 'Driver',
    });
  });

  test('joinChannel rejects expired or invalid channel codes', () async {
    final supabase = _FakeCrewSupabase()
      ..joinError = const PostgrestException(
        message: 'invalid crew channel code',
        code: '22023',
      );
    final service = CrewChannelService(supabase: supabase);

    expect(
      () => service.joinChannel('ABCD2345', displayName: 'Min'),
      throwsA(
        isA<CrewChannelException>().having(
          (error) => error.kind,
          'kind',
          CrewChannelFailureKind.invalidOrExpiredCode,
        ),
      ),
    );
  });

  test('joinChannel maps rate limits to user copy', () async {
    final supabase = _FakeCrewSupabase()
      ..joinError = const PostgrestException(
        message: 'join rate limit exceeded',
        code: 'P0001',
      );
    final service = CrewChannelService(supabase: supabase);

    await expectLater(
      service.joinChannel('ABCD2345', displayName: 'Min'),
      throwsA(
        isA<CrewChannelException>()
            .having(
              (error) => error.kind,
              'kind',
              CrewChannelFailureKind.rateLimited,
            )
            .having(
              (error) => error.messageFor(AppLanguage.korean),
              'ko copy',
              '참여 시도가 너무 많아요. 잠시 후 다시 시도해 주세요.',
            )
            .having(
              (error) => error.messageFor(AppLanguage.english),
              'en copy',
              'Too many join attempts. Please wait a moment and try again.',
            )
            .having(
              (error) => error.messageFor(AppLanguage.french),
              'fr copy',
              'Trop de tentatives. Attendez un moment puis réessayez.',
            ),
      ),
    );
  });

  test('presence sync exposes online members by nickname only', () async {
    final supabase = _FakeCrewSupabase();
    final service = CrewChannelService(supabase: supabase);
    await service.joinChannel('ABCD2345', displayName: 'Min');

    supabase.subscriptions.single.setPresence([
      const (memberId: 'member-1', payload: {'display_name': 'Min'}),
      const (memberId: 'member-2', payload: {'display_name': 'Alex'}),
    ]);

    expect(service.onlineMembers.map((member) => member.displayName), [
      'Min',
      'Alex',
    ]);
  });

  test(
    'leaveChannel untracks, unsubscribes, deletes membership, and clears state',
    () async {
      final supabase = _FakeCrewSupabase();
      final service = CrewChannelService(supabase: supabase);
      await service.joinChannel('ABCD2345', displayName: 'Min');
      supabase.subscriptions.single.setPresence([
        const (memberId: 'member-1', payload: {'display_name': 'Min'}),
      ]);

      await service.leaveChannel();

      final subscription = supabase.subscriptions.single;
      expect(subscription.untracked, isTrue);
      expect(subscription.unsubscribed, isTrue);
      expect(supabase.deletedChannelId, 'channel-1');
      expect(supabase.deletedMemberId, 'member-1');
      expect(service.isJoined, isFalse);
      expect(service.onlineMembers, isEmpty);
    },
  );
}

class _FakeCrewSupabase implements CrewChannelSupabase {
  @override
  bool isReady = true;

  @override
  String? uid = 'member-1';

  Object? joinError;
  String? createdName;
  String? joinedCode;
  String? joinedDisplayName;
  String? deletedChannelId;
  String? deletedMemberId;
  final List<_FakePresenceSubscription> subscriptions = [];

  @override
  Future<Map<String, dynamic>> createChannelRow(String name) async {
    createdName = name;
    return {'id': 'channel-1', 'code': 'ABCD2345'};
  }

  @override
  Future<Map<String, dynamic>> joinCrewChannel(
    String code,
    String displayName,
  ) async {
    final error = joinError;
    if (error != null) throw error;
    joinedCode = code;
    joinedDisplayName = displayName;
    return {
      'channel_id': 'channel-1',
      'member_id': 'member-1',
      'display_name': displayName.isEmpty ? '크루원 1' : displayName,
    };
  }

  @override
  Future<void> deleteMember(String channelId, String memberId) async {
    deletedChannelId = channelId;
    deletedMemberId = memberId;
  }

  @override
  CrewPresenceSubscription openPresence(
    String channelId, {
    required String presenceKey,
  }) {
    final subscription = _FakePresenceSubscription();
    subscriptions.add(subscription);
    return subscription;
  }
}

class _FakePresenceSubscription implements CrewPresenceSubscription {
  VoidCallback? _onSync;
  List<CrewPresenceRecord> _presence = const [];
  Map<String, dynamic>? trackedPayload;
  bool untracked = false;
  bool unsubscribed = false;

  @override
  void onSync(VoidCallback callback) {
    _onSync = callback;
  }

  @override
  Future<void> subscribe() async {}

  @override
  Future<void> track(Map<String, dynamic> payload) async {
    trackedPayload = Map<String, dynamic>.from(payload);
  }

  @override
  Future<void> untrack() async {
    untracked = true;
  }

  @override
  Future<void> unsubscribe() async {
    unsubscribed = true;
  }

  @override
  List<CrewPresenceRecord> presenceState() => _presence;

  void setPresence(List<CrewPresenceRecord> presence) {
    _presence = presence;
    _onSync?.call();
  }
}
