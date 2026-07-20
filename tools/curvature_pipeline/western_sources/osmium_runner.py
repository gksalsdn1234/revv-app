from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import ClassVar, final

from pydantic import BaseModel, ConfigDict, Field

from .deadline import DeadlineExceeded, enforce_deadline, remaining_seconds
from .manifest import Hub

OSMIUM_VERSION = "1.19.0"


@final
class OsmiumError(RuntimeError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(f"osmium validation failed: {detail}")


class OsmiumRunner(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    executable: Path
    timeout_seconds: float = Field(default=300.0, gt=0, le=300.0)
    use_streaming_extract: bool = True

    def validate_installation(self, deadline_monotonic: float) -> str:
        if not self.executable.is_file() or not os.access(self.executable, os.X_OK):
            raise OsmiumError("required osmium executable is missing or not executable")
        completed = self._run([str(self.executable), "--version"], deadline_monotonic)
        version_output = completed.stdout.strip()
        if OSMIUM_VERSION not in version_output:
            raise OsmiumError(f"expected osmium {OSMIUM_VERSION}")
        return version_output

    def extract(self, task: "OsmiumExtraction") -> None:
        temporary = task.destination.with_name(
            f".{task.destination.name}.part.osm.pbf"
        )
        temporary.unlink(missing_ok=True)
        try:
            if self.use_streaming_extract:
                self._extract_streaming(task, temporary)
            else:
                self._extract_with_osmium(task, temporary)
            if not temporary.is_file() or temporary.stat().st_size == 0:
                raise OsmiumError("extract reported success without a non-empty output")
            enforce_deadline(task.deadline_monotonic)
            fileinfo = self._run(
                [str(self.executable), "fileinfo", "-e", str(temporary)],
                task.deadline_monotonic,
            )
            if fileinfo.returncode != 0:
                raise OsmiumError(f"fileinfo exited {fileinfo.returncode}")
            enforce_deadline(task.deadline_monotonic)
            os.replace(temporary, task.destination)
            enforce_deadline(task.deadline_monotonic)
        except (DeadlineExceeded, OsmiumError):
            temporary.unlink(missing_ok=True)
            raise

    def _extract_streaming(
        self, task: "OsmiumExtraction", temporary: Path
    ) -> None:
        extraction = self._run(
            [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_sources.streaming_extract",
                str(task.source),
                str(temporary),
                task.hub.model_dump_json(),
            ],
            task.deadline_monotonic,
        )
        if extraction.returncode != 0:
            raise OsmiumError(f"streaming extract exited {extraction.returncode}")

    def _extract_with_osmium(
        self, task: "OsmiumExtraction", temporary: Path
    ) -> None:
        bounds = task.hub.bounds
        bbox = f"{bounds.min_lng},{bounds.min_lat},{bounds.max_lng},{bounds.max_lat}"
        extraction = self._run(
            [
                str(self.executable),
                "extract",
                "--strategy=complete_ways",
                "--output-format=pbf",
                "--overwrite",
                "-b",
                bbox,
                "-o",
                str(temporary),
                str(task.source),
            ],
            task.deadline_monotonic,
        )
        if extraction.returncode != 0:
            raise OsmiumError(f"extract exited {extraction.returncode}")

    def _run(
        self,
        command: list[str],
        deadline_monotonic: float,
    ) -> subprocess.CompletedProcess[str]:
        try:
            completed = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                timeout=min(
                    self.timeout_seconds,
                    remaining_seconds(deadline_monotonic),
                ),
            )
            enforce_deadline(deadline_monotonic)
            return completed
        except (FileNotFoundError, PermissionError) as error:
            raise OsmiumError(type(error).__name__) from error
        except subprocess.TimeoutExpired as error:
            raise OsmiumError("command exceeded timeout") from error


class OsmiumExtraction(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    source: Path
    destination: Path
    hub: Hub
    deadline_monotonic: float
