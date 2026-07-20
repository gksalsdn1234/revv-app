from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from typing import final

from test.western_upload_fixture import PROJECT_REF, write_program_manifests
from tools.curvature_pipeline.western_upload import (
    BatchAudit,
    RevvUploadError,
    RouteConflict,
    TransitionResult,
    execute_shadow,
    execute_transition,
    load_manifest,
    request_chunks,
)
from tools.curvature_pipeline.western_upload.model import (
    RoutePayload,
    TargetState,
    ValidatedManifest,
)


@final
class FakeStore:
    def __init__(self) -> None:
        self.audit: BatchAudit | None = None
        self.conflicts: tuple[RouteConflict, ...] = ()
        self.register_count = 0
        self.upsert_batches: list[int] = []
        self.status = "shadow"
        self.epoch = 0

    def audit_batch(self, batch_id: str) -> BatchAudit | None:
        _ = batch_id
        return self.audit

    def find_route_conflicts(
        self, route_ids: tuple[str, ...]
    ) -> tuple[RouteConflict, ...]:
        _ = route_ids
        return self.conflicts

    def register_batch(self, manifest: ValidatedManifest) -> None:
        self.register_count += 1
        self.audit = BatchAudit(
            manifest.batch_id,
            "shadow",
            manifest.manifest_sha256,
            len(manifest.routes),
            0,
            False,
            self.epoch,
        )

    def upsert_routes(self, rows: tuple[RoutePayload, ...]) -> None:
        self.upsert_batches.append(len(rows))
        if self.audit is not None:
            actual = self.audit.actual_route_count + len(rows)
            self.audit = replace(
                self.audit,
                actual_route_count=actual,
                route_ids_match=actual == self.audit.expected_route_count,
            )

    def transition(
        self,
        batch_id: str,
        manifest_sha256: str,
        target_state: TargetState,
    ) -> TransitionResult:
        _ = manifest_sha256
        if self.status == "disabled" and target_state == "active":
            raise RevvUploadError(
                "invalid_transition", "disabled batches cannot reactivate"
            )
        if self.status == target_state:
            return TransitionResult(
                batch_id, self.status, self.status, False, self.epoch
            )
        previous = self.status
        self.status = target_state
        self.epoch += 1
        return TransitionResult(batch_id, previous, target_state, True, self.epoch)


class WesternUploadLifecycleTest(unittest.TestCase):
    def test_default_dry_run_makes_no_store_calls(self) -> None:
        manifest = self._pilot()
        store = FakeStore()

        receipt = execute_shadow(manifest, store, apply=False)

        self.assertFalse(receipt.applied)
        self.assertEqual(store.register_count, 0)
        self.assertEqual(store.upsert_batches, [])

    def test_shadow_upload_chunks_at_100_and_identical_rerun_changes_zero(self) -> None:
        manifest = self._pilot()
        store = FakeStore()

        first = execute_shadow(manifest, store, apply=True)
        store.audit = BatchAudit(
            manifest.batch_id, "shadow", manifest.manifest_sha256, 24, 24, True, 0
        )
        second = execute_shadow(manifest, store, apply=True)

        self.assertTrue(first.changed)
        self.assertEqual(store.upsert_batches, [24])
        self.assertFalse(second.changed)
        self.assertEqual(store.register_count, 1)

    def test_changed_payload_and_cross_batch_route_conflict_fail_closed(self) -> None:
        manifest = self._pilot()
        store = FakeStore()
        store.audit = BatchAudit(manifest.batch_id, "shadow", "0" * 64, 24, 24, True, 0)

        with self.assertRaisesRegex(RevvUploadError, "changed_payload"):
            _ = execute_shadow(manifest, store, apply=True)

        store.audit = None
        store.conflicts = (RouteConflict(manifest.route_ids[0], "another-batch"),)
        with self.assertRaisesRegex(RevvUploadError, "route_conflict"):
            _ = execute_shadow(manifest, store, apply=True)

    def test_whole_batch_transition_is_idempotent_and_epoch_changes_once(self) -> None:
        manifest = self._pilot()
        store = FakeStore()

        activated = execute_transition(manifest, store, "active", apply=True)
        active_noop = execute_transition(manifest, store, "active", apply=True)
        disabled = execute_transition(manifest, store, "disabled", apply=True)

        self.assertTrue(activated.changed)
        self.assertFalse(active_noop.changed)
        self.assertTrue(disabled.changed)
        self.assertEqual(
            (
                activated.catalog_epoch,
                active_noop.catalog_epoch,
                disabled.catalog_epoch,
            ),
            (1, 1, 2),
        )
        with self.assertRaisesRegex(RevvUploadError, "invalid_transition"):
            _ = execute_transition(manifest, store, "active", apply=True)

    def test_preflight_rejects_request_over_ten_megabytes(self) -> None:
        manifest = self._pilot()
        large_route = manifest.routes[0].model_copy(update={"name": "x" * 10_600_000})
        large_document = manifest.document.model_copy(
            update={"routes": (large_route, *manifest.routes[1:])}
        )
        oversized = replace(manifest, document=large_document)

        with self.assertRaisesRegex(RevvUploadError, "request_size"):
            _ = execute_shadow(oversized, FakeStore(), apply=False)

    def test_request_planner_never_exceeds_one_hundred_rows(self) -> None:
        manifest = self._pilot()
        routes = tuple(
            manifest.routes[0].model_copy(update={"id": f"osmgen:v1:chunk-{index:03d}"})
            for index in range(101)
        )

        chunks = request_chunks(routes)

        self.assertEqual(tuple(len(chunk) for chunk in chunks), (100, 1))

    def _pilot(self) -> ValidatedManifest:
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        pilot_path, pilot_sha, _, _ = write_program_manifests(Path(root.name))
        return load_manifest(
            pilot_path, pilot_sha, PROJECT_REF, "west-pilot-v1-fixture"
        )


if __name__ == "__main__":
    _ = unittest.main()
