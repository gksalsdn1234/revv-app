from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from test.region_repair_fixture import write_boundary_archive
from tools.route_audit.region_repair_model import (
    BoundaryArchiveError,
    RegionRepairTarget,
)
from tools.route_audit.region_repair_preflight import (
    build_preflight_report,
    canonical_json,
    load_statcan_boundaries,
)
from tools.route_audit.region_repair_live import (
    RegionRepairLiveConfig,
    RevvRegionRepairSource,
)
from tools.route_audit.western_source import AuditHttpRequest, AuditHttpResponse


class RegionRepairPreflightTest(unittest.TestCase):
    def test_build_report_proposes_only_unique_matches(self) -> None:
        # Given: two target coordinates inside separate official-code polygons.
        with tempfile.TemporaryDirectory() as directory:
            archive = write_boundary_archive(Path(directory))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            boundaries = load_statcan_boundaries(archive, digest)
            targets = (
                RegionRepairTarget(
                    id="qc-route",
                    region="",
                    center_lat=45.5,
                    center_lng=-73.5,
                ),
                RegionRepairTarget(
                    id="on-route",
                    region=None,
                    center_lat=45.5,
                    center_lng=-75.5,
                ),
            )

            # When: the repair preflight classifies the canonical coordinates.
            report = build_preflight_report(
                targets,
                boundaries,
                boundary_sha256=digest,
                expected_target_count=2,
            )

        # Then: every target has one checksum-covered, dry-run-only proposal.
        self.assertEqual(report.unique_count, 2)
        self.assertEqual(report.ambiguous_count, 0)
        self.assertEqual(report.province_counts, {"ON": 1, "QC": 1})
        self.assertEqual(
            [(update.id, update.region) for update in report.proposed_updates],
            [("on-route", "ontario"), ("qc-route", "quebec")],
        )
        self.assertIsNone(report.proposed_updates[0].expected_region)
        self.assertEqual(report.production_writes, 0)

    def test_build_report_fails_closed_on_boundary_ambiguity(self) -> None:
        # Given: a target lies exactly on the shared edge of two polygons.
        with tempfile.TemporaryDirectory() as directory:
            archive = write_boundary_archive(Path(directory))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            boundaries = load_statcan_boundaries(archive, digest)
            target = RegionRepairTarget(
                id="border-route",
                region="",
                center_lat=45.5,
                center_lng=-74.5,
            )

            # When: both polygons cover the canonical coordinate.
            report = build_preflight_report(
                (target,),
                boundaries,
                boundary_sha256=digest,
                expected_target_count=1,
            )

        # Then: no update is proposed and both matches are auditable.
        self.assertEqual(report.unique_count, 0)
        self.assertEqual(report.ambiguous_count, 1)
        self.assertEqual(report.proposed_updates, ())
        self.assertEqual(report.ambiguities[0].province_codes, ("ON", "QC"))

    def test_archive_checksum_and_output_are_deterministic(self) -> None:
        # Given: a structurally valid boundary archive and one target.
        with tempfile.TemporaryDirectory() as directory:
            archive = write_boundary_archive(Path(directory))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()

            # When/Then: the wrong source checksum is rejected before parsing.
            with self.assertRaisesRegex(BoundaryArchiveError, "checksum"):
                _ = load_statcan_boundaries(archive, "0" * 64)

            boundaries = load_statcan_boundaries(archive, digest)
            target = RegionRepairTarget(
                id="qc-route",
                region="",
                center_lat=45.5,
                center_lng=-73.5,
            )
            first = canonical_json(
                build_preflight_report(
                    (target,),
                    boundaries,
                    boundary_sha256=digest,
                    expected_target_count=1,
                )
            )
            second = canonical_json(
                build_preflight_report(
                    (target,),
                    boundaries,
                    boundary_sha256=digest,
                    expected_target_count=1,
                )
            )

        # Then: equivalent inputs produce byte-identical evidence.
        self.assertEqual(first, second)
        self.assertEqual(json.loads(first)["target_count"], 1)

    def test_live_scan_is_one_fixed_read_only_request(self) -> None:
        # Given: Revv production configuration and an exact-count REST response.
        payload = json.dumps(
            [
                {
                    "id": "route-1",
                    "region": "",
                    "center_lat": 45.5,
                    "center_lng": -73.5,
                }
            ]
        ).encode()
        transport = _RecordingTransport(
            response=AuditHttpResponse(
                status_code=200,
                body=payload,
                headers={"content-range": "0-0/1"},
            )
        )
        config = RegionRepairLiveConfig.create(
            supabase_url="https://zvwgnduuumksuqazpvsf.supabase.co",
            publishable_key="publishable-fixture",
        )

        # When: the source reads the empty-region target set.
        targets = RevvRegionRepairSource(config, transport).fetch_targets()

        # Then: it uses GET only, fixed columns and a redacted credential model.
        self.assertEqual(len(targets), 1)
        self.assertIsNotNone(transport.request)
        request = transport.request
        assert request is not None
        self.assertEqual(request.method, "GET")
        self.assertIn("select=id%2Cregion%2Ccenter_lat%2Ccenter_lng", request.url)
        self.assertIn("region.is.null%2Cregion.eq.", request.url)
        self.assertNotIn("service", repr(config).lower())


class _RecordingTransport:
    __slots__ = ("request", "response")

    def __init__(self, response: AuditHttpResponse) -> None:
        self.response = response
        self.request: AuditHttpRequest | None = None

    def send(self, request: AuditHttpRequest) -> AuditHttpResponse:
        self.request = request
        return self.response


if __name__ == "__main__":
    unittest.main()
