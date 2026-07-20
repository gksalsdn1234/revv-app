from __future__ import annotations

import json
from typing import TypedDict

from .model import GeneratedRoute


class _CoordinatePayload(TypedDict):
    lat: float
    lng: float


class _ReplaySpanPayload(TypedDict):
    first_edge_index: int
    last_edge_index: int


class _RoutePayload(TypedDict):
    distance_m: float
    edge_ids: list[str]
    generator_version: str
    geometry: list[_CoordinatePayload]
    hausdorff_error_m: float
    hub_id: str
    hub_pbf_checksum: str
    is_loop: bool
    length_error_ratio: float
    province_code: str
    replay_spans: list[_ReplaySpanPayload]
    route_id: str
    seed_ids: list[str]
    source_pbf_checksum: str


class _RouteBatchPayload(TypedDict):
    schema_version: int
    routes: list[_RoutePayload]


def route_bytes(route: GeneratedRoute) -> bytes:
    return _json_bytes(_route_payload(route))


def route_batch_bytes(routes: tuple[GeneratedRoute, ...]) -> bytes:
    payload: _RouteBatchPayload = {
        "schema_version": 1,
        "routes": [
            _route_payload(route)
            for route in sorted(routes, key=lambda item: item.route_id)
        ],
    }
    return _json_bytes(payload)


def _route_payload(route: GeneratedRoute) -> _RoutePayload:
    return {
        "distance_m": round(route.distance_m, 6),
        "edge_ids": list(route.edge_ids),
        "generator_version": route.generator_version,
        "geometry": [
            {"lat": round(point.lat, 8), "lng": round(point.lng, 8)}
            for point in route.geometry
        ],
        "hausdorff_error_m": round(route.hausdorff_error_m, 6),
        "hub_id": route.hub_id,
        "hub_pbf_checksum": route.hub_pbf_checksum,
        "is_loop": route.is_loop,
        "length_error_ratio": round(route.length_error_ratio, 9),
        "province_code": route.province_code,
        "replay_spans": [
            {
                "first_edge_index": span.first_edge_index,
                "last_edge_index": span.last_edge_index,
            }
            for span in route.replay_spans
        ],
        "route_id": route.route_id,
        "seed_ids": list(route.seed_ids),
        "source_pbf_checksum": route.source_pbf_checksum,
    }


def _json_bytes(payload: _RoutePayload | _RouteBatchPayload) -> bytes:
    return json.dumps(
        payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
