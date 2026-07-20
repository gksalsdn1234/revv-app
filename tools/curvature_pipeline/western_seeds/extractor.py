from __future__ import annotations

import hashlib
import math
from collections import defaultdict
from collections.abc import Iterable
from itertools import pairwise
from typing import Final, assert_never

from ..western_graph.model import Coordinate, GraphEdge, HubGraph
from ..western_graph.policy import Direction, evaluate_drivable_way
from ..western_routes.geometry import polyline_length_m
from .model import (
    DEFAULT_NATIVE_SEED_LIMITS,
    NativeSeed,
    NativeSeedBatch,
    NativeSeedError,
    NativeSeedLimits,
    NativeSeedRejection,
)
from .paths import road_paths

GENERATOR_VERSION: Final = "western-osm-seed-v1"


def extract_native_seeds(
    graph: HubGraph,
    *,
    limits: NativeSeedLimits = DEFAULT_NATIVE_SEED_LIMITS,
) -> NativeSeedBatch:
    seeds: dict[str, NativeSeed] = {}
    for path_seeds in native_seed_paths(graph, limits=limits):
        for seed in path_seeds:
            _ = seeds.setdefault(seed.seed_id, seed)
            if len(seeds) > limits.max_seeds:
                raise NativeSeedError(
                    NativeSeedRejection.RESOURCE_LIMIT,
                    "native seed output exceeds its fixed budget",
                )
    return NativeSeedBatch(
        schema_version=1,
        generator_version=GENERATOR_VERSION,
        hub_id=graph.hub_id,
        province_code=graph.province_code,
        source_pbf_checksum=graph.source_pbf_checksum,
        hub_pbf_checksum=graph.hub_pbf_checksum,
        seeds=tuple(seeds[seed_id] for seed_id in sorted(seeds)),
    )


def native_seed_paths(
    graph: HubGraph,
    *,
    limits: NativeSeedLimits = DEFAULT_NATIVE_SEED_LIMITS,
) -> Iterable[tuple[NativeSeed, ...]]:
    if len(graph.edges) > limits.max_candidate_edges:
        raise NativeSeedError(
            NativeSeedRejection.RESOURCE_LIMIT,
            "graph exceeds the native seed edge budget",
        )
    canonical_edges = _canonical_legal_edges(graph)
    for path in road_paths(canonical_edges):
        seeds = tuple(
            _native_seed(graph, window) for window in _seed_windows(path, limits)
        )
        if seeds:
            yield seeds


def physical_edge_tokens(edges: tuple[GraphEdge, ...]) -> tuple[str, ...]:
    return tuple(f"w{edge.osm_way_id}:s{edge.segment_index}" for edge in edges)


def canonical_seed_id(graph: HubGraph, edges: tuple[GraphEdge, ...]) -> str:
    forward = physical_edge_tokens(edges)
    reverse = tuple(reversed(forward))
    canonical = min(forward, reverse)
    material = "|".join(
        (
            GENERATOR_VERSION,
            graph.hub_id,
            graph.source_pbf_checksum,
            graph.hub_pbf_checksum,
            *canonical,
        )
    ).encode("utf-8")
    return f"osmseed:v1:{hashlib.sha256(material).hexdigest()}"


def total_turn_degrees(edges: tuple[GraphEdge, ...]) -> float:
    bearings = tuple(_bearing(edge) for edge in edges)
    return sum(
        abs((following - current + 180.0) % 360.0 - 180.0)
        for current, following in pairwise(bearings)
    )


def seed_points(edges: tuple[GraphEdge, ...]) -> tuple[Coordinate, ...]:
    first_start, first_end = edges[0].coordinates
    last_start, last_end = edges[-1].coordinates
    first = first_start.model_copy(
        update={
            "lat": first_start.lat + (first_end.lat - first_start.lat) * 0.2,
            "lng": first_start.lng + (first_end.lng - first_start.lng) * 0.2,
        }
    )
    last = last_start.model_copy(
        update={
            "lat": last_start.lat + (last_end.lat - last_start.lat) * 0.8,
            "lng": last_start.lng + (last_end.lng - last_start.lng) * 0.8,
        }
    )
    if len(edges) == 1:
        return (first, last)
    return (first, *(edge.coordinates[1] for edge in edges[:-1]), last)


def _canonical_legal_edges(graph: HubGraph) -> tuple[GraphEdge, ...]:
    physical: dict[tuple[int, int], list[GraphEdge]] = defaultdict(list)
    for edge in graph.edges:
        expected_prefix = f"w{edge.osm_way_id}:s{edge.segment_index}:"
        if (
            edge.hub_id != graph.hub_id
            or edge.province_code != graph.province_code
            or edge.source_pbf_checksum != graph.source_pbf_checksum
            or not edge.edge_id.startswith(expected_prefix)
        ):
            raise NativeSeedError(
                NativeSeedRejection.PROVENANCE,
                "edge provenance differs from its graph",
            )
        physical[(edge.osm_way_id, edge.segment_index)].append(edge)
    selected: list[GraphEdge] = []
    for key in sorted(physical):
        variants = tuple(sorted(physical[key], key=lambda edge: edge.edge_id))
        decision = evaluate_drivable_way(
            {tag.key: tag.value for tag in variants[0].tags}
        )
        if decision is None or any(edge.tags != variants[0].tags for edge in variants):
            raise NativeSeedError(
                NativeSeedRejection.ILLEGAL_EDGE,
                "graph contains an edge outside the drivable OSM policy",
            )
        suffixes = tuple(edge.edge_id.rsplit(":", 1)[1] for edge in variants)
        match decision.direction:
            case Direction.FORWARD:
                expected = ("f",)
                chosen_suffix = "f"
            case Direction.REVERSE:
                expected = ("r",)
                chosen_suffix = "r"
            case Direction.BOTH:
                expected = ("f", "r")
                chosen_suffix = "f"
            case _:
                assert_never(decision.direction)
        if suffixes != expected:
            raise NativeSeedError(
                NativeSeedRejection.ILLEGAL_EDGE,
                "graph directions disagree with OSM access tags",
            )
        selected.append(
            next(
                edge for edge in variants if edge.edge_id.endswith(f":{chosen_suffix}")
            )
        )
    return tuple(selected)


def _seed_windows(
    path: tuple[GraphEdge, ...], limits: NativeSeedLimits
) -> Iterable[tuple[GraphEdge, ...]]:
    start = 0
    while start < len(path):
        end = start
        distance = 0.0
        while end < len(path):
            candidate = distance + path[end].length_m
            if candidate > limits.max_distance_m:
                break
            distance = candidate
            end += 1
            if distance >= limits.target_distance_m:
                break
        window = path[start:end]
        turn = total_turn_degrees(window)
        seed_distance = polyline_length_m(seed_points(window)) if window else 0.0
        density = turn / (seed_distance / 1_000.0) if seed_distance > 0.0 else 0.0
        if (
            limits.min_distance_m <= seed_distance <= limits.max_distance_m
            and len(window) <= limits.max_edges_per_seed
            and turn >= limits.min_total_turn_degrees
            and density >= limits.min_turn_degrees_per_km
        ):
            yield window
        start = max(end, start + 1)


def _native_seed(graph: HubGraph, edges: tuple[GraphEdge, ...]) -> NativeSeed:
    points = seed_points(edges)
    refs = tuple(
        sorted(
            {
                value.strip()
                for edge in edges
                for tag in edge.tags
                if tag.key == "ref"
                for value in tag.value.split(";")
                if value.strip()
            }
        )
    )
    return NativeSeed(
        seed_id=canonical_seed_id(graph, edges),
        hub_id=graph.hub_id,
        province_code=graph.province_code,
        source_pbf_checksum=graph.source_pbf_checksum,
        hub_pbf_checksum=graph.hub_pbf_checksum,
        source_license="ODbL-1.0",
        edge_ids=tuple(edge.edge_id for edge in edges),
        osm_way_ids=tuple(sorted({edge.osm_way_id for edge in edges})),
        points=points,
        road_refs=refs,
        distance_m=polyline_length_m(points),
        total_turn_degrees=total_turn_degrees(edges),
    )


def _bearing(edge: GraphEdge) -> float:
    start, end = edge.coordinates
    latitude_1 = math.radians(start.lat)
    latitude_2 = math.radians(end.lat)
    delta_lng = math.radians(end.lng - start.lng)
    y = math.sin(delta_lng) * math.cos(latitude_2)
    x = math.cos(latitude_1) * math.sin(latitude_2) - math.sin(latitude_1) * math.cos(
        latitude_2
    ) * math.cos(delta_lng)
    return math.degrees(math.atan2(y, x))
