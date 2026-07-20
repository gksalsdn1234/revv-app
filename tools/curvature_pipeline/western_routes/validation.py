from __future__ import annotations

from ..western_graph.model import GraphEdge
from .model import GenerationLimits, RouteGenerationError, RouteRejection


def validate_loop_return(
    edges: tuple[GraphEdge, ...], *, is_loop: bool, limits: GenerationLimits
) -> None:
    physical = tuple((edge.osm_way_id, edge.segment_index) for edge in edges)
    return_ratio = (len(physical) - len(set(physical))) / len(physical)
    if is_loop and return_ratio >= limits.max_loop_return_ratio:
        raise RouteGenerationError(
            RouteRejection.LOOP_RETURN_OVERLAP,
            "loop repeats at least 40% of physical edges in reverse",
        )
