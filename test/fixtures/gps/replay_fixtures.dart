import 'package:revv_app/models/revv_route.dart';

class GpsReplaySample {
  final int tMs;
  final double lat;
  final double lng;
  final double speedKmh;
  final double lateralG;
  final double longitudinalG;
  final String driveMode;

  const GpsReplaySample({
    required this.tMs,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    this.lateralG = 0,
    this.longitudinalG = 0,
    this.driveMode = 'cruise',
  });
}

class GpsReplayFixture {
  final String id;
  final List<GpsReplaySample> samples;
  final double expectedDistanceKm;
  final int expectedDurationSeconds;
  final int expectedSharpCornerCount;

  const GpsReplayFixture({
    required this.id,
    required this.samples,
    required this.expectedDistanceKm,
    required this.expectedDurationSeconds,
    this.expectedSharpCornerCount = 0,
  });
}

const montrealScenicReplay = GpsReplayFixture(
  id: 'montreal-scenic-gap',
  expectedDistanceKm: 10.40817871657922,
  expectedDurationSeconds: 900,
  samples: [
    GpsReplaySample(tMs: 0, lat: 45.4915, lng: -73.8720, speedKmh: 0),
    GpsReplaySample(tMs: 60000, lat: 45.4952, lng: -73.8605, speedKmh: 38),
    GpsReplaySample(tMs: 120000, lat: 45.5000, lng: -73.8480, speedKmh: 42),
    GpsReplaySample(tMs: 420000, lat: 45.5064, lng: -73.8362, speedKmh: 44),
    GpsReplaySample(tMs: 480000, lat: 45.5127, lng: -73.8240, speedKmh: 46),
    GpsReplaySample(tMs: 560000, lat: 45.5192, lng: -73.8115, speedKmh: 48),
    GpsReplaySample(tMs: 640000, lat: 45.5250, lng: -73.7988, speedKmh: 46),
    GpsReplaySample(tMs: 720000, lat: 45.5308, lng: -73.7860, speedKmh: 45),
    GpsReplaySample(tMs: 810000, lat: 45.5370, lng: -73.7735, speedKmh: 43),
    GpsReplaySample(tMs: 900000, lat: 45.5432, lng: -73.7610, speedKmh: 40),
  ],
);

const montrealCornerReplay = GpsReplayFixture(
  id: 'montreal-corner-events',
  expectedDistanceKm: 6.480881378777362,
  expectedDurationSeconds: 720,
  expectedSharpCornerCount: 2,
  samples: [
    GpsReplaySample(tMs: 0, lat: 45.4420, lng: -73.9050, speedKmh: 0),
    GpsReplaySample(tMs: 90000, lat: 45.4450, lng: -73.8960, speedKmh: 34),
    GpsReplaySample(tMs: 180000, lat: 45.4472, lng: -73.8870, speedKmh: 38),
    GpsReplaySample(
      tMs: 270000,
      lat: 45.4460,
      lng: -73.8780,
      speedKmh: 42,
      lateralG: 0.58,
      driveMode: 'winding',
    ),
    GpsReplaySample(tMs: 360000, lat: 45.4498, lng: -73.8700, speedKmh: 40),
    GpsReplaySample(tMs: 450000, lat: 45.4560, lng: -73.8650, speedKmh: 41),
    GpsReplaySample(
      tMs: 540000,
      lat: 45.4620,
      lng: -73.8580,
      speedKmh: 44,
      lateralG: -0.62,
      driveMode: 'winding',
    ),
    GpsReplaySample(tMs: 630000, lat: 45.4675, lng: -73.8490, speedKmh: 39),
    GpsReplaySample(tMs: 720000, lat: 45.4710, lng: -73.8385, speedKmh: 35),
  ],
);

// Haversine segment sums, using RevvRoute.haversineKm:
// scenic = 0.986295 + 1.110882 + 1.162810 + 1.180901 + 1.212831
//   + 1.181052 + 1.187500 + 1.192998 + 1.192911 = 10.40817871657922 km.
// corner = 0.777355 + 0.743506 + 0.714670 + 0.753666 + 0.792083
//   + 0.862083 + 0.930941 + 0.906577 = 6.480881378777362 km.
double replayFixtureDistanceKm(GpsReplayFixture fixture) {
  var distanceKm = 0.0;
  for (var i = 1; i < fixture.samples.length; i++) {
    final previous = fixture.samples[i - 1];
    final current = fixture.samples[i];
    distanceKm += RevvRoute.haversineKm(
      LatLng(previous.lat, previous.lng),
      LatLng(current.lat, current.lng),
    );
  }
  return distanceKm;
}
