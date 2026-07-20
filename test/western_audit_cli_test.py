from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from pydantic import TypeAdapter

from tools.curvature_pipeline.western_audit_cli import (
    AuditSeedSource,
    DryRunConfig,
    DryRunMode,
    DryRunStatus,
    FixtureProfile,
    ResourceBudget,
    run_dry_run,
)
from tools.curvature_pipeline.western_sources.checkpoint import (
    AcquisitionCheckpoint,
    CompletedHub,
    CompletedSource,
)
from tools.curvature_pipeline.western_sources.manifest import (
    ProvinceCode,
    canonical_hub_spec_digest,
    canonical_manifest_digest,
    load_manifest,
)
from tools.curvature_pipeline.western_selection.model import (
    BatchManifest,
    QualityCandidate,
    SelectionResult,
    SelectionStatus,
    SelectionSummary,
)

from test.western_pbf_fixture import write_curvy_hub_pbf

_REPO_ROOT = Path(__file__).resolve().parent.parent
_WESTERN_MANIFEST = (
    _REPO_ROOT
    / "tools"
    / "curvature_pipeline"
    / "western_sources"
    / "manifests"
    / "western-2026-07-15.json"
)
_DETERMINISTIC_ARTIFACTS = (
    "manifest.json",
    "accepted_routes.geojson",
    "rejected.json",
    "rejected.csv",
    "funnel.json",
    "overlap_matrix.json",
)


def _fixture_config(
    output_dir: Path,
    *,
    resource_budget: ResourceBudget | None = None,
    fixture_profile: FixtureProfile = FixtureProfile.DEFAULT,
    overpass_fixture_path: Path | None = None,
) -> DryRunConfig:
    return DryRunConfig(
        mode=DryRunMode.FIXTURE,
        snapshot="test-20260716",
        seed=20260716,
        output_dir=output_dir,
        resource_budget=resource_budget or ResourceBudget(),
        fixture_profile=fixture_profile,
        overpass_fixture_path=overpass_fixture_path,
    )


_JSON_OBJECT: TypeAdapter[dict[str, object]] = TypeAdapter(dict[str, object])
_JSON_ARRAY: TypeAdapter[list[object]] = TypeAdapter(list[object])


def _read_json(path: Path) -> dict[str, object]:
    return _JSON_OBJECT.validate_json(path.read_bytes())


def _as_dict(value: object) -> dict[str, object]:
    return _JSON_OBJECT.validate_python(value)


def _as_list(value: object) -> list[object]:
    return _JSON_ARRAY.validate_python(value)


def _as_int(value: object) -> int:
    if not isinstance(value, int):
        raise AssertionError("expected JSON integer")
    return value


class WesternAuditCliFixtureTest(unittest.TestCase):
    def test_fixture_dry_run_is_byte_identical_and_funnel_reconciles(self) -> None:
        # Given: the deterministic built-in fixture hubs run twice.
        with tempfile.TemporaryDirectory() as directory:
            first_dir = Path(directory) / "first"
            second_dir = Path(directory) / "second"
            first = run_dry_run(_fixture_config(first_dir))
            second = run_dry_run(_fixture_config(second_dir))

            # Then: the bounded fixture cannot meet the 120-250 production
            # quota, so the run is an explicit NO-GO, not a success manifest.
            self.assertEqual(first.status, DryRunStatus.NO_GO_INSUFFICIENT_QUALITY)
            self.assertEqual(first.exit_code, 3)
            self.assertEqual(second.status, first.status)

            # Then: every deterministic artifact is byte-identical on rerun.
            for name in _DETERMINISTIC_ARTIFACTS:
                self.assertEqual(
                    (first_dir / name).read_bytes(),
                    (second_dir / name).read_bytes(),
                    name,
                )

            # Then: funnel counts reconcile at every stage.
            funnel = _read_json(first_dir / "funnel.json")
            totals = _as_dict(funnel["totals"])
            quality = _as_dict(funnel["quality"])
            by_hub = _as_list(funnel["by_hub"])
            generated_accepted = _as_int(totals["generated_accepted"])
            generated_rejected = _as_int(totals["generated_rejected"])
            for entry_value in by_hub:
                entry = _as_dict(entry_value)
                accepted = _as_int(entry["generated_accepted"])
                rejected = sum(
                    _as_int(count)
                    for count in _as_dict(entry["generated_rejected"]).values()
                )
                if _as_int(entry["seeds_in"]) > 0:
                    self.assertEqual(accepted + rejected, 1, entry["hub_id"])
                else:
                    self.assertEqual(accepted + rejected, 0, entry["hub_id"])
            self.assertEqual(
                generated_accepted,
                sum(_as_int(_as_dict(entry)["generated_accepted"]) for entry in by_hub),
            )
            self.assertEqual(_as_int(quality["input_count"]), generated_accepted)
            self.assertEqual(
                _as_int(quality["deduped_count"]),
                _as_int(quality["selected_count"])
                + _as_int(quality["unselected_count"]),
            )
            self.assertGreater(generated_rejected, 0)

            # Then: the SK fixture hub documents expected Saskatchewan
            # sparsity as a per-reason rejection, not a filled quota.
            sk_entry = _as_dict(
                next(
                    entry
                    for entry in by_hub
                    if _as_dict(entry)["hub_id"] == "sk-audit-fixture"
                )
            )
            self.assertEqual(_as_int(sk_entry["generated_accepted"]), 0)
            self.assertEqual(
                _as_dict(sk_entry["generated_rejected"]), {"route_too_short": 1}
            )

    def test_manifest_checksum_covers_all_emitted_artifacts(self) -> None:
        # Given: one fixture dry-run.
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory) / "run"
            _ = run_dry_run(_fixture_config(output_dir))
            manifest = _read_json(output_dir / "manifest.json")

            # Then: each recorded artifact checksum matches the file bytes.
            checksums = _as_dict(manifest["artifact_checksums"])
            self.assertGreaterEqual(len(checksums), 5)
            for name, digest in checksums.items():
                self.assertEqual(
                    hashlib.sha256((output_dir / name).read_bytes()).hexdigest(),
                    digest,
                    name,
                )

            # Then: the bundle checksum binds the per-artifact checksums.
            bundle_lines = "\n".join(
                f"{name}:{digest}" for name, digest in sorted(checksums.items())
            )
            self.assertEqual(
                manifest["artifact_bundle_checksum"],
                hashlib.sha256(bundle_lines.encode("utf-8")).hexdigest(),
            )

            # Then: the fixed-seed sample selection is explicit and rendered.
            sample_ids = _as_list(manifest["sample_route_ids"])
            self.assertGreater(len(sample_ids), 0)
            for sample_id in sample_ids:
                safe_name = str(sample_id).replace(":", "_")
                self.assertTrue(
                    (output_dir / "samples" / f"{safe_name}.geojson").exists()
                )


class WesternAuditCliFailureTest(unittest.TestCase):
    def test_changed_pbf_checksum_fails_closed_with_diagnostics(self) -> None:
        # Given: a valid manifest/checkpoint chain but a corrupted hub PBF.
        manifest = load_manifest(_WESTERN_MANIFEST)
        hub = next(
            item for item in manifest.hubs if item.hub_id == "sk-swift-current-cypress"
        )
        source = next(
            item for item in manifest.sources if item.province_code == hub.province_code
        )
        checkpoint = AcquisitionCheckpoint(
            generator_version=manifest.generator_version,
            snapshot=manifest.snapshot.isoformat(),
            manifest_digest=canonical_manifest_digest(manifest),
            completed_sources=(
                CompletedSource(
                    province_code=hub.province_code,
                    source_checksum=source.checksum,
                ),
            ),
            completed_hubs=(
                CompletedHub(
                    hub_id=hub.hub_id,
                    hub_spec_digest=canonical_hub_spec_digest(hub),
                    source_checksum=source.checksum,
                    output_checksum="e" * 64,
                ),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkpoint_path = root / "checkpoint.json"
            _ = checkpoint_path.write_text(
                checkpoint.model_dump_json(), encoding="utf-8"
            )
            corrupt_pbf = root / "corrupt.osm.pbf"
            _ = corrupt_pbf.write_bytes(b"this is not the pinned hub pbf")
            output_dir = root / "out"

            # When: the dry-run verifies the checksum chain.
            outcome = run_dry_run(
                DryRunConfig(
                    mode=DryRunMode.REAL_HUB,
                    snapshot="test-20260716",
                    seed=20260716,
                    output_dir=output_dir,
                    manifest_path=_WESTERN_MANIFEST,
                    checkpoint_path=checkpoint_path,
                    pbf_path=corrupt_pbf,
                    hub_id=hub.hub_id,
                )
            )

            # Then: it is a nonzero fail-closed NO-GO that keeps diagnostics.
            self.assertEqual(outcome.status, DryRunStatus.NO_GO_CHECKSUM_MISMATCH)
            self.assertEqual(outcome.exit_code, 2)
            failure_manifest = _read_json(output_dir / "manifest.json")
            self.assertEqual(failure_manifest["status"], "NO_GO_CHECKSUM_MISMATCH")
            self.assertIn("checksum", str(failure_manifest["failure_detail"]))
            self.assertTrue((output_dir / "resource_metrics.json").exists())

    def test_incomplete_enrichment_is_no_go_and_retains_artifacts(self) -> None:
        # Given: a canned Overpass body with no usable highway context.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            overpass_path = root / "overpass.json"
            _ = overpass_path.write_bytes(b'{"elements":[]}')
            output_dir = root / "out"

            def selected_result(
                candidates: tuple[QualityCandidate, ...], *, snapshot: str
            ) -> SelectionResult:
                del snapshot
                route_ids = tuple(
                    sorted(candidate.route.route_id for candidate in candidates)
                )
                return SelectionResult(
                    status=SelectionStatus.READY,
                    manifests=(
                        BatchManifest(
                            batch_id="west-pilot-v1-test",
                            route_ids=route_ids,
                            province_counts=(),
                            hub_counts=(),
                            hub_ids=(),
                            geohash4_cells=(),
                            activation_eligible=True,
                        ),
                    ),
                    shadow_route_ids=(),
                    rejections=(),
                    unselected_route_ids=(),
                    summary=SelectionSummary(
                        input_count=len(candidates),
                        quality_eligible_count=len(candidates),
                        deduped_count=len(candidates),
                        selected_count=len(candidates),
                        unselected_count=0,
                        rejection_counts=(),
                    ),
                )

            with patch(
                "tools.curvature_pipeline.western_audit_cli.pipeline.select_western_batches",
                side_effect=selected_result,
            ):
                outcome = run_dry_run(
                    _fixture_config(output_dir, overpass_fixture_path=overpass_path)
                )

            # Then: incomplete enrichment is a distinct nonzero NO-GO.
            self.assertEqual(outcome.status, DryRunStatus.NO_GO_INCOMPLETE_ENRICHMENT)
            self.assertEqual(outcome.exit_code, 4)
            manifest = _read_json(output_dir / "manifest.json")
            enrichment = _as_dict(manifest["enrichment"])
            self.assertEqual(enrichment["status"], "NO_GO_INCOMPLETE_GENERATED")
            routes = [_as_dict(route) for route in _as_list(enrichment["routes"])]
            self.assertTrue(routes)
            for route in routes:
                self.assertEqual(route["status"], "failed")
                self.assertFalse(route["activation_eligible"])
            self.assertTrue((output_dir / "rejected.json").exists())
            self.assertTrue((output_dir / "funnel.json").exists())

    def test_resource_budget_breach_is_no_go_with_recorded_metrics(self) -> None:
        # Given: an impossible peak-RSS budget.
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory) / "out"

            # When: the fixture dry-run finishes and checks its budget.
            outcome = run_dry_run(
                _fixture_config(
                    output_dir,
                    resource_budget=ResourceBudget(max_peak_rss_bytes=1),
                )
            )

            # Then: the breach is a distinct nonzero NO-GO with metrics kept.
            self.assertEqual(outcome.status, DryRunStatus.NO_GO_RESOURCE_BUDGET)
            self.assertEqual(outcome.exit_code, 5)
            metrics = _read_json(output_dir / "resource_metrics.json")
            self.assertGreater(_as_int(metrics["peak_rss_bytes"]), 1)
            stage_names = [
                _as_dict(item)["stage"] for item in _as_list(metrics["stage_timings"])
            ]
            self.assertEqual(
                stage_names,
                ["acquisition_graph", "generation", "selection", "enrichment"],
            )

    def test_zero_viable_routes_is_no_go_and_retains_artifacts(self) -> None:
        # Given: a fixture hub with zero seeds.
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory) / "out"

            # When: the dry-run produces no generated route at all.
            outcome = run_dry_run(
                _fixture_config(output_dir, fixture_profile=FixtureProfile.EMPTY)
            )

            # Then: the empty pool is a nonzero NO-GO, never a success.
            self.assertEqual(outcome.status, DryRunStatus.NO_GO_INSUFFICIENT_QUALITY)
            self.assertEqual(outcome.exit_code, 3)
            manifest = _read_json(output_dir / "manifest.json")
            self.assertEqual(_as_list(manifest["accepted_route_ids"]), [])
            self.assertEqual(_as_list(manifest["sample_route_ids"]), [])
            self.assertTrue((output_dir / "funnel.json").exists())


def _real_all_fixture(
    root: Path, hub_pbf_ids: tuple[str, ...], completed_extra: tuple[str, ...] = ()
) -> tuple[Path, Path]:
    """Build a pbf-dir and matching checkpoint for the given manifest hubs.

    ``hub_pbf_ids`` get a real synthetic PBF on disk; ``completed_extra``
    hubs are marked completed in the checkpoint but have no PBF file, which
    lets a test exercise the explicit per-hub missing-PBF path.
    """
    manifest = load_manifest(_WESTERN_MANIFEST)
    pbf_dir = root / "pbf"
    pbf_dir.mkdir()
    completed_hubs: list[CompletedHub] = []
    completed_provinces: dict[ProvinceCode, str] = {}
    for index, hub_id in enumerate(sorted(hub_pbf_ids + completed_extra)):
        hub = next(item for item in manifest.hubs if item.hub_id == hub_id)
        source = next(
            item for item in manifest.sources if item.province_code == hub.province_code
        )
        completed_provinces[hub.province_code] = source.checksum
        if hub_id in hub_pbf_ids:
            checksum = write_curvy_hub_pbf(
                pbf_dir / f"{hub_id}.osm.pbf",
                id_base=100_000 * (index + 1),
                base_lat=49.0 + index * 2.0,
                base_lng=-120.0 + index * 3.0,
            )
        else:
            checksum = "f" * 64
        completed_hubs.append(
            CompletedHub(
                hub_id=hub_id,
                hub_spec_digest=canonical_hub_spec_digest(hub),
                source_checksum=source.checksum,
                output_checksum=checksum,
            )
        )
    checkpoint = AcquisitionCheckpoint(
        generator_version=manifest.generator_version,
        snapshot=manifest.snapshot.isoformat(),
        manifest_digest=canonical_manifest_digest(manifest),
        completed_sources=tuple(
            CompletedSource(province_code=province, source_checksum=checksum)
            for province, checksum in sorted(completed_provinces.items())
        ),
        completed_hubs=tuple(completed_hubs),
    )
    checkpoint_path = root / "checkpoint.json"
    _ = checkpoint_path.write_text(checkpoint.model_dump_json(), encoding="utf-8")
    return pbf_dir, checkpoint_path


def _real_all_config(
    output_dir: Path,
    pbf_dir: Path,
    checkpoint_path: Path,
    hub_ids: tuple[str, ...] | None = None,
    seed_source: AuditSeedSource = AuditSeedSource.SIMPLIFIED,
) -> DryRunConfig:
    return DryRunConfig(
        mode=DryRunMode.REAL_ALL,
        snapshot="test-20260717",
        seed=20260716,
        output_dir=output_dir,
        manifest_path=_WESTERN_MANIFEST,
        checkpoint_path=checkpoint_path,
        pbf_dir=pbf_dir,
        hub_ids=hub_ids,
        seed_source=seed_source,
    )


class WesternAuditCliRealAllTest(unittest.TestCase):
    def test_real_all_two_hub_pool_is_deterministic_and_pool_wide(self) -> None:
        # Given: two checksum-pinned synthetic hub PBFs for real manifest hubs.
        hub_ids = ("ab-banff-canmore", "bc-kamloops")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pbf_dir, checkpoint_path = _real_all_fixture(root, hub_ids)

            # When: the multi-hub dry-run executes twice.
            first = run_dry_run(
                _real_all_config(root / "first", pbf_dir, checkpoint_path)
            )
            second = run_dry_run(
                _real_all_config(root / "second", pbf_dir, checkpoint_path)
            )

            # Then: a 2-route pool cannot meet the 120-250 quota; explicit NO-GO.
            self.assertEqual(first.status, DryRunStatus.NO_GO_INSUFFICIENT_QUALITY)
            self.assertEqual(first.exit_code, 3)
            self.assertEqual(second.status, first.status)
            for name in _DETERMINISTIC_ARTIFACTS:
                self.assertEqual(
                    (root / "first" / name).read_bytes(),
                    (root / "second" / name).read_bytes(),
                    name,
                )

            # Then: both hubs feed one combined pool-wide selection input.
            funnel = _read_json(root / "first" / "funnel.json")
            by_hub = [_as_dict(entry) for entry in _as_list(funnel["by_hub"])]
            self.assertEqual([entry["hub_id"] for entry in by_hub], sorted(hub_ids))
            for entry in by_hub:
                self.assertEqual(_as_int(entry["seeds_in"]), 3)
                self.assertEqual(_as_int(entry["generated_accepted"]), 1)
            totals = _as_dict(funnel["totals"])
            self.assertEqual(_as_int(totals["hubs_processed"]), 2)
            self.assertEqual(_as_int(totals["hubs_failed"]), 0)
            self.assertEqual(_as_list(funnel["hub_failures"]), [])
            quality = _as_dict(funnel["quality"])
            self.assertEqual(_as_int(quality["input_count"]), 2)

    def test_real_all_missing_hub_pbf_is_explicit_and_run_continues(self) -> None:
        # Given: two real PBFs plus one completed hub whose PBF is absent.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pbf_dir, checkpoint_path = _real_all_fixture(
                root,
                ("ab-banff-canmore", "bc-kamloops"),
                completed_extra=("sk-swift-current-cypress",),
            )

            # When: all three hubs are requested.
            outcome = run_dry_run(
                _real_all_config(root / "out", pbf_dir, checkpoint_path)
            )

            # Then: the missing hub is an explicit per-hub failure entry, the
            # two loadable hubs still reach the pool, and accounting reconciles.
            self.assertEqual(outcome.status, DryRunStatus.NO_GO_INSUFFICIENT_QUALITY)
            funnel = _read_json(root / "out" / "funnel.json")
            failures = [_as_dict(item) for item in _as_list(funnel["hub_failures"])]
            self.assertEqual(len(failures), 1)
            self.assertEqual(failures[0]["hub_id"], "sk-swift-current-cypress")
            self.assertEqual(failures[0]["reason"], "hub_pbf_missing")
            totals = _as_dict(funnel["totals"])
            self.assertEqual(_as_int(totals["hubs_processed"]), 2)
            self.assertEqual(_as_int(totals["hubs_failed"]), 1)
            manifest = _read_json(root / "out" / "manifest.json")
            manifest_failures = [
                _as_dict(item) for item in _as_list(manifest["hub_failures"])
            ]
            self.assertEqual(manifest_failures, failures)


class WesternAuditCliRealSeedSourceTest(unittest.TestCase):
    def test_real_seed_source_yields_multi_candidate_pool_deterministically(
        self,
    ) -> None:
        # Given: two checksum-pinned synthetic hub PBFs for real manifest hubs.
        hub_ids = ("ab-banff-canmore", "bc-kamloops")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pbf_dir, checkpoint_path = _real_all_fixture(root, hub_ids)

            # When: the Todo 6 production seed source runs twice, plus one
            # simplified-source run for comparison.
            first = run_dry_run(
                _real_all_config(
                    root / "first",
                    pbf_dir,
                    checkpoint_path,
                    seed_source=AuditSeedSource.REAL,
                )
            )
            second = run_dry_run(
                _real_all_config(
                    root / "second",
                    pbf_dir,
                    checkpoint_path,
                    seed_source=AuditSeedSource.REAL,
                )
            )
            simplified = run_dry_run(
                _real_all_config(root / "simplified", pbf_dir, checkpoint_path)
            )

            # Then: the bounded 2-hub pool is still an explicit quota NO-GO.
            self.assertEqual(first.status, DryRunStatus.NO_GO_INSUFFICIENT_QUALITY)
            self.assertEqual(second.status, first.status)
            self.assertEqual(simplified.status, first.status)

            # Then: every deterministic artifact is byte-identical on rerun.
            for name in _DETERMINISTIC_ARTIFACTS:
                self.assertEqual(
                    (root / "first" / name).read_bytes(),
                    (root / "second" / name).read_bytes(),
                    name,
                )

            # Then: the manifest names the seed source explicitly.
            manifest = _read_json(root / "first" / "manifest.json")
            self.assertEqual(manifest["seed_source"], "real")
            simplified_manifest = _read_json(root / "simplified" / "manifest.json")
            self.assertEqual(simplified_manifest["seed_source"], "simplified")

            # Then: real seeds produce strictly more candidates than the
            # 3-window simplified seam's one-route-per-hub ceiling.
            funnel = _read_json(root / "first" / "funnel.json")
            by_hub = [_as_dict(entry) for entry in _as_list(funnel["by_hub"])]
            self.assertEqual([entry["hub_id"] for entry in by_hub], sorted(hub_ids))
            for entry in by_hub:
                self.assertGreater(_as_int(entry["seeds_in"]), 3, entry["hub_id"])
                self.assertGreater(
                    _as_int(entry["generated_accepted"]), 1, entry["hub_id"]
                )
            accepted_ids = _as_list(manifest["accepted_route_ids"])
            simplified_ids = _as_list(simplified_manifest["accepted_route_ids"])
            self.assertGreater(len(accepted_ids), len(simplified_ids))
            for entry in by_hub:
                self.assertLessEqual(_as_int(entry["generated_accepted"]), 25)

            # Then: an incomplete pool has no activation batch, so its
            # quality-accepted diagnostic routes must not consume the bounded
            # Overpass request budget. They remain in the artifact but are
            # not selected for enrichment.
            enrichment = _read_json(root / "first" / "enrichment_manifest.json")
            routes = [_as_dict(route) for route in _as_list(enrichment["routes"])]
            self.assertTrue(routes)
            self.assertTrue(all(route["accepted"] for route in routes))
            self.assertTrue(all(not route["selected"] for route in routes))
            manifest_enrichment = _as_dict(manifest["enrichment"])
            enrichment_summary = _as_dict(manifest_enrichment["summary"])
            self.assertEqual(_as_int(enrichment_summary["attempted"]), 0)

            # Then: per-hub native seed accounting reconciles exactly:
            # seeds_in = consumed-by-accepted + rejected starts + unused.
            rejected_records = [
                _as_dict(item)
                for item in _JSON_ARRAY.validate_json(
                    (root / "first" / "rejected.json").read_bytes()
                )
            ]
            for entry in by_hub:
                hub_rejected_starts = sum(
                    1
                    for record in rejected_records
                    if record["hub_id"] == entry["hub_id"]
                    and record["stage"] == "generation"
                )
                self.assertEqual(
                    sum(
                        _as_int(count)
                        for count in _as_dict(entry["generated_rejected"]).values()
                    ),
                    hub_rejected_starts,
                    entry["hub_id"],
                )
                self.assertLessEqual(
                    _as_int(entry["seeds_unused"]) + hub_rejected_starts,
                    _as_int(entry["seeds_in"]),
                    entry["hub_id"],
                )

            # Then: the pool-wide quality funnel consumes every accepted route.
            quality = _as_dict(funnel["quality"])
            totals = _as_dict(funnel["totals"])
            quality_rejected_ids = {
                str(record["route_or_seed_id"])
                for record in rejected_records
                if record["stage"] == "quality"
            }
            self.assertEqual(
                _as_int(quality["input_count"]),
                len(accepted_ids) + len(quality_rejected_ids),
            )
            self.assertEqual(
                _as_int(totals["generated_accepted"]),
                sum(_as_int(entry["generated_accepted"]) for entry in by_hub),
            )


class WesternAuditCliInvocationTest(unittest.TestCase):
    def test_cli_real_all_requires_pbf_dir(self) -> None:
        # Given/When: real-all mode invoked without --pbf-dir.
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_audit_cli",
                "--mode",
                "real-all",
                "--snapshot",
                "test",
                "--output-dir",
                "/tmp/never-created-by-this-test",
                "--no-upload",
                "--manifest",
                str(_WESTERN_MANIFEST),
                "--checkpoint",
                "/tmp/never-read-by-this-test.json",
            ],
            check=False,
            capture_output=True,
            text=True,
            cwd=_REPO_ROOT,
        )

        # Then: the CLI refuses to run and names the required flag.
        self.assertEqual(result.returncode, 2)
        self.assertIn("--pbf-dir", result.stderr)

    def test_cli_rejects_real_seed_source_in_fixture_mode(self) -> None:
        # Given/When: fixture mode combined with the real seed source.
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_audit_cli",
                "--mode",
                "fixture",
                "--snapshot",
                "test",
                "--output-dir",
                "/tmp/never-created-by-this-test",
                "--no-upload",
                "--seed-source",
                "real",
            ],
            check=False,
            capture_output=True,
            text=True,
            cwd=_REPO_ROOT,
        )

        # Then: the CLI refuses to run and names the conflicting flag.
        self.assertEqual(result.returncode, 2)
        self.assertIn("--seed-source real", result.stderr)

    def test_cli_requires_explicit_no_upload_flag(self) -> None:
        # Given/When: an invocation that omits --no-upload.
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_audit_cli",
                "--mode",
                "fixture",
                "--snapshot",
                "test",
                "--output-dir",
                "/tmp/never-created-by-this-test",
            ],
            check=False,
            capture_output=True,
            text=True,
            cwd=_REPO_ROOT,
        )

        # Then: the CLI refuses to run and names the required flag.
        self.assertEqual(result.returncode, 2)
        self.assertIn("--no-upload", result.stderr)

    def test_cli_help_needs_no_credentials(self) -> None:
        # Given/When: the help surface without any environment secrets.
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "tools.curvature_pipeline.western_audit_cli",
                "--help",
            ],
            check=False,
            capture_output=True,
            text=True,
            cwd=_REPO_ROOT,
        )

        # Then: usage renders and requests no credential.
        self.assertEqual(result.returncode, 0)
        self.assertIn("--no-upload", result.stdout)
        self.assertNotIn("SUPABASE", result.stdout)
        self.assertNotIn("MAPBOX", result.stdout)
