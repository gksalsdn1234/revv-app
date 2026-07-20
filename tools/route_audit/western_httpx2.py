from __future__ import annotations

import socket
from collections.abc import Iterable
from types import TracebackType
from typing import cast, final

import httpx2

from .western_source import AuditContractError, AuditHttpRequest, AuditHttpResponse

MAX_RESPONSE_BYTES = 16 * 1024 * 1024


def collect_bounded_identity_body(
    chunks: Iterable[bytes],
    *,
    content_encoding: str | None,
    max_bytes: int = MAX_RESPONSE_BYTES,
) -> bytes:
    encoding = (content_encoding or "identity").strip().lower()
    if encoding not in ("", "identity"):
        raise AuditContractError(
            code="unsupported_encoding",
            detail="audit responses must use identity encoding",
        )
    body = bytearray()
    for chunk in chunks:
        if len(body) + len(chunk) > max_bytes:
            raise AuditContractError(
                code="response_too_large",
                detail="audit response exceeds the 16 MiB response budget",
            )
        body.extend(chunk)
    return bytes(body)


@final
class Httpx2AuditTransport:
    def __init__(self) -> None:
        limits = httpx2.Limits(
            max_connections=200,
            max_keepalive_connections=40,
            keepalive_expiry=30.0,
        )
        timeout = httpx2.Timeout(
            connect=5.0,
            read=30.0,
            write=10.0,
            pool=10.0,
        )
        transport = httpx2.HTTPTransport(
            http2=True,
            retries=0,
            limits=limits,
            socket_options=[(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)],
        )
        self._client: httpx2.Client = httpx2.Client(
            transport=transport,
            timeout=timeout,
            follow_redirects=False,
        )

    def __enter__(self) -> Httpx2AuditTransport:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self._client.close()

    def send(self, request: AuditHttpRequest) -> AuditHttpResponse:
        try:
            with self._client.stream(
                request.method,
                request.url,
                headers=dict(request.headers),
                content=request.body,
            ) as response:
                content_length = cast(
                    str | None, response.headers.get("content-length")
                )
                if content_length is not None:
                    try:
                        parsed_length = int(content_length)
                        if parsed_length < 0 or parsed_length > MAX_RESPONSE_BYTES:
                            raise AuditContractError(
                                code="response_too_large",
                                detail=(
                                    "audit response exceeds the 16 MiB response budget"
                                ),
                            )
                    except ValueError as error:
                        raise AuditContractError(
                            code="malformed_content_length",
                            detail="audit response has an invalid Content-Length",
                        ) from error
                body = collect_bounded_identity_body(
                    response.iter_raw(),
                    content_encoding=cast(
                        str | None, response.headers.get("content-encoding")
                    ),
                )
                return AuditHttpResponse(
                    status_code=response.status_code,
                    body=body,
                    headers=dict(response.headers),
                )
        except httpx2.HTTPError as error:
            raise AuditContractError(
                code="transport_error",
                detail="read-only audit transport failed",
            ) from error
