from __future__ import annotations

import math
import re
from collections import Counter
from types import MappingProxyType
from typing import ClassVar, Final

from pydantic import BaseModel, ConfigDict, Field, JsonValue


EXPECTED_PROJECT_NAME: Final = "Revv"
EXPECTED_PROJECT_REF: Final = "zvwgnduuumksuqazpvsf"
ALLOWED_PROVINCE_CODES: Final = (
    "AB",
    "BC",
    "MB",
    "NB",
    "NL",
    "NS",
    "NT",
    "NU",
    "ON",
    "PE",
    "QC",
    "SK",
    "YT",
)
LEGACY_REGION_TO_PROVINCE: Final = MappingProxyType(
    {
        "alberta": "AB",
        "british_columbia": "BC",
        "manitoba": "MB",
        "new_brunswick": "NB",
        "newfoundland_and_labrador": "NL",
        "nova_scotia": "NS",
        "northwest_territories": "NT",
        "nunavut": "NU",
        "ontario": "ON",
        "prince_edward_island": "PE",
        "quebec": "QC",
        "saskatchewan": "SK",
        "yukon": "YT",
    }
)
_NUMERIC_NAME = re.compile(r"^[\d\-\s_]+$")
_STRICT_MODEL = ConfigDict(
    frozen=True,
    extra="forbid",
    strict=True,
    allow_inf_nan=False,
)


class RouteAuditRow(BaseModel):
    model_config: ClassVar[ConfigDict] = _STRICT_MODEL

    id: str = Field(min_length=1)
    region: str | None
    name: str | None
    center_lat: float = Field(ge=-90, le=90)
    center_lng: float = Field(ge=-180, le=180)
    distance_km: float = Field(ge=0)
    winding_score: float = 0.0
    is_facility_like: bool = False
    is_connector_like: bool = False
    stop_sign_count: int = Field(default=0, ge=0)
    stop_control_density: float = Field(default=0, ge=0)
    max_continuous_km: float = Field(default=0, ge=0)
    quality_version: str | None = None
    residential_version: str | None = None
    stop_control_version: str | None = None
    context_version: str | None = None


class RpcSample(BaseModel):
    model_config: ClassVar[ConfigDict] = _STRICT_MODEL

    rpc: str = Field(pattern=r"^find_curvy_(roads|map_segments)$")
    center: str = Field(min_length=1)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    radius_m: int = Field(gt=0, le=160000)
    returned_rows: int = Field(ge=0)
    payload_bytes: int = Field(ge=0)
    latency_ms: float = Field(ge=0)


class CountBaseline(BaseModel):
    model_config: ClassVar[ConfigDict] = _STRICT_MODEL

    metric: str = Field(min_length=1)
    expected: int = Field(ge=0)
    tolerance: int = Field(ge=0)


class AuditDataset(BaseModel):
    model_config: ClassVar[ConfigDict] = _STRICT_MODEL

    project_name: str
    project_ref: str
    captured_at: str = Field(min_length=1)
    rpc_samples: tuple[RpcSample, ...]
    known_count_baselines: tuple[CountBaseline, ...]
    rows: tuple[RouteAuditRow, ...]


class AuditReport(BaseModel):
    model_config: ClassVar[ConfigDict] = _STRICT_MODEL

    schema_version: int
    source: str
    project: dict[str, str]
    captured_at: str
    province_classification: dict[str, JsonValue]
    funnels: dict[str, JsonValue]
    enrichment: dict[str, int]
    duplicates: dict[str, JsonValue]
    payloads: dict[str, JsonValue]
    rpc_latency: dict[str, JsonValue]
    baseline_assertions: tuple[dict[str, JsonValue], ...]
    gates: dict[str, bool]


def normalize_region(value: str | None) -> str:
    if value is None:
        return ""
    normalized = re.sub(r"[\s\-]+", "_", value.strip().lower())
    return re.sub(r"_+", "_", normalized).strip("_")


def classify_province(value: str | None) -> str | None:
    return LEGACY_REGION_TO_PROVINCE.get(normalize_region(value))


def recommendation_eligible(row: RouteAuditRow) -> bool:
    if (
        row.distance_km < 4.0
        or row.winding_score < 0.0
        or row.is_facility_like
        or row.is_connector_like
    ):
        return False
    if row.stop_sign_count >= 5 and row.distance_km < 12.0:
        return False
    if row.stop_control_density >= 0.65 and row.max_continuous_km < 1.2:
        return False
    return not (
        _NUMERIC_NAME.fullmatch((row.name or "").strip()) is not None
        and row.distance_km < 8.0
    )


def funnel(rows: tuple[RouteAuditRow, ...]) -> dict[str, int]:
    return {
        "raw_rows": len(rows),
        "map_distance_window": sum(1 for row in rows if 0.3 <= row.distance_km < 4.0),
        "recommendation_distance": sum(1 for row in rows if row.distance_km >= 4.0),
        "recommendation_eligible": sum(
            1 for row in rows if recommendation_eligible(row)
        ),
    }


def distance_km(row: RouteAuditRow, sample: RpcSample) -> float:
    lat1 = math.radians(row.center_lat)
    lat2 = math.radians(sample.lat)
    delta_lat = lat2 - lat1
    delta_lng = math.radians(sample.lng - row.center_lng)
    chord = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lng / 2) ** 2
    )
    return 6371.0088 * 2 * math.atan2(math.sqrt(chord), math.sqrt(1 - chord))


def metric_value(metric: str, dataset: AuditDataset) -> int | None:
    rows = dataset.rows
    if metric == "rows_total":
        return len(rows)
    national_match = re.fullmatch(r"national\.(\w+)", metric)
    if national_match is not None:
        return funnel(rows).get(national_match.group(1))
    metric_match = re.fullmatch(r"province\.([A-Z]{2})\.(\w+)", metric)
    if metric_match is not None:
        code, key = metric_match.groups()
        province_rows = tuple(
            row for row in rows if classify_province(row.region) == code
        )
        return funnel(province_rows).get(key)
    center_match = re.fullmatch(r"center\.([a-z_]+)\.(\w+)", metric)
    if center_match is None:
        return None
    center, key = center_match.groups()
    sample = next(
        (sample for sample in dataset.rpc_samples if sample.center == center), None
    )
    if sample is None:
        return None
    nearby = tuple(
        row for row in rows if distance_km(row, sample) <= sample.radius_m / 1000.0
    )
    return funnel(nearby).get(key)


def parse_dataset_json(raw: str) -> AuditDataset:
    return AuditDataset.model_validate_json(raw)


def duplicate_summary(rows: tuple[RouteAuditRow, ...]) -> dict[str, JsonValue]:
    ids = Counter(row.id for row in rows)
    signatures = Counter(
        (
            (row.name or "").strip().casefold(),
            round(row.center_lat, 5),
            round(row.center_lng, 5),
            round(row.distance_km, 2),
        )
        for row in rows
    )
    return {
        "duplicate_id_groups": sum(1 for count in ids.values() if count > 1),
        "duplicate_signature_groups": sum(
            1 for count in signatures.values() if count > 1
        ),
    }
