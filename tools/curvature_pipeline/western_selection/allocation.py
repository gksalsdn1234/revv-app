from __future__ import annotations

from collections import Counter
from dataclasses import dataclass

from .model import BatchManifest, ProvinceCode, ScoredCandidate


@dataclass(frozen=True, slots=True)
class BatchQuota:
    prefix: str
    province_counts: tuple[tuple[ProvinceCode, int], ...]
    minimum_hubs: int
    minimum_cells: int

    @property
    def size(self) -> int:
        return sum(count for _, count in self.province_counts)


PILOT_QUOTA = BatchQuota(
    prefix="west-pilot-v1",
    province_counts=(
        (ProvinceCode.BC, 8),
        (ProvinceCode.AB, 8),
        (ProvinceCode.SK, 4),
        (ProvinceCode.MB, 4),
    ),
    minimum_hubs=6,
    minimum_cells=12,
)

EXPANSION_QUOTA = BatchQuota(
    prefix="west-expand-v1",
    province_counts=(
        (ProvinceCode.BC, 32),
        (ProvinceCode.AB, 32),
        (ProvinceCode.SK, 16),
        (ProvinceCode.MB, 16),
    ),
    minimum_hubs=10,
    minimum_cells=48,
)


def allocate_batches(
    candidates: tuple[ScoredCandidate, ...], snapshot: str
) -> tuple[BatchManifest, BatchManifest] | None:
    attempts = (
        _allocate_in_order(candidates, snapshot, (PILOT_QUOTA, EXPANSION_QUOTA)),
        _allocate_in_order(candidates, snapshot, (EXPANSION_QUOTA, PILOT_QUOTA)),
    )
    valid = tuple(attempt for attempt in attempts if attempt is not None)
    if not valid:
        return None
    return min(valid, key=_manifest_key)


def _allocate_in_order(
    candidates: tuple[ScoredCandidate, ...],
    snapshot: str,
    quotas: tuple[BatchQuota, BatchQuota],
) -> tuple[BatchManifest, BatchManifest] | None:
    remaining = candidates
    manifests: list[BatchManifest] = []
    for quota in quotas:
        selected = _select_batch(remaining, quota)
        if selected is None:
            return None
        manifests.append(_manifest(selected, quota, snapshot))
        selected_ids = {item.route.route_id for item in selected}
        remaining = tuple(
            item for item in remaining if item.route.route_id not in selected_ids
        )
    by_prefix = {manifest.batch_id.split("-v1-")[0]: manifest for manifest in manifests}
    return by_prefix["west-pilot"], by_prefix["west-expand"]


def _select_batch(
    candidates: tuple[ScoredCandidate, ...], quota: BatchQuota
) -> tuple[ScoredCandidate, ...] | None:
    required = dict(quota.province_counts)
    available = Counter(ProvinceCode(item.route.province_code) for item in candidates)
    if any(available[province] < count for province, count in quota.province_counts):
        return None
    selected: list[ScoredCandidate] = []
    province_counts: Counter[ProvinceCode] = Counter()
    hub_counts: Counter[str] = Counter()
    cells: set[str] = set()
    hubs: set[str] = set()
    while len(cells) < quota.minimum_cells or len(hubs) < quota.minimum_hubs:
        eligible = tuple(
            item
            for item in candidates
            if item not in selected
            and province_counts[ProvinceCode(item.route.province_code)]
            < required[ProvinceCode(item.route.province_code)]
            and hub_counts[item.route.hub_id] < 25
        )
        if not eligible:
            return None
        ranked = sorted(
            eligible,
            key=lambda item: (
                -int(
                    item.candidate.geohash4 not in cells
                    and len(cells) < quota.minimum_cells
                )
                - int(item.route.hub_id not in hubs and len(hubs) < quota.minimum_hubs),
                -item.quality_score,
                item.route.route_id,
            ),
        )
        choice = ranked[0]
        old_cell_count = len(cells)
        old_hub_count = len(hubs)
        _append(choice, selected, province_counts, hub_counts, cells, hubs)
        if len(cells) == old_cell_count and len(hubs) == old_hub_count:
            return None
    for province, target in quota.province_counts:
        while province_counts[province] < target:
            eligible = tuple(
                item
                for item in candidates
                if item not in selected
                and item.route.province_code == province.value
                and hub_counts[item.route.hub_id] < 25
            )
            if not eligible:
                return None
            choice = min(
                eligible, key=lambda item: (-item.quality_score, item.route.route_id)
            )
            _append(choice, selected, province_counts, hub_counts, cells, hubs)
    if (
        len(selected) != quota.size
        or len(cells) < quota.minimum_cells
        or len(hubs) < quota.minimum_hubs
    ):
        return None
    return tuple(sorted(selected, key=lambda item: item.route.route_id))


def _append(
    item: ScoredCandidate,
    selected: list[ScoredCandidate],
    province_counts: Counter[ProvinceCode],
    hub_counts: Counter[str],
    cells: set[str],
    hubs: set[str],
) -> None:
    selected.append(item)
    province_counts[ProvinceCode(item.route.province_code)] += 1
    hub_counts[item.route.hub_id] += 1
    cells.add(item.candidate.geohash4)
    hubs.add(item.route.hub_id)


def _manifest(
    selected: tuple[ScoredCandidate, ...], quota: BatchQuota, snapshot: str
) -> BatchManifest:
    hubs = Counter(item.route.hub_id for item in selected)
    provinces = Counter(ProvinceCode(item.route.province_code) for item in selected)
    return BatchManifest(
        batch_id=f"{quota.prefix}-{snapshot}",
        route_ids=tuple(item.route.route_id for item in selected),
        province_counts=tuple(
            (province, provinces[province]) for province, _ in quota.province_counts
        ),
        hub_counts=tuple(sorted(hubs.items())),
        hub_ids=tuple(sorted(hubs)),
        geohash4_cells=tuple(sorted({item.candidate.geohash4 for item in selected})),
        activation_eligible=True,
    )


def _manifest_key(
    manifests: tuple[BatchManifest, BatchManifest],
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    return manifests[0].route_ids, manifests[1].route_ids
