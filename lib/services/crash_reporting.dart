import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

bool get isCrashReportingEnabled =>
    kReleaseMode && _sentryDsn.trim().isNotEmpty;

Future<void> runWithCrashReporting(FutureOr<void> Function() appRunner) async {
  if (!isCrashReportingEnabled) {
    await appRunner();
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
  }, appRunner: appRunner);
}
