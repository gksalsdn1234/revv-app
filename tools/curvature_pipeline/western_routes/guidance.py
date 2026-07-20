from __future__ import annotations

from typing import Final, Protocol

from ..western_graph.model import Coordinate
from .geometry import distance_m, point_segment_distance_m, sample_polyline
from .model import (
    GeneratedRoute,
    GuidanceBatchError,
    GuidanceBatchResult,
    GuidanceBudget,
    GuidanceHttpResponse,
    GuidanceMatch,
    GuidanceReceipt,
    GuidanceRejection,
)


class GuidanceTransport(Protocol):
    def match(
        self, route_id: str, geometry: tuple[Coordinate, ...]
    ) -> GuidanceHttpResponse: ...


DEFAULT_GUIDANCE_BUDGET: Final = GuidanceBudget()


def validate_guidance_batch(
    routes: tuple[GeneratedRoute, ...],
    transport: GuidanceTransport,
    *,
    budget: GuidanceBudget = DEFAULT_GUIDANCE_BUDGET,
) -> GuidanceBatchResult:
    _preflight_budget(len(routes), budget)
    receipts: list[GuidanceReceipt] = []
    request_count = 0
    for route in routes:
        route_request_count = 1
        _require_request_capacity(request_count + 1, budget)
        response = _request(route, transport)
        request_count += 1
        if _retryable(response.status_code):
            _require_request_capacity(request_count + 1, budget)
            response = _request(route, transport)
            request_count += 1
            route_request_count = 2
        receipts.append(_receipt(route, response, route_request_count))
    return GuidanceBatchResult(
        receipts=tuple(receipts),
        request_count=request_count,
        estimated_charge_usd=request_count * budget.estimated_charge_per_request_usd,
    )


def _request(
    route: GeneratedRoute, transport: GuidanceTransport
) -> GuidanceHttpResponse:
    return transport.match(
        route.route_id,
        route.geometry,
    )


def _preflight_budget(route_count: int, budget: GuidanceBudget) -> None:
    if route_count > budget.max_requests:
        raise GuidanceBatchError(
            GuidanceRejection.REQUEST_BUDGET,
            "one request per candidate exceeds the 300-request ceiling",
        )
    estimated = route_count * budget.estimated_charge_per_request_usd
    if estimated > budget.max_estimated_charge_usd:
        raise GuidanceBatchError(
            GuidanceRejection.COST_BUDGET,
            "one request per candidate exceeds the $5 estimate ceiling",
        )


def _require_request_capacity(request_count: int, budget: GuidanceBudget) -> None:
    if request_count > budget.max_requests:
        raise GuidanceBatchError(
            GuidanceRejection.REQUEST_BUDGET, "retry would exceed request ceiling"
        )
    if (
        request_count * budget.estimated_charge_per_request_usd
        > budget.max_estimated_charge_usd
    ):
        raise GuidanceBatchError(
            GuidanceRejection.COST_BUDGET, "retry would exceed cost ceiling"
        )


def _retryable(status_code: int) -> bool:
    return status_code == 429 or 500 <= status_code <= 599


def _receipt(
    route: GeneratedRoute, response: GuidanceHttpResponse, request_count: int
) -> GuidanceReceipt:
    if response.status_code != 200:
        return _failed(route, GuidanceRejection.HTTP_FAILURE, request_count)
    if (
        response.match is None
        or len(response.match.geometry) < 2
        or response.match.distance_m <= 0.0
    ):
        return _failed(route, GuidanceRejection.MALFORMED_MATCH, request_count)
    return _match_receipt(route, response.match, request_count)


def _match_receipt(
    route: GeneratedRoute, match: GuidanceMatch, request_count: int
) -> GuidanceReceipt:
    matched = match.geometry
    endpoint_error = max(
        distance_m(route.geometry[0], matched[0]),
        distance_m(route.geometry[-1], matched[-1]),
    )
    distance_error = abs(match.distance_m - route.distance_m) / route.distance_m
    samples = sample_polyline(matched)
    within = sum(
        min(
            point_segment_distance_m(point, start, end)
            for start, end in zip(route.geometry, route.geometry[1:], strict=False)
        )
        <= 100.0
        for point in samples
    )
    coverage = within / len(samples)
    reason: GuidanceRejection | None = None
    if endpoint_error > 100.0:
        reason = GuidanceRejection.ENDPOINT_MISS
    elif distance_error > 0.05:
        reason = GuidanceRejection.DISTANCE_MISS
    elif coverage < 0.95:
        reason = GuidanceRejection.COVERAGE_MISS
    return GuidanceReceipt(
        route_id=route.route_id,
        shadow_eligible=reason is None,
        reason=reason,
        endpoint_error_m=endpoint_error,
        distance_error_ratio=distance_error,
        coverage_ratio=coverage,
        request_count=request_count,
    )


def _failed(
    route: GeneratedRoute, reason: GuidanceRejection, request_count: int
) -> GuidanceReceipt:
    return GuidanceReceipt(
        route_id=route.route_id,
        shadow_eligible=False,
        reason=reason,
        endpoint_error_m=float("inf"),
        distance_error_ratio=float("inf"),
        coverage_ratio=0.0,
        request_count=request_count,
    )
