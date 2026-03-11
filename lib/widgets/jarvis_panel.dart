import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/jarvis_service.dart';

class JarvisPanel extends StatefulWidget {
  const JarvisPanel({super.key});

  @override
  State<JarvisPanel> createState() => _JarvisPanelState();
}

class _JarvisPanelState extends State<JarvisPanel>
    with SingleTickerProviderStateMixin {
  String _displayText = '';
  int _charIndex = 0;
  bool _typing = false;
  String _currentLine = '';
  Timer? _typeTimer;
  late AnimationController _cursor;
  String? _lastSpoken;

  @override
  void initState() {
    super.initState();
    _cursor = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  void _startTyping(String line) {
    _typeTimer?.cancel();
    _currentLine = line;
    _charIndex = 0;
    _displayText = '';
    _typing = true;
    _cursor.repeat(reverse: true); // 타이핑 시작할 때만 커서 애니메이션

    _typeTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) {
        if (!mounted) return;
        if (_charIndex < _currentLine.length) {
          setState(() {
            _displayText += _currentLine[_charIndex];
            _charIndex++;
          });
        } else {
          _typeTimer?.cancel();
          if (mounted) {
            setState(() => _typing = false);
            _cursor.stop(); // 타이핑 끝나면 커서 정지
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JarvisService>(
      builder: (context, jarvis, _) {
        if (jarvis.lastSpoken != null && jarvis.lastSpoken != _lastSpoken) {
          _lastSpoken = jarvis.lastSpoken;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _startTyping(jarvis.lastSpoken!));
        }

        return Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(top: BorderSide(color: AppColors.red, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'JARVIS',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                      letterSpacing: 4,
                    ),
                  ),
                  if (jarvis.isSpeaking) ...[
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _cursor,
                      builder: (_, __) => Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.red.withOpacity(_cursor.value),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _displayText.isEmpty
                    ? Text(
                        '마이크 버튼을 누르고 말해보세요',
                        style: GoogleFonts.rajdhani(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.25),
                        ),
                      )
                    : AnimatedBuilder(
                        animation: _cursor,
                        builder: (_, __) => RichText(
                          text: TextSpan(
                            style: GoogleFonts.rajdhani(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            children: [
                              TextSpan(text: _displayText),
                              if (_typing)
                                TextSpan(
                                  text: '|',
                                  style: TextStyle(
                                    color: AppColors.red
                                        .withOpacity(_cursor.value),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
