import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../services/settings_service.dart';
import '../services/jarvis_script.dart';
import '../services/route_service.dart';
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SETTINGS',
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.red.withOpacity(0.3)),
        ),
      ),
      body: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              // ── 섹션: 음성 ──────────────────────────────────────
              _SectionHeader(label: '음성 안내'),
              _ToggleTile(
                icon: settings.ttsMuted ? Icons.volume_off : Icons.volume_up,
                iconColor: settings.ttsMuted ? AppColors.gray : Colors.lightBlueAccent,
                title: 'TTS 음성 안내',
                subtitle: settings.ttsMuted ? '음소거 중' : '안내 음성 켜짐',
                value: !settings.ttsMuted,
                onChanged: (v) => settings.setTtsMuted(!v),
              ),

              // ── 섹션: 코파일럿 스타일 ───────────────────────────────
              _SectionHeader(label: '코파일럿 스타일'),
              _RadioTile<JarvisPersona>(
                icon: Icons.record_voice_over_rounded,
                iconColor: AppColors.red,
                title: '음성 페르소나',
                subtitle: '자동 브리핑 어조',
                options: const [
                  _Option(label: '레이스 엔지니어', value: JarvisPersona.engineer),
                  _Option(label: '친근한 코파일럿', value: JarvisPersona.friendly),
                ],
                selected: settings.jarvisPersona,
                onChanged: settings.setJarvisPersona,
              ),

              // ── 섹션: 루트 탐색 ─────────────────────────────────
              _SectionHeader(label: '루트 탐색'),
              _RadioTile<int>(
                icon: Icons.radar,
                iconColor: AppColors.red,
                title: '탐색 반경',
                subtitle: '루트를 찾을 반경 거리',
                options: const [
                  _Option(label: '30 km', value: 30),
                  _Option(label: '50 km', value: 50),
                  _Option(label: '100 km', value: 100),
                ],
                selected: settings.searchRadiusKm,
                onChanged: (v) {
                  settings.setSearchRadius(v);
                  // RouteService searchRadiusKm 동기화
                  context.read<RouteService>().searchRadiusKm = v;
                },
              ),
              _RadioTile<String>(
                icon: Icons.straighten,
                iconColor: AppColors.textSecondary,
                title: '거리 단위',
                subtitle: '앱 전체 거리 표시 단위',
                options: const [
                  _Option(label: 'km', value: 'km'),
                  _Option(label: 'mi', value: 'mi'),
                ],
                selected: settings.distUnit,
                onChanged: settings.setDistUnit,
              ),

              // ── 섹션: 주행 ──────────────────────────────────────
              _SectionHeader(label: '주행'),
              _ToggleTile(
                icon: Icons.speed,
                iconColor: AppColors.textSecondary,
                title: '속도 HUD 표시',
                subtitle: '레일에 속도/날씨 항목 표시',
                value: settings.showSpeedHud,
                onChanged: settings.setShowSpeedHud,
              ),
              _ToggleTile(
                icon: Icons.warning_amber_rounded,
                iconColor: Colors.orange,
                title: '루트 이탈 경고',
                subtitle: '루트 300m 이상 벗어나면 알림',
                value: settings.offRouteAlert,
                onChanged: settings.setOffRouteAlert,
              ),
              _ToggleTile(
                icon: Icons.hearing,
                iconColor: AppColors.cyan,
                title: '항상 듣기',
                subtitle: '마이크 버튼 없이 자동으로 음성 명령 감지',
                value: settings.alwaysListen,
                onChanged: settings.setAlwaysListen,
              ),

              const SizedBox(height: 32),
              // ── 루트 캘리브레이션 ─────────────────────────────────
              _SectionHeader(label: '루트 캘리브레이션'),
              _ActionTile(
                label: '캘리브레이션 다시하기',
                subtitle: '싫어하는 루트 취향을 다시 설정합니다',
                icon: Icons.tune_rounded,
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(kCalibrationDoneKey);
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const CalibrationScreen()),
                  );
                },
              ),
              _ActionTile(
                label: '배제 루트 초기화',
                subtitle: '싫어요한 루트를 모두 복원합니다',
                icon: Icons.restore_rounded,
                color: AppColors.orange,
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('revv_excluded_centers');
                  if (!context.mounted) return;
                  context.read<RouteService>().resetExclusions();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('배제 루트가 초기화됐어요',
                          style: GoogleFonts.rajdhani(fontSize: 13)),
                      backgroundColor: AppColors.panel,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),


              const SizedBox(height: 32),
              // ── 앱 정보 ──────────────────────────────────────────
              _SectionHeader(label: '앱 정보'),
              _InfoTile(label: '버전', value: 'v1.40'),
              _InfoTile(label: '지도', value: 'Mapbox'),
              _InfoTile(label: '루트 데이터', value: 'Overpass API (OSM)'),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ── 섹션 헤더 ─────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.red,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: AppColors.red.withOpacity(0.2))),
        ],
      ),
    );
  }
}

// ── 토글 타일 ─────────────────────────────────────────────────
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        title: Text(
          title,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.red,
          inactiveTrackColor: AppColors.panel2,
          inactiveThumbColor: AppColors.gray,
        ),
      ),
    );
  }
}

// ── 라디오 선택 타일 ──────────────────────────────────────────
class _Option<T> {
  final String label;
  final T value;
  const _Option({required this.label, required this.value});
}

class _RadioTile<T> extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<_Option<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const _RadioTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSelected = opt.value == selected;
              return GestureDetector(
                onTap: () => onChanged(opt.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.red : AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? AppColors.red : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    opt.label,
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── 액션 타일 ─────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.red;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(subtitle,
                      style: GoogleFonts.rajdhani(
                          fontSize: 11, color: AppColors.textHint)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

// ── 정보 타일 ─────────────────────────────────────────────────
class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}


