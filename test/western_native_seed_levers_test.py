from __future__ import annotations

import math
import unittest

from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    WayInput,
    build_graph,
)
from tools.curvature_pipeline.western_graph.model import GraphEdge, HubGraph
from tools.curvature_pipeline.western_routes.model import RouteRejection
from tools.curvature_pipeline.western_seeds import (
    NativeRouteBatchStatus,
    extract_native_seed_batches,
    generate_native_routes,
)

_LATITUDE_STEP = 1_000.0 / 111_195.0
_RESIDENTIAL_VALUES = frozenset({"residential", "service"})


def _curvy_coordinates(
    node_count: int,
    *,
    base_lat: float = 51.0,
    base_lng: float = -114.0,
    start_index: int = 0,
    amplitude: float = 0.004,
) -> tuple[tuple[float, float], ...]:
    return tuple(
        (
            base_lat + (start_index + offset) * _LATITUDE_STEP,
            base_lng + amplitude * math.sin((start_index + offset) * math.pi / 2.0),
        )
        for offset in range(node_count)
    )


def _way(
    way_id: int,
    node_ids: tuple[int, ...],
    coordinates: tuple[tuple[float, float], ...],
    highway: str,
    name: str,
) -> WayInput:
    tags = {
        "highway": highway,
        "name": name,
        "surface": "asphalt",
    }
    return WayInput(
        osm_way_id=way_id,
        osm_node_ids=node_ids,
        coordinates=coordinates,
        tags=tuple(sorted(tags.items())),
    )


def _spec(hub_id: str) -> HubGraphSpec:
    return HubGraphSpec(
        hub_id=hub_id,
        province_code="AB",
        source_pbf_checksum="a" * 32,
        hub_pbf_checksum="b" * 64,
    )


def _edge_by_id(graph: HubGraph) -> dict[str, GraphEdge]:
    return {edge.edge_id: edge for edge in graph.edges}


def _residential_exposure(edges: tuple[GraphEdge, ...]) -> float:
    total_m = sum(edge.length_m for edge in edges)
    residential_m = sum(
        edge.length_m
        for edge in edges
        if any(
            tag.key == "highway" and tag.value in _RESIDENTIAL_VALUES
            for tag in edge.tags
        )
    )
    return residential_m / total_m if total_m > 0.0 else 0.0


def _branching_graph() -> HubGraph:
    """13 km secondary spine ending at a junction with two 5 km branches.

    Both branches are equally curvy and equally distant continuations; one
    is residential, one is secondary. Reaching the 15 km route floor
    requires exactly one of them.
    """
    spine_nodes = 14  # 13 segments of ~1 km
    spine = _way(
        10_000,
        tuple(range(1, spine_nodes + 1)),
        _curvy_coordinates(spine_nodes),
        "secondary",
        "Alpha Spine",
    )
    junction_id = spine_nodes
    junction_index = spine_nodes - 1
    # Residential branch heads east of the spine axis, secondary branch
    # continues north, both from the same junction node.
    residential_nodes = (junction_id, *range(100, 105))
    residential_coordinates = (
        _curvy_coordinates(1, start_index=junction_index)[0],
        *(
            (
                51.0 + junction_index * _LATITUDE_STEP,
                -114.0
                + 0.004 * math.sin(junction_index * math.pi / 2.0)
                + (offset + 1) * _LATITUDE_STEP * (1.6 if offset % 2 else 1.0),
            )
            for offset in range(5)
        ),
    )
    residential = _way(
        20_000,
        residential_nodes,
        residential_coordinates,
        "residential",
        "Beta Crescent",
    )
    secondary_nodes = (junction_id, *range(200, 205))
    secondary = _way(
        30_000,
        secondary_nodes,
        _curvy_coordinates(6, start_index=junction_index),
        "secondary",
        "Gamma Route",
    )
    return build_graph(_spec("ab-branching"), (spine, residential, secondary))


def _repair_graph() -> HubGraph:
    """Secondary 14 km, then residential 3 km, then secondary 7 km chain.

    Any 15 km candidate from the spine must pass through the residential
    middle (~17 km, exposure ~0.18 - failing the downstream 15% gate);
    exposure-repair extension into the far secondary is the only way to
    dilute it below the gate without touching the gate.
    """
    first_nodes = 15  # 14 segments
    first = _way(
        10_000,
        tuple(range(1, first_nodes + 1)),
        _curvy_coordinates(first_nodes),
        "secondary",
        "Alpha Route",
    )
    middle_nodes = (first_nodes, *range(100, 103))
    middle = _way(
        20_000,
        middle_nodes,
        _curvy_coordinates(4, start_index=first_nodes - 1),
        "residential",
        "Beta Crescent",
    )
    last_nodes = (102, *range(200, 207))
    last = _way(
        30_000,
        last_nodes,
        _curvy_coordinates(8, start_index=first_nodes + 2),
        "secondary",
        "Gamma Route",
    )
    return build_graph(_spec("ab-repair"), (first, middle, last))


def _tail_heavy_graph() -> HubGraph:
    """One 18 km secondary road whose curviest window is the LAST one.

    The ranked start seed sits at the road's far end with nothing ahead of
    it, so only head-side (reverse) extension can reach the 15 km floor.
    """
    node_count = 19  # 18 segments
    coordinates = tuple(
        (
            51.0 + index * _LATITUDE_STEP,
            -114.0
            + (0.002 + 0.004 * (index / node_count)) * math.sin(index * math.pi / 2.0),
        )
        for index in range(node_count)
    )
    road = _way(
        10_000,
        tuple(range(1, node_count + 1)),
        coordinates,
        "secondary",
        "Delta Climb",
    )
    return build_graph(_spec("ab-tail-heavy"), (road,))


class WesternNativeSeedLeversTest(unittest.TestCase):
    def test_assembly_prefers_non_residential_continuation(self) -> None:
        # Given: a spine whose 15 km continuation is a fork between an
        # equally close residential branch and a secondary branch.
        graph = _branching_graph()
        batches = extract_native_seed_batches(graph)
        edges = _edge_by_id(graph)

        # When: the bounded hub generator runs twice with reversed input.
        first = generate_native_routes(graph, batches)
        repeated = generate_native_routes(graph, tuple(reversed(batches)))

        # Then: deterministically, the route reaches 15 km entirely on
        # non-residential pavement - the residential fork is never chosen.
        self.assertEqual(first, repeated)
        self.assertEqual(first.receipt.status, NativeRouteBatchStatus.READY)
        route = first.routes[0]
        self.assertGreaterEqual(route.distance_m, 15_000.0)
        route_edges = tuple(edges[edge_id] for edge_id in route.edge_ids)
        self.assertEqual(_residential_exposure(route_edges), 0.0)
        self.assertTrue(
            any(edge.osm_way_id == 30_000 for edge in route_edges),
            "route must continue onto the secondary branch",
        )

    def test_exposure_repair_extends_past_minimum_until_gate_would_pass(self) -> None:
        # Given: a chain where every minimal 15 km candidate carries ~18%
        # residential exposure and only further stitching can dilute it.
        graph = _repair_graph()
        batches = extract_native_seed_batches(graph)
        edges = _edge_by_id(graph)

        # When: the bounded hub generator runs twice with reversed input.
        first = generate_native_routes(graph, batches)
        repeated = generate_native_routes(graph, tuple(reversed(batches)))

        # Then: the candidate keeps stitching curvature seeds beyond the
        # 15 km floor until its exposure is below the (unchanged) 15% gate.
        self.assertEqual(first, repeated)
        self.assertEqual(first.receipt.status, NativeRouteBatchStatus.READY)
        route = first.routes[0]
        route_edges = tuple(edges[edge_id] for edge_id in route.edge_ids)
        self.assertGreaterEqual(route.distance_m, 15_000.0)
        self.assertLess(_residential_exposure(route_edges), 0.15)
        self.assertTrue(
            any(edge.osm_way_id == 30_000 for edge in route_edges),
            "repair extension must continue onto the far secondary road",
        )

    def test_reverse_extension_rescues_tail_start_from_route_too_short(self) -> None:
        # Given: the curviest (first-ranked) seed sits at the dead-end tail
        # of its road, with all remaining seed distance behind it.
        graph = _tail_heavy_graph()
        batches = extract_native_seed_batches(graph)

        # When: the bounded hub generator runs twice with reversed input.
        first = generate_native_routes(graph, batches)
        repeated = generate_native_routes(graph, tuple(reversed(batches)))

        # Then: head-side extension stitches earlier windows into a legal
        # 15-80 km route instead of wasting the start as route_too_short.
        self.assertEqual(first, repeated)
        self.assertEqual(first.receipt.status, NativeRouteBatchStatus.READY)
        self.assertTrue(
            all(15_000.0 <= route.distance_m <= 80_000.0 for route in first.routes)
        )
        self.assertNotIn(
            RouteRejection.TOO_SHORT,
            dict(first.receipt.rejection_counts),
        )


if __name__ == "__main__":
    _ = unittest.main()
