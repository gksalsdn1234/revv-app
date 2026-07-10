import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revv_app/models/revv_route.dart';
import 'package:revv_app/services/region_photo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RegionPhotoService parses Wikimedia thumbnail URL', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = RegionPhotoService(
      prefs: prefs,
      client: MockClient((request) async {
        if (request.url.queryParameters['list'] == 'geosearch') {
          return http.Response(
            '{"query":{"geosearch":[{"title":"File:Road.jpg"}]}}',
            200,
          );
        }
        return http.Response(
          '{"query":{"pages":{"1":{"imageinfo":[{"thumburl":"https://img.example/road.jpg"}]}}}}',
          200,
        );
      }),
      now: () => DateTime(2026, 7, 9),
    );

    final url = await service.photoUrl(
      geohash4: 'f25d',
      point: const LatLng(45.6, -74.0),
    );

    expect(url, 'https://img.example/road.jpg');
    expect(prefs.getString('region_photo:f25d'), url);
  });

  test('RegionPhotoService uses cache without another request', () async {
    SharedPreferences.setMockInitialValues({
      'region_photo:f25d': 'https://img.example/cached.jpg',
      'region_photo:f25d:ts': DateTime(2026, 7, 1).millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    var requests = 0;
    final service = RegionPhotoService(
      prefs: prefs,
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 500);
      }),
      now: () => DateTime(2026, 7, 9),
    );

    final url = await service.photoUrl(
      geohash4: 'f25d',
      point: const LatLng(45.6, -74.0),
    );

    expect(url, 'https://img.example/cached.jpg');
    expect(requests, 0);
  });

  test('RegionPhotoService returns null on Wikimedia failure', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = RegionPhotoService(
      prefs: prefs,
      client: MockClient((request) async => http.Response('{}', 500)),
      now: () => DateTime(2026, 7, 9),
    );

    final url = await service.photoUrl(
      geohash4: 'f25d',
      point: const LatLng(45.6, -74.0),
    );

    expect(url, isNull);
  });
}
