from __future__ import annotations

import base64
from dataclasses import dataclass
from typing import ClassVar

from pydantic import BaseModel, ConfigDict, TypeAdapter, ValidationError

from supabase import Client, create_client

from .contract import EXPECTED_PROJECT_REF, RevvUploadError
from .model import (
    BatchAudit,
    RouteConflict,
    RoutePayload,
    TargetState,
    TransitionResult,
    ValidatedManifest,
)


class _AuditRow(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore", frozen=True)

    batch_id: str
    status: str
    manifest_sha256: str
    expected_route_count: int
    actual_route_count: int
    route_ids_match: bool
    catalog_epoch: int


class _ConflictRow(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore", frozen=True)

    id: str
    generation_batch_id: str | None


class _TransitionRow(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore", frozen=True)

    batch_id: str
    previous_state: str
    current_state: str
    changed: bool
    catalog_epoch: int


class _JwtClaims(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore", frozen=True)

    role: str


@dataclass(frozen=True, slots=True)
class SupabaseUploadStore:
    client: Client

    def audit_batch(self, batch_id: str) -> BatchAudit | None:
        response = self.client.rpc(
            "admin_audit_route_generation_batch", {"batch_id_input": batch_id}
        ).execute()
        try:
            rows = TypeAdapter(list[_AuditRow]).validate_python(response.data)
        except ValidationError as error:
            raise RevvUploadError(
                "audit_response", "batch audit returned malformed data"
            ) from error
        if not rows:
            return None
        if len(rows) != 1:
            raise RevvUploadError(
                "audit_response", "batch audit must return at most one row"
            )
        row = rows[0]
        return BatchAudit(
            row.batch_id,
            row.status,
            row.manifest_sha256,
            row.expected_route_count,
            row.actual_route_count,
            row.route_ids_match,
            row.catalog_epoch,
        )

    def find_route_conflicts(
        self, route_ids: tuple[str, ...]
    ) -> tuple[RouteConflict, ...]:
        response = (
            self.client.table("curvy_roads")
            .select("id,generation_batch_id")
            .in_("id", list(route_ids))
            .execute()
        )
        try:
            rows = TypeAdapter(list[_ConflictRow]).validate_python(response.data)
        except ValidationError as error:
            raise RevvUploadError(
                "conflict_response", "route preflight returned malformed data"
            ) from error
        return tuple(RouteConflict(row.id, row.generation_batch_id) for row in rows)

    def register_batch(self, manifest: ValidatedManifest) -> None:
        document = manifest.document
        stored_manifest = document.model_dump(mode="json", exclude={"routes"})
        _ = self.client.rpc(
            "admin_register_route_generation_batch",
            {
                "batch_id_input": document.batch_id,
                "cohort_kind_input": document.cohort_kind,
                "generator_version_input": document.generator_version,
                "manifest_sha256_input": manifest.manifest_sha256,
                "route_ids_sha256_input": manifest.route_ids_sha256,
                "expected_route_count_input": len(document.route_ids),
                "manifest_input": stored_manifest,
                "sources_input": [
                    source.model_dump(mode="json") for source in document.sources
                ],
            },
        ).execute()

    def upsert_routes(self, rows: tuple[RoutePayload, ...]) -> None:
        payload = [row.model_dump(mode="json", exclude_none=True) for row in rows]
        _ = self.client.table("curvy_roads").upsert(payload, on_conflict="id").execute()

    def transition(
        self, batch_id: str, manifest_sha256: str, target_state: TargetState
    ) -> TransitionResult:
        response = self.client.rpc(
            "admin_transition_route_batch",
            {
                "batch_id_input": batch_id,
                "manifest_sha256_input": manifest_sha256,
                "target_state_input": target_state,
            },
        ).execute()
        try:
            rows = TypeAdapter(list[_TransitionRow]).validate_python(response.data)
        except ValidationError as error:
            raise RevvUploadError(
                "transition_response", "transition returned malformed data"
            ) from error
        if len(rows) != 1:
            raise RevvUploadError(
                "transition_response", "transition must return one whole-batch receipt"
            )
        row = rows[0]
        return TransitionResult(
            row.batch_id,
            row.previous_state,
            row.current_state,
            row.changed,
            row.catalog_epoch,
        )


def create_revv_store(project_ref: str, service_key: str) -> SupabaseUploadStore:
    if project_ref != EXPECTED_PROJECT_REF:
        raise RevvUploadError(
            "wrong_project", "uploads are allowlisted to the Revv project"
        )
    validate_service_key(service_key)
    return SupabaseUploadStore(
        create_client(f"https://{EXPECTED_PROJECT_REF}.supabase.co", service_key)
    )


def validate_service_key(service_key: str) -> None:
    key = service_key.strip()
    if not key:
        raise RevvUploadError(
            "missing_service_key", "SUPABASE_SERVICE_KEY is required only with --apply"
        )
    if key.startswith("sb_secret_") and len(key) >= 32:
        return
    parts = key.split(".")
    if len(parts) != 3:
        raise RevvUploadError(
            "invalid_service_key", "apply requires a service-role or secret key"
        )
    try:
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = TypeAdapter(_JwtClaims).validate_json(base64.urlsafe_b64decode(padded))
    except (ValueError, ValidationError) as error:
        raise RevvUploadError(
            "invalid_service_key", "apply requires a valid service-role key"
        ) from error
    if claims.role != "service_role":
        raise RevvUploadError(
            "anon_key", "anonymous and publishable keys cannot upload route batches"
        )
