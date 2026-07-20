from __future__ import annotations

import json
import os
from pathlib import Path
from typing import ClassVar

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .manifest import ProvinceCode, WesternManifest, canonical_manifest_digest


class CompletedSource(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    province_code: ProvinceCode
    source_checksum: str = Field(pattern=r"^[0-9a-f]{32}$")


class CompletedHub(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    hub_id: str
    hub_spec_digest: str = Field(pattern=r"^[0-9a-f]{64}$")
    source_checksum: str = Field(pattern=r"^[0-9a-f]{32}$")
    output_checksum: str = Field(pattern=r"^[0-9a-f]{64}$")


class AcquisitionCheckpoint(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    schema_version: int = Field(default=1, ge=1, le=1)
    generator_version: str
    snapshot: str
    manifest_digest: str = Field(pattern=r"^[0-9a-f]{64}$")
    completed_sources: tuple[CompletedSource, ...] = ()
    completed_hubs: tuple[CompletedHub, ...] = ()


def empty_checkpoint(manifest: WesternManifest) -> AcquisitionCheckpoint:
    return AcquisitionCheckpoint(
        generator_version=manifest.generator_version,
        snapshot=manifest.snapshot.isoformat(),
        manifest_digest=canonical_manifest_digest(manifest),
    )


def load_checkpoint(path: Path, manifest: WesternManifest) -> AcquisitionCheckpoint:
    try:
        checkpoint = AcquisitionCheckpoint.model_validate_json(path.read_bytes())
    except FileNotFoundError:
        return empty_checkpoint(manifest)
    except (OSError, ValidationError):
        return empty_checkpoint(manifest)
    if checkpoint.generator_version != manifest.generator_version:
        return empty_checkpoint(manifest)
    if checkpoint.snapshot != manifest.snapshot.isoformat():
        return empty_checkpoint(manifest)
    if checkpoint.manifest_digest != canonical_manifest_digest(manifest):
        return empty_checkpoint(manifest)
    return checkpoint


def save_checkpoint(path: Path, checkpoint: AcquisitionCheckpoint) -> None:
    payload = json.dumps(
        checkpoint.model_dump(mode="json"),
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    temporary = path.with_suffix(".json.part")
    with temporary.open("wb") as handle:
        _ = handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)
