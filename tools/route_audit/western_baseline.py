from __future__ import annotations

import json
import os
import stat
from pathlib import Path

from pydantic import TypeAdapter, ValidationError

from .western_contract import (
    ALLOWED_PROVINCE_CODES,
    LEGACY_REGION_TO_PROVINCE,
    AuditReport,
    parse_dataset_json,
)
from .western_report import audit_dataset
from .western_source import (
    AuditContractError,
    AuditHttpRequest,
    AuditHttpResponse,
    LiveAuditConfig,
    RevvRestAuditSource,
)

__all__ = [
    "ALLOWED_PROVINCE_CODES",
    "LEGACY_REGION_TO_PROVINCE",
    "AuditContractError",
    "AuditHttpRequest",
    "AuditHttpResponse",
    "LiveAuditConfig",
    "RevvRestAuditSource",
    "audit_dataset",
    "audit_fixture",
    "canonical_json",
    "human_summary",
]
_INT_DICT_ADAPTER = TypeAdapter(dict[str, int])
_MAX_FIXTURE_BYTES = 10 * 1024 * 1024


def audit_fixture(path: Path) -> AuditReport:
    try:
        flags = (
            os.O_RDONLY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0)
            | getattr(os, "O_NONBLOCK", 0)
        )
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb", closefd=True) as fixture_file:
            metadata = os.fstat(fixture_file.fileno())
            if not stat.S_ISREG(metadata.st_mode):
                raise AuditContractError(
                    code="unsafe_fixture",
                    detail="audit fixture must be a regular file",
                )
            raw = fixture_file.read(_MAX_FIXTURE_BYTES + 1)
        if len(raw) > _MAX_FIXTURE_BYTES:
            raise AuditContractError(
                code="fixture_too_large",
                detail="audit fixture exceeds the 10 MiB input budget",
            )
        dataset = parse_dataset_json(raw.decode("utf-8"))
    except AuditContractError:
        raise
    except (OSError, UnicodeDecodeError, ValidationError) as error:
        raise AuditContractError(
            code="malformed_fixture",
            detail="fixture does not satisfy the western audit schema",
        ) from error
    return audit_dataset(dataset, source="fixture")


def canonical_json(report: AuditReport) -> bytes:
    return (
        json.dumps(
            report.model_dump(mode="json"),
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def human_summary(report: AuditReport) -> str:
    national = _INT_DICT_ADAPTER.validate_python(report.funnels["national"])
    classification = _INT_DICT_ADAPTER.validate_python(
        {
            "eligible_unclassified_rows": report.province_classification[
                "eligible_unclassified_rows"
            ]
        }
    )
    latency = report.rpc_latency
    gates = report.gates
    return (
        f"Revv western route baseline ({report.captured_at})\n"
        f"Rows: {national['raw_rows']} raw, "
        f"{national['map_distance_window']} map-distance-window rows, "
        f"{national['recommendation_eligible']} recommendation eligible\n"
        f"Province codes: {', '.join(ALLOWED_PROVINCE_CODES)}\n"
        f"Catalog-eligible unclassified: "
        f"{classification['eligible_unclassified_rows']}\n"
        f"RPC latency: p50 {latency['p50_ms']:.1f} ms, "
        f"p95 {latency['p95_ms']:.1f} ms, max {latency['max_ms']:.1f} ms\n"
        f"Catalog readiness: {'PASS' if gates['catalog_ready'] else 'FAIL'}\n"
    )
