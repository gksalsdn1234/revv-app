from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Final, Protocol

from pydantic import JsonValue, TypeAdapter, ValidationError

from .western_contract import (
    EXPECTED_PROJECT_NAME,
    EXPECTED_PROJECT_REF,
    AuditDataset,
    CountBaseline,
    RouteAuditRow,
    RpcSample,
)
from .western_source import (
    AuditContractError,
    AuditJsonValue,
    JsonDocument,
    JsonFetch,
)


class WesternAuditSource(Protocol):
    def get_curvy_roads_page(self, *, offset: int, page_size: int) -> JsonDocument: ...

    def post_rpc_with_metrics(
        self, function_name: str, payload: dict[str, AuditJsonValue]
    ) -> JsonFetch: ...


@dataclass(frozen=True, slots=True)
class AuditCenter:
    name: str
    lat: float
    lng: float


WESTERN_CENTERS: Final = (
    AuditCenter("victoria", 48.4284, -123.3656),
    AuditCenter("vancouver", 49.2827, -123.1207),
    AuditCenter("kamloops", 50.6745, -120.3273),
    AuditCenter("banff", 51.1784, -115.5708),
    AuditCenter("calgary", 51.0447, -114.0719),
    AuditCenter("edmonton", 53.5461, -113.4938),
    AuditCenter("jasper", 52.8737, -118.0814),
    AuditCenter("regina", 50.4452, -104.6189),
    AuditCenter("saskatoon", 52.1579, -106.6702),
    AuditCenter("swift_current", 50.2851, -107.7972),
    AuditCenter("winnipeg", 49.8954, -97.1385),
)
KNOWN_BASELINES: Final = (
    CountBaseline(metric="rows_total", expected=83208, tolerance=4160),
    CountBaseline(
        metric="national.recommendation_distance", expected=4534, tolerance=500
    ),
    CountBaseline(
        metric="national.map_distance_window", expected=66414, tolerance=5000
    ),
    CountBaseline(metric="province.AB.raw_rows", expected=10836, tolerance=1100),
    CountBaseline(metric="province.BC.raw_rows", expected=14037, tolerance=1400),
    CountBaseline(metric="province.MB.raw_rows", expected=2504, tolerance=300),
    CountBaseline(metric="province.SK.raw_rows", expected=2131, tolerance=250),
    CountBaseline(metric="center.calgary.raw_rows", expected=5808, tolerance=581),
    CountBaseline(
        metric="center.calgary.recommendation_distance", expected=81, tolerance=9
    ),
    CountBaseline(metric="center.edmonton.raw_rows", expected=3291, tolerance=330),
    CountBaseline(
        metric="center.edmonton.recommendation_distance", expected=14, tolerance=2
    ),
    CountBaseline(metric="center.regina.raw_rows", expected=500, tolerance=50),
    CountBaseline(
        metric="center.regina.recommendation_distance", expected=4, tolerance=2
    ),
    CountBaseline(metric="center.saskatoon.raw_rows", expected=746, tolerance=75),
    CountBaseline(
        metric="center.saskatoon.recommendation_distance", expected=4, tolerance=2
    ),
    CountBaseline(metric="center.vancouver.raw_rows", expected=5722, tolerance=573),
    CountBaseline(
        metric="center.vancouver.recommendation_distance", expected=262, tolerance=27
    ),
)
_PAGE_SIZE: Final = 1000
_MAX_PAGES: Final = 200


def capture_live_dataset(source: WesternAuditSource) -> AuditDataset:
    rows = _fetch_rows(source)
    samples = tuple(
        _fetch_rpc_sample(source, center, rpc)
        for center in WESTERN_CENTERS
        for rpc in ("find_curvy_roads", "find_curvy_map_segments")
    )
    return AuditDataset(
        project_name=EXPECTED_PROJECT_NAME,
        project_ref=EXPECTED_PROJECT_REF,
        captured_at=datetime.now(UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        rpc_samples=samples,
        known_count_baselines=KNOWN_BASELINES,
        rows=rows,
    )


def _fetch_rows(source: WesternAuditSource) -> tuple[RouteAuditRow, ...]:
    rows: list[RouteAuditRow] = []
    adapter = TypeAdapter(list[RouteAuditRow])
    for page in range(_MAX_PAGES):
        payload = source.get_curvy_roads_page(
            offset=page * _PAGE_SIZE,
            page_size=_PAGE_SIZE,
        )
        try:
            parsed = adapter.validate_python(payload)
        except ValidationError as error:
            raise AuditContractError(
                code="malformed_row",
                detail="curvy_roads returned a row outside the audit schema",
            ) from error
        rows.extend(parsed)
        if len(parsed) < _PAGE_SIZE:
            return tuple(rows)
    raise AuditContractError(
        code="row_budget_exceeded",
        detail=f"curvy_roads exceeded {_PAGE_SIZE * _MAX_PAGES} audit rows",
    )


def _fetch_rpc_sample(
    source: WesternAuditSource, center: AuditCenter, rpc: str
) -> RpcSample:
    threshold = "min_score" if rpc == "find_curvy_roads" else "min_distance_km"
    fetch = source.post_rpc_with_metrics(
        rpc,
        {
            "user_lat": center.lat,
            "user_lng": center.lng,
            "radius_m": 160000,
            threshold: 0 if rpc == "find_curvy_roads" else 0.3,
            "max_results": 120 if rpc == "find_curvy_roads" else 60,
        },
    )
    try:
        returned_rows = len(
            TypeAdapter(list[dict[str, JsonValue]]).validate_python(fetch.payload)
        )
    except ValidationError as error:
        raise AuditContractError(
            code="malformed_rpc",
            detail=f"{rpc} returned malformed data for {center.name}",
        ) from error
    return RpcSample(
        rpc=rpc,
        center=center.name,
        lat=center.lat,
        lng=center.lng,
        radius_m=160000,
        returned_rows=returned_rows,
        payload_bytes=fetch.payload_bytes,
        latency_ms=fetch.latency_ms,
    )
