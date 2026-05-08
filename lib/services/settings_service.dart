import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage_keys.dart';
import 'route_loading_policy.dart';

class SettingsService extends ChangeNotifier {
  bool _ttsMuted = false;
  int _searchRadius = 50;
  RouteFilterStrength _routeFilterStrength = RouteFilterStrength.balanced;
  String _distUnit = 'km';

  bool get ttsMuted => _ttsMuted;
  int get searchRadiusKm => _searchRadius;
  RouteFilterStrength get routeFilterStrength => _routeFilterStrength;
  String get distUnit => _distUnit;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsMuted = prefs.getBool(StorageKeys.ttsMuted) ?? false;
    _searchRadius = _normalizeSearchRadius(
      prefs.getInt(StorageKeys.searchRadius) ?? 50,
    );
    _routeFilterStrength = routeFilterStrengthFromStorage(
      prefs.getString(StorageKeys.routeFilterStrength),
    );
    _distUnit = prefs.getString(StorageKeys.distUnit) ?? 'km';
    notifyListeners();
  }

  Future<void> setTtsMuted(bool value) async {
    if (_ttsMuted == value) return;
    _ttsMuted = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.ttsMuted, value);
  }

  Future<void> setSearchRadius(int value) async {
    final next = _normalizeSearchRadius(value);
    if (_searchRadius == next) return;
    _searchRadius = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageKeys.searchRadius, next);
  }

  Future<void> setRouteFilterStrength(RouteFilterStrength value) async {
    if (_routeFilterStrength == value) return;
    _routeFilterStrength = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StorageKeys.routeFilterStrength,
      routeFilterStrengthStorageValue(value),
    );
  }

  Future<void> setDistUnit(String value) async {
    final next = value == 'mi' ? 'mi' : 'km';
    if (_distUnit == next) return;
    _distUnit = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.distUnit, next);
  }

  int _normalizeSearchRadius(int value) {
    const allowed = [30, 50, 100, 160, 220];
    if (allowed.contains(value)) return value;
    return allowed.reduce(
      (best, current) =>
          (value - current).abs() < (value - best).abs() ? current : best,
    );
  }
}
