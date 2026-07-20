from __future__ import annotations

import math

from pydantic import JsonValue, TypeAdapter

from .western_contract import (
    ALLOWED_PROVINCE_CODES,
    EXPECTED_PROJECT_NAME,
    EXPECTED_PROJECT_REF,
    LEGACY_REGION_TO_PROVINCE,
    AuditDataset,
    AuditReport,
    CountBaseline,
    classify_province,
    distance_km,
    duplicate_summary,
    funnel,
    metric_value,
    recommendation_eligible,
)
from .western_source import AuditContractError

_JSON_DICT_ADAPTER = TypeAdapter(dict[str, JsonValue])
_MAX_RPC_PAYLOAD_BYTES = 16 * 1024 * 1024
_RPC_NAMES = ("find_curvy_roads", "find_curvy_map_segments")


def audit_dataset(dataset: AuditDataset, *, source: str) -> AuditReport:
    if (
        dataset.project_name != EXPECTED_PROJECT_NAME
        or dataset.project_ref != EXPECTED_PROJECT_REF
    ):
        raise AuditContractError(
            code="wrong_project",
            detail="audit dataset must identify Revv production",
        )

    province_rows = {
        code: tuple(
            row for row in dataset.rows if classify_province(row.region) == code
        )
        for code in ALLOWED_PROVINCE_CODES
    }
    unclassified_rows = tuple(
        row for row in dataset.rows if classify_province(row.region) is None
    )
    eligible_unclassified = sum(
        1 for row in unclassified_rows if recommendation_eligible(row)
    )
    baseline_assertions = tuple(
        _baseline_assertion(baseline, dataset)
        for baseline in sorted(
            dataset.known_count_baselines, key=lambda item: item.metric
        )
    )
    payloads, latency, performance_ready = _performance(dataset)
    counts_ready = all(bool(item["passed"]) for item in baseline_assertions)
    return AuditReport(
        schema_version=1,
        source=source,
        project={"name": EXPECTED_PROJECT_NAME, "ref": EXPECTED_PROJECT_REF},
        captured_at=dataset.captured_at,
        province_classification=_JSON_DICT_ADAPTER.validate_python(
            {
                "allowed_codes": list(ALLOWED_PROVINCE_CODES),
                "legacy_region_map": dict(LEGACY_REGION_TO_PROVINCE),
                "unclassified_rows": len(unclassified_rows),
                "eligible_unclassified_rows": eligible_unclassified,
            }
        ),
        funnels=_JSON_DICT_ADAPTER.validate_python(
            {
                "national": funnel(dataset.rows),
                "provinces": {
                    code: funnel(province_rows[code]) for code in ALLOWED_PROVINCE_CODES
                },
                "centers": _center_funnels(dataset),
            }
        ),
        enrichment={
            "rows_total": len(dataset.rows),
            "quality_enriched": sum(bool(row.quality_version) for row in dataset.rows),
            "residential_enriched": sum(
                bool(row.residential_version) for row in dataset.rows
            ),
            "stop_control_enriched": sum(
                bool(row.stop_control_version) for row in dataset.rows
            ),
            "context_enriched": sum(bool(row.context_version) for row in dataset.rows),
        },
        duplicates=duplicate_summary(dataset.rows),
        payloads=payloads,
        rpc_latency=latency,
        baseline_assertions=baseline_assertions,
        gates={
            "catalog_ready": eligible_unclassified == 0
            and counts_ready
            and performance_ready,
            "known_counts_within_tolerance": counts_ready,
            "zero_catalog_eligible_unclassified": eligible_unclassified == 0,
            "performance_within_budget": performance_ready,
        },
    )


def _center_funnels(dataset: AuditDataset) -> dict[str, JsonValue]:
    result: dict[str, JsonValue] = {}
    for center_name in sorted({sample.center for sample in dataset.rpc_samples}):
        samples = tuple(
            sample for sample in dataset.rpc_samples if sample.center == center_name
        )
        anchor = samples[0]
        nearby = tuple(
            row
            for row in dataset.rows
            if distance_km(row, anchor) <= anchor.radius_m / 1000.0
        )
        result[center_name] = {
            **funnel(nearby),
            "rpc": {
                sample.rpc: {
                    "returned_rows": sample.returned_rows,
                    "payload_bytes": sample.payload_bytes,
                    "latency_ms": sample.latency_ms,
                }
                for sample in samples
            },
        }
    return result


def _performance(
    dataset: AuditDataset,
) -> tuple[dict[str, JsonValue], dict[str, JsonValue], bool]:
    payload_samples = [
        {
            "center": sample.center,
            "rpc": sample.rpc,
            "payload_bytes": sample.payload_bytes,
            "returned_rows": sample.returned_rows,
        }
        for sample in sorted(
            dataset.rpc_samples, key=lambda item: (item.center, item.rpc)
        )
    ]
    payload_by_rpc = {
        rpc: {
            "samples": len(values),
            "total_bytes": sum(values),
            "max_bytes": max(values, default=0),
        }
        for rpc in _RPC_NAMES
        if (
            values := [
                sample.payload_bytes
                for sample in dataset.rpc_samples
                if sample.rpc == rpc
            ]
        )
    }
    latency_by_rpc = {
        rpc: _latency_summary(
            sorted(
                sample.latency_ms for sample in dataset.rpc_samples if sample.rpc == rpc
            )
        )
        for rpc in _RPC_NAMES
    }
    performance_ready = (
        all(summary["samples"] > 0 for summary in latency_by_rpc.values())
        and all(
            summary["p95_ms"] <= 800.0 and summary["max_ms"] <= 2000.0
            for summary in latency_by_rpc.values()
        )
        and all(
            sample.payload_bytes <= _MAX_RPC_PAYLOAD_BYTES
            for sample in dataset.rpc_samples
        )
    )
    latency_values = sorted(sample.latency_ms for sample in dataset.rpc_samples)
    payloads = _JSON_DICT_ADAPTER.validate_python(
        {
            "rpc_samples": payload_samples,
            "total_bytes": sum(sample.payload_bytes for sample in dataset.rpc_samples),
            "max_bytes": max(
                (sample.payload_bytes for sample in dataset.rpc_samples), default=0
            ),
            "by_rpc": payload_by_rpc,
        }
    )
    latency = _JSON_DICT_ADAPTER.validate_python(
        {**_latency_summary(latency_values), "by_rpc": latency_by_rpc}
    )
    return payloads, latency, performance_ready


def _baseline_assertion(
    baseline: CountBaseline,
    dataset: AuditDataset,
) -> dict[str, JsonValue]:
    actual = metric_value(baseline.metric, dataset)
    return {
        "metric": baseline.metric,
        "expected": baseline.expected,
        "tolerance": baseline.tolerance,
        "actual": actual,
        "passed": actual is not None
        and abs(actual - baseline.expected) <= baseline.tolerance,
    }


def _percentile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    index = max(0, math.ceil(percentile * len(values)) - 1)
    return round(values[index], 3)


def _latency_summary(values: list[float]) -> dict[str, float | int]:
    return {
        "samples": len(values),
        "p50_ms": _percentile(values, 0.50),
        "p95_ms": _percentile(values, 0.95),
        "p99_ms": _percentile(values, 0.99),
        "max_ms": max(values, default=0.0),
    }
