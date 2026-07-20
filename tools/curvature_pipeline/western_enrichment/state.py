from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
from typing import ClassVar, final

from pydantic import BaseModel, ConfigDict, ValidationError

from .model import RouteOutcome, TileRequest
from .payload import OverpassPayload


class TileState(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    cache_key: str
    payload_sha256: str
    payload_base64: str


class RouteState(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    fingerprint: str
    outcome: RouteOutcome


@final
class EnrichmentStateStore:
    def __init__(self, root: Path) -> None:
        self._root: Path = root
        self._tiles: Path = root / "tiles"
        self._routes: Path = root / "routes"
        self._tiles.mkdir(parents=True, exist_ok=True)
        self._routes.mkdir(parents=True, exist_ok=True)

    def load_tile(self, request: TileRequest) -> OverpassPayload | None:
        path = self._tiles / f"{_digest(request.cache_key.encode())}.json"
        try:
            document = TileState.model_validate_json(path.read_bytes())
            payload = base64.b64decode(document.payload_base64, validate=True)
            if document.cache_key != request.cache_key:
                return None
            if _digest(payload) != document.payload_sha256:
                return None
            return OverpassPayload.model_validate_json(payload)
        except (OSError, ValidationError, binascii.Error):
            return None

    def save_tile(self, request: TileRequest, body: bytes) -> OverpassPayload:
        payload = OverpassPayload.model_validate_json(body)
        canonical = payload.model_dump_json().encode()
        document = TileState(
            cache_key=request.cache_key,
            payload_sha256=_digest(canonical),
            payload_base64=base64.b64encode(canonical).decode(),
        )
        path = self._tiles / f"{_digest(request.cache_key.encode())}.json"
        _atomic_write(path, document.model_dump_json().encode())
        return payload

    def load_route(self, route_id: str, fingerprint: str) -> RouteOutcome | None:
        path = self._routes / f"{_digest(route_id.encode())}.json"
        try:
            document = RouteState.model_validate_json(path.read_bytes())
        except (OSError, ValidationError):
            return None
        if document.fingerprint != fingerprint:
            return None
        return document.outcome

    def save_route(
        self,
        route_id: str,
        fingerprint: str,
        outcome: RouteOutcome,
    ) -> None:
        document = RouteState(fingerprint=fingerprint, outcome=outcome)
        path = self._routes / f"{_digest(route_id.encode())}.json"
        _atomic_write(path, document.model_dump_json().encode())


def _digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _atomic_write(path: Path, value: bytes) -> None:
    temporary = path.with_suffix(f".{os.getpid()}.tmp")
    _ = temporary.write_bytes(value)
    _ = temporary.replace(path)


def route_fingerprint(route_json: str, versions_json: str) -> str:
    return _digest(
        json.dumps(
            [json.loads(route_json), json.loads(versions_json)],
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
    )
