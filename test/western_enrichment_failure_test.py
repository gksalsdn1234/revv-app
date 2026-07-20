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
from tools.curvature_pipeline.western_enrichment.model import SelectionClass


class WesternEnrichmentFailureTest(unittest.TestCase):
    def test_timeout_fails_over_once_to_second_endpoint(self) -> None:
        # Given: the primary endpoint times out and the fallback is healthy.
        manifest = make_manifest([make_route("route-a", "calgary", 51.01, -114.01)])
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
                ): (OverpassHttpResponse.timeout(),),
                (
                    "https://overpass.kumi.systems/api/interpreter",
                    request.cache_key,
                ): (OverpassHttpResponse(status_code=200, body=overpass_payload()),),
            }
        )

        # When: enrichment runs with the fixed one-retry policy.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: exactly two attempts occur and the route succeeds.
        self.assertEqual(result.status, RunStatus.READY)
        self.assertEqual(result.summary.request_attempts, 2)
        self.assertEqual(
            [call[0] for call in transport.calls],
            [
                "https://overpass-api.de/api/interpreter",
                "https://overpass.kumi.systems/api/interpreter",
            ],
        )

    def test_429_then_malformed_payload_fails_without_success_stamp(self) -> None:
        # Given: both bounded attempts fail on retryable response classes.
        manifest = make_manifest([make_route("route-a", "calgary", 51.01, -114.01)])
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
                ): (OverpassHttpResponse(status_code=429, body=b"{}"),),
                (
                    "https://overpass.kumi.systems/api/interpreter",
                    request.cache_key,
                ): (OverpassHttpResponse(status_code=200, body=b"not-json"),),
            }
        )

        # When: the selected first-batch route cannot be enriched.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: it is failed, shadow-ineligible, and produces no success metadata.
        self.assertEqual(result.status, RunStatus.NO_GO_INCOMPLETE_GENERATED)
        self.assertEqual(result.exit_code, 2)
        self.assertEqual(result.summary.request_attempts, 2)
        self.assertEqual(result.summary.attempted, 1)
        self.assertEqual(result.summary.failed, 1)
        self.assertEqual(result.summary.succeeded, 0)
        self.assertFalse(result.routes[0].activation_eligible)
        self.assertIn("stop_control", result.routes[0].failed_fields)
        self.assertIsNone(result.routes[0].metadata)

    def test_missing_elevation_fails_closed_before_overpass(self) -> None:
        # Given: a selected generated route has no elevation evidence.
        route = make_route("route-a", "calgary", 51.01, -114.01).model_copy(
            update={"elevation_evidence": None}
        )
        manifest = make_manifest([route])
        transport = FixtureTransport({})

        # When: preflight validates activation evidence.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: no Overpass request runs and the route is explicitly incomplete.
        self.assertEqual(result.status, RunStatus.NO_GO_INCOMPLETE_GENERATED)
        self.assertEqual(result.summary.failed, 1)
        self.assertEqual(result.summary.request_attempts, 0)
        self.assertEqual(transport.calls, [])
        self.assertIn("elevation", result.routes[0].failed_fields)

    def test_more_than_120_unique_tiles_returns_no_go_before_requests(self) -> None:
        # Given: a malicious manifest expands beyond the fixed unique-tile ceiling.
        routes = [
            make_route(
                f"route-{index:03d}",
                "western-sweep",
                45.0 + index * 0.2,
                -130.0,
                batch=SelectionClass.EXPANSION,
            )
            for index in range(121)
        ]
        manifest = make_manifest(routes)
        transport = FixtureTransport({})

        # When: request planning runs.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: the whole batch is a no-go with zero network attempts.
        self.assertEqual(result.status, RunStatus.NO_GO_REQUEST_BUDGET)
        self.assertEqual(result.exit_code, 3)
        self.assertEqual(result.summary.unique_tile_queries, 121)
        self.assertEqual(result.summary.request_attempts, 0)
        self.assertEqual(result.summary.failed, 121)
        self.assertEqual(transport.calls, [])

    def test_empty_200_payload_fails_closed_without_metadata_stamp(self) -> None:
        # Given: both bounded endpoints return an empty but syntactically valid payload.
        manifest = make_manifest([make_route("route-a", "calgary", 51.01, -114.01)])
        request = TileRequest.for_coordinate(
            lat=51.01,
            lng=-114.01,
            tile_size_deg=0.15,
            version=manifest.versions.overpass,
        )
        responses = {
            (endpoint, request.cache_key): (
                OverpassHttpResponse(status_code=200, body=b'{"elements":[]}'),
            )
            for endpoint in (
                "https://overpass-api.de/api/interpreter",
                "https://overpass.kumi.systems/api/interpreter",
            )
        }

        # When: the selected generated route is enriched.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(FixtureTransport(responses)),
            )

        # Then: empty evidence is retried once and never stamped as success.
        self.assertEqual(result.status, RunStatus.NO_GO_INCOMPLETE_GENERATED)
        self.assertEqual(result.summary.request_attempts, 2)
        self.assertEqual(result.summary.failed, 1)
        self.assertIsNone(result.routes[0].metadata)
        self.assertFalse(result.routes[0].activation_eligible)

    def test_over_8_mib_response_fails_before_parse_or_stamp(self) -> None:
        # Given: both endpoints exceed the immutable response-byte ceiling.
        manifest = make_manifest([make_route("route-a", "calgary", 51.01, -114.01)])
        request = TileRequest.for_coordinate(
            lat=51.01,
            lng=-114.01,
            tile_size_deg=0.15,
            version=manifest.versions.overpass,
        )
        oversized = (
            overpass_payload()[:-1] + b',"padding":"' + b"x" * (8 * 1024 * 1024) + b'"}'
        )
        responses = {
            (endpoint, request.cache_key): (
                OverpassHttpResponse(status_code=200, body=oversized),
            )
            for endpoint in (
                "https://overpass-api.de/api/interpreter",
                "https://overpass.kumi.systems/api/interpreter",
            )
        }

        # When: the route reaches the wire response boundary.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(FixtureTransport(responses)),
            )

        # Then: two bounded attempts fail with no cache or success metadata.
        self.assertEqual(result.status, RunStatus.NO_GO_INCOMPLETE_GENERATED)
        self.assertEqual(result.summary.request_attempts, 2)
        self.assertEqual(result.summary.succeeded, 0)
        self.assertIsNone(result.routes[0].metadata)
