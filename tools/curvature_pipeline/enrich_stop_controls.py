from __future__ import annotations

import argparse
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


OVERPASS_ENDPOINT = "https://overpass-api.de/api/interpreter"


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


def fetch_stop_controls(route_nodes: list[dict[str, float]], padding_deg: float, timeout_seconds: int) -> tuple[int, int]:
    south, west, north, east = build_bbox(route_nodes, padding_deg)
    query = f"""
[out:json][timeout:{timeout_seconds}];
(
  node["highway"="stop"]({south},{west},{north},{east});
  node["traffic_sign"="stop"]({south},{west},{north},{east});
  node["highway"="traffic_signals"]({south},{west},{north},{east});
);
out body;
"""
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(OVERPASS_ENDPOINT, data=body, method="POST")
    with urllib.request.urlopen(request, timeout=timeout_seconds + 2) as response:
        payload = json.loads(response.read().decode("utf-8"))

    stop_nodes: list[dict[str, float]] = []
    signal_nodes: list[dict[str, float]] = []
    for element in payload.get("elements", []):
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


def enrich_record(record: dict[str, Any], padding_deg: float, timeout_seconds: int) -> dict[str, Any]:
    nodes = record.get("nodes") or []
    if not isinstance(nodes, list) or len(nodes) < 2:
        return record

    stop_count, signal_count = fetch_stop_controls(nodes, padding_deg, timeout_seconds)
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
    args = parser.parse_args(argv)

    records = json.loads(Path(args.input).read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("expected a JSON array")

    enriched = []
    for index, record in enumerate(records, start=1):
        enriched.append(enrich_record(dict(record), args.padding_deg, args.timeout_seconds))
        if index < len(records):
            time.sleep(args.sleep_ms / 1000)

    output = json.dumps(enriched, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
