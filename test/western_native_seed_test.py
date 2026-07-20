from __future__ import annotations

import unittest
from dataclasses import replace

from test.western_seed_fixture import native_seed_graph
from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    WayInput,
    build_graph,
)
from tools.curvature_pipeline.western_seeds import (
    NativeSeedError,
    NativeSeedLimits,
    NativeSeedRejection,
    extract_native_seeds,
    generate_native_route,
    seed_batch_bytes,
)


class WesternNativeSeedTest(unittest.TestCase):
    def test_curvy_osm_graph_produces_deterministic_licensed_route(self) -> None:
        # Given: a checksum-pinned legal OSM graph with repeated curves.
        graph = native_seed_graph()

        # When: seeds and the Todo6 route are generated twice.
        first = extract_native_seeds(graph)
        repeated = extract_native_seeds(graph)
        route = generate_native_route(graph, first)

        # Then: canonical licensed seed bytes feed one valid deterministic route.
        self.assertEqual(seed_batch_bytes(first), seed_batch_bytes(repeated))
        self.assertGreaterEqual(len(first.seeds), 3)
        self.assertGreaterEqual(route.distance_m, 15_000.0)
        self.assertLessEqual(route.distance_m, 80_000.0)
        self.assertEqual(route.source_pbf_checksum, graph.source_pbf_checksum)
        self.assertEqual(route.hub_pbf_checksum, graph.hub_pbf_checksum)
        self.assertTrue(all(seed.source_license == "ODbL-1.0" for seed in first.seeds))
        self.assertTrue(
            all(300.0 <= seed.distance_m <= 4_000.0 for seed in first.seeds)
        )

    def test_straight_graph_has_no_native_curvature_seed(self) -> None:
        # Given: a legal but straight OSM graph.
        graph = native_seed_graph(straight=True)

        # When: native seed extraction runs.
        batch = extract_native_seeds(graph)

        # Then: no straight fragment is promoted and route generation fails closed.
        self.assertEqual(batch.seeds, ())
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.NO_CURVATURE):
            _ = generate_native_route(graph, batch)

    def test_private_edge_injected_after_graph_policy_is_rejected(self) -> None:
        # Given: a structurally valid graph whose source tags claim private access.
        graph = native_seed_graph()
        private_edges = tuple(
            edge.model_copy(
                update={
                    "tags": tuple(
                        sorted(
                            (
                                *edge.tags,
                                edge.tags[0].model_copy(
                                    update={"key": "access", "value": "private"}
                                ),
                            ),
                            key=lambda tag: tag.key,
                        )
                    )
                }
            )
            for edge in graph.edges
        )
        injected = graph.model_copy(update={"edges": private_edges})

        # When/Then: the extractor rechecks policy and fails closed.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.ILLEGAL_EDGE):
            _ = extract_native_seeds(injected)

    def test_oneway_and_reverse_duplicates_use_only_legal_canonical_edges(self) -> None:
        # Given: equivalent curved bidirectional and one-way graphs.
        bidirectional = native_seed_graph()
        one_way = native_seed_graph(one_way=True)

        # When: both are extracted.
        two_way_batch = extract_native_seeds(bidirectional)
        one_way_batch = extract_native_seeds(one_way)

        # Then: physical paths are unique and one-way output never invents reverse edges.
        physical_paths = tuple(
            tuple(edge_id.rsplit(":", 1)[0] for edge_id in seed.edge_ids)
            for seed in two_way_batch.seeds
        )
        self.assertEqual(len(physical_paths), len(set(physical_paths)))
        self.assertTrue(
            all(
                edge_id.endswith(":f")
                for seed in one_way_batch.seeds
                for edge_id in seed.edge_ids
            )
        )

    def test_mutated_seed_provenance_is_rejected_before_todo6(self) -> None:
        # Given: a valid extracted batch with a mismatched source checksum.
        graph = native_seed_graph()
        batch = extract_native_seeds(graph)
        corrupted = replace(
            batch,
            source_pbf_checksum="e" * 32,
        )

        # When/Then: integration rejects it before route generation.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.PROVENANCE):
            _ = generate_native_route(graph, corrupted)

    def test_mutated_seed_geometry_is_rejected_before_todo6(self) -> None:
        # Given: a licensed batch whose first seed no longer replays its graph edges.
        graph = native_seed_graph()
        batch = extract_native_seeds(graph)
        corrupted_seed = replace(
            batch.seeds[0],
            points=batch.seeds[0].points[1:],
        )
        corrupted = replace(batch, seeds=(corrupted_seed, *batch.seeds[1:]))

        # When/Then: graph replay rejects the mutation before Todo6 consumes it.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.TOPOLOGY):
            _ = generate_native_route(graph, corrupted)

    def test_oneway_direction_mutation_is_rejected_during_extraction(self) -> None:
        # Given: a one-way graph whose edge ID is mutated to the forbidden direction.
        graph = native_seed_graph(one_way=True)
        first = graph.edges[0]
        reversed_id = f"{first.edge_id.rsplit(':', 1)[0]}:r"
        injected = graph.model_copy(
            update={
                "edges": (
                    first.model_copy(update={"edge_id": reversed_id}),
                    *graph.edges[1:],
                )
            }
        )

        # When/Then: OSM direction tags remain authoritative.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.ILLEGAL_EDGE):
            _ = extract_native_seeds(injected)

    def test_edge_and_seed_output_budgets_fail_closed(self) -> None:
        # Given: a curved graph larger than deliberately tiny extraction budgets.
        graph = native_seed_graph()

        # When/Then: input and output bounds reject rather than truncate silently.
        with self.assertRaisesRegex(
            NativeSeedError,
            NativeSeedRejection.RESOURCE_LIMIT,
        ):
            _ = extract_native_seeds(
                graph,
                limits=NativeSeedLimits(max_candidate_edges=1),
            )
        with self.assertRaisesRegex(
            NativeSeedError,
            NativeSeedRejection.RESOURCE_LIMIT,
        ):
            _ = extract_native_seeds(
                graph,
                limits=NativeSeedLimits(max_seeds=1),
            )

    def test_graph_with_only_forbidden_way_yields_no_edges_or_seeds(self) -> None:
        # Given: a private OSM way passed through the real graph builder.
        graph = build_graph(
            HubGraphSpec(
                hub_id="ab-private",
                province_code="AB",
                source_pbf_checksum="a" * 32,
                hub_pbf_checksum="b" * 64,
            ),
            (
                WayInput(
                    osm_way_id=70_000,
                    osm_node_ids=(1, 2, 3),
                    coordinates=((51.0, -114.0), (51.01, -114.01), (51.02, -114.0)),
                    tags=(("access", "private"), ("highway", "secondary")),
                ),
            ),
        )

        # When: native extraction runs on the policy-filtered graph.
        batch = extract_native_seeds(graph)

        # Then: forbidden source data cannot create a seed.
        self.assertEqual(graph.edges, ())
        self.assertEqual(batch.seeds, ())


if __name__ == "__main__":
    _ = unittest.main()
