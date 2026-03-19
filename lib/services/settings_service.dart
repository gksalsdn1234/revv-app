import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 전역 사용자 설정
class SettingsService extends ChangeNotifier {
  // ── 키 ────────────────────────────────────────────────────
  static const _kTtsMuted       = 'setting_ttsMuted';
  static const _kSearchRadius   = 'setting_searchRadius';
  static const _kDistUnit       = 'setting_distUnit';
  static const _kShowSpeedHud   = 'setting_showSpeedHud';
  static const _kOffRouteAlert  = 'setting_offRouteAlert';

  // ── 기본값 ─────────────────────────────────────────────────
  bool   _ttsMuted      = false;
  int    _searchRadius  = 50;    // km: 30 / 50 / 100
  String _distUnit      = 'km';  // 'km' | 'mi'
  bool   _showSpeedHud  = true;
  bool   _offRouteAlert = true;

  // ── Getters ────────────────────────────────────────────────
  bool   get ttsMuted      => _ttsMuted;
  int    get searchRadiusKm => _searchRadius;
  String get distUnit      => _distUnit;
  bool   get showSpeedHud  => _showSpeedHud;
  bool   get offRouteAlert => _offRouteAlert;

  // ── 로드 ──────────────────────────────────────────────────
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _ttsMuted      = p.getBool(_kTtsMuted)      ?? false;
    _searchRadius  = p.getInt(_kSearchRadius)    ?? 50;
    _distUnit      = p.getString(_kDistUnit)     ?? 'km';
    _showSpeedHud  = p.getBool(_kShowSpeedHud)   ?? true;
    _offRouteAlert = p.getBool(_kOffRouteAlert)  ?? true;
    notifyListeners();
  }

  // ── Setters ────────────────────────────────────────────────
  Future<void> setTtsMuted(bool v) async {
    if (_ttsMuted == v) return;
    _ttsMuted = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTtsMuted, v);
  }

  Future<void> setSearchRadius(int v) async {
    assert(v == 30 || v == 50 || v == 100);
    if (_searchRadius == v) return;
    _searchRadius = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSearchRadius, v);
  }

  Future<void> setDistUnit(String v) async {
    if (_distUnit == v) return;
    _distUnit = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDistUnit, v);
  }

  Future<void> setShowSpeedHud(bool v) async {
    if (_showSpeedHud == v) return;
    _showSpeedHud = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowSpeedHud, v);
  }

  Future<void> setOffRouteAlert(bool v) async {
    if (_offRouteAlert == v) return;
    _offRouteAlert = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOffRouteAlert, v);
  }
}
