import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/obd_service.dart';
import '../services/imu_service.dart';

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
            bottom: BorderSide(color: AppColors.red.withValues(alpha: 0.3)),
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
            _FuelEcoRow(obd: obd),
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

// 차량 의존 확장 채널 + 폰 IMU 실시간 데이터
class _ExtendedSection extends StatelessWidget {
  const _ExtendedSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<ImuService>(
      builder: (_, imu, __) {
        final latG = imu.lateralG;
        final lonG = imu.longitudinalG;
        final yaw = imu.yawRateDps;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 폰 IMU 섹션 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Text(
                    '📱  IMU (폰 센서)',
                    style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.red,
                        letterSpacing: 2),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: imu.calibrated
                          ? const Color(0xFF00FF88).withValues(alpha: 0.15)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      imu.calibrated ? '캘리브레이션 완료' : '미캘리브레이션',
                      style: GoogleFonts.rajdhani(
                          fontSize: 9,
                          color: imu.calibrated
                              ? const Color(0xFF00FF88)
                              : Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: _CarGforceMeter(
                lateralG: latG,
                longitudinalG: lonG,
                yawDps: yaw,
                maxLatG: imu.maxLateralG,
                maxLonG: imu.maxLonG,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Colors.white12, indent: 16, endIndent: 16),

            // ── 차량 의존 Mode 22 섹션 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Text(
                    '🏎  EXTENDED (Mode 22)',
                    style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gray,
                        letterSpacing: 2),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      '차량 의존',
                      style: GoogleFonts.rajdhani(fontSize: 9, color: AppColors.gray),
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
            ...const [
              ('조향각', '°'),
              ('ABS 압력', 'bar'),
              ('트랙션 컨트롤', '—'),
            ].map((c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(c.$1,
                        style: GoogleFonts.rajdhani(fontSize: 12, color: Colors.white38)),
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
                    child: Text('— ${c.$2}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.orbitron(fontSize: 10, color: Colors.white24)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}


// ── 순간 연비 행 ───────────────────────────────────────────────

class _FuelEcoRow extends StatelessWidget {
  final OBDService obd;
  const _FuelEcoRow({required this.obd});

  @override
  Widget build(BuildContext context) {
    final eco = obd.instantFuelEconomyL100;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text('순간연비',
                style: GoogleFonts.rajdhani(fontSize: 12, color: Colors.white70)),
          ),
          Expanded(
            child: Stack(children: [
              Container(height: 4,
                  decoration: BoxDecoration(color: Colors.white12,
                      borderRadius: BorderRadius.circular(2))),
              if (eco != null)
                FractionallySizedBox(
                  widthFactor: (1 - (eco / 30).clamp(0.0, 1.0)),
                  child: Container(height: 4,
                      decoration: BoxDecoration(
                          color: eco < 8
                              ? const Color(0xFF00CC66)
                              : eco < 15
                              ? Colors.orange
                              : AppColors.red,
                          borderRadius: BorderRadius.circular(2))),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              eco != null ? '${eco.toStringAsFixed(1)} L/100' : '— L/100',
              textAlign: TextAlign.right,
              style: GoogleFonts.orbitron(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: eco != null
                      ? (eco < 8 ? const Color(0xFF00CC66) : eco < 15 ? Colors.orange : AppColors.red)
                      : Colors.white24),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 자동차 G포스 미터 ───────────────────────────────────────────

class _CarGforceMeter extends StatefulWidget {
  final double lateralG;
  final double longitudinalG;
  final double yawDps;
  final double maxLatG;
  final double maxLonG;

  const _CarGforceMeter({
    required this.lateralG,
    required this.longitudinalG,
    required this.yawDps,
    required this.maxLatG,
    required this.maxLonG,
  });

  @override
  State<_CarGforceMeter> createState() => _CarGforceMeterState();
}

class _CarGforceMeterState extends State<_CarGforceMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static Color _gColor(double mag) {
    final t = (mag / 1.2).clamp(0.0, 1.0);
    if (t < 0.42) {
      return Color.lerp(const Color(0xFF1565C0), const Color(0xFFFDD835), t / 0.42)!;
    }
    return Color.lerp(
      const Color(0xFFFDD835),
      const Color(0xFFE53935),
      ((t - 0.42) / 0.58).clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final mag = math.sqrt(
        widget.lateralG * widget.lateralG + widget.longitudinalG * widget.longitudinalG);
    final maxMag = math.sqrt(widget.maxLatG * widget.maxLatG + widget.maxLonG * widget.maxLonG);
    final color = _gColor(mag);

    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => CustomPaint(
            size: const Size(110, 185),
            painter: _CarGforcePainter(
              lateralG: widget.lateralG,
              longitudinalG: widget.longitudinalG,
              gColor: color,
              pulseValue: _pulse.value,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 수치 행
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _GNum(label: '횡G', value: widget.lateralG, unit: 'g', color: color),
              Container(width: 1, height: 36, color: Colors.white10),
              _GNum(label: '종G', value: widget.longitudinalG, unit: 'g', color: color),
              Container(width: 1, height: 36, color: Colors.white10),
              _GNum(label: '요레이트', value: widget.yawDps, unit: '°/s',
                  color: AppColors.red),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 최대G 배지
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('MAX', style: GoogleFonts.rajdhani(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: Colors.white38, letterSpacing: 2)),
              const SizedBox(width: 10),
              Text('횡 ${widget.maxLatG.toStringAsFixed(2)}g',
                  style: GoogleFonts.rajdhani(fontSize: 12,
                      color: Colors.orange, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Text('종 ${widget.maxLonG.toStringAsFixed(2)}g',
                  style: GoogleFonts.rajdhani(fontSize: 12,
                      color: Colors.orange, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Text('합 ${maxMag.toStringAsFixed(2)}g',
                  style: GoogleFonts.rajdhani(fontSize: 12,
                      color: _gColor(maxMag), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GNum extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;

  const _GNum({required this.label, required this.value,
    required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.rajdhani(
            fontSize: 9, color: Colors.white38, letterSpacing: 1.5)),
        Text(
          value >= 0 ? '+${value.toStringAsFixed(2)}' : value.toStringAsFixed(2),
          style: GoogleFonts.rajdhani(
              fontSize: 19, fontWeight: FontWeight.w700, color: color),
        ),
        Text(unit, style: GoogleFonts.rajdhani(fontSize: 9, color: Colors.white38)),
      ],
    );
  }
}

class _CarGforcePainter extends CustomPainter {
  final double lateralG;
  final double longitudinalG;
  final Color gColor;
  final double pulseValue;

  const _CarGforcePainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.gColor,
    required this.pulseValue,
  });

  double get _magnitude =>
      math.sqrt(lateralG * lateralG + longitudinalG * longitudinalG);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mag = _magnitude;
    final glowRadius = (3.0 + mag * 9.0) * (0.65 + 0.35 * pulseValue);

    // ── 차체 실루엣 ──────────────────────────────────────────────
    final bodyRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.18, h * 0.04, w * 0.64, h * 0.92),
      topLeft: Radius.circular(w * 0.23),
      topRight: Radius.circular(w * 0.23),
      bottomLeft: Radius.circular(w * 0.14),
      bottomRight: Radius.circular(w * 0.14),
    );

    // 글로우
    canvas.drawRRect(bodyRRect, Paint()
      ..color = gColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, glowRadius));

    // 실선
    canvas.drawRRect(bodyRRect, Paint()
      ..color = gColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8);

    // ── 바퀴 4개 ──────────────────────────────────────────────
    final wheelGlow = Paint()
      ..color = gColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.5);
    final wheelFill = Paint()
      ..color = gColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (final r in [
      Rect.fromLTWH(w * 0.01, h * 0.10, w * 0.16, h * 0.15),
      Rect.fromLTWH(w * 0.83, h * 0.10, w * 0.16, h * 0.15),
      Rect.fromLTWH(w * 0.01, h * 0.75, w * 0.16, h * 0.15),
      Rect.fromLTWH(w * 0.83, h * 0.75, w * 0.16, h * 0.15),
    ]) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
      canvas.drawRRect(rr, wheelGlow);
      canvas.drawRRect(rr, wheelFill);
    }

    // ── 앞유리 / 뒷유리 ──────────────────────────────────────
    final glassPaint = Paint()
      ..color = gColor.withValues(alpha: 0.22)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.27, h * 0.23), Offset(w * 0.73, h * 0.23), glassPaint);
    canvas.drawLine(Offset(w * 0.27, h * 0.77), Offset(w * 0.73, h * 0.77), glassPaint);

    // ── G포스 도트 ─────────────────────────────────────────────
    final cx = w / 2;
    final cy = h / 2;
    final maxOff = w * 0.21;

    double dx = lateralG * maxOff;
    double dy = -longitudinalG * maxOff; // 가속 = 위(음수 y)
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > maxOff) {
      dx = dx / dist * maxOff;
      dy = dy / dist * maxOff;
    }

    // 크로스헤어
    final crossP = Paint()..color = Colors.white.withValues(alpha: 0.07)..strokeWidth = 0.5;
    canvas.drawLine(Offset(cx - maxOff, cy), Offset(cx + maxOff, cy), crossP);
    canvas.drawLine(Offset(cx, cy - maxOff), Offset(cx, cy + maxOff), crossP);
    canvas.drawCircle(Offset(cx, cy), maxOff, Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);

    // 도트 글로우
    canvas.drawCircle(Offset(cx + dx, cy + dy), 9, Paint()
      ..color = gColor.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    // 도트 본체
    canvas.drawCircle(Offset(cx + dx, cy + dy), 5, Paint()..color = gColor);
    // 도트 하이라이트
    canvas.drawCircle(Offset(cx + dx, cy + dy), 2,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_CarGforcePainter old) =>
      old.lateralG != lateralG ||
      old.longitudinalG != longitudinalG ||
      old.gColor != gColor ||
      old.pulseValue != pulseValue;
}

// ── TAB 3: SETUP ─────────────────────────────────────────────

class _SetupTab extends StatelessWidget {
  const _SetupTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<OBDService, ImuService>(
      builder: (_, obd, imu, __) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // OBD 연결 카드
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
            const SizedBox(height: 20),
          ],
          // IMU 캘리브레이션 카드
          _ImuCalibrationCard(imu: imu),
        ],
      ),
    );
  }
}

// ── IMU 캘리브레이션 카드 ─────────────────────────────────────

class _ImuCalibrationCard extends StatelessWidget {
  final ImuService imu;
  const _ImuCalibrationCard({required this.imu});

  static const _mountLabels = ['대시보드 수평', '에어컨 세로', '에어컨 가로', '앞유리 세로'];
  static const _mountIcons = ['⬛', '📱', '📲', '🔲'];
  static const _mountDescs = [
    '화면 위, 대시보드에 수평\n(가장 정확)',
    '화면 앞, 에어컨 마운트\n세로 방향',
    '화면 앞, 에어컨 마운트\n가로 방향',
    '화면 앞, 앞유리 흡착\n세로 방향',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IMU 센서 (폰 G-FORCE)',
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.red,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),

        // 마운트 타입 선택 그리드
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: List.generate(MountType.values.length, (i) {
            final selected = imu.mountType == MountType.values[i];
            return GestureDetector(
              onTap: () => imu.setMountType(MountType.values[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.red.withValues(alpha: 0.15) : AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? AppColors.red : Colors.white12,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(_mountIcons[i], style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _mountLabels[i],
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected ? AppColors.red : Colors.white70,
                            ),
                          ),
                          Text(
                            _mountDescs[i],
                            style: GoogleFonts.rajdhani(fontSize: 9, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 16),

        // 현재 실시간 값 미리보기
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '현재 센서 값 (정지 상태에서 0에 가까워야 함)',
                style: GoogleFonts.rajdhani(fontSize: 10, color: Colors.white38),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _LiveVal(label: '횡G', value: imu.lateralG, unit: 'g'),
                  const SizedBox(width: 20),
                  _LiveVal(label: '종G', value: imu.longitudinalG, unit: 'g'),
                  const SizedBox(width: 20),
                  _LiveVal(label: '요레이트', value: imu.yawRateDps, unit: '°/s'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 캘리브레이션 버튼
        GestureDetector(
          onTap: imu.calibrate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Text(
                  imu.calibrated ? '재캘리브레이션' : '캘리브레이션 시작',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  '차량 정지 + 수평 상태에서 탭',
                  style: GoogleFonts.rajdhani(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),

        if (imu.calibrated) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              '✓ 캘리브레이션 완료 — 저장됨',
              style: GoogleFonts.rajdhani(fontSize: 11, color: const Color(0xFF00FF88)),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LiveVal extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  const _LiveVal({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.rajdhani(fontSize: 9, color: AppColors.gray, letterSpacing: 1)),
        Text(
          '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}',
          style: GoogleFonts.orbitron(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        Text(unit, style: GoogleFonts.rajdhani(fontSize: 9, color: AppColors.gray)),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final OBDService obd;
  const _ConnectionCard({required this.obd});

  @override
  Widget build(BuildContext context) {
    final isConnected = obd.isConnected;
    final isScanning = obd.state == OBDState.scanning;
    final isConnecting = obd.state == OBDState.connecting;
    final isBusy = isScanning || isConnecting;
    final hasResults = obd.scanResults.isNotEmpty;
    final hasError = obd.state == OBDState.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF00FF88).withValues(alpha: 0.3)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상태 헤더
          Row(
            children: [
              Icon(
                isConnected
                    ? Icons.bluetooth_connected
                    : isScanning
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_disabled,
                size: 22,
                color: isConnected
                    ? const Color(0xFF00FF88)
                    : isBusy
                        ? Colors.orange
                        : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isConnected
                      ? '${obd.scanResults.isNotEmpty ? obd.scanResults.first.device.platformName : "OBD2"} 연결됨'
                      : isConnecting
                          ? '연결 중...'
                          : isScanning
                              ? '기기 탐색 중... (30초)'
                              : 'OBD 미연결',
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isConnected
                        ? const Color(0xFF00FF88)
                        : isBusy
                            ? Colors.orange
                            : Colors.white54,
                  ),
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.orange),
                ),
            ],
          ),

          // 에러 메시지
          if (hasError && obd.errorMsg != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                obd.errorMsg!,
                style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.red),
              ),
            ),
          ],

          // 스캔 결과 기기 목록
          if ((isScanning || hasError) && hasResults) ...[
            const SizedBox(height: 12),
            Text(
              '발견된 기기 ${obd.scanResults.length}개 — 탭하면 연결',
              style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  color: Colors.white38,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            ...obd.scanResults.map((r) {
              final name = r.device.platformName;
              final isObd = OBDService.isObdDeviceName(name);
              return GestureDetector(
                onTap: () => obd.connectToDevice(r.device),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isObd
                        ? AppColors.red.withValues(alpha: 0.1)
                        : AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isObd
                          ? AppColors.red.withValues(alpha: 0.4)
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bluetooth,
                        size: 14,
                        color: isObd ? AppColors.red : Colors.white24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isObd ? Colors.white : Colors.white54,
                          ),
                        ),
                      ),
                      Text(
                        '${r.rssi} dBm',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10, color: Colors.white24),
                      ),
                      if (isObd) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OBD',
                            style: GoogleFonts.rajdhani(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 14),

          // 메인 버튼
          if (!isBusy)
            GestureDetector(
              onTap: isConnected ? obd.disconnect : obd.connect,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.transparent : AppColors.red,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.red),
                ),
                child: Center(
                  child: Text(
                    isConnected ? '연결 해제' : 'OBD 연결하기',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isConnected ? AppColors.red : Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            )
          else if (isScanning)
            GestureDetector(
              onTap: obd.disconnect,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Text(
                    '탐색 취소',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
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
                color: AppColors.red.withValues(alpha: 0.15),
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
