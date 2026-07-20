from __future__ import annotations

import math
from typing import ClassVar, Literal, Self, final

from pydantic import BaseModel, ConfigDict, Field, model_validator

from ..western_sources.manifest import ProvinceCode


@final
class GraphFieldError(ValueError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


class Coordinate(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    lat: float
    lng: float

    @model_validator(mode="after")
    def finite_world_coordinate(self) -> Self:
        if not math.isfinite(self.lat) or not math.isfinite(self.lng):
            raise GraphFieldError("coordinates must be finite")
        if not -90.0 <= self.lat <= 90.0 or not -180.0 <= self.lng <= 180.0:
            raise GraphFieldError("coordinates must be within WGS84 bounds")
        return self


class SourceTag(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    key: str = Field(min_length=1, max_length=255)
    value: str = Field(max_length=1024)


class GraphNode(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    osm_node_id: int = Field(gt=0)
    coordinate: Coordinate


class GraphEdge(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    edge_id: str = Field(pattern=r"^w[1-9][0-9]*:s[0-9]+:[fr]$")
    hub_id: str = Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
    province_code: ProvinceCode
    source_pbf_checksum: str = Field(pattern=r"^[0-9a-f]{32}$")
    osm_way_id: int = Field(gt=0)
    segment_index: int = Field(ge=0)
    osm_node_sequence: tuple[int, int]
    coordinates: tuple[Coordinate, Coordinate]
    length_m: float = Field(gt=0)
    tags: tuple[SourceTag, ...]

    @property
    def from_node_id(self) -> int:
        return self.osm_node_sequence[0]

    @property
    def to_node_id(self) -> int:
        return self.osm_node_sequence[1]

    @model_validator(mode="after")
    def valid_edge(self) -> Self:
        if not math.isfinite(self.length_m):
            raise GraphFieldError("edge length must be finite")
        if self.from_node_id == self.to_node_id:
            raise GraphFieldError("edge endpoints must differ")
        tag_keys = tuple(tag.key for tag in self.tags)
        if tag_keys != tuple(sorted(tag_keys)) or len(set(tag_keys)) != len(tag_keys):
            raise GraphFieldError("edge source tags must be unique and sorted")
        return self


class HubGraph(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    schema_version: Literal[1] = 1
    generator_version: Literal["western-graph-v1"] = "western-graph-v1"
    hub_id: str = Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
    province_code: ProvinceCode
    source_pbf_checksum: str = Field(pattern=r"^[0-9a-f]{32}$")
    hub_pbf_checksum: str = Field(pattern=r"^[0-9a-f]{64}$")
    nodes: tuple[GraphNode, ...]
    edges: tuple[GraphEdge, ...]

    @model_validator(mode="after")
    def one_graph_provenance(self) -> Self:
        node_ids = tuple(node.osm_node_id for node in self.nodes)
        if node_ids != tuple(sorted(node_ids)) or len(set(node_ids)) != len(node_ids):
            raise GraphFieldError("graph nodes must be unique and sorted")
        known_nodes = set(node_ids)
        edge_ids: set[str] = set()
        previous_key: tuple[int, int, str] | None = None
        for edge in self.edges:
            if (
                edge.hub_id != self.hub_id
                or edge.province_code != self.province_code
                or edge.source_pbf_checksum != self.source_pbf_checksum
            ):
                raise GraphFieldError("every edge must use the graph provenance")
            if (
                edge.from_node_id not in known_nodes
                or edge.to_node_id not in known_nodes
            ):
                raise GraphFieldError("every edge endpoint must exist in graph nodes")
            if edge.edge_id in edge_ids:
                raise GraphFieldError("graph edge IDs must be unique")
            edge_ids.add(edge.edge_id)
            key = (edge.osm_way_id, edge.segment_index, edge.edge_id)
            if previous_key is not None and key < previous_key:
                raise GraphFieldError("graph edges must be canonically sorted")
            previous_key = key
        return self
