from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from pydantic import JsonValue, TypeAdapter

from tools.route_audit.export_region_audit import summarize, write_csv
from tools.route_audit.western_baseline import (
    ALLOWED_PROVINCE_CODES,
    LEGACY_REGION_TO_PROVINCE,
    AuditContractError,
    audit_fixture,
    canonical_json,
    human_summary,
)


class ExistingRegionAuditCharacterizationTest(unittest.TestCase):
    def test_summary_and_empty_csv_preserve_current_observable_contract(self) -> None:
        rows: list[dict[str, JsonValue]] = [
            {
                "quality_mismatch": "yes",
                "character_mismatch": "",
                "reason_mismatch": "yes",
                "caution_mismatch": "",
                "quality_label": "keep",
            },
            {
                "quality_mismatch": "",
                "character_mismatch": "yes",
                "reason_mismatch": "",
                "caution_mismatch": "yes",
                "quality_label": "reject",
            },
        ]

        self.assertEqual(
            summarize(rows),
            {
                "routes": 2,
                "quality_mismatches": 1,
                "character_mismatches": 1,
                "reason_mismatches": 1,
                "caution_mismatches": 1,
                "keep_routes": 1,
                "maybe_routes": 0,
                "reject_routes": 1,
            },
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "empty.csv"
            write_csv(output_path, [])
            self.assertEqual(output_path.read_bytes(), b"")


class WesternBaselineAuditContractTest(unittest.TestCase):
    def _write_fixture(self, directory: str, rows: list[dict[str, JsonValue]]) -> Path:
        path = Path(directory) / "fixture.json"
        _ = path.write_text(
            json.dumps(
                {
                    "project_name": "Revv",
                    "project_ref": "zvwgnduuumksuqazpvsf",
                    "captured_at": "2026-07-16T00:00:00Z",
                    "rpc_samples": [
                        {
                            "rpc": "find_curvy_roads",
                            "center": "calgary",
                            "lat": 51.0447,
                            "lng": -114.0719,
                            "radius_m": 160000,
                            "returned_rows": 2,
                            "payload_bytes": 512,
                            "latency_ms": 125.5,
                        },
                        {
                            "rpc": "find_curvy_map_segments",
                            "center": "calgary",
                            "lat": 51.0447,
                            "lng": -114.0719,
                            "radius_m": 160000,
                            "returned_rows": 2,
                            "payload_bytes": 384,
                            "latency_ms": 110.0,
                        },
                    ],
                    "known_count_baselines": [
                        {"metric": "rows_total", "expected": len(rows), "tolerance": 0}
                    ],
                    "rows": rows,
                },
                sort_keys=True,
            ),
            encoding="utf-8",
        )
        return path

    def test_fixture_is_canonical_deterministic_and_complete(self) -> None:
        rows: list[dict[str, JsonValue]] = [
            {
                "id": "ab-eligible",
                "region": " Alberta ",
                "name": "Foothills Road",
                "center_lat": 51.1,
                "center_lng": -114.2,
                "distance_km": 15.0,
                "is_facility_like": False,
                "is_connector_like": False,
                "stop_sign_count": 1,
                "stop_control_density": 0.1,
                "max_continuous_km": 2.0,
                "quality_version": "quality-v1",
                "residential_version": "residential-v1",
                "stop_control_version": "stop-control-v1",
                "context_version": "route-context-v1",
            },
            {
                "id": "sk-fragment",
                "region": "saskatchewan",
                "name": "Prairie Bend",
                "center_lat": 50.4,
                "center_lng": -104.6,
                "distance_km": 2.5,
                "is_facility_like": False,
                "is_connector_like": False,
                "stop_sign_count": 0,
                "stop_control_density": 0.0,
                "max_continuous_km": 0.8,
                "quality_version": None,
                "residential_version": None,
                "stop_control_version": None,
                "context_version": None,
            },
        ]
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = self._write_fixture(temp_dir, rows)
            first = audit_fixture(fixture)
            second = audit_fixture(fixture)

        self.assertEqual(canonical_json(first), canonical_json(second))
        allowed_codes = TypeAdapter(list[str]).validate_python(
            first.province_classification["allowed_codes"]
        )
        legacy_map = TypeAdapter(dict[str, str]).validate_python(
            first.province_classification["legacy_region_map"]
        )
        national = TypeAdapter(dict[str, int]).validate_python(
            first.funnels["national"]
        )
        self.assertEqual(first.project["name"], "Revv")
        self.assertEqual(allowed_codes, list(ALLOWED_PROVINCE_CODES))
        self.assertEqual(legacy_map, LEGACY_REGION_TO_PROVINCE)
        self.assertTrue(first.gates["catalog_ready"])
        self.assertEqual(national["recommendation_eligible"], 1)
        self.assertEqual(national["map_distance_window"], 1)
        self.assertIn("RPC latency", human_summary(first))
        self.assertNotIn("anon-key", canonical_json(first).decode("utf-8"))

    def test_unknown_catalog_eligible_region_fails_closed(self) -> None:
        row: dict[str, JsonValue] = {
            "id": "unknown-eligible",
            "region": "western_mystery",
            "name": "Unknown Road",
            "center_lat": 51.0,
            "center_lng": -113.0,
            "distance_km": 20.0,
            "is_facility_like": False,
            "is_connector_like": False,
            "stop_sign_count": 0,
            "stop_control_density": 0.0,
            "max_continuous_km": 2.0,
            "quality_version": "quality-v1",
            "residential_version": "residential-v1",
            "stop_control_version": "stop-control-v1",
            "context_version": "route-context-v1",
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            report = audit_fixture(self._write_fixture(temp_dir, [row]))

        classification = TypeAdapter(dict[str, int]).validate_python(
            {
                "eligible_unclassified_rows": report.province_classification[
                    "eligible_unclassified_rows"
                ]
            }
        )
        self.assertFalse(report.gates["catalog_ready"])
        self.assertEqual(classification["eligible_unclassified_rows"], 1)

    def test_malformed_fixture_row_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = self._write_fixture(temp_dir, [{"id": "missing-fields"}])
            with self.assertRaises(AuditContractError):
                _ = audit_fixture(fixture)

    def test_fixture_is_reloaded_instead_of_reusing_stale_state(self) -> None:
        row: dict[str, JsonValue] = {
            "id": "fresh-row",
            "region": "alberta",
            "name": "Fresh Road",
            "center_lat": 51.0,
            "center_lng": -114.0,
            "distance_km": 10.0,
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = self._write_fixture(temp_dir, [row])
            first = audit_fixture(fixture)
            fixture = self._write_fixture(temp_dir, [row, {**row, "id": "new-row"}])
            second = audit_fixture(fixture)

        self.assertEqual(first.enrichment["rows_total"], 1)
        self.assertEqual(second.enrichment["rows_total"], 2)

    def test_negative_winding_score_is_not_recommendation_eligible(self) -> None:
        base: dict[str, JsonValue] = {
            "id": "route",
            "region": "alberta",
            "name": "Road",
            "center_lat": 51.0,
            "center_lng": -114.0,
            "distance_km": 10.0,
            "winding_score": -0.01,
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = self._write_fixture(
                temp_dir,
                [base, {**base, "id": "zero", "winding_score": 0.0}],
            )
            report = audit_fixture(fixture)
        national = TypeAdapter(dict[str, int]).validate_python(
            report.funnels["national"]
        )
        self.assertEqual(national["recommendation_eligible"], 1)

    def test_nonfinite_fixture_number_is_rejected(self) -> None:
        row: dict[str, JsonValue] = {
            "id": "nonfinite",
            "region": "alberta",
            "name": "Road",
            "center_lat": 51.0,
            "center_lng": -114.0,
            "distance_km": float("inf"),
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = self._write_fixture(temp_dir, [row])
            with self.assertRaises(AuditContractError):
                _ = audit_fixture(fixture)

    def test_fixture_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = self._write_fixture(temp_dir, [])
            link = Path(temp_dir) / "fixture-link.json"
            link.symlink_to(fixture)
            with self.assertRaises(AuditContractError):
                _ = audit_fixture(link)


if __name__ == "__main__":
    _ = unittest.main()
