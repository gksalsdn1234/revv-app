# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic==2.13.2", "supabase>=2.6.0"]
# ///
# ─── How to run ───
# PYTHONPATH=. uv run tools/curvature_pipeline/upload_western_batch.py shadow MANIFEST --project-ref REF --batch-id ID --checksum SHA256

from __future__ import annotations

import json
import os
import sys
from collections.abc import Sequence
from dataclasses import asdict, dataclass
from enum import StrEnum
from pathlib import Path
from typing import Final, override

from tools.curvature_pipeline.western_upload import (
    RevvUploadError,
    execute_shadow,
    execute_transition,
    load_manifest,
)
from tools.curvature_pipeline.western_upload.model import TargetState
from tools.curvature_pipeline.western_upload.store import create_revv_store


class Action(StrEnum):
    SHADOW = "shadow"
    ACTIVATE = "activate"
    DISABLE = "disable"


@dataclass(frozen=True, slots=True)
class CliArguments:
    action: Action
    manifest: Path
    project_ref: str
    batch_id: str
    checksum: str
    apply: bool


@dataclass(frozen=True, slots=True)
class CliUsageError(ValueError):
    detail: str

    @override
    def __str__(self) -> str:
        return self.detail


_HELP = """usage: upload_western_batch.py {shadow,activate,disable} MANIFEST --project-ref REF --batch-id ID --checksum SHA256 [--apply]

Preflight one exact western route batch by default. --apply performs the validated mutation.
"""
_TARGET_STATES: Final[dict[Action, TargetState | None]] = {
    Action.SHADOW: None,
    Action.ACTIVATE: "active",
    Action.DISABLE: "disabled",
}


def main(argv: Sequence[str] | None = None) -> int:
    values = tuple(sys.argv[1:] if argv is None else argv)
    if values == ("--help",) or values == ("-h",):
        print(_HELP, end="")
        return 0
    try:
        arguments = _parse_arguments(values)
        validated = load_manifest(
            arguments.manifest,
            arguments.checksum,
            arguments.project_ref,
            arguments.batch_id,
        )
        store = (
            create_revv_store(
                arguments.project_ref,
                os.environ.get("SUPABASE_SERVICE_KEY", ""),
            )
            if arguments.apply
            else None
        )
        receipt = (
            execute_shadow(validated, store, apply=arguments.apply)
            if arguments.action is Action.SHADOW
            else execute_transition(
                validated,
                store,
                _target_state(arguments.action),
                apply=arguments.apply,
            )
        )
    except (CliUsageError, RevvUploadError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps(asdict(receipt), sort_keys=True, separators=(",", ":")))
    return 0


def _parse_arguments(values: tuple[str, ...]) -> CliArguments:
    if len(values) < 2:
        raise CliUsageError(_HELP.rstrip())
    try:
        action = Action(values[0])
    except ValueError as error:
        raise CliUsageError("action must be shadow, activate, or disable") from error
    options: dict[str, str] = {}
    apply = False
    index = 2
    while index < len(values):
        option = values[index]
        if option == "--apply":
            apply = True
            index += 1
            continue
        if option not in {"--project-ref", "--batch-id", "--checksum"}:
            raise CliUsageError(f"unknown option: {option}")
        if index + 1 >= len(values):
            raise CliUsageError(f"missing value for {option}")
        if option in options:
            raise CliUsageError(f"duplicate option: {option}")
        options[option] = values[index + 1]
        index += 2
    missing = tuple(
        option
        for option in ("--project-ref", "--batch-id", "--checksum")
        if option not in options
    )
    if missing:
        raise CliUsageError(f"missing required option: {', '.join(missing)}")
    return CliArguments(
        action=action,
        manifest=Path(values[1]),
        project_ref=options["--project-ref"],
        batch_id=options["--batch-id"],
        checksum=options["--checksum"],
        apply=apply,
    )


def _target_state(action: Action) -> TargetState:
    target = _TARGET_STATES[action]
    if target is None:
        raise RevvUploadError("invalid_transition", "shadow upload is not a transition")
    return target


if __name__ == "__main__":
    raise SystemExit(main())
