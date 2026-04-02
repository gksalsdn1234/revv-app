import '../models/revv_route.dart';

enum JarvisPersona { engineer, friendly }

class JarvisScript {
  static String _tone(JarvisPersona persona, String engineer, String friendly) {
    return persona == JarvisPersona.friendly ? friendly : engineer;
  }

  static String sessionStart(
    RevvRoute? route,
    String roadCondition,
    JarvisPersona persona, {
    double? firstCornerKm,
  }) {
    final routeText = route?.name ?? '자유 드라이빙';
    final cornerText = firstCornerKm != null && firstCornerKm > 0
        ? '첫 코너는 ${firstCornerKm.toStringAsFixed(1)}km 앞이에요.'
        : '오늘도 안정적으로 시작해볼게요.';
    return _tone(
      persona,
      '$routeText 진입 준비 완료. 노면은 $roadCondition 상태입니다. $cornerText',
      '$routeText 출발해요. 노면은 $roadCondition 느낌이고, $cornerText',
    );
  }

  static String routeEntry(
    double distanceKm,
    int hairpin,
    int sharp,
    double firstCornerM,
    JarvisPersona persona,
  ) {
    return _tone(
      persona,
      '${distanceKm.toStringAsFixed(1)}km 루트 진입. 헤어핀 $hairpin개, 급코너 $sharp개 예상됩니다.',
      '${distanceKm.toStringAsFixed(1)}km 코스에 들어왔어요. 재밌게 달리되 무리하지는 말아요.',
    );
  }

  static String offRoute(JarvisPersona persona) => _tone(
        persona,
        '루트에서 벗어났습니다. 안전한 지점에서 복귀 경로를 확인하세요.',
        '잠깐 루트를 벗어났어요. 괜찮아요, 다시 맞춰볼게요.',
      );

  static String onRoute(JarvisPersona persona) => _tone(
        persona,
        '루트로 복귀했습니다. 계속 진행하세요.',
        '좋아요, 다시 루트로 돌아왔어요.',
      );

  static String sportMode(JarvisPersona persona) => _tone(
        persona,
        'SPORT 모드 감지. 입력은 부드럽게 유지하세요.',
        '오, 페이스가 올라오네요. 그래도 부드럽게 가요.',
      );

  static String sessionEnd(double distanceKm, int sharpCorners, JarvisPersona persona) => _tone(
        persona,
        '${distanceKm.toStringAsFixed(1)}km 주행 종료. 급조작 $sharpCorners회 기록했습니다.',
        '${distanceKm.toStringAsFixed(1)}km 수고했어요. 오늘 급한 조작은 $sharpCorners번 정도였네요.',
      );
}
