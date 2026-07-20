from __future__ import annotations

from collections import deque

from .model import HubGraph


def shortest_node_path(
    graph: HubGraph,
    start_node_id: int,
    end_node_id: int,
) -> tuple[int, ...] | None:
    if start_node_id == end_node_id:
        return (
            (start_node_id,)
            if any(node.osm_node_id == start_node_id for node in graph.nodes)
            else None
        )
    adjacency: dict[int, list[int]] = {}
    for edge in graph.edges:
        adjacency.setdefault(edge.from_node_id, []).append(edge.to_node_id)
    queue = deque((start_node_id,))
    parent: dict[int, int | None] = {start_node_id: None}
    while queue:
        node_id = queue.popleft()
        for neighbor in sorted(adjacency.get(node_id, ())):
            if neighbor in parent:
                continue
            parent[neighbor] = node_id
            if neighbor == end_node_id:
                return _reconstruct(parent, end_node_id)
            queue.append(neighbor)
    return None


def weak_components(graph: HubGraph) -> tuple[tuple[int, ...], ...]:
    adjacency: dict[int, set[int]] = {node.osm_node_id: set() for node in graph.nodes}
    for edge in graph.edges:
        adjacency[edge.from_node_id].add(edge.to_node_id)
        adjacency[edge.to_node_id].add(edge.from_node_id)
    unseen = set(adjacency)
    components: list[tuple[int, ...]] = []
    while unseen:
        start = min(unseen)
        pending = [start]
        unseen.remove(start)
        component: list[int] = []
        while pending:
            node_id = pending.pop()
            component.append(node_id)
            for neighbor in sorted(adjacency[node_id], reverse=True):
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    pending.append(neighbor)
        components.append(tuple(sorted(component)))
    return tuple(sorted(components))


def _reconstruct(parent: dict[int, int | None], end_node_id: int) -> tuple[int, ...]:
    reversed_path: list[int] = []
    node_id: int | None = end_node_id
    while node_id is not None:
        reversed_path.append(node_id)
        node_id = parent[node_id]
    return tuple(reversed(reversed_path))
