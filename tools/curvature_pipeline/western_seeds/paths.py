from __future__ import annotations

from collections import defaultdict
from typing import final

from ..western_graph.model import GraphEdge


def road_paths(edges: tuple[GraphEdge, ...]) -> tuple[tuple[GraphEdge, ...], ...]:
    groups: dict[str, list[GraphEdge]] = defaultdict(list)
    for edge in edges:
        groups[_road_key(edge)].append(edge)
    paths: list[tuple[GraphEdge, ...]] = []
    for road_key in sorted(groups):
        paths.extend(_decompose(tuple(groups[road_key])))
    return tuple(paths)


def _road_key(edge: GraphEdge) -> str:
    tags = {tag.key: tag.value.strip() for tag in edge.tags}
    road_ref = tags.get("ref", "")
    if road_ref:
        return f"ref:{road_ref}"
    name = tags.get("name", "")
    if name:
        return f"name:{name}"
    return f"way:{edge.osm_way_id}"


def _decompose(edges: tuple[GraphEdge, ...]) -> tuple[tuple[GraphEdge, ...], ...]:
    outgoing: dict[int, list[GraphEdge]] = defaultdict(list)
    incoming: dict[int, int] = defaultdict(int)
    for edge in edges:
        outgoing[edge.from_node_id].append(edge)
        incoming[edge.to_node_id] += 1
    for values in outgoing.values():
        values.sort(key=lambda edge: edge.edge_id)
    starts = tuple(
        edge
        for edge in sorted(edges, key=lambda item: item.edge_id)
        if incoming[edge.from_node_id] != 1 or len(outgoing[edge.from_node_id]) != 1
    )
    walker = _PathWalker(outgoing, incoming)
    paths = [walker.walk(start) for start in starts]
    paths.extend(
        walker.walk(edge)
        for edge in sorted(edges, key=lambda item: item.edge_id)
        if walker.is_pending(edge)
    )
    return tuple(path for path in paths if path)


@final
class _PathWalker:
    """Own the mutable visited set while decomposing one road group."""

    def __init__(
        self,
        outgoing: dict[int, list[GraphEdge]],
        incoming: dict[int, int],
    ) -> None:
        self._outgoing: dict[int, list[GraphEdge]] = outgoing
        self._incoming: dict[int, int] = incoming
        self._visited: set[str] = set()

    def is_pending(self, edge: GraphEdge) -> bool:
        return edge.edge_id not in self._visited

    def walk(self, start: GraphEdge) -> tuple[GraphEdge, ...]:
        path: list[GraphEdge] = []
        current = start
        while current.edge_id not in self._visited:
            self._visited.add(current.edge_id)
            path.append(current)
            following = tuple(
                edge
                for edge in self._outgoing[current.to_node_id]
                if edge.edge_id not in self._visited
            )
            if self._incoming[current.to_node_id] != 1 or len(following) != 1:
                break
            current = following[0]
        return tuple(path)
