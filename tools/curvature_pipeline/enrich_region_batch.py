from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from supabase import Client
except ImportError:  # pragma: no cover - optional CLI dependency in unit tests
    Client = Any  # type: ignore

if __package__:
    from .enrich_residential_context import (
        TileResidentialCache,
        enrich_record as enrich_residential_record,
    )
    from .enrich_route_context import (
        TileRouteContextCache,
        enrich_record as enrich_context_record,
    )
    from .enrich_stop_controls import TileControlCache, enrich_record
    from .quality_metadata import apply_quality_metadata
    from .upload_to_supabase import get_client, upload_records
else:
    import sys

    sys.path.append(str(Path(__file__).resolve().parent))
    from enrich_residential_context import (
        TileResidentialCache,
        enrich_record as enrich_residential_record,
    )
    from enrich_route_context import (
        TileRouteContextCache,
        enrich_record as enrich_context_record,
    )
    from enrich_stop_controls import TileControlCache, enrich_record
    from quality_metadata import apply_quality_metadata
    from upload_to_supabase import get_client, upload_records


DEFAULT_VERSION = "stop-control-v1"
DEFAULT_RESIDENTIAL_VERSION = "residential-v2"
DEFAULT_QUALITY_VERSION = "quality-v3"
DEFAULT_CONTEXT_VERSION = "route-context-v1"


def load_regions(path: str | Path) -> list[dict[str, Any]]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("regions config must be a JSON array")
    return [dict(item) for item in payload]


def select_region(regions: list[dict[str, Any]], region_name: str) -> dict[str, Any]:
    for region in regions:
        if region.get("region_name") == region_name:
            return region
    raise ValueError(f"unknown region: {region_name}")


def fetch_region_candidates(
    client: Client,
    *,
    center_lat: float,
    center_lng: float,
    radius_m: int,
    top_n: int,
) -> list[dict[str, Any]]:
    response = client.rpc(
        "find_curvy_roads",
        {
            "user_lat": center_lat,
            "user_lng": center_lng,
            "radius_m": radius_m,
            "min_score": 0,
            "max_results": top_n,
        },
    ).execute()
    return [dict(item) for item in (response.data or [])]


def chunked(items: list[str], size: int) -> list[list[str]]:
    return [items[index:index + size] for index in range(0, len(items), size)]


def fetch_existing_metadata(client: Client, route_ids: list[str]) -> dict[str, dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for batch in chunked(route_ids, 200):
        response = client.table("curvy_roads").select(
            "id,stop_control_enriched_at,stop_control_version,stop_control_source,"
            "residential_enriched_at,residential_version,"
            "quality_enriched_at,quality_version,"
            "context_enriched_at,context_version"
        ).in_("id", batch).execute()
        rows.extend(response.data or [])
    return {row["id"]: dict(row) for row in rows if row.get("id")}


def should_skip_route(
    route_row: dict[str, Any],
    existing_row: dict[str, Any] | None,
    *,
    version: str,
) -> bool:
    if existing_row is None:
        return False
    return bool(
        existing_row.get("stop_control_enriched_at")
        and existing_row.get("stop_control_version") == version
    )


def should_skip_quality(
    existing_row: dict[str, Any] | None,
    *,
    version: str,
) -> bool:
    if existing_row is None:
        return False
    return bool(
        existing_row.get("quality_enriched_at")
        and existing_row.get("quality_version") == version
    )


def should_skip_residential(
    existing_row: dict[str, Any] | None,
    *,
    version: str,
) -> bool:
    if existing_row is None:
        return False
    return bool(
        existing_row.get("residential_enriched_at")
        and existing_row.get("residential_version") == version
    )


def should_skip_context(
    existing_row: dict[str, Any] | None,
    *,
    version: str,
) -> bool:
    if existing_row is None:
        return False
    return bool(
        existing_row.get("context_enriched_at")
        and existing_row.get("context_version") == version
    )


def enrich_routes(
    routes: list[dict[str, Any]],
    *,
    padding_deg: float,
    timeout_seconds: int,
    tile_size_deg: float,
    tile_cache_dir: Path | None,
    version: str,
    source: str,
) -> tuple[list[dict[str, Any]], TileControlCache]:
    cache = TileControlCache(
        tile_size_deg=tile_size_deg,
        cache_dir=tile_cache_dir,
    )
    enriched = [
        enrich_record(
            dict(route),
            padding_deg,
            timeout_seconds,
            cache,
            version,
            source,
        )
        for route in routes
    ]
    return enriched, cache


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Incrementally enrich stop-control data for a configured region")
    parser.add_argument("--region", required=True, help="Region name from regions.json")
    parser.add_argument(
        "--regions-config",
        default=str(Path(__file__).resolve().parent / "regions.json"),
        help="Path to regions.json",
    )
    parser.add_argument("--top-n", type=int, help="Override region top_n")
    parser.add_argument("--radius-m", type=int, help="Override region radius_m")
    parser.add_argument("--padding-deg", type=float, default=0.0004)
    parser.add_argument("--timeout-seconds", type=int, default=12)
    parser.add_argument("--tile-size-deg", type=float, default=0.15)
    parser.add_argument(
        "--tile-cache-dir",
        default=str(Path(__file__).resolve().parent / "cache" / "stop_controls"),
        help="Persistent tile cache directory",
    )
    parser.add_argument("--output-dir", default=str(Path(__file__).resolve().parent / "data"))
    parser.add_argument("--version", default=DEFAULT_VERSION)
    parser.add_argument("--source", default="overpass_tile_cache")
    parser.add_argument("--residential-version", default=DEFAULT_RESIDENTIAL_VERSION)
    parser.add_argument("--quality-version", default=DEFAULT_QUALITY_VERSION)
    parser.add_argument("--context-version", default=DEFAULT_CONTEXT_VERSION)
    parser.add_argument("--no-upload", action="store_true")
    args = parser.parse_args(argv)

    client = get_client()
    regions = load_regions(args.regions_config)
    region = select_region(regions, args.region)
    radius_m = int(args.radius_m or region["radius_m"])
    top_n = int(args.top_n or region["top_n"])

    candidates = fetch_region_candidates(
        client,
        center_lat=float(region["center_lat"]),
        center_lng=float(region["center_lng"]),
        radius_m=radius_m,
        top_n=top_n,
    )
    route_ids = [str(route["id"]) for route in candidates if route.get("id")]
    existing = fetch_existing_metadata(client, route_ids)

    already_enriched = [
        route for route in candidates
        if should_skip_route(route, existing.get(str(route.get("id"))), version=args.version)
    ]
    stop_to_enrich = [
        route for route in candidates
        if not should_skip_route(route, existing.get(str(route.get("id"))), version=args.version)
    ]
    residential_to_update = [
        route for route in candidates
        if not should_skip_residential(existing.get(str(route.get("id"))), version=args.residential_version)
    ]
    quality_to_update = [
        route for route in candidates
        if not should_skip_quality(existing.get(str(route.get("id"))), version=args.quality_version)
    ]
    context_to_update = [
        route for route in candidates
        if not should_skip_context(existing.get(str(route.get("id"))), version=args.context_version)
    ]

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    subset_path = output_dir / f"{args.region}_top{top_n}_routes.json"
    subset_path.write_text(json.dumps(candidates, ensure_ascii=False, indent=2), encoding="utf-8")

    enriched_routes, cache = enrich_routes(
        stop_to_enrich,
        padding_deg=args.padding_deg,
        timeout_seconds=args.timeout_seconds,
        tile_size_deg=args.tile_size_deg,
        tile_cache_dir=Path(args.tile_cache_dir) if args.tile_cache_dir else None,
        version=args.version,
        source=args.source,
    )
    stop_enriched_by_id = {str(route.get("id")): route for route in enriched_routes if route.get("id")}
    residential_cache = TileResidentialCache(
        tile_size_deg=args.tile_size_deg,
        cache_dir=(Path(args.tile_cache_dir) / "residential") if args.tile_cache_dir else None,
    )
    residential_enriched_routes = [
        enrich_residential_record(
            stop_enriched_by_id.get(str(route.get("id")), dict(route)),
            args.padding_deg,
            args.timeout_seconds,
            residential_cache,
            args.residential_version,
        )
        for route in residential_to_update
    ]
    residential_enriched_by_id = {
        str(route.get("id")): route for route in residential_enriched_routes if route.get("id")
    }
    context_cache = TileRouteContextCache(
        tile_size_deg=args.tile_size_deg,
        cache_dir=(Path(args.tile_cache_dir) / "route_context") if args.tile_cache_dir else None,
    )
    context_enriched_routes = [
        enrich_context_record(
            residential_enriched_by_id.get(
                str(route.get("id")),
                stop_enriched_by_id.get(str(route.get("id")), dict(route)),
            ),
            args.padding_deg,
            args.timeout_seconds,
            context_cache,
            args.context_version,
        )
        for route in context_to_update
    ]
    context_enriched_by_id = {
        str(route.get("id")): route for route in context_enriched_routes if route.get("id")
    }
    quality_candidate_ids = {
        str(route.get("id"))
        for route in quality_to_update
        if route.get("id")
    } | set(stop_enriched_by_id.keys()) | set(residential_enriched_by_id.keys()) | set(context_enriched_by_id.keys())
    quality_enriched_routes = [
        apply_quality_metadata(
            context_enriched_by_id.get(
                str(route.get("id")),
                residential_enriched_by_id.get(
                    str(route.get("id")),
                    stop_enriched_by_id.get(str(route.get("id")), dict(route)),
                ),
            ),
            version=args.quality_version,
        )
        for route in candidates
        if str(route.get("id")) in quality_candidate_ids
    ]
    final_updates_by_id: dict[str, dict[str, Any]] = {}
    for record in enriched_routes:
        if record.get("id"):
            final_updates_by_id[str(record["id"])] = record
    for record in residential_enriched_routes:
        if record.get("id"):
            final_updates_by_id[str(record["id"])] = record
    for record in context_enriched_routes:
        if record.get("id"):
            final_updates_by_id[str(record["id"])] = record
    for record in quality_enriched_routes:
        if record.get("id"):
            final_updates_by_id[str(record["id"])] = record

    enriched_path = output_dir / f"{args.region}_top{top_n}_routes.enriched.json"
    enriched_path.write_text(
        json.dumps(list(final_updates_by_id.values()), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    if not args.no_upload and final_updates_by_id:
        upload_records(list(final_updates_by_id.values()), client=client)

    summary = {
        "region": args.region,
        "candidates": len(candidates),
        "already_enriched": len(already_enriched),
        "newly_enriched": len(enriched_routes),
        "residential_updated": len(residential_enriched_routes),
        "context_updated": len(context_enriched_routes),
        "quality_updated": len(quality_enriched_routes),
        "tiles_cached": len(cache.payload_cache),
        "cache_hits": cache.cache_hits,
        "cache_misses": cache.cache_misses,
        "residential_tiles_cached": len(residential_cache.payload_cache),
        "residential_cache_hits": residential_cache.cache_hits,
        "residential_cache_misses": residential_cache.cache_misses,
        "context_tiles_cached": len(context_cache.payload_cache),
        "context_cache_hits": context_cache.cache_hits,
        "context_cache_misses": context_cache.cache_misses,
        "uploaded": 0 if args.no_upload else len(final_updates_by_id),
        "subset_path": str(subset_path),
        "enriched_path": str(enriched_path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
