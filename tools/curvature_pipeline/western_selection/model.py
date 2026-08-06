from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from ..western_routes.model import GeneratedRoute


class ProvinceCode(StrEnum):
    AB = "AB"
    BC = "BC"
    MB = "MB"
    SK = "SK"


class PolicyEvidence(StrEnum):
    ALLOWED = "allowed"
    FORBIDDEN = "forbidden"
    MISSING = "missing"


class QualityRejection(StrEnum):
    INVALID_PROVINCE = "invalid_province"
    DUPLICATE_ROUTE_ID = "duplicate_route_id"
    INVALID_TOPOLOGY = "invalid_topology"
    INVALID_QUALITY_METRICS = "invalid_quality_metrics"
    INVALID_GEOHASH4 = "invalid_geohash4"
    REPEATED_EDGE = "repeated_directed_edge"
    DISTANCE = "distance_out_of_bounds"
    CURVED_DISTANCE = "curved_distance_below_2km"
    CURVED_RATIO = "curved_ratio_below_12pct"
    STRAIGHT_RUN = "straight_run_above_8km"
    ROAD_EXPOSURE = "residential_service_exposure_at_least_15pct"
    ACCESS_POLICY = "forbidden_or_missing_access_policy"
    SURFACE_POLICY = "forbidden_or_missing_surface_policy"
    OVERLAP = "overlap_at_least_75pct"


class SelectionStatus(StrEnum):
    READY = "READY"
    PILOT_READY_EXPANSION_DEFERRED = "PILOT_READY_EXPANSION_DEFERRED"
    NO_GO_INSUFFICIENT_QUALITY = "NO_GO_INSUFFICIENT_QUALITY"


@dataclass(frozen=True, slots=True)
class QualityCandidate:
    route: GeneratedRoute
    edge_lengths_m: tuple[float, ...]
    curved_distance_m: float
    max_straight_run_m: float
    residential_service_exposure_ratio: float
    access_evidence: PolicyEvidence
    surface_evidence: PolicyEvidence
    geohash4: str


@dataclass(frozen=True, slots=True)
class OverlapReference:
    route_id: str
    edge_ids: tuple[str, ...]
    edge_lengths_m: tuple[float, ...]


@dataclass(frozen=True, slots=True)
class ScoredCandidate:
    candidate: QualityCandidate
    quality_score: float

    @property
    def route(self) -> GeneratedRoute:
        return self.candidate.route


@dataclass(frozen=True, slots=True)
class RouteRejectionRecord:
    route_id: str
    reason: QualityRejection
    overlap_route_id: str | None = None


@dataclass(frozen=True, slots=True)
class DedupeOutcome:
    accepted: tuple[QualityCandidate, ...]
    scored: tuple[ScoredCandidate, ...]
    rejections: tuple[RouteRejectionRecord, ...]


@dataclass(frozen=True, slots=True)
class BatchManifest:
    batch_id: str
    route_ids: tuple[str, ...]
    province_counts: tuple[tuple[ProvinceCode, int], ...]
    hub_counts: tuple[tuple[str, int], ...]
    hub_ids: tuple[str, ...]
    geohash4_cells: tuple[str, ...]
    activation_eligible: bool


@dataclass(frozen=True, slots=True)
class SelectionSummary:
    input_count: int
    quality_eligible_count: int
    deduped_count: int
    selected_count: int
    unselected_count: int
    rejection_counts: tuple[tuple[QualityRejection, int], ...]


@dataclass(frozen=True, slots=True)
class SelectionResult:
    status: SelectionStatus
    manifests: tuple[BatchManifest, ...]
    shadow_route_ids: tuple[str, ...]
    rejections: tuple[RouteRejectionRecord, ...]
    unselected_route_ids: tuple[str, ...]
    summary: SelectionSummary
