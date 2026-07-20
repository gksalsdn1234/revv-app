from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Final, Protocol, assert_never, final

import osmium
import typer

from ..western_graph.policy import Direction, evaluate_drivable_way
from .deadline import enforce_deadline
from .manifest import Hub


@final
class StreamingExtractError(RuntimeError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(f"western streaming extract failed: {detail}")


@dataclass(frozen=True, slots=True)
class StreamingLimits:
    max_nodes: int = 500_000
    max_directed_edges: int = 2_000_000


@dataclass(frozen=True, slots=True)
class StreamingExtractReceipt:
    node_count: int
    way_count: int
    directed_edge_count: int


@dataclass(frozen=True, slots=True)
class StreamingExtractTask:
    source: Path
    destination: Path
    hub: Hub
    deadline_monotonic: float | None = None
    limits: StreamingLimits = StreamingLimits()


@dataclass(frozen=True, slots=True)
class _SelectionPolicy:
    hub: Hub
    limits: StreamingLimits
    deadline_monotonic: float | None


class _OsmTag(Protocol):
    k: str
    v: str


class _OsmLocation(Protocol):
    def valid(self) -> bool: ...


class _OsmNodeRef(Protocol):
    ref: int
    lat: float
    lon: float
    location: _OsmLocation


class _OsmWay(Protocol):
    id: int
    tags: tuple[_OsmTag, ...]
    nodes: tuple[_OsmNodeRef, ...]


class _OsmNode(Protocol):
    id: int


class _WayWriter(Protocol):
    def add_way(self, way: _OsmWay) -> None: ...


class _NodeWriter(Protocol):
    def add_node(self, node: _OsmNode) -> None: ...


DEFAULT_STREAMING_LIMITS: Final = StreamingLimits()


def extract_drivable_hub(task: StreamingExtractTask) -> StreamingExtractReceipt:
    if task.limits.max_nodes < 1 or task.limits.max_directed_edges < 1:
        raise StreamingExtractError("extraction limits must be positive")
    sidecar = task.destination.with_suffix(f"{task.destination.suffix}.locations")
    selected_ways = task.destination.with_name(f".{task.destination.name}.ways.osm.pbf")
    sidecar.unlink(missing_ok=True)
    selected_ways.unlink(missing_ok=True)
    task.destination.unlink(missing_ok=True)
    try:
        with osmium.SimpleWriter(str(selected_ways), overwrite=True) as writer:
            handler = _DrivableHubHandler(
                writer,
                _SelectionPolicy(
                    hub=task.hub,
                    limits=task.limits,
                    deadline_monotonic=task.deadline_monotonic,
                ),
            )
            handler.apply_file(
                str(task.source),
                locations=True,
                idx=f"sparse_file_array,{sidecar}",
            )
        with osmium.SimpleWriter(str(task.destination), overwrite=True) as writer:
            node_handler = _ReferencedNodeHandler(writer, handler.node_ids)
            node_handler.apply_file(str(task.source))
            if node_handler.remaining_node_ids:
                raise StreamingExtractError("accepted way has a missing node reference")
            _SelectedWayHandler(writer).apply_file(str(selected_ways))
        return StreamingExtractReceipt(
            node_count=len(handler.node_ids),
            way_count=handler.way_count,
            directed_edge_count=handler.directed_edge_count,
        )
    except StreamingExtractError:
        task.destination.unlink(missing_ok=True)
        raise
    except (OSError, RuntimeError, ValueError) as error:
        task.destination.unlink(missing_ok=True)
        raise StreamingExtractError(str(error)) from error
    finally:
        sidecar.unlink(missing_ok=True)
        selected_ways.unlink(missing_ok=True)


@final
class _DrivableHubHandler(osmium.SimpleHandler):
    """Mutable streaming accumulator required by pyosmium callbacks."""

    def __init__(
        self,
        writer: _WayWriter,
        policy: _SelectionPolicy,
    ) -> None:
        super().__init__()
        self._hub = policy.hub
        self._limits = policy.limits
        self._writer = writer
        self._deadline_monotonic = policy.deadline_monotonic
        self.node_ids: set[int] = set()
        self.way_count = 0
        self.directed_edge_count = 0

    def way(self, way: _OsmWay) -> None:
        if self._deadline_monotonic is not None:
            enforce_deadline(self._deadline_monotonic)
        tags = tuple(sorted((tag.k, tag.v) for tag in way.tags))
        decision = evaluate_drivable_way(dict(tags))
        if decision is None:
            return
        nodes = tuple(way.nodes)
        if len(nodes) < 2 or not all(node.location.valid() for node in nodes):
            raise StreamingExtractError("accepted way has an invalid node reference")
        bounds = self._hub.bounds
        if not any(
            bounds.min_lat <= node.lat <= bounds.max_lat
            and bounds.min_lng <= node.lon <= bounds.max_lng
            for node in nodes
        ):
            return
        match decision.direction:
            case Direction.BOTH:
                multiplier = 2
            case Direction.FORWARD | Direction.REVERSE:
                multiplier = 1
            case unreachable:
                assert_never(unreachable)
        self.directed_edge_count += (len(nodes) - 1) * multiplier
        if self.directed_edge_count > self._limits.max_directed_edges:
            raise StreamingExtractError("directed-edge limit exceeded")
        self.node_ids.update(node.ref for node in nodes)
        if len(self.node_ids) > self._limits.max_nodes:
            raise StreamingExtractError("node limit exceeded")
        self._writer.add_way(way)
        self.way_count += 1


@final
class _ReferencedNodeHandler(osmium.SimpleHandler):
    def __init__(self, writer: _NodeWriter, node_ids: set[int]) -> None:
        super().__init__()
        self._writer = writer
        self.remaining_node_ids = set(node_ids)

    def node(self, node: _OsmNode) -> None:
        if node.id not in self.remaining_node_ids:
            return
        self._writer.add_node(node)
        self.remaining_node_ids.remove(node.id)


@final
class _SelectedWayHandler(osmium.SimpleHandler):
    def __init__(self, writer: _WayWriter) -> None:
        super().__init__()
        self._writer = writer

    def way(self, way: _OsmWay) -> None:
        self._writer.add_way(way)


def stream_cli(
    source: Path,
    destination: Path,
    hub_json: str,
) -> None:
    try:
        receipt = extract_drivable_hub(
            StreamingExtractTask(
                source=source,
                destination=destination,
                hub=Hub.model_validate_json(hub_json),
            )
        )
    except (StreamingExtractError, ValueError) as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(code=1) from error
    typer.echo(
        f"nodes={receipt.node_count} ways={receipt.way_count} "
        f"directed_edges={receipt.directed_edge_count}"
    )


if __name__ == "__main__":
    typer.run(stream_cli)
