from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

try:
    from supabase import Client, create_client
except ModuleNotFoundError:  # pragma: no cover - optional local dependency
    Client = Any  # type: ignore[assignment]
    create_client = None

if __package__:
    from ..curvature_pipeline.quality_metadata import apply_quality_metadata
else:
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[1] / "curvature_pipeline"))
    from quality_metadata import apply_quality_metadata


DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / "output"


def get_client() -> Client:
    import os

    if create_client is None:
        raise RuntimeError(
            "The Python 'supabase' package is not installed. "
            "Install tools/curvature_pipeline/requirements.txt first."
        )
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")
    return create_client(url, key)


def fetch_candidates(
    client: Client,
    *,
    lat: float,
    lng: float,
    radius_m: int,
    top_n: int,
) -> list[dict[str, Any]]:
    response = client.rpc(
        "find_curvy_roads",
        {
            "user_lat": lat,
            "user_lng": lng,
            "radius_m": radius_m,
            "min_score": 0,
            "max_results": top_n,
        },
    ).execute()
    rows = response.data or []
    return [dict(row) for row in rows]


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def to_bool_flag(value: bool) -> str:
    return "yes" if value else ""


def build_audit_rows(routes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    audit_rows: list[dict[str, Any]] = []
    for index, route in enumerate(routes, start=1):
        derived = apply_quality_metadata(route)
        quality_mismatch = normalize_text(route.get("quality_label")) != normalize_text(
            derived.get("quality_label")
        )
        character_mismatch = normalize_text(route.get("route_character")) != normalize_text(
            derived.get("route_character")
        )
        reason_mismatch = normalize_text(route.get("primary_reason")) != normalize_text(
            derived.get("primary_reason")
        )
        caution_mismatch = normalize_text(route.get("caution_note")) != normalize_text(
            derived.get("caution_note")
        )

        audit_rows.append(
            {
                "rank_position": index,
                "id": normalize_text(route.get("id")),
                "name": normalize_text(route.get("name")),
                "distance_km": route.get("distance_km", 0),
                "distance_from_user_km": route.get("distance_from_user_km", 0),
                "winding_score": route.get("winding_score", 0),
                "fun_score": route.get("fun_score", 0),
                "flow_score": route.get("flow_score", 0),
                "driveability_penalty": route.get("driveability_penalty", 0),
                "residential_penalty": route.get("residential_penalty", 0),
                "route_rank_score": route.get("route_rank_score", 0),
                "tight_curve_km": route.get("tight_curve_km", 0),
                "medium_curve_km": route.get("medium_curve_km", 0),
                "max_continuous_km": route.get("max_continuous_km", 0),
                "stop_sign_count": route.get("stop_sign_count", 0),
                "traffic_signal_count": route.get("traffic_signal_count", 0),
                "stop_control_density": route.get("stop_control_density", 0),
                "residential_ratio": route.get("residential_ratio", 0),
                "urban_friction_score": route.get("urban_friction_score", 0),
                "quality_label": normalize_text(route.get("quality_label")),
                "route_character": normalize_text(route.get("route_character")),
                "primary_reason": normalize_text(route.get("primary_reason")),
                "caution_note": normalize_text(route.get("caution_note")),
                "derived_quality_label": normalize_text(derived.get("quality_label")),
                "derived_route_character": normalize_text(derived.get("route_character")),
                "derived_primary_reason": normalize_text(derived.get("primary_reason")),
                "derived_caution_note": normalize_text(derived.get("caution_note")),
                "quality_mismatch": to_bool_flag(quality_mismatch),
                "character_mismatch": to_bool_flag(character_mismatch),
                "reason_mismatch": to_bool_flag(reason_mismatch),
                "caution_mismatch": to_bool_flag(caution_mismatch),
            }
        )
    return audit_rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "routes": len(rows),
        "quality_mismatches": sum(1 for row in rows if row["quality_mismatch"]),
        "character_mismatches": sum(1 for row in rows if row["character_mismatch"]),
        "reason_mismatches": sum(1 for row in rows if row["reason_mismatch"]),
        "caution_mismatches": sum(1 for row in rows if row["caution_mismatch"]),
        "keep_routes": sum(1 for row in rows if row["quality_label"] == "keep"),
        "maybe_routes": sum(1 for row in rows if row["quality_label"] == "maybe"),
        "reject_routes": sum(1 for row in rows if row["quality_label"] == "reject"),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export internal route audit rows from Supabase with metadata mismatch checks"
    )
    parser.add_argument("--region-name", required=True)
    parser.add_argument("--lat", required=True, type=float)
    parser.add_argument("--lng", required=True, type=float)
    parser.add_argument("--radius-m", type=int, default=50000)
    parser.add_argument("--top-n", type=int, default=200)
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    args = parser.parse_args(argv)

    client = get_client()
    routes = fetch_candidates(
        client,
        lat=args.lat,
        lng=args.lng,
        radius_m=args.radius_m,
        top_n=args.top_n,
    )
    audit_rows = build_audit_rows(routes)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    slug = f"{args.region_name}_top{args.top_n}_audit"
    json_path = output_dir / f"{slug}.json"
    csv_path = output_dir / f"{slug}.csv"

    json_path.write_text(
        json.dumps(audit_rows, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    write_csv(csv_path, audit_rows)

    print(
        json.dumps(
            {
                "region_name": args.region_name,
                "radius_m": args.radius_m,
                "top_n": args.top_n,
                "csv_path": str(csv_path),
                "json_path": str(json_path),
                "summary": summarize(audit_rows),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
