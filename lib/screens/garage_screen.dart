import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/garage_service.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GarageScreen()),
    );
  }

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  final _nameFocus   = FocusNode();
  final _nameCtrl    = TextEditingController();
  final _hpCtrl      = TextEditingController();
  final _weightCtrl  = TextEditingController();
  final _tireCtrl    = TextEditingController();
  String _fuel = FuelType.gasoline;

  // 타이어 폭 프리셋 (mm)
  static const _tirePresets = [195, 205, 215, 225, 235, 245, 255, 265];

  double get _latG {
    final t = int.tryParse(_tireCtrl.text) ?? 225;
    return (0.95 * t / 225.0).clamp(0.55, 1.85);
  }

  double get _lonG {
    final t = int.tryParse(_tireCtrl.text) ?? 225;
    return (0.75 * t / 225.0).clamp(0.45, 1.40);
  }

  @override
  void initState() {
    super.initState();
    final svc = context.read<GarageService>();
    _nameCtrl.text   = svc.vehicleName;
    _hpCtrl.text     = svc.horsepowerHp > 0 ? '${svc.horsepowerHp}' : '';
    _weightCtrl.text = svc.weightKg > 0 ? '${svc.weightKg}' : '';
    _tireCtrl.text   = '${svc.tireWidth}';
    _fuel            = svc.fuelType;

    _tireCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hpCtrl.dispose();
    _weightCtrl.dispose();
    _tireCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final svc = context.read<GarageService>();
    await svc.save(
      name:   _nameCtrl.text.trim(),
      hp:     int.tryParse(_hpCtrl.text) ?? 0,
      weight: int.tryParse(_weightCtrl.text) ?? 1400,
      tire:   int.tryParse(_tireCtrl.text) ?? 225,
      fuel:   _fuel,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final safePad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // ── 앱바 ──────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16, safePad.top + 12, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white54),
                ),
                const SizedBox(width: 14),
                Text(
                  'GARAGE PRO',
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                // 차량 이모지
                Text(
                  _fuelEmoji(_fuel),
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
          // ── 폼 ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 20, 16, safePad.bottom + 24),
              children: [
                // 차량 기본 정보
                _SectionHeader('차량 기본 정보'),
                const SizedBox(height: 12),
                _Field(
                  label: '차종',
                  hint: 'e.g. Honda Civic Type R',
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        label: '마력 (HP)',
                        hint: '예) 320',
                        controller: _hpCtrl,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Field(
                        label: '차량 무게 (kg)',
                        hint: '예) 1400',
                        controller: _weightCtrl,
                        isNumber: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 연료 타입
                _SectionHeader('연료 타입'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FuelType.gasoline,
                    FuelType.diesel,
                    FuelType.ev,
                  ].map((f) {
                    final active = _fuel == f;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _fuel = f),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.red.withValues(alpha: 0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: active ? AppColors.red : Colors.white12,
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(FuelType.emoji(f),
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(height: 4),
                              Text(
                                FuelType.label(f),
                                style: GoogleFonts.rajdhani(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: active ? AppColors.red : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // 타이어 폭
                _SectionHeader('타이어 폭 (mm)'),
                const SizedBox(height: 12),
                _Field(
                  label: '폭 (mm)',
                  hint: '예) 225',
                  controller: _tireCtrl,
                  isNumber: true,
                ),
                const SizedBox(height: 10),
                // 프리셋 칩
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tirePresets.map((mm) {
                    final current = int.tryParse(_tireCtrl.text) == mm;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _tireCtrl.text = '$mm');
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: current
                              ? AppColors.red.withValues(alpha: 0.18)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: current ? AppColors.red : Colors.white12,
                          ),
                        ),
                        child: Text(
                          '$mm',
                          style: GoogleFonts.orbitron(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: current ? AppColors.red : Colors.white38,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // G-force 임계치 미리보기
                _SectionHeader('G-FORCE 임계치 (예상)'),
                const SizedBox(height: 12),
                _GThresholdCard(latG: _latG, lonG: _lonG),
                const SizedBox(height: 28),

                // 저장 버튼
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.red.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'SAVE',
                        style: GoogleFonts.orbitron(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fuelEmoji(String f) => FuelType.emoji(f);
}

// ── 섹션 헤더 ──────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppColors.red,
        letterSpacing: 2,
      ),
    );
  }
}

// ── 텍스트 필드 ────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool isNumber;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.isNumber = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textHint,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: isNumber
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          style: GoogleFonts.orbitron(fontSize: 13, color: Colors.white),
          cursorColor: AppColors.red,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.rajdhani(fontSize: 13, color: Colors.white24),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.red.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── G-force 임계치 미리보기 카드 ──────────────────────────────
class _GThresholdCard extends StatelessWidget {
  final double latG;
  final double lonG;
  const _GThresholdCard({required this.latG, required this.lonG});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _GVal(label: '횡G 한계', value: latG, color: const Color(0xFFF97316)),
          Container(width: 1, height: 44, color: Colors.white12,
              margin: const EdgeInsets.symmetric(horizontal: 16)),
          _GVal(label: '종G 한계', value: lonG, color: const Color(0xFF3B82F6)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '타이어 폭 기반 추정값입니다. 실제 차량과 다를 수 있어요.',
              style: GoogleFonts.rajdhani(fontSize: 9, color: Colors.white24),
            ),
          ),
        ],
      ),
    );
  }
}

class _GVal extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _GVal({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${value.toStringAsFixed(2)}g',
          style: GoogleFonts.orbitron(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}
