from __future__ import annotations

import json
import tempfile
import unittest
from dataclasses import dataclass, field
from pathlib import Path

from pydantic import JsonValue, TypeAdapter

from tools.route_audit.western_baseline import audit_fixture
from tools.route_audit.western_live import capture_live_dataset
from tools.route_audit.western_source import (
    AuditJsonValue,
    JsonDocument,
    JsonFetch,
)


@dataclass(frozen=True, slots=True)
class CappedAuditSource:
    row_count: int
    offsets: list[int] = field(default_factory=list)
    rpc_names: list[str] = field(default_factory=list)

    def get_curvy_roads_page(self, *, offset: int, page_size: int) -> JsonDocument:
        self.offsets.append(offset)
        count = min(page_size, max(0, self.row_count - offset))
        return [
            {
                "id": f"route-{offset + index:06d}",
                "region": "alberta",
                "name": "Road",
                "center_lat": 51.0,
                "center_lng": -114.0,
                "distance_km": 5.0,
                "winding_score": 0.5,
            }
            for index in range(count)
        ]

    def post_rpc_with_metrics(
        self, function_name: str, payload: dict[str, AuditJsonValue]
    ) -> JsonFetch:
        _ = payload
        self.rpc_names.append(function_name)
        return JsonFetch(payload=[], payload_bytes=2, latency_ms=20.0)


class WesternLiveAuditTest(unittest.TestCase):
    def test_server_capped_pages_continue_until_a_short_page(self) -> None:
        fake = CappedAuditSource(row_count=2001)
        dataset = capture_live_dataset(fake)
        self.assertEqual(len(dataset.rows), 2001)
        self.assertEqual(fake.offsets, [0, 1000, 2000])

    def test_both_route_and_map_rpcs_are_sampled(self) -> None:
        fake = CappedAuditSource(row_count=0)
        dataset = capture_live_dataset(fake)
        self.assertEqual(len(dataset.rpc_samples), 22)
        self.assertEqual(
            fake.rpc_names[:2], ["find_curvy_roads", "find_curvy_map_segments"]
        )
        self.assertEqual(
            {sample.rpc for sample in dataset.rpc_samples},
            {"find_curvy_roads", "find_curvy_map_segments"},
        )

    def test_slow_rpc_fails_the_performance_readiness_gate(self) -> None:
        fixture_path = Path("tools/route_audit/fixtures/western_baseline.json")
        document = TypeAdapter(dict[str, JsonValue]).validate_json(
            fixture_path.read_bytes()
        )
        rpc_samples = TypeAdapter(list[dict[str, JsonValue]]).validate_python(
            document["rpc_samples"]
        )
        rpc_samples[0]["latency_ms"] = 2000.1
        document["rpc_samples"] = TypeAdapter(JsonValue).validate_python(rpc_samples)
        with tempfile.TemporaryDirectory() as temp_dir:
            slow_fixture = Path(temp_dir) / "slow.json"
            _ = slow_fixture.write_text(json.dumps(document), encoding="utf-8")
            report = audit_fixture(slow_fixture)
        self.assertFalse(report.gates["performance_within_budget"])
        self.assertFalse(report.gates["catalog_ready"])


if __name__ == "__main__":
    _ = unittest.main()
