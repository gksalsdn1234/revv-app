from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Final, Literal, override

from ..western_graph.model import Coordinate, GraphEdge
from ..western_routes.model import GeneratedRoute, RouteRejection
from ..western_sources.manifest import ProvinceCode


class NativeSeedRejection(StrEnum):
    NO_CURVATURE = "no_curvature"
    ILLEGAL_EDGE = "illegal_edge"
    PROVENANCE = "provenance_mismatch"
    TOPOLOGY = "topology_mismatch"
    RESOURCE_LIMIT = "resource_limit"


@dataclass(frozen=True, slots=True)
class NativeSeedError(RuntimeError):
    reason: NativeSeedRejection
    detail: str

    @override
    def __str__(self) -> str:
        return f"native OSM seed rejected [{self.reason}]: {self.detail}"


@dataclass(frozen=True, slots=True)
class NativeSeedLimits:
    min_distance_m: float = 300.0
    target_distance_m: float = 3_500.0
    max_distance_m: float = 4_000.0
    min_total_turn_degrees: float = 20.0
    min_turn_degrees_per_km: float = 5.0
    max_candidate_edges: int = 2_000_000
    max_edges_per_seed: int = 512
    max_seeds: int = 256


@dataclass(frozen=True, slots=True)
class NativeSeed:
    seed_id: str
    hub_id: str
    province_code: ProvinceCode
    source_pbf_checksum: str
    hub_pbf_checksum: str
    source_license: Literal["ODbL-1.0"]
    edge_ids: tuple[str, ...]
    osm_way_ids: tuple[int, ...]
    points: tuple[Coordinate, ...]
    road_refs: tuple[str, ...]
    distance_m: float
    total_turn_degrees: float


@dataclass(frozen=True, slots=True)
class NativeSeedBatch:
    schema_version: Literal[1]
    generator_version: Literal["western-osm-seed-v1"]
    hub_id: str
    province_code: ProvinceCode
    source_pbf_checksum: str
    hub_pbf_checksum: str
    seeds: tuple[NativeSeed, ...]


@dataclass(frozen=True, slots=True)
class ResolvedNativeSeed:
    seed: NativeSeed
    edges: tuple[GraphEdge, ...]


class NativeRouteBatchStatus(StrEnum):
    READY = "ready"
    NO_GO = "no_go"


@dataclass(frozen=True, slots=True)
class NativeRouteBatchLimits:
    # 25 is the plan's Todo 7 "max 25 routes/hub" ceiling; selection still
    # enforces its own per-hub cap downstream, so this only widens the
    # candidate pool entering the (unchanged) quality gates.
    max_candidates: int = 25
    max_start_attempts: int = 256
    max_seeds_per_candidate: int = 256
    max_connector_distance_m: float = 12_000.0


@dataclass(frozen=True, slots=True)
class NativeRouteBatchReceipt:
    hub_id: str
    status: NativeRouteBatchStatus
    input_seed_count: int
    candidate_count: int
    rejected_start_count: int
    unused_seed_count: int
    rejection_counts: tuple[tuple[RouteRejection, int], ...]
    # Diagnostic seam only: one (start seed ID, rejection reason) entry per
    # rejected start, so audit tooling can attribute each rejection without
    # changing any generation gate. Aggregates above remain authoritative.
    rejected_start_details: tuple[tuple[str, RouteRejection], ...] = ()


@dataclass(frozen=True, slots=True)
class NativeRouteBatchResult:
    routes: tuple[GeneratedRoute, ...]
    receipt: NativeRouteBatchReceipt


DEFAULT_NATIVE_SEED_LIMITS: Final = NativeSeedLimits()
DEFAULT_NATIVE_ROUTE_BATCH_LIMITS: Final = NativeRouteBatchLimits()
