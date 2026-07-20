from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Final

from .allocation import allocate_batches
from .model import (
    OverlapReference,
    QualityCandidate,
    QualityRejection,
    SelectionResult,
    SelectionStatus,
    SelectionSummary,
)
from .quality import deduplicate_quality_candidates, rejection_counts

_SNAPSHOT_PATTERN: Final = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$")


@dataclass(frozen=True, slots=True)
class SelectionInputError(ValueError):
    snapshot: str

    def __str__(self) -> str:
        return f"invalid western selection snapshot: {self.snapshot!r}"


def select_western_batches(
    candidates: tuple[QualityCandidate, ...],
    *,
    snapshot: str,
    existing_routes: tuple[OverlapReference, ...] = (),
) -> SelectionResult:
    if _SNAPSHOT_PATTERN.fullmatch(snapshot) is None:
        raise SelectionInputError(snapshot)
    outcome = deduplicate_quality_candidates(candidates, existing_routes)
    manifests = allocate_batches(outcome.scored, snapshot)
    counts = rejection_counts(outcome.rejections)
    quality_rejected = sum(
        1
        for rejection in outcome.rejections
        if rejection.reason is not QualityRejection.OVERLAP
    )
    quality_eligible = len(candidates) - quality_rejected
    shadow_ids = tuple(sorted(item.route.route_id for item in candidates))
    if manifests is None:
        return SelectionResult(
            status=SelectionStatus.NO_GO_INSUFFICIENT_QUALITY,
            manifests=(),
            shadow_route_ids=shadow_ids,
            rejections=outcome.rejections,
            unselected_route_ids=tuple(
                sorted(item.route.route_id for item in outcome.accepted)
            ),
            summary=SelectionSummary(
                input_count=len(candidates),
                quality_eligible_count=quality_eligible,
                deduped_count=len(outcome.accepted),
                selected_count=0,
                unselected_count=len(outcome.accepted),
                rejection_counts=counts,
            ),
        )
    selected_ids = {
        route_id for manifest in manifests for route_id in manifest.route_ids
    }
    unselected = tuple(
        sorted(
            item.route.route_id
            for item in outcome.accepted
            if item.route.route_id not in selected_ids
        )
    )
    return SelectionResult(
        status=SelectionStatus.READY,
        manifests=manifests,
        shadow_route_ids=shadow_ids,
        rejections=outcome.rejections,
        unselected_route_ids=unselected,
        summary=SelectionSummary(
            input_count=len(candidates),
            quality_eligible_count=quality_eligible,
            deduped_count=len(outcome.accepted),
            selected_count=len(selected_ids),
            unselected_count=len(unselected),
            rejection_counts=counts,
        ),
    )
