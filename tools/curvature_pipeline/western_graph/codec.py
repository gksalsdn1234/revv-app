from __future__ import annotations

import gzip
import io
import os
import stat
import zlib
from enum import StrEnum
from pathlib import Path
from typing import Final, final

from pydantic import ValidationError

from .codec_format import (
    COMPACT_GRAPH_MAGIC,
    MAX_GRAPH_INPUT_BYTES,
    CompactGraphFormatError,
    decode_compact_graph,
    write_compact_graph,
)
from .model import HubGraph


class GraphCodecRejection(StrEnum):
    NOT_REGULAR = "not_regular"
    RESOURCE_LIMIT = "resource_limit"
    READ_FAILURE = "read_failure"
    INVALID_GRAPH = "invalid_graph"


@final
class GraphCodecError(RuntimeError):
    def __init__(
        self,
        path: Path,
        reason: GraphCodecRejection,
        detail: str,
    ) -> None:
        self.path = path
        self.reason = reason
        self.detail = detail
        super().__init__(f"western graph codec failed [{reason}] for {path}: {detail}")


def graph_bytes(graph: HubGraph) -> bytes:
    output = io.BytesIO()
    try:
        write_compact_graph(output, graph)
    except CompactGraphFormatError as error:
        raise GraphCodecError(
            Path("<memory>"),
            GraphCodecRejection.RESOURCE_LIMIT,
            error.detail,
        ) from error
    payload = output.getvalue()
    if len(payload) > MAX_GRAPH_INPUT_BYTES:
        raise GraphCodecError(
            Path("<memory>"),
            GraphCodecRejection.RESOURCE_LIMIT,
            "compact graph exceeds the fixed byte budget",
        )
    return payload


def load_graph(path: Path) -> HubGraph:
    _check_input(path)
    try:
        with path.open("rb") as handle:
            if handle.read(len(COMPACT_GRAPH_MAGIC)) != COMPACT_GRAPH_MAGIC:
                raise CompactGraphFormatError("compact graph magic is invalid")
            with gzip.GzipFile(fileobj=handle, mode="rb") as compressed:
                return decode_compact_graph(compressed)
    except (OSError, EOFError, ValidationError, zlib.error) as error:
        raise GraphCodecError(
            path,
            GraphCodecRejection.INVALID_GRAPH,
            "compact graph records are invalid",
        ) from error
    except CompactGraphFormatError as error:
        raise GraphCodecError(
            path,
            GraphCodecRejection.INVALID_GRAPH,
            error.detail,
        ) from error


def write_graph(path: Path, graph: HubGraph) -> None:
    temporary = path.with_name(f".{path.name}.part")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with temporary.open("wb") as handle:
            write_compact_graph(handle, graph)
            handle.flush()
            os.fsync(handle.fileno())
        if temporary.stat().st_size > MAX_GRAPH_INPUT_BYTES:
            raise CompactGraphFormatError("compact graph exceeds the fixed byte budget")
        os.replace(temporary, path)
    except CompactGraphFormatError as error:
        temporary.unlink(missing_ok=True)
        raise GraphCodecError(
            path,
            GraphCodecRejection.RESOURCE_LIMIT,
            error.detail,
        ) from error
    except OSError as error:
        temporary.unlink(missing_ok=True)
        raise GraphCodecError(
            path,
            GraphCodecRejection.READ_FAILURE,
            "compact graph could not be written",
        ) from error


def _check_input(path: Path) -> None:
    try:
        metadata = path.stat()
    except OSError as error:
        raise GraphCodecError(
            path,
            GraphCodecRejection.READ_FAILURE,
            "graph metadata is unavailable",
        ) from error
    if not stat.S_ISREG(metadata.st_mode):
        raise GraphCodecError(
            path,
            GraphCodecRejection.NOT_REGULAR,
            "graph input must be a regular file",
        )
    if metadata.st_size > MAX_GRAPH_INPUT_BYTES:
        raise GraphCodecError(
            path,
            GraphCodecRejection.RESOURCE_LIMIT,
            "compact graph exceeds the fixed byte budget",
        )


__all__: Final = (
    "COMPACT_GRAPH_MAGIC",
    "MAX_GRAPH_INPUT_BYTES",
    "GraphCodecError",
    "GraphCodecRejection",
    "graph_bytes",
    "load_graph",
    "write_graph",
)
