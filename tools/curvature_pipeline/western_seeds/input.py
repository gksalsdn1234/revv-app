from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import assert_never, override

from ..western_graph.codec import (
    MAX_GRAPH_INPUT_BYTES,
    GraphCodecError,
    GraphCodecRejection,
    load_graph,
)
from ..western_graph.model import HubGraph


class GraphInputRejection(StrEnum):
    NOT_REGULAR = "not_regular"
    RESOURCE_LIMIT = "resource_limit"
    READ_FAILURE = "read_failure"
    INVALID_GRAPH = "invalid_graph"


@dataclass(frozen=True, slots=True)
class GraphInputError(RuntimeError):
    reason: GraphInputRejection
    detail: str

    @override
    def __str__(self) -> str:
        return f"western graph input rejected [{self.reason}]: {self.detail}"


def load_bounded_graph(path: Path) -> HubGraph:
    try:
        return load_graph(path)
    except GraphCodecError as error:
        match error.reason:
            case GraphCodecRejection.NOT_REGULAR:
                reason = GraphInputRejection.NOT_REGULAR
            case GraphCodecRejection.RESOURCE_LIMIT:
                reason = GraphInputRejection.RESOURCE_LIMIT
            case GraphCodecRejection.READ_FAILURE:
                reason = GraphInputRejection.READ_FAILURE
            case GraphCodecRejection.INVALID_GRAPH:
                reason = GraphInputRejection.INVALID_GRAPH
            case _:
                assert_never(error.reason)
        raise GraphInputError(reason, "bounded graph input was rejected") from error


__all__ = ("MAX_GRAPH_INPUT_BYTES", "GraphInputError", "load_bounded_graph")
