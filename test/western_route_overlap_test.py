from __future__ import annotations

import unittest

from test.western_route_selection_test import _candidate
from tools.curvature_pipeline.western_selection import (
    OverlapReference,
    ProvinceCode,
    QualityRejection,
    deduplicate_quality_candidates,
)


class WesternRouteOverlapTest(unittest.TestCase):
    def test_seventy_six_percent_overlap_rejects_lower_ranked_route(self) -> None:
        # Given: two routes sharing 76% of equal-length canonical edges.
        shared = tuple(f"shared-{index}" for index in range(19))
        first = _candidate(
            "overlap-best",
            ProvinceCode.AB,
            0,
            edge_ids=shared + tuple(f"best-{index}" for index in range(6)),
            curved_distance_m=7_000.0,
        )
        second = _candidate(
            "overlap-lower",
            ProvinceCode.AB,
            1,
            edge_ids=shared + tuple(f"lower-{index}" for index in range(6)),
            curved_distance_m=6_000.0,
        )

        # When: deterministic overlap dedupe runs.
        outcome = deduplicate_quality_candidates((second, first))

        # Then: only the higher-scored route survives at the >=75% boundary.
        self.assertEqual(
            tuple(item.route.route_id for item in outcome.accepted), ("overlap-best",)
        )
        self.assertEqual(outcome.rejections[0].route_id, "overlap-lower")
        self.assertEqual(outcome.rejections[0].reason, QualityRejection.OVERLAP)

    def test_at_grade_crossing_does_not_count_as_route_overlap(self) -> None:
        # Given: two routes from different hubs share only one crossing edge token.
        crossing = ("crossing",)
        first = _candidate(
            "cross-a",
            ProvinceCode.AB,
            0,
            hub="hub-a",
            edge_ids=crossing + tuple(f"a-{index}" for index in range(19)),
        )
        second = _candidate(
            "cross-b",
            ProvinceCode.AB,
            1,
            hub="hub-b",
            edge_ids=crossing + tuple(f"b-{index}" for index in range(19)),
        )

        # When: overlap dedupe runs.
        outcome = deduplicate_quality_candidates((first, second))

        # Then: both legitimate crossing routes survive.
        self.assertEqual(
            {item.route.route_id for item in outcome.accepted}, {"cross-a", "cross-b"}
        )
        self.assertEqual(outcome.rejections, ())

    def test_legacy_recommendation_overlap_always_wins_dedupe(self) -> None:
        # Given: a candidate overlaps exactly 75% with an existing legacy route.
        candidate = _candidate(
            "generated",
            ProvinceCode.BC,
            0,
            edge_ids=tuple(f"edge-{index}" for index in range(20)),
        )
        legacy = OverlapReference(
            route_id="legacy",
            edge_ids=tuple(f"edge-{index}" for index in range(15))
            + tuple(f"legacy-{index}" for index in range(5)),
            edge_lengths_m=tuple(1_000.0 for _ in range(20)),
        )

        # When: generated candidates are deduped against legacy recommendations.
        outcome = deduplicate_quality_candidates((candidate,), (legacy,))

        # Then: the generated duplicate is rejected at the inclusive boundary.
        self.assertEqual(outcome.accepted, ())
        self.assertEqual(outcome.rejections[0].reason, QualityRejection.OVERLAP)
        self.assertEqual(outcome.rejections[0].overlap_route_id, "legacy")

    def test_reverse_traversal_of_same_osm_segments_is_duplicate(self) -> None:
        # Given: forward and reverse edge IDs describe the same physical segments.
        forward = _candidate(
            "forward",
            ProvinceCode.AB,
            0,
            edge_ids=tuple(f"w100:s{index}:f" for index in range(20)),
        )
        reverse = _candidate(
            "reverse",
            ProvinceCode.AB,
            1,
            edge_ids=tuple(f"w100:s{index}:r" for index in reversed(range(20))),
        )

        # When: direction-independent geometry overlap is calculated.
        outcome = deduplicate_quality_candidates((forward, reverse))

        # Then: one canonical geometry survives and one is rejected as overlap.
        self.assertEqual(len(outcome.accepted), 1)
        self.assertEqual(len(outcome.rejections), 1)
        self.assertEqual(outcome.rejections[0].reason, QualityRejection.OVERLAP)


if __name__ == "__main__":
    unittest.main()
