from __future__ import annotations

import hashlib
import unittest

from tools.curvature_pipeline.western_graph.model import Coordinate
from tools.curvature_pipeline.western_routes.model import GeneratedRoute, ReplaySpan
from tools.curvature_pipeline.western_selection import (
    PolicyEvidence,
    ProvinceCode,
    QualityCandidate,
    QualityRejection,
    SelectionStatus,
    select_western_batches,
    selection_bytes,
)


def _candidate(
    route_id: str,
    province: ProvinceCode,
    index: int,
    *,
    hub: str | None = None,
    cell: str | None = None,
    edge_ids: tuple[str, ...] | None = None,
    curved_distance_m: float = 6_000.0,
    max_straight_run_m: float = 4_000.0,
    exposure: float = 0.05,
    access: PolicyEvidence = PolicyEvidence.ALLOWED,
    surface: PolicyEvidence = PolicyEvidence.ALLOWED,
) -> QualityCandidate:
    edges = edge_ids or tuple(f"{route_id}:edge:{part}" for part in range(20))
    route = GeneratedRoute(
        route_id=route_id,
        generator_version="osmgen-v1",
        hub_id=hub or f"{province.value.lower()}-hub-{index % 4}",
        province_code=province.value,
        source_pbf_checksum="a" * 64,
        hub_pbf_checksum="b" * 64,
        seed_ids=(f"seed-{route_id}",),
        edge_ids=edges,
        geometry=(
            Coordinate(lat=50.0, lng=-110.0),
            Coordinate(lat=50.2, lng=-110.2),
        ),
        replay_spans=(ReplaySpan(0, len(edges) - 1),),
        distance_m=20_000.0,
        hausdorff_error_m=5.0,
        length_error_ratio=0.001,
        is_loop=False,
    )
    return QualityCandidate(
        route=route,
        edge_lengths_m=tuple(1_000.0 for _ in edges),
        curved_distance_m=curved_distance_m,
        max_straight_run_m=max_straight_run_m,
        residential_service_exposure_ratio=exposure,
        access_evidence=access,
        surface_evidence=surface,
        geohash4=cell or f"{province.value.lower()}{index:03x}"[-4:],
    )


def _full_pool() -> tuple[QualityCandidate, ...]:
    counts = {
        ProvinceCode.BC: 40,
        ProvinceCode.AB: 40,
        ProvinceCode.SK: 20,
        ProvinceCode.MB: 20,
    }
    return tuple(
        _candidate(
            f"route-{province.value.lower()}-{index:03d}",
            province,
            index,
            hub=f"{province.value.lower()}-hub-{index % 4}",
            cell=f"{province.value.lower()}{index:02x}"[-4:],
            curved_distance_m=6_000.0 + index,
        )
        for province, count in counts.items()
        for index in range(count)
    )


class WesternRouteSelectionTest(unittest.TestCase):
    def test_selects_stable_disjoint_pilot_and_expansion(self) -> None:
        # Given: enough independently diverse quality routes for both cohorts.
        candidates = _full_pool()

        # When: input order changes across identical snapshot selections.
        first = select_western_batches(candidates, snapshot="20260716")
        second = select_western_batches(
            tuple(reversed(candidates)), snapshot="20260716"
        )

        # Then: exact manifests remain byte-stable and satisfy every quota.
        self.assertEqual(first.status, SelectionStatus.READY)
        self.assertEqual(selection_bytes(first), selection_bytes(second))
        self.assertEqual(len(first.manifests), 2)
        pilot, expansion = first.manifests
        self.assertEqual(pilot.batch_id, "west-pilot-v1-20260716")
        self.assertEqual(expansion.batch_id, "west-expand-v1-20260716")
        self.assertEqual(len(pilot.route_ids), 24)
        self.assertEqual(len(expansion.route_ids), 96)
        self.assertEqual(
            dict(pilot.province_counts),
            {
                ProvinceCode.BC: 8,
                ProvinceCode.AB: 8,
                ProvinceCode.SK: 4,
                ProvinceCode.MB: 4,
            },
        )
        self.assertEqual(
            dict(expansion.province_counts),
            {
                ProvinceCode.BC: 32,
                ProvinceCode.AB: 32,
                ProvinceCode.SK: 16,
                ProvinceCode.MB: 16,
            },
        )
        self.assertFalse(set(pilot.route_ids) & set(expansion.route_ids))
        self.assertGreaterEqual(len(pilot.hub_ids), 6)
        self.assertGreaterEqual(len(pilot.geohash4_cells), 12)
        self.assertGreaterEqual(len(expansion.hub_ids), 10)
        self.assertGreaterEqual(len(expansion.geohash4_cells), 48)
        self.assertTrue(all(count <= 25 for _, count in pilot.hub_counts))
        self.assertTrue(all(count <= 25 for _, count in expansion.hub_counts))
        self.assertEqual(first.summary.selected_count, 120)
        self.assertEqual(first.summary.input_count, 120)
        self.assertEqual(first.summary.quality_eligible_count, 120)
        self.assertEqual(first.summary.deduped_count, 120)
        self.assertEqual(
            first.summary.deduped_count,
            first.summary.selected_count + first.summary.unselected_count,
        )
        self.assertEqual(
            hashlib.sha256(selection_bytes(first)).hexdigest(),
            hashlib.sha256(selection_bytes(second)).hexdigest(),
        )

    def test_underfilled_pilot_is_no_go(self) -> None:
        # Given: every pilot floor except the immutable BC count is available.
        counts = {
            ProvinceCode.BC: 7,
            ProvinceCode.AB: 8,
            ProvinceCode.SK: 4,
            ProvinceCode.MB: 4,
        }
        candidates = tuple(
            _candidate(f"under-{province.value.lower()}-{index}", province, index)
            for province, count in counts.items()
            for index in range(count)
        )

        # When: the 23-route pool is evaluated for Western allocation.
        result = select_western_batches(candidates, snapshot="underfilled-pilot")

        # Then: no partial pilot or activation-eligible manifest is emitted.
        self.assertEqual(result.status, SelectionStatus.NO_GO_INSUFFICIENT_QUALITY)
        self.assertEqual(result.manifests, ())
        self.assertEqual(result.summary.selected_count, 0)

    def test_selects_pilot_when_expansion_is_insufficient(self) -> None:
        # Given: exact pilot supply with diverse hubs and cells, but no expansion.
        counts = {
            ProvinceCode.BC: 8,
            ProvinceCode.AB: 8,
            ProvinceCode.SK: 4,
            ProvinceCode.MB: 4,
        }
        candidates = tuple(
            _candidate(f"pilot-{province.value.lower()}-{index}", province, index)
            for province, count in counts.items()
            for index in range(count)
        )

        # When: the same qualified pilot is selected in opposite input orders.
        first = select_western_batches(candidates, snapshot="pilot-only")
        reversed_result = select_western_batches(
            tuple(reversed(candidates)), snapshot="pilot-only"
        )

        # Then: only the deterministic pilot is emitted and expansion is deferred.
        self.assertEqual(first.status, SelectionStatus.PILOT_READY_EXPANSION_DEFERRED)
        self.assertEqual(selection_bytes(first), selection_bytes(reversed_result))
        self.assertEqual(len(first.manifests), 1)
        self.assertEqual(first.manifests[0].batch_id, "west-pilot-v1-pilot-only")
        self.assertEqual(
            first.manifests[0].route_ids, tuple(sorted(first.shadow_route_ids))
        )
        self.assertEqual(first.summary.selected_count, 24)

    def test_fixed_quality_gates_reject_each_unsafe_boundary(self) -> None:
        # Given: one candidate for each immutable quality failure.
        base = _candidate("good", ProvinceCode.AB, 0)
        cases = (
            _candidate("repeat", ProvinceCode.AB, 1, edge_ids=("a", "b", "a")),
            _candidate("curve-km", ProvinceCode.AB, 2, curved_distance_m=1_999.0),
            _candidate("curve-ratio", ProvinceCode.AB, 3, curved_distance_m=2_399.0),
            _candidate("straight", ProvinceCode.AB, 4, max_straight_run_m=8_001.0),
            _candidate("exposure", ProvinceCode.AB, 5, exposure=0.15),
            _candidate("access", ProvinceCode.AB, 6, access=PolicyEvidence.FORBIDDEN),
            _candidate("surface", ProvinceCode.AB, 7, surface=PolicyEvidence.MISSING),
            _candidate("nan", ProvinceCode.AB, 8, exposure=float("nan")),
        )

        # When: an insufficient pool is evaluated.
        result = select_western_batches((base, *cases), snapshot="gates")

        # Then: it fails closed and records each stable reason.
        self.assertEqual(result.status, SelectionStatus.NO_GO_INSUFFICIENT_QUALITY)
        self.assertEqual(result.manifests, ())
        reasons = {
            rejection.route_id: rejection.reason for rejection in result.rejections
        }
        self.assertEqual(reasons["repeat"], QualityRejection.REPEATED_EDGE)
        self.assertEqual(reasons["curve-km"], QualityRejection.CURVED_DISTANCE)
        self.assertEqual(reasons["curve-ratio"], QualityRejection.CURVED_RATIO)
        self.assertEqual(reasons["straight"], QualityRejection.STRAIGHT_RUN)
        self.assertEqual(reasons["exposure"], QualityRejection.ROAD_EXPOSURE)
        self.assertEqual(reasons["access"], QualityRejection.ACCESS_POLICY)
        self.assertEqual(reasons["surface"], QualityRejection.SURFACE_POLICY)
        self.assertEqual(reasons["nan"], QualityRejection.INVALID_QUALITY_METRICS)
        quality_gate_rejections = sum(
            count
            for reason, count in result.summary.rejection_counts
            if reason is not QualityRejection.OVERLAP
        )
        self.assertEqual(
            result.summary.input_count,
            result.summary.quality_eligible_count + quality_gate_rejections,
        )
        self.assertEqual(
            set(result.shadow_route_ids),
            {item.route.route_id for item in (base, *cases)},
        )

    def test_bc_heavy_pool_never_borrows_other_province_quota(self) -> None:
        # Given: a large BC pool but sub-minimum prairie quality supply.
        candidates = tuple(
            _candidate(f"bc-{index}", ProvinceCode.BC, index) for index in range(140)
        ) + tuple(
            _candidate(f"ab-{index}", ProvinceCode.AB, index) for index in range(39)
        )

        # When: independent cohort quotas are requested.
        result = select_western_batches(candidates, snapshot="sparse")

        # Then: no activation-eligible manifest is emitted.
        self.assertEqual(result.status, SelectionStatus.NO_GO_INSUFFICIENT_QUALITY)
        self.assertEqual(result.manifests, ())
        self.assertEqual(result.summary.selected_count, 0)

    def test_duplicate_canonical_route_ids_are_rejected_before_allocation(self) -> None:
        # Given: two distinct candidates claim the same canonical generated ID.
        duplicate_a = _candidate("duplicate", ProvinceCode.BC, 0)
        duplicate_b = _candidate("duplicate", ProvinceCode.BC, 1)

        # When: quality and identity gates run before quota allocation.
        result = select_western_batches(
            (duplicate_a, duplicate_b), snapshot="duplicate-id"
        )

        # Then: both ambiguous rows reject and no activation manifest is emitted.
        self.assertEqual(result.status, SelectionStatus.NO_GO_INSUFFICIENT_QUALITY)
        self.assertEqual(result.manifests, ())
        self.assertEqual(
            [item.reason for item in result.rejections],
            [
                QualityRejection.DUPLICATE_ROUTE_ID,
                QualityRejection.DUPLICATE_ROUTE_ID,
            ],
        )


if __name__ == "__main__":
    _ = unittest.main()
