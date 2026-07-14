import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/models/exploration_cell.dart';
import 'package:revv_app/models/revv_route.dart';

void main() {
  test('encodes a point into a stable precision-seven cell with bounds', () {
    const point = LatLng(45.5019, -73.5674);

    final cell = ExplorationCell.fromPoint(point);

    expect(cell.id, RevvRoute.encodeGeohash(point.lat, point.lng, 7));
    expect(cell.bounds.contains(point), isTrue);
    expect(cell.bounds.polygon.first.lat, cell.bounds.polygon.last.lat);
    expect(cell.bounds.polygon.first.lng, cell.bounds.polygon.last.lng);
  });

  test('interpolates a driven segment without gaps larger than 75 metres', () {
    const path = [LatLng(45.5, -73.6), LatLng(45.5, -73.58)];

    final cells = ExplorationGrid.cellsForPath(path);

    expect(cells.length, greaterThan(10));
    expect(cells.first, ExplorationCell.fromPoint(path.first).id);
    expect(cells.last, ExplorationCell.fromPoint(path.last).id);
  });

  test('empty paths stay empty and repeated points remain idempotent', () {
    expect(ExplorationGrid.cellsForPath(const []), isEmpty);
    expect(
      ExplorationGrid.cellsForPath(const [
        LatLng(45.5, -73.6),
        LatLng(45.5, -73.6),
      ]),
      hasLength(1),
    );
  });

  test('hostile long segments stop at the exploration work budget', () {
    final cells = ExplorationGrid.cellsForPath(const [
      LatLng(-89, -179),
      LatLng(89, 179),
    ]);

    expect(cells, hasLength(ExplorationGrid.maxCellsPerPath));
  });

  test('invalid coordinates do not enter exploration persistence', () {
    final cells = ExplorationGrid.cellsForPath(const [
      LatLng(double.nan, -73.6),
      LatLng(45.5, -73.6),
      LatLng(95, -73.5),
    ]);

    expect(cells, [ExplorationCell.fromPoint(const LatLng(45.5, -73.6)).id]);
  });
}
