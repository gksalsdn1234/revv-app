from __future__ import annotations

import unittest

from tools.curvature_pipeline.western_graph.policy import (
    Direction,
    evaluate_drivable_way,
)


class WesternGraphPolicyTest(unittest.TestCase):
    def test_primary_secondary_tertiary_allow_missing_surface(self) -> None:
        for highway in ("primary", "secondary", "tertiary"):
            with self.subTest(highway=highway):
                # Given: an approved major road without a surface tag.
                tags = {"highway": highway}

                # When: graph eligibility is evaluated.
                decision = evaluate_drivable_way(tags)

                # Then: the road is public and bidirectional.
                self.assertIsNotNone(decision)
                self.assertEqual(decision.direction, Direction.BOTH)

    def test_lower_classes_require_explicit_paved_surface(self) -> None:
        for highway in ("unclassified", "residential"):
            with self.subTest(highway=highway):
                # Given: a lower-class road with no surface evidence.
                tags = {"highway": highway}

                # When: graph eligibility is evaluated.
                decision = evaluate_drivable_way(tags)

                # Then: it fails closed.
                self.assertIsNone(decision)

        self.assertIsNotNone(
            evaluate_drivable_way(
                {"highway": "residential", "surface": "asphalt"}
            )
        )

    def test_access_precedence_uses_first_explicit_motor_vehicle_scope(self) -> None:
        # Given: access is private but motor vehicles are explicitly allowed.
        allowed_tags = {
            "highway": "secondary",
            "access": "private",
            "motor_vehicle": "yes",
        }
        rejected_tags = {
            "highway": "secondary",
            "access": "yes",
            "vehicle": "destination",
        }

        # When: access precedence is evaluated.
        allowed = evaluate_drivable_way(allowed_tags)
        rejected = evaluate_drivable_way(rejected_tags)

        # Then: motor_vehicle overrides access and vehicle overrides access.
        self.assertIsNotNone(allowed)
        self.assertIsNone(rejected)

    def test_oneway_and_roundabout_directions_are_explicit(self) -> None:
        cases = (
            ({"highway": "secondary", "oneway": "yes"}, Direction.FORWARD),
            ({"highway": "secondary", "oneway": "-1"}, Direction.REVERSE),
            ({"highway": "secondary", "junction": "roundabout"}, Direction.FORWARD),
            (
                {
                    "highway": "secondary",
                    "junction": "roundabout",
                    "oneway": "no",
                },
                Direction.BOTH,
            ),
        )

        for tags, expected in cases:
            with self.subTest(tags=tags):
                # Given/When: an eligible way has a direction tag.
                decision = evaluate_drivable_way(tags)

                # Then: its legal direction is deterministic.
                self.assertIsNotNone(decision)
                self.assertEqual(decision.direction, expected)

    def test_forbidden_and_restricted_tags_produce_no_decision(self) -> None:
        cases = (
            {"highway": "motorway"},
            {"highway": "trunk_link"},
            {"highway": "primary_link"},
            {"highway": "service", "surface": "asphalt"},
            {"highway": "track", "surface": "asphalt"},
            {"highway": "path", "surface": "asphalt"},
            {"highway": "construction", "surface": "asphalt"},
            {"highway": "proposed", "surface": "asphalt"},
            {"highway": "secondary", "route": "ferry"},
            {"highway": "secondary", "ferry": "yes"},
            {"highway": "secondary", "surface": "gravel"},
            {"highway": "secondary", "access": "private"},
            {"highway": "secondary", "access": "destination"},
            {"highway": "secondary", "access:conditional": "no @ (snow)"},
            {"highway": "secondary", "seasonal": "yes"},
            {"highway": "secondary", "winter_road": "yes"},
        )

        for tags in cases:
            with self.subTest(tags=tags):
                # Given/When: a prohibited road is evaluated.
                decision = evaluate_drivable_way(tags)

                # Then: no graph edge may be emitted.
                self.assertIsNone(decision)


if __name__ == "__main__":
    unittest.main()
