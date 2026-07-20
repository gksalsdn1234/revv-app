from __future__ import annotations

import math
import re
from collections import Counter
from typing import Final

from .model import (
    DedupeOutcome,
    OverlapReference,
    PolicyEvidence,
    ProvinceCode,
    QualityCandidate,
    QualityRejection,
    RouteRejectionRecord,
    ScoredCandidate,
)

_DIRECTED_EDGE_PATTERN: Final = re.compile(r"^(w[1-9]\d*:s(?:0|[1-9]\d*)):[fr]$")


def quality_rejection(candidate: QualityCandidate) -> QualityRejection | None:
    route = candidate.route
    if route.province_code not in tuple(province.value for province in ProvinceCode):
        return QualityRejection.INVALID_PROVINCE
    if (
        len(route.edge_ids) != len(candidate.edge_lengths_m)
        or not route.edge_ids
        or any(
            not math.isfinite(length) or length <= 0.0
            for length in candidate.edge_lengths_m
        )
    ):
        return QualityRejection.INVALID_TOPOLOGY
    if len(set(route.edge_ids)) != len(route.edge_ids):
        return QualityRejection.REPEATED_EDGE
    metrics = (
        route.distance_m,
        candidate.curved_distance_m,
        candidate.max_straight_run_m,
        candidate.residential_service_exposure_ratio,
    )
    if (
        any(not math.isfinite(value) for value in metrics)
        or candidate.curved_distance_m < 0.0
        or candidate.max_straight_run_m < 0.0
        or not 0.0 <= candidate.residential_service_exposure_ratio <= 1.0
    ):
        return QualityRejection.INVALID_QUALITY_METRICS
    if len(candidate.geohash4) != 4 or not candidate.geohash4.isalnum():
        return QualityRejection.INVALID_GEOHASH4
    if route.distance_m < 15_000.0 or route.distance_m > 80_000.0:
        return QualityRejection.DISTANCE
    if candidate.curved_distance_m < 2_000.0:
        return QualityRejection.CURVED_DISTANCE
    if candidate.curved_distance_m / route.distance_m < 0.12:
        return QualityRejection.CURVED_RATIO
    if candidate.max_straight_run_m > 8_000.0:
        return QualityRejection.STRAIGHT_RUN
    if candidate.residential_service_exposure_ratio >= 0.15:
        return QualityRejection.ROAD_EXPOSURE
    if candidate.access_evidence is not PolicyEvidence.ALLOWED:
        return QualityRejection.ACCESS_POLICY
    if candidate.surface_evidence is not PolicyEvidence.ALLOWED:
        return QualityRejection.SURFACE_POLICY
    return None


def quality_score(candidate: QualityCandidate) -> float:
    curved_ratio = candidate.curved_distance_m / candidate.route.distance_m
    density = min(curved_ratio / 0.35, 1.0)
    curved_distance = min(candidate.curved_distance_m / 8_000.0, 1.0)
    road_quality = 1.0 - candidate.residential_service_exposure_ratio
    return round(
        100.0 * (0.5 * density + 0.3 * curved_distance + 0.2 * road_quality), 6
    )


def deduplicate_quality_candidates(
    candidates: tuple[QualityCandidate, ...],
    existing_routes: tuple[OverlapReference, ...] = (),
) -> DedupeOutcome:
    rejections: list[RouteRejectionRecord] = []
    scored: list[ScoredCandidate] = []
    route_id_counts = Counter(candidate.route.route_id for candidate in candidates)
    for candidate in sorted(candidates, key=lambda item: item.route.route_id):
        reason = (
            QualityRejection.DUPLICATE_ROUTE_ID
            if route_id_counts[candidate.route.route_id] > 1
            else quality_rejection(candidate)
        )
        if reason is None:
            scored.append(ScoredCandidate(candidate, quality_score(candidate)))
        else:
            rejections.append(RouteRejectionRecord(candidate.route.route_id, reason))
    ranked = sorted(scored, key=lambda item: (-item.quality_score, item.route.route_id))
    references = list(sorted(existing_routes, key=lambda item: item.route_id))
    accepted: list[ScoredCandidate] = []
    for item in ranked:
        overlap_id = _first_overlap(item.candidate, references)
        if overlap_id is None:
            accepted.append(item)
            references.append(_as_reference(item.candidate))
        else:
            rejections.append(
                RouteRejectionRecord(
                    item.route.route_id,
                    QualityRejection.OVERLAP,
                    overlap_id,
                )
            )
    return DedupeOutcome(
        accepted=tuple(item.candidate for item in accepted),
        scored=tuple(accepted),
        rejections=tuple(sorted(rejections, key=lambda item: item.route_id)),
    )


def rejection_counts(
    rejections: tuple[RouteRejectionRecord, ...],
) -> tuple[tuple[QualityRejection, int], ...]:
    counts = Counter(item.reason for item in rejections)
    return tuple(
        (reason, counts[reason]) for reason in QualityRejection if counts[reason]
    )


def _first_overlap(
    candidate: QualityCandidate, references: list[OverlapReference]
) -> str | None:
    for reference in references:
        if _overlap_ratio(candidate, reference) >= 0.75:
            return reference.route_id
    return None


def _overlap_ratio(candidate: QualityCandidate, reference: OverlapReference) -> float:
    candidate_lengths = _segment_lengths(
        candidate.route.edge_ids, candidate.edge_lengths_m
    )
    reference_lengths = _segment_lengths(reference.edge_ids, reference.edge_lengths_m)
    shared = sum(
        min(length, reference_lengths[edge_id])
        for edge_id, length in candidate_lengths.items()
        if edge_id in reference_lengths
    )
    denominator = min(sum(candidate_lengths.values()), sum(reference_lengths.values()))
    return 0.0 if denominator <= 0.0 else shared / denominator


def _segment_lengths(
    edge_ids: tuple[str, ...], edge_lengths_m: tuple[float, ...]
) -> dict[str, float]:
    lengths: dict[str, float] = {}
    for edge_id, length in zip(edge_ids, edge_lengths_m, strict=True):
        matched = _DIRECTED_EDGE_PATTERN.fullmatch(edge_id)
        segment_id = matched.group(1) if matched is not None else edge_id
        lengths[segment_id] = max(lengths.get(segment_id, 0.0), length)
    return lengths


def _as_reference(candidate: QualityCandidate) -> OverlapReference:
    return OverlapReference(
        route_id=candidate.route.route_id,
        edge_ids=candidate.route.edge_ids,
        edge_lengths_m=candidate.edge_lengths_m,
    )
