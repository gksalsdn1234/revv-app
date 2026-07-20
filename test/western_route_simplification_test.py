from __future__ import annotations

import unittest
from dataclasses import replace

from test.western_route_fixture import (
    chain_graph,
    chained_seeds,
    licensed_seed,
    loop_graph,
)
from tools.curvature_pipeline.western_routes.generator import generate_route
from tools.curvature_pipeline.western_routes.model import (
    GenerationLimits,
    RouteGenerationError,
    RouteRejection,
)
from tools.curvature_pipeline.western_routes.pathing import path_distance_m
from tools.curvature_pipeline.western_routes.replay import route_replays_on_graph
from tools.curvature_pipeline.western_routes.simplify import simplify_graph_path
from tools.curvature_pipeline.western_routes.validation import validate_loop_return


class WesternRouteSimplificationTest(unittest.TestCase):
    def test_exactly_300_preserved_nodes_pass_and_301_rejects(self) -> None:
        graph_300 = chain_graph(segment_count=299, spacing_m=250.0)
        edges_300 = tuple(
            edge for edge in graph_300.edges if edge.edge_id.endswith(":f")
        )
        nodes_300 = (
            edges_300[0].from_node_id,
            *(edge.to_node_id for edge in edges_300),
        )

        simplified = simplify_graph_path(
            graph_300,
            nodes_300,
            frozenset(nodes_300),
            path_distance_m(edges_300),
            GenerationLimits(),
        )
        self.assertEqual(len(simplified.geometry), 300)

        graph_301 = chain_graph(segment_count=300, spacing_m=250.0)
        edges_301 = tuple(
            edge for edge in graph_301.edges if edge.edge_id.endswith(":f")
        )
        nodes_301 = (
            edges_301[0].from_node_id,
            *(edge.to_node_id for edge in edges_301),
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = simplify_graph_path(
                graph_301,
                nodes_301,
                frozenset(nodes_301),
                path_distance_m(edges_301),
                GenerationLimits(),
            )
        self.assertEqual(caught.exception.reason, RouteRejection.NODE_LIMIT)

    def test_hausdorff_and_length_errors_have_independent_rejections(self) -> None:
        graph = chain_graph()
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(
                graph,
                chained_seeds(graph),
                limits=GenerationLimits(
                    max_hausdorff_m=0.0,
                    max_length_error_ratio=1.0,
                ),
            )
        self.assertEqual(caught.exception.reason, RouteRejection.HAUSDORFF_LIMIT)

        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(
                graph,
                chained_seeds(graph),
                limits=GenerationLimits(max_length_error_ratio=0.0),
            )
        self.assertEqual(caught.exception.reason, RouteRejection.LENGTH_ERROR)

    def test_replay_rejects_changed_order_geometry_and_provenance(self) -> None:
        graph = chain_graph()
        route = generate_route(graph, chained_seeds(graph))
        self.assertTrue(route_replays_on_graph(graph, route))
        self.assertFalse(
            route_replays_on_graph(
                graph,
                replace(route, edge_ids=tuple(reversed(route.edge_ids))),
            )
        )
        self.assertFalse(
            route_replays_on_graph(
                graph,
                replace(route, geometry=tuple(reversed(route.geometry))),
            )
        )
        self.assertFalse(
            route_replays_on_graph(
                graph,
                replace(route, source_pbf_checksum="0" * 32),
            )
        )

    def test_loop_closes_on_distinct_edges(self) -> None:
        graph = loop_graph()
        seeds = (
            licensed_seed(graph, "loop-a", 0, 3),
            licensed_seed(graph, "loop-b", 6, 9),
            licensed_seed(graph, "loop-c", 12, 15),
        )
        route = generate_route(graph, seeds)
        self.assertTrue(route.is_loop)
        self.assertEqual(len(route.edge_ids), len(set(route.edge_ids)))

    def test_out_and_back_loop_rejects_shared_return_edges(self) -> None:
        graph = chain_graph()
        outbound = tuple(
            edge
            for edge in graph.edges
            if edge.edge_id.endswith(":f") and edge.osm_way_id < 10_010
        )
        returning = tuple(
            sorted(
                (
                    edge
                    for edge in graph.edges
                    if edge.edge_id.endswith(":r") and edge.osm_way_id < 10_010
                ),
                key=lambda edge: edge.osm_way_id,
                reverse=True,
            )
        )

        with self.assertRaises(RouteGenerationError) as caught:
            validate_loop_return(
                (*outbound, *returning),
                is_loop=True,
                limits=GenerationLimits(),
            )
        self.assertEqual(
            caught.exception.reason,
            RouteRejection.LOOP_RETURN_OVERLAP,
        )

    def test_connector_and_ref_failures_are_distinct(self) -> None:
        graph = chain_graph()
        far_seeds = (
            licensed_seed(graph, "near", 0, 3),
            licensed_seed(graph, "far", 20, 23),
        )
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(graph, far_seeds)
        self.assertEqual(caught.exception.reason, RouteRejection.SEEDS_TOO_FAR)

        mismatched = replace(far_seeds[1], road_refs=("R9",))
        with self.assertRaises(RouteGenerationError) as caught:
            _ = generate_route(graph, (far_seeds[0], mismatched))
        self.assertEqual(caught.exception.reason, RouteRejection.REF_MISMATCH)


if __name__ == "__main__":
    unittest.main()
