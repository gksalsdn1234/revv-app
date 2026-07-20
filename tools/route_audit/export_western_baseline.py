# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "httpx2[http2,brotli,zstd]>=0.1.0",
#   "pydantic>=2.11,<3",
#   "typer>=0.16,<1",
# ]
# ///
from __future__ import annotations

import os
import secrets
import stat
import sys
from pathlib import Path
from typing import Annotated, Final

import typer

DEFAULT_JSON_OUT: Final = Path("tools/route_audit/output/western_baseline.json")
DEFAULT_SUMMARY_OUT: Final = Path("tools/route_audit/output/western_baseline.txt")
MAX_OUTPUT_BYTES: Final = 32 * 1024 * 1024

if __package__:
    from .western_baseline import (
        AuditContractError,
        audit_dataset,
        audit_fixture,
        canonical_json,
        human_summary,
    )
    from .western_contract import AuditReport
    from .western_live import capture_live_dataset
    from .western_source import LiveAuditConfig, RevvRestAuditSource
else:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from tools.route_audit.western_baseline import (
        AuditContractError,
        audit_dataset,
        audit_fixture,
        canonical_json,
        human_summary,
    )
    from tools.route_audit.western_contract import AuditReport
    from tools.route_audit.western_live import capture_live_dataset
    from tools.route_audit.western_source import LiveAuditConfig, RevvRestAuditSource


def main(
    fixture: Annotated[Path | None, typer.Option(exists=True, dir_okay=False)] = None,
    live: Annotated[bool, typer.Option()] = False,
    json_out: Annotated[Path, typer.Option(dir_okay=False)] = DEFAULT_JSON_OUT,
    summary_out: Annotated[Path, typer.Option(dir_okay=False)] = DEFAULT_SUMMARY_OUT,
) -> None:
    """Write canonical JSON and a human summary without mutating Supabase."""
    if (fixture is None and not live) or (fixture is not None and live):
        typer.echo("Choose exactly one of --fixture FILE or --live", err=True)
        raise typer.Exit(code=2)
    try:
        validate_output_paths(
            fixture=fixture,
            json_out=json_out,
            summary_out=summary_out,
        )
        report = _load_report(fixture=fixture, live=live)
        json_bytes = canonical_json(report)
        summary = human_summary(report)
        atomic_write(json_out, json_bytes)
        atomic_write(summary_out, summary.encode("utf-8"))
    except AuditContractError as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(code=2) from error

    typer.echo(summary, nl=False)
    if not report.gates["catalog_ready"]:
        raise typer.Exit(code=2)


def _load_report(*, fixture: Path | None, live: bool) -> AuditReport:
    if fixture is not None:
        return audit_fixture(fixture)
    if not live:
        raise AuditContractError(
            code="mode_required", detail="live mode was not selected"
        )
    config = LiveAuditConfig.create(
        supabase_url=os.environ.get("SUPABASE_URL", ""),
        publishable_key=os.environ.get("SUPABASE_PUBLISHABLE_KEY")
        or os.environ.get("SUPABASE_ANON_KEY", ""),
        access_token=os.environ.get("SUPABASE_AUDIT_ACCESS_TOKEN", ""),
    )
    from tools.route_audit.western_httpx2 import Httpx2AuditTransport

    with Httpx2AuditTransport() as transport:
        dataset = capture_live_dataset(RevvRestAuditSource(config, transport))
    return audit_dataset(dataset, source="production_read_only")


def validate_output_paths(
    *, fixture: Path | None, json_out: Path, summary_out: Path
) -> None:
    paths = [json_out, summary_out]
    if fixture is not None:
        paths.append(fixture)
    for index, left in enumerate(paths):
        for right in paths[index + 1 :]:
            if _paths_collide(left, right):
                raise AuditContractError(
                    code="path_collision",
                    detail="fixture and output paths must be distinct",
                )
    for output in (json_out, summary_out):
        if output.parent.is_symlink():
            raise AuditContractError(
                code="unsafe_output",
                detail="output parent must not be a symbolic link",
            )
        if output.is_symlink():
            raise AuditContractError(
                code="unsafe_output",
                detail="output paths must not be symbolic links",
            )
        try:
            metadata = output.lstat()
        except FileNotFoundError:
            continue
        except OSError as error:
            raise AuditContractError(
                code="unsafe_output", detail="output path could not be inspected"
            ) from error
        if not stat.S_ISREG(metadata.st_mode):
            raise AuditContractError(
                code="unsafe_output",
                detail="existing output must be a regular file",
            )


def atomic_write(path: Path, content: bytes) -> None:
    if len(content) > MAX_OUTPUT_BYTES:
        raise AuditContractError(
            code="output_too_large",
            detail="audit output exceeds the 32 MiB output budget",
        )
    directory_descriptor = -1
    temporary_name: str | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.parent.is_symlink():
            raise AuditContractError(
                code="unsafe_output",
                detail="output parent must not be a symbolic link",
            )
        directory_descriptor = os.open(
            path.parent,
            os.O_RDONLY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_NOFOLLOW", 0),
        )
        temporary_name = f".{path.name}.{secrets.token_hex(12)}"
        temporary_descriptor = os.open(
            temporary_name,
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=directory_descriptor,
        )
        with os.fdopen(temporary_descriptor, "wb", closefd=True) as temporary:
            _ = temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(
            temporary_name,
            path.name,
            src_dir_fd=directory_descriptor,
            dst_dir_fd=directory_descriptor,
        )
    except AuditContractError:
        raise
    except OSError as error:
        raise AuditContractError(
            code="output_write_failed", detail="audit output could not be written"
        ) from error
    finally:
        if temporary_name is not None and directory_descriptor >= 0:
            try:
                os.unlink(temporary_name, dir_fd=directory_descriptor)
            except FileNotFoundError:
                temporary_name = None
        if directory_descriptor >= 0:
            os.close(directory_descriptor)


def _paths_collide(left: Path, right: Path) -> bool:
    if left.resolve(strict=False) == right.resolve(strict=False):
        return True
    try:
        return os.path.samefile(left, right)
    except (FileNotFoundError, OSError):
        return False


if __name__ == "__main__":
    typer.run(main)
