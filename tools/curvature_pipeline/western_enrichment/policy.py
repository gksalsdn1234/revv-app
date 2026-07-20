from __future__ import annotations

from dataclasses import dataclass
from typing import assert_never

from .model import (
    CandidateKind,
    EnrichmentManifest,
    OutcomeStatus,
    RouteCandidate,
    RouteOutcome,
    RunResult,
    RunStatus,
    RunSummary,
)

LEGACY_MIN_DISTANCE_M = 4_000.0
LEGACY_RANK_LIMIT = 50


@dataclass(frozen=True, slots=True)
class ResultBuild:
    status: RunStatus
    exit_code: int
    targets: tuple[RouteCandidate, ...]
    outcomes: dict[str, RouteOutcome]
    skipped: int
    unique_tile_queries: int
    request_attempts: int
    cache_hits: int


def is_target(route: RouteCandidate, manifest: EnrichmentManifest) -> bool:
    if not route.accepted or not route.selected:
        return False
    match route.kind:
        case CandidateKind.GENERATED:
            return True
        case CandidateKind.LEGACY:
            legacy_rank = route.legacy_rank or LEGACY_RANK_LIMIT + 1
            if (
                route.distance_m < LEGACY_MIN_DISTANCE_M
                or legacy_rank > LEGACY_RANK_LIMIT
            ):
                return False
            expected = manifest.versions
            existing = route.existing_versions
            return (
                existing.stop_control != expected.stop_control
                or existing.context != expected.context
                or existing.residential != expected.residential
                or existing.quality != expected.quality
                or existing.elevation != expected.elevation
            )
        case _ as unreachable:
            assert_never(unreachable)


def missing_non_overpass_evidence(
    route: RouteCandidate,
    manifest: EnrichmentManifest,
) -> tuple[str, ...]:
    missing: list[str] = []
    quality = route.quality_evidence
    elevation = route.elevation_evidence
    if quality is None or quality.version != manifest.versions.quality:
        missing.append("quality")
    if elevation is None or elevation.version != manifest.versions.elevation:
        missing.append("elevation")
    return tuple(missing)


def failed_outcome(
    route: RouteCandidate,
    fields: tuple[str, ...],
) -> RouteOutcome:
    return RouteOutcome(
        route_id=route.route_id,
        status=OutcomeStatus.FAILED,
        activation_eligible=False,
        failed_fields=tuple(sorted(fields)),
        metadata=None,
    )


def build_result(build: ResultBuild) -> RunResult:
    ordered = tuple(build.outcomes[route.route_id] for route in build.targets)
    succeeded = sum(
        1 for outcome in ordered if outcome.status is OutcomeStatus.SUCCEEDED
    )
    failed = sum(1 for outcome in ordered if outcome.status is OutcomeStatus.FAILED)
    summary = RunSummary(
        attempted=len(build.targets),
        succeeded=succeeded,
        failed=failed,
        skipped=build.skipped,
        unique_tile_queries=build.unique_tile_queries,
        request_attempts=build.request_attempts,
        cache_hits=build.cache_hits,
    )
    return RunResult(
        status=build.status,
        exit_code=build.exit_code,
        summary=summary,
        routes=ordered,
    )
