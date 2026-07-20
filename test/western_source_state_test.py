import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.curvature_pipeline.western_sources.acquisition import (
    AcquisitionError,
    AcquisitionPaths,
    AcquisitionPolicy,
    run_acquisition,
)
from tools.curvature_pipeline.western_sources.manifest import load_manifest
from test.western_source_fixture import (
    FixtureHandler,
    FixtureServer,
    write_fake_osmium,
    write_fixture_manifest,
)


class WesternSourceStateTest(unittest.TestCase):
    def test_changed_hub_bounds_reject_stale_output_checkpoint(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            paths = AcquisitionPaths(root / "cache", root / "output", osmium_path)
            policy = AcquisitionPolicy(fixture_origin=server.origin)
            _ = run_acquisition(manifest, paths, policy)
            output_path = root / "output" / "ab-fixture.osm.pbf"
            first_output = output_path.read_bytes()
            checkpoint_path = root / "output" / "acquisition-checkpoint.json"
            first_checkpoint = json.loads(checkpoint_path.read_text())

            payload = json.loads(manifest_path.read_text())
            payload["hubs"][0]["bounds"]["max_lat"] = 50.25
            manifest_path.write_text(json.dumps(payload))
            changed_manifest = load_manifest(
                manifest_path,
                fixture_origin=server.origin,
            )
            rerun = run_acquisition(changed_manifest, paths, policy)
            second_checkpoint = json.loads(checkpoint_path.read_text())

            self.assertEqual(rerun.http_attempts, 0)
            self.assertEqual(rerun.cache_hits, 4)
            self.assertNotEqual(output_path.read_bytes(), first_output)
            self.assertNotEqual(
                first_checkpoint.get("manifest_digest"),
                second_checkpoint.get("manifest_digest"),
            )
            self.assertIn("hub_spec_digest", second_checkpoint["completed_hubs"][0])

    def test_source_deadline_interrupts_slow_http_asset(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            FixtureHandler.mode = "slow"
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            started = time.monotonic()
            with (
                patch(
                    "tools.curvature_pipeline.western_sources.acquisition.MAX_ELAPSED_SECONDS",
                    0.05,
                ),
                self.assertRaises(AcquisitionError),
            ):
                _ = run_acquisition(
                    load_manifest(manifest_path, fixture_origin=server.origin),
                    AcquisitionPaths(root / "cache", root / "output", osmium_path),
                    AcquisitionPolicy(fixture_origin=server.origin),
                )
            elapsed = time.monotonic() - started

            self.assertLess(elapsed, 0.15)
            self.assertEqual(list((root / "cache").rglob("*.pbf")), [])

    def test_acquisition_deadline_bounds_osmium_remaining_timeout(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            paths = AcquisitionPaths(root / "cache", root / "output", osmium_path)
            policy = AcquisitionPolicy(
                fixture_origin=server.origin,
                osmium_timeout_seconds=1.0,
            )
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            _ = run_acquisition(manifest, paths, policy)
            payload = json.loads(manifest_path.read_text())
            payload["hubs"][0]["bounds"]["max_lat"] = 50.25
            manifest_path.write_text(json.dumps(payload))
            write_fake_osmium(osmium_path, sleep_seconds=1.0)

            started = time.monotonic()
            with (
                patch(
                    "tools.curvature_pipeline.western_sources.acquisition.MAX_ELAPSED_SECONDS",
                    0.05,
                ),
                self.assertRaises(AcquisitionError),
            ):
                _ = run_acquisition(
                    load_manifest(manifest_path, fixture_origin=server.origin),
                    paths,
                    policy,
                )
            elapsed = time.monotonic() - started

            self.assertLess(elapsed, 0.2)


if __name__ == "__main__":
    unittest.main()
