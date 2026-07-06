import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_language.dart';
import '../../services/crew_channel_service.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../ui/app_copy.dart';
import 'walkie_ptt_controller.dart';

export 'walkie_ptt_controller.dart' show WalkiePttController;

class WalkieLabScreen extends StatefulWidget {
  const WalkieLabScreen({
    super.key,
    required this.crewChannelService,
    required this.pttController,
    required this.language,
  });

  factory WalkieLabScreen.production({required AppLanguage language}) {
    return WalkieLabScreen(
      crewChannelService: CrewChannelService(),
      pttController: PttServiceWalkieController.production(),
      language: language,
    );
  }

  final CrewChannelService crewChannelService;
  final WalkiePttController pttController;
  final AppLanguage language;

  @override
  State<WalkieLabScreen> createState() => _WalkieLabScreenState();
}

class _WalkieLabScreenState extends State<WalkieLabScreen> {
  final _codeController = TextEditingController();
  final _roomController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;
  bool _talking = false;
  String? _status;
  String? _connectedChannelId;

  CrewChannelService get _crew => widget.crewChannelService;
  AppLanguage get _language => widget.language;

  @override
  void initState() {
    super.initState();
    _crew.addListener(_onCrewChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWalkieConnection();
    });
  }

  @override
  void dispose() {
    _crew.removeListener(_onCrewChanged);
    _codeController.dispose();
    _roomController.dispose();
    _nameController.dispose();
    // pttController/crew는 공유 인스턴스 — 소유자(Provider)가 정리한다.
    super.dispose();
  }

  void _onCrewChanged() {
    if (!mounted) return;
    setState(() {});
    _syncWalkieConnection();
  }

  void _syncWalkieConnection() {
    final channelId = _crew.channelId;
    if (_crew.isJoined && channelId != null) {
      if (_connectedChannelId == channelId) return;
      _connectedChannelId = channelId;
      unawaited(
        widget.pttController.connect(channelId).catchError((Object error) {
          if (!mounted) return;
          _connectedChannelId = null;
          setState(() {
            _status =
                '${_copy(ko: '무전 수신 연결 실패', en: 'Voice receive failed', fr: 'Réception échouée')}: $error';
          });
        }),
      );
    } else if (_connectedChannelId != null) {
      _connectedChannelId = null;
      unawaited(widget.pttController.disconnect().catchError((_) {}));
    }
  }

  Future<void> _createRoom() async {
    await _runAction(() async {
      final code = await _crew.createChannel(
        name: _roomController.text,
        displayName: _nameController.text,
      );
      _codeController.text = code;
      _status = _copy(
        ko: '방을 만들고 참여했어요.',
        en: 'Room created and joined.',
        fr: 'Salon créé et rejoint.',
      );
    });
  }

  Future<void> _joinRoom() async {
    await _runAction(() async {
      await _crew.joinChannel(
        _codeController.text,
        displayName: _nameController.text,
      );
      _status = _copy(
        ko: '방에 참여했어요.',
        en: 'Room joined.',
        fr: 'Salon rejoint.',
      );
    });
  }

  Future<void> _leaveRoom() async {
    await _stopTalking();
    await _runAction(() async {
      await _crew.leaveChannel();
      _status = _copy(
        ko: '방에서 나왔어요.',
        en: 'Left the room.',
        fr: 'Salon quitté.',
      );
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } on CrewChannelException catch (error) {
      _status = error.messageFor(_language);
    } catch (_) {
      _status = _copy(
        ko: '작업을 완료하지 못했어요.',
        en: 'Could not finish that action.',
        fr: 'Action non terminée.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startTalking() {
    final channelId = _crew.channelId;
    if (!_crew.isJoined || channelId == null) return;
    setState(() => _talking = true);
    unawaited(
      widget.pttController
          .startTalking(channelId)
          .catchError((Object error) {
            if (!mounted) return;
            setState(() {
              // 랩 진단: 실제 예외를 노출해 마이크/채널 원인을 구분한다.
              _status = '${_copy(ko: '무전 시작 실패', en: 'PTT start failed', fr: 'Échec PTT')}: $error';
            });
          })
          .whenComplete(() {
            if (mounted) setState(() => _talking = false);
          }),
    );
  }

  Future<void> _stopTalking() async {
    if (!_crew.isJoined) return;
    setState(() => _talking = false);
    try {
      await widget.pttController.stopTalking();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _copy(
          ko: '마이크를 정지하지 못했어요.',
          en: 'Could not stop the microphone.',
          fr: 'Micro non arrêté.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final joined = _crew.isJoined;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_copy(ko: '크루 보이스', en: 'Crew Voice', fr: 'Voix groupe')),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusPanel(
                      label: joined
                          ? _copy(ko: '연결됨', en: 'Connected', fr: 'Connecté')
                          : _copy(
                              ko: '대기 중',
                              en: 'Not joined',
                              fr: 'En attente',
                            ),
                      detail: joined
                          ? '${_copy(ko: '코드', en: 'Code', fr: 'Code')} ${_crew.code ?? ''}'
                          : _copy(
                              ko: '방을 만들거나 코드로 참여하세요.',
                              en: 'Create a room or join with a code.',
                              fr: 'Créez un salon ou entrez un code.',
                            ),
                      active: joined,
                    ),
                    const SizedBox(height: 12),
                    _RoomPanel(
                      codeController: _codeController,
                      roomController: _roomController,
                      nameController: _nameController,
                      busy: _busy,
                      joined: joined,
                      language: _language,
                      onCreate: _createRoom,
                      onJoin: _joinRoom,
                      onLeave: _leaveRoom,
                    ),
                    const SizedBox(height: 12),
                    _MembersPanel(
                      language: _language,
                      members: _crew.onlineMembers,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: _MicButton(
                        enabled: joined && !_busy,
                        talking: _talking,
                        language: _language,
                        onDown: _startTalking,
                        onUpOrCancel: _stopTalking,
                      ),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _status!,
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _copy({required String ko, required String en, required String fr}) {
    return AppCopy.t(_language, ko: ko, en: en, fr: fr);
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.label,
    required this.detail,
    required this.active,
  });

  final String label;
  final String detail;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.radio_button_off,
            color: active ? AppColors.success : AppColors.stoneMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.label(
                    size: 18,
                    weight: FontWeight.w900,
                    color: AppColors.cream,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppText.body(size: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomPanel extends StatelessWidget {
  const _RoomPanel({
    required this.codeController,
    required this.roomController,
    required this.nameController,
    required this.busy,
    required this.joined,
    required this.language,
    required this.onCreate,
    required this.onJoin,
    required this.onLeave,
  });

  final TextEditingController codeController;
  final TextEditingController roomController;
  final TextEditingController nameController;
  final bool busy;
  final bool joined;
  final AppLanguage language;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InputField(
            controller: nameController,
            label: _t(language, ko: '표시 이름', en: 'Display name', fr: 'Nom'),
          ),
          const SizedBox(height: 10),
          _InputField(
            controller: roomController,
            label: _t(language, ko: '방 이름', en: 'Room name', fr: 'Salon'),
          ),
          const SizedBox(height: 10),
          _InputField(
            controller: codeController,
            label: _t(language, ko: '참여 코드', en: 'Join code', fr: 'Code'),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                icon: Icons.add_rounded,
                label: _t(language, ko: '방 만들기', en: 'Create', fr: 'Créer'),
                enabled: !busy,
                filled: true,
                onTap: onCreate,
              ),
              _ActionButton(
                icon: Icons.login_rounded,
                label: _t(language, ko: '참여', en: 'Join', fr: 'Rejoindre'),
                enabled: !busy,
                onTap: onJoin,
              ),
              _ActionButton(
                icon: Icons.logout_rounded,
                label: _t(language, ko: '떠나기', en: 'Leave', fr: 'Quitter'),
                enabled: joined && !busy,
                onTap: onLeave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      style: AppText.body(color: AppColors.cream),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.body(size: 12, color: AppColors.stoneMuted),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? AppColors.onPrimary : AppColors.cream;
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: filled ? AppColors.primaryContainer : null,
          side: BorderSide(
            color: filled ? AppColors.primaryContainer : AppColors.outline,
          ),
          textStyle: AppText.label(size: 13, weight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _MembersPanel extends StatelessWidget {
  const _MembersPanel({required this.language, required this.members});

  final AppLanguage language;
  final List<CrewChannelOnlineMember> members;

  @override
  Widget build(BuildContext context) {
    final count = members.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              language,
              ko: '온라인 $count명',
              en: '$count online',
              fr: '$count en ligne',
            ),
            style: AppText.label(
              size: 17,
              weight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            Text(
              _t(
                language,
                ko: '아직 온라인 멤버가 없어요.',
                en: 'No online members yet.',
                fr: 'Aucun membre en ligne.',
              ),
              style: AppText.body(size: 13, color: AppColors.stone),
            )
          else
            ...members.map(
              (member) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 14,
                          weight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.enabled,
    required this.talking,
    required this.language,
    required this.onDown,
    required this.onUpOrCancel,
  });

  final bool enabled;
  final bool talking;
  final AppLanguage language;
  final VoidCallback onDown;
  final Future<void> Function() onUpOrCancel;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? talking
              ? AppColors.danger
              : AppColors.primaryContainer
        : AppColors.surfaceHigh;
    return GestureDetector(
      key: const ValueKey('walkieMicButton'),
      onTapDown: enabled ? (_) => onDown() : null,
      onTapUp: enabled ? (_) => unawaited(onUpOrCancel()) : null,
      onTapCancel: enabled ? () => unawaited(onUpOrCancel()) : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: _t(language, ko: '마이크', en: 'Microphone', fr: 'Micro'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.36),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.mic_rounded,
                color: AppColors.onPrimary,
                size: 34,
              ),
              const SizedBox(height: 4),
              Text(
                enabled
                    ? _t(language, ko: '누르기', en: 'Hold', fr: 'Tenir')
                    : _t(language, ko: '대기', en: 'Locked', fr: 'Bloqué'),
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.onPrimary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _t(
  AppLanguage language, {
  required String ko,
  required String en,
  required String fr,
}) {
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
