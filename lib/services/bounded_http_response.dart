import 'dart:convert';

import 'package:http/http.dart' as http;

class HttpResponseTooLargeException implements Exception {
  const HttpResponseTooLargeException(this.maxBytes);

  final int maxBytes;
}

Future<String> getBoundedResponseBody(
  http.Client client,
  Uri uri, {
  required int maxBytes,
}) async {
  final request = http.Request('GET', uri);
  final response = await client.send(request);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    await response.stream.listen((_) {}).cancel();
    throw http.ClientException('HTTP ${response.statusCode}', uri);
  }
  if (response.contentLength != null && response.contentLength! > maxBytes) {
    await response.stream.listen((_) {}).cancel();
    throw HttpResponseTooLargeException(maxBytes);
  }

  final bytes = <int>[];
  await for (final chunk in response.stream) {
    if (bytes.length + chunk.length > maxBytes) {
      throw HttpResponseTooLargeException(maxBytes);
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}
