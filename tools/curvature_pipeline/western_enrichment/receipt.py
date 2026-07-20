from __future__ import annotations

import json
from pathlib import Path
from typing import ClassVar

from pydantic import BaseModel, ConfigDict

from .model import RunResult


class EnrichmentReceipt(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    selection_checksum: str
    enrichment_manifest_checksum: str
    result: RunResult


def receipt_bytes(receipt: EnrichmentReceipt) -> bytes:
    return (
        json.dumps(
            receipt.model_dump(mode="json"),
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
        + b"\n"
    )


def write_receipt(path: Path, receipt: EnrichmentReceipt) -> None:
    temporary = path.with_suffix(f"{path.suffix}.tmp")
    _ = temporary.write_bytes(receipt_bytes(receipt))
    _ = temporary.replace(path)
