from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated, ClassVar, Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field, JsonValue

type CohortKind = Literal["pilot", "expansion"]
type TargetState = Literal["active", "disabled"]
type EvidenceId = Annotated[str, Field(min_length=1, max_length=160)]


class Node(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="forbid", frozen=True)

    lat: float = Field(ge=-90.0, le=90.0)
    lng: float = Field(ge=-180.0, le=180.0)


class Provenance(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="forbid", frozen=True)

    province_codes: tuple[Literal["AB", "BC", "MB", "SK"], ...]
    source_hub_id: str
    directed_edge_ids: tuple[EvidenceId, ...] = Field(min_length=1, max_length=1200)
    source_seed_ids: tuple[EvidenceId, ...] = Field(min_length=1, max_length=128)
    guidance_receipt_sha256: str


class RoutePayload(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="forbid", frozen=True)

    id: str
    name: str = ""
    center_lat: float = Field(ge=-90.0, le=90.0)
    center_lng: float = Field(ge=-180.0, le=180.0)
    nodes: tuple[Node, ...] = Field(min_length=2, max_length=300)
    distance_km: float = Field(ge=15.0, le=80.0)
    curvature_score: float = Field(default=0.0, allow_inf_nan=False)
    winding_score: float = Field(ge=0.0, allow_inf_nan=False)
    star_rating: int = Field(default=1, ge=1, le=5)
    sharp_curve_count: int = Field(default=0, ge=0)
    tight_curve_km: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    medium_curve_km: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    max_continuous_km: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    is_loop: bool = False
    elevation_delta: float = Field(default=0.0, allow_inf_nan=False)
    geohash4: str
    region: str
    province_code: Literal["AB", "BC", "MB", "SK"]
    source: Literal["osm_generated"]
    stop_sign_count: int = Field(default=0, ge=0)
    traffic_signal_count: int = Field(default=0, ge=0)
    stop_control_density: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    flow_score: float = Field(default=0.0, allow_inf_nan=False)
    fun_score: float = Field(default=0.0, allow_inf_nan=False)
    driveability_penalty: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    road_class_bucket: str = ""
    is_named: bool = True
    is_facility_like: bool = False
    is_bridge_like: bool = False
    is_connector_like: bool = False
    is_major_road_like: bool = False
    is_private_like: bool = False
    residential_ratio: float = Field(default=0.0, ge=0.0, le=1.0, allow_inf_nan=False)
    service_ratio: float = Field(default=0.0, ge=0.0, le=1.0, allow_inf_nan=False)
    local_road_ratio: float = Field(default=0.0, ge=0.0, le=1.0, allow_inf_nan=False)
    intersection_density: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    building_density: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    housing_proximity_score: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    urban_friction_score: float = Field(default=0.0, ge=0.0, allow_inf_nan=False)
    residential_penalty: float = Field(default=1.0, ge=0.0, allow_inf_nan=False)
    residential_version: str = ""
    residential_enriched_at: str | None = None
    quality_label: str = ""
    quality_reject_reason: str | None = None
    route_character: str = ""
    primary_reason: str | None = None
    caution_note: str | None = None
    quality_version: str = ""
    quality_enriched_at: str | None = None
    elevation_profile: tuple[float, ...] = Field(default=(), max_length=300)
    road_names: tuple[str, ...] = ()
    surface_summary: str = ""
    speed_limit_summary: str = ""
    nearby_pois: tuple[JsonValue, ...] = ()
    route_context: dict[str, JsonValue] = Field(default_factory=dict)
    context_version: str = ""
    context_enriched_at: str | None = None
    publication_kind: Literal["osm_generated"]
    generation_batch_id: str
    source_hub_id: str
    source_pbf_sha256: str
    source_graph_sha256: str
    generation_provenance: Provenance


class SourceManifest(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="forbid", frozen=True)

    hub_id: str
    province_code: Literal["AB", "BC", "MB", "SK"]
    source_pbf_sha256: str
    source_graph_sha256: str
    source_snapshot: str


class ProgramBatch(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="forbid", frozen=True)

    batch_id: str
    cohort_kind: CohortKind
    route_ids: tuple[str, ...]


class UploadDocument(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="forbid", frozen=True)

    schema_version: Literal["revv-western-upload-v1"]
    project_ref: str
    batch_id: str
    cohort_kind: CohortKind
    generator_version: str
    activation_eligible: Literal[True]
    route_ids: tuple[str, ...]
    province_counts: dict[Literal["AB", "BC", "MB", "SK"], int]
    hub_counts: dict[str, int]
    geohash4_cells: tuple[str, ...]
    program_batches: tuple[ProgramBatch, ...]
    sources: tuple[SourceManifest, ...]
    routes: tuple[RoutePayload, ...]


@dataclass(frozen=True, slots=True)
class ValidatedManifest:
    document: UploadDocument
    manifest_sha256: str
    route_ids_sha256: str
    program_route_count: int

    @property
    def batch_id(self) -> str:
        return self.document.batch_id

    @property
    def cohort_kind(self) -> CohortKind:
        return self.document.cohort_kind

    @property
    def route_ids(self) -> tuple[str, ...]:
        return self.document.route_ids

    @property
    def routes(self) -> tuple[RoutePayload, ...]:
        return self.document.routes


@dataclass(frozen=True, slots=True)
class BatchAudit:
    batch_id: str
    status: str
    manifest_sha256: str
    expected_route_count: int
    actual_route_count: int
    route_ids_match: bool
    catalog_epoch: int


@dataclass(frozen=True, slots=True)
class RouteConflict:
    route_id: str
    generation_batch_id: str | None


@dataclass(frozen=True, slots=True)
class TransitionResult:
    batch_id: str
    previous_state: str
    current_state: str
    changed: bool
    catalog_epoch: int


@dataclass(frozen=True, slots=True)
class UploadReceipt:
    batch_id: str
    manifest_sha256: str
    route_ids_sha256: str
    route_count: int
    request_count: int
    applied: bool
    changed: bool
    status: Literal["shadow"] = "shadow"


@dataclass(frozen=True, slots=True)
class TransitionReceipt:
    batch_id: str
    manifest_sha256: str
    target_state: TargetState
    applied: bool
    changed: bool
    previous_state: str | None
    current_state: str | None
    catalog_epoch: int | None


class UploadStore(Protocol):
    def audit_batch(self, batch_id: str) -> BatchAudit | None: ...

    def find_route_conflicts(
        self, route_ids: tuple[str, ...]
    ) -> tuple[RouteConflict, ...]: ...

    def register_batch(self, manifest: ValidatedManifest) -> None: ...

    def upsert_routes(self, rows: tuple[RoutePayload, ...]) -> None: ...

    def transition(
        self, batch_id: str, manifest_sha256: str, target_state: TargetState
    ) -> TransitionResult: ...
