from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import UTC, datetime
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


def load_context_payload_for_bbox(
    bbox: tuple[float, float, float, float],
    timeout_seconds: int,
) -> dict[str, Any]:
    south, west, north, east = bbox
    query = f"""
[out:json][timeout:{timeout_seconds}];
(
  way["highway"]({south},{west},{north},{east});
  node["tourism"="viewpoint"]({south},{west},{north},{east});
  node["natural"~"peak|water|wood|beach"]({south},{west},{north},{east});
  node["amenity"~"fuel|cafe|parking"]({south},{west},{north},{east});
);
out geom;
"""
    return load_overpass_payload(query, timeout_seconds)


class TileRouteContextCache:
    def __init__(
        self,
        *,
        loader: Any = load_context_payload_for_bbox,
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
        return (south, west, south + self.tile_size_deg, west + self.tile_size_deg)

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
    ) -> dict[str, Any]:
        route_bbox = build_bbox(route_nodes, padding_deg)
        elements: list[dict[str, Any]] = []
        for tile_key in tile_keys_for_bbox(route_bbox, tile_size_deg=self.tile_size_deg):
            payload = self.payload_for_tile(tile_key, timeout_seconds)
            elements.extend(payload.get("elements", []))
        return summarize_route_context(route_nodes, elements)


def summarize_route_context(
    route_nodes: list[dict[str, float]],
    elements: list[dict[str, Any]],
) -> dict[str, Any]:
    road_names: Counter[str] = Counter()
    road_refs: Counter[str] = Counter()
    highway_classes: Counter[str] = Counter()
    surfaces: Counter[str] = Counter()
    speed_limits: Counter[str] = Counter()
    nearby_pois: list[dict[str, Any]] = []

    for element in elements:
        tags = element.get("tags", {}) or {}
        element_type = element.get("type")
        geometry = element.get("geometry") or []
        if element_type == "way" and isinstance(geometry, list) and len(geometry) >= 2:
            points = _way_points(geometry)
            if not points:
                continue
            if min(nearest_route_distance_km(route_nodes, point) for point in points) > 0.09:
                continue
            approx_length = _polyline_length_km(points)
            weight = max(approx_length, 0.05)
            _add_weighted(road_names, _tag_text(tags, "name"), weight)
            _add_weighted(road_refs, _tag_text(tags, "ref"), weight)
            _add_weighted(highway_classes, _tag_text(tags, "highway"), weight)
            _add_weighted(surfaces, _tag_text(tags, "surface"), weight)
            _add_weighted(speed_limits, _tag_text(tags, "maxspeed"), weight)
            continue

        poi = _poi_from_element(element, route_nodes)
        if poi is not None:
            nearby_pois.append(poi)

    nearby_pois.sort(key=lambda poi: (poi["distance_km"], poi["name"]))
    compact_pois = _dedupe_pois(nearby_pois)[:6]
    dominant_highway = _top_keys(highway_classes, 3)
    route_context = {
        "dominant_highways": dominant_highway,
        "road_refs": _top_keys(road_refs, 4),
        "surfaces": _top_keys(surfaces, 4),
        "speed_limits": _top_keys(speed_limits, 4),
        "nearby_pois": compact_pois,
    }
    return {
        "road_names": _top_keys(road_names, 5),
        "surface_summary": _summary_from_counter(surfaces, fallback=""),
        "speed_limit_summary": _summary_from_counter(speed_limits, fallback=""),
        "nearby_pois": compact_pois,
        "route_context": route_context,
    }


def enrich_record(
    record: dict[str, Any],
    padding_deg: float,
    timeout_seconds: int,
    tile_cache: TileRouteContextCache,
    version: str,
) -> dict[str, Any]:
    nodes = record.get("nodes") or []
    if not isinstance(nodes, list) or len(nodes) < 2:
        return record
    context = tile_cache.fetch_for_route(
        nodes,
        padding_deg=padding_deg,
        timeout_seconds=timeout_seconds,
    )
    updated = dict(record)
    updated.update(context)
    updated["context_version"] = version
    updated["context_enriched_at"] = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    return updated


def _way_points(geometry: list[Any]) -> list[dict[str, float]]:
    points: list[dict[str, float]] = []
    for point in geometry:
        if not isinstance(point, dict):
            continue
        lat = point.get("lat")
        lon = point.get("lon")
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
            points.append({"lat": float(lat), "lng": float(lon)})
    return points


def _polyline_length_km(points: list[dict[str, float]]) -> float:
    return sum(haversine_km(points[index], points[index + 1]) for index in range(len(points) - 1))


def _tag_text(tags: dict[str, Any], key: str) -> str | None:
    value = tags.get(key)
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _add_weighted(counter: Counter[str], value: str | None, weight: float) -> None:
    if value:
        counter[value] += weight


def _top_keys(counter: Counter[str], limit: int) -> list[str]:
    return [key for key, _ in counter.most_common(limit) if key]


def _summary_from_counter(counter: Counter[str], *, fallback: str) -> str:
    keys = _top_keys(counter, 2)
    if not keys:
        return fallback
    return " / ".join(keys)


def _poi_from_element(
    element: dict[str, Any],
    route_nodes: list[dict[str, float]],
) -> dict[str, Any] | None:
    tags = element.get("tags", {}) or {}
    lat = element.get("lat")
    lon = element.get("lon")
    center = element.get("center") or {}
    if not isinstance(lat, (int, float)):
        lat = center.get("lat")
    if not isinstance(lon, (int, float)):
        lon = center.get("lon")
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        return None
    point = {"lat": float(lat), "lng": float(lon)}
    distance = nearest_route_distance_km(route_nodes, point)
    if distance > 0.7:
        return None
    category = _poi_category(tags)
    if category is None:
        return None
    name = _tag_text(tags, "name") or _tag_text(tags, "name:en") or category
    return {
        "name": name,
        "category": category,
        "distance_km": round(distance, 2),
    }


def _poi_category(tags: dict[str, Any]) -> str | None:
    if tags.get("tourism") == "viewpoint":
        return "viewpoint"
    if tags.get("natural") in {"peak", "water", "wood", "beach"}:
        return str(tags["natural"])
    if tags.get("amenity") in {"fuel", "cafe", "parking"}:
        return str(tags["amenity"])
    return None


def _dedupe_pois(pois: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, str]] = set()
    result: list[dict[str, Any]] = []
    for poi in pois:
        key = (str(poi.get("name", "")).lower(), str(poi.get("category", "")))
        if key in seen:
            continue
        seen.add(key)
        result.append(poi)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Enrich routes with road names, surface, speed, and POI context")
    parser.add_argument("input", help="JSON file produced by process_roads.py")
    parser.add_argument("-o", "--output", help="Write enriched JSON to file")
    parser.add_argument("--padding-deg", type=float, default=0.0008)
    parser.add_argument("--timeout-seconds", type=int, default=12)
    parser.add_argument("--tile-size-deg", type=float, default=DEFAULT_TILE_SIZE_DEG)
    parser.add_argument("--tile-cache-dir")
    parser.add_argument("--version", default="route-context-v1")
    args = parser.parse_args(argv)

    records = json.loads(Path(args.input).read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("expected a JSON array")
    cache = TileRouteContextCache(
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
