import unittest

from tools.curvature_pipeline.process_roads import (
    compute_bearing_rate_profile,
    downsample_nodes,
    stable_road_id,
    analyze_road,
)


class CurvaturePipelineTest(unittest.TestCase):
    def test_downsample_preserves_endpoints_and_cap(self) -> None:
        nodes = [{"lat": float(i), "lng": float(i)} for i in range(500)]

        sampled = downsample_nodes(nodes, max_points=300)

        self.assertEqual(sampled[0], nodes[0])
        self.assertEqual(sampled[-1], nodes[-1])
        self.assertLessEqual(len(sampled), 300)

    def test_bearing_rate_profile_detects_curves(self) -> None:
        nodes = [
            {"lat": 45.0000, "lng": -73.0000},
            {"lat": 45.0010, "lng": -73.0000},
            {"lat": 45.0020, "lng": -72.9990},
            {"lat": 45.0030, "lng": -72.9975},
            {"lat": 45.0040, "lng": -72.9960},
        ]

        profile = compute_bearing_rate_profile(nodes)

        self.assertGreater(profile["total_curvature_deg"], 0)
        self.assertGreater(profile["medium_curve_km"], 0)
        self.assertGreaterEqual(profile["tight_curve_km"], 0)

    def test_stable_road_id_is_deterministic(self) -> None:
        road = {
            "name": "North Twist",
            "center_lat": 45.1234,
            "center_lng": -73.5678,
        }

        first = stable_road_id(road["name"], road["center_lat"], road["center_lng"])
        second = stable_road_id(road["name"], road["center_lat"], road["center_lng"])

        self.assertEqual(first, second)
        self.assertEqual(len(first), 64)

    def test_analyze_road_builds_winding_metrics(self) -> None:
        road = {
            "name": "Valley Sweep",
            "nodes": [
                {"lat": 45.0000, "lng": -73.0000},
                {"lat": 45.0015, "lng": -73.0000},
                {"lat": 45.0028, "lng": -72.9988},
                {"lat": 45.0038, "lng": -72.9974},
                {"lat": 45.0050, "lng": -72.9959},
            ],
            "curvature_score": 31.7,
        }

        analyzed = analyze_road(road)

        self.assertIn("id", analyzed)
        self.assertGreater(analyzed["distance_km"], 0)
        self.assertGreater(analyzed["winding_score"], 0)
        self.assertGreaterEqual(analyzed["star_rating"], 1)
        self.assertLessEqual(analyzed["star_rating"], 5)
        self.assertIn("nodes", analyzed)


if __name__ == "__main__":
    unittest.main()
