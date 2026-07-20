from __future__ import annotations

import unittest

from test.western_route_fixture import chain_graph, chained_seeds, licensed_seed
from tools.curvature_pipeline.western_routes.codec import route_bytes
from tools.curvature_pipeline.western_routes.generator import generate_route
from tools.curvature_pipeline.western_routes.identity import canonical_route_id


class WesternRouteGenerationTest(unittest.TestCase):
    def test_reversed_input_and_rerun_are_byte_identical(self) -> None:
        # Given: three licensed seeds chained by legal graph paths.
        graph = chain_graph()

        # When: input order and seed geometry orientation are reversed.
        first = generate_route(graph, chained_seeds(graph))
        repeated = generate_route(graph, chained_seeds(graph))
        reversed_route = generate_route(graph, chained_seeds(graph, reverse=True))

        # Then: canonical route identity and bytes do not depend on input direction.
        self.assertEqual(first.route_id, reversed_route.route_id)
        self.assertEqual(route_bytes(first), route_bytes(repeated))
        self.assertEqual(route_bytes(first), route_bytes(reversed_route))
        self.assertTrue(first.route_id.startswith("osmgen:v1:"))

    def test_geographic_stitching_does_not_depend_on_osm_way_id_order(self) -> None:
        graph = chain_graph(reverse_way_ids=True)

        first = generate_route(graph, chained_seeds(graph))
        reversed_route = generate_route(graph, chained_seeds(graph, reverse=True))

        self.assertEqual(route_bytes(first), route_bytes(reversed_route))
        self.assertGreaterEqual(first.distance_m, 15_000.0)

    def test_forward_and_reverse_edge_sequences_have_the_same_id(self) -> None:
        graph = chain_graph()
        route = generate_route(graph, chained_seeds(graph))
        edge_by_id = {edge.edge_id: edge for edge in graph.edges}
        forward = tuple(edge_by_id[edge_id] for edge_id in route.edge_ids)
        reverse_by_pair = {
            (
                edge.from_node_id,
                edge.to_node_id,
                edge.osm_way_id,
                edge.segment_index,
            ): edge
            for edge in graph.edges
        }
        reverse = tuple(
            reverse_by_pair[
                (
                    edge.to_node_id,
                    edge.from_node_id,
                    edge.osm_way_id,
                    edge.segment_index,
                )
            ]
            for edge in reversed(forward)
        )

        self.assertEqual(canonical_route_id(forward), canonical_route_id(reverse))

    def test_adjacent_distinct_osm_refs_stitch_on_the_legal_graph(self) -> None:
        graph = chain_graph(split_ref_at=8)
        seeds = (
            licensed_seed(graph, "r1", 0, 3, road_ref="R1"),
            licensed_seed(graph, "r2-a", 9, 12, road_ref="R2"),
            licensed_seed(graph, "r2-b", 18, 21, road_ref="R2"),
        )

        route = generate_route(graph, seeds)

        self.assertGreaterEqual(route.distance_m, 15_000.0)

    def test_route_is_continuous_bounded_and_replayable(self) -> None:
        graph = chain_graph()
        route = generate_route(graph, chained_seeds(graph))

        self.assertGreaterEqual(route.distance_m, 15_000.0)
        self.assertLessEqual(route.distance_m, 80_000.0)
        self.assertLessEqual(len(route.geometry), 300)
        self.assertLessEqual(len(route_bytes(route)), 512 * 1024)
        self.assertLessEqual(route.hausdorff_error_m, 25.0)
        self.assertLessEqual(route.length_error_ratio, 0.01)
        self.assertEqual(len(route.edge_ids), len(set(route.edge_ids)))
        self.assertEqual(route.replay_spans[0].first_edge_index, 0)
        self.assertEqual(
            route.replay_spans[-1].last_edge_index,
            len(route.edge_ids) - 1,
        )
        node_coordinates = {node.osm_node_id: node.coordinate for node in graph.nodes}
        for node_id in (1, 5, 10, 14, 19, 23):
            self.assertIn(node_coordinates[node_id], route.geometry)

    def test_oneway_chain_uses_only_legal_forward_edges(self) -> None:
        graph = chain_graph(one_way=True)
        route = generate_route(graph, chained_seeds(graph))

        self.assertGreaterEqual(route.distance_m, 15_000.0)
        self.assertTrue(all(edge_id.endswith(":f") for edge_id in route.edge_ids))


if __name__ == "__main__":
    unittest.main()
