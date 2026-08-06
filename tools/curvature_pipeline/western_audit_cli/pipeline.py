from __future__ import annotations

import gc
import random
import resource
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import anyio

from ..western_enrichment.model import EnrichmentRuntime, OutcomeStatus, RunStatus
from ..western_enrichment.pipeline import run_enrichment
from ..western_graph.model import HubGraph
from ..western_routes.generator import generate_route
from ..western_routes.model import RouteGenerationError, SeedFragment
from ..western_sources.checkpoint import AcquisitionCheckpoint
from ..western_sources.manifest import WesternManifest
from ..western_seeds import (
    NativeRouteBatchResult,
    NativeSeedBatch,
    NativeSeedError,
    extract_native_seed_batches,
    generate_native_routes,
)
from ..western_selection.codec import selection_bytes
from ..western_selection.model import (
    QualityCandidate,
    QualityRejection,
    SelectionResult,
    SelectionStatus,
)
from ..western_selection.selection import select_western_batches
from .artifacts import (
    accepted_geojson_bytes,
    canonical_json_bytes,
    rejected_csv_bytes,
    rejected_json_bytes,
    sample_route_geojson_bytes,
    sha256_hex,
    write_bytes_atomic,
)
from .candidates import edges_for_route, quality_candidate_from_route
from .enrichment_bridge import (
    FixtureOverpassTransport,
    build_enrichment_manifest,
    enrichment_manifest_bytes,
    selection_checksum_bytes,
)
from .upload_bridge import build_upload_documents
from .fixtures import (
    build_default_fixture_hubs,
    build_empty_fixture_hubs,
    fixture_overpass_body,
)
from .model import (
    EXIT_CODES,
    AuditSeedSource,
    DryRunConfig,
    DryRunError,
    DryRunMode,
    DryRunStatus,
    FixtureProfile,
    HubFailure,
    HubMetric,
    RejectedRecord,
    StageTiming,
)
from .real_hub import (
    build_verified_hub_graph,
    derive_seeds_from_graph,
    load_acquisition_inputs,
    load_real_hub_graph,
)

GENERATOR_VERSION = "western-audit-cli-v1"


def _peak_rss_bytes() -> int:
    raw = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # macOS reports ru_maxrss in bytes; Linux reports it in kibibytes.
    return raw if sys.platform == "darwin" else raw * 1024


@dataclass(frozen=True, slots=True)
class _HubBundle:
    graph: HubGraph
    seeds: tuple[SeedFragment, ...]
    # Populated only when the real (Todo 6 production) seed source runs:
    # native curvature seed batches extracted from this hub's graph.
    native_batches: tuple[NativeSeedBatch, ...] = ()
    pbf_path: Path | None = None
    manifest: WesternManifest | None = None
    checkpoint: AcquisitionCheckpoint | None = None


@dataclass(frozen=True, slots=True)
class _HubLoadResult:
    bundles: tuple[_HubBundle, ...]
    failures: tuple[HubFailure, ...]
    metrics: tuple[HubMetric, ...]


@dataclass(frozen=True, slots=True)
class _HubFunnelEntry:
    hub_id: str
    province_code: str
    source_pbf_checksum: str
    hub_pbf_checksum: str
    seeds_in: int
    generated_accepted: int
    generated_rejected: dict[str, int]
    # Real seed source only: seeds that were neither consumed by an accepted
    # candidate nor charged to a rejected start, so per-hub seed accounting
    # reconciles as seeds_in = consumed + rejected_starts + seeds_unused.
    seeds_unused: int = 0


@dataclass(frozen=True, slots=True)
class DryRunOutcome:
    status: DryRunStatus
    exit_code: int
    output_dir: Path


def run_dry_run(config: DryRunConfig) -> DryRunOutcome:
    timings: list[StageTiming] = []
    started = time.perf_counter()

    stage_started = time.perf_counter()
    try:
        load_result = _load_hubs(config)
    except DryRunError as error:
        timings.append(
            StageTiming("acquisition_graph", time.perf_counter() - stage_started)
        )
        return _write_early_failure(
            config, DryRunStatus.NO_GO_CHECKSUM_MISMATCH, str(error), timings, started
        )
    hubs = load_result.bundles
    hub_failures: list[HubFailure] = list(load_result.failures)
    hub_metrics: list[HubMetric] = list(load_result.metrics)
    timings.append(
        StageTiming("acquisition_graph", time.perf_counter() - stage_started)
    )

    stage_started = time.perf_counter()
    funnel_entries: list[_HubFunnelEntry] = []
    rejected: list[RejectedRecord] = []
    quality_candidates: dict[str, QualityCandidate] = {}
    for bundle in hubs:
        try:
            graph = _graph_for_generation(bundle)
        except DryRunError as error:
            hub_failures.append(
                HubFailure(
                    hub_id=bundle.graph.hub_id,
                    stage="generation",
                    reason="hub_graph_reload_rejected",
                    detail=str(error),
                )
            )
            continue
        if config.seed_source is AuditSeedSource.REAL:
            _generate_native_hub(
                config,
                graph,
                bundle,
                quality_candidates,
                funnel_entries,
                rejected,
                hub_failures,
                hub_metrics,
            )
            if bundle.pbf_path is not None:
                del graph
                _ = gc.collect()
            continue
        rejected_by_reason: dict[str, int] = {}
        accepted_count = 0
        if bundle.seeds:
            try:
                route = generate_route(graph, bundle.seeds)
                quality_candidates[route.route_id] = quality_candidate_from_route(
                    route, edges_for_route(graph, route)
                )
                accepted_count = 1
            except RouteGenerationError as error:
                rejected_by_reason[error.reason.value] = (
                    rejected_by_reason.get(error.reason.value, 0) + 1
                )
                rejected.append(
                    RejectedRecord(
                        route_or_seed_id=",".join(
                            seed.seed_id for seed in bundle.seeds
                        ),
                        stage="generation",
                        reason=error.reason.value,
                        hub_id=graph.hub_id,
                        province_code=graph.province_code,
                        detail=error.detail,
                    )
                )
        funnel_entries.append(
            _HubFunnelEntry(
                hub_id=graph.hub_id,
                province_code=graph.province_code,
                source_pbf_checksum=graph.source_pbf_checksum,
                hub_pbf_checksum=graph.hub_pbf_checksum,
                seeds_in=len(bundle.seeds),
                generated_accepted=accepted_count,
                generated_rejected=rejected_by_reason,
            )
        )
    timings.append(StageTiming("generation", time.perf_counter() - stage_started))

    stage_started = time.perf_counter()
    selection_result = select_western_batches(
        tuple(quality_candidates.values()), snapshot=config.snapshot
    )
    for record in selection_result.rejections:
        route = quality_candidates[record.route_id].route
        detail = (
            f"overlaps with {record.overlap_route_id}"
            if record.reason is QualityRejection.OVERLAP
            else ""
        )
        rejected.append(
            RejectedRecord(
                route_or_seed_id=record.route_id,
                stage="quality",
                reason=record.reason.value,
                hub_id=route.hub_id,
                province_code=route.province_code,
                detail=detail,
            )
        )
    timings.append(StageTiming("selection", time.perf_counter() - stage_started))

    accepted_ids = frozenset(selection_result.unselected_route_ids) | frozenset(
        route_id
        for manifest in selection_result.manifests
        for route_id in manifest.route_ids
    )
    accepted_candidates = tuple(
        quality_candidates[route_id] for route_id in sorted(accepted_ids)
    )

    stage_started = time.perf_counter()
    enrichment_ran = False
    enrichment_status: RunStatus | None = None
    enrichment_summary: dict[str, int] | None = None
    enrichment_routes: list[dict[str, object]] = []
    if accepted_candidates:
        pilot_ids = frozenset(
            route_id
            for manifest in selection_result.manifests
            if manifest.batch_id.startswith("west-pilot-v1-")
            for route_id in manifest.route_ids
        )
        expansion_ids = frozenset(
            route_id
            for manifest in selection_result.manifests
            if manifest.batch_id.startswith("west-expand-v1-")
            for route_id in manifest.route_ids
        )
        enrichment_manifest = build_enrichment_manifest(
            accepted_candidates,
            pilot_ids,
            expansion_ids,
            selection_checksum_bytes(selection_bytes(selection_result)),
        )
        overpass_body = (
            config.overpass_fixture_path.read_bytes()
            if config.overpass_fixture_path is not None
            else fixture_overpass_body()
        )
        transport = FixtureOverpassTransport(overpass_body)
        state_dir = config.output_dir / "enrichment-state"
        result = anyio.run(
            run_enrichment,
            enrichment_manifest,
            state_dir,
            EnrichmentRuntime(transport),
        )
        enrichment_ran = True
        enrichment_status = result.status
        enrichment_summary = {
            "attempted": result.summary.attempted,
            "succeeded": result.summary.succeeded,
            "failed": result.summary.failed,
            "skipped": result.summary.skipped,
        }
        enrichment_routes = [
            {
                "route_id": outcome.route_id,
                "status": outcome.status.value,
                "activation_eligible": outcome.activation_eligible,
                "failed_fields": list(outcome.failed_fields),
            }
            for outcome in sorted(result.routes, key=lambda item: item.route_id)
        ]
        for outcome in result.routes:
            if outcome.status is OutcomeStatus.FAILED:
                route = quality_candidates[outcome.route_id].route
                rejected.append(
                    RejectedRecord(
                        route_or_seed_id=outcome.route_id,
                        stage="enrichment",
                        reason=",".join(outcome.failed_fields) or "unknown",
                        hub_id=route.hub_id,
                        province_code=route.province_code,
                    )
                )
        write_bytes_atomic(
            config.output_dir / "enrichment_manifest.json",
            enrichment_manifest_bytes(enrichment_manifest),
        )
    timings.append(StageTiming("enrichment", time.perf_counter() - stage_started))

    status = _final_status(selection_result, enrichment_ran, enrichment_status)

    rng = random.Random(config.seed)
    sample_pool = sorted(accepted_ids)
    sample_ids = tuple(
        sorted(rng.sample(sample_pool, k=min(config.sample_size, len(sample_pool))))
    )

    peak_rss = _peak_rss_bytes()
    elapsed_total = time.perf_counter() - started
    if (
        peak_rss > config.resource_budget.max_peak_rss_bytes
        or elapsed_total > config.resource_budget.max_elapsed_seconds
    ):
        status = DryRunStatus.NO_GO_RESOURCE_BUDGET

    _write_artifacts(
        config=config,
        hubs=hubs,
        hub_failures=tuple(hub_failures),
        hub_metrics=tuple(hub_metrics),
        funnel_entries=funnel_entries,
        rejected=tuple(rejected),
        quality_candidates=quality_candidates,
        accepted_candidates=accepted_candidates,
        selection_result=selection_result,
        enrichment_ran=enrichment_ran,
        enrichment_status=enrichment_status,
        enrichment_summary=enrichment_summary,
        enrichment_routes=enrichment_routes,
        sample_ids=sample_ids,
        status=status,
        timings=timings,
        peak_rss=peak_rss,
        elapsed_total=elapsed_total,
    )
    exit_code = EXIT_CODES[status]
    return DryRunOutcome(
        status=status, exit_code=exit_code, output_dir=config.output_dir
    )


def _generate_native_hub(
    config: DryRunConfig,
    graph: HubGraph,
    bundle: _HubBundle,
    quality_candidates: dict[str, QualityCandidate],
    funnel_entries: list[_HubFunnelEntry],
    rejected: list[RejectedRecord],
    hub_failures: list[HubFailure],
    hub_metrics: list[HubMetric],
) -> None:
    """Run the Todo 6 production generator over one hub's native seed batches.

    Mirrors the real-all per-hub safety net at the generation stage: a hub
    that blows its elapsed/RSS budget (or fails native seed resolution) is
    recorded as an explicit ``HubFailure`` and its routes are dropped from
    the pool - never silently. Observed elapsed/RSS values go only to the
    non-deterministic ``resource_metrics.json``; the deterministic failure
    entry names the fixed budget.
    """
    budget = config.resource_budget
    hub_started = time.perf_counter()
    rss_before = _peak_rss_bytes()
    result: NativeRouteBatchResult | None = None
    failure_reason: str | None = None
    failure_detail = ""
    try:
        result = generate_native_routes(graph, bundle.native_batches)
    except NativeSeedError as error:
        failure_reason = "native_seed_rejected"
        failure_detail = str(error)
    hub_elapsed = time.perf_counter() - hub_started
    rss_after = _peak_rss_bytes()
    hub_metrics.append(
        HubMetric(
            hub_id=graph.hub_id,
            elapsed_seconds=hub_elapsed,
            peak_rss_bytes_after=rss_after,
            stage="generation",
        )
    )
    if failure_reason is None and hub_elapsed > budget.max_hub_elapsed_seconds:
        failure_reason = "hub_elapsed_budget_exceeded"
        failure_detail = (
            f"hub exceeded max_hub_elapsed_seconds={budget.max_hub_elapsed_seconds}"
        )
    if (
        failure_reason is None
        and rss_after - rss_before > budget.max_hub_peak_rss_bytes
    ):
        failure_reason = "hub_rss_budget_exceeded"
        failure_detail = (
            f"hub exceeded max_hub_peak_rss_bytes={budget.max_hub_peak_rss_bytes}"
        )
    if failure_reason is not None or result is None:
        hub_failures.append(
            HubFailure(
                hub_id=graph.hub_id,
                stage="generation",
                reason=failure_reason or "native_seed_rejected",
                detail=failure_detail,
            )
        )
        return
    for route in result.routes:
        quality_candidates[route.route_id] = quality_candidate_from_route(
            route, edges_for_route(graph, route)
        )
    receipt = result.receipt
    for seed_id, reason in receipt.rejected_start_details:
        rejected.append(
            RejectedRecord(
                route_or_seed_id=seed_id,
                stage="generation",
                reason=reason.value,
                hub_id=graph.hub_id,
                province_code=graph.province_code,
            )
        )
    funnel_entries.append(
        _HubFunnelEntry(
            hub_id=graph.hub_id,
            province_code=graph.province_code,
            source_pbf_checksum=graph.source_pbf_checksum,
            hub_pbf_checksum=graph.hub_pbf_checksum,
            seeds_in=receipt.input_seed_count,
            generated_accepted=receipt.candidate_count,
            generated_rejected={
                reason.value: count for reason, count in receipt.rejection_counts
            },
            seeds_unused=receipt.unused_seed_count,
        )
    )


def _graph_for_generation(bundle: _HubBundle) -> HubGraph:
    if bundle.pbf_path is None:
        return bundle.graph
    if bundle.manifest is None or bundle.checkpoint is None:
        raise DryRunError("real-all bundle missing graph reload inputs")
    return build_verified_hub_graph(
        bundle.manifest, bundle.checkpoint, bundle.pbf_path, bundle.graph.hub_id
    )


def _final_status(
    selection_result: SelectionResult,
    enrichment_ran: bool,
    enrichment_status: RunStatus | None,
) -> DryRunStatus:
    """Combine the (independent) selection and enrichment stage outcomes.

    Enrichment runs as a diagnostic preview over every quality-accepted
    candidate regardless of whether ``selection_result`` reached a complete
    120-250 route activation-eligible batch (a bounded dry-run fixture will
    almost always be far smaller than that quota, which is expected per the
    plan's own Saskatchewan-sparsity guidance). So an enrichment defect is
    checked first and reported as the headline status even when the batch is
    also quota-insufficient - both are recorded independently in
    ``manifest.json`` ("selection" and "enrichment" sections) either way,
    nothing is hidden by whichever status wins here.
    """
    if enrichment_ran and enrichment_status is not RunStatus.READY:
        return DryRunStatus.NO_GO_INCOMPLETE_ENRICHMENT
    if selection_result.status is SelectionStatus.NO_GO_INSUFFICIENT_QUALITY:
        return DryRunStatus.NO_GO_INSUFFICIENT_QUALITY
    if selection_result.status is SelectionStatus.PILOT_READY_EXPANSION_DEFERRED:
        return DryRunStatus.PILOT_READY_EXPANSION_DEFERRED
    return DryRunStatus.READY


def _load_hubs(config: DryRunConfig) -> _HubLoadResult:
    if config.mode is DryRunMode.FIXTURE:
        if config.fixture_profile is FixtureProfile.EMPTY:
            bundles = build_empty_fixture_hubs()
        else:
            bundles = build_default_fixture_hubs()
        return _HubLoadResult(
            bundles=tuple(_HubBundle(item.graph, item.seeds) for item in bundles),
            failures=(),
            metrics=(),
        )
    if config.mode is DryRunMode.REAL_ALL:
        return _load_real_all_hubs(config)
    if (
        config.manifest_path is None
        or config.checkpoint_path is None
        or config.pbf_path is None
        or config.hub_id is None
    ):
        raise DryRunError(
            "real-hub mode requires --manifest, --checkpoint, --pbf, and --hub-id"
        )
    graph = load_real_hub_graph(
        config.manifest_path, config.checkpoint_path, config.pbf_path, config.hub_id
    )
    return _HubLoadResult(
        bundles=(_bundle_for_graph(graph, config.seed_source),),
        failures=(),
        metrics=(),
    )


def _bundle_for_graph(graph: HubGraph, seed_source: AuditSeedSource) -> _HubBundle:
    """Derive one hub's seeds through the configured seed source.

    ``REAL`` runs the Todo 6 production extraction
    (``western_seeds.extract_native_seed_batches``) directly on the
    checksum-pinned hub graph - a pure function of the graph, no network,
    credentials, wall clock, or randomness. ``SIMPLIFIED`` keeps the
    original 3-window pipeline-integrity seam unchanged.
    """
    if seed_source is AuditSeedSource.REAL:
        try:
            batches = extract_native_seed_batches(graph)
        except NativeSeedError as error:
            raise DryRunError(f"native seed extraction rejected: {error}") from error
        return _HubBundle(graph=graph, seeds=(), native_batches=batches)
    return _HubBundle(graph=graph, seeds=derive_seeds_from_graph(graph))


def _load_real_all_hubs(config: DryRunConfig) -> _HubLoadResult:
    """Load every requested hub, converting per-hub problems into explicit
    ``HubFailure`` records instead of aborting the combined pool.

    Hub order is the sorted hub ID list, so the pool (and every downstream
    artifact byte) is independent of filesystem enumeration order.
    """
    if (
        config.manifest_path is None
        or config.checkpoint_path is None
        or config.pbf_dir is None
    ):
        raise DryRunError(
            "real-all mode requires --manifest, --checkpoint, and --pbf-dir"
        )
    manifest, checkpoint = load_acquisition_inputs(
        config.manifest_path, config.checkpoint_path
    )
    completed_ids = frozenset(hub.hub_id for hub in checkpoint.completed_hubs)
    hub_ids = (
        tuple(sorted(set(config.hub_ids)))
        if config.hub_ids
        else tuple(sorted(completed_ids))
    )
    if not hub_ids:
        raise DryRunError("real-all mode found no completed hubs to process")
    budget = config.resource_budget
    bundles: list[_HubBundle] = []
    failures: list[HubFailure] = []
    metrics: list[HubMetric] = []
    for hub_id in hub_ids:
        hub_started = time.perf_counter()
        rss_before = _peak_rss_bytes()
        if hub_id not in completed_ids:
            failures.append(
                HubFailure(
                    hub_id=hub_id,
                    stage="acquisition_graph",
                    reason="hub_not_completed",
                    detail="hub absent from acquisition checkpoint",
                )
            )
            continue
        pbf_path = config.pbf_dir / f"{hub_id}.osm.pbf"
        if not pbf_path.is_file():
            failures.append(
                HubFailure(
                    hub_id=hub_id,
                    stage="acquisition_graph",
                    reason="hub_pbf_missing",
                    detail=str(pbf_path),
                )
            )
            continue
        try:
            graph = build_verified_hub_graph(manifest, checkpoint, pbf_path, hub_id)
            bundle = _bundle_for_graph(graph, config.seed_source)
        except DryRunError as error:
            metrics.append(
                HubMetric(
                    hub_id=hub_id,
                    elapsed_seconds=time.perf_counter() - hub_started,
                    peak_rss_bytes_after=_peak_rss_bytes(),
                )
            )
            failures.append(
                HubFailure(
                    hub_id=hub_id,
                    stage="acquisition_graph",
                    reason="checksum_or_graph_rejected",
                    detail=str(error),
                )
            )
            continue
        except MemoryError:
            metrics.append(
                HubMetric(
                    hub_id=hub_id,
                    elapsed_seconds=time.perf_counter() - hub_started,
                    peak_rss_bytes_after=_peak_rss_bytes(),
                )
            )
            failures.append(
                HubFailure(
                    hub_id=hub_id,
                    stage="acquisition_graph",
                    reason="hub_rss_budget_exceeded",
                    detail="allocation exhausted process memory",
                )
            )
            continue
        hub_elapsed = time.perf_counter() - hub_started
        rss_after = _peak_rss_bytes()
        metrics.append(
            HubMetric(
                hub_id=hub_id,
                elapsed_seconds=hub_elapsed,
                peak_rss_bytes_after=rss_after,
            )
        )
        if hub_elapsed > budget.max_hub_elapsed_seconds:
            # Observed elapsed/RSS values stay in resource_metrics.json (a
            # deliberately non-deterministic artifact); the deterministic
            # funnel/manifest failure entry names only the fixed budget so a
            # byte-identical rerun stays byte-identical.
            failures.append(
                HubFailure(
                    hub_id=hub_id,
                    stage="acquisition_graph",
                    reason="hub_elapsed_budget_exceeded",
                    detail=(
                        "hub exceeded max_hub_elapsed_seconds="
                        f"{budget.max_hub_elapsed_seconds}"
                    ),
                )
            )
            continue
        # Charge each hub only its own RSS growth: ru_maxrss is a
        # process-lifetime high-water mark, so comparing the absolute value
        # against the per-hub cap would blame whichever small hub happens to
        # be loading when the cumulative peak crosses the line.
        if rss_after - rss_before > budget.max_hub_peak_rss_bytes:
            failures.append(
                HubFailure(
                    hub_id=hub_id,
                    stage="acquisition_graph",
                    reason="hub_rss_budget_exceeded",
                    detail=(
                        "hub exceeded max_hub_peak_rss_bytes="
                        f"{budget.max_hub_peak_rss_bytes}"
                    ),
                )
            )
            continue
        if config.seed_source is AuditSeedSource.REAL:
            bundle = _HubBundle(
                graph=HubGraph(
                    hub_id=graph.hub_id,
                    province_code=graph.province_code,
                    source_pbf_checksum=graph.source_pbf_checksum,
                    hub_pbf_checksum=graph.hub_pbf_checksum,
                    nodes=(),
                    edges=(),
                ),
                seeds=(),
                native_batches=bundle.native_batches,
                pbf_path=pbf_path,
                manifest=manifest,
                checkpoint=checkpoint,
            )
        bundles.append(bundle)
        del graph
        _ = gc.collect()
    if not bundles and failures:
        details = "; ".join(f"{item.hub_id}[{item.reason}]" for item in failures)
        raise DryRunError(f"real-all mode loaded zero hubs: {details}")
    return _HubLoadResult(
        bundles=tuple(bundles), failures=tuple(failures), metrics=tuple(metrics)
    )


def _write_early_failure(
    config: DryRunConfig,
    status: DryRunStatus,
    detail: str,
    timings: list[StageTiming],
    started: float,
) -> DryRunOutcome:
    config.output_dir.mkdir(parents=True, exist_ok=True)
    manifest_core: dict[str, object] = {
        "schema_version": 1,
        "generator_version": GENERATOR_VERSION,
        "mode": config.mode.value,
        "snapshot": config.snapshot,
        "seed": config.seed,
        "seed_source": config.seed_source.value,
        "status": status.value,
        "exit_code": EXIT_CODES[status],
        "failure_detail": detail,
        "hubs": [],
        "funnel": None,
        "selection": None,
        "enrichment": None,
        "accepted_route_ids": [],
        "rejected": [],
        "overlap_matrix": [],
        "sample_route_ids": [],
    }
    manifest_bytes = canonical_json_bytes(manifest_core)
    write_bytes_atomic(config.output_dir / "manifest.json", manifest_bytes)
    write_bytes_atomic(
        config.output_dir / "resource_metrics.json",
        canonical_json_bytes(
            {
                "stage_timings": [
                    {"stage": item.stage, "elapsed_seconds": item.elapsed_seconds}
                    for item in timings
                ],
                "peak_rss_bytes": _peak_rss_bytes(),
                "elapsed_seconds_total": time.perf_counter() - started,
                "resource_budget": {
                    "max_peak_rss_bytes": config.resource_budget.max_peak_rss_bytes,
                    "max_elapsed_seconds": config.resource_budget.max_elapsed_seconds,
                },
            }
        ),
    )
    return DryRunOutcome(
        status=status, exit_code=EXIT_CODES[status], output_dir=config.output_dir
    )


def _write_artifacts(
    *,
    config: DryRunConfig,
    hubs: tuple[_HubBundle, ...],
    hub_failures: tuple[HubFailure, ...],
    hub_metrics: tuple[HubMetric, ...],
    funnel_entries: list[_HubFunnelEntry],
    rejected: tuple[RejectedRecord, ...],
    quality_candidates: dict[str, QualityCandidate],
    accepted_candidates: tuple[QualityCandidate, ...],
    selection_result: SelectionResult,
    enrichment_ran: bool,
    enrichment_status: RunStatus | None,
    enrichment_summary: dict[str, int] | None,
    enrichment_routes: list[dict[str, object]],
    sample_ids: tuple[str, ...],
    status: DryRunStatus,
    timings: list[StageTiming],
    peak_rss: int,
    elapsed_total: float,
) -> None:
    del hubs
    output_dir = config.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    accepted_bytes = accepted_geojson_bytes(accepted_candidates)
    write_bytes_atomic(output_dir / "accepted_routes.geojson", accepted_bytes)

    rejected_json = rejected_json_bytes(rejected)
    write_bytes_atomic(output_dir / "rejected.json", rejected_json)
    rejected_csv = rejected_csv_bytes(rejected)
    write_bytes_atomic(output_dir / "rejected.csv", rejected_csv)

    overlap_records: list[dict[str, str]] = [
        {
            "route_id": item.route_id,
            "overlaps_with": item.overlap_route_id or "",
        }
        for item in selection_result.rejections
        if item.reason is QualityRejection.OVERLAP
    ]
    overlap_bytes = canonical_json_bytes(
        sorted(overlap_records, key=lambda item: item["route_id"])
    )
    write_bytes_atomic(output_dir / "overlap_matrix.json", overlap_bytes)

    funnel_payload = {
        "by_hub": [
            {
                "hub_id": entry.hub_id,
                "province_code": entry.province_code,
                "source_pbf_checksum": entry.source_pbf_checksum,
                "hub_pbf_checksum": entry.hub_pbf_checksum,
                "seeds_in": entry.seeds_in,
                "seeds_unused": entry.seeds_unused,
                "generated_accepted": entry.generated_accepted,
                "generated_rejected": entry.generated_rejected,
            }
            for entry in sorted(funnel_entries, key=lambda item: item.hub_id)
        ],
        "hub_failures": [
            {
                "hub_id": item.hub_id,
                "stage": item.stage,
                "reason": item.reason,
                "detail": item.detail,
            }
            for item in sorted(hub_failures, key=lambda item: item.hub_id)
        ],
        "totals": {
            "hubs_processed": len(funnel_entries),
            "hubs_failed": len(hub_failures),
            "seeds_in": sum(entry.seeds_in for entry in funnel_entries),
            "seeds_unused": sum(entry.seeds_unused for entry in funnel_entries),
            "generated_accepted": sum(
                entry.generated_accepted for entry in funnel_entries
            ),
            "generated_rejected": sum(
                sum(entry.generated_rejected.values()) for entry in funnel_entries
            ),
        },
        "quality": {
            "input_count": selection_result.summary.input_count,
            "quality_eligible_count": selection_result.summary.quality_eligible_count,
            "deduped_count": selection_result.summary.deduped_count,
            "selected_count": selection_result.summary.selected_count,
            "unselected_count": selection_result.summary.unselected_count,
            "rejection_counts": {
                reason.value: count
                for reason, count in selection_result.summary.rejection_counts
            },
        },
    }
    funnel_bytes = canonical_json_bytes(funnel_payload)
    write_bytes_atomic(output_dir / "funnel.json", funnel_bytes)

    samples_dir = output_dir / "samples"
    for route_id in sample_ids:
        candidate = quality_candidates[route_id]
        safe_name = route_id.replace(":", "_")
        write_bytes_atomic(
            samples_dir / f"{safe_name}.geojson", sample_route_geojson_bytes(candidate)
        )

    accepted_route_ids = sorted(
        candidate.route.route_id for candidate in accepted_candidates
    )

    enrichment_section: dict[str, object] | None = None
    if enrichment_ran:
        enrichment_section = {
            "ran": True,
            "status": enrichment_status.value
            if enrichment_status is not None
            else None,
            "summary": enrichment_summary,
            "routes": enrichment_routes,
        }

    artifact_checksums: dict[str, str] = {
        "accepted_routes.geojson": sha256_hex(accepted_bytes),
        "rejected.json": sha256_hex(rejected_json),
        "rejected.csv": sha256_hex(rejected_csv),
        "funnel.json": sha256_hex(funnel_bytes),
        "overlap_matrix.json": sha256_hex(overlap_bytes),
    }
    upload_documents = build_upload_documents(
        accepted_candidates,
        selection_result,
        generator_version=GENERATOR_VERSION,
        source_snapshot=config.snapshot,
    )
    for document in upload_documents:
        upload_bytes = document.model_dump_json(
            by_alias=False, exclude_none=True, indent=None
        ).encode("utf-8")
        upload_name = f"upload-{document.batch_id}.json"
        write_bytes_atomic(output_dir / upload_name, upload_bytes)
        artifact_checksums[upload_name] = sha256_hex(upload_bytes)
    bundle_lines = "\n".join(
        f"{name}:{digest}" for name, digest in sorted(artifact_checksums.items())
    )
    manifest_core: dict[str, object] = {
        "schema_version": 1,
        "generator_version": GENERATOR_VERSION,
        "mode": config.mode.value,
        "snapshot": config.snapshot,
        "seed": config.seed,
        "seed_source": config.seed_source.value,
        "status": status.value,
        "exit_code": EXIT_CODES[status],
        "hubs": [
            {
                "hub_id": entry.hub_id,
                "province_code": entry.province_code,
                "source_pbf_checksum": entry.source_pbf_checksum,
                "hub_pbf_checksum": entry.hub_pbf_checksum,
            }
            for entry in sorted(funnel_entries, key=lambda item: item.hub_id)
        ],
        "hub_failures": [
            {
                "hub_id": item.hub_id,
                "stage": item.stage,
                "reason": item.reason,
                "detail": item.detail,
            }
            for item in sorted(hub_failures, key=lambda item: item.hub_id)
        ],
        "selection": {
            "status": selection_result.status.value,
            "manifests": [
                {
                    "batch_id": manifest.batch_id,
                    "route_ids": list(manifest.route_ids),
                    "province_counts": [
                        [province.value, count]
                        for province, count in manifest.province_counts
                    ],
                    "hub_counts": [list(item) for item in manifest.hub_counts],
                    "hub_ids": list(manifest.hub_ids),
                    "geohash4_cells": list(manifest.geohash4_cells),
                }
                for manifest in selection_result.manifests
            ],
            "shadow_route_ids": list(selection_result.shadow_route_ids),
            "unselected_route_ids": list(selection_result.unselected_route_ids),
        },
        "enrichment": enrichment_section,
        "accepted_route_ids": accepted_route_ids,
        "sample_route_ids": list(sample_ids),
        "artifact_checksums": artifact_checksums,
        "artifact_bundle_checksum": sha256_hex(bundle_lines.encode("utf-8")),
    }
    manifest_bytes = canonical_json_bytes(manifest_core)
    write_bytes_atomic(output_dir / "manifest.json", manifest_bytes)

    write_bytes_atomic(
        output_dir / "resource_metrics.json",
        canonical_json_bytes(
            {
                "stage_timings": [
                    {"stage": item.stage, "elapsed_seconds": item.elapsed_seconds}
                    for item in timings
                ],
                "per_hub": [
                    {
                        "hub_id": item.hub_id,
                        "stage": item.stage,
                        "elapsed_seconds": item.elapsed_seconds,
                        "peak_rss_bytes_after": item.peak_rss_bytes_after,
                    }
                    for item in sorted(
                        hub_metrics, key=lambda item: (item.hub_id, item.stage)
                    )
                ],
                "peak_rss_bytes": peak_rss,
                "elapsed_seconds_total": elapsed_total,
                "resource_budget": {
                    "max_peak_rss_bytes": config.resource_budget.max_peak_rss_bytes,
                    "max_elapsed_seconds": config.resource_budget.max_elapsed_seconds,
                    "max_hub_peak_rss_bytes": (
                        config.resource_budget.max_hub_peak_rss_bytes
                    ),
                    "max_hub_elapsed_seconds": (
                        config.resource_budget.max_hub_elapsed_seconds
                    ),
                },
            }
        ),
    )
