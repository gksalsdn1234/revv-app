from __future__ import annotations

import hashlib
import json
import math
import argparse
from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence


PointDict = dict[str, float]
RoadInput = Mapping[str, object]
RoadRecord = dict[str, object]


@dataclass(frozen=True)
class CurveThresholds:
    tight_deg_per_km: float = 200.0
    medium_deg_per_km: float = 20.0


def normalize_point(point: Mapping[str, object]) -> PointDict:
    lat = point.get("lat")
    lng = point.get("lng")
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        raise ValueError("point must contain numeric lat/lng")
    return {"lat": float(lat), "lng": float(lng)}


def downsample_nodes(nodes: Sequence[Mapping[str, object]], max_points: int = 300) -> list[PointDict]:
    points = [normalize_point(node) for node in nodes]
    if len(points) <= max_points:
        return points
    if max_points < 2:
        raise ValueError("max_points must be at least 2")

    last_index = len(points) - 1
    step = last_index / (max_points - 1)
    selected_indices: list[int] = []
    previous = -1
    for i in range(max_points):
        idx = min(last_index, int(round(i * step)))
        if idx <= previous:
            idx = min(last_index, previous + 1)
        selected_indices.append(idx)
        previous = idx
    selected_indices[0] = 0
    selected_indices[-1] = last_index
    return [points[idx] for idx in selected_indices]


def haversine_km(a: Mapping[str, object], b: Mapping[str, object]) -> float:
    lat1 = float(a["lat"])
    lng1 = float(a["lng"])
    lat2 = float(b["lat"])
    lng2 = float(b["lng"])
    radius = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    sin_lat = math.sin(d_lat / 2)
    sin_lng = math.sin(d_lng / 2)
    h = sin_lat * sin_lat + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * sin_lng * sin_lng
    return 2 * radius * math.asin(math.sqrt(h))


def _bearing_degrees(a: Mapping[str, object], b: Mapping[str, object]) -> float:
    lat1 = math.radians(float(a["lat"]))
    lat2 = math.radians(float(b["lat"]))
    d_lng = math.radians(float(b["lng"]) - float(a["lng"]))
    y = math.sin(d_lng) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(d_lng)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def _bearing_delta(prev_bearing: float, next_bearing: float) -> float:
    delta = abs(next_bearing - prev_bearing) % 360.0
    return 360.0 - delta if delta > 180.0 else delta


def center_point(nodes: Sequence[Mapping[str, object]]) -> PointDict:
    points = [normalize_point(node) for node in nodes]
    if not points:
        raise ValueError("nodes cannot be empty")
    lat = sum(p["lat"] for p in points) / len(points)
    lng = sum(p["lng"] for p in points) / len(points)
    return {"lat": lat, "lng": lng}


def total_distance_km(nodes: Sequence[Mapping[str, object]]) -> float:
    points = [normalize_point(node) for node in nodes]
    total = 0.0
    for idx in range(len(points) - 1):
        total += haversine_km(points[idx], points[idx + 1])
    return total


def is_loop(nodes: Sequence[Mapping[str, object]]) -> bool:
    points = [normalize_point(node) for node in nodes]
    if len(points) < 10:
        return False
    return haversine_km(points[0], points[-1]) < 3.0


def encode_geohash(lat: float, lng: float, precision: int = 4) -> str:
    chars = "0123456789bcdefghjkmnpqrstuvwxyz"
    min_lat, max_lat = -90.0, 90.0
    min_lng, max_lng = -180.0, 180.0
    bits = 0
    value = 0
    is_lng = True
    out: list[str] = []

    while len(out) < precision:
        if is_lng:
            mid = (min_lng + max_lng) / 2
            if lng >= mid:
                value = (value << 1) | 1
                min_lng = mid
            else:
                value <<= 1
                max_lng = mid
        else:
            mid = (min_lat + max_lat) / 2
            if lat >= mid:
                value = (value << 1) | 1
                min_lat = mid
            else:
                value <<= 1
                max_lat = mid
        is_lng = not is_lng
        bits += 1
        if bits == 5:
            out.append(chars[value])
            bits = 0
            value = 0
    return "".join(out)


def stable_road_id(name: str, center_lat: float, center_lng: float) -> str:
    raw = f"{name}:{center_lat:.4f}:{center_lng:.4f}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def compute_bearing_rate_profile(
    nodes: Sequence[Mapping[str, object]],
    thresholds: CurveThresholds | None = None,
) -> dict[str, float]:
    thresholds = thresholds or CurveThresholds()
    points = [normalize_point(node) for node in nodes]
    if len(points) < 3:
        return {
            "distance_km": total_distance_km(points),
            "total_curvature_deg": 0.0,
            "curvature_density": 0.0,
            "tight_curve_km": 0.0,
            "medium_curve_km": 0.0,
            "max_continuous_km": 0.0,
            "curvy_distance_km": 0.0,
            "sharp_curve_count": 0.0,
            "straight_fraction": 1.0,
        }

    distance_km = total_distance_km(points)
    total_curvature_deg = 0.0
    total_curvature_deg_km = 0.0
    tight_curve_km = 0.0
    medium_curve_km = 0.0
    curvy_distance_km = 0.0
    sharp_curve_count = 0
    current_continuous_km = 0.0
    max_continuous_km = 0.0
    straight_distance_km = 0.0

    for idx in range(len(points) - 2):
        a = points[idx]
        b = points[idx + 1]
        c = points[idx + 2]
        prev_bearing = _bearing_degrees(a, b)
        next_bearing = _bearing_degrees(b, c)
        delta = _bearing_delta(prev_bearing, next_bearing)
        segment_km = (haversine_km(a, b) + haversine_km(b, c)) / 2.0
        rate = delta / max(segment_km, 1e-6)

        total_curvature_deg += delta
        total_curvature_deg_km += delta * segment_km

        if rate >= thresholds.medium_deg_per_km:
            curvy_distance_km += segment_km
            current_continuous_km += segment_km
            max_continuous_km = max(max_continuous_km, current_continuous_km)
        else:
            straight_distance_km += segment_km
            current_continuous_km = 0.0

        if rate >= thresholds.tight_deg_per_km:
            tight_curve_km += segment_km
            sharp_curve_count += 1
        elif rate >= thresholds.medium_deg_per_km:
            medium_curve_km += segment_km

    density = total_curvature_deg / max(distance_km, 1e-6)
    straight_fraction = straight_distance_km / max(distance_km, 1e-6)
    return {
        "distance_km": distance_km,
        "total_curvature_deg": total_curvature_deg,
        "curvature_integral_deg_km": total_curvature_deg_km,
        "curvature_density": density,
        "tight_curve_km": tight_curve_km,
        "medium_curve_km": medium_curve_km,
        "max_continuous_km": max_continuous_km,
        "curvy_distance_km": curvy_distance_km,
        "sharp_curve_count": float(sharp_curve_count),
        "straight_fraction": straight_fraction,
    }


def winding_score(distance_km: float, curvature_density: float) -> float:
    if distance_km <= 0:
        return 0.0
    return curvature_density * math.sqrt(distance_km)


def star_rating_for_score(score: float) -> int:
    if score >= 8.0:
        return 5
    if score >= 5.5:
        return 4
    if score >= 3.5:
        return 3
    if score >= 2.0:
        return 2
    return 1


def analyze_road(road: RoadInput, max_points: int = 300) -> RoadRecord:
    name = str(road.get("name", "") or "").strip()
    raw_nodes = road.get("nodes")
    if not isinstance(raw_nodes, Sequence):
        raise ValueError("road must contain nodes")

    nodes = downsample_nodes(raw_nodes, max_points=max_points)
    if len(nodes) < 2:
        raise ValueError("road must contain at least two valid nodes")

    center = center_point(nodes)
    profile = compute_bearing_rate_profile(nodes)
    distance_km = profile["distance_km"]
    curvature_density = profile["curvature_density"]
    score = winding_score(distance_km, curvature_density)
    rating = star_rating_for_score(score)
    curvature_score = float(road.get("curvature_score", 0.0) or 0.0)

    return {
        "id": stable_road_id(name, center["lat"], center["lng"]),
        "name": name,
        "nodes": nodes,
        "center_lat": center["lat"],
        "center_lng": center["lng"],
        "distance_km": distance_km,
        "curvature_score": curvature_score,
        "winding_score": score,
        "star_rating": rating,
        "tight_curve_km": profile["tight_curve_km"],
        "medium_curve_km": profile["medium_curve_km"],
        "max_continuous_km": profile["max_continuous_km"],
        "is_loop": is_loop(nodes),
        "elevation_delta": float(road.get("elevation_delta", 0.0) or 0.0),
        "geohash4": encode_geohash(center["lat"], center["lng"], 4),
        "region": road.get("region") or "",
        "source": road.get("source") or "roadcurvature",
        "curvy_distance_km": profile["curvy_distance_km"],
        "sharp_curve_count": int(profile["sharp_curve_count"]),
        "straight_fraction": profile["straight_fraction"],
        "curvature_integral_deg_km": profile["curvature_integral_deg_km"],
        "total_curvature_deg": profile["total_curvature_deg"],
    }


def analyze_roads(roads: Iterable[RoadInput], max_points: int = 300) -> list[RoadRecord]:
    return [analyze_road(road, max_points=max_points) for road in roads]


def to_json(records: Sequence[RoadRecord]) -> str:
    return json.dumps(records, ensure_ascii=False, indent=2)


def from_json(raw: str) -> list[RoadRecord]:
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError("expected a JSON array")
    return [dict(item) for item in data]


def load_json_file(path: str) -> list[RoadRecord]:
    with open(path, "r", encoding="utf-8") as handle:
        return from_json(handle.read())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyze road placemarks into Supabase-ready records")
    parser.add_argument("input", help="JSON file created by parse_kml.py")
    parser.add_argument("-o", "--output", help="Write analyzed JSON to file")
    parser.add_argument("--max-points", type=int, default=300, help="Maximum nodes per road")
    args = parser.parse_args(argv)

    records = load_json_file(args.input)
    analyzed = analyze_roads(records, max_points=args.max_points)
    payload = to_json(analyzed)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(payload)
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
