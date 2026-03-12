import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/obd_service.dart';

class OBDScreen extends StatefulWidget {
  const OBDScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OBDScreen()),
    );
  }

  @override
  State<OBDScreen> createState() => _OBDScreenState();
}

class _OBDScreenState extends State<OBDScreen> {
  int _tab = 0; // 0=Live, 1=Telem, 2=Setup

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(onBack: () => Navigator.pop(context)),
            Expanded(
              child: Row(
                children: [
                  // 왼쪽 레일
                  _LeftRail(
                    selected: _tab,
                    onSelect: (t) => setState(() => _tab = t),
                  ),
                  Container(width: 1, color: Colors.white12),
                  // 탭 컨텐츠
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _buildTab(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 0:
        return const _LiveTab(key: ValueKey(0));
      case 1:
        return const _TelemTab(key: ValueKey(1));
      case 2:
        return const _SetupTab(key: ValueKey(2));
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── 앱바 ─────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _AppBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Consumer<OBDService>(
      builder: (_, obd, __) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border(
            bottom: BorderSide(color: AppColors.red.withOpacity(0.3)),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white54, size: 16),
            ),
            const SizedBox(width: 12),
            Text(
              'OBD TELEMETRY',
              style: GoogleFonts.orbitron(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            const Spacer(),
            // 연결 상태 표시
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _stateColor(obd.state),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _stateLabel(obd.state),
                  style: GoogleFonts.rajdhani(
                      fontSize: 11, color: _stateColor(obd.state)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _stateColor(OBDState s) {
    switch (s) {
      case OBDState.ready:
        return const Color(0xFF00FF88);
      case OBDState.scanning:
      case OBDState.connecting:
        return Colors.orange;
      case OBDState.error:
        return AppColors.red;
      case OBDState.disconnected:
        return Colors.white24;
    }
  }

  String _stateLabel(OBDState s) {
    switch (s) {
      case OBDState.ready:
        return 'CONNECTED';
      case OBDState.scanning:
        return 'SCANNING';
      case OBDState.connecting:
        return 'CONNECTING';
      case OBDState.error:
        return 'ERROR';
      case OBDState.disconnected:
        return 'DISCONNECTED';
    }
  }
}

// ── 왼쪽 레일 ────────────────────────────────────────────────

class _LeftRail extends StatelessWidget {
  final int selected;
  final void Function(int) onSelect;
  const _LeftRail({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      color: AppColors.panel,
      child: Column(
        children: [
          const SizedBox(height: 16),
          _RailItem(icon: Icons.speed, label: 'LIVE', idx: 0, selected: selected, onSelect: onSelect),
          const SizedBox(height: 8),
          _RailItem(icon: Icons.show_chart, label: 'DATA', idx: 1, selected: selected, onSelect: onSelect),
          const SizedBox(height: 8),
          _RailItem(icon: Icons.settings, label: 'SETUP', idx: 2, selected: selected, onSelect: onSelect),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int idx;
  final int selected;
  final void Function(int) onSelect;
  const _RailItem({
    required this.icon,
    required this.label,
    required this.idx,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final active = idx == selected;
    return GestureDetector(
      onTap: () => onSelect(idx),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: active ? AppColors.red : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 18,
                color: active ? AppColors.red : Colors.white24),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.red : Colors.white24,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── TAB 1: LIVE ──────────────────────────────────────────────

class _LiveTab extends StatelessWidget {
  const _LiveTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OBDService>(
      builder: (context, obd, _) {
        if (!obd.isConnected) {
          return _NotConnectedBanner(onConnect: () => obd.connect());
        }
        final channels = obd.liveChannels;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                  children: List.generate(4, (i) {
                    final pid = channels[i];
                    final ch = OBDService.channels[pid];
                    return _GaugeCard(
                      pid: pid,
                      channel: ch,
                      value: obd.getDisplayValue(pid),
                      percent: obd.getPercent(pid),
                      onTap: () => _showChannelPicker(context, obd, i),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '게이지 탭 → 채널 변경',
                  style: GoogleFonts.rajdhani(
                      fontSize: 10, color: Colors.white24),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChannelPicker(BuildContext context, OBDService obd, int idx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('채널 선택',
                style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          ...OBDService.channels.entries.map((e) {
            final isActive = obd.liveChannels[idx] == e.key;
            return ListTile(
              dense: true,
              leading: Text(
                _categoryIcon(e.value.category),
                style: const TextStyle(fontSize: 16),
              ),
              title: Text(e.value.name,
                  style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              subtitle: Text('${e.value.category} · ${e.value.unit}',
                  style: GoogleFonts.rajdhani(
                      fontSize: 11, color: AppColors.gray)),
              trailing: isActive
                  ? const Icon(Icons.check_circle,
                      color: AppColors.red, size: 18)
                  : null,
              onTap: () {
                obd.setLiveChannel(idx, e.key);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _categoryIcon(String cat) {
    switch (cat) {
      case 'ENGINE':
        return '⚙️';
      case 'AIR':
        return '💨';
      case 'FUEL':
        return '⛽';
      case 'VEHICLE':
        return '🚗';
      default:
        return '📊';
    }
  }
}

// ── 아크 게이지 카드 ─────────────────────────────────────────

class _GaugeCard extends StatelessWidget {
  final String pid;
  final OBDChannel? channel;
  final String value;
  final double percent;
  final VoidCallback onTap;

  const _GaugeCard({
    required this.pid,
    required this.channel,
    required this.value,
    required this.percent,
    required this.onTap,
  });

  Color _gaugeColor() {
    if (percent > 0.85) return AppColors.red;
    if (percent > 0.65) return Colors.orange;
    if (pid == '012F' && percent < 0.15) return AppColors.red;
    return AppColors.red;
  }

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    final color = _gaugeColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 110,
              height: 90,
              child: CustomPaint(
                painter: _ArcPainter(percent: percent, color: color),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: GoogleFonts.orbitron(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      if (ch != null)
                        Text(
                          ch.unit,
                          style: GoogleFonts.rajdhani(
                              fontSize: 10, color: AppColors.gray),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ch?.name ?? pid,
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gray,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.swap_horiz, size: 12, color: Colors.white24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double percent;
  final Color color;
  const _ArcPainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final radius = size.width * 0.44;
    // 시작: 왼쪽 아래 (210°), 스윕: 240°
    const startDeg = 210.0;
    const sweepDeg = 240.0;
    final startRad = startDeg * math.pi / 180;
    final sweepRad = sweepDeg * math.pi / 180;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 배경 트랙
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = Colors.white12
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // 전경 (값)
    if (percent > 0) {
      canvas.drawArc(
        rect,
        startRad,
        sweepRad * percent.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color
          ..strokeWidth = 7
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.percent != percent || old.color != color;
}

// ── TAB 2: TELEMETRY ─────────────────────────────────────────

class _TelemTab extends StatelessWidget {
  const _TelemTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OBDService>(
      builder: (_, obd, __) {
        if (!obd.isConnected) {
          return _NotConnectedBanner(onConnect: () => obd.connect());
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _telemSection('⚙️  ENGINE', ['010C', '0104', '0111', '0145', '0105', '015C'], obd),
            _telemSection('💨  AIR / INTAKE', ['010F', '010B', '0110'], obd),
            _telemSection('⛽  FUEL', ['012F', '015E'], obd),
            _telemSection('🚗  VEHICLE', ['010D', '0149', '0142'], obd),
            _ExtendedSection(),
          ],
        );
      },
    );
  }

  Widget _telemSection(String title, List<String> pids, OBDService obd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.red,
              letterSpacing: 2,
            ),
          ),
        ),
        ...pids.map((pid) => _TelemRow(pid: pid, obd: obd)),
        Divider(height: 1, color: Colors.white12, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _TelemRow extends StatelessWidget {
  final String pid;
  final OBDService obd;
  const _TelemRow({required this.pid, required this.obd});

  @override
  Widget build(BuildContext context) {
    final ch = OBDService.channels[pid];
    if (ch == null) return const SizedBox.shrink();
    final val = obd.getDisplayValue(pid);
    final pct = obd.getPercent(pid);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          // 채널명
          SizedBox(
            width: 90,
            child: Text(
              ch.name,
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ),
          // 바
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: _barColor(pct),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 값
          SizedBox(
            width: 52,
            child: Text(
              '$val ${ch.unit}',
              textAlign: TextAlign.right,
              style: GoogleFonts.orbitron(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _barColor(double pct) {
    if (pid == '012F') {
      // 연료: 적을수록 빨강
      if (pct < 0.15) return AppColors.red;
      if (pct < 0.30) return Colors.orange;
      return const Color(0xFF00CC66);
    }
    if (pct > 0.85) return AppColors.red;
    if (pct > 0.65) return Colors.orange;
    return AppColors.red;
  }
}

// 차량 의존 확장 채널
class _ExtendedSection extends StatelessWidget {
  const _ExtendedSection();

  @override
  Widget build(BuildContext context) {
    const extChannels = [
      ('조향각', 'Steering Angle', '°'),
      ('ABS 압력', 'ABS Brake Pressure', 'bar'),
      ('요레이트', 'Yaw Rate', '°/s'),
      ('횡가속도', 'Lateral G', 'g'),
      ('종가속도', 'Longitudinal G', 'g'),
      ('트랙션 컨트롤', 'TCS Status', '—'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              Text(
                '🏎  EXTENDED',
                style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gray,
                    letterSpacing: 2),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  '차량 의존',
                  style: GoogleFonts.rajdhani(
                      fontSize: 9, color: AppColors.gray),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            'Mode 22 확장 PID — 차량 제조사별 지원 여부가 다릅니다.',
            style: GoogleFonts.rajdhani(fontSize: 10, color: Colors.white24),
          ),
        ),
        ...extChannels.map((c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(c.$1,
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: Colors.white38)),
                ),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text(
                    '— ${c.$3}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.orbitron(
                        fontSize: 10, color: Colors.white24),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── TAB 3: SETUP ─────────────────────────────────────────────

class _SetupTab extends StatelessWidget {
  const _SetupTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OBDService>(
      builder: (_, obd, __) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 연결 카드
          _ConnectionCard(obd: obd),
          const SizedBox(height: 20),
          // 라이브 채널 설정
          if (obd.isConnected) ...[
            Text(
              'LIVE 게이지 채널 설정',
              style: GoogleFonts.rajdhani(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.red,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            ...List.generate(4, (i) => _ChannelSelector(index: i, obd: obd)),
          ],
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final OBDService obd;
  const _ConnectionCard({required this.obd});

  @override
  Widget build(BuildContext context) {
    final isConnected = obd.isConnected;
    final isBusy = obd.state == OBDState.scanning ||
        obd.state == OBDState.connecting;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF00FF88).withOpacity(0.3)
              : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
            size: 40,
            color: isConnected
                ? const Color(0xFF00FF88)
                : isBusy
                    ? Colors.orange
                    : Colors.white38,
          ),
          const SizedBox(height: 12),
          Text(
            isConnected
                ? 'VEEPEAK OBD2 BLE+'
                : isBusy
                    ? obd.state == OBDState.scanning
                        ? '기기 탐색 중...'
                        : '연결 중...'
                    : 'OBD 기기 없음',
            style: GoogleFonts.orbitron(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (obd.state == OBDState.error && obd.errorMsg != null) ...[
            const SizedBox(height: 6),
            Text(
              obd.errorMsg!,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                  fontSize: 11, color: AppColors.red),
            ),
          ],
          const SizedBox(height: 16),
          if (!isBusy)
            GestureDetector(
              onTap: isConnected ? obd.disconnect : obd.connect,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.transparent
                      : AppColors.red,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isConnected ? AppColors.red : AppColors.red,
                  ),
                ),
                child: Center(
                  child: Text(
                    isConnected ? '연결 해제' : 'OBD 연결하기',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isConnected ? AppColors.red : Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.red),
            ),
        ],
      ),
    );
  }
}

class _ChannelSelector extends StatelessWidget {
  final int index;
  final OBDService obd;
  const _ChannelSelector({required this.index, required this.obd});

  @override
  Widget build(BuildContext context) {
    final pid = obd.liveChannels[index];
    final ch = OBDService.channels[pid];

    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: GoogleFonts.orbitron(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ch?.name ?? pid,
                    style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  Text(
                    ch != null ? '${ch.category} · ${ch.unit}' : '',
                    style: GoogleFonts.rajdhani(
                        fontSize: 10, color: AppColors.gray),
                  ),
                ],
              ),
            ),
            const Icon(Icons.swap_horiz, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  void _pick(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('게이지 ${index + 1} 채널',
                style: GoogleFonts.orbitron(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          ...OBDService.channels.entries.map((e) {
            final active = obd.liveChannels[index] == e.key;
            return ListTile(
              dense: true,
              title: Text('${e.value.name}  (${e.value.unit})',
                  style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              subtitle: Text(e.value.category,
                  style: GoogleFonts.rajdhani(
                      fontSize: 10, color: AppColors.gray)),
              trailing: active
                  ? const Icon(Icons.check_circle,
                      color: AppColors.red, size: 18)
                  : null,
              onTap: () {
                obd.setLiveChannel(index, e.key);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── 공통: 미연결 배너 ────────────────────────────────────────

class _NotConnectedBanner extends StatelessWidget {
  final VoidCallback onConnect;
  const _NotConnectedBanner({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bluetooth_disabled,
              size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'OBD 연결 필요',
            style: GoogleFonts.orbitron(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Text(
            'SETUP 탭에서 연결하거나 아래를 탭하세요',
            style: GoogleFonts.rajdhani(fontSize: 12, color: Colors.white24),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'OBD 연결하기',
                style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
