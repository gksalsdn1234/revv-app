from __future__ import annotations

import argparse
import sys
from pathlib import Path

from pydantic import ValidationError

from ..western_selection.selection import SelectionInputError
from .model import (
    AuditSeedSource,
    DryRunConfig,
    DryRunError,
    DryRunMode,
    FixtureProfile,
    ResourceBudget,
)
from .pipeline import run_dry_run

_NO_UPLOAD_HELP = (
    "Required. This CLI has no code path that can upload or mutate any "
    "remote API; the flag exists so every invocation states that intent "
    "explicitly."
)
_OVERPASS_FIXTURE_HELP = (
    "Canned Overpass response body; defaults to a built-in fixture. "
    "Never contacts a live Overpass endpoint."
)


class _ParsedArguments(argparse.Namespace):
    """Typed view of the parsed CLI namespace.

    argparse leaves pre-existing namespace attributes alone when an option
    is omitted, so these class attributes are the single source of truth
    for every optional flag's default value.
    """

    mode: str = ""
    snapshot: str = ""
    seed: int = 20260716
    output_dir: Path = Path()
    no_upload: bool = False
    sample_size: int = 5
    max_peak_rss_bytes: int = ResourceBudget().max_peak_rss_bytes
    max_elapsed_seconds: float = ResourceBudget().max_elapsed_seconds
    max_hub_peak_rss_bytes: int = ResourceBudget().max_hub_peak_rss_bytes
    max_hub_elapsed_seconds: float = ResourceBudget().max_hub_elapsed_seconds
    fixture_profile: str = FixtureProfile.DEFAULT.value
    seed_source: str = AuditSeedSource.SIMPLIFIED.value
    overpass_fixture: Path | None = None
    manifest: Path | None = None
    checkpoint: Path | None = None
    pbf: Path | None = None
    pbf_dir: Path | None = None
    hub_id: list[str] | None = None


def parse_args(argv: list[str] | None) -> DryRunConfig:
    parser = argparse.ArgumentParser(
        prog="western_audit_cli",
        description=(
            "Run acquisition->graph->generation->quality/selection->enrichment "
            "entirely offline (--no-upload) and emit a deterministic dry-run "
            "audit bundle. Never calls Supabase, Mapbox, or Overpass."
        ),
    )
    _ = parser.add_argument(
        "--mode", choices=[mode.value for mode in DryRunMode], required=True
    )
    _ = parser.add_argument(
        "--snapshot",
        required=True,
        help="Label used for batch IDs and artifact provenance; never wall-clock.",
    )
    _ = parser.add_argument("--seed", type=int, help="Fixed sample seed.")
    _ = parser.add_argument("--output-dir", type=Path, required=True)
    _ = parser.add_argument("--no-upload", action="store_true", help=_NO_UPLOAD_HELP)
    _ = parser.add_argument("--sample-size", type=int)
    _ = parser.add_argument("--max-peak-rss-bytes", type=int)
    _ = parser.add_argument("--max-elapsed-seconds", type=float)
    _ = parser.add_argument(
        "--max-hub-peak-rss-bytes",
        type=int,
        help="real-all: skip (never silently drop) a hub past this RSS",
    )
    _ = parser.add_argument(
        "--max-hub-elapsed-seconds",
        type=float,
        help="real-all: skip (never silently drop) a hub past this elapsed time",
    )
    _ = parser.add_argument(
        "--fixture-profile",
        choices=[profile.value for profile in FixtureProfile],
    )
    _ = parser.add_argument(
        "--seed-source",
        choices=[source.value for source in AuditSeedSource],
        help=(
            "real-hub / real-all modes only. 'simplified' (default) keeps "
            "the 3-window pipeline-integrity seam; 'real' runs the Todo 6 "
            "production seed extraction (western_seeds) for up to 25 "
            "candidate routes per hub. Both are offline and deterministic."
        ),
    )
    _ = parser.add_argument(
        "--overpass-fixture", type=Path, help=_OVERPASS_FIXTURE_HELP
    )
    _ = parser.add_argument(
        "--manifest", type=Path, help="real-hub / real-all modes only"
    )
    _ = parser.add_argument(
        "--checkpoint", type=Path, help="real-hub / real-all modes only"
    )
    _ = parser.add_argument("--pbf", type=Path, help="real-hub mode only")
    _ = parser.add_argument(
        "--pbf-dir",
        type=Path,
        help="real-all mode only: directory with one <hub_id>.osm.pbf per hub",
    )
    _ = parser.add_argument(
        "--hub-id",
        type=str,
        action="append",
        help=(
            "real-hub: exactly one. real-all: repeatable optional filter; "
            "default is every checkpoint-completed hub"
        ),
    )
    parsed = parser.parse_args(argv, namespace=_ParsedArguments())
    if not parsed.no_upload:
        parser.error("--no-upload is required; this CLI never uploads")
    mode = DryRunMode(parsed.mode)
    hub_id_args = parsed.hub_id or []
    if mode is DryRunMode.REAL_HUB and (
        parsed.manifest is None
        or parsed.checkpoint is None
        or parsed.pbf is None
        or len(hub_id_args) != 1
    ):
        parser.error(
            "--mode real-hub requires --manifest, --checkpoint, --pbf, "
            + "and exactly one --hub-id"
        )
    if mode is DryRunMode.REAL_ALL and (
        parsed.manifest is None or parsed.checkpoint is None or parsed.pbf_dir is None
    ):
        parser.error("--mode real-all requires --manifest, --checkpoint, and --pbf-dir")
    seed_source = AuditSeedSource(parsed.seed_source)
    if seed_source is AuditSeedSource.REAL and mode is DryRunMode.FIXTURE:
        parser.error(
            "--seed-source real requires --mode real-hub or real-all; "
            + "fixture mode always uses its built-in fixture seeds"
        )
    return DryRunConfig(
        mode=mode,
        snapshot=parsed.snapshot,
        seed=parsed.seed,
        output_dir=parsed.output_dir,
        sample_size=parsed.sample_size,
        resource_budget=ResourceBudget(
            max_peak_rss_bytes=parsed.max_peak_rss_bytes,
            max_elapsed_seconds=parsed.max_elapsed_seconds,
            max_hub_peak_rss_bytes=parsed.max_hub_peak_rss_bytes,
            max_hub_elapsed_seconds=parsed.max_hub_elapsed_seconds,
        ),
        fixture_profile=FixtureProfile(parsed.fixture_profile),
        overpass_fixture_path=parsed.overpass_fixture,
        manifest_path=parsed.manifest,
        checkpoint_path=parsed.checkpoint,
        pbf_path=parsed.pbf,
        hub_id=hub_id_args[0] if mode is DryRunMode.REAL_HUB else None,
        pbf_dir=parsed.pbf_dir,
        hub_ids=tuple(hub_id_args)
        if mode is DryRunMode.REAL_ALL and hub_id_args
        else None,
        seed_source=seed_source,
    )


def main(argv: list[str] | None = None) -> int:
    config = parse_args(argv)
    try:
        outcome = run_dry_run(config)
    except (DryRunError, SelectionInputError, ValidationError, OSError) as error:
        print(f"western audit dry-run rejected: {error}", file=sys.stderr)
        return 1
    summary_line = (
        f"western audit dry-run status={outcome.status.value}"
        + f" exit_code={outcome.exit_code} output_dir={outcome.output_dir}"
    )
    print(summary_line)
    return outcome.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
