from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import final

import anyio
import httpx2
from pydantic import ValidationError

from test.western_enrichment_fixture import (
    FixtureTransport,
    make_manifest,
    make_route,
    overpass_payload,
)
from tools.curvature_pipeline.western_enrichment import (
    EnrichmentRuntime,
    Httpx2OverpassTransport,
    OverpassHttpResponse,
    RunStatus,
    TileRequest,
    run_enrichment,
)
from tools.curvature_pipeline.western_enrichment.model import (
    CandidateKind,
    ExistingVersions,
    SelectionClass,
)


@final
class ExpiredClock:
    def __init__(self) -> None:
        self._value: float = 0.0

    def now(self) -> float:
        self._value += 3_601.0
        return self._value


@final
class NearDeadlineClock:
    def __init__(self) -> None:
        self._values: list[float] = [0.0, 3_599.0, 3_600.0]

    def now(self) -> float:
        return self._values.pop(0)


class WesternEnrichmentScopeTest(unittest.TestCase):
    def test_scope_includes_only_selected_generated_and_missing_ranked_legacy(
        self,
    ) -> None:
        # Given: selected, unselected, complete legacy, and missing legacy routes.
        generated = make_route("generated", "calgary", 51.01, -114.01)
        unselected = make_route("unselected", "calgary", 51.02, -114.02).model_copy(
            update={"selected": False}
        )
        complete_legacy = make_route(
            "legacy-complete", "calgary", 51.03, -114.03
        ).model_copy(
            update={
                "kind": CandidateKind.LEGACY,
                "selection": SelectionClass.LEGACY_LONG,
                "legacy_rank": 1,
                "existing_versions": ExistingVersions(
                    stop_control="stop-control-v2",
                    context="route-context-v2",
                    residential="residential-v3",
                    quality="quality-v4",
                    elevation="elevation-v1",
                ),
            }
        )
        missing_legacy = make_route(
            "legacy-missing", "calgary", 51.04, -114.04
        ).model_copy(
            update={
                "kind": CandidateKind.LEGACY,
                "selection": SelectionClass.LEGACY_LONG,
                "legacy_rank": 2,
            }
        )
        manifest = make_manifest(
            [generated, unselected, complete_legacy, missing_legacy]
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

        # When: the manifest is run.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport),
            )

        # Then: only accepted generated and missing ranked legacy routes are attempted.
        self.assertEqual(result.status, RunStatus.READY)
        self.assertEqual(result.summary.attempted, 2)
        self.assertEqual(
            {outcome.route_id for outcome in result.routes},
            {"generated", "legacy-missing"},
        )
        self.assertEqual(len(transport.calls), 1)

    def test_expired_batch_deadline_returns_no_go_without_request(self) -> None:
        # Given: the absolute sixty-minute deadline is already exhausted.
        manifest = make_manifest([make_route("route-a", "calgary", 51.01, -114.01)])
        transport = FixtureTransport({})

        # When: request execution checks the injected monotonic clock.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport, ExpiredClock()),
            )

        # Then: the batch fails closed before reaching either endpoint.
        self.assertEqual(result.status, RunStatus.NO_GO_TIME_BUDGET)
        self.assertEqual(result.exit_code, 3)
        self.assertEqual(result.summary.request_attempts, 0)
        self.assertEqual(result.summary.failed, 1)
        self.assertEqual(transport.calls, [])

    def test_manifest_rejects_non_western_province(self) -> None:
        # Given: a valid western manifest serialized at the trust boundary.
        manifest = make_manifest([make_route("route-a", "calgary", 51.01, -114.01)])
        invalid = manifest.model_dump_json().replace('"AB"', '"ON"')

        # When/Then: boundary parsing rejects every non-western hub and route code.
        with self.assertRaises(ValidationError):
            _ = type(manifest).model_validate_json(invalid)

    def test_request_timeout_is_capped_to_remaining_batch_deadline(self) -> None:
        # Given: one second remains in the absolute batch deadline.
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
                ): (OverpassHttpResponse(status_code=200, body=overpass_payload()),)
            }
        )

        # When: the next request is planned against the remaining deadline.
        with tempfile.TemporaryDirectory() as directory:
            result = anyio.run(
                run_enrichment,
                manifest,
                Path(directory),
                EnrichmentRuntime(transport, NearDeadlineClock()),
            )

        # Then: the request receives one second, never the nominal twelve seconds.
        self.assertEqual(transport.calls[0][2], 1.0)
        self.assertEqual(result.status, RunStatus.NO_GO_TIME_BUDGET)
        self.assertEqual(result.summary.succeeded, 0)

    def test_httpx2_adapter_combines_required_overpass_evidence(self) -> None:
        # Given: a wire adapter backed by an in-memory HTTP transport.
        observed_bodies: list[bytes] = []

        def handler(request: httpx2.Request) -> httpx2.Response:
            observed_bodies.append(request.content)
            return httpx2.Response(200, content=overpass_payload())

        request = TileRequest.for_coordinate(
            lat=51.01,
            lng=-114.01,
            tile_size_deg=0.15,
            version="overpass-west-v1",
        )

        async def exercise() -> OverpassHttpResponse:
            async with httpx2.AsyncClient(
                transport=httpx2.MockTransport(handler)
            ) as client:
                return await Httpx2OverpassTransport(client).fetch(
                    "https://overpass.test/api/interpreter",
                    request,
                    12.0,
                )

        # When: one versioned tile is fetched.
        response = anyio.run(exercise)

        # Then: a single query asks for controls, roads, and route context.
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(observed_bodies), 1)
        body = observed_bodies[0]
        self.assertIn(b"traffic_signals", body)
        self.assertIn(b"way%5B%22highway%22%5D", body)
        self.assertIn(b"viewpoint", body)
