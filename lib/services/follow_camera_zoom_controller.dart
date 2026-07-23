/// 지도에서 감지하는 유저 제스처 종류.
enum MapCameraGesture { pan, zoom }

/// 제스처 진행 단계 (Mapbox GestureState 매핑).
enum MapCameraGesturePhase { start, update, end }

/// 유저가 직접 만든 줌을 지켜주는 팔로우 카메라 보조 상태기.
///
/// 주행 중에는 GPS가 갱신될 때마다 카메라를 다시 쓰는데, 예전에는 줌을 모드 기본값으로
/// 고정해서 유저가 핀치로 확대해도 다음 GPS 틱에 원래 줌으로 튕겨 돌아갔다.
/// 이 상태기는
///  1. 제스처가 진행 중인 구간을 알려줘 팔로우 카메라 쓰기를 잠깐 멈추게 하고,
///  2. 제스처로 만들어진 줌을 기억해 이후 팔로우가 center/bearing만 갱신하도록 한다.
class FollowCameraZoomController {
  /// 기본 줌과 이만큼도 차이 나지 않으면 "유저가 바꿨다"고 보지 않는다.
  static const double _overrideThreshold = 0.15;

  /// 제스처가 끝나도 관성·더블탭 애니메이션이 남아 있어 잠시 더 줌을 지켜본다.
  static const Duration _settleWindow = Duration(milliseconds: 450);

  /// end 이벤트가 유실돼도 팔로우가 영구히 멈추지 않게 하는 안전장치.
  static const Duration _staleGesture = Duration(seconds: 2);

  double _defaultZoom;
  double? _userZoom;
  bool _panActive = false;
  bool _zoomActive = false;
  Duration _lastGestureAt = Duration.zero;
  Duration? _settleUntil;

  FollowCameraZoomController({double defaultZoom = 15.0})
    : _defaultZoom = defaultZoom;

  double get defaultZoom => _defaultZoom;

  double? get userZoom => _userZoom;

  /// 유저가 정한 줌이 살아 있는가 (리센터 버튼 노출 조건).
  bool get hasUserZoom => _userZoom != null;

  /// 팔로우 카메라가 써야 할 줌 — 유저 값이 있으면 그 값, 없으면 모드 기본값.
  double get followZoom => _userZoom ?? _defaultZoom;

  /// 모드 전환(파인더 ↔ 주행)으로 기본 줌이 바뀌면 유저 줌은 무효로 본다.
  void setDefaultZoom(double zoom) {
    if (zoom == _defaultZoom) return;
    _defaultZoom = zoom;
    _userZoom = null;
  }

  void onGesture(
    MapCameraGesture gesture,
    MapCameraGesturePhase phase, {
    required Duration now,
  }) {
    _lastGestureAt = now;
    final active = phase != MapCameraGesturePhase.end;
    switch (gesture) {
      case MapCameraGesture.pan:
        _panActive = active;
      case MapCameraGesture.zoom:
        _zoomActive = active;
        _settleUntil = now + _settleWindow;
    }
  }

  /// 제스처 중에는 팔로우 카메라가 지도를 덮어쓰지 않아야 한다.
  bool isFollowSuppressed(Duration now) {
    _expireStaleGesture(now);
    if (_panActive || _zoomActive) return true;
    return _withinSettleWindow(now);
  }

  /// 지금 들어오는 카메라 줌이 "유저가 만든 줌"인지.
  bool isTrackingZoom(Duration now) {
    _expireStaleGesture(now);
    return _zoomActive || _withinSettleWindow(now);
  }

  /// 카메라 변경 이벤트의 줌. 제스처 구간에서 들어온 값만 유저 줌으로 기억한다.
  void onCameraZoom(double zoom, {required Duration now}) {
    if (!isTrackingZoom(now)) return;
    _userZoom = (zoom - _defaultZoom).abs() < _overrideThreshold ? null : zoom;
  }

  /// 리센터 — 기본 줌으로 복귀.
  void reset() {
    _userZoom = null;
    _panActive = false;
    _zoomActive = false;
    _settleUntil = null;
  }

  bool _withinSettleWindow(Duration now) {
    final until = _settleUntil;
    if (until == null) return false;
    if (now < until) return true;
    _settleUntil = null;
    return false;
  }

  void _expireStaleGesture(Duration now) {
    if (!_panActive && !_zoomActive) return;
    if (now - _lastGestureAt < _staleGesture) return;
    _panActive = false;
    _zoomActive = false;
  }
}
