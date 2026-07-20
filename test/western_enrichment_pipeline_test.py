from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import anyio

from test.western_enrichment_fixture import (
    FixtureTransport,
    make_manifest,
    make_route,
    overpass_payload,
)
from tools.curvature_pipeline.western_enrichment import (
    EnrichmentRuntime,
    OverpassHttpResponse,
    RunStatus,
    TileRequest,
    run_enrichment,
)


class WesternEnrichmentPipelineTest(unittest.TestCase):
    def test_overlapping_hubs_share_tile_and_reconcile_route_accounting(self) -> None:
        # Given: two selected pilot routes from overlapping western hubs.
        manifest = make_manifest(
            [
                make_route("route-a", "calgary-west", 51.01, -114.01),
                make_route("route-b", "calgary-east", 51.02, -114.02),
            ]
        )
        request = TileRequest.for_coordinate(
            lat=51.01,
            lng=-114.01,
            tile_size_deg=0.15,
            version=manifest.versions.overpass,
        )
        transport = FixtureTransport(
            {
                (
                    "https://overpass-api.de/api/interpreter",
                    request.cache_key,
                ): (OverpassHttpResponse(status_code=200, body=overpass_payload()),)
            }
        )

        # When: the manifest is enriched through the persisted pipeline.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: the tile is fetched once and every selected route is complete.
        self.assertEqual(result.status, RunStatus.READY)
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(transport.calls[0][2], 12.0)
        self.assertEqual(result.summary.attempted, 2)
        self.assertEqual(result.summary.succeeded, 2)
        self.assertEqual(result.summary.failed, 0)
        self.assertEqual(result.summary.skipped, 0)
        self.assertEqual(
            result.summary.attempted,
            result.summary.succeeded + result.summary.failed + result.summary.skipped,
        )
        self.assertEqual(result.summary.unique_tile_queries, 1)
        self.assertEqual(result.summary.request_attempts, 1)
        self.assertTrue(all(route.activation_eligible for route in result.routes))
        self.assertTrue(all(route.failed_fields == () for route in result.routes))

    def test_resume_skips_completed_route_and_reuses_versioned_tile_state(self) -> None:
        # Given: one route completed before a second selected route is introduced.
        first_route = make_route("route-a", "calgary", 51.01, -114.01)
        second_route = make_route("route-b", "edmonton", 53.55, -113.49)
        first_manifest = make_manifest([first_route])
        full_manifest = make_manifest([first_route, second_route])
        first_request = TileRequest.for_coordinate(
            lat=51.01,
            lng=-114.01,
            tile_size_deg=0.15,
            version=first_manifest.versions.overpass,
        )
        second_request = TileRequest.for_coordinate(
            lat=53.55,
            lng=-113.49,
            tile_size_deg=0.15,
            version=full_manifest.versions.overpass,
        )

        # When: a later run resumes from the same state directory.
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory)
            first_transport = FixtureTransport(
                {
                    (
                        "https://overpass-api.de/api/interpreter",
                        first_request.cache_key,
                    ): (OverpassHttpResponse(status_code=200, body=overpass_payload()),)
                }
            )
            first = anyio.run(
                run_enrichment,
                first_manifest,
                state_dir,
                EnrichmentRuntime(first_transport),
            )
            resumed_transport = FixtureTransport(
                {
                    (
                        "https://overpass-api.de/api/interpreter",
                        second_request.cache_key,
                    ): (OverpassHttpResponse(status_code=200, body=overpass_payload()),)
                }
            )
            resumed = anyio.run(
                run_enrichment,
                full_manifest,
                state_dir,
                EnrichmentRuntime(resumed_transport),
            )

        # Then: only unfinished work performs a request and accounting remains exact.
        self.assertEqual(first.summary.succeeded, 1)
        self.assertEqual(resumed.summary.attempted, 2)
        self.assertEqual(resumed.summary.succeeded, 1)
        self.assertEqual(resumed.summary.skipped, 1)
        self.assertEqual(resumed.summary.failed, 0)
        self.assertEqual(len(resumed_transport.calls), 1)
        self.assertEqual(resumed_transport.calls[0][1], second_request.cache_key)

    def test_overpass_fetches_never_exceed_concurrency_two(self) -> None:
        # Given: three selected routes in distinct tiles.
        locations = (
            ("route-a", "calgary", 51.01, -114.01),
            ("route-b", "edmonton", 53.55, -113.49),
            ("route-c", "red-deer", 52.27, -113.81),
        )
        routes = [make_route(*location) for location in locations]
        manifest = make_manifest(routes)
        responses: dict[tuple[str, str], tuple[OverpassHttpResponse, ...]] = {}
        for _, _, lat, lng in locations:
            request = TileRequest.for_coordinate(
                lat=lat,
                lng=lng,
                tile_size_deg=0.15,
                version=manifest.versions.overpass,
            )
            responses[
                ("https://overpass-api.de/api/interpreter", request.cache_key)
            ] = (OverpassHttpResponse(status_code=200, body=overpass_payload()),)
        transport = FixtureTransport(responses, hold_for_pair=True)

        # When: unique tiles are fetched concurrently.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: the limiter reaches but never exceeds two active requests.
        self.assertEqual(result.status, RunStatus.READY)
        self.assertEqual(transport.peak_active, 2)
        self.assertLessEqual(transport.peak_active, 2)
