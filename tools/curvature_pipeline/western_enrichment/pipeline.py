from __future__ import annotations

import time
from pathlib import Path

import anyio

from .fetch import (
    MAX_CONCURRENCY,
    MAX_REQUEST_ATTEMPTS,
    MAX_UNIQUE_TILE_QUERIES,
    TileFetchResult,
    fetch_tile,
)
from .model import (
    CandidateKind,
    EnrichmentInvariantError,
    EnrichmentManifest,
    EnrichmentRuntime,
    OutcomeStatus,
    RouteOutcome,
    RunResult,
    RunStatus,
    TileRequest,
)
from .payload import OverpassPayload, merge_metadata
from .policy import (
    ResultBuild,
    build_result,
    failed_outcome,
    is_target,
    missing_non_overpass_evidence,
)
from .state import EnrichmentStateStore, route_fingerprint
from .tiling import tile_requests_for_route


class SystemClock:
    def now(self) -> float:
        return time.monotonic()


async def run_enrichment(
    manifest: EnrichmentManifest,
    state_root: Path,
    runtime: EnrichmentRuntime,
) -> RunResult:
    active_clock = runtime.clock or SystemClock()
    started_at = active_clock.now()
    store = EnrichmentStateStore(state_root)
    targets = tuple(route for route in manifest.routes if is_target(route, manifest))
    outcomes: dict[str, RouteOutcome] = {}
    route_requests: dict[str, tuple[TileRequest, ...]] = {}
    route_fingerprints: dict[str, str] = {}
    skipped = 0

    for route in targets:
        fingerprint = route_fingerprint(
            route.model_dump_json(), manifest.versions.model_dump_json()
        )
        route_fingerprints[route.route_id] = fingerprint
        checkpoint = store.load_route(route.route_id, fingerprint)
        if checkpoint is not None:
            outcomes[route.route_id] = checkpoint.model_copy(
                update={"status": OutcomeStatus.SKIPPED}
            )
            skipped += 1
            continue
        missing = missing_non_overpass_evidence(route, manifest)
        if missing:
            outcomes[route.route_id] = failed_outcome(route, missing)
            continue
        route_requests[route.route_id] = tile_requests_for_route(
            route, manifest.versions.overpass
        )

    planned = {
        request.cache_key: request
        for requests in route_requests.values()
        for request in requests
    }
    payloads: dict[str, OverpassPayload] = {}
    cache_hits = 0
    missing_requests: dict[str, TileRequest] = {}
    for cache_key, request in planned.items():
        cached = store.load_tile(request)
        if cached is None:
            missing_requests[cache_key] = request
        else:
            payloads[cache_key] = cached
            cache_hits += 1

    if len(missing_requests) > MAX_UNIQUE_TILE_QUERIES:
        for route in targets:
            if route.route_id not in outcomes:
                outcomes[route.route_id] = failed_outcome(route, ("request_budget",))
        return build_result(
            ResultBuild(
                status=RunStatus.NO_GO_REQUEST_BUDGET,
                exit_code=3,
                targets=targets,
                outcomes=outcomes,
                skipped=skipped,
                unique_tile_queries=len(missing_requests),
                request_attempts=0,
                cache_hits=cache_hits,
            )
        )

    fetch_results: dict[str, TileFetchResult] = {}
    limiter = anyio.CapacityLimiter(MAX_CONCURRENCY)

    async def fetch_one(request: TileRequest) -> None:
        async with limiter:
            fetch_results[request.cache_key] = await fetch_tile(
                request,
                runtime.transport,
                store,
                active_clock,
                started_at,
            )

    async with anyio.create_task_group() as task_group:
        for request in missing_requests.values():
            _ = task_group.start_soon(fetch_one, request)

    request_attempts = sum(result.attempts for result in fetch_results.values())
    if request_attempts > MAX_REQUEST_ATTEMPTS:
        raise EnrichmentInvariantError("request attempt ceiling")
    for cache_key, fetched in fetch_results.items():
        if fetched.payload is not None:
            payloads[cache_key] = fetched.payload

    time_budget_exceeded = any(
        result.time_budget_exceeded for result in fetch_results.values()
    )
    for route in targets:
        if route.route_id in outcomes:
            continue
        requests = route_requests[route.route_id]
        route_payloads = tuple(
            payloads[request.cache_key]
            for request in requests
            if request.cache_key in payloads
        )
        if len(route_payloads) != len(requests):
            outcomes[route.route_id] = failed_outcome(
                route,
                ("stop_control", "context", "residential"),
            )
            continue
        quality = route.quality_evidence
        elevation = route.elevation_evidence
        if quality is None or elevation is None:
            raise EnrichmentInvariantError("validated evidence")
        metadata = merge_metadata(
            route_payloads,
            quality,
            elevation,
            manifest.versions,
        )
        outcome = RouteOutcome(
            route_id=route.route_id,
            status=OutcomeStatus.SUCCEEDED,
            activation_eligible=route.kind is CandidateKind.GENERATED,
            failed_fields=(),
            metadata=metadata,
        )
        outcomes[route.route_id] = outcome
        store.save_route(route.route_id, route_fingerprints[route.route_id], outcome)

    if time_budget_exceeded:
        status = RunStatus.NO_GO_TIME_BUDGET
        exit_code = 3
    elif any(
        outcome.status is OutcomeStatus.FAILED and route.kind is CandidateKind.GENERATED
        for route in targets
        for outcome in (outcomes[route.route_id],)
    ):
        status = RunStatus.NO_GO_INCOMPLETE_GENERATED
        exit_code = 2
    elif any(outcome.status is OutcomeStatus.FAILED for outcome in outcomes.values()):
        status = RunStatus.PARTIAL_LEGACY
        exit_code = 0
    else:
        status = RunStatus.READY
        exit_code = 0
    return build_result(
        ResultBuild(
            status=status,
            exit_code=exit_code,
            targets=targets,
            outcomes=outcomes,
            skipped=skipped,
            unique_tile_queries=len(missing_requests),
            request_attempts=request_attempts,
            cache_hits=cache_hits,
        )
    )
