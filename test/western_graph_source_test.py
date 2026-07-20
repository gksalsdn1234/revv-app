from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.curvature_pipeline.western_graph.builder import GraphBuildError
from tools.curvature_pipeline.western_graph.source import spec_from_acquisition
from tools.curvature_pipeline.western_sources.checkpoint import (
    AcquisitionCheckpoint,
    CompletedHub,
    CompletedSource,
)
from tools.curvature_pipeline.western_sources.manifest import (
    canonical_hub_spec_digest,
    canonical_manifest_digest,
    load_manifest,
)
from test.western_source_fixture import write_fixture_manifest


class WesternGraphSourceTest(unittest.TestCase):
    def test_spec_uses_the_exact_manifest_province_and_checkpoint_checksums(self) -> None:
        # Given: a Todo 2 manifest and completed bounded-hub checkpoint.
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest_path = Path(temp_dir) / "manifest.json"
            write_fixture_manifest(manifest_path, "http://127.0.0.1:8080")
            manifest = load_manifest(
                manifest_path,
                fixture_origin="http://127.0.0.1:8080",
            )
            hub = manifest.hubs[0]
            source = manifest.sources[0]
            checkpoint = AcquisitionCheckpoint(
                generator_version=manifest.generator_version,
                snapshot=manifest.snapshot.isoformat(),
                manifest_digest=canonical_manifest_digest(manifest),
                completed_sources=(
                    CompletedSource(
                        province_code=source.province_code,
                        source_checksum=source.checksum,
                    ),
                ),
                completed_hubs=(
                    CompletedHub(
                        hub_id=hub.hub_id,
                        hub_spec_digest=canonical_hub_spec_digest(hub),
                        source_checksum=source.checksum,
                        output_checksum="b" * 64,
                    ),
                ),
            )

            # When: the graph source spec is resolved.
            spec = spec_from_acquisition(manifest, checkpoint, hub.hub_id)

        # Then: one hub, province, provincial PBF, and bounded PBF are pinned.
        self.assertEqual(spec.hub_id, hub.hub_id)
        self.assertEqual(spec.province_code, source.province_code)
        self.assertEqual(spec.source_pbf_checksum, source.checksum)
        self.assertEqual(spec.hub_pbf_checksum, "b" * 64)

    def test_stale_or_cross_province_checkpoint_fails_closed(self) -> None:
        # Given: a manifest with a checkpoint that lies about source provenance.
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest_path = Path(temp_dir) / "manifest.json"
            write_fixture_manifest(manifest_path, "http://127.0.0.1:8080")
            manifest = load_manifest(
                manifest_path,
                fixture_origin="http://127.0.0.1:8080",
            )
            hub = manifest.hubs[0]
            checkpoint = AcquisitionCheckpoint(
                generator_version=manifest.generator_version,
                snapshot=manifest.snapshot.isoformat(),
                manifest_digest=canonical_manifest_digest(manifest),
                completed_hubs=(
                    CompletedHub(
                        hub_id=hub.hub_id,
                        hub_spec_digest=canonical_hub_spec_digest(hub),
                        source_checksum="0" * 32,
                        output_checksum="b" * 64,
                    ),
                ),
            )

            # When/Then: a cross-source join cannot become a graph spec.
            with self.assertRaises(GraphBuildError):
                spec_from_acquisition(manifest, checkpoint, hub.hub_id)


if __name__ == "__main__":
    unittest.main()
