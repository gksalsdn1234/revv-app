import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/imu_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ImuService stays idle until an active drive starts', () {
    SharedPreferences.setMockInitialValues({});

    final service = ImuService();

    expect(service.isActive, isFalse);
    service.dispose();
  });
}
