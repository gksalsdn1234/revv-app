import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/services/crash_reporting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Given no SENTRY_DSN When crash reporting runs Then app starts normally',
    () async {
      var appRunnerCalls = 0;

      await runWithCrashReporting(() {
        appRunnerCalls += 1;
      });

      expect(isCrashReportingEnabled, isFalse);
      expect(appRunnerCalls, 1);
    },
  );
}
