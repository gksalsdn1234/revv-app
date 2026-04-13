import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/revv_route.dart';
import 'supabase_service.dart';

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

    final sync = SupabaseService();
    if (sync.isReady) {
      final remote = await sync.loadSavedRoutes();
      if (remote.isNotEmpty) {
        _routes = _mergeRemote(_routes, remote);
        await _persist();
        notifyListeners();
      }
    }
  }

  bool isSaved(String routeId) => _routes.any((r) => r.id == routeId);

  Future<void> toggle(RevvRoute route) async {
    final shouldSave = !isSaved(route.id);
    if (shouldSave) {
      _routes.insert(0, route);
    } else {
      _routes.removeWhere((r) => r.id == route.id);
    }
    await _persist();
    notifyListeners();

    final sync = SupabaseService();
    if (sync.isReady) {
      await sync.saveRouteBookmark(route, saved: shouldSave);
    }
  }

  List<RevvRoute> _mergeRemote(List<RevvRoute> local, List<RevvRoute> remote) {
    final map = <String, RevvRoute>{};
    for (final route in remote) {
      map[route.id] = route;
    }
    for (final route in local) {
      map[route.id] = route;
    }
    return map.values.toList();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RevvRoute.listToJson(_routes));
  }
}
