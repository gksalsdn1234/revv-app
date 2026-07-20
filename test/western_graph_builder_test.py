from __future__ import annotations

import hashlib
import math
import tempfile
import unittest
from pathlib import Path

import osmium

from tools.curvature_pipeline.western_graph.builder import (
    GraphBuildError,
    GraphLimits,
    HubGraphSpec,
    WayInput,
    build_graph,
    build_graph_from_pbf,
)
from tools.curvature_pipeline.western_graph.codec import (
    graph_bytes,
    load_graph,
    write_graph,
)
from tools.curvature_pipeline.western_graph.graph import (
    shortest_node_path,
    weak_components,
)


def _spec(hub_pbf_checksum: str = "b" * 64) -> HubGraphSpec:
    return HubGraphSpec(
        hub_id="ab-fixture",
        province_code="AB",
        source_pbf_checksum="a" * 32,
        hub_pbf_checksum=hub_pbf_checksum,
    )


def _way(
    way_id: int,
    node_ids: tuple[int, ...],
    coordinates: tuple[tuple[float, float], ...],
    tags: dict[str, str],
) -> WayInput:
    return WayInput(
        osm_way_id=way_id,
        osm_node_ids=node_ids,
        coordinates=coordinates,
        tags=tuple(sorted(tags.items())),
    )


class WesternGraphBuilderTest(unittest.TestCase):
    def test_graph_edges_preserve_legal_direction_and_provenance(self) -> None:
        # Given: one forward road, one reverse road, and a one-way roundabout.
        ways = (
            _way(
                10,
                (1, 2, 3),
                ((51.0, -114.0), (51.001, -113.999), (51.002, -113.998)),
                {"highway": "secondary", "oneway": "yes", "ref": "1A"},
            ),
            _way(
                11,
                (3, 4),
                ((51.002, -113.998), (51.003, -113.997)),
                {"highway": "secondary", "oneway": "-1"},
            ),
            _way(
                12,
                (3, 5, 6, 3),
                (
                    (51.002, -113.998),
                    (51.003, -113.998),
                    (51.003, -113.997),
                    (51.002, -113.998),
                ),
                {"highway": "tertiary", "junction": "roundabout"},
            ),
        )

        # When: the bounded hub graph is built.
        graph = build_graph(_spec(), ways)

        # Then: only legal directed pairs exist and every edge is traceable.
        pairs = {(edge.from_node_id, edge.to_node_id) for edge in graph.edges}
        self.assertIn((1, 2), pairs)
        self.assertNotIn((2, 1), pairs)
        self.assertIn((4, 3), pairs)
        self.assertNotIn((3, 4), pairs)
        self.assertIn((3, 5), pairs)
        self.assertNotIn((5, 3), pairs)
        self.assertEqual(shortest_node_path(graph, 1, 6), (1, 2, 3, 5, 6))
        self.assertIsNone(shortest_node_path(graph, 6, 1))
        for edge in graph.edges:
            self.assertEqual(edge.hub_id, "ab-fixture")
            self.assertEqual(edge.province_code, "AB")
            self.assertEqual(edge.source_pbf_checksum, "a" * 32)
            self.assertGreater(edge.length_m, 0)
            self.assertTrue(math.isfinite(edge.length_m))
            self.assertEqual(
                edge.osm_node_sequence,
                (edge.from_node_id, edge.to_node_id),
            )

    def test_forbidden_ways_emit_zero_edges_and_components_remain_separate(
        self,
    ) -> None:
        # Given: two legal disconnected roads plus forbidden private/service ways.
        ways = (
            _way(
                20, (1, 2), ((51.0, -114.0), (51.01, -114.0)), {"highway": "secondary"}
            ),
            _way(
                21, (8, 9), ((52.0, -115.0), (52.01, -115.0)), {"highway": "tertiary"}
            ),
            _way(
                22,
                (2, 8),
                ((51.01, -114.0), (52.0, -115.0)),
                {"highway": "service", "surface": "asphalt"},
            ),
            _way(
                23,
                (9, 10),
                ((52.01, -115.0), (52.02, -115.0)),
                {"highway": "secondary", "access": "private"},
            ),
        )

        # When: the graph is built and weak components are computed.
        graph = build_graph(_spec(), ways)
        components = weak_components(graph)

        # Then: forbidden ways do not bridge the two legal components.
        self.assertEqual({edge.osm_way_id for edge in graph.edges}, {20, 21})
        self.assertEqual(components, ((1, 2), (8, 9)))

    def test_invalid_coordinates_and_oversized_component_fail_closed(self) -> None:
        invalid = _way(
            30,
            (1, 2),
            ((51.0, -114.0), (float("nan"), -114.0)),
            {"highway": "secondary"},
        )
        oversized = _way(
            31,
            (1, 2, 3),
            ((51.0, -114.0), (51.01, -114.0), (51.02, -114.0)),
            {"highway": "secondary"},
        )

        with self.assertRaises(GraphBuildError):
            build_graph(_spec(), (invalid,))
        with self.assertRaises(GraphBuildError):
            build_graph(
                _spec(),
                (oversized,),
                limits=GraphLimits(max_nodes=2, max_directed_edges=10),
            )

    def test_serialization_round_trip_is_byte_identical(self) -> None:
        # Given: a deterministic bounded graph.
        graph = build_graph(
            _spec(),
            (
                _way(
                    40,
                    (1, 2),
                    ((51.0, -114.0), (51.01, -114.0)),
                    {"highway": "secondary", "name": "Fixture Road"},
                ),
            ),
        )

        # When: it is written, loaded, and serialized again.
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "graph.json"
            write_graph(path, graph)
            loaded = load_graph(path)

        # Then: model and bytes are identical.
        self.assertEqual(loaded, graph)
        self.assertEqual(graph_bytes(loaded), graph_bytes(graph))

    def test_serialization_deduplicates_repeated_edge_provenance(self) -> None:
        # Given: one realistic long way whose edges repeat source metadata and tags.
        node_ids = tuple(range(1, 202))
        coordinates = tuple(
            (51.0 + index * 0.0001, -114.0 + index * 0.0001)
            for index in range(len(node_ids))
        )
        graph = build_graph(
            _spec(),
            (
                _way(
                    41,
                    node_ids,
                    coordinates,
                    {"highway": "secondary", "name": "Repeated Metadata Road"},
                ),
            ),
        )
        legacy_size = len(graph.model_dump_json().encode("utf-8"))

        # When: the public graph codec serializes the repeated metadata.
        payload = graph_bytes(graph)

        # Then: a deterministic compact envelope avoids JSON field repetition.
        self.assertTrue(payload.startswith(b"RVVG1\n"))
        self.assertLess(len(payload), legacy_size // 4)

    def test_input_checksum_must_match_the_bounded_hub_spec(self) -> None:
        # Given: a valid tiny PBF whose SHA-256 is not the declared hub checksum.
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "hub.osm.pbf"
            with osmium.SimpleWriter(str(path), overwrite=True) as writer:
                writer.add_node(osmium.osm.mutable.Node(id=1, location=(-114.0, 51.0)))
                writer.add_node(
                    osmium.osm.mutable.Node(id=2, location=(-113.99, 51.01))
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=50,
                        nodes=[1, 2],
                        tags={"highway": "secondary"},
                    )
                )
            actual = hashlib.sha256(path.read_bytes()).hexdigest()

            # When/Then: provenance validation fails before parsing.
            self.assertNotEqual(actual, "b" * 64)
            with self.assertRaises(GraphBuildError):
                build_graph_from_pbf(_spec(), path)


if __name__ == "__main__":
    unittest.main()
