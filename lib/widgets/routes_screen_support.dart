import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../services/loop_route_service.dart';
import '../services/route_loading_policy.dart';
import '../services/route_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

class RoutesRadiusButton extends StatelessWidget {
  final int km;
  final bool active;

  const RoutesRadiusButton({super.key, required this.km, required this.active});

  @override
  Widget build(BuildContext context) {
    return RoutesTapScale(
      onTap: () {
        final loc = context.read<LocationService>();
        context.read<RouteService>().changeRadius(km, loc.lat, loc.lng);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? AppColors.primaryContainer
                : AppColors.outlineVariant.withValues(alpha: 0.36),
            width: 1,
          ),
        ),
        child: Text(
          km == 30
              ? 'NEAR'
              : km == 50
              ? 'MID'
              : 'FAR',
          style: AppText.technicalLabel(
            size: 9,
            color: active ? AppColors.onPrimary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

class RoutesLimitButton extends StatelessWidget {
  final int count;
  final bool active;

  const RoutesLimitButton({
    super.key,
    required this.count,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return RoutesTapScale(
      onTap: () {
        final loc = context.read<LocationService>();
        context.read<RouteService>().changeVisibleRouteLimit(
          count,
          loc.lat,
          loc.lng,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? AppColors.primaryContainer
                : AppColors.outlineVariant.withValues(alpha: 0.36),
            width: 1,
          ),
        ),
        child: Text(
          count >= maximumVisibleRoutes ? 'ALL' : '$count',
          style: AppText.technicalLabel(
            size: 9,
            color: active ? AppColors.onPrimary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

class RoutesBriefingText extends StatefulWidget {
  final String text;

  const RoutesBriefingText(this.text, {super.key});

  @override
  State<RoutesBriefingText> createState() => _RoutesBriefingTextState();
}

class _RoutesBriefingTextState extends State<RoutesBriefingText> {
  String _displayed = '';
  int _charIdx = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(RoutesBriefingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _charIdx = 0;
      _displayed = '';
      _startTyping();
    }
  }

  void _startTyping() {
    Future.doWhile(() async {
      if (!mounted) return false;
      if (_charIdx >= widget.text.length) return false;
      await Future.delayed(const Duration(milliseconds: 22));
      if (!mounted) return false;
      setState(() {
        _charIdx++;
        _displayed = widget.text.substring(0, _charIdx);
      });
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayed,
      style: GoogleFonts.rajdhani(
        fontSize: 11.5,
        color: Colors.white70,
        height: 1.45,
      ),
    );
  }
}

class RoutesTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const RoutesTapScale({super.key, required this.child, this.onTap});

  @override
  State<RoutesTapScale> createState() => _RoutesTapScaleState();
}

class _RoutesTapScaleState extends State<RoutesTapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class RoutesTabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const RoutesTabButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: RoutesTapScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 40,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: AppText.technicalLabel(
                size: 10,
                color: active ? AppColors.onPrimary : AppColors.textHint,
                letterSpacing: 2,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

class RoutesTooltipChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const RoutesTooltipChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class RoutesLoopTabPanel extends StatelessWidget {
  final LoopRouteService loopSvc;
  final int loopIdx;
  final bool loopFromHome;
  final String? loopBrief;
  final bool loopBriefLoading;
  final void Function(int) onLoopSelected;
  final void Function(bool) onHomeToggled;
  final VoidCallback onGo;

  const RoutesLoopTabPanel({
    super.key,
    required this.loopSvc,
    required this.loopIdx,
    required this.loopFromHome,
    this.loopBrief,
    this.loopBriefLoading = false,
    required this.onLoopSelected,
    required this.onHomeToggled,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final loops = loopSvc.loops;
    final loop = loops.isNotEmpty
        ? loops[loopIdx.clamp(0, loops.length - 1)]
        : null;
    final diffColor = loop != null
        ? routeDifficultyColor(loop.difficultyLevel)
        : AppColors.red;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF0141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: diffColor.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 3, color: diffColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.loop_rounded,
                      size: 14,
                      color: AppColors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LOOP',
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => onHomeToggled(!loopFromHome),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: loopFromHome
                              ? AppColors.red.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: loopFromHome
                                ? AppColors.red.withValues(alpha: 0.6)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.home_rounded,
                              size: 11,
                              color: loopFromHome
                                  ? AppColors.red
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '집 출발',
                              style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: loopFromHome
                                    ? AppColors.red
                                    : Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (loops.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Row(
                    children: List.generate(loops.length, (i) {
                      final selectedLoop = loops[i];
                      final active = i == loopIdx;
                      return GestureDetector(
                        onTap: () => onLoopSelected(i),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.red.withValues(alpha: 0.85)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: active ? AppColors.red : Colors.white12,
                            ),
                          ),
                          child: Text(
                            '${selectedLoop.targetKm}km',
                            style: GoogleFonts.orbitron(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: active ? Colors.white : AppColors.textHint,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              if (loopSvc.isBuilding)
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.red,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '루프 생성 중...',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                )
              else if (loop != null) ...[
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          RoutesTooltipChip(
                            icon: Icons.route_rounded,
                            label: loop.totalDisplay,
                          ),
                          const SizedBox(width: 8),
                          RoutesTooltipChip(
                            icon: Icons.map_rounded,
                            label: '${loop.segments.length}개 구간',
                          ),
                          const SizedBox(width: 8),
                          RoutesTooltipChip(
                            icon: Icons.star_rounded,
                            label: loop.scoreDisplay,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: diffColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: diffColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              loop.difficultyLabel,
                              style: GoogleFonts.orbitron(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: diffColor,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...loop.segments
                          .take(3)
                          .map(
                            (segment) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: routeDifficultyColor(
                                        segment.difficultyLevel,
                                      ),
                                      borderRadius: BorderRadius.circular(1.5),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      segment.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    segment.distanceDisplay,
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 10,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      if (loop.segments.length > 3)
                        Text(
                          '+${loop.segments.length - 3}개 더',
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      if (loopBriefLoading || loopBrief != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                          child: loopBriefLoading
                              ? Row(
                                  children: [
                                    const SizedBox(
                                      width: 9,
                                      height: 9,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.2,
                                        color: AppColors.red,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      'AI 소개 생성 중...',
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 10,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ],
                                )
                              : RoutesBriefingText(loopBrief!),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: onGo,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.red.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Text(
                                'GO',
                                style: GoogleFonts.orbitron(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Text(
                    '루트를 먼저 탐색해주세요.',
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color routeDifficultyColor(int level) {
  switch (level) {
    case 4:
      return const Color(0xFFEF4444);
    case 3:
      return const Color(0xFFF97316);
    case 2:
      return const Color(0xFFF59E0B);
    case 1:
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF60A5FA);
  }
}
