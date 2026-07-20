from __future__ import annotations

import os
from pathlib import Path
from typing import ClassVar, final

import httpx2
from pydantic import BaseModel, ConfigDict

from .deadline import enforce_deadline
from .http_io import DownloadRequest, HttpSettings, download
from .manifest import Source
from .verified_files import file_checksum

CHECKSUM_RECEIPT_BYTES = 256


@final
class SourceDownloadError(RuntimeError):
    pass


class SourceDownload(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    source: Source
    cache_path: Path
    deadline_monotonic: float


def download_source(client: httpx2.Client, task: SourceDownload) -> int:
    receipt_path = task.cache_path.with_suffix(".md5.part")
    payload_path = task.cache_path.with_suffix(".osm.pbf.part")
    receipt_path.unlink(missing_ok=True)
    payload_path.unlink(missing_ok=True)
    attempts = 0
    try:
        receipt = download(
            client,
            DownloadRequest(
                url=task.source.checksum_url,
                destination=receipt_path,
                max_bytes=CHECKSUM_RECEIPT_BYTES,
                deadline_monotonic=task.deadline_monotonic,
            ),
            HttpSettings(),
        )
        attempts += receipt.attempts
        _verify_checksum_receipt(receipt_path, task.source)
        enforce_deadline(task.deadline_monotonic)
        payload = download(
            client,
            DownloadRequest(
                url=task.source.url,
                destination=payload_path,
                max_bytes=task.source.size_bytes,
                deadline_monotonic=task.deadline_monotonic,
            ),
            HttpSettings(),
        )
        attempts += payload.attempts
        if payload.bytes_written != task.source.size_bytes:
            raise SourceDownloadError("source byte count does not match manifest")
        if (
            file_checksum(payload_path, "md5", task.deadline_monotonic)
            != task.source.checksum
        ):
            raise SourceDownloadError("source checksum does not match manifest")
        enforce_deadline(task.deadline_monotonic)
        os.replace(payload_path, task.cache_path)
        enforce_deadline(task.deadline_monotonic)
        return attempts
    finally:
        receipt_path.unlink(missing_ok=True)
        payload_path.unlink(missing_ok=True)


def _verify_checksum_receipt(path: Path, source: Source) -> None:
    fields = path.read_text(encoding="ascii").strip().split()
    if fields != [source.checksum, source.filename]:
        raise SourceDownloadError("checksum receipt does not match manifest")
