from __future__ import annotations

from itertools import pairwise
from typing import Final

from ..western_graph.model import GraphEdge, HubGraph
from .cluster import SeedPath, assemble_seed_cluster
from .codec import route_bytes
from .geometry import distance_m, polyline_length_m
from .identity import canonical_route_id
from .model import (
    GeneratedRoute,
    GenerationLimits,
    RouteGenerationError,
    RouteRejection,
    SeedFragment,
    SeedSource,
)
from .pathing import (
    path_distance_m,
    shortest_edge_path,
    snap_point,
    weakly_connected,
)
from .replay import route_replays_on_graph
from .simplify import simplify_graph_path
from .validation import validate_loop_return

GENERATOR_VERSION: Final = "western-route-v1"
DEFAULT_GENERATION_LIMITS: Final = GenerationLimits()


def generate_route(
    graph: HubGraph,
    seeds: tuple[SeedFragment, ...],
    *,
    limits: GenerationLimits = DEFAULT_GENERATION_LIMITS,
) -> GeneratedRoute:
    if not seeds:
        raise RouteGenerationError(RouteRejection.TOO_SHORT, "no seed fragments")
    seed_options = tuple(_build_seed_options(graph, seed, limits) for seed in seeds)
    edges, mandatory_nodes = assemble_seed_cluster(graph, seed_options, limits)
    return generate_route_from_edges(
        graph,
        seeds,
        edges,
        mandatory_nodes,
        limits=limits,
    )


def generate_route_from_edges(
    graph: HubGraph,
    seeds: tuple[SeedFragment, ...],
    edges: tuple[GraphEdge, ...],
    mandatory_nodes: frozenset[int],
    *,
    limits: GenerationLimits = DEFAULT_GENERATION_LIMITS,
) -> GeneratedRoute:
    if not seeds:
        raise RouteGenerationError(RouteRejection.TOO_SHORT, "no seed fragments")
    for seed in seeds:
        _validate_seed_fragment(seed, limits)
    _validate_edge_replay(edges)
    distance = path_distance_m(edges)
    if distance < limits.min_route_distance_m:
        raise RouteGenerationError(RouteRejection.TOO_SHORT, "route is below 15 km")
    if distance > limits.max_route_distance_m:
        raise RouteGenerationError(RouteRejection.TOO_LONG, "route exceeds 80 km")
    node_ids = (edges[0].from_node_id, *(edge.to_node_id for edge in edges))
    coordinates = (edges[0].coordinates[0], *(edge.coordinates[1] for edge in edges))
    is_loop = (
        distance_m(coordinates[0], coordinates[-1]) <= limits.loop_close_distance_m
    )
    validate_loop_return(edges, is_loop=is_loop, limits=limits)
    simplified = simplify_graph_path(graph, node_ids, mandatory_nodes, distance, limits)
    route = GeneratedRoute(
        route_id=canonical_route_id(edges),
        generator_version=GENERATOR_VERSION,
        hub_id=graph.hub_id,
        province_code=graph.province_code,
        source_pbf_checksum=graph.source_pbf_checksum,
        hub_pbf_checksum=graph.hub_pbf_checksum,
        seed_ids=tuple(sorted(seed.seed_id for seed in seeds)),
        edge_ids=tuple(edge.edge_id for edge in edges),
        geometry=simplified.geometry,
        replay_spans=simplified.replay_spans,
        distance_m=distance,
        hausdorff_error_m=simplified.hausdorff_error_m,
        length_error_ratio=simplified.length_error_ratio,
        is_loop=is_loop,
    )
    if not route_replays_on_graph(graph, route):
        raise RouteGenerationError(
            RouteRejection.TOPOLOGY_REPLAY, "stored route cannot replay on its graph"
        )
    if len(route_bytes(route)) > limits.max_payload_bytes:
        raise RouteGenerationError(
            RouteRejection.PAYLOAD_LIMIT, "canonical route payload exceeds 512 KiB"
        )
    return route


def _build_seed_options(
    graph: HubGraph, seed: SeedFragment, limits: GenerationLimits
) -> tuple[SeedPath, ...]:
    _validate_seed_fragment(seed, limits)
    first = snap_point(graph, seed.points[0], limits)
    last = snap_point(graph, seed.points[-1], limits)
    if first.node_id == last.node_id:
        same_edge = tuple(
            edge
            for edge in graph.edges
            if (edge.osm_way_id, edge.segment_index) == first.physical_edge
        )
        matching_same_edge = tuple(
            edge for edge in same_edge if _path_matches_refs((edge,), seed.road_refs)
        )
        if matching_same_edge:
            return tuple(
                SeedPath(seed=seed, edges=(edge,))
                for edge in sorted(matching_same_edge, key=lambda item: item.edge_id)
            )
    forward = shortest_edge_path(graph, first.node_id, last.node_id)
    reverse = shortest_edge_path(graph, last.node_id, first.node_id)
    candidates = tuple(path for path in (forward, reverse) if path)
    if not candidates:
        reason = (
            RouteRejection.ILLEGAL_DIRECTION
            if weakly_connected(graph, first.node_id, last.node_id)
            else RouteRejection.DISCONNECTED
        )
        raise RouteGenerationError(
            reason, f"seed {seed.seed_id} has no legal graph path"
        )
    matching = tuple(
        path for path in candidates if _path_matches_refs(path, seed.road_refs)
    )
    if not matching:
        raise RouteGenerationError(
            RouteRejection.REF_MISMATCH,
            f"seed {seed.seed_id} refs do not match its snapped graph path",
        )
    unique = {tuple(edge.edge_id for edge in path): path for path in matching}
    return tuple(SeedPath(seed=seed, edges=unique[key]) for key in sorted(unique))


def _validate_seed_fragment(seed: SeedFragment, limits: GenerationLimits) -> None:
    if seed.source is not SeedSource.OSM or seed.source_license != "ODbL-1.0":
        raise RouteGenerationError(
            RouteRejection.UNLICENSED_SEED, f"seed {seed.seed_id} is not reusable"
        )
    if len(seed.points) < 2:
        raise RouteGenerationError(
            RouteRejection.SEED_DISTANCE, "seed has fewer than two points"
        )
    seed_distance = polyline_length_m(seed.points)
    if not limits.min_seed_distance_m <= seed_distance <= limits.max_seed_distance_m:
        raise RouteGenerationError(
            RouteRejection.SEED_DISTANCE, f"seed {seed.seed_id} is outside 0.3-4 km"
        )


def _path_matches_refs(
    edges: tuple[GraphEdge, ...], road_refs: tuple[str, ...]
) -> bool:
    if not road_refs:
        return True
    path_refs = {
        value.strip()
        for edge in edges
        for tag in edge.tags
        if tag.key == "ref"
        for value in tag.value.split(";")
        if value.strip()
    }
    return not path_refs.isdisjoint(road_refs)


def _validate_edge_replay(edges: tuple[GraphEdge, ...]) -> None:
    edge_ids = tuple(edge.edge_id for edge in edges)
    if len(edge_ids) != len(set(edge_ids)):
        raise RouteGenerationError(
            RouteRejection.REPEATED_EDGE, "route repeats a directed graph edge"
        )
    if any(
        current.to_node_id != following.from_node_id
        for current, following in pairwise(edges)
    ):
        raise RouteGenerationError(
            RouteRejection.TOPOLOGY_REPLAY, "route contains a graph jump"
        )
