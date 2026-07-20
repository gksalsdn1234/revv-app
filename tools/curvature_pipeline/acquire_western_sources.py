# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "httpx2[http2,brotli,zstd]==2.7.0",
#   "pydantic==2.13.2",
#   "typer==0.21.0",
# ]
# ///

# ─── How to run ───
# uv run tools/curvature_pipeline/acquire_western_sources.py MANIFEST [--workspace PATH] [--dry-run]

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Final

import typer

from tools.curvature_pipeline.western_sources.acquisition import (
    AcquisitionError,
    AcquisitionPaths,
    AcquisitionPolicy,
    run_acquisition,
)
from tools.curvature_pipeline.western_sources.manifest import (
    ManifestError,
    load_manifest,
)

DEFAULT_WORKSPACE: Final = Path(".pipeline-cache/western")


def acquire(
    manifest_path: Path,
    workspace: Path = DEFAULT_WORKSPACE,
    dry_run: bool = False,
) -> None:
    try:
        manifest = load_manifest(manifest_path)
        osmium = Path(shutil.which("osmium") or "osmium")
        receipt = run_acquisition(
            manifest,
            AcquisitionPaths(workspace / "cache", workspace / "outputs", osmium),
            AcquisitionPolicy(dry_run=dry_run),
        )
    except (ManifestError, AcquisitionError) as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(code=1) from error
    typer.echo(receipt.model_dump_json())


if __name__ == "__main__":
    typer.run(acquire)
