from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path

from ..western_selection.model import QualityCandidate
from .model import RejectedRecord


def canonical_json_bytes(payload: object) -> bytes:
    return json.dumps(
        payload, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def accepted_geojson_bytes(candidates: tuple[QualityCandidate, ...]) -> bytes:
    features = [
        {
            "type": "Feature",
            "properties": {
                "route_id": candidate.route.route_id,
                "hub_id": candidate.route.hub_id,
                "province_code": candidate.route.province_code,
                "distance_m": round(candidate.route.distance_m, 3),
                "curved_distance_m": round(candidate.curved_distance_m, 3),
                "is_loop": candidate.route.is_loop,
                "geohash4": candidate.geohash4,
            },
            "geometry": {
                "type": "LineString",
                "coordinates": [
                    [round(point.lng, 8), round(point.lat, 8)]
                    for point in candidate.route.geometry
                ],
            },
        }
        for candidate in sorted(candidates, key=lambda item: item.route.route_id)
    ]
    return canonical_json_bytes({"type": "FeatureCollection", "features": features})


def sample_route_geojson_bytes(candidate: QualityCandidate) -> bytes:
    feature = {
        "type": "Feature",
        "properties": {
            "route_id": candidate.route.route_id,
            "hub_id": candidate.route.hub_id,
            "province_code": candidate.route.province_code,
            "distance_m": round(candidate.route.distance_m, 3),
            "curved_distance_m": round(candidate.curved_distance_m, 3),
            "max_straight_run_m": round(candidate.max_straight_run_m, 3),
            "is_loop": candidate.route.is_loop,
        },
        "geometry": {
            "type": "LineString",
            "coordinates": [
                [round(point.lng, 8), round(point.lat, 8)]
                for point in candidate.route.geometry
            ],
        },
    }
    return canonical_json_bytes(feature)


def rejected_json_bytes(records: tuple[RejectedRecord, ...]) -> bytes:
    payload = [
        {
            "id": record.route_or_seed_id,
            "stage": record.stage,
            "reason": record.reason,
            "hub_id": record.hub_id,
            "province_code": record.province_code,
            "detail": record.detail,
        }
        for record in sorted(
            records, key=lambda item: (item.stage, item.reason, item.route_or_seed_id)
        )
    ]
    return canonical_json_bytes(payload)


def rejected_csv_bytes(records: tuple[RejectedRecord, ...]) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["id", "stage", "reason", "hub_id", "province_code", "detail"])
    for record in sorted(
        records, key=lambda item: (item.stage, item.reason, item.route_or_seed_id)
    ):
        writer.writerow(
            [
                record.route_or_seed_id,
                record.stage,
                record.reason,
                record.hub_id,
                record.province_code,
                record.detail,
            ]
        )
    return buffer.getvalue().encode("utf-8")


def write_bytes_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".part")
    _ = temporary.write_bytes(data)
    _ = temporary.replace(path)
