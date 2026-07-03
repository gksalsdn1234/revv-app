import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MountType {
  dashFlat, // 대시보드 수평 (화면 위)
  ventPort, // 에어컨 마운트 세로 (화면 앞)
  ventLand, // 에어컨 마운트 가로 (화면 앞)
  windshield, // 앞유리 마운트 세로
}

class ImuVector {
  final double x;
  final double y;
  final double z;

  const ImuVector(this.x, this.y, this.z);
  const ImuVector.zero() : this(0, 0, 0);

  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

typedef GForceSample = ({
  ImuVector acceleration,
  ImuVector gyro,
  double? speedKmh,
  Duration dt,
});

typedef GForceReading = ({
  double lateralG,
  double longitudinalG,
  double lateralMps2,
  double longitudinalMps2,
});

const GForceReading _zeroGForceReading = (
  lateralG: 0,
  longitudinalG: 0,
  lateralMps2: 0,
  longitudinalMps2: 0,
);

class GForceResolver {
  static const double gravity = 9.81;
  static const double _orientationAlpha = 0.98;

  MountType mountType;
  ImuVector _offset = const ImuVector.zero();
  double _roll = 0, _pitch = 0;

  GForceResolver({this.mountType = MountType.dashFlat});

  void setCalibrationOffset(ImuVector offset) => _offset =
      offset.magnitude > gravity * 0.5 ? const ImuVector.zero() : offset;

  void resetCalibration() {
    _offset = const ImuVector.zero();
  }

  GForceReading resolve(GForceSample sample) {
    _trackTilt(sample);
    final acceleration = _removeResidualGravity(sample.acceleration);
    var lateralMps2 = _lateral(acceleration);
    var longitudinalMps2 = _longitudinal(acceleration);

    if (_isStationary(sample)) {
      lateralMps2 = 0;
      longitudinalMps2 = 0;
    }

    return (
      lateralG: lateralMps2 / gravity,
      longitudinalG: longitudinalMps2 / gravity,
      lateralMps2: lateralMps2,
      longitudinalMps2: longitudinalMps2,
    );
  }

  void _trackTilt(GForceSample sample) {
    final seconds = sample.dt.inMicroseconds / 1000000.0;
    if (seconds <= 0) return;
    _roll = (_roll + sample.gyro.x * seconds) * _orientationAlpha;
    _pitch = (_pitch + sample.gyro.y * seconds) * _orientationAlpha;
  }

  ImuVector _removeResidualGravity(ImuVector acceleration) {
    final residual = _rotatedOffset();
    return ImuVector(
      acceleration.x - residual.x,
      acceleration.y - residual.y,
      acceleration.z - residual.z,
    );
  }

  ImuVector _rotatedOffset() {
    final cr = math.cos(_roll);
    final sr = math.sin(_roll);
    final cp = math.cos(_pitch);
    final sp = math.sin(_pitch);
    final y = _offset.y * cr - _offset.z * sr;
    final z = _offset.y * sr + _offset.z * cr;
    return ImuVector(_offset.x * cp + z * sp, y, -_offset.x * sp + z * cp);
  }

  bool _isStationary(GForceSample sample) {
    final speedKmh = sample.speedKmh;
    return speedKmh != null &&
        speedKmh <= 1.0 &&
        sample.gyro.magnitude <= 0.035;
  }

  double _lateral(ImuVector acceleration) {
    switch (mountType) {
      case MountType.dashFlat:
      case MountType.ventPort:
      case MountType.windshield:
        return acceleration.x;
      case MountType.ventLand:
        return acceleration.y;
    }
  }

  double _longitudinal(ImuVector acceleration) {
    switch (mountType) {
      case MountType.dashFlat:
        return acceleration.y;
      case MountType.ventPort:
      case MountType.ventLand:
      case MountType.windshield:
        return -acceleration.z;
    }
  }
}

class ImuService extends ChangeNotifier {
  MountType _mountType = MountType.dashFlat;
  MountType get mountType => _mountType;
  final GForceResolver _resolver = GForceResolver();

  // 캘리브레이션 오프셋 (정지 상태에서 측정한 기준값)
  double _offX = 0, _offY = 0, _offZ = 0;
  bool _calibrated = false;
  bool get calibrated => _calibrated;

  // 현재 선형 가속도계 값 (m/s², gravity removed)
  double _rawX = 0, _rawY = 0, _rawZ = 0;

  // 현재 자이로스코프 값 (rad/s)
  double _gyrX = 0, _gyrY = 0, _gyrZ = 0;
  double? _speedKmh;
  GForceReading _reading = _zeroGForceReading;

  // 세션 최대 G값
  double _maxLateralG = 0;
  double _maxLonG = 0;
  double get maxLateralG => _maxLateralG;
  double get maxLonG => _maxLonG;

  void resetMaxG() {
    _maxLateralG = 0;
    _maxLonG = 0;
    notifyListeners();
  }

  StreamSubscription? _accelSub, _gyroSub;
  bool _notifyPending = false; // 프레임당 1회만 notify (레이아웃 assertion 방지)

  // ── 공개 G값 ──────────────────────────────────────────────

  /// 횡가속도 (좌: -, 우: +) in G
  double get lateralG => _reading.lateralG;

  /// 종가속도 (감속: -, 가속: +) in G
  double get longitudinalG => _reading.longitudinalG;

  /// 요레이트 (좌: -, 우: +) in °/s
  double get yawRateDps => _yaw() * 180 / math.pi;

  /// 현재 원시값 (캘리브레이션 UI용)
  double get rawLateral => _reading.lateralMps2;
  double get rawLongitudinal => _reading.longitudinalMps2;

  double _yaw() {
    switch (_mountType) {
      case MountType.dashFlat:
        return _gyrZ;
      case MountType.ventPort:
        return _gyrY;
      case MountType.ventLand:
        return _gyrY;
      case MountType.windshield:
        return _gyrY;
    }
  }

  // ── 초기화 ────────────────────────────────────────────────

  ImuService() {
    _loadPrefs().then((_) => _startSensors());
  }

  void _startSensors() {
    _accelSub =
        userAccelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 20), // 50Hz
        ).listen((e) {
          _rawX = e.x;
          _rawY = e.y;
          _rawZ = e.z;
          _reading = _resolver.resolve((
            acceleration: ImuVector(_rawX, _rawY, _rawZ),
            gyro: ImuVector(_gyrX, _gyrY, _gyrZ),
            speedKmh: _speedKmh,
            dt: const Duration(milliseconds: 20),
          ));
          final lG = _reading.lateralG.abs();
          final nG = _reading.longitudinalG.abs();
          if (lG > _maxLateralG) _maxLateralG = lG;
          if (nG > _maxLonG) _maxLonG = nG;
          // addPostFrameCallback으로 감싸야 layout 패스 중 notifyListeners() 호출 방지
          // → '!_debugDoingThisLayout' assertion + RenderBox not laid out 해결
          // 프레임당 1회만 등록 (50Hz 센서가 한 프레임 안에 여러 번 올 수 있음)
          if (!_notifyPending) {
            _notifyPending = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _notifyPending = false;
              notifyListeners();
            });
          }
        });

    _gyroSub =
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 20),
        ).listen((e) {
          _gyrX = e.x;
          _gyrY = e.y;
          _gyrZ = e.z;
        });
  }

  // ── Public API ────────────────────────────────────────────

  void setMountType(MountType type) {
    _mountType = type;
    _resolver.mountType = type;
    _calibrated = false;
    _offX = _offY = _offZ = 0;
    _resolver.resetCalibration();
    _savePrefs();
    notifyListeners();
  }

  void updateSpeedKmh(double speedKmh) {
    _speedKmh = speedKmh.clamp(0, 300);
  }

  /// 차량 정지 상태에서 호출 — 현재 값을 기준점으로 저장
  void calibrate() {
    _offX = _rawX;
    _offY = _rawY;
    _offZ = _rawZ;
    _calibrated = true;
    _resolver.setCalibrationOffset(ImuVector(_offX, _offY, _offZ));
    _savePrefs();
    notifyListeners();
  }

  void resetCalibration() {
    _offX = _offY = _offZ = 0;
    _calibrated = false;
    _resolver.resetCalibration();
    _savePrefs();
    notifyListeners();
  }

  // ── SharedPreferences ──────────────────────────────────────

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getInt('imu_mount') ?? 0;
    _mountType = MountType.values[idx.clamp(0, MountType.values.length - 1)];
    _offX = p.getDouble('imu_ox') ?? 0;
    _offY = p.getDouble('imu_oy') ?? 0;
    _offZ = p.getDouble('imu_oz') ?? 0;
    _calibrated = p.getBool('imu_cal') ?? false;
    _resolver.mountType = _mountType;
    if (_calibrated) {
      _resolver.setCalibrationOffset(ImuVector(_offX, _offY, _offZ));
    }
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('imu_mount', _mountType.index);
    await p.setDouble('imu_ox', _offX);
    await p.setDouble('imu_oy', _offY);
    await p.setDouble('imu_oz', _offZ);
    await p.setBool('imu_cal', _calibrated);
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    super.dispose();
  }
}
