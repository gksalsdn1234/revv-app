from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path
from typing import Final, override


class DryRunMode(StrEnum):
    FIXTURE = "fixture"
    REAL_HUB = "real-hub"
    REAL_ALL = "real-all"


class FixtureProfile(StrEnum):
    DEFAULT = "default"
    EMPTY = "empty"


class AuditSeedSource(StrEnum):
    """Where real-hub / real-all modes obtain their seed fragments.

    ``SIMPLIFIED`` keeps the original Todo 9 pipeline-integrity seam: three
    deterministic seed windows on the largest weak component's 20-35 km
    shortest path, at most one candidate route per hub.

    ``REAL`` runs the Todo 6 production seed extraction instead:
    ``western_seeds.extract_native_seed_batches`` derives 0.3-4 km curvature
    seed fragments from the checksum-pinned hub graph itself and
    ``western_seeds.generate_native_routes`` stitches them into up to 20
    candidate routes per hub. Both are pure functions of the hub graph -
    no network, credentials, wall clock, or randomness.
    """

    SIMPLIFIED = "simplified"
    REAL = "real"


class DryRunStatus(StrEnum):
    READY = "READY"
    PILOT_READY_EXPANSION_DEFERRED = "PILOT_READY_EXPANSION_DEFERRED"
    NO_GO_CHECKSUM_MISMATCH = "NO_GO_CHECKSUM_MISMATCH"
    NO_GO_INSUFFICIENT_QUALITY = "NO_GO_INSUFFICIENT_QUALITY"
    NO_GO_INCOMPLETE_ENRICHMENT = "NO_GO_INCOMPLETE_ENRICHMENT"
    NO_GO_RESOURCE_BUDGET = "NO_GO_RESOURCE_BUDGET"


EXIT_CODES: Final[dict[DryRunStatus, int]] = {
    DryRunStatus.READY: 0,
    DryRunStatus.PILOT_READY_EXPANSION_DEFERRED: 0,
    DryRunStatus.NO_GO_CHECKSUM_MISMATCH: 2,
    DryRunStatus.NO_GO_INSUFFICIENT_QUALITY: 3,
    DryRunStatus.NO_GO_INCOMPLETE_ENRICHMENT: 4,
    DryRunStatus.NO_GO_RESOURCE_BUDGET: 5,
}


@dataclass(frozen=True, slots=True)
class ResourceBudget:
    max_peak_rss_bytes: int = 2 * 1024 * 1024 * 1024
    max_elapsed_seconds: float = 240.0
    # Per-hub guards for real-all mode: a pathological hub is recorded and
    # skipped with an explicit per-hub failure entry instead of sinking the
    # whole multi-hub run.
    max_hub_peak_rss_bytes: int = 4 * 1024 * 1024 * 1024
    max_hub_elapsed_seconds: float = 900.0


DEFAULT_RESOURCE_BUDGET: Final = ResourceBudget()


@dataclass(frozen=True, slots=True)
class DryRunConfig:
    mode: DryRunMode
    snapshot: str
    seed: int
    output_dir: Path
    sample_size: int = 5
    resource_budget: ResourceBudget = field(default_factory=ResourceBudget)
    fixture_profile: FixtureProfile = FixtureProfile.DEFAULT
    overpass_fixture_path: Path | None = None
    manifest_path: Path | None = None
    checkpoint_path: Path | None = None
    pbf_path: Path | None = None
    hub_id: str | None = None
    # real-all mode only: directory holding one `<hub_id>.osm.pbf` per hub.
    pbf_dir: Path | None = None
    # real-all mode only: optional subset filter; None means every hub the
    # acquisition checkpoint marks completed.
    hub_ids: tuple[str, ...] | None = None
    # real-hub / real-all modes only: which seed derivation feeds generation.
    seed_source: AuditSeedSource = AuditSeedSource.SIMPLIFIED


@dataclass(frozen=True, slots=True)
class StageTiming:
    stage: str
    elapsed_seconds: float


@dataclass(frozen=True, slots=True)
class DryRunError(RuntimeError):
    detail: str

    @override
    def __str__(self) -> str:
        return self.detail


@dataclass(frozen=True, slots=True)
class HubFailure:
    """One hub that could not join the combined pool, recorded explicitly.

    real-all mode never drops a hub silently: every hub that fails to load,
    verify, or stay inside its per-hub resource budget produces exactly one
    of these, and the funnel/manifest artifacts carry them all.
    """

    hub_id: str
    stage: str
    reason: str
    detail: str = ""


@dataclass(frozen=True, slots=True)
class HubMetric:
    hub_id: str
    elapsed_seconds: float
    peak_rss_bytes_after: int
    # Which pipeline stage this observation covers. The real seed source
    # additionally measures per-hub generation, so one hub can contribute
    # one metric entry per stage.
    stage: str = "acquisition_graph"


@dataclass(frozen=True, slots=True)
class RejectedRecord:
    route_or_seed_id: str
    stage: str
    reason: str
    hub_id: str
    province_code: str
    detail: str = ""
