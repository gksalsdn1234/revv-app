import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/follow_camera_zoom_controller.dart';

void main() {
  Duration ms(int value) => Duration(milliseconds: value);

  test('제스처가 없으면 모드 기본 줌을 그대로 쓴다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    expect(controller.followZoom, 16.5);
    expect(controller.hasUserZoom, isFalse);
    expect(controller.isFollowSuppressed(ms(0)), isFalse);
  });

  test('제스처 밖에서 들어온 카메라 줌은 유저 줌으로 기억하지 않는다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    // 내부 setCamera/flyTo가 만든 카메라 이벤트.
    controller.onCameraZoom(13.0, now: ms(0));

    expect(controller.hasUserZoom, isFalse);
    expect(controller.followZoom, 16.5);
  });

  test('핀치줌으로 만든 줌은 제스처가 끝난 뒤에도 팔로우 줌으로 유지된다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    controller.onCameraZoom(15.4, now: ms(20));
    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.update,
      now: ms(40),
    );
    controller.onCameraZoom(13.2, now: ms(60));
    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.end,
      now: ms(80),
    );

    expect(controller.hasUserZoom, isTrue);
    expect(controller.followZoom, 13.2);

    // settle window가 지나고 GPS 팔로우가 재개돼도 유저 줌은 그대로.
    expect(controller.isFollowSuppressed(ms(2000)), isFalse);
    expect(controller.followZoom, 13.2);
  });

  test('제스처 중에는 팔로우 카메라 쓰기를 멈추고 settle 후 재개한다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    expect(controller.isFollowSuppressed(ms(10)), isTrue);

    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.end,
      now: ms(100),
    );
    // 관성/더블탭 애니메이션이 남아 있는 구간
    expect(controller.isFollowSuppressed(ms(300)), isTrue);
    expect(controller.isFollowSuppressed(ms(600)), isFalse);
  });

  test('팬 제스처는 팔로우만 잠시 멈추고 줌은 건드리지 않는다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    controller.onGesture(
      MapCameraGesture.pan,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    expect(controller.isFollowSuppressed(ms(10)), isTrue);

    controller.onCameraZoom(13.0, now: ms(20));
    expect(controller.hasUserZoom, isFalse);

    controller.onGesture(
      MapCameraGesture.pan,
      MapCameraGesturePhase.end,
      now: ms(30),
    );
    expect(controller.isFollowSuppressed(ms(40)), isFalse);
  });

  test('기본 줌과 사실상 같은 값이면 유저 줌으로 보지 않는다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    controller.onCameraZoom(16.56, now: ms(20));

    expect(controller.hasUserZoom, isFalse);
    expect(controller.followZoom, 16.5);
  });

  test('리센터는 기본 줌으로 복귀시킨다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    controller.onCameraZoom(12.0, now: ms(20));
    expect(controller.followZoom, 12.0);

    controller.reset();

    expect(controller.hasUserZoom, isFalse);
    expect(controller.followZoom, 16.5);
    expect(controller.isFollowSuppressed(ms(30)), isFalse);
  });

  test('모드 전환(기본 줌 변경)은 유저 줌을 정리한다', () {
    final controller = FollowCameraZoomController(defaultZoom: 15.0);

    controller.onGesture(
      MapCameraGesture.zoom,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    controller.onCameraZoom(11.5, now: ms(20));
    expect(controller.followZoom, 11.5);

    controller.setDefaultZoom(16.5);

    expect(controller.hasUserZoom, isFalse);
    expect(controller.followZoom, 16.5);
  });

  test('end 이벤트가 유실돼도 팔로우가 영구히 멈추지 않는다', () {
    final controller = FollowCameraZoomController(defaultZoom: 16.5);

    controller.onGesture(
      MapCameraGesture.pan,
      MapCameraGesturePhase.start,
      now: ms(0),
    );
    // end가 오지 않은 상태
    expect(controller.isFollowSuppressed(ms(1000)), isTrue);
    expect(controller.isFollowSuppressed(ms(2500)), isFalse);
  });
}
