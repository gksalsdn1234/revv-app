import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/audio_service.dart';
import '../services/stt_service.dart';
import '../services/revv_ai_service.dart';
import '../services/jarvis_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';

class MicButton extends StatefulWidget {
  const MicButton({super.key});

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with TickerProviderStateMixin {
  bool _isListening = false;
  bool _isProcessing = false;

  late List<AnimationController> _barControllers;
  late List<Animation<double>> _barAnims;
  static const int _barCount = 5;

  @override
  void initState() {
    super.initState();
    _barControllers = List.generate(_barCount, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + i * 70),
      );
    });
    _barAnims = _barControllers.map((ctrl) {
      return Tween<double>(
        begin: 4,
        end: 24,
      ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _barControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _startWave() {
    for (int i = 0; i < _barCount; i++) {
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (mounted && _isListening) {
          _barControllers[i].repeat(reverse: true);
        }
      });
    }
  }

  void _stopWave() {
    for (final c in _barControllers) {
      c.stop();
      c.reset();
    }
  }

  Future<void> _onPressDown() async {
    if (_isProcessing) return;
    await AudioService().playBeep();
    await SttService().startListening();
    if (mounted) setState(() => _isListening = true);
    _startWave();
  }

  Future<void> _onPressUp() async {
    if (!_isListening) return;
    setState(() {
      _isListening = false;
      _isProcessing = true;
    });
    _stopWave();

    final text = await SttService().stopListening();

    if (text.isNotEmpty && mounted) {
      final loc = context.read<LocationService>();
      final weather = context.read<WeatherService>();
      final jarvis = context.read<JarvisService>();

      final response = await RevvAiService().ask(
        text,
        speedKmh: loc.speedKmh,
        weather: weather.weatherDesc,
        roadCondition: weather.roadCondition,
      );

      if (mounted) jarvis.speak(response);
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isListening || _isProcessing;

    return GestureDetector(
      onTapDown: (_) => _onPressDown(),
      onTapUp: (_) => _onPressUp(),
      onTapCancel: () => _onPressUp(),
      // AnimatedContainer → Container: implicit animation이
      // layout phase에서 크기 변경 → !_debugDoingThisLayout 유발 가능
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? AppColors.red : AppColors.panel,
          border: Border.all(
            color: isActive
                ? AppColors.red
                : AppColors.red.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.5),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: isActive
            ? (_isListening
                  ? _WaveformBars(barAnims: _barAnims)
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ))
            : const Icon(Icons.mic, color: AppColors.red, size: 24),
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final List<Animation<double>> barAnims;
  const _WaveformBars({required this.barAnims});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(barAnims),
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barAnims.length, (i) {
            final h = barAnims[i].value.clamp(4.0, 24.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
