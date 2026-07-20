from __future__ import annotations

import math

from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    WayInput,
    build_graph,
)
from tools.curvature_pipeline.western_graph.model import Coordinate, HubGraph
from tools.curvature_pipeline.western_routes.model import SeedFragment, SeedSource


def chain_graph(
    *,
    segment_count: int = 24,
    one_way: bool = False,
    spacing_m: float = 1_000.0,
    reverse_way_ids: bool = False,
    split_ref_at: int | None = None,
) -> HubGraph:
    lat_step = spacing_m / 111_195.0
    coordinates = tuple(
        (51.0 + index * lat_step, -114.0 + 0.0015 * math.sin(index / 2.0))
        for index in range(segment_count + 1)
    )
    ways = tuple(
        WayInput(
            osm_way_id=10_000
            + (segment_count - 1 - index if reverse_way_ids else index),
            osm_node_ids=(index + 1, index + 2),
            coordinates=(coordinates[index], coordinates[index + 1]),
            tags=tuple(
                sorted(
                    {
                        "highway": "secondary",
                        "ref": "R2"
                        if split_ref_at is not None and index >= split_ref_at
                        else "R1",
                        **({"oneway": "yes"} if one_way else {}),
                    }.items()
                )
            ),
        )
        for index in range(segment_count)
    )
    return build_graph(
        HubGraphSpec(
            hub_id="ab-fixture",
            province_code="AB",
            source_pbf_checksum="a" * 32,
            hub_pbf_checksum="b" * 64,
        ),
        ways,
    )


def loop_graph(segment_count: int = 16, radius_m: float = 2_600.0) -> HubGraph:
    latitude_scale = 1.0 / 111_195.0
    longitude_scale = 1.0 / (111_195.0 * math.cos(math.radians(51.0)))
    coordinates = tuple(
        (
            51.0
            + radius_m
            * math.sin(2.0 * math.pi * index / segment_count)
            * latitude_scale,
            -114.0
            + radius_m
            * math.cos(2.0 * math.pi * index / segment_count)
            * longitude_scale,
        )
        for index in range(segment_count)
    )
    ways = tuple(
        WayInput(
            osm_way_id=10_000 + index,
            osm_node_ids=(index + 1, (index + 1) % segment_count + 1),
            coordinates=(coordinates[index], coordinates[(index + 1) % segment_count]),
            tags=(("highway", "secondary"), ("ref", "R1")),
        )
        for index in range(segment_count)
    )
    return build_graph(
        HubGraphSpec(
            hub_id="ab-loop",
            province_code="AB",
            source_pbf_checksum="a" * 32,
            hub_pbf_checksum="c" * 64,
        ),
        ways,
    )


def point_between(graph: HubGraph, edge_index: int, fraction: float) -> Coordinate:
    coordinates = {node.osm_node_id: node.coordinate for node in graph.nodes}
    start = coordinates[edge_index + 1]
    end = coordinates[(edge_index + 1) % len(graph.nodes) + 1]
    return Coordinate(
        lat=start.lat + (end.lat - start.lat) * fraction,
        lng=start.lng + (end.lng - start.lng) * fraction,
    )


def licensed_seed(
    graph: HubGraph,
    seed_id: str,
    first_edge: int,
    last_edge: int,
    *,
    reverse: bool = False,
    source: SeedSource = SeedSource.OSM,
    road_ref: str = "R1",
) -> SeedFragment:
    points = (
        point_between(graph, first_edge, 0.2),
        point_between(graph, last_edge, 0.8),
    )
    return SeedFragment(
        seed_id=seed_id,
        points=tuple(reversed(points)) if reverse else points,
        road_refs=(road_ref,),
        source=source,
        source_license="ODbL-1.0" if source is SeedSource.OSM else "unresolved",
    )


def chained_seeds(
    graph: HubGraph, *, reverse: bool = False
) -> tuple[SeedFragment, ...]:
    seeds = (
        licensed_seed(graph, "seed-a", 0, 3, reverse=reverse),
        licensed_seed(graph, "seed-b", 9, 12, reverse=reverse),
        licensed_seed(graph, "seed-c", 18, 21, reverse=reverse),
    )
    return tuple(reversed(seeds)) if reverse else seeds
