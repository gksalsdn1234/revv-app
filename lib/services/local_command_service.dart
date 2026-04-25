import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'location_service.dart';
import 'weather_service.dart';
import 'route_service.dart';
import 'obd_service.dart';
import 'settings_service.dart';

/// 로컬에서 처리 가능한 명령 인텐트
/// → 패턴 매칭으로 즉시 응답, null이면 AI로 폴백
class LocalCommandService {
  static String? handle(BuildContext context, String text) {
    final t = text.toLowerCase();

    // ── 날씨 ──────────────────────────────────────────────────
    if (_any(t, ['날씨', '기온', '온도', '비', '눈', '맑', '흐림', '노면'])) {
      final w = context.read<WeatherService>();
      return '현재 ${w.tempDisplay}, ${w.weatherDesc}. ${w.weatherBriefLine}';
    }

    // ── 속도 ──────────────────────────────────────────────────
    if (_any(t, ['속도', '얼마나 빨리', '빠르기', '몇 키로'])) {
      final spd = context.read<LocationService>().speedKmh;
      return '현재 속도 ${spd.toStringAsFixed(0)} 킬로미터입니다.';
    }

    // ── 시간 ──────────────────────────────────────────────────
    if (_any(t, ['몇 시', '시간', '시각', '지금 몇'])) {
      final now = TimeOfDay.now();
      final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
      final ampm = now.period == DayPeriod.am ? '오전' : '오후';
      final m = now.minute.toString().padLeft(2, '0');
      return '$ampm $h시 $m분이에요.';
    }

    // ── 루트 정보 ─────────────────────────────────────────────
    if (_any(t, ['루트', '코스', '경로'])) {
      final svc = context.read<RouteService>();
      if (_any(t, ['찾아', '탐색', '검색', '추천'])) {
        // 루트 재탐색 트리거
        final loc = context.read<LocationService>();
        svc.changeRadius(svc.searchRadiusKm, loc.lat, loc.lng);
        return '루트 탐색을 시작할게요.';
      }
      final route = svc.selectedRoute;
      if (route == null) return '선택된 루트가 없어요.';
      return '현재 루트 ${route.name}, ${route.distanceDisplay}, 예상 ${route.durationDisplay}이에요.';
    }

    // ── OBD ───────────────────────────────────────────────────
    if (_any(t, ['rpm', '알피엠', '엔진', '스로틀', '냉각수', '연료', '오비디', 'obd'])) {
      final obd = context.read<OBDService>();
      if (!obd.isConnected) return 'OBD가 연결되어 있지 않아요.';
      final d = obd.data;
      if (d == null) return 'OBD 데이터를 읽는 중이에요.';
      final parts = <String>[];
      if (d.rpm != null) parts.add('RPM ${d.rpm}');
      if (d.coolantTempC != null) parts.add('냉각수 ${d.coolantTempC}도');
      if (d.throttlePct != null) {
        parts.add('스로틀 ${d.throttlePct!.toStringAsFixed(0)}퍼센트');
      }
      return parts.isEmpty ? '데이터가 없어요.' : parts.join(', ');
    }

    // ── 음소거 토글 ───────────────────────────────────────────
    if (_any(t, ['음소거', '조용히', '소리 꺼', '뮤트'])) {
      context.read<SettingsService>().setTtsMuted(true);
      return null; // TTS로 응답하면 모순 → 무음 처리
    }
    if (_any(t, ['소리 켜', '음소거 해제', '언뮤트', '들려줘'])) {
      context.read<SettingsService>().setTtsMuted(false);
      return '소리를 켤게요.';
    }

    // ── 위치 ─────────────────────────────────────────────────
    if (_any(t, ['지금 어디', '현재 위치', '내 위치', '여기 어디'])) {
      return '현재 위치는 화면 지도에서 확인해 주세요.';
    }

    // ── 처리 불가 → AI 폴백 ──────────────────────────────────
    return null;
  }

  static bool _any(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
