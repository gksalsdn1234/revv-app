from __future__ import annotations

import gzip
import json
from typing import Final, Literal, Protocol, final

from pydantic import TypeAdapter

from ..western_sources.manifest import ProvinceCode
from .model import Coordinate, GraphEdge, GraphNode, HubGraph, SourceTag

COMPACT_GRAPH_MAGIC: Final = b"RVVG1\n"
MAX_GRAPH_INPUT_BYTES: Final = 32 * 1024 * 1024
MAX_GRAPH_UNCOMPRESSED_BYTES: Final = 256 * 1024 * 1024
MAX_GRAPH_RECORD_BYTES: Final = 2 * 1024 * 1024
MAX_GRAPH_NODES: Final = 500_000
MAX_GRAPH_EDGES: Final = 2_000_000

_HeaderRecord = tuple[
    Literal["header"],
    Literal[1],
    Literal["western-graph-v1"],
    str,
    ProvinceCode,
    str,
    str,
    int,
    int,
    int,
]
_TagRecord = tuple[Literal["tag"], int, tuple[tuple[str, str], ...]]
_NodeRecord = tuple[Literal["node"], int, float, float]
_EdgeRecord = tuple[
    Literal["edge"],
    int,
    int,
    Literal["f", "r"],
    int,
    int,
    float,
    int,
]
_Direction = Literal["f", "r"]
_Record = _HeaderRecord | _TagRecord | _NodeRecord | _EdgeRecord

_HEADER_ADAPTER: Final = TypeAdapter(_HeaderRecord)
_TAG_ADAPTER: Final = TypeAdapter(_TagRecord)
_NODE_ADAPTER: Final = TypeAdapter(_NodeRecord)
_EDGE_ADAPTER: Final = TypeAdapter(_EdgeRecord)
_DIRECTION_ADAPTER: Final[TypeAdapter[_Direction]] = TypeAdapter(_Direction)


class _BinaryReader(Protocol):
    def read(self, size: int = -1) -> bytes: ...

    def readline(self, size: int = -1) -> bytes: ...


class _BinaryWriter(Protocol):
    def write(self, data: bytes, /) -> int: ...

    def flush(self) -> None: ...


@final
class CompactGraphFormatError(ValueError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


def write_compact_graph(handle: _BinaryWriter, graph: HubGraph) -> None:
    tag_values = tuple(sorted({_tag_key(edge) for edge in graph.edges}))
    tag_indexes = {value: index for index, value in enumerate(tag_values)}
    _ = handle.write(COMPACT_GRAPH_MAGIC)
    written = 0
    with gzip.GzipFile(filename="", mode="wb", fileobj=handle, mtime=0) as compressed:
        written = _write_record(
            compressed,
            (
                "header",
                graph.schema_version,
                graph.generator_version,
                graph.hub_id,
                graph.province_code,
                graph.source_pbf_checksum,
                graph.hub_pbf_checksum,
                len(tag_values),
                len(graph.nodes),
                len(graph.edges),
            ),
            written,
        )
        for index, value in enumerate(tag_values):
            written = _write_record(compressed, ("tag", index, value), written)
        for node in graph.nodes:
            written = _write_record(
                compressed,
                ("node", node.osm_node_id, node.coordinate.lat, node.coordinate.lng),
                written,
            )
        for edge in graph.edges:
            direction = _DIRECTION_ADAPTER.validate_python(
                edge.edge_id.rsplit(":", 1)[1]
            )
            written = _write_record(
                compressed,
                (
                    "edge",
                    edge.osm_way_id,
                    edge.segment_index,
                    direction,
                    edge.from_node_id,
                    edge.to_node_id,
                    edge.length_m,
                    tag_indexes[_tag_key(edge)],
                ),
                written,
            )


def decode_compact_graph(stream: _BinaryReader) -> HubGraph:
    header, consumed = _read_record(stream, _HEADER_ADAPTER, 0)
    (
        _,
        _,
        _,
        hub_id,
        province_code,
        source_checksum,
        hub_checksum,
        tag_count,
        node_count,
        edge_count,
    ) = header
    _check_counts(tag_count, node_count, edge_count)

    tag_table: list[tuple[SourceTag, ...]] = []
    previous_tag: tuple[tuple[str, str], ...] | None = None
    for expected_index in range(tag_count):
        record, consumed = _read_record(stream, _TAG_ADAPTER, consumed)
        _, index, values = record
        if index != expected_index or (
            previous_tag is not None and values <= previous_tag
        ):
            raise CompactGraphFormatError("tag table is not canonical")
        previous_tag = values
        tag_table.append(
            tuple(SourceTag(key=key, value=value) for key, value in values)
        )

    nodes: list[GraphNode] = []
    coordinates: dict[int, Coordinate] = {}
    previous_node_id = 0
    for _ in range(node_count):
        record, consumed = _read_record(stream, _NODE_ADAPTER, consumed)
        _, node_id, lat, lng = record
        if node_id <= previous_node_id:
            raise CompactGraphFormatError("nodes are not canonical")
        previous_node_id = node_id
        coordinate = Coordinate(lat=lat, lng=lng)
        nodes.append(GraphNode(osm_node_id=node_id, coordinate=coordinate))
        coordinates[node_id] = coordinate

    edges: list[GraphEdge] = []
    for _ in range(edge_count):
        record, consumed = _read_record(stream, _EDGE_ADAPTER, consumed)
        _, way_id, segment, suffix, from_id, to_id, length, tag_index = record
        if not 0 <= tag_index < len(tag_table):
            raise CompactGraphFormatError("edge tag index is invalid")
        edges.append(
            GraphEdge(
                edge_id=f"w{way_id}:s{segment}:{suffix}",
                hub_id=hub_id,
                province_code=province_code,
                source_pbf_checksum=source_checksum,
                osm_way_id=way_id,
                segment_index=segment,
                osm_node_sequence=(from_id, to_id),
                coordinates=(
                    _coordinate(coordinates, from_id),
                    _coordinate(coordinates, to_id),
                ),
                length_m=length,
                tags=tag_table[tag_index],
            )
        )
    if stream.read(1):
        raise CompactGraphFormatError("compact graph has trailing records")
    return HubGraph(
        hub_id=hub_id,
        province_code=province_code,
        source_pbf_checksum=source_checksum,
        hub_pbf_checksum=hub_checksum,
        nodes=tuple(nodes),
        edges=tuple(edges),
    )


def _read_record[T](
    stream: _BinaryReader,
    adapter: TypeAdapter[T],
    consumed: int,
) -> tuple[T, int]:
    line = stream.readline(MAX_GRAPH_RECORD_BYTES + 1)
    updated = consumed + len(line)
    if not line or len(line) > MAX_GRAPH_RECORD_BYTES:
        raise CompactGraphFormatError("compact graph record is invalid")
    if updated > MAX_GRAPH_UNCOMPRESSED_BYTES:
        raise CompactGraphFormatError("compact graph exceeds its decoded byte budget")
    return adapter.validate_json(line), updated


def _write_record(handle: _BinaryWriter, record: _Record, written: int) -> int:
    payload = json.dumps(
        record,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    updated = written + len(payload) + 1
    if len(payload) > MAX_GRAPH_RECORD_BYTES:
        raise CompactGraphFormatError("compact graph record exceeds its byte budget")
    if updated > MAX_GRAPH_UNCOMPRESSED_BYTES:
        raise CompactGraphFormatError("compact graph exceeds its decoded byte budget")
    _ = handle.write(payload)
    _ = handle.write(b"\n")
    return updated


def _check_counts(tag_count: int, node_count: int, edge_count: int) -> None:
    if not 0 <= tag_count <= edge_count:
        raise CompactGraphFormatError("compact graph tag count is invalid")
    if not 0 <= node_count <= MAX_GRAPH_NODES:
        raise CompactGraphFormatError("compact graph node count is invalid")
    if not 0 <= edge_count <= MAX_GRAPH_EDGES:
        raise CompactGraphFormatError("compact graph edge count is invalid")


def _coordinate(coordinates: dict[int, Coordinate], node_id: int) -> Coordinate:
    try:
        return coordinates[node_id]
    except KeyError as error:
        raise CompactGraphFormatError("edge references a missing node") from error


def _tag_key(edge: GraphEdge) -> tuple[tuple[str, str], ...]:
    return tuple((tag.key, tag.value) for tag in edge.tags)
