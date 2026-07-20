from __future__ import annotations

from dataclasses import dataclass
from types import MappingProxyType
from typing import ClassVar, Final, Literal, override

from pydantic import BaseModel, ConfigDict, Field
from shapely.geometry.base import BaseGeometry

STATCAN_ARCHIVE_URL: Final = (
    "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/"
    "boundary-limites/files-fichiers/lpr_000a21a_e.zip"
)
STATCAN_ARCHIVE_SHA256: Final = (
    "c4dd830f8a6e9b4a1d80e71bc830ae319aaab37785cc92185e830f5e3da4714e"
)
STATCAN_ARCHIVE_BYTES: Final = 2_777_186
STATCAN_PRODUCT_VERSION: Final = "2021 Census Province/Territory DBF"
STATCAN_LICENSE_URL: Final = "https://open.canada.ca/en/open-government-licence-canada"
ARCHIVE_STEM: Final = "lpr_000a21a_e"
ARCHIVE_MEMBERS: Final = frozenset(
    f"{ARCHIVE_STEM}{suffix}" for suffix in (".dbf", ".prj", ".shp", ".shx", ".xml")
)
MAX_ARCHIVE_BYTES: Final = 8 * 1024 * 1024
MAX_EXPANDED_BYTES: Final = 8 * 1024 * 1024
PRUID_TO_CODE: Final = MappingProxyType(
    {
        "10": "NL",
        "11": "PE",
        "12": "NS",
        "13": "NB",
        "24": "QC",
        "35": "ON",
        "46": "MB",
        "47": "SK",
        "48": "AB",
        "59": "BC",
        "60": "YT",
        "61": "NT",
        "62": "NU",
    }
)
CODE_TO_REGION: Final = MappingProxyType(
    {
        "AB": "alberta",
        "BC": "british_columbia",
        "MB": "manitoba",
        "NB": "new_brunswick",
        "NL": "newfoundland_and_labrador",
        "NS": "nova_scotia",
        "NT": "northwest_territories",
        "NU": "nunavut",
        "ON": "ontario",
        "PE": "prince_edward_island",
        "QC": "quebec",
        "SK": "saskatchewan",
        "YT": "yukon",
    }
)
STRICT_MODEL: Final = ConfigDict(
    frozen=True,
    extra="forbid",
    strict=True,
    allow_inf_nan=False,
)


@dataclass(frozen=True, slots=True)
class BoundaryArchiveError(Exception):
    code: str
    detail: str

    @override
    def __str__(self) -> str:
        return f"{self.code}: {self.detail}"


class RegionRepairTarget(BaseModel):
    model_config: ClassVar[ConfigDict] = STRICT_MODEL

    id: str = Field(min_length=1)
    region: str | None
    center_lat: float = Field(ge=-90, le=90)
    center_lng: float = Field(ge=-180, le=180)


class ProposedRegionUpdate(BaseModel):
    model_config: ClassVar[ConfigDict] = STRICT_MODEL

    id: str
    expected_region: Literal[""] | None
    center_lat: float
    center_lng: float
    province_code: str
    region: str
    boundary_distance_m: float = Field(ge=0)


class RegionAmbiguity(BaseModel):
    model_config: ClassVar[ConfigDict] = STRICT_MODEL

    id: str
    center_lat: float
    center_lng: float
    province_codes: tuple[str, ...]


class RegionRepairReport(BaseModel):
    model_config: ClassVar[ConfigDict] = STRICT_MODEL

    schema_version: Literal["revv-region-repair-preflight-v1"]
    project_ref: str
    source_url: str
    source_product: str
    source_license_url: str
    boundary_sha256: str
    target_snapshot_sha256: str
    target_count: int
    unique_count: int
    ambiguous_count: int
    province_counts: dict[str, int]
    proposed_updates: tuple[ProposedRegionUpdate, ...]
    ambiguities: tuple[RegionAmbiguity, ...]
    production_writes: Literal[0]


@dataclass(frozen=True, slots=True)
class ProvinceBoundary:
    code: str
    geometry: BaseGeometry
