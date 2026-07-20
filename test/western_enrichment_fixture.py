from __future__ import annotations

from collections.abc import Mapping
from typing import final

import anyio

from tools.curvature_pipeline.western_enrichment import (
    EnrichmentManifest,
    OverpassHttpResponse,
    TileRequest,
)
from tools.curvature_pipeline.western_enrichment.model import (
    CandidateKind,
    CoordinateInput,
    ElevationEvidence,
    ExistingVersions,
    HubManifest,
    QualityEvidence,
    RouteCandidate,
    SelectionClass,
    VerificationVersions,
    WesternProvince,
)


@final
class FixtureTransport:
    _PAIR_SIZE = 2

    def __init__(
        self,
        responses: Mapping[tuple[str, str], tuple[OverpassHttpResponse, ...]],
        *,
        hold_for_pair: bool = False,
    ) -> None:
        self._responses: dict[tuple[str, str], list[OverpassHttpResponse]] = {
            key: list(value) for key, value in responses.items()
        }
        self._hold_for_pair: bool = hold_for_pair
        self._pair_ready: anyio.Event = anyio.Event()
        self.calls: list[tuple[str, str, float]] = []
        self.active: int = 0
        self.peak_active: int = 0

    async def fetch(
        self,
        endpoint: str,
        request: TileRequest,
        timeout_seconds: float,
    ) -> OverpassHttpResponse:
        self.calls.append((endpoint, request.cache_key, timeout_seconds))
        self.active += 1
        self.peak_active = max(self.peak_active, self.active)
        if self._hold_for_pair:
            if self.active == self._PAIR_SIZE:
                self._pair_ready.set()
            await self._pair_ready.wait()
        try:
            queued = self._responses[(endpoint, request.cache_key)]
            return queued.pop(0)
        finally:
            self.active -= 1


def overpass_payload() -> bytes:
    return (
        b'{"elements":['
        b'{"type":"node","id":1,"lat":51.0001,"lon":-114.0001,'
        b'"tags":{"highway":"stop"}},'
        b'{"type":"way","id":2,"tags":{"highway":"secondary",'
        b'"name":"Ridge Road","surface":"asphalt"}}]}'
    )


def make_route(
    route_id: str,
    hub_id: str,
    lat: float,
    lng: float,
    *,
    batch: SelectionClass = SelectionClass.PILOT,
) -> RouteCandidate:
    return RouteCandidate(
        route_id=route_id,
        hub_id=hub_id,
        province_code=WesternProvince.AB,
        kind=CandidateKind.GENERATED,
        selection=batch,
        accepted=True,
        selected=True,
        distance_m=20_000.0,
        nodes=(
            CoordinateInput(lat=lat, lng=lng),
            CoordinateInput(lat=lat + 0.005, lng=lng + 0.005),
        ),
        quality_evidence=QualityEvidence(version="quality-v4", score=0.91),
        elevation_evidence=ElevationEvidence(
            version="elevation-v1",
            profile_m=(900.0, 940.0, 925.0),
        ),
        existing_versions=ExistingVersions(),
    )


def make_manifest(routes: list[RouteCandidate]) -> EnrichmentManifest:
    hubs = tuple(
        HubManifest(hub_id=hub_id, province_code=WesternProvince.AB)
        for hub_id in sorted({route.hub_id for route in routes})
    )
    return EnrichmentManifest(
        manifest_version="western-enrichment-v1",
        selection_checksum="a" * 64,
        hubs=hubs,
        versions=VerificationVersions(
            overpass="overpass-west-v1",
            stop_control="stop-control-v2",
            context="route-context-v2",
            residential="residential-v3",
            quality="quality-v4",
            elevation="elevation-v1",
        ),
        routes=tuple(routes),
    )
