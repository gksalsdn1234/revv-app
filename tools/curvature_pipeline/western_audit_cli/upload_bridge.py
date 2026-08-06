from __future__ import annotations

import hashlib
from typing import Literal

from ..western_routes.codec import route_bytes
from ..western_selection.model import BatchManifest, QualityCandidate, SelectionResult
from ..western_upload.contract import EXPECTED_PROJECT_REF
from ..western_upload.model import (
    Node,
    ProgramBatch,
    Provenance,
    RoutePayload,
    SourceManifest,
    UploadDocument,
)


def build_upload_documents(
    candidates: tuple[QualityCandidate, ...],
    selection: SelectionResult,
    *,
    generator_version: str,
    source_snapshot: str,
) -> tuple[UploadDocument, ...]:
    by_id = {candidate.route.route_id: candidate for candidate in candidates}
    program = tuple(
        ProgramBatch(
            batch_id=batch.batch_id,
            cohort_kind=_cohort_kind(batch),
            route_ids=batch.route_ids,
        )
        for batch in selection.manifests
    )
    expansion_deferred = (
        True if selection.status.value == "PILOT_READY_EXPANSION_DEFERRED" else None
    )
    return tuple(
        _document_for_batch(
            batch,
            by_id,
            program,
            expansion_deferred,
            generator_version,
            source_snapshot,
        )
        for batch in selection.manifests
    )


def _document_for_batch(
    batch: BatchManifest,
    by_id: dict[str, QualityCandidate],
    program: tuple[ProgramBatch, ...],
    expansion_deferred: bool | None,
    generator_version: str,
    source_snapshot: str,
) -> UploadDocument:
    selected = tuple(by_id[route_id] for route_id in batch.route_ids)
    routes = tuple(_route_payload(candidate, batch.batch_id) for candidate in selected)
    sources = tuple(
        SourceManifest(
            hub_id=candidate.route.hub_id,
            province_code=candidate.route.province_code,
            source_pbf_sha256=candidate.route.hub_pbf_checksum,
            source_graph_sha256=candidate.route.hub_pbf_checksum,
            source_snapshot=source_snapshot,
        )
        for candidate in sorted(
            {candidate.route.hub_id: candidate for candidate in selected}.values(),
            key=lambda candidate: candidate.route.hub_id,
        )
    )
    return UploadDocument(
        schema_version="revv-western-upload-v1",
        project_ref=EXPECTED_PROJECT_REF,
        batch_id=batch.batch_id,
        cohort_kind=_cohort_kind(batch),
        generator_version=generator_version,
        activation_eligible=True,
        expansion_deferred=expansion_deferred,
        route_ids=batch.route_ids,
        province_counts=dict(batch.province_counts),
        hub_counts=dict(batch.hub_counts),
        geohash4_cells=batch.geohash4_cells,
        program_batches=program,
        sources=sources,
        routes=routes,
    )


def _route_payload(candidate: QualityCandidate, batch_id: str) -> RoutePayload:
    route = candidate.route
    ratio = candidate.curved_distance_m / route.distance_m
    nodes = tuple(Node(lat=point.lat, lng=point.lng) for point in route.geometry)
    return RoutePayload(
        id=route.route_id,
        name=f"Western Curves · {route.hub_id}",
        center_lat=sum(point.lat for point in route.geometry) / len(route.geometry),
        center_lng=sum(point.lng for point in route.geometry) / len(route.geometry),
        nodes=nodes,
        distance_km=route.distance_m / 1_000,
        curvature_score=ratio,
        winding_score=ratio * 100,
        star_rating=max(1, min(5, round(1 + ratio * 4))),
        tight_curve_km=candidate.curved_distance_m / 1_000,
        max_continuous_km=route.distance_m / 1_000,
        is_loop=route.is_loop,
        geohash4=candidate.geohash4,
        region=route.province_code.lower(),
        province_code=route.province_code,
        source="osm_generated",
        publication_kind="osm_generated",
        generation_batch_id=batch_id,
        source_hub_id=route.hub_id,
        source_pbf_sha256=route.hub_pbf_checksum,
        source_graph_sha256=route.hub_pbf_checksum,
        generation_provenance=Provenance(
            province_codes=(route.province_code,),
            source_hub_id=route.hub_id,
            directed_edge_ids=route.edge_ids,
            source_seed_ids=route.seed_ids,
            guidance_receipt_sha256=hashlib.sha256(route_bytes(route)).hexdigest(),
        ),
    )


def _cohort_kind(batch: BatchManifest) -> Literal["pilot", "expansion"]:
    return "pilot" if batch.batch_id.startswith("west-pilot-v1-") else "expansion"
