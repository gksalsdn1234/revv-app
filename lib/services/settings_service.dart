import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_language.dart';
import '../core/storage_keys.dart';
import 'route_loading_policy.dart';

class SettingsService extends ChangeNotifier {
  bool _ttsMuted = false;
  AppLanguage _appLanguage = AppLanguage.english;
  int _searchRadius = 50;
  RouteFilterStrength _routeFilterStrength = RouteFilterStrength.balanced;
  String _distUnit = 'km';
  bool _cloudRunStorageEnabled = false;
  Set<String> _regionRequestGrids = const {};

  bool get ttsMuted => _ttsMuted;
  AppLanguage get appLanguage => _appLanguage;
  int get searchRadiusKm => _searchRadius;
  RouteFilterStrength get routeFilterStrength => _routeFilterStrength;
  String get distUnit => _distUnit;
  bool get cloudRunStorageEnabled => _cloudRunStorageEnabled;
  bool hasRequestedRegion(String gridKey) =>
      _regionRequestGrids.contains(gridKey);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsMuted = prefs.getBool(StorageKeys.ttsMuted) ?? false;
    // iOS native permission sheets choose their copy from the platform's
    // preferred language, not Flutter's MaterialApp locale. Keep the app on
    // that same source of truth so a location/microphone/motion request cannot
    // appear in a different language from the surrounding UI. The old
    // persisted value is intentionally ignored for users upgrading from a
    // build that exposed an in-app language switch.
    _appLanguage = appLanguageFromLocaleCode(
      PlatformDispatcher.instance.locale.languageCode,
    );
    _searchRadius = _normalizeSearchRadius(
      prefs.getInt(StorageKeys.searchRadius) ?? 50,
    );
    _routeFilterStrength = routeFilterStrengthFromStorage(
      prefs.getString(StorageKeys.routeFilterStrength),
    );
    _distUnit = prefs.getString(StorageKeys.distUnit) ?? 'km';
    _cloudRunStorageEnabled =
        prefs.getBool(StorageKeys.cloudRunStorageEnabled) ?? false;
    _regionRequestGrids =
        prefs.getStringList(StorageKeys.regionRequestGrids)?.toSet() ??
        const {};
    notifyListeners();
  }

  Future<void> setTtsMuted(bool value) async {
    if (_ttsMuted == value) return;
    _ttsMuted = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.ttsMuted, value);
  }

  /// Test-only copy override. Released builds always derive language from the
  /// platform so Flutter UI and iOS permission sheets stay in sync.
  @visibleForTesting
  Future<void> setAppLanguage(AppLanguage value) async {
    assert(() {
      if (_appLanguage != value) {
        _appLanguage = value;
        notifyListeners();
      }
      return true;
    }());
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

  Future<void> setCloudRunStorageEnabled(bool value) async {
    if (_cloudRunStorageEnabled == value) return;
    _cloudRunStorageEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.cloudRunStorageEnabled, value);
  }

  Future<void> markRegionRequested(String gridKey) async {
    if (_regionRequestGrids.contains(gridKey)) return;
    _regionRequestGrids = {..._regionRequestGrids, gridKey};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      StorageKeys.regionRequestGrids,
      _regionRequestGrids.toList()..sort(),
    );
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
