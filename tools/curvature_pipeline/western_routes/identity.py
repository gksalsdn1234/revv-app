from __future__ import annotations

import hashlib
import json

from ..western_graph.model import GraphEdge


def canonical_route_id(edges: tuple[GraphEdge, ...]) -> str:
    forward = _edge_tokens(edges)
    reverse = tuple(reversed(forward))
    canonical = min(forward, reverse)
    digest = hashlib.sha256(
        json.dumps(canonical, separators=(",", ":")).encode()
    ).hexdigest()
    return f"osmgen:v1:{digest}"


def _edge_tokens(edges: tuple[GraphEdge, ...]) -> tuple[str, ...]:
    return tuple(
        f"{edge.osm_way_id}:{edge.segment_index}:{min(edge.from_node_id, edge.to_node_id)}:{max(edge.from_node_id, edge.to_node_id)}"
        for edge in edges
    )
