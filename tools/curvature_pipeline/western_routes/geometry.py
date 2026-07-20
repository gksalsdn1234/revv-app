from __future__ import annotations

import math
from itertools import pairwise
from typing import Final

from ..western_graph.model import Coordinate

EARTH_RADIUS_M: Final = 6_371_008.8


def distance_m(start: Coordinate, end: Coordinate) -> float:
    lat1 = math.radians(start.lat)
    lat2 = math.radians(end.lat)
    delta_lat = lat2 - lat1
    delta_lng = math.radians(end.lng - start.lng)
    a = (
        math.sin(delta_lat / 2.0) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lng / 2.0) ** 2
    )
    return 2.0 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def polyline_length_m(points: tuple[Coordinate, ...]) -> float:
    return sum(distance_m(start, end) for start, end in pairwise(points))


def point_segment_distance_m(
    point: Coordinate, start: Coordinate, end: Coordinate
) -> float:
    reference_lat = math.radians(point.lat)
    scale_x = EARTH_RADIUS_M * math.cos(reference_lat) * math.pi / 180.0
    scale_y = EARTH_RADIUS_M * math.pi / 180.0
    start_x = (start.lng - point.lng) * scale_x
    start_y = (start.lat - point.lat) * scale_y
    end_x = (end.lng - point.lng) * scale_x
    end_y = (end.lat - point.lat) * scale_y
    delta_x = end_x - start_x
    delta_y = end_y - start_y
    denominator = delta_x * delta_x + delta_y * delta_y
    if denominator == 0.0:
        return math.hypot(start_x, start_y)
    ratio = max(
        0.0,
        min(1.0, -(start_x * delta_x + start_y * delta_y) / denominator),
    )
    return math.hypot(start_x + ratio * delta_x, start_y + ratio * delta_y)


def max_distance_to_polyline_m(
    points: tuple[Coordinate, ...], line: tuple[Coordinate, ...]
) -> float:
    return max(
        min(
            point_segment_distance_m(point, start, end) for start, end in pairwise(line)
        )
        for point in points
    )


def sample_polyline(
    points: tuple[Coordinate, ...], interval_m: float = 100.0
) -> tuple[Coordinate, ...]:
    if len(points) < 2:
        return points
    segment_lengths = tuple(distance_m(start, end) for start, end in pairwise(points))
    total = sum(segment_lengths)
    targets = [0.0]
    cursor = interval_m
    while cursor < total:
        targets.append(cursor)
        cursor += interval_m
    targets.append(total)
    samples: list[Coordinate] = []
    segment_index = 0
    segment_start_distance = 0.0
    for target in targets:
        while (
            segment_index < len(segment_lengths) - 1
            and target > segment_start_distance + segment_lengths[segment_index]
        ):
            segment_start_distance += segment_lengths[segment_index]
            segment_index += 1
        length = segment_lengths[segment_index]
        ratio = 0.0 if length == 0.0 else (target - segment_start_distance) / length
        start = points[segment_index]
        end = points[segment_index + 1]
        samples.append(
            Coordinate(
                lat=start.lat + (end.lat - start.lat) * ratio,
                lng=start.lng + (end.lng - start.lng) * ratio,
            )
        )
    return tuple(samples)


def turn_degrees(before: Coordinate, point: Coordinate, after: Coordinate) -> float:
    longitude_scale = math.cos(math.radians(point.lat))
    first = math.atan2(
        (point.lng - before.lng) * longitude_scale,
        point.lat - before.lat,
    )
    second = math.atan2(
        (after.lng - point.lng) * longitude_scale,
        after.lat - point.lat,
    )
    delta = abs(math.degrees(second - first)) % 360.0
    return min(delta, 360.0 - delta)
