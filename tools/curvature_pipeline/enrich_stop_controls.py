from __future__ import annotations

import argparse
import json
import math
import time
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from urllib.error import HTTPError, URLError
from pathlib import Path
from typing import Any


OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.osm.ch/api/interpreter",
]
DEFAULT_TILE_SIZE_DEG = 0.15


def haversine_km(a: dict[str, float], b: dict[str, float]) -> float:
    radius = 6371.0
    d_lat = math.radians(b["lat"] - a["lat"])
    d_lng = math.radians(b["lng"] - a["lng"])
    sin_lat = math.sin(d_lat / 2)
    sin_lng = math.sin(d_lng / 2)
    h = sin_lat * sin_lat + math.cos(math.radians(a["lat"])) * math.cos(math.radians(b["lat"])) * sin_lng * sin_lng
    return 2 * radius * math.asin(math.sqrt(h))


def build_bbox(nodes: list[dict[str, float]], padding_deg: float) -> tuple[float, float, float, float]:
    lats = [node["lat"] for node in nodes]
    lngs = [node["lng"] for node in nodes]
    return (
        min(lats) - padding_deg,
        min(lngs) - padding_deg,
        max(lats) + padding_deg,
        max(lngs) + padding_deg,
    )


def dedupe_controls(nodes: list[dict[str, float]], radius_km: float = 0.05) -> list[dict[str, float]]:
    deduped: list[dict[str, float]] = []
    for node in nodes:
      if not any(haversine_km(node, existing) < radius_km for existing in deduped):
          deduped.append(node)
    return deduped


def nearest_route_distance_km(route_nodes: list[dict[str, float]], control: dict[str, float]) -> float:
    return min(haversine_km(route_node, control) for route_node in route_nodes)


def cache_key_for_bbox(bbox: tuple[float, float, float, float]) -> tuple[int, int, int, int]:
    return tuple(int(round(value * 10000)) for value in bbox)


def load_overpass_payload(query: str, timeout_seconds: int) -> dict[str, Any]:
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    last_error: Exception | None = None

    for endpoint in OVERPASS_ENDPOINTS:
        request = urllib.request.Request(endpoint, data=body, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout_seconds + 2) as response:
                return json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError) as error:
            last_error = error
            continue

    if last_error is not None:
        raise last_error
    raise RuntimeError("no overpass endpoint available")


def load_overpass_payload_for_bbox(
    bbox: tuple[float, float, float, float],
    timeout_seconds: int,
) -> dict[str, Any]:
    south, west, north, east = bbox
    query = f"""
[out:json][timeout:{timeout_seconds}];
(
  node["highway"="stop"]({south},{west},{north},{east});
  node["traffic_sign"="stop"]({south},{west},{north},{east});
  node["highway"="traffic_signals"]({south},{west},{north},{east});
);
out body;
"""
    return load_overpass_payload(query, timeout_seconds)


def _tile_origin(value: float, tile_size_deg: float) -> float:
    return math.floor(value / tile_size_deg) * tile_size_deg


def tile_keys_for_bbox(
    bbox: tuple[float, float, float, float],
    *,
    tile_size_deg: float = DEFAULT_TILE_SIZE_DEG,
) -> set[tuple[int, int]]:
    south, west, north, east = bbox
    min_lat_index = math.floor(south / tile_size_deg)
    max_lat_index = math.floor(north / tile_size_deg)
    min_lng_index = math.floor(west / tile_size_deg)
    max_lng_index = math.floor(east / tile_size_deg)
    return {
        (lat_index, lng_index)
        for lat_index in range(min_lat_index, max_lat_index + 1)
        for lng_index in range(min_lng_index, max_lng_index + 1)
    }


class TileControlCache:
    def __init__(
        self,
        *,
        loader: Any = load_overpass_payload_for_bbox,
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

    def fetch_for_route(
        self,
        route_nodes: list[dict[str, float]],
        *,
        padding_deg: float,
        timeout_seconds: int,
    ) -> tuple[int, int]:
        route_bbox = build_bbox(route_nodes, padding_deg)
        elements: list[dict[str, Any]] = []
        for tile_key in tile_keys_for_bbox(route_bbox, tile_size_deg=self.tile_size_deg):
            payload = self.payload_for_tile(tile_key, timeout_seconds)
            elements.extend(payload.get("elements", []))

        stop_nodes: list[dict[str, float]] = []
        signal_nodes: list[dict[str, float]] = []
        for element in elements:
            lat = element.get("lat")
            lng = element.get("lon")
            if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                continue
            point = {"lat": float(lat), "lng": float(lng)}
            tags = element.get("tags", {}) or {}
            is_signal = tags.get("highway") == "traffic_signals"
            if nearest_route_distance_km(route_nodes, point) > 0.08:
                continue
            if is_signal:
                signal_nodes.append(point)
            else:
                stop_nodes.append(point)

        return len(dedupe_controls(stop_nodes)), len(dedupe_controls(signal_nodes))


def fetch_stop_controls(
    route_nodes: list[dict[str, float]],
    padding_deg: float,
    timeout_seconds: int,
    tile_cache: TileControlCache,
) -> tuple[int, int]:
    return tile_cache.fetch_for_route(
        route_nodes,
        padding_deg=padding_deg,
        timeout_seconds=timeout_seconds,
    )


def enrich_record(
    record: dict[str, Any],
    padding_deg: float,
    timeout_seconds: int,
    tile_cache: TileControlCache,
    version: str,
    source: str,
) -> dict[str, Any]:
    nodes = record.get("nodes") or []
    if not isinstance(nodes, list) or len(nodes) < 2:
        return record

    stop_count, signal_count = fetch_stop_controls(nodes, padding_deg, timeout_seconds, tile_cache)
    distance_km = max(float(record.get("distance_km", 0.0) or 0.0), 1.0)
    weighted_stop_count = stop_count + signal_count * 1.5
    stop_control_density = weighted_stop_count / distance_km
    flow_score = max(0.15, min(1.0, 1.0 - stop_control_density * 0.35))

    record["stop_sign_count"] = stop_count
    record["traffic_signal_count"] = signal_count
    record["stop_control_density"] = stop_control_density
    record["flow_score"] = flow_score
    record["stop_control_enriched_at"] = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    record["stop_control_version"] = version
    record["stop_control_source"] = source
    return record


def enrich_record_legacy(record: dict[str, Any], padding_deg: float, timeout_seconds: int) -> dict[str, Any]:
    stop_nodes: list[dict[str, float]] = []
    signal_nodes: list[dict[str, float]] = []
    nodes = record.get("nodes") or []
    if not isinstance(nodes, list) or len(nodes) < 2:
        return record
    payload = load_overpass_payload_for_bbox(build_bbox(nodes, padding_deg), timeout_seconds)
    for element in payload.get("elements", []):
        lat = element.get("lat")
        lng = element.get("lon")
        if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
            continue
        point = {"lat": float(lat), "lng": float(lng)}
        tags = element.get("tags", {}) or {}
        is_signal = tags.get("highway") == "traffic_signals"
        if nearest_route_distance_km(nodes, point) > 0.08:
            continue
        if is_signal:
            signal_nodes.append(point)
        else:
            stop_nodes.append(point)

    stop_count = len(dedupe_controls(stop_nodes))
    signal_count = len(dedupe_controls(signal_nodes))
    distance_km = max(float(record.get("distance_km", 0.0) or 0.0), 1.0)
    weighted_stop_count = stop_count + signal_count * 1.5
    stop_control_density = weighted_stop_count / distance_km
    flow_score = max(0.15, min(1.0, 1.0 - stop_control_density * 0.35))

    record["stop_sign_count"] = stop_count
    record["traffic_signal_count"] = signal_count
    record["stop_control_density"] = stop_control_density
    record["flow_score"] = flow_score
    return record


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Enrich analyzed routes with stop/signals from Overpass")
    parser.add_argument("input", help="JSON file produced by process_roads.py")
    parser.add_argument("-o", "--output", help="Write enriched JSON to file")
    parser.add_argument("--padding-deg", type=float, default=0.0004, help="BBox padding in degrees")
    parser.add_argument("--timeout-seconds", type=int, default=12, help="Overpass query timeout")
    parser.add_argument("--sleep-ms", type=int, default=250, help="Delay between route requests")
    parser.add_argument(
        "--tile-cache-dir",
        help="Optional directory for persistent tile payload cache",
    )
    parser.add_argument(
        "--tile-size-deg",
        type=float,
        default=DEFAULT_TILE_SIZE_DEG,
        help="Tile size in degrees for shared Overpass fetch cache",
    )
    parser.add_argument(
        "--version",
        default="stop-control-v1",
        help="Metadata version to stamp onto enriched routes",
    )
    parser.add_argument(
        "--source",
        default="overpass_tile_cache",
        help="Metadata source tag to stamp onto enriched routes",
    )
    args = parser.parse_args(argv)

    records = json.loads(Path(args.input).read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("expected a JSON array")

    tile_cache = TileControlCache(
        tile_size_deg=args.tile_size_deg,
        cache_dir=Path(args.tile_cache_dir) if args.tile_cache_dir else None,
    )
    enriched = []
    for index, record in enumerate(records, start=1):
        try:
            enriched.append(
                enrich_record(
                    dict(record),
                    args.padding_deg,
                    args.timeout_seconds,
                    tile_cache,
                    args.version,
                    args.source,
                )
            )
        except Exception as error:
            fallback = dict(record)
            fallback["stop_sign_count"] = int(fallback.get("stop_sign_count", 0) or 0)
            fallback["traffic_signal_count"] = int(fallback.get("traffic_signal_count", 0) or 0)
            fallback["stop_control_density"] = float(fallback.get("stop_control_density", 0.0) or 0.0)
            fallback["flow_score"] = float(fallback.get("flow_score", 1.0) or 1.0)
            print(f"[warn] enrich failed for {fallback.get('id', index)}: {error}")
            enriched.append(fallback)
        if index < len(records):
            time.sleep(args.sleep_ms / 1000)

    output = json.dumps(enriched, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        print(output)
    print(
        f"[summary] tiles cached={len(tile_cache.payload_cache)} hits={tile_cache.cache_hits} misses={tile_cache.cache_misses}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
