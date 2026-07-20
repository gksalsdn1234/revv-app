from __future__ import annotations

import math
from typing import Final

from ..western_graph.model import Coordinate, GraphEdge, HubGraph
from ..western_routes.geometry import distance_m
from ..western_routes.model import GeneratedRoute
from ..western_selection.model import PolicyEvidence, QualityCandidate

_GEOHASH_BASE32: Final = "0123456789bcdefghjkmnpqrstuvwxyz"
_CURVE_THRESHOLD_DEG: Final = 20.0
_RESIDENTIAL_HIGHWAY_VALUES: Final = frozenset({"residential", "service"})


def geohash4(lat: float, lng: float) -> str:
    """Standard public-domain geohash encoding, truncated to 4 base32 characters.

    Used only to bucket route centroids into the geohash4 diversity cells that
    ``western_selection`` already requires on ``QualityCandidate.geohash4`` -
    this function only supplies that input, it does not reimplement any
    selection/quota logic.
    """
    lat_range = [-90.0, 90.0]
    lng_range = [-180.0, 180.0]
    bits: list[int] = []
    even = True
    while len(bits) < 20:
        if even:
            mid = (lng_range[0] + lng_range[1]) / 2.0
            if lng >= mid:
                bits.append(1)
                lng_range[0] = mid
            else:
                bits.append(0)
                lng_range[1] = mid
        else:
            mid = (lat_range[0] + lat_range[1]) / 2.0
            if lat >= mid:
                bits.append(1)
                lat_range[0] = mid
            else:
                bits.append(0)
                lat_range[1] = mid
        even = not even
    chars: list[str] = []
    for chunk_index in range(4):
        chunk = bits[chunk_index * 5 : chunk_index * 5 + 5]
        value = 0
        for bit in chunk:
            value = (value << 1) | bit
        chars.append(_GEOHASH_BASE32[value])
    return "".join(chars)


def _bearing_deg(start: Coordinate, end: Coordinate) -> float:
    lat1 = math.radians(start.lat)
    lat2 = math.radians(end.lat)
    delta_lng = math.radians(end.lng - start.lng)
    x = math.sin(delta_lng) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(
        delta_lng
    )
    return math.degrees(math.atan2(x, y)) % 360.0


def _angle_delta(first: float, second: float) -> float:
    delta = abs(first - second) % 360.0
    return delta if delta <= 180.0 else 360.0 - delta


def _curvature_metrics(geometry: tuple[Coordinate, ...]) -> tuple[float, float]:
    """Return ``(curved_distance_m, max_straight_run_m)`` from a polyline.

    A segment counts as curved when its bearing differs from the previous
    segment's bearing by at least the plan's 20-degree curve-extrema
    tolerance (the same tolerance the Todo 6 simplifier is required to
    preserve), so this heuristic stays consistent with what generation
    already guarantees survives simplification.
    """
    if len(geometry) < 3:
        return 0.0, 0.0
    bearings = tuple(
        _bearing_deg(start, end) for start, end in zip(geometry, geometry[1:])
    )
    curved_distance_m = 0.0
    straight_run_m = 0.0
    max_straight_run_m = 0.0
    for index in range(1, len(bearings)):
        segment_length_m = distance_m(geometry[index], geometry[index + 1])
        delta = _angle_delta(bearings[index], bearings[index - 1])
        if delta >= _CURVE_THRESHOLD_DEG:
            curved_distance_m += segment_length_m
            straight_run_m = 0.0
        else:
            straight_run_m += segment_length_m
            max_straight_run_m = max(max_straight_run_m, straight_run_m)
    return curved_distance_m, max_straight_run_m


def _residential_ratio(edges: tuple[GraphEdge, ...]) -> float:
    total_m = sum(edge.length_m for edge in edges)
    if total_m <= 0.0:
        return 0.0
    residential_m = sum(
        edge.length_m
        for edge in edges
        if any(
            tag.key == "highway" and tag.value in _RESIDENTIAL_HIGHWAY_VALUES
            for tag in edge.tags
        )
    )
    return residential_m / total_m


def edges_for_route(graph: HubGraph, route: GeneratedRoute) -> tuple[GraphEdge, ...]:
    by_id = {edge.edge_id: edge for edge in graph.edges}
    return tuple(by_id[edge_id] for edge_id in route.edge_ids)


def quality_candidate_from_route(
    route: GeneratedRoute, edges: tuple[GraphEdge, ...]
) -> QualityCandidate:
    """Build the Todo 7 quality-gate input for one generated route.

    ``edges`` must be the exact ordered graph edges the route replayed on
    (``GeneratedRoute.edge_ids`` order), so this only *measures* signals from
    real graph provenance - it does not decide acceptance, that is still
    ``western_selection.quality.quality_rejection``'s job.
    """
    edge_lengths_m = tuple(edge.length_m for edge in edges)
    curved_distance_m, max_straight_run_m = _curvature_metrics(route.geometry)
    centroid_lat = sum(point.lat for point in route.geometry) / len(route.geometry)
    centroid_lng = sum(point.lng for point in route.geometry) / len(route.geometry)
    return QualityCandidate(
        route=route,
        edge_lengths_m=edge_lengths_m,
        curved_distance_m=curved_distance_m,
        max_straight_run_m=max_straight_run_m,
        residential_service_exposure_ratio=_residential_ratio(edges),
        access_evidence=PolicyEvidence.ALLOWED,
        surface_evidence=PolicyEvidence.ALLOWED,
        geohash4=geohash4(centroid_lat, centroid_lng),
    )
