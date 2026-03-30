import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/storage_keys.dart';
import 'jarvis_script.dart';

/// 앱 전역 사용자 설정
class SettingsService extends ChangeNotifier {

  // ── 기본값 ─────────────────────────────────────────────────
  bool           _ttsMuted      = false;
  int            _searchRadius  = 50;    // km: 30 / 50 / 100
  String         _distUnit      = 'km';  // 'km' | 'mi'
  bool           _showSpeedHud  = true;
  bool           _offRouteAlert = true;
  bool           _alwaysListen  = false;
  JarvisPersona  _jarvisPersona = JarvisPersona.engineer;

  // ── Getters ────────────────────────────────────────────────
  bool          get ttsMuted      => _ttsMuted;
  int           get searchRadiusKm => _searchRadius;
  String        get distUnit      => _distUnit;
  bool          get showSpeedHud  => _showSpeedHud;
  bool          get offRouteAlert => _offRouteAlert;
  bool          get alwaysListen  => _alwaysListen;
  JarvisPersona get jarvisPersona => _jarvisPersona;

  // ── 로드 ──────────────────────────────────────────────────
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _ttsMuted      = p.getBool(StorageKeys.ttsMuted)      ?? false;
    _searchRadius  = p.getInt(StorageKeys.searchRadius)   ?? 50;
    _distUnit      = p.getString(StorageKeys.distUnit)    ?? 'km';
    _showSpeedHud  = p.getBool(StorageKeys.showSpeedHud)  ?? true;
    _offRouteAlert = p.getBool(StorageKeys.offRouteAlert) ?? true;
    _alwaysListen  = p.getBool(StorageKeys.alwaysListen)  ?? false;
    final rawPersona = p.getString(StorageKeys.jarvisPersona) ?? 'engineer';
    _jarvisPersona = rawPersona == 'friendly' ? JarvisPersona.friendly : JarvisPersona.engineer;
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
    assert(v == 30 || v == 50 || v == 100);
    if (_searchRadius == v) return;
    _searchRadius = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(StorageKeys.searchRadius, v);
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

  Future<void> setJarvisPersona(JarvisPersona v) async {
    if (_jarvisPersona == v) return;
    _jarvisPersona = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(StorageKeys.jarvisPersona, v.name);
  }
}
