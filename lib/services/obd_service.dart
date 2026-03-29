import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/obd_data.dart';
export '../models/obd_data.dart' show OBDRunSummary;

enum OBDState { disconnected, scanning, connecting, ready, error }

// ── 채널 메타데이터 ────────────────────────────────────────────

class OBDChannel {
  final String pid;
  final String name;
  final String unit;
  final double minVal;
  final double maxVal;
  final String category;

  const OBDChannel({
    required this.pid,
    required this.name,
    required this.unit,
    required this.minVal,
    required this.maxVal,
    required this.category,
  });
}

// ── 서비스 ────────────────────────────────────────────────────

class OBDService extends ChangeNotifier {
  OBDState _state = OBDState.disconnected;
  OBDData? _data;
  String? _errorMsg;

  OBDState get state => _state;
  OBDData? get data => _data;
  String? get errorMsg => _errorMsg;
  bool get isConnected => _state == OBDState.ready;

  /// 순간 연비 (L/100km) — 속도 5km/h 이상일 때만 유효
  double? get instantFuelEconomyL100 {
    final spd = _data?.speedKmh;
    final rate = _data?.fuelRateLph;
    if (spd == null || rate == null || spd < 5 || rate <= 0) return null;
    return (rate / spd * 100).clamp(0.0, 99.9);
  }

  // 라이브 탭에 표시할 4개 채널 (PID)
  List<String> _liveChannels = ['010C', '012F', '0111', '0105'];
  List<String> get liveChannels => List.unmodifiable(_liveChannels);

  void setLiveChannel(int idx, String pid) {
    if (idx < 0 || idx >= _liveChannels.length) return;
    _liveChannels[idx] = pid;
    notifyListeners();
  }

  // ── 채널 정의 ─────────────────────────────────────────────

  static const Map<String, OBDChannel> channels = {
    // ENGINE
    '010C': OBDChannel(pid: '010C', name: 'RPM', unit: 'rpm', minVal: 0, maxVal: 8000, category: 'ENGINE'),
    '0104': OBDChannel(pid: '0104', name: '엔진 부하', unit: '%', minVal: 0, maxVal: 100, category: 'ENGINE'),
    '0111': OBDChannel(pid: '0111', name: '스로틀', unit: '%', minVal: 0, maxVal: 100, category: 'ENGINE'),
    '0145': OBDChannel(pid: '0145', name: '상대 스로틀', unit: '%', minVal: 0, maxVal: 100, category: 'ENGINE'),
    '0105': OBDChannel(pid: '0105', name: '냉각수 온도', unit: '°C', minVal: -40, maxVal: 130, category: 'ENGINE'),
    '015C': OBDChannel(pid: '015C', name: '엔진 오일 온도', unit: '°C', minVal: -40, maxVal: 150, category: 'ENGINE'),
    // AIR
    '010F': OBDChannel(pid: '010F', name: '흡기 온도', unit: '°C', minVal: -40, maxVal: 100, category: 'AIR'),
    '010B': OBDChannel(pid: '010B', name: '흡기 압력', unit: 'kPa', minVal: 0, maxVal: 255, category: 'AIR'),
    '0110': OBDChannel(pid: '0110', name: '공기 유량', unit: 'g/s', minVal: 0, maxVal: 200, category: 'AIR'),
    // FUEL
    '012F': OBDChannel(pid: '012F', name: '연료량', unit: '%', minVal: 0, maxVal: 100, category: 'FUEL'),
    '015E': OBDChannel(pid: '015E', name: '연료 소비율', unit: 'L/h', minVal: 0, maxVal: 50, category: 'FUEL'),
    // VEHICLE
    '010D': OBDChannel(pid: '010D', name: '속도', unit: 'km/h', minVal: 0, maxVal: 260, category: 'VEHICLE'),
    '0149': OBDChannel(pid: '0149', name: '가속 페달', unit: '%', minVal: 0, maxVal: 100, category: 'VEHICLE'),
    '0142': OBDChannel(pid: '0142', name: '배터리 전압', unit: 'V', minVal: 10, maxVal: 16, category: 'VEHICLE'),
  };

  static const List<String> _pollOrder = [
    '010C', '010D', '0104', '0111', '012F', '0105',
    '015C', '010F', '010B', '0110', '015E', '0149', '0142', '0145',
  ];

  // ── 값 조회 헬퍼 ──────────────────────────────────────────

  double? getValue(String pid) {
    final d = _data;
    if (d == null) return null;
    switch (pid) {
      case '010C': return d.rpm?.toDouble();
      case '010D': return d.speedKmh?.toDouble();
      case '0104': return d.engineLoadPct;
      case '0111': return d.throttlePct;
      case '0145': return d.relThrottlePct;
      case '0105': return d.coolantTempC?.toDouble();
      case '015C': return d.oilTempC?.toDouble();
      case '010F': return d.intakeAirTempC?.toDouble();
      case '010B': return d.intakeMapKpa?.toDouble();
      case '0110': return d.mafGps;
      case '012F': return d.fuelLevelPct;
      case '015E': return d.fuelRateLph;
      case '0149': return d.accelPedalPct;
      case '0142': return d.moduleVoltageV;
      default: return null;
    }
  }

  String getDisplayValue(String pid) {
    final d = _data;
    if (d == null) return '—';
    switch (pid) {
      case '010C': return d.rpmDisplay;
      case '010D': return d.speedDisplay;
      case '0104': return d.loadDisplay;
      case '0111': return d.throttleDisplay;
      case '0145': return d.relThrottleDisplay;
      case '0105': return d.coolantDisplay;
      case '015C': return d.oilDisplay;
      case '010F': return d.intakeTempDisplay;
      case '010B': return d.mapDisplay;
      case '0110': return d.mafDisplay;
      case '012F': return d.fuelDisplay;
      case '015E': return d.fuelRateDisplay;
      case '0149': return d.accelDisplay;
      case '0142': return d.voltageDisplay;
      default: return '—';
    }
  }

  double getPercent(String pid) {
    final val = getValue(pid);
    final ch = channels[pid];
    if (val == null || ch == null) return 0.0;
    final range = ch.maxVal - ch.minVal;
    if (range <= 0) return 0.0;
    return ((val - ch.minVal) / range).clamp(0.0, 1.0);
  }

  // ── BLE 상태 ──────────────────────────────────────────────

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _pollTimer;

  // 스캔 중 발견된 기기 목록 (UI에 실시간 표시용)
  final List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);

  // FFE0/FFE1 UUID — short form, full 128bit, 또는 포함 여부로 매칭
  static bool _matchUuid(String uuid, String shortId) {
    final u = uuid.toLowerCase().replaceAll('-', '').replaceAll('{', '').replaceAll('}', '');
    return u == shortId ||
        u == '0000${shortId}00001000800000805f9b34fb' ||
        u.contains(shortId); // 비표준 포맷 fallback
  }

  int _pidIdx = 0;
  final StringBuffer _buf = StringBuffer();
  Completer<String>? _responseCompleter;

  // 자동 재연결
  int _consecutiveFailures = 0;
  static const _maxConsecutiveFailures = 5;

  // 런 트래킹 (주행 중 OBD 집계)
  bool _trackingRun = false;
  int? _maxRpm;
  double _fuelRateSum = 0;
  int _fuelRateSamples = 0;
  double? _startFuelLevel;
  int? _maxCoolantTemp;

  // ── Public API ────────────────────────────────────────────

  // OBD 동글로 알려진 이름 패턴 (대소문자 무시)
  static const _obdNamePatterns = [
    'veepeak', 'obd', 'elm', 'obdii', 'vgate', 'icar',
    'kiwi', 'v-link', 'vlink', 'bafx', 'obdlink', 'carista',
    'scan', 'diag', 'torque', 'odb', 'eobd', 'bluetooth obd',
  ];

  static bool isObdDeviceName(String name) {
    final lower = name.toLowerCase();
    return _obdNamePatterns.any((p) => lower.contains(p));
  }

  Future<void> connect() async {
    if (_state == OBDState.scanning || _state == OBDState.connecting) return;
    _setState(OBDState.scanning);
    _errorMsg = null;
    _data = null;
    _scanResults.clear();

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        bool changed = false;
        for (final r in results) {
          final name = r.device.platformName;
          // 이름 없는 기기는 무시 (노이즈 방지)
          if (name.isEmpty) continue;
          // 목록에 없으면 추가
          final alreadyIn = _scanResults.any(
            (s) => s.device.remoteId == r.device.remoteId,
          );
          if (!alreadyIn) {
            _scanResults.add(r);
            changed = true;
            debugPrint('[OBD SCAN] 발견: "$name" rssi=${r.rssi}');
          }
          // 자동 매칭 — 패턴에 걸리는 기기 즉시 연결
          if (_state == OBDState.scanning && isObdDeviceName(name)) {
            debugPrint('[OBD SCAN] 자동 매칭! → 연결: "$name"');
            FlutterBluePlus.stopScan();
            _scanSub?.cancel();
            _connectDevice(r.device);
            return;
          }
        }
        if (changed) notifyListeners();
      });

      FlutterBluePlus.isScanning.where((s) => !s).first.then((_) {
        if (_state == OBDState.scanning) {
          if (_scanResults.isEmpty) {
            _setError('주변에서 블루투스 기기를 찾지 못했어요.\n동글이 차에 꽂혀있는지, 블루투스가 켜져있는지 확인해주세요.');
          } else {
            _setError('OBD 기기를 자동으로 찾지 못했어요.\n아래 목록에서 직접 선택해주세요.');
          }
        }
      });
    } catch (e) {
      _setError('블루투스 스캔 실패: $e');
    }
  }

  /// 수동 기기 선택 후 연결 (스캔 결과 목록에서 탭 시 호출)
  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_state == OBDState.connecting || _state == OBDState.ready) return;
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _errorMsg = null;
    await _connectDevice(device);
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _notifySub?.cancel();
    _scanSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _char = null;
    _data = null;
    _setState(OBDState.disconnected);
  }

  // ── 내부 연결 ─────────────────────────────────────────────

  Future<void> _connectDevice(BluetoothDevice device) async {
    _setState(OBDState.connecting);
    _device = device;

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      debugPrint('[OBD] 연결됨 → 서비스 탐색 중...');
      final services = await device.discoverServices();
      debugPrint('[OBD] 발견된 서비스 ${services.length}개:');
      for (final svc in services) {
        debugPrint('[OBD]   SVC: ${svc.uuid}');
        for (final c in svc.characteristics) {
          debugPrint('[OBD]     CHAR: ${c.uuid}');
        }
      }

      for (final svc in services) {
        if (_matchUuid(svc.uuid.toString(), 'ffe0')) {
          debugPrint('[OBD] FFE0 서비스 매칭!');
          for (final c in svc.characteristics) {
            if (_matchUuid(c.uuid.toString(), 'ffe1')) {
              debugPrint('[OBD] FFE1 특성 매칭!');
              _char = c;
              break;
            }
          }
        }
        if (_char != null) break;
      }

      if (_char == null) {
        debugPrint('[OBD] ❌ FFE0/FFE1 매칭 실패 — 위 UUID 목록 확인 필요');
        _setError('OBD 특성을 찾지 못했어요.');
        return;
      }

      await _char!.setNotifyValue(true);
      _notifySub = _char!.onValueReceived.listen(_onBytes);

      await _cmd('ATZ');
      await Future.delayed(const Duration(milliseconds: 800));
      await _cmd('ATE0');
      await _cmd('ATH0');
      await _cmd('ATS0');
      await _cmd('ATSP0');

      _setState(OBDState.ready);
      _startPolling();
    } catch (e) {
      _setError('연결 실패: $e');
    }
  }

  void _onBytes(List<int> bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    _buf.write(str);
    final current = _buf.toString();
    final promptIdx = current.indexOf('>');
    if (promptIdx >= 0) {
      final response = current.substring(0, promptIdx).trim();
      // '>' 이후 남은 데이터는 버퍼에 유지 (다음 응답의 시작일 수 있음)
      final remaining = current.substring(promptIdx + 1);
      _buf.clear();
      if (remaining.isNotEmpty) _buf.write(remaining);
      final completer = _responseCompleter;
      if (completer != null && !completer.isCompleted) {
        _responseCompleter = null;
        completer.complete(response);
      }
    }
  }

  Future<String> _cmd(String command) async {
    final c = _char;
    if (c == null) return '';
    _buf.clear();
    _responseCompleter?.complete('');
    _responseCompleter = Completer<String>();
    try {
      await c.write(utf8.encode('$command\r'), withoutResponse: true);
    } catch (_) {
      return '';
    }
    return _responseCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _responseCompleter = null;
        return '';
      },
    );
  }

  // ── 폴링 ─────────────────────────────────────────────────

  void _startPolling() {
    _pidIdx = 0;
    _consecutiveFailures = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_state != OBDState.ready) return;
      final pid = _pollOrder[_pidIdx];
      _pidIdx = (_pidIdx + 1) % _pollOrder.length;
      final resp = await _cmd(pid);
      if (resp.isNotEmpty) {
        _consecutiveFailures = 0;
        _parse(pid, resp);
      } else {
        _consecutiveFailures++;
        if (_consecutiveFailures >= _maxConsecutiveFailures) {
          _consecutiveFailures = 0;
          debugPrint('[OBD] 연속 ${_maxConsecutiveFailures}회 응답 없음 → 자동 재연결');
          _autoReconnect();
        }
      }
    });
  }

  Future<void> _autoReconnect() async {
    _pollTimer?.cancel();
    _notifySub?.cancel();
    try { await _device?.disconnect(); } catch (_) {}
    _device = null;
    _char = null;
    _setError('응답 없음. 재연결 중...');
    await Future.delayed(const Duration(seconds: 2));
    connect();
  }

  // ── PID 파싱 ─────────────────────────────────────────────

  void _parse(String pid, String raw) {
    final s = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final prefix = '41${pid.substring(2).toUpperCase()}';
    final idx = s.indexOf(prefix);
    if (idx < 0) return;
    final hex = s.substring(idx + prefix.length);
    if (hex.length < 2) return;

    try {
      final cur = _data ?? OBDData(timestamp: DateTime.now());
      OBDData? upd;

      int byteA() => int.parse(hex.substring(0, 2), radix: 16);
      int byteB() => int.parse(hex.substring(2, 4), radix: 16);

      switch (pid) {
        case '010C': // RPM: (A*256+B)/4
          if (hex.length >= 4) {
            upd = cur.copyWith(rpm: (byteA() * 256 + byteB()) ~/ 4, timestamp: DateTime.now());
          }
          break;
        case '010D':
          upd = cur.copyWith(speedKmh: byteA(), timestamp: DateTime.now());
          break;
        case '0104':
          upd = cur.copyWith(engineLoadPct: byteA() * 100.0 / 255.0, timestamp: DateTime.now());
          break;
        case '0111':
          upd = cur.copyWith(throttlePct: byteA() * 100.0 / 255.0, timestamp: DateTime.now());
          break;
        case '0145':
          upd = cur.copyWith(relThrottlePct: byteA() * 100.0 / 255.0, timestamp: DateTime.now());
          break;
        case '0105':
          upd = cur.copyWith(coolantTempC: byteA() - 40, timestamp: DateTime.now());
          break;
        case '015C':
          upd = cur.copyWith(oilTempC: byteA() - 40, timestamp: DateTime.now());
          break;
        case '010F':
          upd = cur.copyWith(intakeAirTempC: byteA() - 40, timestamp: DateTime.now());
          break;
        case '010B':
          upd = cur.copyWith(intakeMapKpa: byteA(), timestamp: DateTime.now());
          break;
        case '0110': // MAF: (A*256+B)/100
          if (hex.length >= 4) {
            upd = cur.copyWith(
                mafGps: (byteA() * 256 + byteB()) / 100.0, timestamp: DateTime.now());
          }
          break;
        case '012F':
          upd = cur.copyWith(fuelLevelPct: byteA() * 100.0 / 255.0, timestamp: DateTime.now());
          break;
        case '015E': // Fuel rate: (A*256+B)/20
          if (hex.length >= 4) {
            upd = cur.copyWith(
                fuelRateLph: (byteA() * 256 + byteB()) / 20.0, timestamp: DateTime.now());
          }
          break;
        case '0149':
          upd = cur.copyWith(accelPedalPct: byteA() * 100.0 / 255.0, timestamp: DateTime.now());
          break;
        case '0142': // Voltage: (A*256+B)/1000
          if (hex.length >= 4) {
            upd = cur.copyWith(
                moduleVoltageV: (byteA() * 256 + byteB()) / 1000.0, timestamp: DateTime.now());
          }
          break;
      }

      if (upd != null) {
        _data = upd;
        // 런 트래킹 집계
        if (_trackingRun) {
          if (upd.rpm != null && (upd.rpm! > (_maxRpm ?? 0))) _maxRpm = upd.rpm;
          if (upd.fuelRateLph != null && upd.fuelRateLph! > 0) {
            _fuelRateSum += upd.fuelRateLph!;
            _fuelRateSamples++;
          }
          if (upd.coolantTempC != null &&
              (upd.coolantTempC! > (_maxCoolantTemp ?? -999))) {
            _maxCoolantTemp = upd.coolantTempC;
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    } catch (e) {
      debugPrint('[OBD] Parse error [$pid]: $e');
    }
  }

  // ── 런 트래킹 ────────────────────────────────────────────

  /// 주행 시작 시 호출 — OBD 집계 초기화
  void startRunTracking() {
    _trackingRun = true;
    _maxRpm = null;
    _fuelRateSum = 0;
    _fuelRateSamples = 0;
    _startFuelLevel = _data?.fuelLevelPct;
    _maxCoolantTemp = null;
  }

  /// 주행 종료 시 호출 — OBDRunSummary 반환 (OBD 미연결 시 null)
  OBDRunSummary? stopRunTracking() {
    if (!_trackingRun) return null;
    _trackingRun = false;
    final summary = OBDRunSummary(
      maxRpm: _maxRpm,
      avgFuelRateLph: _fuelRateSamples > 0 ? _fuelRateSum / _fuelRateSamples : null,
      startFuelLevelPct: _startFuelLevel,
      endFuelLevelPct: _data?.fuelLevelPct,
      maxCoolantTempC: _maxCoolantTemp,
    );
    return summary.hasData ? summary : null;
  }

  // ── 유틸 ─────────────────────────────────────────────────

  void _setState(OBDState s) {
    _state = s;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  void _setError(String msg) {
    _errorMsg = msg;
    _state = OBDState.error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
