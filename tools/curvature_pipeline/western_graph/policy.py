from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from typing import Final, assert_never


class Direction(StrEnum):
    FORWARD = "forward"
    REVERSE = "reverse"
    BOTH = "both"


@dataclass(frozen=True, slots=True)
class RoadDecision:
    direction: Direction
    tags: tuple[tuple[str, str], ...]


ALLOWED_HIGHWAYS: Final = frozenset(
    {"primary", "secondary", "tertiary", "unclassified", "residential"}
)
MISSING_SURFACE_HIGHWAYS: Final = frozenset({"primary", "secondary", "tertiary"})
PAVED_SURFACES: Final = frozenset(
    {
        "asphalt",
        "chipseal",
        "cobblestone",
        "concrete",
        "concrete:lanes",
        "concrete:plates",
        "metal",
        "paved",
        "paving_stones",
        "sett",
    }
)
ALLOWED_ACCESS: Final = frozenset({"yes", "permissive", "designated"})
RESTRICTED_ACCESS: Final = frozenset(
    {
        "agricultural",
        "customers",
        "delivery",
        "destination",
        "forestry",
        "no",
        "permit",
        "private",
    }
)
TRUE_VALUES: Final = frozenset({"1", "true", "yes"})
FALSE_VALUES: Final = frozenset({"0", "false", "no"})


def evaluate_drivable_way(tags: Mapping[str, str]) -> RoadDecision | None:
    cleaned = tuple(
        sorted((key.strip().lower(), value.strip()) for key, value in tags.items())
    )
    lookup = {key: value.lower() for key, value in cleaned}
    highway = lookup.get("highway", "")
    if highway not in ALLOWED_HIGHWAYS or highway.endswith("_link"):
        return None
    if _has_ferry_or_inactive_evidence(lookup) or _has_time_restriction(lookup):
        return None
    if lookup.get("area") in TRUE_VALUES:
        return None
    access = next(
        (
            lookup[key]
            for key in ("motor_vehicle", "vehicle", "access")
            if key in lookup
        ),
        None,
    )
    if access is not None and access not in ALLOWED_ACCESS:
        return None
    if access in RESTRICTED_ACCESS:
        return None
    surface = lookup.get("surface")
    if surface is None:
        if highway not in MISSING_SURFACE_HIGHWAYS:
            return None
    elif any(part.strip() not in PAVED_SURFACES for part in surface.split(";")):
        return None
    direction = _direction(lookup)
    if direction is None:
        return None
    return RoadDecision(direction=direction, tags=cleaned)


def _has_ferry_or_inactive_evidence(tags: Mapping[str, str]) -> bool:
    if tags.get("route") == "ferry":
        return True
    if "ferry" in tags and tags["ferry"] not in FALSE_VALUES:
        return True
    return any(
        key in tags and tags[key] not in FALSE_VALUES
        for key in ("construction", "proposed")
    )


def _has_time_restriction(tags: Mapping[str, str]) -> bool:
    if any("conditional" in key or "@" in value for key, value in tags.items()):
        return True
    return any(
        key in tags and tags[key] not in FALSE_VALUES
        for key in ("seasonal", "winter_road", "ice_road")
    )


def _direction(tags: Mapping[str, str]) -> Direction | None:
    oneway = tags.get("oneway")
    match oneway:
        case None:
            return (
                Direction.FORWARD
                if tags.get("junction") == "roundabout"
                else Direction.BOTH
            )
        case "yes" | "true" | "1":
            return Direction.FORWARD
        case "-1" | "reverse":
            return Direction.REVERSE
        case "no" | "false" | "0":
            return Direction.BOTH
        case str():
            return None
        case unreachable:
            assert_never(unreachable)
