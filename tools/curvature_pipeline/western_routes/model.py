from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from ..western_graph.model import Coordinate
from ..western_sources.manifest import ProvinceCode


class SeedSource(StrEnum):
    OSM = "osm"
    ROAD_CURVATURE = "roadcurvature"


class RouteRejection(StrEnum):
    UNLICENSED_SEED = "unlicensed_seed"
    SEED_DISTANCE = "seed_distance_out_of_bounds"
    SNAP_MISS = "snap_miss"
    SNAP_AMBIGUOUS = "snap_ambiguous"
    DISCONNECTED = "disconnected"
    ILLEGAL_DIRECTION = "illegal_direction"
    REF_MISMATCH = "ref_mismatch"
    SEEDS_TOO_FAR = "seeds_too_far"
    REPEATED_EDGE = "repeated_directed_edge"
    LOOP_RETURN_OVERLAP = "loop_return_overlap"
    TOO_SHORT = "route_too_short"
    TOO_LONG = "route_too_long"
    NODE_LIMIT = "simplified_node_limit"
    PAYLOAD_LIMIT = "payload_limit"
    HAUSDORFF_LIMIT = "hausdorff_limit"
    LENGTH_ERROR = "length_error"
    TOPOLOGY_REPLAY = "topology_replay_failure"


@dataclass(frozen=True, slots=True)
class RouteGenerationError(RuntimeError):
    reason: RouteRejection
    detail: str

    def __str__(self) -> str:
        return f"western route rejected [{self.reason}]: {self.detail}"


@dataclass(frozen=True, slots=True)
class SeedFragment:
    seed_id: str
    points: tuple[Coordinate, ...]
    road_refs: tuple[str, ...]
    source: SeedSource
    source_license: str


@dataclass(frozen=True, slots=True)
class GenerationLimits:
    snap_distance_m: float = 100.0
    snap_ambiguity_m: float = 1.0
    min_seed_distance_m: float = 300.0
    max_seed_distance_m: float = 4_000.0
    max_seed_connector_m: float = 12_000.0
    min_route_distance_m: float = 15_000.0
    max_route_distance_m: float = 80_000.0
    loop_close_distance_m: float = 3_000.0
    max_loop_return_ratio: float = 0.4
    initial_simplification_m: float = 12.0
    max_simplification_m: float = 25.0
    max_hausdorff_m: float = 25.0
    max_length_error_ratio: float = 0.01
    max_geometry_nodes: int = 300
    max_payload_bytes: int = 512 * 1024


@dataclass(frozen=True, slots=True)
class ReplaySpan:
    first_edge_index: int
    last_edge_index: int


@dataclass(frozen=True, slots=True)
class GeneratedRoute:
    route_id: str
    generator_version: str
    hub_id: str
    province_code: ProvinceCode
    source_pbf_checksum: str
    hub_pbf_checksum: str
    seed_ids: tuple[str, ...]
    edge_ids: tuple[str, ...]
    geometry: tuple[Coordinate, ...]
    replay_spans: tuple[ReplaySpan, ...]
    distance_m: float
    hausdorff_error_m: float
    length_error_ratio: float
    is_loop: bool


class GuidanceRejection(StrEnum):
    REQUEST_BUDGET = "request_budget"
    COST_BUDGET = "cost_budget"
    HTTP_FAILURE = "http_failure"
    MALFORMED_MATCH = "malformed_match"
    ENDPOINT_MISS = "endpoint_miss"
    DISTANCE_MISS = "distance_miss"
    COVERAGE_MISS = "coverage_miss"


@dataclass(frozen=True, slots=True)
class GuidanceBatchError(RuntimeError):
    reason: GuidanceRejection
    detail: str

    def __str__(self) -> str:
        return f"guidance batch rejected [{self.reason}]: {self.detail}"


@dataclass(frozen=True, slots=True)
class GuidanceBudget:
    max_requests: int = 300
    max_estimated_charge_usd: float = 5.0
    estimated_charge_per_request_usd: float = 0.005


@dataclass(frozen=True, slots=True)
class GuidanceMatch:
    distance_m: float
    geometry: tuple[Coordinate, ...]


@dataclass(frozen=True, slots=True)
class GuidanceHttpResponse:
    status_code: int
    match: GuidanceMatch | None = None


@dataclass(frozen=True, slots=True)
class GuidanceReceipt:
    route_id: str
    shadow_eligible: bool
    reason: GuidanceRejection | None
    endpoint_error_m: float
    distance_error_ratio: float
    coverage_ratio: float
    request_count: int


@dataclass(frozen=True, slots=True)
class GuidanceBatchResult:
    receipts: tuple[GuidanceReceipt, ...]
    request_count: int
    estimated_charge_usd: float
