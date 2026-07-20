from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Literal

from test.western_upload_fixture import PROJECT_REF, write_program_manifests
from tools.curvature_pipeline.western_upload import RevvUploadError, load_manifest
from tools.curvature_pipeline.western_upload.model import Provenance, UploadDocument
from tools.curvature_pipeline.western_upload.store import validate_service_key


class WesternUploadContractTest(unittest.TestCase):
    def test_loads_checksum_covered_pilot_and_expansion(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            pilot_path, pilot_sha, expansion_path, expansion_sha = (
                write_program_manifests(Path(raw_root))
            )

            pilot = load_manifest(
                pilot_path, pilot_sha, PROJECT_REF, "west-pilot-v1-fixture"
            )
            expansion = load_manifest(
                expansion_path, expansion_sha, PROJECT_REF, "west-expand-v1-fixture"
            )

        self.assertEqual(len(pilot.routes), 24)
        self.assertEqual(len(expansion.routes), 96)
        self.assertEqual(pilot.program_route_count, 120)

    def test_loads_explicit_pilot_only_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            pilot_path, _, _, _ = write_program_manifests(Path(raw_root))
            document = UploadDocument.model_validate_json(pilot_path.read_bytes())
            payload = document.model_dump(mode="json")
            payload["expansion_deferred"] = True
            payload["program_batches"] = payload["program_batches"][:1]
            body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
            _ = pilot_path.write_bytes(body)

            pilot = load_manifest(
                pilot_path,
                hashlib.sha256(body).hexdigest(),
                PROJECT_REF,
                "west-pilot-v1-fixture",
            )

        self.assertEqual(pilot.cohort_kind, "pilot")
        self.assertTrue(pilot.expansion_deferred)
        self.assertEqual(pilot.program_route_count, 24)

    def test_rejects_supplied_expansion_when_marked_deferred(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            pilot_path, _, _, _ = write_program_manifests(Path(raw_root))
            document = UploadDocument.model_validate_json(pilot_path.read_bytes())
            payload = document.model_dump(mode="json")
            payload["expansion_deferred"] = True
            payload["program_batches"][1]["route_ids"] = []
            body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
            _ = pilot_path.write_bytes(body)

            with self.assertRaisesRegex(RevvUploadError, "program_shape"):
                _ = load_manifest(
                    pilot_path,
                    hashlib.sha256(body).hexdigest(),
                    PROJECT_REF,
                    "west-pilot-v1-fixture",
                )

    def test_rejects_changed_or_truncated_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            pilot_path, pilot_sha, _, _ = write_program_manifests(Path(raw_root))
            _ = pilot_path.write_bytes(pilot_path.read_bytes()[:-1])

            with self.assertRaisesRegex(RevvUploadError, "checksum_mismatch"):
                _ = load_manifest(
                    pilot_path, pilot_sha, PROJECT_REF, "west-pilot-v1-fixture"
                )

    def test_rejects_wrong_project_batch_and_wildcard_pre_parse(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            pilot_path, pilot_sha, _, _ = write_program_manifests(Path(raw_root))

            for project, batch in (
                ("jarvis", "west-pilot-v1-fixture"),
                (PROJECT_REF, "west-*"),
                (PROJECT_REF, "other-batch"),
            ):
                with (
                    self.subTest(project=project, batch=batch),
                    self.assertRaises(RevvUploadError),
                ):
                    _ = load_manifest(pilot_path, pilot_sha, project, batch)

    def test_rejects_path_traversal_and_oversize_before_read(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            root = Path(raw_root)
            unsafe = root / ".." / root.name / "pilot.json"
            pilot_path, pilot_sha, _, _ = write_program_manifests(root)
            self.assertEqual(unsafe.resolve(), pilot_path.resolve())

            with self.assertRaisesRegex(RevvUploadError, "unsafe_path"):
                _ = load_manifest(
                    unsafe, pilot_sha, PROJECT_REF, "west-pilot-v1-fixture"
                )

    def test_rejects_distribution_drift_and_more_than_250_program_routes(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            root = Path(raw_root)
            pilot_path, _, _, _ = write_program_manifests(root)
            document = UploadDocument.model_validate_json(pilot_path.read_bytes())
            expansion = document.program_batches[1].model_copy(
                update={
                    "route_ids": document.program_batches[1].route_ids
                    + tuple(f"extra-{index}" for index in range(131))
                }
            )
            changed = document.model_copy(
                update={
                    "province_counts": {
                        **document.province_counts,
                        "SK": 3,
                        "BC": 9,
                    },
                    "program_batches": (document.program_batches[0], expansion),
                }
            )
            digest = _write_document(pilot_path, changed)

            with self.assertRaises(RevvUploadError):
                _ = load_manifest(
                    pilot_path, digest, PROJECT_REF, "west-pilot-v1-fixture"
                )

    def test_rejects_anon_key_before_client_creation(self) -> None:
        header = base64.urlsafe_b64encode(b'{"alg":"none"}').decode().rstrip("=")
        payload = base64.urlsafe_b64encode(b'{"role":"anon"}').decode().rstrip("=")

        with self.assertRaisesRegex(RevvUploadError, "anon_key"):
            validate_service_key(f"{header}.{payload}.signature")

    def test_rejects_wildcard_route_id_before_network(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            root = Path(raw_root)
            pilot_path, _, _, _ = write_program_manifests(root)
            document = UploadDocument.model_validate_json(pilot_path.read_bytes())
            unsafe_id = "osmgen:v1:*unsafe"
            first_route = document.routes[0].model_copy(update={"id": unsafe_id})
            pilot_program = document.program_batches[0].model_copy(
                update={
                    "route_ids": (unsafe_id, *document.program_batches[0].route_ids[1:])
                }
            )
            changed = document.model_copy(
                update={
                    "route_ids": (unsafe_id, *document.route_ids[1:]),
                    "routes": (first_route, *document.routes[1:]),
                    "program_batches": (pilot_program, document.program_batches[1]),
                }
            )
            digest = _write_document(pilot_path, changed)

            with self.assertRaises(RevvUploadError):
                _ = load_manifest(
                    pilot_path, digest, PROJECT_REF, "west-pilot-v1-fixture"
                )

    def test_legacy_uploader_has_no_dotenv_discovery(self) -> None:
        source = Path("tools/curvature_pipeline/upload_to_supabase.py").read_text()

        self.assertNotIn("dotenv", source)
        self.assertNotIn("candidate_paths", source)
        self.assertNotIn(".worktrees", source)
        self.assertNotIn("_load_local_env", source)

    def test_cli_rejects_161_character_edge_and_seed_ids_before_network(self) -> None:
        for field in ("directed_edge_ids", "source_seed_ids"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as raw_root:
                pilot_path, _, _, _ = write_program_manifests(Path(raw_root))
                document = UploadDocument.model_validate_json(pilot_path.read_bytes())
                changed = _with_evidence_id(document, field, "x" * 161)
                digest = _write_document(pilot_path, changed)
                environment = os.environ.copy()
                _ = environment.pop("SUPABASE_SERVICE_KEY", None)

                result = subprocess.run(
                    [
                        sys.executable,
                        "tools/curvature_pipeline/upload_western_batch.py",
                        "shadow",
                        str(pilot_path),
                        "--project-ref",
                        PROJECT_REF,
                        "--batch-id",
                        "west-pilot-v1-fixture",
                        "--checksum",
                        digest,
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                    env=environment,
                )

                self.assertEqual(result.returncode, 2)
                self.assertIn("invalid_manifest", result.stderr)


def _write_document(path: Path, document: UploadDocument) -> str:
    payload = json.dumps(
        document.model_dump(mode="json"), sort_keys=True, separators=(",", ":")
    ).encode()
    _ = path.write_bytes(payload)
    return hashlib.sha256(payload).hexdigest()


def _with_evidence_id(
    document: UploadDocument,
    field: Literal["directed_edge_ids", "source_seed_ids"],
    evidence_id: str,
) -> UploadDocument:
    first_route = document.routes[0]
    original = first_route.generation_provenance
    if field == "directed_edge_ids":
        directed_edge_ids = (evidence_id,)
        source_seed_ids = original.source_seed_ids
    else:
        directed_edge_ids = original.directed_edge_ids
        source_seed_ids = (evidence_id,)
    provenance = Provenance.model_construct(
        province_codes=original.province_codes,
        source_hub_id=original.source_hub_id,
        directed_edge_ids=directed_edge_ids,
        source_seed_ids=source_seed_ids,
        guidance_receipt_sha256=original.guidance_receipt_sha256,
    )
    changed_route = first_route.model_copy(update={"generation_provenance": provenance})
    return document.model_copy(update={"routes": (changed_route, *document.routes[1:])})


if __name__ == "__main__":
    _ = unittest.main()
