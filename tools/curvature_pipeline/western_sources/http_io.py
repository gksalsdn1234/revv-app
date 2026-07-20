from __future__ import annotations

import socket
from pathlib import Path
from typing import ClassVar, final

import httpx2
from pydantic import BaseModel, ConfigDict, Field

from .deadline import DeadlineExceeded, enforce_deadline, remaining_seconds


@final
class HttpTransferError(RuntimeError):
    def __init__(self, url: str, detail: str, attempts: int) -> None:
        self.url = url
        self.detail = detail
        self.attempts = attempts
        super().__init__(f"HTTP transfer failed after {attempts} attempt(s): {detail}")


class HttpSettings(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    max_attempts_per_asset: int = Field(default=2, ge=2, le=2)
    connect_timeout_seconds: float = Field(default=5.0, ge=5.0, le=5.0)
    read_timeout_seconds: float = Field(default=30.0, ge=30.0, le=30.0)
    write_timeout_seconds: float = Field(default=10.0, ge=10.0, le=10.0)
    pool_timeout_seconds: float = Field(default=10.0, ge=10.0, le=10.0)


class DownloadRequest(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    url: str
    destination: Path
    max_bytes: int = Field(gt=0)
    deadline_monotonic: float


class DownloadResult(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    attempts: int
    bytes_written: int


def create_client(settings: HttpSettings) -> httpx2.Client:
    limits = httpx2.Limits(
        max_connections=200,
        max_keepalive_connections=40,
        keepalive_expiry=30.0,
    )
    timeout = httpx2.Timeout(
        connect=settings.connect_timeout_seconds,
        read=settings.read_timeout_seconds,
        write=settings.write_timeout_seconds,
        pool=settings.pool_timeout_seconds,
    )
    transport = httpx2.HTTPTransport(
        http2=True,
        retries=0,
        limits=limits,
        socket_options=[(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)],
    )
    return httpx2.Client(
        transport=transport,
        timeout=timeout,
        follow_redirects=False,
        headers={"User-Agent": "REVV-western-source-v1"},
    )


def download(
    client: httpx2.Client, request: DownloadRequest, settings: HttpSettings
) -> DownloadResult:
    attempts = 0
    last_detail = "retry budget exhausted"
    while attempts < settings.max_attempts_per_asset:
        attempts += 1
        try:
            timeout = _remaining_timeout(request, settings)
            with client.stream("GET", request.url, timeout=timeout) as response:
                if 300 <= response.status_code < 400:
                    raise HttpTransferError(
                        request.url, "redirects are not permitted", attempts
                    )
                if response.status_code >= 500:
                    last_detail = f"upstream status {response.status_code}"
                    continue
                if response.status_code >= 400:
                    raise HttpTransferError(
                        request.url, f"upstream status {response.status_code}", attempts
                    )
                written = _write_response(response, request)
                enforce_deadline(request.deadline_monotonic)
                return DownloadResult(attempts=attempts, bytes_written=written)
        except (
            httpx2.ConnectError,
            httpx2.ConnectTimeout,
            httpx2.ReadError,
            httpx2.ReadTimeout,
            httpx2.RemoteProtocolError,
        ) as error:
            last_detail = type(error).__name__
        except DeadlineExceeded as error:
            raise HttpTransferError(request.url, str(error), attempts) from error
    raise HttpTransferError(request.url, last_detail, attempts)


def _write_response(response: httpx2.Response, request: DownloadRequest) -> int:
    written = 0
    with request.destination.open("wb") as handle:
        for chunk in response.iter_bytes():
            enforce_deadline(request.deadline_monotonic)
            written += len(chunk)
            if written > request.max_bytes:
                raise HttpTransferError(request.url, "stream exceeds byte budget", 1)
            _ = handle.write(chunk)
        handle.flush()
    enforce_deadline(request.deadline_monotonic)
    return written


def _remaining_timeout(
    request: DownloadRequest,
    settings: HttpSettings,
) -> httpx2.Timeout:
    remaining = remaining_seconds(request.deadline_monotonic)
    return httpx2.Timeout(
        connect=min(settings.connect_timeout_seconds, remaining),
        read=min(settings.read_timeout_seconds, remaining),
        write=min(settings.write_timeout_seconds, remaining),
        pool=min(settings.pool_timeout_seconds, remaining),
    )
