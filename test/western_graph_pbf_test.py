from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import osmium

from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    build_graph_from_pbf,
)


class WesternGraphPbfTest(unittest.TestCase):
    def test_fixture_pbf_builds_expected_components_and_way_mapping(self) -> None:
        # Given: a real PBF with public, private, and explicitly unpaved ways.
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "ab-fixture.osm.pbf"
            with osmium.SimpleWriter(str(path), overwrite=True) as writer:
                for node_id, lon, lat in (
                    (1, -114.0, 51.0),
                    (2, -113.99, 51.01),
                    (3, -113.98, 51.02),
                    (8, -115.0, 52.0),
                    (9, -114.99, 52.01),
                ):
                    writer.add_node(
                        osmium.osm.mutable.Node(id=node_id, location=(lon, lat))
                    )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=100,
                        nodes=[1, 2, 3],
                        tags={"highway": "secondary", "oneway": "yes"},
                    )
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=101,
                        nodes=[8, 9],
                        tags={"highway": "residential", "surface": "asphalt"},
                    )
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=102,
                        nodes=[3, 8],
                        tags={"highway": "secondary", "access": "destination"},
                    )
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=103,
                        nodes=[2, 9],
                        tags={"highway": "secondary", "surface": "gravel"},
                    )
                )
            checksum = hashlib.sha256(path.read_bytes()).hexdigest()
            spec = HubGraphSpec(
                hub_id="ab-fixture",
                province_code="AB",
                source_pbf_checksum="a" * 32,
                hub_pbf_checksum=checksum,
            )

            # When: the checksum-pinned PBF is streamed into one hub graph.
            graph = build_graph_from_pbf(spec, path)

        # Then: only allowed OSM ways survive and directions are legal.
        self.assertEqual({edge.osm_way_id for edge in graph.edges}, {100, 101})
        self.assertEqual(
            {(edge.from_node_id, edge.to_node_id) for edge in graph.edges},
            {(1, 2), (2, 3), (8, 9), (9, 8)},
        )


if __name__ == "__main__":
    unittest.main()
