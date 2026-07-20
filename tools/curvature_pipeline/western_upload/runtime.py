from __future__ import annotations

import json
from typing import Final

from .contract import RevvUploadError
from .model import (
    RoutePayload,
    TargetState,
    TransitionReceipt,
    UploadReceipt,
    UploadStore,
    ValidatedManifest,
)

MAX_REQUEST_ROWS: Final = 100
MAX_REQUEST_BYTES: Final = 10 * 1024 * 1024


def execute_shadow(
    manifest: ValidatedManifest, store: UploadStore | None, *, apply: bool = False
) -> UploadReceipt:
    chunks = request_chunks(manifest.routes)
    dry_receipt = UploadReceipt(
        batch_id=manifest.batch_id,
        manifest_sha256=manifest.manifest_sha256,
        route_ids_sha256=manifest.route_ids_sha256,
        route_count=len(manifest.routes),
        request_count=len(chunks),
        applied=False,
        changed=False,
    )
    if not apply:
        return dry_receipt
    if store is None:
        raise RevvUploadError(
            "missing_store", "apply requires an initialized Revv store"
        )
    audit = store.audit_batch(manifest.batch_id)
    if audit is not None:
        if audit.manifest_sha256 != manifest.manifest_sha256:
            raise RevvUploadError(
                "changed_payload",
                "an existing batch id cannot accept changed manifest bytes",
            )
        if audit.route_ids_match and audit.actual_route_count == len(manifest.routes):
            return UploadReceipt(
                batch_id=dry_receipt.batch_id,
                manifest_sha256=dry_receipt.manifest_sha256,
                route_ids_sha256=dry_receipt.route_ids_sha256,
                route_count=dry_receipt.route_count,
                request_count=dry_receipt.request_count,
                applied=True,
                changed=False,
            )
        if audit.status != "shadow":
            raise RevvUploadError(
                "invalid_state", "only an incomplete shadow batch can resume"
            )
    conflicts = store.find_route_conflicts(manifest.route_ids)
    cross_batch = tuple(
        item for item in conflicts if item.generation_batch_id != manifest.batch_id
    )
    if cross_batch:
        raise RevvUploadError(
            "route_conflict", "route ids already belong to another or legacy cohort"
        )
    if audit is None:
        store.register_batch(manifest)
    for chunk in chunks:
        store.upsert_routes(chunk)
    verified = store.audit_batch(manifest.batch_id)
    if (
        verified is None
        or not verified.route_ids_match
        or verified.actual_route_count != len(manifest.routes)
    ):
        raise RevvUploadError(
            "postflight_mismatch",
            "stored shadow cohort does not match the checksum-covered manifest",
        )
    return UploadReceipt(
        batch_id=dry_receipt.batch_id,
        manifest_sha256=dry_receipt.manifest_sha256,
        route_ids_sha256=dry_receipt.route_ids_sha256,
        route_count=dry_receipt.route_count,
        request_count=dry_receipt.request_count,
        applied=True,
        changed=True,
    )


def execute_transition(
    manifest: ValidatedManifest,
    store: UploadStore | None,
    target_state: TargetState,
    *,
    apply: bool = False,
) -> TransitionReceipt:
    if not apply:
        return TransitionReceipt(
            batch_id=manifest.batch_id,
            manifest_sha256=manifest.manifest_sha256,
            target_state=target_state,
            applied=False,
            changed=False,
            previous_state=None,
            current_state=None,
            catalog_epoch=None,
        )
    if store is None:
        raise RevvUploadError(
            "missing_store", "apply requires an initialized Revv store"
        )
    result = store.transition(manifest.batch_id, manifest.manifest_sha256, target_state)
    if result.batch_id != manifest.batch_id or result.current_state != target_state:
        raise RevvUploadError(
            "transition_receipt",
            "database returned a transition receipt for another whole batch",
        )
    return TransitionReceipt(
        batch_id=result.batch_id,
        manifest_sha256=manifest.manifest_sha256,
        target_state=target_state,
        applied=True,
        changed=result.changed,
        previous_state=result.previous_state,
        current_state=result.current_state,
        catalog_epoch=result.catalog_epoch,
    )


def request_chunks(
    routes: tuple[RoutePayload, ...],
) -> tuple[tuple[RoutePayload, ...], ...]:
    chunks: list[tuple[RoutePayload, ...]] = []
    for start in range(0, len(routes), MAX_REQUEST_ROWS):
        chunk = routes[start : start + MAX_REQUEST_ROWS]
        body = json.dumps(
            [route.model_dump(mode="json", exclude_none=True) for route in chunk],
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode()
        if len(body) > MAX_REQUEST_BYTES:
            raise RevvUploadError(
                "request_size", "a bounded 100-row request exceeds 10 MB"
            )
        chunks.append(chunk)
    return tuple(chunks)
