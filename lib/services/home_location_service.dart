import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';

class HomeLocationService extends ChangeNotifier {
  static const _latKey = 'home_lat';
  static const _lngKey = 'home_lng';
  static const _nameKey = 'home_name';

  LatLng? _home;
  String _homeName = '집';

  LatLng? get home => _home;
  String get homeName => _homeName;
  bool get isSet => _home != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_latKey);
    final lng = prefs.getDouble(_lngKey);
    if (lat != null && lng != null) {
      _home = LatLng(lat, lng);
      _homeName = prefs.getString(_nameKey) ?? '집';
      notifyListeners();
    }
  }

  Future<void> setHome(LatLng location, {String name = '집'}) async {
    _home = location;
    _homeName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_latKey, location.lat);
    await prefs.setDouble(_lngKey, location.lng);
    await prefs.setString(_nameKey, name);
    notifyListeners();
  }

  Future<void> setHomeFromCurrentLocation(double lat, double lng) async {
    await setHome(LatLng(lat, lng), name: '집');
  }
}
