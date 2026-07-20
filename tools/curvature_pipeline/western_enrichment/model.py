from __future__ import annotations

import math
import re
from dataclasses import dataclass
from enum import StrEnum
from typing import ClassVar, Protocol, Self, assert_never, override

from pydantic import BaseModel, ConfigDict, Field, model_validator

_CHECKSUM = re.compile(r"[0-9a-f]{64}")
MAX_SELECTED_ROUTES = 250


class WesternProvince(StrEnum):
    AB = "AB"
    BC = "BC"
    MB = "MB"
    SK = "SK"


class CandidateKind(StrEnum):
    GENERATED = "generated"
    LEGACY = "legacy"


class SelectionClass(StrEnum):
    PILOT = "pilot"
    EXPANSION = "expansion"
    LEGACY_LONG = "legacy_long"


class RunStatus(StrEnum):
    READY = "READY"
    PARTIAL_LEGACY = "PARTIAL_LEGACY"
    NO_GO_INCOMPLETE_GENERATED = "NO_GO_INCOMPLETE_GENERATED"
    NO_GO_REQUEST_BUDGET = "NO_GO_REQUEST_BUDGET"
    NO_GO_TIME_BUDGET = "NO_GO_TIME_BUDGET"


class OutcomeStatus(StrEnum):
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    SKIPPED = "skipped"


class CoordinateInput(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    lat: float = Field(ge=-90.0, le=90.0, allow_inf_nan=False)
    lng: float = Field(ge=-180.0, le=180.0, allow_inf_nan=False)


class QualityEvidence(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    version: str = Field(min_length=1, max_length=80)
    score: float = Field(ge=0.0, le=1.0, allow_inf_nan=False)


class ElevationEvidence(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    version: str = Field(min_length=1, max_length=80)
    profile_m: tuple[float, ...] = Field(min_length=2, max_length=300)

    @model_validator(mode="after")
    def finite_profile(self) -> Self:
        if not all(math.isfinite(value) for value in self.profile_m):
            raise EnrichmentManifestError("elevation profile must be finite")
        return self


class ExistingVersions(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    stop_control: str | None = None
    context: str | None = None
    residential: str | None = None
    quality: str | None = None
    elevation: str | None = None


class VerificationVersions(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    overpass: str = Field(min_length=1, max_length=80)
    stop_control: str = Field(min_length=1, max_length=80)
    context: str = Field(min_length=1, max_length=80)
    residential: str = Field(min_length=1, max_length=80)
    quality: str = Field(min_length=1, max_length=80)
    elevation: str = Field(min_length=1, max_length=80)


class HubManifest(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    hub_id: str = Field(min_length=1, max_length=120)
    province_code: WesternProvince


class RouteCandidate(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    route_id: str = Field(min_length=1, max_length=160)
    hub_id: str = Field(min_length=1, max_length=120)
    province_code: WesternProvince
    kind: CandidateKind
    selection: SelectionClass
    accepted: bool
    selected: bool
    distance_m: float = Field(gt=0.0, le=80_000.0, allow_inf_nan=False)
    nodes: tuple[CoordinateInput, ...] = Field(min_length=2, max_length=300)
    quality_evidence: QualityEvidence | None = None
    elevation_evidence: ElevationEvidence | None = None
    existing_versions: ExistingVersions = ExistingVersions()
    legacy_rank: int | None = Field(default=None, ge=1, le=1_000_000)

    @model_validator(mode="after")
    def valid_selection(self) -> Self:
        match self.kind:
            case CandidateKind.GENERATED:
                if self.selection not in {
                    SelectionClass.PILOT,
                    SelectionClass.EXPANSION,
                }:
                    raise EnrichmentManifestError(
                        "generated route must use pilot or expansion selection"
                    )
            case CandidateKind.LEGACY:
                if self.selection is not SelectionClass.LEGACY_LONG:
                    raise EnrichmentManifestError(
                        "legacy route must use legacy_long selection"
                    )
                if self.legacy_rank is None:
                    raise EnrichmentManifestError("legacy route requires rank evidence")
            case _ as unreachable:
                assert_never(unreachable)
        return self


class EnrichmentManifest(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    manifest_version: str = Field(pattern=r"^western-enrichment-v1$")
    selection_checksum: str
    hubs: tuple[HubManifest, ...] = Field(min_length=1, max_length=64)
    versions: VerificationVersions
    routes: tuple[RouteCandidate, ...] = Field(max_length=500)

    @model_validator(mode="after")
    def consistent_scope(self) -> Self:
        if _CHECKSUM.fullmatch(self.selection_checksum) is None:
            raise EnrichmentManifestError("selection checksum must be lowercase sha256")
        hubs = {hub.hub_id: hub.province_code for hub in self.hubs}
        if len(hubs) != len(self.hubs):
            raise EnrichmentManifestError("hub ids must be unique")
        route_ids = {route.route_id for route in self.routes}
        if len(route_ids) != len(self.routes):
            raise EnrichmentManifestError("route ids must be unique")
        for route in self.routes:
            if hubs.get(route.hub_id) is not route.province_code:
                raise EnrichmentManifestError("route hub/province evidence mismatch")
        if (
            len(tuple(route for route in self.routes if route.selected))
            > MAX_SELECTED_ROUTES
        ):
            raise EnrichmentManifestError(
                "selected enrichment scope exceeds 250 routes"
            )
        return self


@dataclass(frozen=True, slots=True)
class EnrichmentManifestError(ValueError):
    detail: str

    @override
    def __str__(self) -> str:
        return self.detail


@dataclass(frozen=True, slots=True)
class EnrichmentInvariantError(RuntimeError):
    invariant: str

    @override
    def __str__(self) -> str:
        return f"western enrichment invariant failed: {self.invariant}"


@dataclass(frozen=True, slots=True)
class TileRequest:
    lat_index: int
    lng_index: int
    tile_size_deg: float
    version: str

    @property
    def cache_key(self) -> str:
        return f"{self.version}:{self.lat_index}:{self.lng_index}"

    @property
    def bbox(self) -> tuple[float, float, float, float]:
        south = self.lat_index * self.tile_size_deg
        west = self.lng_index * self.tile_size_deg
        return (south, west, south + self.tile_size_deg, west + self.tile_size_deg)

    @classmethod
    def for_coordinate(
        cls,
        *,
        lat: float,
        lng: float,
        tile_size_deg: float,
        version: str,
    ) -> TileRequest:
        return cls(
            lat_index=math.floor(lat / tile_size_deg),
            lng_index=math.floor(lng / tile_size_deg),
            tile_size_deg=tile_size_deg,
            version=version,
        )


@dataclass(frozen=True, slots=True)
class OverpassHttpResponse:
    status_code: int
    body: bytes
    timed_out: bool = False

    @classmethod
    def timeout(cls) -> OverpassHttpResponse:
        return cls(status_code=0, body=b"", timed_out=True)


class OverpassTransport(Protocol):
    async def fetch(
        self,
        endpoint: str,
        request: TileRequest,
        timeout_seconds: float,
    ) -> OverpassHttpResponse: ...


class MonotonicClock(Protocol):
    def now(self) -> float: ...


@dataclass(frozen=True, slots=True)
class EnrichmentRuntime:
    transport: OverpassTransport
    clock: MonotonicClock | None = None


class EnrichedMetadata(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    stop_sign_count: int = Field(ge=0)
    traffic_signal_count: int = Field(ge=0)
    road_names: tuple[str, ...]
    surfaces: tuple[str, ...]
    residential_ratio: float = Field(ge=0.0, le=1.0, allow_inf_nan=False)
    quality_score: float = Field(ge=0.0, le=1.0, allow_inf_nan=False)
    elevation_profile_m: tuple[float, ...]
    versions: VerificationVersions


class RouteOutcome(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    route_id: str
    status: OutcomeStatus
    activation_eligible: bool
    failed_fields: tuple[str, ...]
    metadata: EnrichedMetadata | None

    @model_validator(mode="after")
    def consistent_outcome(self) -> Self:
        match self.status:
            case OutcomeStatus.SUCCEEDED | OutcomeStatus.SKIPPED:
                if self.metadata is None or self.failed_fields:
                    raise EnrichmentInvariantError("successful route outcome")
            case OutcomeStatus.FAILED:
                if (
                    self.metadata is not None
                    or self.activation_eligible
                    or not self.failed_fields
                ):
                    raise EnrichmentInvariantError("failed route outcome")
            case _ as unreachable:
                assert_never(unreachable)
        return self


class RunSummary(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    attempted: int = Field(ge=0)
    succeeded: int = Field(ge=0)
    failed: int = Field(ge=0)
    skipped: int = Field(ge=0)
    unique_tile_queries: int = Field(ge=0)
    request_attempts: int = Field(ge=0, le=240)
    cache_hits: int = Field(ge=0)

    @model_validator(mode="after")
    def reconciled(self) -> Self:
        if self.attempted != self.succeeded + self.failed + self.skipped:
            raise EnrichmentInvariantError("route accounting")
        return self


class RunResult(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    status: RunStatus
    exit_code: int
    summary: RunSummary
    routes: tuple[RouteOutcome, ...]
