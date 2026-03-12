import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/obd_data.dart';

enum OBDState { disconnected, scanning, connecting, ready, error }

class OBDService extends ChangeNotifier {
  OBDState _state = OBDState.disconnected;
  OBDData? _data;
  String? _errorMsg;

  OBDState get state => _state;
  OBDData? get data => _data;
  String? get errorMsg => _errorMsg;
  bool get isConnected => _state == OBDState.ready;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _pollTimer;

  // VEEPEAK OBD2 BLE+ uses FFE0/FFE1 service
  static const _svcUuid = 'ffe0';
  static const _charUuid = 'ffe1';

  // PID polling order: RPM, Speed, Engine Load, Throttle, Fuel, Coolant
  static const _pids = ['010C', '010D', '0104', '0111', '012F', '0105'];
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

      // 스캔 타임아웃 후 기기를 못 찾으면 에러
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

      // ELM327 초기화
      await _cmd('ATZ');
      await Future.delayed(const Duration(milliseconds: 800));
      await _cmd('ATE0'); // 에코 끄기
      await _cmd('ATH0'); // 헤더 끄기
      await _cmd('ATS0'); // 공백 끄기
      await _cmd('ATSP0'); // 자동 프로토콜

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
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (_state != OBDState.ready) return;
      final pid = _pids[_pidIdx];
      _pidIdx = (_pidIdx + 1) % _pids.length;
      final resp = await _cmd(pid);
      if (resp.isNotEmpty) _parse(pid, resp);
    });
  }

  // ── PID 파싱 ─────────────────────────────────────────────

  void _parse(String pid, String raw) {
    // 공백·개행 제거, 대문자화
    final s = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    // 응답 prefix: 41 + PID[2..] e.g. "010C" → "410C"
    final prefix = '41${pid.substring(2).toUpperCase()}';
    final idx = s.indexOf(prefix);
    if (idx < 0) return;
    final hex = s.substring(idx + prefix.length);
    if (hex.length < 2) return;

    try {
      final current = _data ?? OBDData(timestamp: DateTime.now());
      OBDData? updated;

      switch (pid) {
        case '010C': // RPM: (A*256+B)/4
          if (hex.length >= 4) {
            final a = int.parse(hex.substring(0, 2), radix: 16);
            final b = int.parse(hex.substring(2, 4), radix: 16);
            updated = current.copyWith(
                rpm: (a * 256 + b) ~/ 4, timestamp: DateTime.now());
          }
          break;

        case '010D': // 속도 km/h
          updated = current.copyWith(
              speedKmh: int.parse(hex.substring(0, 2), radix: 16),
              timestamp: DateTime.now());
          break;

        case '0104': // 엔진 부하 %
          updated = current.copyWith(
              engineLoadPct:
                  int.parse(hex.substring(0, 2), radix: 16) * 100.0 / 255.0,
              timestamp: DateTime.now());
          break;

        case '0111': // 스로틀 %
          updated = current.copyWith(
              throttlePct:
                  int.parse(hex.substring(0, 2), radix: 16) * 100.0 / 255.0,
              timestamp: DateTime.now());
          break;

        case '012F': // 연료량 %
          updated = current.copyWith(
              fuelLevelPct:
                  int.parse(hex.substring(0, 2), radix: 16) * 100.0 / 255.0,
              timestamp: DateTime.now());
          break;

        case '0105': // 냉각수 온도 (A-40)
          updated = current.copyWith(
              coolantTempC:
                  int.parse(hex.substring(0, 2), radix: 16) - 40,
              timestamp: DateTime.now());
          break;
      }

      if (updated != null) {
        _data = updated;
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
