# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "httpx2[http2,brotli,zstd]>=2.7,<3",
#   "pydantic>=2.11,<3",
#   "pyproj>=3.7,<4",
#   "pyshp>=2.3,<3",
#   "shapely>=2.1,<3",
#   "typer>=0.16,<1",
# ]
# ///
# ─── How to run ───
# uv run tools/route_audit/preflight_region_repair.py --help
from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Annotated, Final

import typer

if TYPE_CHECKING:
    from tools.route_audit.export_western_baseline import (
        atomic_write,
        validate_output_paths,
    )
    from tools.route_audit.region_repair_live import (
        RegionRepairLiveConfig,
        RevvRegionRepairSource,
    )
    from tools.route_audit.region_repair_model import (
        STATCAN_ARCHIVE_SHA256,
        BoundaryArchiveError,
        RegionRepairReport,
    )
    from tools.route_audit.region_repair_preflight import (
        build_preflight_report,
        canonical_json,
        load_statcan_boundaries,
        parse_targets,
    )
    from tools.route_audit.western_httpx2 import Httpx2AuditTransport
else:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from tools.route_audit.export_western_baseline import (
        atomic_write,
        validate_output_paths,
    )
    from tools.route_audit.region_repair_live import (
        RegionRepairLiveConfig,
        RevvRegionRepairSource,
    )
    from tools.route_audit.region_repair_model import (
        STATCAN_ARCHIVE_SHA256,
        BoundaryArchiveError,
        RegionRepairReport,
    )
    from tools.route_audit.region_repair_preflight import (
        build_preflight_report,
        canonical_json,
        load_statcan_boundaries,
        parse_targets,
    )
    from tools.route_audit.western_httpx2 import Httpx2AuditTransport

DEFAULT_REPORT_OUT: Final = Path(
    "tools/route_audit/output/region_repair_preflight.json"
)
DEFAULT_AMBIGUITY_OUT: Final = Path(
    "tools/route_audit/output/region_repair_ambiguities.json"
)
DEFAULT_CHECKSUMS_OUT: Final = Path(
    "tools/route_audit/output/region_repair_checksums.json"
)


def main(
    boundary_archive: Annotated[
        Path, typer.Option(exists=True, dir_okay=False, readable=True)
    ],
    fixture: Annotated[Path | None, typer.Option(exists=True, dir_okay=False)] = None,
    live: Annotated[bool, typer.Option()] = False,
    expected_target_count: Annotated[int, typer.Option(min=1, max=999)] = 230,
    report_out: Annotated[Path, typer.Option(dir_okay=False)] = DEFAULT_REPORT_OUT,
    ambiguity_out: Annotated[
        Path, typer.Option(dir_okay=False)
    ] = DEFAULT_AMBIGUITY_OUT,
    checksums_out: Annotated[
        Path, typer.Option(dir_okay=False)
    ] = DEFAULT_CHECKSUMS_OUT,
) -> None:
    """Emit read-only, checksum-covered region repair proposals."""
    if (fixture is None and not live) or (fixture is not None and live):
        typer.echo("Choose exactly one of --fixture FILE or --live", err=True)
        raise typer.Exit(code=2)
    try:
        _validate_paths(
            boundary_archive,
            fixture,
            report_out,
            ambiguity_out,
            checksums_out,
        )
        report = _build_report(
            boundary_archive,
            fixture,
            live,
            expected_target_count,
        )
        report_bytes = canonical_json(report)
        ambiguity_bytes = _ambiguity_bytes(report)
        checksums_bytes = _checksums_bytes(report, report_bytes, ambiguity_bytes)
        atomic_write(report_out, report_bytes)
        atomic_write(ambiguity_out, ambiguity_bytes)
        atomic_write(checksums_out, checksums_bytes)
    except (BoundaryArchiveError, OSError) as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(code=2) from error
    typer.echo(
        f"targets={report.target_count} unique={report.unique_count} "
        f"ambiguous={report.ambiguous_count} writes=0"
    )
    if report.unique_count != report.target_count or report.ambiguous_count != 0:
        raise typer.Exit(code=2)


def _build_report(
    archive: Path,
    fixture: Path | None,
    live: bool,
    expected_target_count: int,
) -> RegionRepairReport:
    boundaries = load_statcan_boundaries(archive)
    if fixture is not None:
        targets = parse_targets(fixture.read_bytes())
    elif live:
        config = RegionRepairLiveConfig.create(
            supabase_url=os.environ.get("SUPABASE_URL", ""),
            publishable_key=os.environ.get("SUPABASE_PUBLISHABLE_KEY")
            or os.environ.get("SUPABASE_ANON_KEY", ""),
        )
        with Httpx2AuditTransport() as transport:
            targets = RevvRegionRepairSource(config, transport).fetch_targets()
    else:
        raise BoundaryArchiveError("mode_required", "a preflight mode is required")
    return build_preflight_report(
        targets,
        boundaries,
        boundary_sha256=STATCAN_ARCHIVE_SHA256,
        expected_target_count=expected_target_count,
    )


def _ambiguity_bytes(report: RegionRepairReport) -> bytes:
    return (
        json.dumps(
            [item.model_dump(mode="json") for item in report.ambiguities],
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def _checksums_bytes(
    report: RegionRepairReport, report_bytes: bytes, ambiguity_bytes: bytes
) -> bytes:
    receipt = {
        "algorithm": "sha256",
        "boundary_archive": report.boundary_sha256,
        "target_snapshot": report.target_snapshot_sha256,
        "preflight_report": hashlib.sha256(report_bytes).hexdigest(),
        "ambiguity_report": hashlib.sha256(ambiguity_bytes).hexdigest(),
        "production_writes": 0,
    }
    return (json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _validate_paths(
    archive: Path,
    fixture: Path | None,
    report: Path,
    ambiguity: Path,
    checksums: Path,
) -> None:
    validate_output_paths(fixture=fixture, json_out=report, summary_out=ambiguity)
    validate_output_paths(fixture=archive, json_out=checksums, summary_out=report)
    validate_output_paths(fixture=archive, json_out=ambiguity, summary_out=checksums)


if __name__ == "__main__":
    typer.run(main)
