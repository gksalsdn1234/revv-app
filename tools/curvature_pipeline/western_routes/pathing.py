from __future__ import annotations

import heapq
from dataclasses import dataclass

from ..western_graph.model import Coordinate, GraphEdge, HubGraph
from .geometry import distance_m, point_segment_distance_m
from .model import GenerationLimits, RouteGenerationError, RouteRejection


@dataclass(frozen=True, slots=True)
class SnappedPoint:
    node_id: int
    physical_edge: tuple[int, int]


def snap_point(
    graph: HubGraph, point: Coordinate, limits: GenerationLimits
) -> SnappedPoint:
    physical: dict[tuple[int, int], GraphEdge] = {}
    for edge in graph.edges:
        physical.setdefault((edge.osm_way_id, edge.segment_index), edge)
    ranked = sorted(
        (
            (
                point_segment_distance_m(
                    point, edge.coordinates[0], edge.coordinates[1]
                ),
                key,
                edge,
            )
            for key, edge in physical.items()
        ),
        key=lambda item: (item[0], item[1]),
    )
    if not ranked or ranked[0][0] > limits.snap_distance_m:
        raise RouteGenerationError(
            RouteRejection.SNAP_MISS, "no graph edge within 100 m"
        )
    if len(ranked) > 1 and ranked[1][0] - ranked[0][0] <= limits.snap_ambiguity_m:
        raise RouteGenerationError(
            RouteRejection.SNAP_AMBIGUOUS,
            "multiple physical edges are equally plausible",
        )
    _, key, edge = ranked[0]
    from_distance = distance_m(point, edge.coordinates[0])
    to_distance = distance_m(point, edge.coordinates[1])
    node_id = min(edge.from_node_id, edge.to_node_id)
    if from_distance < to_distance:
        node_id = edge.from_node_id
    elif to_distance < from_distance:
        node_id = edge.to_node_id
    return SnappedPoint(node_id=node_id, physical_edge=key)


def shortest_edge_path(
    graph: HubGraph, start_node_id: int, end_node_id: int
) -> tuple[GraphEdge, ...] | None:
    if start_node_id == end_node_id:
        return ()
    adjacency: dict[int, list[GraphEdge]] = {}
    for edge in graph.edges:
        adjacency.setdefault(edge.from_node_id, []).append(edge)
    queue: list[tuple[float, int]] = [(0.0, start_node_id)]
    best: dict[int, float] = {start_node_id: 0.0}
    parent: dict[int, GraphEdge] = {}
    while queue:
        cost, node_id = heapq.heappop(queue)
        if cost != best.get(node_id):
            continue
        if node_id == end_node_id:
            return _reconstruct(parent, start_node_id, end_node_id)
        for edge in sorted(adjacency.get(node_id, ()), key=lambda item: item.edge_id):
            candidate = cost + edge.length_m
            previous = best.get(edge.to_node_id)
            if previous is None or candidate < previous - 1e-9:
                best[edge.to_node_id] = candidate
                parent[edge.to_node_id] = edge
                heapq.heappush(queue, (candidate, edge.to_node_id))
    return None


def weakly_connected(graph: HubGraph, start_node_id: int, end_node_id: int) -> bool:
    pending = [start_node_id]
    seen = {start_node_id}
    adjacency: dict[int, set[int]] = {}
    for edge in graph.edges:
        adjacency.setdefault(edge.from_node_id, set()).add(edge.to_node_id)
        adjacency.setdefault(edge.to_node_id, set()).add(edge.from_node_id)
    while pending:
        node_id = pending.pop()
        if node_id == end_node_id:
            return True
        for neighbor in adjacency.get(node_id, set()) - seen:
            seen.add(neighbor)
            pending.append(neighbor)
    return False


def path_distance_m(edges: tuple[GraphEdge, ...]) -> float:
    return sum(edge.length_m for edge in edges)


def _reconstruct(
    parent: dict[int, GraphEdge], start_node_id: int, end_node_id: int
) -> tuple[GraphEdge, ...]:
    reversed_edges: list[GraphEdge] = []
    node_id = end_node_id
    while node_id != start_node_id:
        edge = parent[node_id]
        reversed_edges.append(edge)
        node_id = edge.from_node_id
    return tuple(reversed(reversed_edges))
