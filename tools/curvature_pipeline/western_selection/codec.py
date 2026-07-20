from __future__ import annotations

import json

from .model import SelectionResult


def selection_bytes(result: SelectionResult) -> bytes:
    document = {
        "manifests": [
            {
                "activation_eligible": manifest.activation_eligible,
                "batch_id": manifest.batch_id,
                "geohash4_cells": list(manifest.geohash4_cells),
                "hub_counts": [list(item) for item in manifest.hub_counts],
                "province_counts": [
                    [province.value, count]
                    for province, count in manifest.province_counts
                ],
                "route_ids": list(manifest.route_ids),
            }
            for manifest in result.manifests
        ],
        "rejections": [
            {
                "overlap_route_id": item.overlap_route_id,
                "reason": item.reason.value,
                "route_id": item.route_id,
            }
            for item in result.rejections
        ],
        "shadow_route_ids": list(result.shadow_route_ids),
        "status": result.status.value,
        "summary": {
            "deduped_count": result.summary.deduped_count,
            "input_count": result.summary.input_count,
            "quality_eligible_count": result.summary.quality_eligible_count,
            "rejection_counts": [
                [reason.value, count]
                for reason, count in result.summary.rejection_counts
            ],
            "selected_count": result.summary.selected_count,
            "unselected_count": result.summary.unselected_count,
        },
        "unselected_route_ids": list(result.unselected_route_ids),
    }
    return json.dumps(
        document, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode()
