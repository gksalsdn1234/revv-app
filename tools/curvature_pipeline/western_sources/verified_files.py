from __future__ import annotations

import hashlib
from pathlib import Path
from typing import ClassVar, Literal

from pydantic import BaseModel, ConfigDict, Field

from .deadline import enforce_deadline


class ChecksumExpectation(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    size_bytes: int | None = Field(default=None, gt=0)
    checksum: str
    algorithm: Literal["md5", "sha256"]
    deadline_monotonic: float


def verified_file(path: Path, expectation: ChecksumExpectation) -> bool:
    enforce_deadline(expectation.deadline_monotonic)
    if not path.is_file():
        return False
    if (
        expectation.size_bytes is not None
        and path.stat().st_size != expectation.size_bytes
    ):
        return False
    return (
        file_checksum(
            path,
            expectation.algorithm,
            expectation.deadline_monotonic,
        )
        == expectation.checksum
    )


def file_checksum(
    path: Path,
    algorithm: Literal["md5", "sha256"],
    deadline_monotonic: float,
) -> str:
    enforce_deadline(deadline_monotonic)
    digest = hashlib.new(algorithm, usedforsecurity=False)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            enforce_deadline(deadline_monotonic)
            digest.update(chunk)
    enforce_deadline(deadline_monotonic)
    return digest.hexdigest()
