import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FuelType {
  static const gasoline = 'gasoline';
  static const diesel = 'diesel';
  static const ev = 'ev';

  static String label(String t) {
    switch (t) {
      case diesel: return '디젤';
      case ev: return '전기차';
      default: return '가솔린';
    }
  }

  static String emoji(String t) {
    switch (t) {
      case diesel: return '🔵';
      case ev: return '⚡';
      default: return '⛽';
    }
  }
}

class GarageService extends ChangeNotifier {
  static const _kName    = 'garage_vehicle_name';
  static const _kHp      = 'garage_hp';
  static const _kWeight  = 'garage_weight_kg';
  static const _kTire    = 'garage_tire_width';
  static const _kFuel    = 'garage_fuel_type';

  String vehicleName  = '';
  int    horsepowerHp = 0;
  int    weightKg     = 1400;
  int    tireWidth    = 225; // mm (e.g. 225 = P225)
  String fuelType     = FuelType.gasoline;

  bool get hasVehicle => vehicleName.isNotEmpty;

  /// 타이어 폭 기반 횡G 한계 추정 (g)
  double get lateralGThreshold =>
      (0.95 * tireWidth / 225.0).clamp(0.55, 1.85);

  /// 타이어 폭 기반 종G 한계 추정 (g)
  double get longitudinalGThreshold =>
      (0.75 * tireWidth / 225.0).clamp(0.45, 1.40);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    vehicleName  = p.getString(_kName)   ?? '';
    horsepowerHp = p.getInt(_kHp)        ?? 0;
    weightKg     = p.getInt(_kWeight)    ?? 1400;
    tireWidth    = p.getInt(_kTire)      ?? 225;
    fuelType     = p.getString(_kFuel)   ?? FuelType.gasoline;
    notifyListeners();
  }

  Future<void> save({
    required String name,
    required int hp,
    required int weight,
    required int tire,
    required String fuel,
  }) async {
    vehicleName  = name;
    horsepowerHp = hp;
    weightKg     = weight;
    tireWidth    = tire;
    fuelType     = fuel;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kName,   name);
    await p.setInt(_kHp,        hp);
    await p.setInt(_kWeight,    weight);
    await p.setInt(_kTire,      tire);
    await p.setString(_kFuel,   fuel);
    notifyListeners();
  }
}
