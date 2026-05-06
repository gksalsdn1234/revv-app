import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/storage_keys.dart';

/// 앱 전역 사용자 설정
class SettingsService extends ChangeNotifier {
  // ── 기본값 ─────────────────────────────────────────────────
  bool _ttsMuted = false;
  int _searchRadius = 50; // km: 30 / 50 / 100 / 160 / 220
  String _distUnit = 'km'; // 'km' | 'mi'
  bool _showSpeedHud = true;
  bool _offRouteAlert = true;
  bool _alwaysListen = false;
  String _ttsRatePreset = 'relaxed';
  String _ttsEngine = 'google';
  String? _ttsVoiceName;
  String? _ttsVoiceLocale;
  String? _googleTtsVoiceName;

  // ── Getters ────────────────────────────────────────────────
  bool get ttsMuted => _ttsMuted;
  int get searchRadiusKm => _searchRadius;
  String get distUnit => _distUnit;
  bool get showSpeedHud => _showSpeedHud;
  bool get offRouteAlert => _offRouteAlert;
  bool get alwaysListen => _alwaysListen;
  String get ttsRatePreset => _ttsRatePreset;
  String get ttsEngine => _ttsEngine;
  String? get ttsVoiceName => _ttsVoiceName;
  String? get ttsVoiceLocale => _ttsVoiceLocale;
  String? get googleTtsVoiceName => _googleTtsVoiceName;

  // ── 로드 ──────────────────────────────────────────────────
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _ttsMuted = p.getBool(StorageKeys.ttsMuted) ?? false;
    final rawRadius = p.getInt(StorageKeys.searchRadius) ?? 50;
    _searchRadius = _normalizeSearchRadius(rawRadius);
    _distUnit = p.getString(StorageKeys.distUnit) ?? 'km';
    _showSpeedHud = p.getBool(StorageKeys.showSpeedHud) ?? true;
    _offRouteAlert = p.getBool(StorageKeys.offRouteAlert) ?? true;
    _alwaysListen = p.getBool(StorageKeys.alwaysListen) ?? false;
    _ttsRatePreset = p.getString(StorageKeys.ttsRatePreset) ?? 'relaxed';
    _ttsEngine = p.getString(StorageKeys.ttsEngine) ?? 'google';
    _ttsVoiceName = p.getString(StorageKeys.ttsVoiceName);
    _ttsVoiceLocale = p.getString(StorageKeys.ttsVoiceLocale);
    _googleTtsVoiceName = p.getString(StorageKeys.googleTtsVoiceName);
    notifyListeners();
  }

  // ── Setters ────────────────────────────────────────────────
  Future<void> setTtsMuted(bool v) async {
    if (_ttsMuted == v) return;
    _ttsMuted = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(StorageKeys.ttsMuted, v);
  }

  Future<void> setSearchRadius(int v) async {
    final next = _normalizeSearchRadius(v);
    if (_searchRadius == next) return;
    _searchRadius = next;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(StorageKeys.searchRadius, next);
  }

  int _normalizeSearchRadius(int value) {
    const allowed = [30, 50, 100, 160, 220];
    if (allowed.contains(value)) return value;
    return allowed.reduce(
      (best, current) =>
          (value - current).abs() < (value - best).abs() ? current : best,
    );
  }

  Future<void> setDistUnit(String v) async {
    if (_distUnit == v) return;
    _distUnit = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(StorageKeys.distUnit, v);
  }

  Future<void> setShowSpeedHud(bool v) async {
    if (_showSpeedHud == v) return;
    _showSpeedHud = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(StorageKeys.showSpeedHud, v);
  }

  Future<void> setOffRouteAlert(bool v) async {
    if (_offRouteAlert == v) return;
    _offRouteAlert = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(StorageKeys.offRouteAlert, v);
  }

  Future<void> setAlwaysListen(bool v) async {
    if (_alwaysListen == v) return;
    _alwaysListen = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(StorageKeys.alwaysListen, v);
  }

  Future<void> setTtsRatePreset(String value) async {
    const allowed = {'relaxed', 'balanced', 'brisk'};
    final next = allowed.contains(value) ? value : 'relaxed';
    if (_ttsRatePreset == next) return;
    _ttsRatePreset = next;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(StorageKeys.ttsRatePreset, next);
  }

  Future<void> setTtsEngine(String value) async {
    const allowed = {'google', 'device'};
    final next = allowed.contains(value) ? value : 'google';
    if (_ttsEngine == next) return;
    _ttsEngine = next;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(StorageKeys.ttsEngine, next);
  }

  Future<void> setTtsVoice({
    required String? name,
    required String? locale,
  }) async {
    if (_ttsVoiceName == name && _ttsVoiceLocale == locale) return;
    _ttsVoiceName = name;
    _ttsVoiceLocale = locale;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (name == null || locale == null) {
      await p.remove(StorageKeys.ttsVoiceName);
      await p.remove(StorageKeys.ttsVoiceLocale);
      return;
    }
    await p.setString(StorageKeys.ttsVoiceName, name);
    await p.setString(StorageKeys.ttsVoiceLocale, locale);
  }

  Future<void> setGoogleTtsVoiceName(String? name) async {
    if (_googleTtsVoiceName == name) return;
    _googleTtsVoiceName = name;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await p.remove(StorageKeys.googleTtsVoiceName);
      return;
    }
    await p.setString(StorageKeys.googleTtsVoiceName, name);
  }
}
