class RunData {
  final double distanceKm;
  final String routeName;
  final String weather;
  final String temperature;
  final String duration;
  final String jarvisComment;

  const RunData({
    this.distanceKm = 62,
    this.routeName = '로랑시앙 루트',
    this.weather = '맑음',
    this.temperature = '-2°C',
    this.duration = '1:24:33',
    this.jarvisComment = '오늘 브레이킹이 지난번보다 정확했어요. 다음엔 2섹터 공략해요.',
  });
}
