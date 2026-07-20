from __future__ import annotations

import math

from .model import RouteCandidate, TileRequest

TILE_SIZE_DEG = 0.15


def tile_requests_for_route(
    route: RouteCandidate,
    version: str,
) -> tuple[TileRequest, ...]:
    min_lat = min(node.lat for node in route.nodes)
    max_lat = max(node.lat for node in route.nodes)
    min_lng = min(node.lng for node in route.nodes)
    max_lng = max(node.lng for node in route.nodes)
    min_lat_index = math.floor(min_lat / TILE_SIZE_DEG)
    max_lat_index = math.floor(max_lat / TILE_SIZE_DEG)
    min_lng_index = math.floor(min_lng / TILE_SIZE_DEG)
    max_lng_index = math.floor(max_lng / TILE_SIZE_DEG)
    return tuple(
        TileRequest(
            lat_index=lat_index,
            lng_index=lng_index,
            tile_size_deg=TILE_SIZE_DEG,
            version=version,
        )
        for lat_index in range(min_lat_index, max_lat_index + 1)
        for lng_index in range(min_lng_index, max_lng_index + 1)
    )
