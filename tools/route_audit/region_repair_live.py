from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import final
from urllib.parse import urlencode, urlsplit

from .region_repair_model import BoundaryArchiveError, RegionRepairTarget
from .region_repair_preflight import parse_targets
from .western_contract import EXPECTED_PROJECT_REF
from .western_source import AuditHttpRequest, AuditTransport

_CONTENT_RANGE = re.compile(r"^0-(\d+)/(\d+)$")
_MAX_TARGET_ROWS = 999


@dataclass(frozen=True, slots=True)
class RegionRepairLiveConfig:
    supabase_url: str
    publishable_key: str = field(repr=False)

    @classmethod
    def create(
        cls, *, supabase_url: str, publishable_key: str
    ) -> RegionRepairLiveConfig:
        parsed = urlsplit(supabase_url.strip())
        expected_host = f"{EXPECTED_PROJECT_REF}.supabase.co"
        if (
            parsed.scheme != "https"
            or parsed.hostname != expected_host
            or parsed.username is not None
            or parsed.password is not None
            or parsed.port is not None
            or parsed.path not in ("", "/")
            or parsed.query
            or parsed.fragment
        ):
            raise BoundaryArchiveError(
                "wrong_project", "SUPABASE_URL must identify Revv production"
            )
        clean_key = publishable_key.strip()
        if not clean_key:
            raise BoundaryArchiveError(
                "missing_publishable_key",
                "a publishable or legacy anon key is required",
            )
        return cls(
            supabase_url=f"https://{expected_host}",
            publishable_key=clean_key,
        )


@final
class RevvRegionRepairSource:
    def __init__(
        self, config: RegionRepairLiveConfig, transport: AuditTransport
    ) -> None:
        self._config = config
        self._transport = transport

    def fetch_targets(self) -> tuple[RegionRepairTarget, ...]:
        query = urlencode(
            {
                "select": "id,region,center_lat,center_lng",
                "or": "(region.is.null,region.eq.)",
                "order": "id.asc",
                "limit": str(_MAX_TARGET_ROWS),
            }
        )
        response = self._transport.send(
            AuditHttpRequest(
                method="GET",
                url=f"{self._config.supabase_url}/rest/v1/curvy_roads?{query}",
                headers={
                    "accept": "application/json",
                    "accept-encoding": "identity",
                    "apikey": self._config.publishable_key,
                    "authorization": f"Bearer {self._config.publishable_key}",
                    "prefer": "count=exact",
                    "user-agent": "revv-read-only-region-repair-preflight/1",
                },
            )
        )
        if response.status_code not in (200, 206):
            raise BoundaryArchiveError(
                "http_error",
                f"read-only target scan failed with HTTP {response.status_code}",
            )
        targets = parse_targets(response.body)
        content_range = response.headers.get("content-range")
        if content_range is None:
            raise BoundaryArchiveError(
                "missing_count", "read-only target scan omitted Content-Range"
            )
        match = _CONTENT_RANGE.fullmatch(content_range)
        if match is None:
            raise BoundaryArchiveError(
                "malformed_count", "read-only target count is malformed"
            )
        last_index, total = (int(value) for value in match.groups())
        if total != len(targets) or last_index + 1 != len(targets):
            raise BoundaryArchiveError(
                "truncated_targets", "read-only target response is incomplete"
            )
        return targets
