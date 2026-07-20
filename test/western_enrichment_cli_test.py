from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test.western_enrichment_fixture import (
    make_manifest,
    make_route,
    overpass_payload,
)


class WesternEnrichmentCliTest(unittest.TestCase):
    def test_cli_bridges_selection_manifest_and_writes_deterministic_receipt(
        self,
    ) -> None:
        # Given: a Todo 7 selection document and matching full candidate manifest.
        selection_bytes = json.dumps(
            {
                "manifests": [
                    {
                        "activation_eligible": True,
                        "batch_id": "west-pilot-v1-fixture",
                        "route_ids": ["route-a"],
                    }
                ],
                "status": "READY",
            },
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
        selection_checksum = hashlib.sha256(selection_bytes).hexdigest()
        manifest = make_manifest(
            [make_route("route-a", "calgary", 51.01, -114.01)]
        ).model_copy(update={"selection_checksum": selection_checksum})

        # When: the operator CLI runs twice from fixture evidence.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selection_path = root / "selection.json"
            manifest_path = root / "enrichment.json"
            fixture_path = root / "overpass.json"
            first_state_path = root / "first-state"
            second_state_path = root / "second-state"
            first_path = root / "first.json"
            second_path = root / "second.json"
            selection_path.write_bytes(selection_bytes)
            manifest_path.write_text(manifest.model_dump_json(), encoding="utf-8")
            fixture_path.write_bytes(overpass_payload())
            base_command = [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_enrichment",
                str(selection_path),
                str(manifest_path),
                "--fixture-overpass-response",
                str(fixture_path),
            ]
            first = subprocess.run(
                [
                    *base_command,
                    "--state-dir",
                    str(first_state_path),
                    "--output",
                    str(first_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            second = subprocess.run(
                [
                    *base_command,
                    "--state-dir",
                    str(second_state_path),
                    "--output",
                    str(second_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            first_receipt = first_path.read_bytes()
            second_receipt = second_path.read_bytes()

        # Then: it succeeds without network and emits stable checksum-bound JSON.
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(first_receipt, second_receipt)
        receipt = json.loads(first_receipt)
        self.assertEqual(receipt["selection_checksum"], selection_checksum)
        self.assertEqual(receipt["result"]["status"], "READY")
        self.assertEqual(receipt["result"]["summary"]["attempted"], 1)

    def test_cli_help_is_available_without_credentials(self) -> None:
        # Given/When: the module help surface is invoked without environment secrets.
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_enrichment",
                "--help",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        # Then: usage is available and no credential is requested.
        self.assertEqual(result.returncode, 0)
        self.assertIn("selection_manifest", result.stdout)
        self.assertNotIn("SUPABASE", result.stdout)
