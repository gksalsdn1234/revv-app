import '../models/run_session.dart';
import '../models/run_summary.dart';
import '../models/revv_route.dart';
import '../models/loop_route.dart';
import 'supabase_service.dart';

class RevvAiService {
  static final RevvAiService _instance = RevvAiService._internal();
  factory RevvAiService() => _instance;
  RevvAiService._internal();

  static const _fallback = '잘 들었어요. 안전하게 달려요.';
  bool lastRequestFailed = false;

  Future<String> _callClaude({
    required String model,
    required String system,
    required List<Map<String, String>> messages,
    int maxTokens = 200,
  }) async {
    final data = await SupabaseService().invokeFunction(
      'call-ai',
      body: {
        'model': model,
        'system': system,
        'messages': messages,
        'maxTokens': maxTokens,
      },
    );
    final text = (data?['text'] as String? ?? '').trim();
    if (text.isEmpty) throw StateError('AI function returned empty text');
    return text;
  }

  Future<String> ask(
    String userText, {
    double speedKmh = 0,
    String weather = '',
    String roadCondition = '',
    String? routeName,
    double? routeDistanceKm,
    double? lateralG,
    double? longitudinalG,
    int? rpm,
    int? coolantTempC,
    double? throttlePct,
  }) async {
    if (userText.isEmpty) return _fallback;
    try {
      final response = await _callClaude(
        model: 'claude-sonnet-4-6',
        system:
            '너는 REVV, AI 코드라이버야. 드라이버와 짧게 소통해. 2문장 이내로, 한국어로, 핵심만 말해. 주행 안전을 최우선으로.',
        messages: [
          {
            'role': 'user',
            'content':
                '''현재 상태:
- 속도: ${speedKmh.toStringAsFixed(0)}km/h
- 날씨: $weather
- 노면: $roadCondition
${routeName != null ? '- 루트: $routeName\n' : ''}${routeDistanceKm != null ? '- 루트 거리: ${routeDistanceKm.toStringAsFixed(1)}km\n' : ''}${lateralG != null ? '- 횡G: ${lateralG.toStringAsFixed(2)}\n' : ''}${longitudinalG != null ? '- 종G: ${longitudinalG.toStringAsFixed(2)}\n' : ''}${rpm != null ? '- RPM: $rpm\n' : ''}${coolantTempC != null ? '- 냉각수: $coolantTempC°C\n' : ''}${throttlePct != null ? '- 스로틀: ${throttlePct.toStringAsFixed(0)}%\n' : ''}

드라이버: "$userText"''',
          },
        ],
        maxTokens: 100,
      );
      lastRequestFailed = false;
      return response;
    } catch (_) {}
    lastRequestFailed = true;
    return _fallback;
  }

  /// 주행 종료 후 자동 분석 리포트 생성
  /// [useHighQuality] OBD 연결 시 true → Sonnet, 미연결 → Haiku
  Future<String> analyzeRun(
    RunSession session, {
    bool useHighQuality = false,
  }) async {
    try {
      final dur = session.duration;
      final durStr = dur.inHours > 0
          ? '${dur.inHours}시간 ${dur.inMinutes % 60}분'
          : dur.inMinutes > 0
          ? '${dur.inMinutes}분 ${dur.inSeconds % 60}초'
          : '${dur.inSeconds}초';

      final totalSecs = session.driveModeSeconds.values.fold(
        0,
        (a, b) => a + b,
      );

      String modeStr;
      if (totalSecs > 0) {
        final cruise =
            ((session.driveModeSeconds['cruise'] ?? 0) / totalSecs * 100)
                .round();
        final winding =
            ((session.driveModeSeconds['winding'] ?? 0) / totalSecs * 100)
                .round();
        final sport =
            ((session.driveModeSeconds['sport'] ?? 0) / totalSecs * 100)
                .round();
        modeStr = 'CRUISE $cruise% / WINDING $winding% / SPORT $sport%';
      } else {
        modeStr = '데이터 없음';
      }

      final hasGData = session.maxLateralG > 0.01 || session.maxLonG > 0.01;
      final gStr = hasGData
          ? '최대 횡G ${session.maxLateralG.toStringAsFixed(2)}G / 최대 종G ${session.maxLonG.toStringAsFixed(2)}G / 급조작 ${session.sharpCorners.length}회'
          : 'G포스 데이터 없음 (실기기 필요)';

      final prompt =
          '''주행 데이터:
- 루트: ${session.routeName}
- 거리: ${session.distanceKm.toStringAsFixed(2)} km
- 주행 시간: $durStr
- 최고 속도: ${session.maxSpeedKmh.toStringAsFixed(1)} km/h
- 평균 속도: ${session.avgSpeedKmh.toStringAsFixed(1)} km/h
- 날씨: ${session.weatherEmoji} ${session.tempDisplay} ${session.weatherDesc}
- G포스: $gStr
- 드라이빙 모드 비율: $modeStr''';

      return await _callClaude(
        model: useHighQuality
            ? 'claude-sonnet-4-6'
            : 'claude-haiku-4-5-20251001',
        system:
            '너는 REVV, AI 코드라이버야. 주행 데이터를 받아 드라이버에게 짧고 솔직한 피드백을 줘. '
            '3문장 이내. 한국어. 구체적인 수치를 인용해. 칭찬과 개선점을 균형있게. '
            '앱스토어 규정상 과속·위험 운전을 조장하는 표현은 절대 쓰지 마.',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: useHighQuality ? 260 : 180,
      );
    } catch (_) {}
    return _buildFallbackAnalysis(session);
  }

  /// 상세 AI 코칭 리포트 — 런카드 "상세 분석" 버튼에서 호출
  /// [useHighQuality] OBD 연결 시 true → Sonnet
  Future<String> analyzeRunDetailed(
    RunSession session, {
    bool useHighQuality = false,
  }) async {
    try {
      final dur = session.duration;
      final durStr = dur.inHours > 0
          ? '${dur.inHours}시간 ${dur.inMinutes % 60}분'
          : '${dur.inMinutes}분';

      final totalSecs = session.driveModeSeconds.values.fold(
        0,
        (a, b) => a + b,
      );
      String modeStr;
      if (totalSecs > 0) {
        final cruise =
            ((session.driveModeSeconds['cruise'] ?? 0) / totalSecs * 100)
                .round();
        final winding =
            ((session.driveModeSeconds['winding'] ?? 0) / totalSecs * 100)
                .round();
        final sport =
            ((session.driveModeSeconds['sport'] ?? 0) / totalSecs * 100)
                .round();
        modeStr = 'CRUISE $cruise% / WINDING $winding% / SPORT $sport%';
      } else {
        modeStr = '데이터 없음';
      }

      final hasG = session.maxLateralG > 0.01;
      final sharpCount = session.sharpCorners.length;

      String styleLabel;
      if (!hasG) {
        styleLabel = '미측정';
      } else if (session.maxLateralG < 0.25) {
        styleLabel = 'CRUISER (0.25G 미만)';
      } else if (session.maxLateralG < 0.45) {
        styleLabel = 'SPORT (0.25~0.45G)';
      } else {
        styleLabel = 'RACER (0.45G 초과)';
      }

      final prompt =
          '''다음 주행 데이터를 바탕으로 드라이버에게 상세 코칭 리포트를 작성해줘.

[주행 데이터]
- 루트: ${session.routeName}
- 거리: ${session.distanceKm.toStringAsFixed(2)} km / 시간: $durStr
- 최고속도: ${session.maxSpeedKmh.toStringAsFixed(1)} km/h / 평균: ${session.avgSpeedKmh.toStringAsFixed(1)} km/h
- 드라이빙 스타일: $styleLabel
- 최대 횡G: ${hasG ? '${session.maxLateralG.toStringAsFixed(2)}G' : '미측정'}
- 최대 종G: ${hasG ? '${session.maxLonG.toStringAsFixed(2)}G' : '미측정'}
- 급조작 횟수: ${hasG ? '$sharpCount회 (0.45G 초과)' : '미측정'}
- 드라이빙 모드: $modeStr
- 날씨: ${session.weatherEmoji} ${session.tempDisplay}

[요청 형식]
아래 3개 섹션으로 구성해줘. 각 섹션은 이모지 + 한 줄 제목 + 2~3문장 내용.
1. 💪 오늘의 하이라이트 — 잘한 점
2. 🎯 개선 포인트 — 구체적인 개선 제안
3. 🗺️ 다음 목표 — 다음 드라이브에 도전할 것
총 8~10문장, 한국어, 수치를 적극 활용. 앱스토어 규정상 과속·위험 표현 절대 금지.''';

      return await _callClaude(
        model: useHighQuality
            ? 'claude-sonnet-4-6'
            : 'claude-haiku-4-5-20251001',
        system:
            '너는 REVV, AI 드라이빙 코치야. 주행 데이터를 분석하여 드라이버 성장에 도움이 되는 구체적이고 따뜻한 피드백을 준다. '
            '앱스토어 규정 준수: 과속·위험 운전 조장 표현 절대 금지.',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: useHighQuality ? 700 : 500,
      );
    } catch (_) {}
    return _buildDetailedFallback(session);
  }

  String _buildDetailedFallback(RunSession session) {
    final km = session.distanceKm;
    final sharpCount = session.sharpCorners.length;
    final hasG = session.maxLateralG > 0.01;
    final buf = StringBuffer();
    buf.writeln('💪 오늘의 하이라이트');
    buf.writeln('${km.toStringAsFixed(1)}km 완주, 수고했어요!');
    if (hasG) {
      buf.writeln('최대 횡G ${session.maxLateralG.toStringAsFixed(2)}G를 기록했네요.');
    }
    buf.writeln();
    buf.writeln('🎯 개선 포인트');
    if (sharpCount > 3) {
      buf.writeln('급조작이 $sharpCount회 감지됐어요. 코너 진입 전 미리 속도를 조정해보세요.');
    } else {
      buf.writeln('코너링이 안정적이에요. 루트 변경으로 새로운 코너를 경험해보세요.');
    }
    buf.writeln();
    buf.writeln('🗺️ 다음 목표');
    buf.writeln('같은 루트를 다시 달리면 더 자연스러운 흐름을 느낄 수 있어요. 도전해보세요!');
    return buf.toString();
  }

  /// 전체 주행 히스토리 기반 드라이버 종합 분석
  Future<String> analyzeHistory(List<RunSummary> history) async {
    if (history.isEmpty) return '아직 주행 기록이 없어요. 첫 드라이브를 시작해보세요!';

    final totalRuns = history.length;
    final totalDistKm = history.fold(0.0, (s, r) => s + r.distanceKm);
    final totalSecs = history.fold(0, (s, r) => s + r.durationSeconds);
    final avgDistKm = totalDistKm / totalRuns;
    final avgDurMin = (totalSecs / totalRuns / 60).round();

    final gRuns = history
        .where((r) => r.maxLateralG != null && r.maxLateralG! > 0.01)
        .toList();
    final bestG = gRuns.isEmpty
        ? null
        : gRuns.map((r) => r.maxLateralG!).reduce((a, b) => a > b ? a : b);
    final avgG = gRuns.isEmpty
        ? null
        : gRuns.map((r) => r.maxLateralG!).fold(0.0, (a, b) => a + b) /
              gRuns.length;
    final totalSharp = history.fold(0, (s, r) => s + r.sharpCornersCount);

    final routeCount = <String, int>{};
    for (final r in history) {
      if (r.routeId != null) {
        routeCount[r.routeName] = (routeCount[r.routeName] ?? 0) + 1;
      }
    }
    final favoriteRoute = routeCount.isEmpty
        ? null
        : routeCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    double? runsPerWeek;
    if (history.length >= 2) {
      final oldest = history
          .map((r) => r.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final daysDiff = DateTime.now().difference(oldest).inDays;
      if (daysDiff > 0) runsPerWeek = totalRuns / (daysDiff / 7);
    }

    final recent = history
        .take(5)
        .map((r) {
          final dur = r.durationSeconds ~/ 60;
          final gStr = r.maxLateralG != null && r.maxLateralG! > 0.01
              ? '횡G ${r.maxLateralG!.toStringAsFixed(2)}G'
              : 'G미측정';
          return '${r.date.month}/${r.date.day} ${r.routeName} ${r.distanceKm.toStringAsFixed(1)}km $dur분 $gStr 급조작${r.sharpCornersCount}회';
        })
        .join('\n');

    final totalHrs = totalSecs ~/ 3600;
    final totalMin = (totalSecs % 3600) ~/ 60;
    final timeStr = totalHrs > 0 ? '$totalHrs시간 $totalMin분' : '$totalMin분';

    final prompt =
        '''[드라이버 전체 주행 기록]
- 총 드라이브: $totalRuns회
- 누적 거리: ${totalDistKm.toStringAsFixed(1)} km
- 누적 주행시간: $timeStr
- 평균 거리/회: ${avgDistKm.toStringAsFixed(1)} km
- 평균 시간/회: $avgDurMin분
${bestG != null ? '- 베스트 횡G: ${bestG.toStringAsFixed(2)}G' : ''}
${avgG != null ? '- 평균 횡G: ${avgG.toStringAsFixed(2)}G (${gRuns.length}회 측정)' : ''}
- 총 급조작: $totalSharp회 (평균 ${totalRuns > 0 ? (totalSharp / totalRuns).toStringAsFixed(1) : 0}회/런)
${favoriteRoute != null ? '- 자주 찾는 루트: $favoriteRoute (${routeCount[favoriteRoute]}회)' : ''}
${runsPerWeek != null ? '- 주행 빈도: 주 ${runsPerWeek.toStringAsFixed(1)}회' : ''}

[최근 5개 드라이브]
$recent

[요청]
이 드라이버의 전체적인 드라이빙 프로필을 분석해줘. 아래 4개 섹션으로 구성:
1. 🏁 드라이버 프로필 — 전체적인 주행 스타일 특성 (2~3문장)
2. 💪 강점 — 데이터에서 보이는 잘하는 점 (2문장)
3. 🎯 개선 포인트 — 구체적 수치 기반 개선 제안 (2문장)
4. 🗺️ 다음 도전 — 성장을 위한 다음 목표 (2문장)
총 8~10문장, 한국어, 수치 적극 활용. 과속·위험 운전 조장 표현 절대 금지.''';

    try {
      return await _callClaude(
        model: 'claude-sonnet-4-6',
        system:
            '너는 REVV, AI 드라이빙 코치야. 누적 주행 데이터를 분석해 드라이버 성장을 돕는 통찰력 있는 피드백을 한국어로 제공한다. 앱스토어 규정 준수: 과속·위험 운전 조장 표현 절대 금지.',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: 700,
      );
    } catch (_) {}

    final buf = StringBuffer();
    buf.writeln('🏁 드라이버 프로필');
    buf.writeln(
      '총 $totalRuns회, ${totalDistKm.toStringAsFixed(1)}km를 달려온 드라이버예요.',
    );
    buf.writeln();
    buf.writeln('💪 강점');
    buf.writeln(
      '꾸준히 드라이브를 이어가고 있어요. 평균 ${avgDistKm.toStringAsFixed(1)}km의 일관된 드라이브가 인상적이에요.',
    );
    buf.writeln();
    buf.writeln('🎯 개선 포인트');
    buf.writeln(
      totalSharp > totalRuns * 3
          ? '급조작이 평균 ${(totalSharp / totalRuns).toStringAsFixed(1)}회/런으로 다소 많아요. 코너 진입 전 속도 조정을 의식해보세요.'
          : '급조작 빈도가 안정적이에요. 다양한 루트에 도전해 경험을 넓혀보세요.',
    );
    buf.writeln();
    buf.writeln('🗺️ 다음 도전');
    buf.writeln('새로운 루트를 탐색하며 드라이빙 반경을 넓혀보세요. REVV가 좋은 길을 찾아드릴게요!');
    return buf.toString();
  }

  // ──────────────────────────────────────────────────────────────
  // AI 루트 닉네임 — 북마크하거나 3회 이상 달린 특별한 루트에만 부여
  // ──────────────────────────────────────────────────────────────
  static final Map<String, String> _nameCache = {};

  /// 루트 닉네임 생성. 이미 닉네임이 있으면 캐시값 반환.
  Future<String?> nameRoute(RevvRoute route) async {
    if (_nameCache.containsKey(route.id)) return _nameCache[route.id];
    try {
      final result = await _callClaude(
        model: 'claude-haiku-4-5-20251001',
        system:
            '너는 드라이빙 루트 닉네임 메이커야. 자주 달리거나 좋아하는 루트에 드라이버만의 별명을 지어준다. 한국어 4~7글자. 이름만 반환. 설명 금지.',
        messages: [
          {
            'role': 'user',
            'content':
                '거리: ${route.distanceKm.toStringAsFixed(0)}km / 커브: ${route.curveStyle} / 점수: ${route.windingScore.toStringAsFixed(1)} / 난이도: ${route.difficultyLabel} / 기존이름: ${route.name}',
          },
        ],
        maxTokens: 15,
      );
      if (result.isNotEmpty) {
        _nameCache[route.id] = result;
        return result;
      }
    } catch (_) {}
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // LOOP 루트 AI 소개 (Haiku, 120 tokens)
  // ──────────────────────────────────────────────────────────────

  Future<String> describeLoop(
    LoopRoute loop, {
    String weatherDesc = '맑음',
    String roadCondition = 'DRY',
    double tempCelsius = 20,
  }) async {
    try {
      final segs = loop.segments
          .take(3)
          .map((s) => '${s.name} ${s.distanceKm.toStringAsFixed(0)}km')
          .join(', ');
      return await _callClaude(
        model: 'claude-haiku-4-5-20251001',
        system:
            '너는 REVV 앱의 AI 코파일럿이야. 순환 드라이빙 루트를 2~3문장으로 임팩트 있게 소개해. 날씨/노면 반영. 한국어. 짧게.',
        messages: [
          {
            'role': 'user',
            'content':
                '총거리: ${loop.totalKm.toStringAsFixed(0)}km / 구간: ${loop.segments.length}개 ($segs) / 평균점수: ${loop.windingScore.toStringAsFixed(1)} / 날씨: $weatherDesc ${tempCelsius.toStringAsFixed(0)}°C 노면: $roadCondition',
          },
        ],
        maxTokens: 120,
      );
    } catch (_) {}
    return '총 ${loop.totalDisplay} 순환 루트예요. ${loop.segments.length}개 와인딩 구간을 연결했어요. 오늘 노면 $roadCondition — 즐거운 드라이브 되세요.';
  }

  // ──────────────────────────────────────────────────────────────
  // 런카드 SNS 공유 캡션 생성 (Haiku, 80 tokens)
  // ──────────────────────────────────────────────────────────────

  Future<String> generateShareCaption(RunSession session) async {
    try {
      final dur = session.duration.inMinutes;
      final hasG = session.maxLateralG > 0.01;
      final gStr = hasG ? '최대G ${session.maxLateralG.toStringAsFixed(2)}G' : '';
      return await _callClaude(
        model: 'claude-haiku-4-5-20251001',
        system:
            '너는 REVV 앱의 AI야. SNS 공유용 드라이빙 후기를 2문장으로 작성해. 한국어. 이모지 1~2개. 수치 활용. 과속 조장 표현 금지.',
        messages: [
          {
            'role': 'user',
            'content':
                '루트: ${session.routeName} / 거리: ${session.distanceKm.toStringAsFixed(1)}km / 시간: $dur분 ${hasG ? gStr : ""}',
          },
        ],
        maxTokens: 80,
      );
    } catch (_) {}
    return 'REVV — ${session.routeName} ${session.distanceKm.toStringAsFixed(1)}km 완주 🏁';
  }

  String _buildFallbackAnalysis(RunSession session) {
    final km = session.distanceKm;
    final min = session.duration.inMinutes;
    final totalSecs = session.driveModeSeconds.values.fold(0, (a, b) => a + b);
    final sportSecs = session.driveModeSeconds['sport'] ?? 0;
    final sportPct = totalSecs > 0 ? (sportSecs / totalSecs * 100).round() : 0;

    if (sportPct >= 30) {
      return '${km.toStringAsFixed(1)}km, $min분 — 오늘 꽤 격한 드라이빙이었네요. SPORT 모드가 $sportPct%였어요. 다음엔 조금 여유있게 달려봐요.';
    }
    if (km >= 30) {
      return '${km.toStringAsFixed(1)}km, $min분 — 오늘 긴 코스 수고했어요. 꾸준히 달리는 것 자체가 실력이에요.';
    }
    if (km >= 10) {
      return '${km.toStringAsFixed(1)}km 완주. 이 코스 마음에 드셨나요? 같은 코스를 반복하면 더 자연스러워져요.';
    }
    return '짧지만 의미있는 드라이브였어요. 다음엔 조금 더 멀리 나가봐요.';
  }
}
