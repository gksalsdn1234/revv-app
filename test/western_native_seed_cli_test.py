from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar

from pydantic import BaseModel, ConfigDict

from test.western_seed_fixture import native_seed_graph
from tools.curvature_pipeline.western_graph.codec import write_graph
from tools.curvature_pipeline.western_seeds.input import MAX_GRAPH_INPUT_BYTES


class _CliReceipt(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    candidate_count: int
    rejected_start_count: int
    route_ids: list[str]
    routes_sha256: str
    seed_cluster_count: int
    seed_count: int
    seed_sha256: str
    status: str
    unused_seed_count: int


class WesternNativeSeedCliTest(unittest.TestCase):
    def test_dry_run_writes_stable_seed_and_route_pool_artifacts(self) -> None:
        # Given: a real graph codec artifact and an empty output directory.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            graph_path = root / "graph.json"
            output_path = root / "dry-run"
            write_graph(graph_path, native_seed_graph())
            command = (
                sys.executable,
                "tools/curvature_pipeline/generate_native_route.py",
                str(graph_path),
                str(output_path),
            )

            # When: the offline CLI is rerun against the same graph.
            first = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
            )
            first_seed_bytes = (output_path / "native-seeds.json").read_bytes()
            first_route_bytes = (output_path / "generated-routes.json").read_bytes()
            repeated = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
            )

            # Then: the public receipt and both artifacts remain byte-identical.
            receipt = _CliReceipt.model_validate_json(first.stdout)
            self.assertGreaterEqual(receipt.seed_count, 3)
            self.assertEqual(receipt.status, "ready")
            self.assertEqual(receipt.candidate_count, len(receipt.route_ids))
            self.assertEqual(first.stdout, repeated.stdout)
            self.assertEqual(
                first_seed_bytes,
                (output_path / "native-seeds.json").read_bytes(),
            )
            self.assertEqual(
                first_route_bytes,
                (output_path / "generated-routes.json").read_bytes(),
            )

    def test_oversized_graph_is_rejected_before_unbounded_read(self) -> None:
        # Given: a sparse graph file one byte beyond the public input budget.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            graph_path = root / "oversized.json"
            output_path = root / "out"
            with graph_path.open("wb") as handle:
                _ = handle.truncate(MAX_GRAPH_INPUT_BYTES + 1)

            # When: the CLI receives the oversized graph.
            result = subprocess.run(
                (
                    sys.executable,
                    "tools/curvature_pipeline/generate_native_route.py",
                    str(graph_path),
                    str(output_path),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

            # Then: it fails concisely without reading or publishing the artifact.
            self.assertEqual(result.returncode, 2)
            self.assertLess(len(result.stderr), 200)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse(output_path.exists())

    def test_pair_publish_failure_preserves_existing_output(self) -> None:
        # Given: an existing seed file and an invalid route artifact directory.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            graph_path = root / "graph.json"
            output_path = root / "out"
            output_path.mkdir()
            old_seed = b"existing-seed"
            _ = (output_path / "native-seeds.json").write_bytes(old_seed)
            (output_path / "generated-routes.json").mkdir()
            write_graph(graph_path, native_seed_graph())

            # When: the CLI attempts to publish the pair.
            result = subprocess.run(
                (
                    sys.executable,
                    "tools/curvature_pipeline/generate_native_route.py",
                    str(graph_path),
                    str(output_path),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

            # Then: neither existing artifact changes and no traceback is exposed.
            self.assertEqual(result.returncode, 2)
            self.assertEqual(
                (output_path / "native-seeds.json").read_bytes(),
                old_seed,
            )
            self.assertTrue((output_path / "generated-routes.json").is_dir())
            self.assertLess(len(result.stderr), 200)
            self.assertNotIn("Traceback", result.stderr)

    def test_missing_graph_reports_concise_error(self) -> None:
        # Given: a graph path that does not exist.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            # When: the CLI attempts to load it.
            result = subprocess.run(
                (
                    sys.executable,
                    "tools/curvature_pipeline/generate_native_route.py",
                    str(root / "missing.json"),
                    str(root / "out"),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

            # Then: the error is bounded and contains no Rich traceback or locals.
            self.assertEqual(result.returncode, 2)
            self.assertLess(len(result.stderr), 200)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse((root / "out").exists())


if __name__ == "__main__":
    _ = unittest.main()
