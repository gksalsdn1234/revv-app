from __future__ import annotations

from dataclasses import dataclass
from typing import ClassVar, Self, override

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .model import (
    ElevationEvidence,
    EnrichedMetadata,
    QualityEvidence,
    VerificationVersions,
)


class OverpassElement(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")

    type: str
    id: int
    lat: float | None = Field(default=None, allow_inf_nan=False)
    lon: float | None = Field(default=None, allow_inf_nan=False)
    tags: dict[str, str] = {}


class OverpassPayload(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")

    elements: tuple[OverpassElement, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def contains_road_context(self) -> Self:
        if not any(
            element.type == "way" and "highway" in element.tags
            for element in self.elements
        ):
            raise EnrichmentPayloadError("payload contains no highway way evidence")
        return self


@dataclass(frozen=True, slots=True)
class EnrichmentPayloadError(ValueError):
    detail: str

    @override
    def __str__(self) -> str:
        return self.detail


def merge_metadata(
    payloads: tuple[OverpassPayload, ...],
    quality: QualityEvidence,
    elevation: ElevationEvidence,
    versions: VerificationVersions,
) -> EnrichedMetadata:
    elements = tuple(element for payload in payloads for element in payload.elements)
    stop_count = sum(1 for element in elements if element.tags.get("highway") == "stop")
    signal_count = sum(
        1 for element in elements if element.tags.get("highway") == "traffic_signals"
    )
    ways = tuple(element for element in elements if element.type == "way")
    road_names = tuple(
        sorted(
            {name for element in ways if (name := element.tags.get("name")) is not None}
        )
    )
    surfaces = tuple(
        sorted(
            {
                surface
                for element in ways
                if (surface := element.tags.get("surface")) is not None
            }
        )
    )
    local_classes = {"residential", "living_street", "service", "unclassified"}
    local_count = sum(
        1 for element in ways if element.tags.get("highway") in local_classes
    )
    residential_ratio = local_count / len(ways) if ways else 0.0
    return EnrichedMetadata(
        stop_sign_count=stop_count,
        traffic_signal_count=signal_count,
        road_names=road_names,
        surfaces=surfaces,
        residential_ratio=residential_ratio,
        quality_score=quality.score,
        elevation_profile_m=elevation.profile_m,
        versions=versions,
    )
