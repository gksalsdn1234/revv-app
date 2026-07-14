import unittest
import tempfile
import csv
import zipfile
from pathlib import Path

from tools.curvature_pipeline.download_kmz import validated_download_url
from tools.curvature_pipeline.enrich_stop_controls import (
    TileControlCache,
    build_bbox,
    tile_keys_for_bbox,
)
from tools.curvature_pipeline.enrich_region_batch import (
    load_regions,
    should_skip_residential,
    should_skip_context,
    select_region,
    should_skip_quality,
    should_skip_route,
)
from tools.curvature_pipeline.enrich_route_context import (
    TileRouteContextCache,
    summarize_route_context,
)
from tools.curvature_pipeline.quality_metadata import (
    apply_quality_metadata,
    route_character,
)
from tools.curvature_pipeline.residential_metadata import (
    apply_residential_metadata,
    compute_residential_penalty,
)
from tools.curvature_pipeline.process_roads import (
    compute_bearing_rate_profile,
    downsample_nodes,
    stable_road_id,
    analyze_road,
    load_json_file,
)
from tools.curvature_pipeline.parse_kml import extract_kml_bytes_from_kmz
from tools.curvature_pipeline.upload_to_supabase import upload_records
from tools.route_audit.export_region_audit import write_csv


class CurvaturePipelineTest(unittest.TestCase):
    def test_downsample_preserves_endpoints_and_cap(self) -> None:
        nodes = [{"lat": float(i), "lng": float(i)} for i in range(500)]

        sampled = downsample_nodes(nodes, max_points=300)

        self.assertEqual(sampled[0], nodes[0])
        self.assertEqual(sampled[-1], nodes[-1])
        self.assertLessEqual(len(sampled), 300)

    def test_downsample_does_not_materialize_discarded_nodes(self) -> None:
        nodes = [{"lat": float(i), "lng": float(i)} for i in range(500)]
        nodes[1] = {"lat": "invalid", "lng": "invalid"}

        sampled = downsample_nodes(nodes, max_points=2)

        self.assertEqual(sampled, [nodes[0], nodes[-1]])

    def test_json_loader_rejects_files_above_its_byte_budget(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "roads.json"
            path.write_text('[{"id":"road-1"}]', encoding="utf-8")

            with self.assertRaises(ValueError):
                load_json_file(str(path), max_bytes=8)

    def test_kmz_parser_rejects_large_decompressed_members(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "roads.kmz"
            with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("doc.kml", b"<kml>" + (b"x" * 128) + b"</kml>")

            with self.assertRaises(ValueError):
                extract_kml_bytes_from_kmz(path, max_kml_bytes=32)

    def test_kmz_links_stay_on_the_supported_https_origin(self) -> None:
        accepted = validated_download_url(
            "https://kml.roadcurvature.com/north_america/canada/roads.kmz",
            expected_host="kml.roadcurvature.com",
        )

        self.assertEqual(accepted.scheme, "https")
        with self.assertRaises(ValueError):
            validated_download_url(
                "http://127.0.0.1/internal.kmz",
                expected_host="kml.roadcurvature.com",
            )

    def test_bearing_rate_profile_detects_curves(self) -> None:
        nodes = [
            {"lat": 45.0000, "lng": -73.0000},
            {"lat": 45.0010, "lng": -73.0000},
            {"lat": 45.0020, "lng": -72.9990},
            {"lat": 45.0030, "lng": -72.9975},
            {"lat": 45.0040, "lng": -72.9960},
        ]

        profile = compute_bearing_rate_profile(nodes)

        self.assertGreater(profile["total_curvature_deg"], 0)
        self.assertGreater(profile["medium_curve_km"], 0)
        self.assertGreaterEqual(profile["tight_curve_km"], 0)

    def test_stable_road_id_is_deterministic(self) -> None:
        road = {
            "name": "North Twist",
            "center_lat": 45.1234,
            "center_lng": -73.5678,
        }

        first = stable_road_id(road["name"], road["center_lat"], road["center_lng"])
        second = stable_road_id(road["name"], road["center_lat"], road["center_lng"])

        self.assertEqual(first, second)
        self.assertEqual(len(first), 64)

    def test_analyze_road_builds_winding_metrics(self) -> None:
        road = {
            "name": "Valley Sweep",
            "nodes": [
                {"lat": 45.0000, "lng": -73.0000},
                {"lat": 45.0015, "lng": -73.0000},
                {"lat": 45.0028, "lng": -72.9988},
                {"lat": 45.0038, "lng": -72.9974},
                {"lat": 45.0050, "lng": -72.9959},
            ],
            "curvature_score": 31.7,
        }

        analyzed = analyze_road(road)

        self.assertIn("id", analyzed)
        self.assertGreater(analyzed["distance_km"], 0)
        self.assertGreater(analyzed["winding_score"], 0)
        self.assertGreaterEqual(analyzed["star_rating"], 1)
        self.assertLessEqual(analyzed["star_rating"], 5)
        self.assertIn("nodes", analyzed)

    def test_tile_keys_for_bbox_collapses_nearby_routes_into_same_tiles(self) -> None:
        first_bbox = build_bbox(
            [
                {"lat": 45.5000, "lng": -73.6000},
                {"lat": 45.5030, "lng": -73.5950},
            ],
            0.0004,
        )
        second_bbox = build_bbox(
            [
                {"lat": 45.5010, "lng": -73.5990},
                {"lat": 45.5040, "lng": -73.5940},
            ],
            0.0004,
        )

        first_tiles = tile_keys_for_bbox(first_bbox, tile_size_deg=0.01)
        second_tiles = tile_keys_for_bbox(second_bbox, tile_size_deg=0.01)

        self.assertGreater(len(first_tiles), 0)
        self.assertTrue(first_tiles.issubset(second_tiles) or second_tiles.issubset(first_tiles))

    def test_tile_expansion_rejects_route_spans_above_budget(self) -> None:
        with self.assertRaises(ValueError):
            tile_keys_for_bbox(
                (-89.0, -179.0, 89.0, 179.0),
                tile_size_deg=0.15,
            )

    def test_audit_csv_neutralizes_formula_leading_cells(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "audit.csv"
            write_csv(path, [{"name": '=HYPERLINK("https://invalid","open")'}])

            with path.open(encoding="utf-8", newline="") as handle:
                row = next(csv.DictReader(handle))

        self.assertTrue(row["name"].startswith("'="))

    def test_privileged_uploader_rejects_non_route_tables(self) -> None:
        with self.assertRaises(ValueError):
            upload_records([], client=object(), table_name="runs")

    def test_tile_control_cache_reuses_tile_fetches_for_overlapping_routes(self) -> None:
        calls: list[tuple[float, float, float, float]] = []

        def fake_loader(bbox: tuple[float, float, float, float], timeout_seconds: int) -> dict[str, object]:
            calls.append(bbox)
            return {
                "elements": [
                    {"lat": 45.5020, "lon": -73.5975, "tags": {"traffic_sign": "stop"}},
                    {"lat": 45.5030, "lon": -73.5965, "tags": {"highway": "traffic_signals"}},
                ]
            }

        cache = TileControlCache(loader=fake_loader, tile_size_deg=0.01)
        route_a = [
            {"lat": 45.5000, "lng": -73.6000},
            {"lat": 45.5040, "lng": -73.5950},
        ]
        route_b = [
            {"lat": 45.5010, "lng": -73.5995},
            {"lat": 45.5050, "lng": -73.5945},
        ]

        first = cache.fetch_for_route(route_a, padding_deg=0.0004, timeout_seconds=8)
        first_call_count = len(calls)
        second = cache.fetch_for_route(route_b, padding_deg=0.0004, timeout_seconds=8)

        self.assertEqual(first, second)
        self.assertGreater(first_call_count, 0)
        self.assertEqual(len(calls), first_call_count)

    def test_tile_control_cache_persists_payloads_to_disk(self) -> None:
        calls: list[tuple[float, float, float, float]] = []

        def fake_loader(bbox: tuple[float, float, float, float], timeout_seconds: int) -> dict[str, object]:
            calls.append(bbox)
            return {"elements": [{"lat": 45.5, "lon": -73.6, "tags": {"traffic_sign": "stop"}}]}

        with tempfile.TemporaryDirectory() as temp_dir:
            first_cache = TileControlCache(
                loader=fake_loader,
                tile_size_deg=0.15,
                cache_dir=Path(temp_dir),
            )
            tile_key = (303, -491)
            first_cache.payload_for_tile(tile_key, timeout_seconds=8)

            second_cache = TileControlCache(
                loader=fake_loader,
                tile_size_deg=0.15,
                cache_dir=Path(temp_dir),
            )
            second_cache.payload_for_tile(tile_key, timeout_seconds=8)

        self.assertEqual(len(calls), 1)
        self.assertEqual(second_cache.cache_hits, 1)

    def test_region_config_selects_requested_region(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "regions.json"
            config_path.write_text(
                '[{"region_name":"montreal","center_lat":45.5,"center_lng":-73.5,"radius_m":100000,"top_n":500,"priority":1}]',
                encoding="utf-8",
            )
            regions = load_regions(config_path)
            selected = select_region(regions, "montreal")

        self.assertEqual(selected["top_n"], 500)

    def test_skip_logic_uses_enrichment_version_metadata(self) -> None:
        route = {"id": "route-1"}
        existing = {
            "id": "route-1",
            "stop_control_enriched_at": "2026-04-15T00:00:00Z",
            "stop_control_version": "stop-control-v1",
        }

        self.assertTrue(should_skip_route(route, existing, version="stop-control-v1"))
        self.assertFalse(should_skip_route(route, existing, version="stop-control-v2"))

    def test_skip_logic_uses_quality_version_metadata(self) -> None:
        existing = {
            "id": "route-1",
            "quality_enriched_at": "2026-04-15T00:00:00Z",
            "quality_version": "quality-v1",
        }

        self.assertTrue(should_skip_quality(existing, version="quality-v1"))
        self.assertFalse(should_skip_quality(existing, version="quality-v2"))

    def test_skip_logic_uses_residential_version_metadata(self) -> None:
        existing = {
            "id": "route-1",
            "residential_enriched_at": "2026-04-15T00:00:00Z",
            "residential_version": "residential-v1",
        }

        self.assertTrue(should_skip_residential(existing, version="residential-v1"))
        self.assertFalse(should_skip_residential(existing, version="residential-v2"))

    def test_skip_logic_uses_context_version_metadata(self) -> None:
        existing = {
            "id": "route-1",
            "context_enriched_at": "2026-04-30T00:00:00Z",
            "context_version": "route-context-v1",
        }

        self.assertTrue(should_skip_context(existing, version="route-context-v1"))
        self.assertFalse(should_skip_context(existing, version="route-context-v2"))

    def test_route_context_summarizes_roads_surface_speed_and_pois(self) -> None:
        route_nodes = [
            {"lat": 45.5000, "lng": -73.6000},
            {"lat": 45.5040, "lng": -73.5960},
        ]
        elements = [
            {
                "type": "way",
                "tags": {
                    "highway": "secondary",
                    "name": "Chemin du Lac",
                    "surface": "asphalt",
                    "maxspeed": "50",
                },
                "geometry": [
                    {"lat": 45.5001, "lon": -73.6001},
                    {"lat": 45.5039, "lon": -73.5961},
                ],
            },
            {
                "type": "node",
                "lat": 45.502,
                "lon": -73.598,
                "tags": {"tourism": "viewpoint", "name": "Belvédère Nord"},
            },
        ]

        context = summarize_route_context(route_nodes, elements)

        self.assertEqual(context["road_names"], ["Chemin du Lac"])
        self.assertEqual(context["surface_summary"], "asphalt")
        self.assertEqual(context["speed_limit_summary"], "50")
        self.assertEqual(context["nearby_pois"][0]["name"], "Belvédère Nord")

    def test_route_context_tile_cache_reuses_overlapping_payloads(self) -> None:
        calls: list[tuple[float, float, float, float]] = []

        def fake_loader(bbox: tuple[float, float, float, float], timeout_seconds: int) -> dict[str, object]:
            calls.append(bbox)
            return {"elements": []}

        cache = TileRouteContextCache(loader=fake_loader, tile_size_deg=0.15)
        route = [
            {"lat": 45.5000, "lng": -73.6000},
            {"lat": 45.5040, "lng": -73.5960},
        ]

        cache.fetch_for_route(route, padding_deg=0.0008, timeout_seconds=8)
        first_call_count = len(calls)
        cache.fetch_for_route(route, padding_deg=0.0008, timeout_seconds=8)

        self.assertGreater(first_call_count, 0)
        self.assertEqual(len(calls), first_call_count)

    def test_quality_metadata_classifies_and_explains_route(self) -> None:
        route = {
            "id": "route-1",
            "name": "North Ridge",
            "distance_km": 12.0,
            "winding_score": 6.4,
            "tight_curve_km": 1.8,
            "medium_curve_km": 0.8,
            "max_continuous_km": 1.4,
            "elevation_delta": 20.0,
            "stop_sign_count": 1,
            "traffic_signal_count": 0,
            "stop_control_density": 0.08,
            "flow_score": 0.97,
            "fun_score": 8.0,
            "driveability_penalty": 1.0,
            "is_loop": False,
            "is_named": True,
            "is_facility_like": False,
            "is_bridge_like": False,
            "is_connector_like": False,
            "is_major_road_like": False,
            "is_private_like": False,
            "road_names": ["North Ridge Road"],
            "surface_summary": "asphalt",
        }

        enriched = apply_quality_metadata(route, version="quality-v1")

        self.assertEqual(route_character(route), "tight_technical")
        self.assertEqual(enriched["quality_label"], "keep")
        self.assertEqual(enriched["route_character"], "tight_technical")
        self.assertIn("North Ridge Road", enriched["primary_reason"])
        self.assertIn("stop sign", enriched["caution_note"])
        self.assertEqual(enriched["quality_version"], "quality-v1")

    def test_residential_metadata_penalizes_urban_routes(self) -> None:
        route = {
            "distance_km": 8.0,
            "max_continuous_km": 0.8,
            "residential_ratio": 0.72,
            "service_ratio": 0.18,
            "local_road_ratio": 0.84,
            "intersection_density": 5.5,
            "building_density": 8.0,
            "housing_proximity_score": 0.82,
            "stop_control_density": 0.7,
        }

        scores = compute_residential_penalty(route)
        enriched = apply_residential_metadata(route, version="residential-v1")

        self.assertLess(scores["residential_penalty"], 0.5)
        self.assertGreater(scores["urban_friction_score"], 0.5)
        self.assertEqual(enriched["residential_version"], "residential-v1")


if __name__ == "__main__":
    unittest.main()
