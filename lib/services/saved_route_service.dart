import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';

class SavedRouteService extends ChangeNotifier {
  static const _key = 'saved_routes';

  List<RevvRoute> _routes = [];
  List<RevvRoute> get routes => List.unmodifiable(_routes);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _routes = RevvRoute.listFromJson(raw);
      notifyListeners();
    }
  }

  bool isSaved(String routeId) => _routes.any((r) => r.id == routeId);

  Future<void> toggle(RevvRoute route) async {
    if (isSaved(route.id)) {
      _routes.removeWhere((r) => r.id == route.id);
    } else {
      _routes.insert(0, route);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RevvRoute.listToJson(_routes));
  }
}
