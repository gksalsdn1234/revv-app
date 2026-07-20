import json
import tempfile
import unittest
from pathlib import Path

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


class WesternSourceAcquisitionTest(unittest.TestCase):
    def test_local_fixture_then_verified_cache_has_zero_network(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            paths = AcquisitionPaths(root / "cache", root / "output", osmium_path)
            policy = AcquisitionPolicy(fixture_origin=server.origin)

            first = run_acquisition(manifest, paths, policy)
            first_request_count = FixtureHandler.request_count
            second = run_acquisition(manifest, paths, policy)

        self.assertEqual(first.http_attempts, 8)
        self.assertEqual(first_request_count, 8)
        self.assertEqual(FixtureHandler.request_count, first_request_count)
        self.assertEqual(second.cache_hits, 4)
        self.assertEqual(second.http_attempts, 0)

    def test_external_redirect_fails_without_promoted_partial(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            FixtureHandler.mode = "redirect"
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            with self.assertRaises(AcquisitionError):
                run_acquisition(
                    manifest,
                    AcquisitionPaths(root / "cache", root / "output", osmium_path),
                    AcquisitionPolicy(fixture_origin=server.origin),
                )
            self.assertEqual(list((root / "cache").rglob("*.pbf")), [])

    def test_checksum_mismatch_and_oversize_fail_closed(self) -> None:
        for mode, checksum, size in (
            ("ok", "f" * 32, None),
            ("oversize", None, len(FixtureHandler.payload)),
        ):
            with (
                self.subTest(mode=mode),
                FixtureServer() as server,
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                FixtureHandler.mode = mode
                root = Path(temp_dir)
                manifest_path = root / "manifest.json"
                osmium_path = root / "osmium"
                write_fixture_manifest(
                    manifest_path, server.origin, checksum=checksum, size=size
                )
                write_fake_osmium(osmium_path)
                manifest = load_manifest(manifest_path, fixture_origin=server.origin)
                with self.assertRaises(AcquisitionError):
                    run_acquisition(
                        manifest,
                        AcquisitionPaths(root / "cache", root / "output", osmium_path),
                        AcquisitionPolicy(fixture_origin=server.origin),
                    )
                self.assertEqual(list((root / "cache").rglob("*.pbf")), [])

    def test_missing_or_misleading_osmium_fails_nonzero(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            write_fixture_manifest(manifest_path, server.origin)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            for osmium_path in (root / "missing-osmium", root / "lying-osmium"):
                if osmium_path.name == "lying-osmium":
                    write_fake_osmium(osmium_path, create_output=False)
                with (
                    self.subTest(osmium=osmium_path.name),
                    self.assertRaises(AcquisitionError),
                ):
                    run_acquisition(
                        manifest,
                        AcquisitionPaths(
                            root / f"cache-{osmium_path.name}",
                            root / f"output-{osmium_path.name}",
                            osmium_path,
                        ),
                        AcquisitionPolicy(fixture_origin=server.origin),
                    )

    def test_dry_run_performs_no_network_or_filesystem_mutation(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            write_fixture_manifest(manifest_path, server.origin)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            receipt = run_acquisition(
                manifest,
                AcquisitionPaths(
                    root / "cache", root / "output", root / "missing-osmium"
                ),
                AcquisitionPolicy(fixture_origin=server.origin, dry_run=True),
            )
            self.assertEqual(FixtureHandler.request_count, 0)
            self.assertFalse((root / "cache").exists())
            self.assertFalse((root / "output").exists())
            self.assertTrue(receipt.dry_run)

    def test_retry_budget_is_exactly_sixteen_attempts(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            FixtureHandler.mode = "retry_once"
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            receipt = run_acquisition(
                load_manifest(manifest_path, fixture_origin=server.origin),
                AcquisitionPaths(root / "cache", root / "output", osmium_path),
                AcquisitionPolicy(fixture_origin=server.origin),
            )
            self.assertEqual(receipt.http_attempts, 16)
            self.assertEqual(FixtureHandler.request_count, 16)

    def test_interrupted_run_resumes_only_from_valid_checkpoint(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            FixtureHandler.mode = "interrupt-after-ab"
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            paths = AcquisitionPaths(root / "cache", root / "output", osmium_path)
            policy = AcquisitionPolicy(fixture_origin=server.origin)

            with self.assertRaises(AcquisitionError):
                run_acquisition(manifest, paths, policy)
            checkpoint = json.loads(
                (root / "output" / "acquisition-checkpoint.json").read_text()
            )
            self.assertEqual(checkpoint["completed_sources"][0]["province_code"], "AB")
            FixtureHandler.mode = "ok"
            request_count_before_resume = FixtureHandler.request_count
            resumed = run_acquisition(manifest, paths, policy)

            self.assertEqual(resumed.cache_hits, 1)
            self.assertEqual(resumed.http_attempts, 6)
            self.assertEqual(
                FixtureHandler.request_count - request_count_before_resume, 6
            )

    def test_repeated_interruption_never_promotes_partial_cache(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            FixtureHandler.mode = "interrupt"
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            paths = AcquisitionPaths(root / "cache", root / "output", osmium_path)
            policy = AcquisitionPolicy(fixture_origin=server.origin)

            for _ in range(2):
                with self.assertRaises(AcquisitionError):
                    run_acquisition(manifest, paths, policy)
                self.assertEqual(list((root / "cache").rglob("*.pbf")), [])

    def test_corrupt_cache_is_refetched_instead_of_trusted(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path)
            manifest = load_manifest(manifest_path, fixture_origin=server.origin)
            paths = AcquisitionPaths(root / "cache", root / "output", osmium_path)
            policy = AcquisitionPolicy(fixture_origin=server.origin)
            run_acquisition(manifest, paths, policy)
            first_source = manifest.sources[0]
            cached = root / "cache" / "md5" / f"{first_source.checksum}.osm.pbf"
            cached.write_bytes(b"stale")
            requests_before = FixtureHandler.request_count

            repaired = run_acquisition(manifest, paths, policy)

            self.assertEqual(repaired.cache_hits, 3)
            self.assertEqual(repaired.http_attempts, 2)
            self.assertEqual(FixtureHandler.request_count - requests_before, 2)

    def test_hung_osmium_is_terminated_by_timeout(self) -> None:
        with FixtureServer() as server, tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            osmium_path = root / "osmium"
            write_fixture_manifest(manifest_path, server.origin)
            write_fake_osmium(osmium_path, sleep_seconds=1.0)
            with self.assertRaises(AcquisitionError):
                run_acquisition(
                    load_manifest(manifest_path, fixture_origin=server.origin),
                    AcquisitionPaths(root / "cache", root / "output", osmium_path),
                    AcquisitionPolicy(
                        fixture_origin=server.origin, osmium_timeout_seconds=0.05
                    ),
                )


if __name__ == "__main__":
    unittest.main()
