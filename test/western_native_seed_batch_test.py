from __future__ import annotations

import math
import unittest

from test.western_seed_fixture import native_seed_graph
from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    WayInput,
    build_graph,
)
from tools.curvature_pipeline.western_graph.model import HubGraph
from tools.curvature_pipeline.western_seeds import (
    NativeRouteBatchLimits,
    NativeRouteBatchStatus,
    NativeSeedError,
    NativeSeedRejection,
    extract_native_seed_batches,
    generate_native_routes,
)


class WesternNativeSeedBatchTest(unittest.TestCase):
    def test_long_hub_is_partitioned_into_bounded_stable_candidates(self) -> None:
        # Given: one curved hub road with far more seed distance than one route allows.
        graph = native_seed_graph(segment_count=144)
        batches = extract_native_seed_batches(graph)

        # When: the bounded hub generator runs twice with reversed cluster input.
        limits = NativeRouteBatchLimits(max_candidates=3)
        first = generate_native_routes(graph, batches, limits=limits)
        repeated = generate_native_routes(
            graph,
            tuple(reversed(batches)),
            limits=limits,
        )

        # Then: multiple deterministic 15-80 km routes replace one oversized route.
        self.assertEqual(first, repeated)
        self.assertEqual(first.receipt.status, NativeRouteBatchStatus.READY)
        self.assertEqual(first.receipt.candidate_count, 3)
        self.assertTrue(all(len(batch.seeds) <= 256 for batch in batches))
        self.assertEqual(len({route.route_id for route in first.routes}), 3)
        self.assertTrue(
            all(15_000.0 <= route.distance_m <= 80_000.0 for route in first.routes)
        )

    def test_sparse_straight_hub_returns_explicit_no_go_receipt(self) -> None:
        # Given: a legal hub graph without reusable curvature.
        graph = native_seed_graph(straight=True)
        batches = extract_native_seed_batches(graph)

        # When: bounded multi-route generation runs.
        result = generate_native_routes(graph, batches)

        # Then: it returns NO_GO without inventing a route or seed.
        self.assertEqual(result.receipt.status, NativeRouteBatchStatus.NO_GO)
        self.assertEqual(result.receipt.input_seed_count, 0)
        self.assertEqual(result.routes, ())

    def test_disconnected_curved_components_never_cross_a_graph_gap(self) -> None:
        # Given: two independent 24 km curved roads in one hub graph.
        graph = _disconnected_curved_graph()
        batches = extract_native_seed_batches(graph)

        # When: the hub generator searches for four candidates.
        result = generate_native_routes(
            graph,
            batches,
            limits=NativeRouteBatchLimits(max_candidates=4),
        )

        # Then: both components yield routes and every route stays on one way.
        self.assertEqual(result.receipt.status, NativeRouteBatchStatus.READY)
        self.assertGreaterEqual(len(result.routes), 2)
        self.assertTrue(
            all(
                len({edge_id.split(":", 1)[0] for edge_id in route.edge_ids}) == 1
                for route in result.routes
            )
        )

    def test_duplicate_seed_cluster_fails_provenance_before_generation(self) -> None:
        # Given: a valid cluster is duplicated in the hub input.
        graph = native_seed_graph()
        batches = extract_native_seed_batches(graph)

        # When/Then: duplicate seed identity fails closed before candidate search.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.PROVENANCE):
            _ = generate_native_routes(graph, (*batches, *batches))

    def test_rejected_start_details_attribute_every_rejection(self) -> None:
        # Given: a curved hub too short for any 15 km route, so every start
        # attempt must be rejected.
        graph = native_seed_graph(segment_count=12)
        batches = extract_native_seed_batches(graph)

        # When: bounded multi-route generation runs.
        result = generate_native_routes(graph, batches)

        # Then: the diagnostic seam names one (seed, reason) per rejected
        # start and agrees exactly with the aggregate counters.
        receipt = result.receipt
        self.assertEqual(receipt.status, NativeRouteBatchStatus.NO_GO)
        self.assertGreater(receipt.rejected_start_count, 0)
        self.assertEqual(
            len(receipt.rejected_start_details), receipt.rejected_start_count
        )
        self.assertEqual(
            receipt.rejected_start_details,
            tuple(sorted(receipt.rejected_start_details)),
        )
        counted: dict[object, int] = {}
        for _, reason in receipt.rejected_start_details:
            counted[reason] = counted.get(reason, 0) + 1
        self.assertEqual(dict(receipt.rejection_counts), counted)

    def test_candidate_and_start_budgets_cannot_exceed_mapbox_program_cap(self) -> None:
        # Given: a valid curved hub and a caller asking for an oversized candidate pool.
        graph = native_seed_graph()
        batches = extract_native_seed_batches(graph)

        # When/Then: the per-hub boundary rejects anything above the plan's
        # 25 routes/hub cap before candidate search.
        with self.assertRaisesRegex(
            NativeSeedError, NativeSeedRejection.RESOURCE_LIMIT
        ):
            _ = generate_native_routes(
                graph,
                batches,
                limits=NativeRouteBatchLimits(max_candidates=26),
            )

    def test_plan_cap_of_25_candidates_per_hub_is_accepted(self) -> None:
        # Given: a valid curved hub.
        graph = native_seed_graph()
        batches = extract_native_seed_batches(graph)

        # When: the caller asks for exactly the plan's 25 routes/hub cap.
        result = generate_native_routes(
            graph,
            batches,
            limits=NativeRouteBatchLimits(max_candidates=25),
        )

        # Then: the limit is legal and the default ceiling matches the plan cap.
        self.assertEqual(result.receipt.status, NativeRouteBatchStatus.READY)
        self.assertEqual(NativeRouteBatchLimits().max_candidates, 25)


def _disconnected_curved_graph() -> HubGraph:
    step = 1_000.0 / 111_195.0

    def way(way_id: int, first_node_id: int, latitude: float) -> WayInput:
        coordinates = tuple(
            (
                latitude + index * step,
                -114.0 + 0.004 * math.sin(index * math.pi / 2.0),
            )
            for index in range(25)
        )
        return WayInput(
            osm_way_id=way_id,
            osm_node_ids=tuple(range(first_node_id, first_node_id + 25)),
            coordinates=coordinates,
            tags=(
                ("highway", "secondary"),
                ("ref", f"R{way_id}"),
                ("surface", "asphalt"),
            ),
        )

    return build_graph(
        HubGraphSpec(
            hub_id="ab-native-disconnected",
            province_code="AB",
            source_pbf_checksum="e" * 32,
            hub_pbf_checksum="f" * 64,
        ),
        (way(60_000, 1, 51.0), way(70_000, 10_001, 53.0)),
    )


if __name__ == "__main__":
    _ = unittest.main()
