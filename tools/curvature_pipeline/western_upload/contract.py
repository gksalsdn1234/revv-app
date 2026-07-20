from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Final, override

from pydantic import TypeAdapter, ValidationError

from .model import UploadDocument, ValidatedManifest

EXPECTED_PROJECT_REF: Final = "zvwgnduuumksuqazpvsf"
MAX_MANIFEST_BYTES: Final = 10 * 1024 * 1024
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9._:-]{7,95}$")
_SAFE_ROUTE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{7,191}$")
_SAFE_HUB_ID = re.compile(r"^[a-z0-9][a-z0-9._:-]{1,95}$")
_QUOTAS: Final = {
    "pilot": (24, 50, {"BC": 8, "AB": 8, "SK": 4, "MB": 4}, 6, 12),
    "expansion": (96, 200, {"BC": 32, "AB": 32, "SK": 16, "MB": 16}, 10, 48),
}


@dataclass(frozen=True, slots=True)
class RevvUploadError(RuntimeError):
    code: str
    detail: str

    @override
    def __str__(self) -> str:
        return f"{self.code}: {self.detail}"


def load_manifest(
    path: str | Path,
    supplied_checksum: str,
    project_ref: str,
    batch_id: str,
) -> ValidatedManifest:
    manifest_path = Path(path)
    _validate_invocation(manifest_path, supplied_checksum, project_ref, batch_id)
    try:
        size = manifest_path.stat().st_size
    except OSError as error:
        raise RevvUploadError(
            "manifest_read", "manifest must be a readable regular file"
        ) from error
    if (
        not manifest_path.is_file()
        or manifest_path.is_symlink()
        or size > MAX_MANIFEST_BYTES
    ):
        raise RevvUploadError(
            "manifest_size", "manifest must be a regular file no larger than 10 MB"
        )
    try:
        payload = manifest_path.read_bytes()
    except OSError as error:
        raise RevvUploadError("manifest_read", "manifest could not be read") from error
    actual_checksum = hashlib.sha256(payload).hexdigest()
    if actual_checksum != supplied_checksum:
        raise RevvUploadError(
            "checksum_mismatch", "supplied checksum does not cover manifest bytes"
        )
    try:
        document = TypeAdapter(UploadDocument).validate_json(payload)
    except ValidationError as error:
        raise RevvUploadError(
            "invalid_manifest", "manifest does not match revv-western-upload-v1"
        ) from error
    _validate_document(document, project_ref, batch_id)
    program_route_count = sum(len(item.route_ids) for item in document.program_batches)
    return ValidatedManifest(
        document=document,
        manifest_sha256=actual_checksum,
        route_ids_sha256=route_ids_sha256(document.route_ids),
        program_route_count=program_route_count,
    )


def route_ids_sha256(route_ids: tuple[str, ...]) -> str:
    framed = "\n".join(f"{len(route_id)}:{route_id}" for route_id in sorted(route_ids))
    return hashlib.sha256(framed.encode()).hexdigest()


def _validate_invocation(
    path: Path, checksum: str, project_ref: str, batch_id: str
) -> None:
    if ".." in path.parts:
        raise RevvUploadError(
            "unsafe_path", "manifest paths cannot traverse parent directories"
        )
    if project_ref != EXPECTED_PROJECT_REF:
        raise RevvUploadError(
            "wrong_project", "uploads are allowlisted to the Revv project"
        )
    if not _SHA256.fullmatch(checksum):
        raise RevvUploadError("invalid_checksum", "checksum must be lowercase SHA-256")
    if not _SAFE_ID.fullmatch(batch_id) or any(
        token in batch_id for token in ("*", "%", "?")
    ):
        raise RevvUploadError("invalid_batch", "an exact safe batch id is required")


def _validate_document(
    document: UploadDocument, project_ref: str, batch_id: str
) -> None:
    if document.project_ref != project_ref or document.batch_id != batch_id:
        raise RevvUploadError(
            "manifest_identity",
            "project and batch must exactly match explicit arguments",
        )
    expected_prefix = (
        "west-pilot-v1-" if document.cohort_kind == "pilot" else "west-expand-v1-"
    )
    if not document.batch_id.startswith(expected_prefix):
        raise RevvUploadError("batch_kind", "batch id does not match cohort kind")
    route_ids = tuple(route.id for route in document.routes)
    if len(set(route_ids)) != len(route_ids) or tuple(sorted(route_ids)) != tuple(
        sorted(document.route_ids)
    ):
        raise RevvUploadError(
            "route_ids", "route payload ids must exactly equal unique manifest ids"
        )
    _validate_quota(document)
    _validate_program(document)
    _validate_provenance(document)
    _validate_payload_boundaries(document)


def _validate_quota(document: UploadDocument) -> None:
    minimum, maximum, floors, min_hubs, min_cells = _QUOTAS[document.cohort_kind]
    count = len(document.route_ids)
    actual_provinces = Counter(route.province_code for route in document.routes)
    actual_hubs = Counter(route.source_hub_id for route in document.routes)
    actual_cells = {route.geohash4 for route in document.routes}
    if not minimum <= count <= maximum:
        raise RevvUploadError(
            "cohort_size", "cohort route count is outside its immutable range"
        )
    if dict(actual_provinces) != document.province_counts or any(
        actual_provinces[code] < floor for code, floor in floors.items()
    ):
        raise RevvUploadError(
            "province_distribution",
            "province counts do not meet the selected cohort contract",
        )
    if (
        dict(actual_hubs) != document.hub_counts
        or len(actual_hubs) < min_hubs
        or any(value > 25 for value in actual_hubs.values())
    ):
        raise RevvUploadError(
            "hub_distribution", "hub counts do not meet the selected cohort contract"
        )
    if actual_cells != set(document.geohash4_cells) or len(actual_cells) < min_cells:
        raise RevvUploadError(
            "cell_distribution",
            "geohash4 coverage does not meet the selected cohort contract",
        )


def _validate_program(document: UploadDocument) -> None:
    batches = document.program_batches
    complete = document.expansion_deferred is None and len(batches) == 2
    pilot_only = document.expansion_deferred is True and len(batches) == 1
    expected_kinds = {"pilot", "expansion"} if complete else {"pilot"}
    if (
        not (complete or pilot_only)
        or {item.cohort_kind for item in batches} != expected_kinds
        or (pilot_only and document.cohort_kind != "pilot")
    ):
        raise RevvUploadError(
            "program_shape",
            "program must be complete or explicitly defer expansion from a pilot",
        )
    all_ids = [route_id for item in batches for route_id in item.route_ids]
    minimum, maximum = (120, 250) if complete else _QUOTAS["pilot"][:2]
    if len(all_ids) != len(set(all_ids)) or not minimum <= len(all_ids) <= maximum:
        raise RevvUploadError(
            "program_size", "program route count is outside its immutable range"
        )
    for item in batches:
        minimum, maximum, _, _, _ = _QUOTAS[item.cohort_kind]
        expected_prefix = (
            "west-pilot-v1-" if item.cohort_kind == "pilot" else "west-expand-v1-"
        )
        if (
            not minimum <= len(item.route_ids) <= maximum
            or not item.batch_id.startswith(expected_prefix)
            or not _SAFE_ID.fullmatch(item.batch_id)
            or any(
                _SAFE_ROUTE_ID.fullmatch(route_id) is None
                for route_id in item.route_ids
            )
        ):
            raise RevvUploadError(
                "program_batch",
                "each program batch must satisfy its immutable identity and size",
            )
    current = [item for item in batches if item.batch_id == document.batch_id]
    if (
        len(current) != 1
        or current[0].cohort_kind != document.cohort_kind
        or set(current[0].route_ids) != set(document.route_ids)
    ):
        raise RevvUploadError(
            "program_identity", "current cohort must exactly match its program entry"
        )


def _validate_provenance(document: UploadDocument) -> None:
    sources = {source.hub_id: source for source in document.sources}
    if len(sources) != len(document.sources) or set(sources) != set(
        document.hub_counts
    ):
        raise RevvUploadError(
            "source_manifest", "each selected hub requires exactly one source row"
        )
    for route in document.routes:
        source = sources[route.source_hub_id]
        provenance = route.generation_provenance
        valid = (
            route.generation_batch_id == document.batch_id
            and source.province_code == route.province_code
            and source.source_pbf_sha256 == route.source_pbf_sha256
            and source.source_graph_sha256 == route.source_graph_sha256
            and provenance.province_codes == (route.province_code,)
            and provenance.source_hub_id == route.source_hub_id
            and _SHA256.fullmatch(provenance.guidance_receipt_sha256) is not None
            and _SHA256.fullmatch(route.source_pbf_sha256) is not None
            and _SHA256.fullmatch(route.source_graph_sha256) is not None
        )
        if not valid:
            raise RevvUploadError(
                "provenance_mismatch",
                f"route {route.id} does not match its exact shadow source",
            )


def _validate_payload_boundaries(document: UploadDocument) -> None:
    if not 1 <= len(document.generator_version) <= 96:
        raise RevvUploadError("generator_version", "generator version must be bounded")
    for source in document.sources:
        if (
            _SAFE_HUB_ID.fullmatch(source.hub_id) is None
            or not 1 <= len(source.source_snapshot) <= 160
        ):
            raise RevvUploadError(
                "source_identity", "source hub and snapshot must be bounded safe values"
            )
    for route in document.routes:
        nodes_size = len(
            json.dumps(
                [node.model_dump(mode="json") for node in route.nodes],
                separators=(",", ":"),
                allow_nan=False,
            ).encode()
        )
        if (
            _SAFE_ROUTE_ID.fullmatch(route.id) is None
            or _SAFE_HUB_ID.fullmatch(route.source_hub_id) is None
            or re.fullmatch(r"[0-9a-z]{4}", route.geohash4) is None
            or nodes_size > 512 * 1024
            or route.quality_reject_reason is not None
        ):
            raise RevvUploadError(
                "route_boundary",
                "route id, hub, geohash, or geometry exceeds the upload contract",
            )
