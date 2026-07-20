from __future__ import annotations

import hashlib
import math
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Final, Protocol, final

import osmium
from pydantic import ValidationError

from ..western_sources.manifest import ProvinceCode
from .model import Coordinate, GraphEdge, GraphNode, HubGraph, SourceTag
from .policy import Direction, evaluate_drivable_way

EARTH_RADIUS_M: Final = 6_371_008.8


@final
class GraphBuildError(RuntimeError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(f"western graph build failed: {detail}")


@dataclass(frozen=True, slots=True)
class GraphLimits:
    max_nodes: int = 500_000
    max_directed_edges: int = 2_000_000


@dataclass(frozen=True, slots=True)
class HubGraphSpec:
    hub_id: str
    province_code: ProvinceCode
    source_pbf_checksum: str
    hub_pbf_checksum: str


@dataclass(frozen=True, slots=True)
class WayInput:
    osm_way_id: int
    osm_node_ids: tuple[int, ...]
    coordinates: tuple[tuple[float, float], ...]
    tags: tuple[tuple[str, str], ...]


DEFAULT_GRAPH_LIMITS: Final = GraphLimits()


class _OsmTag(Protocol):
    k: str
    v: str


class _OsmNodeRef(Protocol):
    ref: int
    lat: float
    lon: float


class _OsmWay(Protocol):
    id: int
    tags: Iterable[_OsmTag]
    nodes: Iterable[_OsmNodeRef]


def build_graph(
    spec: HubGraphSpec,
    ways: tuple[WayInput, ...],
    *,
    limits: GraphLimits = DEFAULT_GRAPH_LIMITS,
) -> HubGraph:
    if limits.max_nodes < 1 or limits.max_directed_edges < 1:
        raise GraphBuildError("graph limits must be positive")

    nodes: dict[int, Coordinate] = {}
    edges: list[GraphEdge] = []
    try:
        for way in sorted(ways, key=lambda item: item.osm_way_id):
            decision = evaluate_drivable_way(dict(way.tags))
            if decision is None:
                continue
            if way.osm_way_id <= 0:
                raise GraphBuildError("OSM way IDs must be positive")
            if len(way.osm_node_ids) != len(way.coordinates):
                raise GraphBuildError(
                    "way nodes and coordinates must have equal length"
                )
            if len(way.osm_node_ids) < 2:
                raise GraphBuildError("accepted ways must contain at least two nodes")

            source_tags = tuple(
                SourceTag(key=key, value=value) for key, value in decision.tags
            )
            for segment_index, ((from_id, to_id), (from_raw, to_raw)) in enumerate(
                zip(
                    zip(way.osm_node_ids, way.osm_node_ids[1:], strict=False),
                    zip(way.coordinates, way.coordinates[1:], strict=False),
                    strict=True,
                )
            ):
                from_coordinate = Coordinate(lat=from_raw[0], lng=from_raw[1])
                to_coordinate = Coordinate(lat=to_raw[0], lng=to_raw[1])
                _record_node(nodes, from_id, from_coordinate)
                _record_node(nodes, to_id, to_coordinate)
                length_m = _haversine_m(from_coordinate, to_coordinate)
                if length_m <= 0.0:
                    raise GraphBuildError("edge length must be positive")
                if decision.direction in (Direction.FORWARD, Direction.BOTH):
                    edges.append(
                        _edge(
                            spec,
                            way.osm_way_id,
                            segment_index,
                            "f",
                            from_id,
                            to_id,
                            from_coordinate,
                            to_coordinate,
                            length_m,
                            source_tags,
                        )
                    )
                if decision.direction in (Direction.REVERSE, Direction.BOTH):
                    edges.append(
                        _edge(
                            spec,
                            way.osm_way_id,
                            segment_index,
                            "r",
                            to_id,
                            from_id,
                            to_coordinate,
                            from_coordinate,
                            length_m,
                            source_tags,
                        )
                    )
                if len(nodes) > limits.max_nodes:
                    raise GraphBuildError("graph node limit exceeded")
                if len(edges) > limits.max_directed_edges:
                    raise GraphBuildError("graph directed-edge limit exceeded")

        return HubGraph(
            hub_id=spec.hub_id,
            province_code=spec.province_code,
            source_pbf_checksum=spec.source_pbf_checksum,
            hub_pbf_checksum=spec.hub_pbf_checksum,
            nodes=tuple(
                GraphNode(osm_node_id=node_id, coordinate=nodes[node_id])
                for node_id in sorted(nodes)
            ),
            edges=tuple(
                sorted(
                    edges,
                    key=lambda edge: (
                        edge.osm_way_id,
                        edge.segment_index,
                        edge.edge_id,
                    ),
                )
            ),
        )
    except (ValidationError, ValueError) as error:
        raise GraphBuildError(str(error)) from error


def build_graph_from_pbf(
    spec: HubGraphSpec,
    path: Path,
    *,
    limits: GraphLimits = DEFAULT_GRAPH_LIMITS,
) -> HubGraph:
    if _sha256(path) != spec.hub_pbf_checksum:
        raise GraphBuildError(
            "bounded hub PBF checksum does not match acquisition provenance"
        )
    handler = _WayHandler(limits)
    try:
        handler.apply_file(str(path), locations=True)
    except (OSError, RuntimeError, ValueError) as error:
        raise GraphBuildError(str(error)) from error
    return build_graph(spec, tuple(handler.ways), limits=limits)


@final
class _WayHandler(osmium.SimpleHandler):
    """Mutable streaming adapter required by pyosmium's callback API."""

    def __init__(self, limits: GraphLimits) -> None:
        super().__init__()
        self._limits: GraphLimits = limits
        self._directed_edges: int = 0
        self._node_ids: set[int] = set()
        self.ways: list[WayInput] = []

    def way(self, way: _OsmWay) -> None:
        tags = tuple(sorted((tag.k, tag.v) for tag in way.tags))
        decision = evaluate_drivable_way(dict(tags))
        if decision is None:
            return
        node_ids = tuple(node.ref for node in way.nodes)
        if len(node_ids) < 2:
            raise GraphBuildError("accepted ways must contain at least two nodes")
        self._node_ids.update(node_ids)
        if len(self._node_ids) > self._limits.max_nodes:
            raise GraphBuildError("graph node limit exceeded while parsing PBF")
        coordinates = tuple((node.lat, node.lon) for node in way.nodes)
        multiplier = 2 if decision.direction is Direction.BOTH else 1
        self._directed_edges += max(0, len(node_ids) - 1) * multiplier
        if self._directed_edges > self._limits.max_directed_edges:
            raise GraphBuildError(
                "graph directed-edge limit exceeded while parsing PBF"
            )
        self.ways.append(
            WayInput(
                osm_way_id=way.id,
                osm_node_ids=node_ids,
                coordinates=coordinates,
                tags=tags,
            )
        )


def _record_node(
    nodes: dict[int, Coordinate], node_id: int, coordinate: Coordinate
) -> None:
    if node_id <= 0:
        raise GraphBuildError("OSM node IDs must be positive")
    previous = nodes.get(node_id)
    if previous is not None and previous != coordinate:
        raise GraphBuildError("one OSM node has conflicting coordinates")
    nodes[node_id] = coordinate


def _edge(
    spec: HubGraphSpec,
    way_id: int,
    segment_index: int,
    suffix: str,
    from_id: int,
    to_id: int,
    from_coordinate: Coordinate,
    to_coordinate: Coordinate,
    length_m: float,
    tags: tuple[SourceTag, ...],
) -> GraphEdge:
    return GraphEdge(
        edge_id=f"w{way_id}:s{segment_index}:{suffix}",
        hub_id=spec.hub_id,
        province_code=spec.province_code,
        source_pbf_checksum=spec.source_pbf_checksum,
        osm_way_id=way_id,
        segment_index=segment_index,
        osm_node_sequence=(from_id, to_id),
        coordinates=(from_coordinate, to_coordinate),
        length_m=length_m,
        tags=tags,
    )


def _haversine_m(start: Coordinate, end: Coordinate) -> float:
    lat1 = math.radians(start.lat)
    lat2 = math.radians(end.lat)
    delta_lat = lat2 - lat1
    delta_lng = math.radians(end.lng - start.lng)
    a = (
        math.sin(delta_lat / 2.0) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lng / 2.0) ** 2
    )
    return 2.0 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise GraphBuildError(str(error)) from error
    return digest.hexdigest()
