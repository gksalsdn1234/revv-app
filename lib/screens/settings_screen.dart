import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/jarvis_service.dart';
import '../services/jarvis_script.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/revv_copy.dart';
import 'calibration_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static void show(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supabase = SupabaseService();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cockpitBackgroundGradient(),
        ),
        child: Stack(
          children: [
            const _SettingsBackdrop(),
            SafeArea(
              bottom: false,
              child: Consumer<SettingsService>(
                builder: (context, settings, _) {
                  final jarvis = context.watch<JarvisService>();
                  final location = context.watch<LocationService>();
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: _SettingsTopBar(
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                          child: _SettingsOverviewCard(
                            voiceLabel: settings.ttsMuted
                                ? '음성 꺼짐'
                                : '음성 안내 켜짐',
                            locationLabel: location.permissionStatusLabel,
                            safetyLabel: settings.offRouteAlert
                                ? '주행 안전 안내 켜짐'
                                : '주행 안전 안내 꺼짐',
                            radiusKm: settings.searchRadiusKm,
                            cloudLabel: supabase.availabilityLabel,
                            speedLabel: _speechPresetLabel(
                              settings.ttsRatePreset,
                            ),
                            engineLabel: _speechEngineLabel(settings.ttsEngine),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final wide = constraints.maxWidth >= 760;
                              final navigationCard = _SettingsFeatureCard(
                                icon: Icons.alt_route_rounded,
                                section: RevvCopy.routeFinder,
                                accent: AppColors.primaryContainer,
                                child: Column(
                                  children: [
                                    _SettingsToggleRow(
                                      title: '음성 안내',
                                      subtitle: settings.ttsMuted
                                          ? '주행 중 음성 안내를 쉬게 해요'
                                          : '코너와 이탈 안내를 짧게 읽어요',
                                      value: !settings.ttsMuted,
                                      onChanged: (value) =>
                                          settings.setTtsMuted(!value),
                                    ),
                                    const SizedBox(height: 14),
                                    _InlineSegmentField<String>(
                                      label: '음성 엔진',
                                      valueLabel: _speechEngineLabel(
                                        settings.ttsEngine,
                                      ),
                                      options: const [
                                        _SegmentOption(
                                          label: 'GOOGLE',
                                          value: 'google',
                                        ),
                                        _SegmentOption(
                                          label: 'DEVICE',
                                          value: 'device',
                                        ),
                                      ],
                                      selected: settings.ttsEngine,
                                      onChanged: settings.setTtsEngine,
                                    ),
                                    const SizedBox(height: 18),
                                    _InlineSegmentField<String>(
                                      label: '음성 속도',
                                      valueLabel: _speechPresetLabel(
                                        settings.ttsRatePreset,
                                      ),
                                      options: const [
                                        _SegmentOption(
                                          label: '차분',
                                          value: 'relaxed',
                                        ),
                                        _SegmentOption(
                                          label: '기본',
                                          value: 'balanced',
                                        ),
                                        _SegmentOption(
                                          label: '빠름',
                                          value: 'brisk',
                                        ),
                                      ],
                                      selected: settings.ttsRatePreset,
                                      onChanged: settings.setTtsRatePreset,
                                    ),
                                    const SizedBox(height: 18),
                                    _SettingsPickerRow(
                                      title: settings.ttsEngine == 'google'
                                          ? 'Google 음성'
                                          : '기기 음성',
                                      subtitle: settings.ttsEngine == 'google'
                                          ? (jarvis.googleVoices.isEmpty
                                                ? 'Google 한국어 음성을 불러오는 중이에요'
                                                : '고급 음성 · 네트워크 필요')
                                          : (jarvis.deviceVoices.isEmpty
                                                ? '사용 가능한 한국어 음성을 불러오는 중이에요'
                                                : '${jarvis.deviceVoices.length}개 한국어 음성 중 선택'),
                                      valueLabel: settings.ttsEngine == 'google'
                                          ? (jarvis.selectedGoogleVoice?.name ??
                                                'Google 기본 음성')
                                          : (jarvis.selectedDeviceVoice?.name ??
                                                '기본 한국어 음성'),
                                      onTap:
                                          (settings.ttsEngine == 'google'
                                                  ? jarvis.googleVoices
                                                  : jarvis.deviceVoices)
                                              .isEmpty
                                          ? null
                                          : () => _showVoicePicker(
                                              context,
                                              jarvis: jarvis,
                                              settings: settings,
                                              useGoogle:
                                                  settings.ttsEngine ==
                                                  'google',
                                            ),
                                    ),
                                    const SizedBox(height: 14),
                                    _SettingsToggleRow(
                                      title: '항상 듣기',
                                      subtitle: settings.alwaysListen
                                          ? '베타 · 웨이크워드로 로컬 명령을 대기해요'
                                          : '마이크 버튼을 눌렀을 때만 음성을 받아요',
                                      value: settings.alwaysListen,
                                      onChanged: settings.setAlwaysListen,
                                    ),
                                    const SizedBox(height: 18),
                                    _InlineSegmentField<int>(
                                      label: '탐색 반경',
                                      valueLabel:
                                          '${settings.searchRadiusKm}KM',
                                      options: const [
                                        _SegmentOption(label: '30', value: 30),
                                        _SegmentOption(label: '50', value: 50),
                                        _SegmentOption(
                                          label: '100',
                                          value: 100,
                                        ),
                                        _SegmentOption(
                                          label: '160',
                                          value: 160,
                                        ),
                                        _SegmentOption(
                                          label: '220',
                                          value: 220,
                                        ),
                                      ],
                                      selected: settings.searchRadiusKm,
                                      onChanged: (value) {
                                        settings.setSearchRadius(value);
                                        context
                                                .read<RouteService>()
                                                .searchRadiusKm =
                                            value;
                                      },
                                    ),
                                    const SizedBox(height: 18),
                                    _InlineSegmentField<String>(
                                      label: '거리 단위',
                                      valueLabel: settings.distUnit
                                          .toUpperCase(),
                                      options: const [
                                        _SegmentOption(
                                          label: 'KM',
                                          value: 'km',
                                        ),
                                        _SegmentOption(
                                          label: 'MI',
                                          value: 'mi',
                                        ),
                                      ],
                                      selected: settings.distUnit,
                                      onChanged: settings.setDistUnit,
                                    ),
                                  ],
                                ),
                              );

                              final hudCard = _SettingsFeatureCard(
                                icon: Icons.speed_rounded,
                                section: '주행 HUD',
                                accent: AppColors.primaryContainer,
                                highlighted: true,
                                child: Column(
                                  children: [
                                    _SettingsToggleRow(
                                      title: '속도 HUD',
                                      subtitle: settings.showSpeedHud
                                          ? '주행 중 기본 정보를 크게 보여줘요'
                                          : 'HUD를 숨겨 지도를 더 넓게 봐요',
                                      value: settings.showSpeedHud,
                                      onChanged: settings.setShowSpeedHud,
                                    ),
                                    const SizedBox(height: 14),
                                    _SettingsToggleRow(
                                      title: '루트 이탈 경고',
                                      subtitle: settings.offRouteAlert
                                          ? '루트 이탈을 음성·화면으로 알려줘요'
                                          : '이탈 경고를 조용히 유지해요',
                                      value: settings.offRouteAlert,
                                      onChanged: settings.setOffRouteAlert,
                                    ),
                                    const SizedBox(height: 18),
                                    _InlineSegmentField<JarvisPersona>(
                                      label: '코파일럿 톤',
                                      valueLabel:
                                          settings.jarvisPersona ==
                                              JarvisPersona.engineer
                                          ? 'ENGINEER'
                                          : 'FRIENDLY',
                                      options: const [
                                        _SegmentOption(
                                          label: 'ENGINEER',
                                          value: JarvisPersona.engineer,
                                        ),
                                        _SegmentOption(
                                          label: 'FRIENDLY',
                                          value: JarvisPersona.friendly,
                                        ),
                                      ],
                                      selected: settings.jarvisPersona,
                                      onChanged: settings.setJarvisPersona,
                                    ),
                                  ],
                                ),
                              );

                              if (!wide) {
                                return Column(
                                  children: [
                                    navigationCard,
                                    const SizedBox(height: 14),
                                    hudCard,
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: navigationCard),
                                  const SizedBox(width: 14),
                                  Expanded(child: hudCard),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                          child: _SectionLabel(
                            icon: Icons.tune_rounded,
                            title: '관리',
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Column(
                            children: [
                              _SettingsListRow(
                                icon: Icons.tune_rounded,
                                iconColor: AppColors.primaryContainer,
                                title: '취향 보정 다시하기',
                                subtitle: '추천/숨기기 선택으로 추천 감도를 다시 맞춰요',
                                trailingIcon: Icons.chevron_right_rounded,
                                onTap: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.remove(kCalibrationDoneKey);
                                  if (!context.mounted) return;
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CalibrationScreen(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              _SettingsListRow(
                                icon: Icons.restore_rounded,
                                iconColor: AppColors.warning,
                                title: '숨긴 루트 초기화',
                                subtitle: '숨긴 루트를 모두 다시 표시해요',
                                trailingIcon: Icons.chevron_right_rounded,
                                onTap: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.remove('revv_excluded_centers');
                                  if (!context.mounted) return;
                                  context
                                      .read<RouteService>()
                                      .resetExclusions();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('배제 루트를 초기화했어요'),
                                      backgroundColor: AppColors.panel2,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                          child: _SectionLabel(
                            icon: Icons.account_circle_outlined,
                            title: '데이터 & 앱 정보',
                            color: AppColors.outline,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: supabase,
                                builder: (context, _) {
                                  final subtitle =
                                      supabase.lastFailureReason ??
                                      (supabase.isCloudAvailable
                                          ? '클라우드 텔레메트리가 준비됐어요'
                                          : '로컬 데이터만 사용 중');
                                  return _SettingsListRow(
                                    icon: Icons.cloud_sync_rounded,
                                    iconColor: AppColors.primaryContainer,
                                    title: '클라우드 동기화',
                                    subtitle: subtitle,
                                    trailingLabel: supabase.availabilityLabel,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              _SettingsListRow(
                                icon: Icons.map_outlined,
                                iconColor: AppColors.textSecondary,
                                title: '루트 데이터 소스',
                                subtitle: 'Mapbox · Overpass · Supabase 베타',
                                trailingLabel: 'ONLINE',
                              ),
                              const SizedBox(height: 8),
                              _SettingsListRow(
                                icon: Icons.info_outline_rounded,
                                iconColor: AppColors.textSecondary,
                                title: '앱 버전',
                                subtitle: 'REVV cockpit build',
                                trailingLabel: 'v1.40',
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 34),
                          child: _SettingsStatusCard(
                            status: settings.alwaysListen
                                ? 'VOICE LINK READY'
                                : 'SYSTEM CALIBRATED',
                            subtitle: '설정이 저장되면 즉시 주행 화면에 반영돼요',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _speechPresetLabel(String preset) {
  switch (preset) {
    case 'balanced':
      return '기본';
    case 'brisk':
      return '빠름';
    case 'relaxed':
    default:
      return '차분';
  }
}

String _speechEngineLabel(String engine) {
  switch (engine) {
    case 'device':
      return '기기 기본';
    case 'google':
    default:
      return 'Google HD';
  }
}

Future<void> _showVoicePicker(
  BuildContext context, {
  required JarvisService jarvis,
  required SettingsService settings,
  required bool useGoogle,
}) async {
  final voices = useGoogle ? jarvis.googleVoices : jarvis.deviceVoices;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.panel2.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.record_voice_over_rounded,
                      color: AppColors.primaryContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      useGoogle ? 'Google 음성 선택' : '기기 음성 선택',
                      style: AppText.body(
                        size: 16,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: voices.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: AppColors.outlineVariant.withValues(alpha: 0.16),
                  ),
                  itemBuilder: (context, index) {
                    final voice = voices[index];
                    final selected = useGoogle
                        ? voice.name == settings.googleTtsVoiceName
                        : (voice.name == settings.ttsVoiceName &&
                              voice.locale == settings.ttsVoiceLocale);
                    return ListTile(
                      onTap: () async {
                        if (useGoogle) {
                          await settings.setGoogleTtsVoiceName(voice.name);
                        } else {
                          await settings.setTtsVoice(
                            name: voice.name,
                            locale: voice.locale,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      title: Text(
                        voice.name,
                        style: AppText.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        voice.locale.replaceAll('_', '-'),
                        style: AppText.body(
                          size: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primaryContainer,
                              size: 18,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SettingsBackdrop extends StatelessWidget {
  const _SettingsBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryContainer.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -60,
            top: 180,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.warning.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _SettingsTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TopBarIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 20,
                color: AppColors.primaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'REVV',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryContainer,
                  letterSpacing: 3.2,
                ),
              ),
            ],
          ),
        ),
        Text(
          'SETTINGS',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryContainer,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.battery_charging_full_rounded,
          size: 22,
          color: AppColors.primaryContainer,
        ),
      ],
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.panel2.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}

class _SettingsOverviewCard extends StatelessWidget {
  final String voiceLabel;
  final String locationLabel;
  final String safetyLabel;
  final int radiusKm;
  final String cloudLabel;
  final String speedLabel;
  final String engineLabel;

  const _SettingsOverviewCard({
    required this.voiceLabel,
    required this.locationLabel,
    required this.safetyLabel,
    required this.radiusKm,
    required this.cloudLabel,
    required this.speedLabel,
    required this.engineLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.panel2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryContainer.withValues(alpha: 0.22),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.settings_input_component_rounded,
                  color: AppColors.primaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      RevvCopy.vehicleSettings,
                      style: AppText.body(
                        size: 18,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '클라우드, 음성, 위치, 주행 안전 상태를 한 번에 확인해요',
                      style: AppText.body(
                        size: 12,
                        height: 1.3,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OverviewPill(label: cloudLabel, icon: Icons.cloud_done_rounded),
              _OverviewPill(label: voiceLabel, icon: Icons.volume_up_rounded),
              _OverviewPill(
                label: locationLabel,
                icon: Icons.location_on_rounded,
              ),
              _OverviewPill(label: safetyLabel, icon: Icons.shield_rounded),
              _OverviewPill(label: '음성 $engineLabel · $speedLabel'),
              _OverviewPill(label: '탐색 반경 ${radiusKm}km'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _OverviewPill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.primaryContainer),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppText.body(
              size: 11,
              weight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsFeatureCard extends StatelessWidget {
  final IconData icon;
  final String section;
  final Color accent;
  final bool highlighted;
  final Widget child;

  const _SettingsFeatureCard({
    required this.icon,
    required this.section,
    required this.accent,
    required this.child,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.panel2.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: 0.20)
              : AppColors.outlineVariant.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 8),
              Text(
                section.toUpperCase(),
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.textHint,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppText.body(
                  size: 11,
                  height: 1.3,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CompactSwitch(
          value: value,
          onChanged: onChanged,
          accent: AppColors.primaryContainer,
        ),
      ],
    );
  }
}

class _SettingsPickerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String valueLabel;
  final VoidCallback? onTap;

  const _SettingsPickerRow({
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.20),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 11,
                      height: 1.3,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: enabled
                      ? AppColors.primaryContainer
                      : AppColors.textHint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: enabled ? AppColors.textSecondary : AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  const _CompactSwitch({
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.92,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.onPrimary,
        activeTrackColor: accent,
        inactiveThumbColor: AppColors.outline,
        inactiveTrackColor: AppColors.surfaceHigh,
      ),
    );
  }
}

class _SegmentOption<T> {
  final String label;
  final T value;

  const _SegmentOption({required this.label, required this.value});
}

class _InlineSegmentField<T> extends StatelessWidget {
  final String label;
  final String valueLabel;
  final List<_SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const _InlineSegmentField({
    required this.label,
    required this.valueLabel,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.textHint,
                letterSpacing: 1.6,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.primaryContainer,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final active = option.value == selected;
            return InkWell(
              onTap: () => onChanged(option.value),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primaryContainer
                      : AppColors.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? AppColors.primaryContainer
                        : AppColors.outlineVariant.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  option.label,
                  style: AppText.body(
                    size: 12,
                    weight: FontWeight.w800,
                    color: active
                        ? AppColors.onPrimary
                        : AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionLabel({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: AppText.technicalLabel(
            size: 10,
            color: AppColors.textHint,
            letterSpacing: 1.7,
          ),
        ),
      ],
    );
  }
}

class _SettingsListRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? trailingLabel;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  const _SettingsListRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailingLabel,
    this.trailingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.body(
                      size: 14,
                      weight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 11,
                      height: 1.3,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.4,
                ),
              ),
            if (trailingLabel == null && trailingIcon != null)
              Icon(trailingIcon, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _SettingsStatusCard extends StatelessWidget {
  final String status;
  final String subtitle;

  const _SettingsStatusCard({required this.status, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 138,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.20),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceLowest, AppColors.panel, AppColors.surface],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -10,
            right: -10,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryContainer.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mechanical Integrity Status'.toUpperCase(),
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                status,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
