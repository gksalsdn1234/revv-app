from __future__ import annotations

from dataclasses import dataclass

import anyio
from pydantic import ValidationError

from .model import (
    MonotonicClock,
    OverpassHttpResponse,
    OverpassTransport,
    TileRequest,
)
from .payload import OverpassPayload
from .state import EnrichmentStateStore

ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)
MAX_UNIQUE_TILE_QUERIES = 120
MAX_REQUEST_ATTEMPTS = 240
REQUEST_TIMEOUT_SECONDS = 12.0
MAX_BATCH_SECONDS = 60.0 * 60.0
MAX_CONCURRENCY = 2
HTTP_OK = 200
HTTP_TOO_MANY_REQUESTS = 429
HTTP_SERVER_ERROR_MIN = 500
MAX_RESPONSE_BYTES = 8 * 1024 * 1024


@dataclass(frozen=True, slots=True)
class TileFetchResult:
    payload: OverpassPayload | None
    attempts: int
    time_budget_exceeded: bool


async def fetch_tile(
    request: TileRequest,
    transport: OverpassTransport,
    store: EnrichmentStateStore,
    clock: MonotonicClock,
    started_at: float,
) -> TileFetchResult:
    attempts = 0
    for endpoint in ENDPOINTS:
        remaining_seconds = MAX_BATCH_SECONDS - (clock.now() - started_at)
        if remaining_seconds <= 0.0:
            return TileFetchResult(None, attempts, True)
        request_timeout = min(REQUEST_TIMEOUT_SECONDS, remaining_seconds)
        attempts += 1
        try:
            with anyio.fail_after(request_timeout):
                response = await transport.fetch(
                    endpoint,
                    request,
                    request_timeout,
                )
        except TimeoutError:
            response = OverpassHttpResponse.timeout()
        if clock.now() - started_at >= MAX_BATCH_SECONDS:
            return TileFetchResult(None, attempts, True)
        if response.timed_out:
            continue
        if (
            response.status_code == HTTP_TOO_MANY_REQUESTS
            or response.status_code >= HTTP_SERVER_ERROR_MIN
        ):
            continue
        if response.status_code != HTTP_OK:
            return TileFetchResult(None, attempts, False)
        if len(response.body) > MAX_RESPONSE_BYTES:
            continue
        try:
            payload = store.save_tile(request, response.body)
        except ValidationError:
            continue
        return TileFetchResult(payload, attempts, False)
    return TileFetchResult(None, attempts, False)
