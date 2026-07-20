from __future__ import annotations

import json
from typing import TypedDict

from .model import NativeSeed, NativeSeedBatch


class _CoordinatePayload(TypedDict):
    lat: float
    lng: float


class _SeedPayload(TypedDict):
    seed_id: str
    hub_id: str
    province_code: str
    source_pbf_checksum: str
    hub_pbf_checksum: str
    source: str
    source_license: str
    edge_ids: list[str]
    osm_way_ids: list[int]
    points: list[_CoordinatePayload]
    road_refs: list[str]
    distance_m: float
    total_turn_degrees: float


class _BatchPayload(TypedDict):
    schema_version: int
    generator_version: str
    hub_id: str
    province_code: str
    source_pbf_checksum: str
    hub_pbf_checksum: str
    seeds: list[_SeedPayload]


class _BatchCollectionPayload(TypedDict):
    schema_version: int
    clusters: list[_BatchPayload]


def seed_batch_bytes(batch: NativeSeedBatch) -> bytes:
    return _json_bytes(_batch_payload(batch))


def seed_batches_bytes(batches: tuple[NativeSeedBatch, ...]) -> bytes:
    ordered = sorted(
        batches,
        key=lambda batch: tuple(seed.seed_id for seed in batch.seeds),
    )
    payload: _BatchCollectionPayload = {
        "schema_version": 1,
        "clusters": [_batch_payload(batch) for batch in ordered],
    }
    return _json_bytes(payload)


def _batch_payload(batch: NativeSeedBatch) -> _BatchPayload:
    return {
        "schema_version": batch.schema_version,
        "generator_version": batch.generator_version,
        "hub_id": batch.hub_id,
        "province_code": batch.province_code,
        "source_pbf_checksum": batch.source_pbf_checksum,
        "hub_pbf_checksum": batch.hub_pbf_checksum,
        "seeds": [_seed_payload(seed) for seed in batch.seeds],
    }


def _json_bytes(payload: _BatchPayload | _BatchCollectionPayload) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _seed_payload(seed: NativeSeed) -> _SeedPayload:
    return {
        "seed_id": seed.seed_id,
        "hub_id": seed.hub_id,
        "province_code": seed.province_code,
        "source_pbf_checksum": seed.source_pbf_checksum,
        "hub_pbf_checksum": seed.hub_pbf_checksum,
        "source": "osm",
        "source_license": seed.source_license,
        "edge_ids": list(seed.edge_ids),
        "osm_way_ids": list(seed.osm_way_ids),
        "points": [{"lat": point.lat, "lng": point.lng} for point in seed.points],
        "road_refs": list(seed.road_refs),
        "distance_m": seed.distance_m,
        "total_turn_degrees": seed.total_turn_degrees,
    }
