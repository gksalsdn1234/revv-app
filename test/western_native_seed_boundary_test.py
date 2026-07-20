from __future__ import annotations

import unittest

from test.western_seed_fixture import native_seed_graph
from tools.curvature_pipeline.western_graph.model import HubGraph
from tools.curvature_pipeline.western_routes.geometry import polyline_length_m
from tools.curvature_pipeline.western_seeds import (
    NativeSeed,
    NativeSeedBatch,
    NativeSeedError,
    NativeSeedRejection,
    extract_native_seeds,
    generate_native_route,
)
from tools.curvature_pipeline.western_seeds.extractor import (
    canonical_seed_id,
    seed_points,
    total_turn_degrees,
)


class WesternNativeSeedBoundaryTest(unittest.TestCase):
    def test_forged_straight_batch_is_rejected_at_todo6_boundary(self) -> None:
        # Given: canonical licensed seeds forged from a legal but straight graph.
        graph = native_seed_graph(straight=True)
        forward = tuple(edge for edge in graph.edges if edge.edge_id.endswith(":f"))
        seeds: list[NativeSeed] = []
        for start in range(0, len(forward), 3):
            edges = forward[start : start + 3]
            points = seed_points(edges)
            seeds.append(
                NativeSeed(
                    seed_id=canonical_seed_id(graph, edges),
                    hub_id=graph.hub_id,
                    province_code=graph.province_code,
                    source_pbf_checksum=graph.source_pbf_checksum,
                    hub_pbf_checksum=graph.hub_pbf_checksum,
                    source_license="ODbL-1.0",
                    edge_ids=tuple(edge.edge_id for edge in edges),
                    osm_way_ids=(50_000,),
                    points=points,
                    road_refs=("R1",),
                    distance_m=polyline_length_m(points),
                    total_turn_degrees=total_turn_degrees(edges),
                )
            )
        batch = NativeSeedBatch(
            schema_version=1,
            generator_version="western-osm-seed-v1",
            hub_id=graph.hub_id,
            province_code=graph.province_code,
            source_pbf_checksum=graph.source_pbf_checksum,
            hub_pbf_checksum=graph.hub_pbf_checksum,
            seeds=tuple(sorted(seeds, key=lambda seed: seed.seed_id)),
        )

        # When/Then: the public integration boundary independently enforces curvature.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.NO_CURVATURE):
            _ = generate_native_route(graph, batch)

    def test_semantically_false_edge_id_is_rejected(self) -> None:
        # Given: a serialized-valid graph whose edge IDs lie about their OSM way ID.
        graph = native_seed_graph()
        edges = tuple(
            edge.model_copy(
                update={"edge_id": edge.edge_id.replace("w50000:s0:", "w60000:s0:")}
            )
            if edge.segment_index == 0
            else edge
            for edge in graph.edges
        )
        injected = HubGraph.model_validate(
            graph.model_copy(update={"edges": edges}).model_dump()
        )

        # When/Then: extraction rejects the false canonical provenance.
        with self.assertRaisesRegex(NativeSeedError, NativeSeedRejection.PROVENANCE):
            _ = extract_native_seeds(injected)


if __name__ == "__main__":
    _ = unittest.main()
