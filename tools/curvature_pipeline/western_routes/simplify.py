from __future__ import annotations

from dataclasses import dataclass
from itertools import pairwise

from ..western_graph.model import Coordinate, HubGraph
from .geometry import (
    max_distance_to_polyline_m,
    point_segment_distance_m,
    polyline_length_m,
    turn_degrees,
)
from .model import GenerationLimits, ReplaySpan, RouteGenerationError, RouteRejection


@dataclass(frozen=True, slots=True)
class SimplifiedPath:
    geometry: tuple[Coordinate, ...]
    replay_spans: tuple[ReplaySpan, ...]
    hausdorff_error_m: float
    length_error_ratio: float


def simplify_graph_path(
    graph: HubGraph,
    node_ids: tuple[int, ...],
    mandatory_node_ids: frozenset[int],
    full_distance_m: float,
    limits: GenerationLimits,
) -> SimplifiedPath:
    coordinates_by_id = {node.osm_node_id: node.coordinate for node in graph.nodes}
    try:
        points = tuple(coordinates_by_id[node_id] for node_id in node_ids)
    except KeyError as error:
        raise RouteGenerationError(
            RouteRejection.TOPOLOGY_REPLAY, "route references an unknown graph node"
        ) from error
    mandatory = _mandatory_indices(graph, node_ids, points, mandatory_node_ids)
    tolerances = (12.0, 15.0, 18.0, 21.0, 25.0)
    selected: tuple[int, ...] = ()
    for tolerance in tolerances:
        if tolerance < limits.initial_simplification_m:
            continue
        if tolerance > limits.max_simplification_m:
            break
        selected = _rdp_with_mandatory(points, mandatory, tolerance)
        if len(selected) <= limits.max_geometry_nodes:
            break
    if len(selected) > limits.max_geometry_nodes or not selected:
        raise RouteGenerationError(
            RouteRejection.NODE_LIMIT,
            f"simplification retained {len(selected)} nodes",
        )
    geometry = tuple(points[index] for index in selected)
    hausdorff = max_distance_to_polyline_m(points, geometry)
    if hausdorff > limits.max_hausdorff_m + 1e-6:
        raise RouteGenerationError(
            RouteRejection.HAUSDORFF_LIMIT, f"Hausdorff error is {hausdorff:.3f} m"
        )
    simplified_length = polyline_length_m(geometry)
    length_error = abs(simplified_length - full_distance_m) / full_distance_m
    if length_error > limits.max_length_error_ratio + 1e-9:
        raise RouteGenerationError(
            RouteRejection.LENGTH_ERROR,
            f"length error ratio is {length_error:.8f}",
        )
    spans = tuple(
        ReplaySpan(first_edge_index=start, last_edge_index=end - 1)
        for start, end in pairwise(selected)
    )
    if (
        not spans
        or spans[0].first_edge_index != 0
        or spans[-1].last_edge_index != len(node_ids) - 2
    ):
        raise RouteGenerationError(
            RouteRejection.TOPOLOGY_REPLAY, "simplified spans do not cover the route"
        )
    return SimplifiedPath(
        geometry=geometry,
        replay_spans=spans,
        hausdorff_error_m=hausdorff,
        length_error_ratio=length_error,
    )


def _mandatory_indices(
    graph: HubGraph,
    node_ids: tuple[int, ...],
    points: tuple[Coordinate, ...],
    mandatory_node_ids: frozenset[int],
) -> frozenset[int]:
    neighbors: dict[int, set[int]] = {}
    for edge in graph.edges:
        neighbors.setdefault(edge.from_node_id, set()).add(edge.to_node_id)
        neighbors.setdefault(edge.to_node_id, set()).add(edge.from_node_id)
    indices = {0, len(node_ids) - 1}
    indices.update(
        index
        for index, node_id in enumerate(node_ids)
        if node_id in mandatory_node_ids or len(neighbors.get(node_id, ())) > 2
    )
    indices.update(
        index
        for index in range(1, len(points) - 1)
        if turn_degrees(points[index - 1], points[index], points[index + 1]) >= 20.0
    )
    return frozenset(indices)


def _rdp_with_mandatory(
    points: tuple[Coordinate, ...], mandatory: frozenset[int], tolerance_m: float
) -> tuple[int, ...]:
    selected = set(mandatory)
    boundaries = sorted(mandatory)
    pending = list(pairwise(boundaries))
    while pending:
        start, end = pending.pop()
        if end <= start + 1:
            continue
        farthest_index = start
        farthest_distance = -1.0
        for index in range(start + 1, end):
            distance = point_segment_distance_m(
                points[index], points[start], points[end]
            )
            if distance > farthest_distance:
                farthest_distance = distance
                farthest_index = index
        if farthest_distance > tolerance_m:
            selected.add(farthest_index)
            pending.append((start, farthest_index))
            pending.append((farthest_index, end))
    return tuple(sorted(selected))
