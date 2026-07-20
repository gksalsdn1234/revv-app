import json
import re
import unittest
from pathlib import Path

from tools.curvature_pipeline.western_sources.manifest import load_manifest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "tools" / "curvature_pipeline" / "western_sources"


class WesternSourceDeclarationsTest(unittest.TestCase):
    def test_production_manifest_pins_four_official_snapshots(self) -> None:
        manifest = load_manifest(SOURCE_ROOT / "manifests" / "western-2026-07-15.json")
        actual = {
            source.province_code: (source.checksum, source.size_bytes)
            for source in manifest.sources
        }
        self.assertEqual(
            actual,
            {
                "AB": ("0cfb0454c4e853ab319647398d2a5c0e", 345640483),
                "BC": ("66f5a2b2d63a4442890cdfbe8d7bef86", 1242530007),
                "MB": ("f0601216f850fb9a3515b9e9483ea822", 206162578),
                "SK": ("7b3a687a74e45feae57202023319385e", 115544832),
            },
        )
        self.assertGreaterEqual(len(manifest.hubs), 10)

    def test_runtime_policy_and_container_use_exact_versions(self) -> None:
        policy = json.loads((SOURCE_ROOT / "runtime-policy.json").read_text())
        container = (SOURCE_ROOT / "Containerfile").read_text()
        self.assertEqual(
            policy["container_budget"],
            {
                "cpu_count": 4,
                "memory_bytes": 2147483648,
                "disk_bytes": 21474836480,
                "elapsed_seconds": 14400,
            },
        )
        self.assertEqual(
            policy["source_budget"],
            {
                "asset_count": 8,
                "attempt_count": 16,
                "elapsed_seconds": 1800,
                "paid_sources": 0,
            },
        )
        for declaration in (
            policy["python_image"],
            policy["uv_image"],
            "ARG OSMIUM_TOOL_VERSION=1.19.0",
            "ARG OSMIUM_TOOL_SHA256=70e77f69b671528a99b1b01ce6de3e834e3170b20e4c38f4b52ceb4b0eba7263",
            "https://api.github.com/repos/osmcode/osmium-tool/tarball/v${OSMIUM_TOOL_VERSION}",
            "uv pip install --system --no-cache --require-hashes",
        ):
            self.assertIn(declaration, container)

    def test_every_locked_distribution_has_hashes(self) -> None:
        lock = (SOURCE_ROOT / "requirements-western.lock").read_text()
        lines = lock.splitlines()
        package_starts = [
            (index, line.split("==", 1)[0])
            for index, line in enumerate(lines)
            if re.match(r"^[a-z0-9][a-z0-9._-]*==[^ ]+", line) and line.endswith(" \\")
        ]
        self.assertGreaterEqual(len(package_starts), 30)
        for index, (line_number, package_name) in enumerate(package_starts):
            end = (
                package_starts[index + 1][0]
                if index + 1 < len(package_starts)
                else len(lines)
            )
            self.assertIn(
                "--hash=sha256:", "\n".join(lines[line_number:end]), package_name
            )
        for pinned in (
            "networkx==3.6.1",
            "osmium==4.3.1",
            "pip-tools==7.5.3",
            "httpx2==2.7.0",
        ):
            self.assertIn(pinned, lock)

    def test_container_configures_osmium_before_building(self) -> None:
        container = (SOURCE_ROOT / "Containerfile").read_text()
        self.assertIn(
            "cmake -S osmium-tool-source -B build-output -DCMAKE_BUILD_TYPE=Release",
            container,
        )
        self.assertNotIn(
            "cmake --source osmium-tool-source --build build-output", container
        )

    def test_container_pins_supported_libosmium_headers(self) -> None:
        container = (SOURCE_ROOT / "Containerfile").read_text()
        for declaration in (
            "ARG LIBOSMIUM_VERSION=2.20.0",
            "ARG LIBOSMIUM_SHA256=b68afee19b3fd6a75030ac8a95f6da2268579efe86b32ad736d22caeee41a8e7",
            "https://api.github.com/repos/osmcode/libosmium/tarball/v${LIBOSMIUM_VERSION}",
            "libprotozero-dev",
            "cp -R libosmium-source/include/osmium /usr/local/include/",
        ):
            self.assertIn(declaration, container)
        self.assertNotIn("libosmium2-dev", container)

    def test_container_declares_osmium_tool_build_dependencies(self) -> None:
        container = (SOURCE_ROOT / "Containerfile").read_text()
        self.assertIn("nlohmann-json3-dev", container)

    def test_container_builds_within_two_gibibytes(self) -> None:
        container = (SOURCE_ROOT / "Containerfile").read_text()
        self.assertIn("-DBUILD_TESTING=OFF", container)
        self.assertIn("cmake --build build-output --parallel 1", container)
        self.assertNotIn("cmake --build build-output --parallel 4", container)

    def test_license_policy_blocks_unlicensed_seed_reuse(self) -> None:
        policy = (SOURCE_ROOT / "LICENSE_POLICY.md").read_text()
        self.assertIn("© OpenStreetMap contributors", policy)
        self.assertIn("does not ingest or reuse RoadCurvature KML/KMZ", policy)
        self.assertIn("https://opendatacommons.org/licenses/odbl/1-0/", policy)

    def test_source_tree_contains_no_pbf_data(self) -> None:
        self.assertEqual(list(SOURCE_ROOT.rglob("*.pbf")), [])
        gitignore = (ROOT / ".gitignore").read_text()
        self.assertIn(".pipeline-cache/", gitignore)


if __name__ == "__main__":
    unittest.main()
