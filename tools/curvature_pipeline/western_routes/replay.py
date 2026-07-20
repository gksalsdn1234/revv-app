from __future__ import annotations

from itertools import pairwise

from ..western_graph.model import HubGraph
from .model import GeneratedRoute


def route_replays_on_graph(graph: HubGraph, route: GeneratedRoute) -> bool:
    if (
        route.hub_id != graph.hub_id
        or route.province_code != graph.province_code
        or route.source_pbf_checksum != graph.source_pbf_checksum
        or route.hub_pbf_checksum != graph.hub_pbf_checksum
    ):
        return False
    edge_by_id = {edge.edge_id: edge for edge in graph.edges}
    try:
        edges = tuple(edge_by_id[edge_id] for edge_id in route.edge_ids)
    except KeyError:
        return False
    if not edges or len(edges) != len(set(route.edge_ids)):
        return False
    if any(
        current.to_node_id != following.from_node_id
        for current, following in pairwise(edges)
    ):
        return False
    if len(route.replay_spans) + 1 != len(route.geometry):
        return False
    expected_first = 0
    for index, span in enumerate(route.replay_spans):
        if (
            span.first_edge_index != expected_first
            or span.last_edge_index < span.first_edge_index
            or span.last_edge_index >= len(edges)
        ):
            return False
        first_edge = edges[span.first_edge_index]
        last_edge = edges[span.last_edge_index]
        if (
            route.geometry[index] != first_edge.coordinates[0]
            or route.geometry[index + 1] != last_edge.coordinates[1]
        ):
            return False
        expected_first = span.last_edge_index + 1
    return expected_first == len(edges)
