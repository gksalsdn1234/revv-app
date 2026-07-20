from __future__ import annotations

import unittest
from dataclasses import dataclass, field, replace
from typing import Final

from test.western_route_fixture import chain_graph, chained_seeds
from tools.curvature_pipeline.western_graph.model import Coordinate
from tools.curvature_pipeline.western_routes.generator import generate_route
from tools.curvature_pipeline.western_routes.guidance import validate_guidance_batch
from tools.curvature_pipeline.western_routes.model import (
    GuidanceBatchError,
    GuidanceBudget,
    GuidanceHttpResponse,
    GuidanceMatch,
    GuidanceRejection,
)


@dataclass(frozen=True, slots=True)
class ScriptedGuidanceTransport:
    responses: list[GuidanceHttpResponse]
    calls: list[str] = field(default_factory=list)

    def match(
        self, route_id: str, geometry: tuple[Coordinate, ...]
    ) -> GuidanceHttpResponse:
        self.calls.append(route_id)
        if not self.responses:
            raise AssertionError("unexpected guidance request")
        _ = geometry
        return self.responses.pop(0)


def _matching_response(
    distance_m: float, geometry: tuple[Coordinate, ...]
) -> GuidanceHttpResponse:
    return GuidanceHttpResponse(
        status_code=200,
        match=GuidanceMatch(distance_m=distance_m, geometry=geometry),
    )


_GRAPH: Final = chain_graph()
ROUTE: Final = generate_route(_GRAPH, chained_seeds(_GRAPH))
GEOMETRY: Final = ROUTE.geometry


class WesternRouteGuidanceTest(unittest.TestCase):
    def test_every_candidate_gets_one_guidance_check_and_receipt(self) -> None:
        suffix = "0" if not ROUTE.route_id.endswith("0") else "1"
        second = replace(ROUTE, route_id=f"{ROUTE.route_id[:-1]}{suffix}")
        transport = ScriptedGuidanceTransport(
            responses=[
                _matching_response(ROUTE.distance_m, GEOMETRY),
                _matching_response(second.distance_m, GEOMETRY),
            ]
        )

        result = validate_guidance_batch((ROUTE, second), transport)

        self.assertEqual(len(result.receipts), 2)
        self.assertTrue(all(receipt.shadow_eligible for receipt in result.receipts))
        self.assertEqual(result.request_count, 2)
        self.assertEqual(transport.calls, [ROUTE.route_id, second.route_id])
        self.assertLessEqual(result.estimated_charge_usd, 5.0)

    def test_only_429_and_5xx_retry_once(self) -> None:
        success = _matching_response(ROUTE.distance_m, GEOMETRY)
        retrying = ScriptedGuidanceTransport(
            responses=[GuidanceHttpResponse(status_code=429), success]
        )
        result = validate_guidance_batch((ROUTE,), retrying)
        self.assertEqual(result.request_count, 2)

        no_retry = ScriptedGuidanceTransport(
            responses=[GuidanceHttpResponse(status_code=400)]
        )
        result = validate_guidance_batch((ROUTE,), no_retry)
        self.assertEqual(result.request_count, 1)
        self.assertEqual(result.receipts[0].reason, GuidanceRejection.HTTP_FAILURE)

        twice_failing = ScriptedGuidanceTransport(
            responses=[
                GuidanceHttpResponse(status_code=500),
                GuidanceHttpResponse(status_code=503),
                success,
            ]
        )
        result = validate_guidance_batch((ROUTE,), twice_failing)
        self.assertEqual(result.request_count, 2)
        self.assertEqual(result.receipts[0].reason, GuidanceRejection.HTTP_FAILURE)
        self.assertEqual(len(twice_failing.responses), 1)

    def test_endpoint_distance_and_sample_coverage_fail_closed(self) -> None:
        shifted = tuple(
            Coordinate(lat=point.lat + 0.01, lng=point.lng) for point in GEOMETRY
        )
        cases = (
            (
                GuidanceMatch(distance_m=ROUTE.distance_m, geometry=shifted),
                GuidanceRejection.ENDPOINT_MISS,
            ),
            (
                GuidanceMatch(distance_m=ROUTE.distance_m * 1.051, geometry=GEOMETRY),
                GuidanceRejection.DISTANCE_MISS,
            ),
            (
                GuidanceMatch(
                    distance_m=ROUTE.distance_m,
                    geometry=(
                        GEOMETRY[0],
                        Coordinate(
                            lat=GEOMETRY[0].lat + 0.01,
                            lng=GEOMETRY[0].lng,
                        ),
                        Coordinate(
                            lat=GEOMETRY[-1].lat + 0.01,
                            lng=GEOMETRY[-1].lng,
                        ),
                        GEOMETRY[-1],
                    ),
                ),
                GuidanceRejection.COVERAGE_MISS,
            ),
        )
        for match, expected in cases:
            with self.subTest(expected=expected):
                result = validate_guidance_batch(
                    (ROUTE,),
                    ScriptedGuidanceTransport(
                        responses=[GuidanceHttpResponse(status_code=200, match=match)]
                    ),
                )
                self.assertFalse(result.receipts[0].shadow_eligible)
                self.assertEqual(result.receipts[0].reason, expected)

    def test_request_and_cost_ceiling_abort_before_overrun(self) -> None:
        transport = ScriptedGuidanceTransport(
            responses=[_matching_response(ROUTE.distance_m, GEOMETRY)]
        )
        with self.assertRaises(GuidanceBatchError) as caught:
            _ = validate_guidance_batch(
                (ROUTE, ROUTE),
                transport,
                budget=GuidanceBudget(max_requests=1),
            )
        self.assertEqual(caught.exception.reason, GuidanceRejection.REQUEST_BUDGET)
        self.assertEqual(transport.calls, [])

        with self.assertRaises(GuidanceBatchError) as caught:
            _ = validate_guidance_batch(
                (ROUTE,),
                transport,
                budget=GuidanceBudget(estimated_charge_per_request_usd=5.01),
            )
        self.assertEqual(caught.exception.reason, GuidanceRejection.COST_BUDGET)
        self.assertEqual(transport.calls, [])

    def test_300_candidate_boundary_checks_every_route_and_301_aborts(self) -> None:
        routes = tuple(
            replace(ROUTE, route_id=f"osmgen:v1:{index:064x}") for index in range(300)
        )
        transport = ScriptedGuidanceTransport(
            responses=[
                _matching_response(route.distance_m, GEOMETRY) for route in routes
            ]
        )
        result = validate_guidance_batch(routes, transport)
        self.assertEqual(result.request_count, 300)
        self.assertEqual(len(result.receipts), 300)
        self.assertTrue(all(receipt.shadow_eligible for receipt in result.receipts))

        blocked = ScriptedGuidanceTransport(responses=[])
        with self.assertRaises(GuidanceBatchError) as caught:
            _ = validate_guidance_batch((*routes, ROUTE), blocked)
        self.assertEqual(caught.exception.reason, GuidanceRejection.REQUEST_BUDGET)
        self.assertEqual(blocked.calls, [])

    def test_retry_cannot_push_a_300_candidate_batch_to_301_requests(self) -> None:
        routes = tuple(ROUTE for _ in range(300))
        responses = [
            GuidanceHttpResponse(status_code=500),
            _matching_response(ROUTE.distance_m, GEOMETRY),
            *[_matching_response(ROUTE.distance_m, GEOMETRY) for _ in range(299)],
        ]
        transport = ScriptedGuidanceTransport(responses=responses)

        with self.assertRaises(GuidanceBatchError) as caught:
            _ = validate_guidance_batch(routes, transport)

        self.assertEqual(caught.exception.reason, GuidanceRejection.REQUEST_BUDGET)
        self.assertEqual(len(transport.calls), 300)

    def test_retry_cannot_push_actual_charge_over_five_dollars(self) -> None:
        transport = ScriptedGuidanceTransport(
            responses=[
                GuidanceHttpResponse(status_code=500),
                _matching_response(ROUTE.distance_m, GEOMETRY),
                _matching_response(ROUTE.distance_m, GEOMETRY),
            ]
        )

        with self.assertRaises(GuidanceBatchError) as caught:
            _ = validate_guidance_batch(
                (ROUTE, ROUTE),
                transport,
                budget=GuidanceBudget(estimated_charge_per_request_usd=2.0),
            )

        self.assertEqual(caught.exception.reason, GuidanceRejection.COST_BUDGET)
        self.assertEqual(len(transport.calls), 2)


if __name__ == "__main__":
    unittest.main()
