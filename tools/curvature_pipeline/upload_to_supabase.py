from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Iterable, Sequence

from supabase import Client, create_client

from .process_roads import RoadRecord, from_json


TABLE_NAME = "curvy_roads"


def get_client() -> Client:
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY are required")
    return create_client(url, key)


def normalize_record(record: RoadRecord) -> dict[str, object]:
    return {
        "id": record["id"],
        "name": record.get("name", ""),
        "center_lat": record["center_lat"],
        "center_lng": record["center_lng"],
        "nodes": record["nodes"],
        "distance_km": record["distance_km"],
        "curvature_score": record["curvature_score"],
        "winding_score": record["winding_score"],
        "star_rating": record["star_rating"],
        "tight_curve_km": record["tight_curve_km"],
        "medium_curve_km": record["medium_curve_km"],
        "max_continuous_km": record["max_continuous_km"],
        "is_loop": record["is_loop"],
        "route_rank_score": record.get("route_rank_score", 0.0),
        "fun_score": record.get("fun_score", 0.0),
        "flow_score": record.get("flow_score", 1.0),
        "driveability_penalty": record.get("driveability_penalty", 1.0),
        "stop_sign_count": record.get("stop_sign_count", 0),
        "traffic_signal_count": record.get("traffic_signal_count", 0),
        "stop_control_density": record.get("stop_control_density", 0.0),
        "road_class_bucket": record.get("road_class_bucket", ""),
        "is_named": record.get("is_named", True),
        "is_facility_like": record.get("is_facility_like", False),
        "is_bridge_like": record.get("is_bridge_like", False),
        "is_connector_like": record.get("is_connector_like", False),
        "is_major_road_like": record.get("is_major_road_like", False),
        "is_private_like": record.get("is_private_like", False),
        "elevation_delta": record.get("elevation_delta", 0.0),
        "geohash4": record.get("geohash4", ""),
        "region": record.get("region", ""),
        "source": record.get("source", "roadcurvature"),
    }


def chunked(items: Sequence[dict[str, object]], size: int) -> Iterable[list[dict[str, object]]]:
    if size <= 0:
        raise ValueError("size must be positive")
    for start in range(0, len(items), size):
        yield list(items[start:start + size])


def upload_records(
    records: Sequence[RoadRecord],
    *,
    client: Client | None = None,
    table_name: str = TABLE_NAME,
    batch_size: int = 200,
) -> None:
    client = client or get_client()
    payload = [normalize_record(record) for record in records]
    for batch in chunked(payload, batch_size):
        client.table(table_name).upsert(batch, on_conflict="id").execute()


def load_records_from_file(path: str | Path) -> list[RoadRecord]:
    raw = Path(path).read_text(encoding="utf-8")
    return from_json(raw)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Upload analyzed roads to Supabase")
    parser.add_argument("input", help="JSON file produced by process_roads.py")
    parser.add_argument("--table", default=TABLE_NAME, help="Destination table")
    parser.add_argument("--batch-size", type=int, default=200, help="Rows per upsert batch")
    parser.add_argument("--dry-run", action="store_true", help="Print payload instead of uploading")
    args = parser.parse_args(argv)

    records = load_records_from_file(args.input)
    if args.dry_run:
        print(json.dumps([normalize_record(r) for r in records], ensure_ascii=False, indent=2))
        return 0

    upload_records(records, table_name=args.table, batch_size=args.batch_size)
    print(f"uploaded {len(records)} record(s) to {args.table}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
