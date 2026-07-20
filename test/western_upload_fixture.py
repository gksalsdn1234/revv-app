from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Final, Literal

from tools.curvature_pipeline.western_upload.model import (
    Node,
    ProgramBatch,
    Provenance,
    RoutePayload,
    SourceManifest,
    UploadDocument,
)

PROJECT_REF = "zvwgnduuumksuqazpvsf"
type Cohort = Literal["pilot", "expansion"]
type Province = Literal["AB", "BC", "MB", "SK"]


@dataclass(frozen=True, slots=True)
class _CohortFixture:
    batch_id: str
    province_counts: dict[Province, int]
    hub_splits: dict[Province, int]


_COHORT_FIXTURES: Final[dict[Cohort, _CohortFixture]] = {
    "pilot": _CohortFixture(
        batch_id="west-pilot-v1-fixture",
        province_counts={"BC": 8, "AB": 8, "SK": 4, "MB": 4},
        hub_splits={"BC": 2, "AB": 2, "SK": 1, "MB": 1},
    ),
    "expansion": _CohortFixture(
        batch_id="west-expand-v1-fixture",
        province_counts={"BC": 32, "AB": 32, "SK": 16, "MB": 16},
        hub_splits={"BC": 3, "AB": 3, "SK": 3, "MB": 3},
    ),
}


def write_program_manifests(root: Path) -> tuple[Path, str, Path, str]:
    pilot_ids = tuple(f"osmgen:v1:pilot-{index:03d}" for index in range(24))
    expansion_ids = tuple(f"osmgen:v1:expand-{index:03d}" for index in range(96))
    program = (
        ProgramBatch(
            batch_id="west-pilot-v1-fixture",
            cohort_kind="pilot",
            route_ids=pilot_ids,
        ),
        ProgramBatch(
            batch_id="west-expand-v1-fixture",
            cohort_kind="expansion",
            route_ids=expansion_ids,
        ),
    )
    pilot = _manifest("pilot", pilot_ids, program)
    expansion = _manifest("expansion", expansion_ids, program)
    pilot_path = root / "pilot.json"
    expansion_path = root / "expansion.json"
    _ = pilot_path.write_bytes(_json_bytes(pilot))
    _ = expansion_path.write_bytes(_json_bytes(expansion))
    return (
        pilot_path,
        hashlib.sha256(pilot_path.read_bytes()).hexdigest(),
        expansion_path,
        hashlib.sha256(expansion_path.read_bytes()).hexdigest(),
    )


def _manifest(
    kind: Cohort,
    route_ids: tuple[str, ...],
    program: tuple[ProgramBatch, ProgramBatch],
) -> UploadDocument:
    fixture = _COHORT_FIXTURES[kind]
    batch_id = fixture.batch_id
    province_counts = fixture.province_counts
    hub_splits = fixture.hub_splits
    hubs_by_province: dict[Province, tuple[str, ...]] = {
        province: tuple(
            f"{kind}-{province.lower()}-hub-{index:02d}" for index in range(count)
        )
        for province, count in hub_splits.items()
    }
    hubs = tuple(
        hub for province_hubs in hubs_by_province.values() for hub in province_hubs
    )
    cells = tuple(f"{index:04x}"[-4:] for index in range(len(route_ids)))
    provinces: tuple[Province, ...] = (
        _repeat_province("BC", province_counts["BC"])
        + _repeat_province("AB", province_counts["AB"])
        + _repeat_province("SK", province_counts["SK"])
        + _repeat_province("MB", province_counts["MB"])
    )
    province_positions: dict[Province, int] = dict.fromkeys(province_counts, 0)
    routes: list[RoutePayload] = []
    for index, route_id in enumerate(route_ids):
        province = provinces[index]
        province_hubs = hubs_by_province[province]
        hub = province_hubs[province_positions[province] % len(province_hubs)]
        province_positions[province] += 1
        routes.append(_route(route_id, batch_id, province, hub, cells[index]))
    hub_counts = {
        hub: sum(route.source_hub_id == hub for route in routes) for hub in hubs
    }
    sources = tuple(
        SourceManifest(
            hub_id=hub,
            province_code=next(
                route.province_code for route in routes if route.source_hub_id == hub
            ),
            source_pbf_sha256="a" * 64,
            source_graph_sha256=hashlib.sha256(hub.encode()).hexdigest(),
            source_snapshot="fixture-2026-07-16",
        )
        for hub in hubs
    )
    return UploadDocument(
        schema_version="revv-western-upload-v1",
        project_ref=PROJECT_REF,
        batch_id=batch_id,
        cohort_kind=kind,
        generator_version="western-v1",
        activation_eligible=True,
        route_ids=route_ids,
        province_counts=province_counts,
        hub_counts=hub_counts,
        geohash4_cells=cells,
        program_batches=program,
        sources=sources,
        routes=tuple(routes),
    )


def _route(
    route_id: str,
    batch_id: str,
    province: Province,
    hub: str,
    cell: str,
) -> RoutePayload:
    graph = hashlib.sha256(hub.encode()).hexdigest()
    return RoutePayload(
        id=route_id,
        name=route_id,
        center_lat=51.0,
        center_lng=-114.0,
        nodes=(Node(lat=51.0, lng=-114.0), Node(lat=51.1, lng=-114.1)),
        distance_km=20.0,
        winding_score=70.0,
        geohash4=cell,
        region=province.lower(),
        province_code=province,
        source="osm_generated",
        publication_kind="osm_generated",
        generation_batch_id=batch_id,
        source_hub_id=hub,
        source_pbf_sha256="a" * 64,
        source_graph_sha256=graph,
        generation_provenance=Provenance(
            province_codes=(province,),
            source_hub_id=hub,
            directed_edge_ids=(f"edge:{route_id}",),
            source_seed_ids=(f"seed:{route_id}",),
            guidance_receipt_sha256="b" * 64,
        ),
    )


def _repeat_province(province: Province, count: int) -> tuple[Province, ...]:
    return (province,) * count


def _json_bytes(value: UploadDocument) -> bytes:
    return json.dumps(
        value.model_dump(mode="json"), sort_keys=True, separators=(",", ":")
    ).encode()
