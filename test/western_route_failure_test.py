from __future__ import annotations

import unittest
from dataclasses import replace

from test.western_route_fixture import chain_graph, chained_seeds, licensed_seed
from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    WayInput,
    build_graph,
)
from tools.curvature_pipeline.western_graph.model import Coordinate
from tools.curvature_pipeline.western_routes.codec import route_bytes
from tools.curvature_pipeline.western_routes.generator import generate_route
from tools.curvature_pipeline.western_routes.model import (
    GenerationLimits,
    RouteGenerationError,
    RouteRejection,
    SeedFragment,
    SeedSource,
)


class WesternRouteFailureTest(unittest.TestCase):
    def test_unlicensed_roadcurvature_seed_fails_closed(self) -> None:
        graph = chain_graph()
        seeds = list(chained_seeds(graph))
        seeds[0] = replace(
            seeds[0],
            source=SeedSource.ROAD_CURVATURE,
            source_license="unresolved",
        )

        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(graph, tuple(seeds))
        self.assertEqual(caught.exception.reason, RouteRejection.UNLICENSED_SEED)

    def test_snap_ambiguity_miss_and_disconnection_have_stable_reasons(self) -> None:
        graph = chain_graph()
        ambiguous = replace(
            licensed_seed(graph, "ambiguous", 0, 3),
            points=(graph.nodes[1].coordinate, graph.nodes[4].coordinate),
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(graph, (ambiguous,))
        self.assertEqual(caught.exception.reason, RouteRejection.SNAP_AMBIGUOUS)

        missed_seed = licensed_seed(graph, "missed", 0, 3)
        missed = replace(
            missed_seed,
            points=tuple(
                Coordinate(lat=point.lat, lng=point.lng + 0.01)
                for point in missed_seed.points
            ),
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(graph, (missed,))
        self.assertEqual(caught.exception.reason, RouteRejection.SNAP_MISS)

        disconnected = build_graph(
            HubGraphSpec(
                hub_id="ab-fixture",
                province_code="AB",
                source_pbf_checksum="a" * 32,
                hub_pbf_checksum="b" * 64,
            ),
            (
                WayInput(
                    osm_way_id=1,
                    osm_node_ids=(1, 2),
                    coordinates=((51.0, -114.0), (51.02, -114.0)),
                    tags=(("highway", "secondary"), ("ref", "R1")),
                ),
                WayInput(
                    osm_way_id=2,
                    osm_node_ids=(3, 4),
                    coordinates=((52.0, -115.0), (52.02, -115.0)),
                    tags=(("highway", "secondary"), ("ref", "R1")),
                ),
            ),
        )
        seeds = (
            SeedFragment(
                seed_id="first",
                points=(
                    Coordinate(lat=51.004, lng=-114.0),
                    Coordinate(lat=51.016, lng=-114.0),
                ),
                road_refs=("R1",),
                source=SeedSource.OSM,
                source_license="ODbL-1.0",
            ),
            SeedFragment(
                seed_id="second",
                points=(
                    Coordinate(lat=52.004, lng=-115.0),
                    Coordinate(lat=52.016, lng=-115.0),
                ),
                road_refs=("R1",),
                source=SeedSource.OSM,
                source_license="ODbL-1.0",
            ),
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(disconnected, seeds)
        self.assertEqual(caught.exception.reason, RouteRejection.DISCONNECTED)

    def test_distance_node_and_payload_limits_reject_without_db_ceiling(self) -> None:
        graph = chain_graph(segment_count=90)
        seeds = tuple(
            licensed_seed(graph, f"seed-{start:02d}", start, start + 3)
            for start in range(0, 87, 10)
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(graph, seeds)
        self.assertEqual(caught.exception.reason, RouteRejection.TOO_LONG)

        bounded_graph = chain_graph()
        baseline = generate_route(bounded_graph, chained_seeds(bounded_graph))
        exact_payload_size = len(route_bytes(baseline))
        exact = generate_route(
            bounded_graph,
            chained_seeds(bounded_graph),
            limits=GenerationLimits(max_payload_bytes=exact_payload_size),
        )
        self.assertEqual(len(route_bytes(exact)), exact_payload_size)

        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(
                bounded_graph,
                chained_seeds(bounded_graph),
                limits=GenerationLimits(max_geometry_nodes=2),
            )
        self.assertEqual(caught.exception.reason, RouteRejection.NODE_LIMIT)

        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(
                bounded_graph,
                chained_seeds(bounded_graph),
                limits=GenerationLimits(max_payload_bytes=exact_payload_size - 1),
            )
        self.assertEqual(caught.exception.reason, RouteRejection.PAYLOAD_LIMIT)

    def test_repeated_edge_and_illegal_direction_reject(self) -> None:
        graph = chain_graph(one_way=True)
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(
                graph,
                (
                    licensed_seed(graph, "forward", 0, 3),
                    licensed_seed(graph, "overlap", 2, 5),
                ),
            )
        self.assertEqual(caught.exception.reason, RouteRejection.REPEATED_EDGE)

        fork = build_graph(
            HubGraphSpec(
                hub_id="ab-fork",
                province_code="AB",
                source_pbf_checksum="a" * 32,
                hub_pbf_checksum="d" * 64,
            ),
            (
                WayInput(
                    osm_way_id=20_000,
                    osm_node_ids=(1, 2, 3, 4, 5),
                    coordinates=tuple(
                        (51.0 + 0.009 * index, -114.0) for index in range(5)
                    ),
                    tags=(("highway", "secondary"), ("oneway", "yes"), ("ref", "R1")),
                ),
                WayInput(
                    osm_way_id=20_001,
                    osm_node_ids=(1, 6, 7, 8, 9),
                    coordinates=tuple(
                        (51.0, -114.0 + 0.014 * index) for index in range(5)
                    ),
                    tags=(("highway", "secondary"), ("oneway", "yes"), ("ref", "R1")),
                ),
            ),
        )
        fork_seeds = (
            SeedFragment(
                seed_id="north",
                points=(
                    Coordinate(lat=51.0018, lng=-114.0),
                    Coordinate(lat=51.0342, lng=-114.0),
                ),
                road_refs=("R1",),
                source=SeedSource.OSM,
                source_license="ODbL-1.0",
            ),
            SeedFragment(
                seed_id="east",
                points=(
                    Coordinate(lat=51.0, lng=-113.9972),
                    Coordinate(lat=51.0, lng=-113.9468),
                ),
                road_refs=("R1",),
                source=SeedSource.OSM,
                source_license="ODbL-1.0",
            ),
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(fork, fork_seeds)
        self.assertEqual(caught.exception.reason, RouteRejection.ILLEGAL_DIRECTION)


if __name__ == "__main__":
    unittest.main()
