from __future__ import annotations

from dataclasses import dataclass

from ..western_graph.model import GraphEdge, HubGraph
from .model import GenerationLimits, RouteGenerationError, RouteRejection, SeedFragment
from .pathing import path_distance_m, shortest_edge_path, weakly_connected


@dataclass(frozen=True, slots=True)
class SeedPath:
    seed: SeedFragment
    edges: tuple[GraphEdge, ...]

    @property
    def start_node_id(self) -> int:
        return self.edges[0].from_node_id

    @property
    def end_node_id(self) -> int:
        return self.edges[-1].to_node_id


def assemble_seed_cluster(
    graph: HubGraph,
    options: tuple[tuple[SeedPath, ...], ...],
    limits: GenerationLimits,
) -> tuple[tuple[GraphEdge, ...], frozenset[int]]:
    complete: list[tuple[GraphEdge, ...]] = []
    for first_index, first_options in enumerate(options):
        for first in first_options:
            candidate = _greedy_candidate(graph, options, first_index, first, limits)
            if candidate is not None:
                complete.append(candidate)
    if not complete:
        _raise_cluster_failure(graph, options, limits)
    edges = min(complete, key=_candidate_key)
    included_ids = {edge.edge_id for edge in edges}
    mandatory = frozenset(
        node_id
        for paths in options
        for path in paths
        if all(edge.edge_id in included_ids for edge in path.edges)
        for node_id in (path.start_node_id, path.end_node_id)
    )
    return edges, mandatory


def _greedy_candidate(
    graph: HubGraph,
    options: tuple[tuple[SeedPath, ...], ...],
    first_index: int,
    first: SeedPath,
    limits: GenerationLimits,
) -> tuple[GraphEdge, ...] | None:
    used = {first_index}
    edges = list(first.edges)
    previous = first
    while len(used) < len(options):
        choices: list[
            tuple[float, tuple[str, ...], int, SeedPath, tuple[GraphEdge, ...]]
        ] = []
        used_edge_ids = {edge.edge_id for edge in edges}
        for index, paths in enumerate(options):
            if index in used:
                continue
            for path in paths:
                connector = shortest_edge_path(
                    graph, previous.end_node_id, path.start_node_id
                )
                if connector is None:
                    continue
                connector_distance = path_distance_m(connector)
                if connector_distance > limits.max_seed_connector_m:
                    continue
                candidate_edges = (*connector, *path.edges)
                if used_edge_ids.intersection(edge.edge_id for edge in candidate_edges):
                    continue
                choices.append(
                    (
                        connector_distance,
                        tuple(edge.edge_id for edge in candidate_edges),
                        index,
                        path,
                        connector,
                    )
                )
        if not choices:
            return None
        _, _, index, path, connector = min(choices)
        edges.extend(connector)
        edges.extend(path.edges)
        used.add(index)
        previous = path
    return tuple(edges)


def _raise_cluster_failure(
    graph: HubGraph,
    options: tuple[tuple[SeedPath, ...], ...],
    limits: GenerationLimits,
) -> None:
    paths = tuple(path for choices in options for path in choices)
    pairs = tuple(
        (first, second)
        for first in paths
        for second in paths
        if first.seed.seed_id != second.seed.seed_id
    )
    legal_paths = tuple(
        path
        for first, second in pairs
        if (path := shortest_edge_path(graph, first.end_node_id, second.start_node_id))
        is not None
    )
    if legal_paths and all(
        path_distance_m(path) > limits.max_seed_connector_m for path in legal_paths
    ):
        raise RouteGenerationError(
            RouteRejection.SEEDS_TOO_FAR, "seed connector exceeds 12 km"
        )
    if any(
        not weakly_connected(graph, first.end_node_id, second.start_node_id)
        for first, second in pairs
    ):
        raise RouteGenerationError(
            RouteRejection.DISCONNECTED, "seed clusters are disconnected"
        )
    if any(
        {edge.edge_id for edge in first.edges}.intersection(
            edge.edge_id for edge in second.edges
        )
        for first, second in pairs
    ):
        raise RouteGenerationError(
            RouteRejection.REPEATED_EDGE,
            "seed paths would repeat a directed graph edge",
        )
    raise RouteGenerationError(
        RouteRejection.ILLEGAL_DIRECTION,
        "seed clusters cannot be stitched without illegal or repeated edges",
    )


def _candidate_key(
    edges: tuple[GraphEdge, ...],
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    physical = tuple(
        f"{edge.osm_way_id}:{edge.segment_index}:{min(edge.from_node_id, edge.to_node_id)}:{max(edge.from_node_id, edge.to_node_id)}"
        for edge in edges
    )
    return (
        min(physical, tuple(reversed(physical))),
        tuple(edge.edge_id for edge in edges),
    )
