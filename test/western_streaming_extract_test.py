from __future__ import annotations

import hashlib
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import osmium

from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    build_graph_from_pbf,
)
from tools.curvature_pipeline.western_sources.manifest import Bounds, Hub
from tools.curvature_pipeline.western_sources.osmium_runner import (
    OsmiumError,
    OsmiumExtraction,
    OsmiumRunner,
)
from tools.curvature_pipeline.western_sources.streaming_extract import (
    StreamingExtractError,
    StreamingExtractTask,
    StreamingLimits,
    extract_drivable_hub,
)
from test.western_source_fixture import write_fake_osmium


class WesternStreamingExtractTest(unittest.TestCase):
    def test_extract_does_not_build_a_second_province_reference_index(self) -> None:
        # Given: one allowed way whose referenced nodes cross the hub boundary.
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "province.osm.pbf"
            destination = root / "hub.osm.pbf"
            with osmium.SimpleWriter(str(source), overwrite=True) as writer:
                writer.add_node(osmium.osm.mutable.Node(id=1, location=(-114.0, 51.0)))
                writer.add_node(osmium.osm.mutable.Node(id=2, location=(-112.0, 53.0)))
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=100,
                        nodes=[1, 2],
                        tags={"highway": "secondary"},
                    )
                )
            hub = Hub(
                hub_id="ab-fixture",
                province_code="AB",
                bounds=Bounds(
                    min_lat=50.0,
                    min_lng=-115.0,
                    max_lat=52.0,
                    max_lng=-113.0,
                ),
            )

            # When: extraction runs without the memory-heavy back-reference index.
            with patch(
                "tools.curvature_pipeline.western_sources.streaming_extract.osmium.BackReferenceWriter",
                side_effect=AssertionError("second province index is forbidden"),
            ):
                receipt = extract_drivable_hub(
                    StreamingExtractTask(
                        source=source,
                        destination=destination,
                        hub=hub,
                    )
                )
            graph = build_graph_from_pbf(
                HubGraphSpec(
                    hub_id=hub.hub_id,
                    province_code=hub.province_code,
                    source_pbf_checksum="a" * 32,
                    hub_pbf_checksum=hashlib.sha256(
                        destination.read_bytes()
                    ).hexdigest(),
                ),
                destination,
            )

        # Then: the output is still complete and graph-readable.
        self.assertEqual(receipt.node_count, 2)
        self.assertEqual(receipt.way_count, 1)
        self.assertEqual({node.osm_node_id for node in graph.nodes}, {1, 2})
        self.assertEqual({edge.osm_way_id for edge in graph.edges}, {100})

    def test_disk_backed_extract_keeps_complete_allowed_bbox_ways(self) -> None:
        # Given: sparse global IDs and allowed/forbidden ways around one hub.
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "province.osm.pbf"
            first = root / "first.osm.pbf"
            second = root / "second.osm.pbf"
            with osmium.SimpleWriter(str(source), overwrite=True) as writer:
                for node_id, lon, lat in (
                    (1, -114.0, 51.0),
                    (9_000_000_000, -113.0, 53.0),
                    (9_000_000_001, -110.0, 55.0),
                    (9_000_000_002, -109.9, 55.1),
                    (9_000_000_003, -114.1, 51.1),
                    (9_000_000_004, -114.2, 51.2),
                    (9_000_000_005, -114.3, 51.3),
                ):
                    writer.add_node(
                        osmium.osm.mutable.Node(id=node_id, location=(lon, lat))
                    )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=100,
                        nodes=[1, 9_000_000_000],
                        tags={"highway": "secondary", "oneway": "yes"},
                    )
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=101,
                        nodes=[9_000_000_001, 9_000_000_002],
                        tags={"highway": "residential", "surface": "asphalt"},
                    )
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=102,
                        nodes=[9_000_000_003, 9_000_000_004],
                        tags={"access": "private", "highway": "secondary"},
                    )
                )
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=103,
                        nodes=[9_000_000_004, 9_000_000_005],
                        tags={"highway": "tertiary", "surface": "gravel"},
                    )
                )
            hub = Hub(
                hub_id="ab-fixture",
                province_code="AB",
                bounds=Bounds(
                    min_lat=50.0,
                    min_lng=-115.0,
                    max_lat=52.0,
                    max_lng=-113.5,
                ),
            )

            # When: the same source is streamed twice through a disk index.
            first_receipt = extract_drivable_hub(
                StreamingExtractTask(source=source, destination=first, hub=hub)
            )
            second_receipt = extract_drivable_hub(
                StreamingExtractTask(source=source, destination=second, hub=hub)
            )
            graph = build_graph_from_pbf(
                HubGraphSpec(
                    hub_id=hub.hub_id,
                    province_code=hub.province_code,
                    source_pbf_checksum="a" * 32,
                    hub_pbf_checksum=hashlib.sha256(first.read_bytes()).hexdigest(),
                ),
                first,
            )
            first_bytes = first.read_bytes()
            second_bytes = second.read_bytes()
            remaining_names = {path.name for path in root.iterdir()}

        # Then: the crossing way is complete and forbidden/outside ways are absent.
        self.assertEqual(first_receipt.node_count, 2)
        self.assertEqual(first_receipt.way_count, 1)
        self.assertEqual(second_receipt, first_receipt)
        self.assertEqual(second_bytes, first_bytes)
        self.assertEqual(
            remaining_names,
            {"province.osm.pbf", "first.osm.pbf", "second.osm.pbf"},
        )
        self.assertEqual({node.osm_node_id for node in graph.nodes}, {1, 9_000_000_000})
        self.assertEqual({edge.osm_way_id for edge in graph.edges}, {100})

    def test_resource_limit_leaves_no_promoted_output(self) -> None:
        # Given: one allowed two-node way and a one-node extraction limit.
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "province.osm.pbf"
            destination = root / "hub.osm.pbf"
            with osmium.SimpleWriter(str(source), overwrite=True) as writer:
                writer.add_node(osmium.osm.mutable.Node(id=1, location=(-114.0, 51.0)))
                writer.add_node(osmium.osm.mutable.Node(id=2, location=(-113.9, 51.1)))
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=100,
                        nodes=[1, 2],
                        tags={"highway": "secondary"},
                    )
                )
            hub = Hub(
                hub_id="ab-fixture",
                province_code="AB",
                bounds=Bounds(
                    min_lat=50.0,
                    min_lng=-115.0,
                    max_lat=52.0,
                    max_lng=-113.0,
                ),
            )

            # When/Then: bounded extraction fails without promoting a PBF.
            with self.assertRaises(StreamingExtractError):
                _ = extract_drivable_hub(
                    StreamingExtractTask(
                        source=source,
                        destination=destination,
                        hub=hub,
                        limits=StreamingLimits(max_nodes=1),
                    )
                )
            self.assertFalse(destination.exists())

    def test_missing_reference_preserves_destination_and_removes_work_files(
        self,
    ) -> None:
        # Given: a malformed source and an existing checksum-valid destination.
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "broken-source.osm.pbf"
            destination = root / "existing.osm.pbf"
            osmium_path = root / "osmium"
            with osmium.SimpleWriter(str(source), overwrite=True) as writer:
                writer.add_node(osmium.osm.mutable.Node(id=1, location=(-114.0, 51.0)))
                writer.add_way(
                    osmium.osm.mutable.Way(
                        id=100,
                        nodes=[2, 1],
                        tags={"highway": "secondary"},
                    )
                )
            destination.write_bytes(b"previous-good-output")
            write_fake_osmium(osmium_path)
            hub = Hub(
                hub_id="ab-fixture",
                province_code="AB",
                bounds=Bounds(
                    min_lat=50.0,
                    min_lng=-115.0,
                    max_lat=52.0,
                    max_lng=-113.0,
                ),
            )

            # When: the hard-deadline runner invokes the streaming subprocess.
            with self.assertRaises(OsmiumError):
                OsmiumRunner(executable=osmium_path).extract(
                    OsmiumExtraction(
                        source=source,
                        destination=destination,
                        hub=hub,
                        deadline_monotonic=time.monotonic() + 30.0,
                    )
                )
            destination_bytes = destination.read_bytes()
            remaining_names = {path.name for path in root.iterdir()}

        # Then: no partial replaces the prior output or leaves a sidecar behind.
        self.assertEqual(destination_bytes, b"previous-good-output")
        self.assertEqual(
            remaining_names,
            {"broken-source.osm.pbf", "existing.osm.pbf", "osmium"},
        )


if __name__ == "__main__":
    unittest.main()
