from __future__ import annotations

import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import override


@dataclass(frozen=True, slots=True)
class ArtifactPublishError(RuntimeError):
    detail: str

    @override
    def __str__(self) -> str:
        return f"native route artifact publication failed: {self.detail}"


def publish_artifact_pair(
    output_dir: Path,
    *,
    seeds: bytes,
    routes: bytes,
) -> None:
    expected = {
        "generated-routes.json": routes,
        "native-seeds.json": seeds,
    }
    if output_dir.exists():
        _accept_identical_output(output_dir, expected)
        return
    staging: Path | None = None
    try:
        output_dir.parent.mkdir(parents=True, exist_ok=True)
        staging = Path(
            tempfile.mkdtemp(
                prefix=f".{output_dir.name}.part-",
                dir=output_dir.parent,
            )
        )
        for name, payload in expected.items():
            _write_durable(staging / name, payload)
        _sync_directory(staging)
        os.replace(staging, output_dir)
        staging = None
        _sync_directory(output_dir.parent)
    except OSError as error:
        raise ArtifactPublishError("artifact pair was not published") from error
    finally:
        if staging is not None:
            shutil.rmtree(staging, ignore_errors=True)


def _accept_identical_output(output_dir: Path, expected: dict[str, bytes]) -> None:
    try:
        if not output_dir.is_dir():
            raise ArtifactPublishError("output path is not a directory")
        observed_names = {path.name for path in output_dir.iterdir()}
        if observed_names != set(expected):
            raise ArtifactPublishError("existing artifact set is incomplete")
        for name, payload in expected.items():
            path = output_dir / name
            if not path.is_file() or path.read_bytes() != payload:
                raise ArtifactPublishError("existing artifact bytes differ")
    except OSError as error:
        raise ArtifactPublishError(
            "existing artifacts could not be verified"
        ) from error


def _write_durable(path: Path, payload: bytes) -> None:
    with path.open("xb") as handle:
        _ = handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())


def _sync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
