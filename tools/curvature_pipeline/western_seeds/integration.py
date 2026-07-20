from __future__ import annotations

import math
from itertools import pairwise

from ..western_graph.model import Coordinate, GraphEdge, HubGraph
from ..western_routes.generator import generate_route
from ..western_routes.geometry import polyline_length_m
from ..western_routes.model import GeneratedRoute, SeedFragment, SeedSource
from .extractor import canonical_seed_id, seed_points, total_turn_degrees
from .model import (
    DEFAULT_NATIVE_SEED_LIMITS,
    NativeSeed,
    NativeSeedBatch,
    NativeSeedError,
    NativeSeedLimits,
    NativeSeedRejection,
    ResolvedNativeSeed,
)


def generate_native_route(
    graph: HubGraph,
    batch: NativeSeedBatch,
    *,
    limits: NativeSeedLimits = DEFAULT_NATIVE_SEED_LIMITS,
) -> GeneratedRoute:
    if not batch.seeds:
        raise NativeSeedError(
            NativeSeedRejection.NO_CURVATURE,
            "graph produced no reusable curvature seeds",
        )
    resolved = resolve_native_seed_batch(graph, batch, limits=limits)
    fragments: list[SeedFragment] = []
    for item in resolved:
        seed = item.seed
        fragments.append(
            SeedFragment(
                seed_id=seed.seed_id,
                points=seed.points,
                road_refs=seed.road_refs,
                source=SeedSource.OSM,
                source_license=seed.source_license,
            )
        )
    return generate_route(graph, tuple(fragments))


def resolve_native_seed_batch(
    graph: HubGraph,
    batch: NativeSeedBatch,
    *,
    limits: NativeSeedLimits = DEFAULT_NATIVE_SEED_LIMITS,
) -> tuple[ResolvedNativeSeed, ...]:
    edge_by_id = {edge.edge_id: edge for edge in graph.edges}
    return _resolve_native_seed_batch(graph, batch, edge_by_id, limits)


def resolve_native_seed_batches(
    graph: HubGraph,
    batches: tuple[NativeSeedBatch, ...],
    *,
    limits: NativeSeedLimits = DEFAULT_NATIVE_SEED_LIMITS,
) -> tuple[ResolvedNativeSeed, ...]:
    edge_by_id = {edge.edge_id: edge for edge in graph.edges}
    resolved = tuple(
        item
        for batch in batches
        for item in _resolve_native_seed_batch(graph, batch, edge_by_id, limits)
    )
    seed_ids = tuple(item.seed.seed_id for item in resolved)
    if len(seed_ids) != len(set(seed_ids)):
        raise NativeSeedError(
            NativeSeedRejection.PROVENANCE,
            "native seed clusters contain a duplicate seed ID",
        )
    return resolved


def _resolve_native_seed_batch(
    graph: HubGraph,
    batch: NativeSeedBatch,
    edge_by_id: dict[str, GraphEdge],
    limits: NativeSeedLimits,
) -> tuple[ResolvedNativeSeed, ...]:
    _validate_batch_provenance(graph, batch, limits)
    resolved: list[ResolvedNativeSeed] = []
    for seed in batch.seeds:
        try:
            edges = tuple(edge_by_id[edge_id] for edge_id in seed.edge_ids)
        except KeyError as error:
            raise NativeSeedError(
                NativeSeedRejection.TOPOLOGY,
                "seed references an edge missing from its graph",
            ) from error
        _validate_seed_replay(seed, edges, limits)
        if (
            seed.hub_id != graph.hub_id
            or seed.province_code != graph.province_code
            or seed.source_pbf_checksum != graph.source_pbf_checksum
            or seed.hub_pbf_checksum != graph.hub_pbf_checksum
            or seed.source_license != "ODbL-1.0"
            or canonical_seed_id(graph, edges) != seed.seed_id
        ):
            raise NativeSeedError(
                NativeSeedRejection.PROVENANCE,
                "seed provenance is not bound to the graph",
            )
        resolved.append(ResolvedNativeSeed(seed=seed, edges=edges))
    return tuple(resolved)


def _validate_batch_provenance(
    graph: HubGraph,
    batch: NativeSeedBatch,
    limits: NativeSeedLimits,
) -> None:
    seed_ids = tuple(seed.seed_id for seed in batch.seeds)
    if len(seed_ids) > limits.max_seeds:
        raise NativeSeedError(
            NativeSeedRejection.RESOURCE_LIMIT,
            "seed batch exceeds its fixed output budget",
        )
    if (
        batch.hub_id != graph.hub_id
        or batch.province_code != graph.province_code
        or batch.source_pbf_checksum != graph.source_pbf_checksum
        or batch.hub_pbf_checksum != graph.hub_pbf_checksum
        or batch.generator_version != "western-osm-seed-v1"
        or batch.schema_version != 1
        or seed_ids != tuple(sorted(seed_ids))
        or len(seed_ids) != len(set(seed_ids))
    ):
        raise NativeSeedError(
            NativeSeedRejection.PROVENANCE,
            "seed batch provenance is not bound to the graph",
        )


def _validate_seed_replay(
    seed: NativeSeed,
    edges: tuple[GraphEdge, ...],
    limits: NativeSeedLimits,
) -> None:
    if not edges or any(
        current.to_node_id != following.from_node_id
        for current, following in pairwise(edges)
    ):
        raise NativeSeedError(
            NativeSeedRejection.TOPOLOGY,
            f"seed {seed.seed_id} is not a contiguous graph path",
        )
    expected_points: tuple[Coordinate, ...] = seed_points(edges)
    expected_way_ids = tuple(sorted({edge.osm_way_id for edge in edges}))
    expected_refs = tuple(
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
    if seed.points != expected_points:
        raise NativeSeedError(
            NativeSeedRejection.TOPOLOGY,
            f"seed {seed.seed_id} geometry differs from graph replay",
        )
    if (
        len(seed.edge_ids) != len(set(seed.edge_ids))
        or seed.osm_way_ids != expected_way_ids
        or seed.road_refs != expected_refs
    ):
        raise NativeSeedError(
            NativeSeedRejection.PROVENANCE,
            f"seed {seed.seed_id} metadata differs from graph replay",
        )
    distance = polyline_length_m(expected_points)
    turn = total_turn_degrees(edges)
    if (
        not math.isfinite(distance)
        or not math.isfinite(turn)
        or not math.isclose(seed.distance_m, distance, rel_tol=0.0, abs_tol=1e-9)
        or not math.isclose(
            seed.total_turn_degrees,
            turn,
            rel_tol=0.0,
            abs_tol=1e-9,
        )
    ):
        raise NativeSeedError(
            NativeSeedRejection.TOPOLOGY,
            f"seed {seed.seed_id} metrics differ from graph replay",
        )
    turn_density = turn / (distance / 1_000.0) if distance > 0.0 else 0.0
    if (
        not limits.min_distance_m <= distance <= limits.max_distance_m
        or len(edges) > limits.max_edges_per_seed
        or turn < limits.min_total_turn_degrees
        or turn_density < limits.min_turn_degrees_per_km
    ):
        raise NativeSeedError(
            NativeSeedRejection.NO_CURVATURE,
            f"seed {seed.seed_id} does not satisfy native curvature limits",
        )
