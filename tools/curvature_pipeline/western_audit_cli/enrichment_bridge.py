from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import final

from ..western_enrichment.model import (
    CandidateKind,
    CoordinateInput,
    ElevationEvidence,
    EnrichmentManifest,
    HubManifest,
    OverpassHttpResponse,
    QualityEvidence,
    RouteCandidate,
    SelectionClass,
    TileRequest,
    VerificationVersions,
    WesternProvince,
)
from ..western_selection.model import ProvinceCode, QualityCandidate
from ..western_selection.quality import quality_score

VERSIONS: VerificationVersions = VerificationVersions(
    overpass="audit-cli-overpass-v1",
    stop_control="audit-cli-stop-control-v1",
    context="audit-cli-context-v1",
    residential="audit-cli-residential-v1",
    quality="audit-cli-quality-v1",
    elevation="audit-cli-elevation-v1",
)


@final
class FixtureOverpassTransport:
    """A canned-response transport: never opens a socket.

    Mirrors ``western_enrichment.__main__.FixtureTransport`` exactly - it
    exists here (rather than importing the CLI's private class) only so this
    module has no import-time dependency on another stage's ``__main__``.
    """

    def __init__(self, body: bytes) -> None:
        self._body: bytes = body

    async def fetch(
        self,
        endpoint: str,
        request: TileRequest,
        timeout_seconds: float,
    ) -> OverpassHttpResponse:
        del endpoint, request, timeout_seconds
        return OverpassHttpResponse(status_code=200, body=self._body)


def build_enrichment_manifest(
    accepted: tuple[QualityCandidate, ...],
    pilot_route_ids: frozenset[str],
    expansion_route_ids: frozenset[str],
    selection_checksum: str,
) -> EnrichmentManifest:
    """Build a diagnostic enrichment manifest over quality-accepted routes.

    Routes that made it into a real pilot/expansion batch are labeled with
    their real ``SelectionClass``. Routes that only passed quality/dedupe but
    were never selected into a complete activation-eligible batch (for
    example because the dry-run fixture is far smaller than the 120-250
    route production quota) are still labeled ``PILOT`` so the model's
    enum is satisfied, but the pipeline report marks the whole enrichment
    run as a non-authoritative preview whenever ``selection.status`` is not
    ``READY`` - this never claims those routes are activation eligible.
    """
    hub_provinces: dict[str, WesternProvince] = {
        item.route.hub_id: WesternProvince(item.route.province_code)
        for item in accepted
    }
    hubs = tuple(
        HubManifest(hub_id=hub_id, province_code=hub_provinces[hub_id])
        for hub_id in sorted(hub_provinces)
    )
    routes = tuple(
        sorted(
            (
                _route_candidate(item, pilot_route_ids, expansion_route_ids)
                for item in accepted
            ),
            key=lambda route: route.route_id,
        )
    )
    return EnrichmentManifest(
        manifest_version="western-enrichment-v1",
        selection_checksum=selection_checksum,
        hubs=hubs,
        versions=VERSIONS,
        routes=routes,
    )


def _route_candidate(
    candidate: QualityCandidate,
    pilot_route_ids: frozenset[str],
    expansion_route_ids: frozenset[str],
) -> RouteCandidate:
    route = candidate.route
    if route.route_id in expansion_route_ids:
        selection = SelectionClass.EXPANSION
    elif route.route_id in pilot_route_ids:
        selection = SelectionClass.PILOT
    else:
        # Quality-accepted but never allocated into a complete batch: keep
        # the enum satisfied while the manifest section stays diagnostic.
        selection = SelectionClass.PILOT
    return RouteCandidate(
        route_id=route.route_id,
        hub_id=route.hub_id,
        province_code=WesternProvince(route.province_code),
        kind=CandidateKind.GENERATED,
        selection=selection,
        accepted=True,
        selected=(
            route.route_id in pilot_route_ids or route.route_id in expansion_route_ids
        ),
        distance_m=route.distance_m,
        nodes=tuple(
            CoordinateInput(lat=point.lat, lng=point.lng) for point in route.geometry
        ),
        quality_evidence=QualityEvidence(
            version=VERSIONS.quality, score=quality_score(candidate) / 100.0
        ),
        elevation_evidence=ElevationEvidence(
            version=VERSIONS.elevation, profile_m=(0.0, 0.0)
        ),
    )


def selection_checksum_bytes(selection_bytes: bytes) -> str:
    return hashlib.sha256(selection_bytes).hexdigest()


def enrichment_manifest_bytes(manifest: EnrichmentManifest) -> bytes:
    payload: object = manifest.model_dump(mode="json")
    return json.dumps(
        payload,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def write_manifest(path: Path, manifest: EnrichmentManifest) -> None:
    _ = path.write_bytes(enrichment_manifest_bytes(manifest))


__all__ = [
    "VERSIONS",
    "FixtureOverpassTransport",
    "ProvinceCode",
    "build_enrichment_manifest",
    "enrichment_manifest_bytes",
    "selection_checksum_bytes",
    "write_manifest",
]
