from __future__ import annotations

from datetime import UTC, datetime
from typing import Any


def compute_residential_penalty(route: dict[str, Any]) -> dict[str, float]:
    residential_ratio = float(route.get("residential_ratio", 0.0) or 0.0)
    service_ratio = float(route.get("service_ratio", 0.0) or 0.0)
    local_road_ratio = float(route.get("local_road_ratio", 0.0) or 0.0)
    intersection_density = float(route.get("intersection_density", 0.0) or 0.0)
    building_density = float(route.get("building_density", 0.0) or 0.0)
    housing_proximity_score = float(route.get("housing_proximity_score", 0.0) or 0.0)
    stop_control_density = float(route.get("stop_control_density", 0.0) or 0.0)
    max_continuous_km = float(route.get("max_continuous_km", 0.0) or 0.0)

    urban_friction_score = min(
        1.0,
        residential_ratio * 0.35
        + service_ratio * 0.15
        + local_road_ratio * 0.2
        + min(intersection_density / 8.0, 1.0) * 0.15
        + building_density * 0.05
        + housing_proximity_score * 0.1
        + min(stop_control_density / 0.8, 1.0) * 0.2,
    )

    continuity_relief = 0.0
    if max_continuous_km >= 2.0:
        continuity_relief = 0.12
    elif max_continuous_km >= 1.2:
        continuity_relief = 0.06

    residential_penalty = max(0.15, min(1.0, 1.0 - urban_friction_score + continuity_relief))
    return {
        "urban_friction_score": urban_friction_score,
        "residential_penalty": residential_penalty,
    }


def apply_residential_metadata(
    route: dict[str, Any],
    *,
    version: str = "residential-v1",
) -> dict[str, Any]:
    updated = dict(route)
    scores = compute_residential_penalty(updated)
    updated.update(scores)
    updated["residential_version"] = version
    updated["residential_enriched_at"] = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    return updated
