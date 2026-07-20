from __future__ import annotations

import socket
from typing import final

import httpx2

from .model import OverpassHttpResponse, TileRequest

USER_AGENT = "REVV-route-pipeline/1.0 (+https://github.com/gksalsdn1234/revv-app)"


def create_overpass_client() -> httpx2.AsyncClient:
    limits = httpx2.Limits(
        max_connections=200,
        max_keepalive_connections=40,
        keepalive_expiry=30.0,
    )
    timeout = httpx2.Timeout(connect=5.0, read=12.0, write=10.0, pool=10.0)
    transport = httpx2.AsyncHTTPTransport(
        http2=True,
        retries=0,
        limits=limits,
        socket_options=[(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)],
    )
    return httpx2.AsyncClient(
        transport=transport,
        timeout=timeout,
        follow_redirects=True,
        headers={"User-Agent": USER_AGENT},
    )


@final
class Httpx2OverpassTransport:
    def __init__(self, client: httpx2.AsyncClient) -> None:
        self._client: httpx2.AsyncClient = client

    async def fetch(
        self,
        endpoint: str,
        request: TileRequest,
        timeout_seconds: float,
    ) -> OverpassHttpResponse:
        south, west, north, east = request.bbox
        query = (
            f"[out:json][timeout:{int(timeout_seconds)}];("
            f'node["highway"~"stop|traffic_signals"]'
            f"({south},{west},{north},{east});"
            f'way["highway"]({south},{west},{north},{east});'
            f'node["tourism"~"viewpoint|attraction"]'
            f"({south},{west},{north},{east}););out body;"
        )
        try:
            response = await self._client.post(endpoint, data={"data": query})
        except httpx2.TimeoutException:
            return OverpassHttpResponse.timeout()
        except httpx2.TransportError:
            return OverpassHttpResponse(status_code=503, body=b"")
        return OverpassHttpResponse(
            status_code=response.status_code,
            body=response.content,
        )
