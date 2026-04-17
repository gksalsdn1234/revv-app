from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

if __package__:
    from .enrich_stop_controls import (
        DEFAULT_TILE_SIZE_DEG,
        build_bbox,
        haversine_km,
        load_overpass_payload,
        nearest_route_distance_km,
        tile_keys_for_bbox,
    )
    from .residential_metadata import apply_residential_metadata
else:
    import sys

    sys.path.append(str(Path(__file__).resolve().parent))
    from enrich_stop_controls import (
        DEFAULT_TILE_SIZE_DEG,
        build_bbox,
        haversine_km,
        load_overpass_payload,
        nearest_route_distance_km,
        tile_keys_for_bbox,
    )
    from residential_metadata import apply_residential_metadata


ROAD_CLASSES = ("residential", "living_street", "service", "unclassified", "tertiary")
LOCAL_CLASSES = {"residential", "living_street", "service", "unclassified"}
RESIDENTIAL_CLASSES = {"residential", "living_street"}


def load_residential_payload_for_bbox(
    bbox: tuple[float, float, float, float],
    timeout_seconds: int,
) -> dict[str, Any]:
    south, west, north, east = bbox
    query = f"""
[out:json][timeout:{timeout_seconds}];
(
  way["highway"~"residential|living_street|service|unclassified|tertiary"]({south},{west},{north},{east});
  way["building"]({south},{west},{north},{east});
);
out tags geom;
"""
    return load_overpass_payload(query, timeout_seconds)


class TileResidentialCache:
    def __init__(
        self,
        *,
        loader: Any = load_residential_payload_for_bbox,
        tile_size_deg: float = DEFAULT_TILE_SIZE_DEG,
        cache_dir: Path | None = None,
    ) -> None:
        self.loader = loader
        self.tile_size_deg = tile_size_deg
        self.payload_cache: dict[tuple[int, int], dict[str, Any]] = {}
        self.cache_dir = cache_dir
        self.cache_hits = 0
        self.cache_misses = 0
        if self.cache_dir is not None:
            self.cache_dir.mkdir(parents=True, exist_ok=True)

    def tile_bbox(self, tile_key: tuple[int, int]) -> tuple[float, float, float, float]:
        lat_index, lng_index = tile_key
        south = lat_index * self.tile_size_deg
        west = lng_index * self.tile_size_deg
        north = south + self.tile_size_deg
        east = west + self.tile_size_deg
        return (south, west, north, east)

    def _cache_path(self, tile_key: tuple[int, int]) -> Path | None:
        if self.cache_dir is None:
            return None
        lat_index, lng_index = tile_key
        return self.cache_dir / f"{lat_index}_{lng_index}.json"

    def _load_from_disk(self, tile_key: tuple[int, int]) -> dict[str, Any] | None:
        path = self._cache_path(tile_key)
        if path is None or not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def _write_to_disk(self, tile_key: tuple[int, int], payload: dict[str, Any]) -> None:
        path = self._cache_path(tile_key)
        if path is None:
            return
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    def payload_for_tile(self, tile_key: tuple[int, int], timeout_seconds: int) -> dict[str, Any]:
        if tile_key not in self.payload_cache:
            disk_payload = self._load_from_disk(tile_key)
            if disk_payload is not None:
                self.cache_hits += 1
                self.payload_cache[tile_key] = disk_payload
            else:
                self.cache_misses += 1
                payload = self.loader(self.tile_bbox(tile_key), timeout_seconds)
                self.payload_cache[tile_key] = payload
                self._write_to_disk(tile_key, payload)
        return self.payload_cache[tile_key]

    def fetch_for_route(
        self,
        route_nodes: list[dict[str, float]],
        *,
        padding_deg: float,
        timeout_seconds: int,
        distance_km: float,
    ) -> dict[str, float]:
        route_bbox = build_bbox(route_nodes, padding_deg)
        elements: list[dict[str, Any]] = []
        for tile_key in tile_keys_for_bbox(route_bbox, tile_size_deg=self.tile_size_deg):
            payload = self.payload_for_tile(tile_key, timeout_seconds)
            elements.extend(payload.get("elements", []))

        class_lengths_km = defaultdict(float)
        total_road_km = 0.0
        building_hits = 0
        node_occurrence: dict[tuple[float, float], int] = defaultdict(int)

        for element in elements:
            tags = element.get("tags", {}) or {}
            geometry = element.get("geometry") or []
            highway = str(tags.get("highway", "") or "")
            is_building = "building" in tags

            if highway in ROAD_CLASSES and isinstance(geometry, list) and len(geometry) >= 2:
                points = []
                for point in geometry:
                    lat = point.get("lat")
                    lng = point.get("lon")
                    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                        continue
                    points.append({"lat": float(lat), "lng": float(lng)})
                if len(points) < 2:
                    continue
                if min(nearest_route_distance_km(route_nodes, point) for point in points) > 0.08:
                    continue

                way_length_km = 0.0
                nearby_keys: set[tuple[float, float]] = set()
                for index in range(len(points) - 1):
                    way_length_km += haversine_km(points[index], points[index + 1])
                for point in points:
                    if nearest_route_distance_km(route_nodes, point) <= 0.05:
                        nearby_keys.add((round(point["lat"], 5), round(point["lng"], 5)))
                for key in nearby_keys:
                    node_occurrence[key] += 1

                total_road_km += way_length_km
                class_lengths_km[highway] += way_length_km
                continue

            if is_building:
                center = element.get("center") or {}
                lat = center.get("lat")
                lng = center.get("lon")
                if (not isinstance(lat, (int, float)) or not isinstance(lng, (int, float))) and isinstance(geometry, list) and geometry:
                    coords = [
                        (float(point["lat"]), float(point["lon"]))
                        for point in geometry
                        if isinstance(point.get("lat"), (int, float)) and isinstance(point.get("lon"), (int, float))
                    ]
                    if coords:
                        lat = sum(coord[0] for coord in coords) / len(coords)
                        lng = sum(coord[1] for coord in coords) / len(coords)
                if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                    continue
                point = {"lat": float(lat), "lng": float(lng)}
                if nearest_route_distance_km(route_nodes, point) <= 0.08:
                    building_hits += 1

        route_distance_km = max(distance_km, 1.0)
        residential_km = sum(class_lengths_km[road_class] for road_class in RESIDENTIAL_CLASSES)
        service_km = class_lengths_km["service"]
        local_km = sum(class_lengths_km[road_class] for road_class in LOCAL_CLASSES)
        denominator = max(total_road_km, 0.001)
        intersection_hits = sum(1 for count in node_occurrence.values() if count >= 2)
        building_density = building_hits / route_distance_km
        residential_ratio = residential_km / denominator
        service_ratio = service_km / denominator
        local_road_ratio = local_km / denominator
        intersection_density = intersection_hits / route_distance_km
        housing_proximity_score = min(
            1.0,
            residential_ratio * 0.55 + local_road_ratio * 0.15 + min(building_density / 10.0, 1.0) * 0.30,
        )

        return {
            "residential_ratio": residential_ratio,
            "service_ratio": service_ratio,
            "local_road_ratio": local_road_ratio,
            "intersection_density": intersection_density,
            "building_density": building_density,
            "housing_proximity_score": housing_proximity_score,
        }


def enrich_record(
    record: dict[str, Any],
    padding_deg: float,
    timeout_seconds: int,
    tile_cache: TileResidentialCache,
    version: str,
) -> dict[str, Any]:
    nodes = record.get("nodes") or []
    if not isinstance(nodes, list) or len(nodes) < 2:
        return record
    metrics = tile_cache.fetch_for_route(
        nodes,
        padding_deg=padding_deg,
        timeout_seconds=timeout_seconds,
        distance_km=float(record.get("distance_km", 0.0) or 0.0),
    )
    updated = dict(record)
    updated.update(metrics)
    return apply_residential_metadata(updated, version=version)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Enrich analyzed routes with residential context from Overpass")
    parser.add_argument("input", help="JSON file produced by process_roads.py")
    parser.add_argument("-o", "--output", help="Write enriched JSON to file")
    parser.add_argument("--padding-deg", type=float, default=0.0004)
    parser.add_argument("--timeout-seconds", type=int, default=12)
    parser.add_argument("--tile-size-deg", type=float, default=DEFAULT_TILE_SIZE_DEG)
    parser.add_argument("--tile-cache-dir")
    parser.add_argument("--version", default="residential-v1")
    args = parser.parse_args(argv)

    records = json.loads(Path(args.input).read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("expected a JSON array")
    cache = TileResidentialCache(
        tile_size_deg=args.tile_size_deg,
        cache_dir=Path(args.tile_cache_dir) if args.tile_cache_dir else None,
    )
    enriched = [
        enrich_record(dict(record), args.padding_deg, args.timeout_seconds, cache, args.version)
        for record in records
    ]
    payload = json.dumps(enriched, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(payload, encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
