from __future__ import annotations

import time
from pathlib import Path
from typing import ClassVar, NamedTuple, final

from pydantic import BaseModel, ConfigDict, Field

from .checkpoint import (
    AcquisitionCheckpoint,
    CompletedHub,
    CompletedSource,
    load_checkpoint,
    save_checkpoint,
)
from .deadline import DeadlineExceeded, enforce_deadline
from .http_io import HttpSettings, HttpTransferError, create_client
from .manifest import (
    Source,
    WesternManifest,
    canonical_hub_spec_digest,
)
from .osmium_runner import OsmiumError, OsmiumExtraction, OsmiumRunner
from .source_download import SourceDownload, SourceDownloadError, download_source
from .verified_files import ChecksumExpectation, file_checksum, verified_file

MAX_HTTP_ATTEMPTS = 16
MAX_ELAPSED_SECONDS = 30 * 60


@final
class AcquisitionError(RuntimeError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(f"western source acquisition failed: {detail}")


class AcquisitionPaths(NamedTuple):
    cache_dir: Path
    output_dir: Path
    osmium_path: Path


class AcquisitionPolicy(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    fixture_origin: str | None = None
    dry_run: bool = False
    osmium_timeout_seconds: float = Field(default=300.0, gt=0, le=300.0)


class AcquisitionReceipt(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    generator_version: str
    snapshot: str
    dry_run: bool
    complete: bool
    http_attempts: int
    cache_hits: int
    source_count: int
    hub_count: int
    elapsed_seconds: float


def run_acquisition(
    manifest: WesternManifest,
    paths: AcquisitionPaths,
    policy: AcquisitionPolicy,
) -> AcquisitionReceipt:
    started = time.monotonic()
    deadline = started + MAX_ELAPSED_SECONDS
    if policy.dry_run:
        return AcquisitionReceipt(
            generator_version=manifest.generator_version,
            snapshot=manifest.snapshot.isoformat(),
            dry_run=True,
            complete=False,
            http_attempts=0,
            cache_hits=0,
            source_count=len(manifest.sources),
            hub_count=len(manifest.hubs),
            elapsed_seconds=round(time.monotonic() - started, 6),
        )

    runner = OsmiumRunner(
        executable=paths.osmium_path,
        timeout_seconds=policy.osmium_timeout_seconds,
        use_streaming_extract=policy.fixture_origin is None,
    )
    try:
        _ = runner.validate_installation(deadline)
    except (DeadlineExceeded, OsmiumError) as error:
        raise AcquisitionError(str(error)) from error

    paths.cache_dir.mkdir(parents=True, exist_ok=True)
    paths.output_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_path = paths.output_dir / "acquisition-checkpoint.json"
    checkpoint = load_checkpoint(checkpoint_path, manifest)
    attempts = 0
    cache_hits = 0

    try:
        with create_client(HttpSettings()) as client:
            for source in manifest.sources:
                enforce_deadline(deadline)
                cache_path = paths.cache_dir / "md5" / f"{source.checksum}.osm.pbf"
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                if verified_file(
                    cache_path,
                    ChecksumExpectation(
                        size_bytes=source.size_bytes,
                        checksum=source.checksum,
                        algorithm="md5",
                        deadline_monotonic=deadline,
                    ),
                ):
                    cache_hits += 1
                else:
                    cache_path.unlink(missing_ok=True)
                    source_attempts = download_source(
                        client,
                        SourceDownload(
                            source=source,
                            cache_path=cache_path,
                            deadline_monotonic=deadline,
                        ),
                    )
                    attempts += source_attempts
                    if attempts > MAX_HTTP_ATTEMPTS:
                        raise AcquisitionError("HTTP attempt budget exceeded")
                checkpoint = _record_source(checkpoint, source)
                save_checkpoint(checkpoint_path, checkpoint)
                enforce_deadline(deadline)

                for hub in (
                    item
                    for item in manifest.hubs
                    if item.province_code == source.province_code
                ):
                    enforce_deadline(deadline)
                    destination = paths.output_dir / f"{hub.hub_id}.osm.pbf"
                    completed = next(
                        (
                            item
                            for item in checkpoint.completed_hubs
                            if item.hub_id == hub.hub_id
                        ),
                        None,
                    )
                    if (
                        completed is not None
                        and completed.source_checksum == source.checksum
                        and completed.hub_spec_digest == canonical_hub_spec_digest(hub)
                        and verified_file(
                            destination,
                            ChecksumExpectation(
                                checksum=completed.output_checksum,
                                algorithm="sha256",
                                deadline_monotonic=deadline,
                            ),
                        )
                    ):
                        continue
                    runner.extract(
                        OsmiumExtraction(
                            source=cache_path,
                            destination=destination,
                            hub=hub,
                            deadline_monotonic=deadline,
                        )
                    )
                    output_checksum = file_checksum(destination, "sha256", deadline)
                    completed_hub = CompletedHub(
                        hub_id=hub.hub_id,
                        hub_spec_digest=canonical_hub_spec_digest(hub),
                        source_checksum=source.checksum,
                        output_checksum=output_checksum,
                    )
                    checkpoint = _record_hub(checkpoint, completed_hub)
                    save_checkpoint(checkpoint_path, checkpoint)
                    enforce_deadline(deadline)
    except (
        DeadlineExceeded,
        HttpTransferError,
        OsmiumError,
        OSError,
        SourceDownloadError,
        UnicodeError,
    ) as error:
        raise AcquisitionError(str(error)) from error

    try:
        enforce_deadline(deadline)
    except DeadlineExceeded as error:
        raise AcquisitionError(str(error)) from error
    return AcquisitionReceipt(
        generator_version=manifest.generator_version,
        snapshot=manifest.snapshot.isoformat(),
        dry_run=False,
        complete=True,
        http_attempts=attempts,
        cache_hits=cache_hits,
        source_count=len(manifest.sources),
        hub_count=len(manifest.hubs),
        elapsed_seconds=round(time.monotonic() - started, 6),
    )


def _record_source(
    checkpoint: AcquisitionCheckpoint, source: Source
) -> AcquisitionCheckpoint:
    retained = tuple(
        item
        for item in checkpoint.completed_sources
        if item.province_code != source.province_code
    )
    return checkpoint.model_copy(
        update={
            "completed_sources": retained
            + (
                CompletedSource(
                    province_code=source.province_code, source_checksum=source.checksum
                ),
            )
        }
    )


def _record_hub(
    checkpoint: AcquisitionCheckpoint,
    completed: CompletedHub,
) -> AcquisitionCheckpoint:
    retained = tuple(
        item for item in checkpoint.completed_hubs if item.hub_id != completed.hub_id
    )
    return checkpoint.model_copy(update={"completed_hubs": retained + (completed,)})
