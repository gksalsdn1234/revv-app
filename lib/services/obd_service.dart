import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/obd_data.dart';

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

  static const _svcUuid = 'ffe0';
  static const _charUuid = 'ffe1';

  int _pidIdx = 0;
  final StringBuffer _buf = StringBuffer();
  Completer<String>? _responseCompleter;

  // ── Public API ────────────────────────────────────────────

  Future<void> connect() async {
    if (_state == OBDState.scanning || _state == OBDState.connecting) return;
    _setState(OBDState.scanning);
    _errorMsg = null;
    _data = null;

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName.toLowerCase();
          if (name.contains('veepeak') ||
              name.contains('obd') ||
              name.contains('elm') ||
              name.contains('obdii')) {
            FlutterBluePlus.stopScan();
            _scanSub?.cancel();
            _connectDevice(r.device);
            return;
          }
        }
      });

      FlutterBluePlus.isScanning.where((s) => !s).first.then((_) {
        if (_state == OBDState.scanning) {
          _setError('OBD 장치를 찾지 못했어요.\n동글이 차에 꽂혀있는지 확인해주세요.');
        }
      });
    } catch (e) {
      _setError('블루투스 스캔 실패: $e');
    }
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
      final services = await device.discoverServices();

      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase().contains(_svcUuid)) {
          for (final c in svc.characteristics) {
            if (c.uuid.toString().toLowerCase().contains(_charUuid)) {
              _char = c;
              break;
            }
          }
        }
        if (_char != null) break;
      }

      if (_char == null) {
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
    if (_buf.toString().contains('>')) {
      final response = _buf.toString().replaceAll('>', '').trim();
      _buf.clear();
      _responseCompleter?.complete(response);
      _responseCompleter = null;
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
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_state != OBDState.ready) return;
      final pid = _pollOrder[_pidIdx];
      _pidIdx = (_pidIdx + 1) % _pollOrder.length;
      final resp = await _cmd(pid);
      if (resp.isNotEmpty) _parse(pid, resp);
    });
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
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── 유틸 ─────────────────────────────────────────────────

  void _setState(OBDState s) {
    _state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMsg = msg;
    _state = OBDState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
