from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar, Literal, Self, override

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .model import CandidateKind, EnrichmentManifest, SelectionClass


class SelectionBatch(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")

    activation_eligible: bool
    batch_id: str = Field(min_length=1, max_length=160)
    route_ids: tuple[str, ...] = Field(min_length=1, max_length=200)


class SelectionDocument(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")

    status: Literal["READY"]
    manifests: tuple[SelectionBatch, ...] = Field(min_length=1, max_length=2)

    @model_validator(mode="after")
    def disjoint_batches(self) -> Self:
        route_ids = tuple(
            route_id for batch in self.manifests for route_id in batch.route_ids
        )
        if len(route_ids) != len(set(route_ids)):
            raise SelectionBridgeError("selection batches contain duplicate route ids")
        if not all(batch.activation_eligible for batch in self.manifests):
            raise SelectionBridgeError("selection batch is not activation eligible")
        return self


@dataclass(frozen=True, slots=True)
class BridgeInputs:
    selection_checksum: str
    enrichment_manifest_checksum: str
    manifest: EnrichmentManifest


@dataclass(frozen=True, slots=True)
class SelectionBridgeError(ValueError):
    detail: str

    @override
    def __str__(self) -> str:
        return self.detail


def load_bridge(selection_path: Path, manifest_path: Path) -> BridgeInputs:
    selection_bytes = selection_path.read_bytes()
    manifest_bytes = manifest_path.read_bytes()
    selection = SelectionDocument.model_validate_json(selection_bytes)
    manifest = EnrichmentManifest.model_validate_json(manifest_bytes)
    selection_checksum = hashlib.sha256(selection_bytes).hexdigest()
    if manifest.selection_checksum != selection_checksum:
        raise SelectionBridgeError("selection checksum does not match manifest")
    selected_routes = {
        route.route_id: route
        for route in manifest.routes
        if route.kind is CandidateKind.GENERATED and route.accepted and route.selected
    }
    selected_ids = {
        route_id for batch in selection.manifests for route_id in batch.route_ids
    }
    if selected_ids != set(selected_routes):
        raise SelectionBridgeError(
            "selection route ids do not match generated candidates"
        )
    for batch in selection.manifests:
        expected = _selection_class(batch.batch_id)
        if any(
            selected_routes[route_id].selection is not expected
            for route_id in batch.route_ids
        ):
            raise SelectionBridgeError("selection batch class does not match candidate")
    return BridgeInputs(
        selection_checksum=selection_checksum,
        enrichment_manifest_checksum=hashlib.sha256(manifest_bytes).hexdigest(),
        manifest=manifest,
    )


def _selection_class(batch_id: str) -> SelectionClass:
    if batch_id.startswith("west-pilot-v1-"):
        return SelectionClass.PILOT
    if batch_id.startswith("west-expand-v1-"):
        return SelectionClass.EXPANSION
    raise SelectionBridgeError("selection batch id is not western pilot or expansion")
