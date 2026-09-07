import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// No coordinates, request bodies, response contents, tokens or user IDs.
class RoutePerformance {
  static const enabled = kDebugMode || bool.fromEnvironment('REVV_ROUTE_PERF');
  static void Function(String, Map<String, num>)? observer;
  static void record(String stage, Map<String, num> values) {
    observer?.call(stage, values);
    if (enabled) debugPrint('[REVV][RoutePerf] $stage $values');
  }

  static T measureSync<T>(String stage, T Function() work) {
    final timer = Stopwatch()..start();
    try {
      return work();
    } finally {
      record(stage, {'ms': timer.elapsedMicroseconds / 1000});
    }
  }

  static Future<T> measure<T>(String stage, Future<T> Function() work) async {
    final timer = Stopwatch()..start();
    var success = false;
    try {
      final result = await work();
      success = true;
      return result;
    } finally {
      record(stage, {
        'ms': timer.elapsedMicroseconds / 1000,
        'ok': success ? 1 : 0,
      });
    }
  }
}

/// Measures response headers and consumed body bytes, not compressed wire bytes.
class RouteTimingClient extends http.BaseClient {
  RouteTimingClient(this.inner);
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final name = request.url.path.split('/').last;
    if (!request.url.path.contains('/rest/v1/rpc/') ||
        !(name.startsWith('find_curvy_') || name.startsWith('get_route_'))) {
      return inner.send(request);
    }
    final timer = Stopwatch()..start();
    final response = await inner.send(request);
    RoutePerformance.record('rpc.$name.headers', {
      'ms': timer.elapsedMicroseconds / 1000,
      'status': response.statusCode,
    });
    Stream<List<int>> counted() async* {
      var bytes = 0;
      var complete = false;
      try {
        await for (final chunk in response.stream) {
          bytes += chunk.length;
          yield chunk;
        }
        complete = true;
      } finally {
        RoutePerformance.record('rpc.$name.body', {
          'ms': timer.elapsedMicroseconds / 1000,
          'bytes': bytes,
          'complete': complete ? 1 : 0,
        });
      }
    }

    return http.StreamedResponse(
      counted(),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => inner.close();
}
