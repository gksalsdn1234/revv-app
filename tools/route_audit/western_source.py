from __future__ import annotations

import json
import time
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Literal, Protocol, final, override
from urllib.parse import urlsplit

from pydantic import JsonValue, TypeAdapter, ValidationError

from .western_contract import EXPECTED_PROJECT_REF

type AuditJsonValue = JsonValue
type JsonDocument = dict[str, JsonValue] | list[dict[str, JsonValue]]
_JSON_DOCUMENT_ADAPTER: TypeAdapter[JsonDocument] = TypeAdapter(JsonDocument)
_CURVY_ROAD_AUDIT_FIELDS = (
    "id,region,name,center_lat,center_lng,distance_km,winding_score,"
    "is_facility_like,is_connector_like,stop_sign_count,stop_control_density,"
    "max_continuous_km,quality_version,residential_version,"
    "stop_control_version,context_version"
)


@dataclass(frozen=True, slots=True)
class AuditContractError(Exception):
    code: str
    detail: str

    @override
    def __str__(self) -> str:
        return f"{self.code}: {self.detail}"


@dataclass(frozen=True, slots=True)
class AuditHttpRequest:
    method: Literal["GET", "POST"]
    url: str
    headers: Mapping[str, str] = field(repr=False)
    body: bytes | None = None


@dataclass(frozen=True, slots=True)
class AuditHttpResponse:
    status_code: int
    body: bytes
    headers: Mapping[str, str]


@dataclass(frozen=True, slots=True)
class JsonFetch:
    payload: JsonDocument
    payload_bytes: int
    latency_ms: float


class AuditTransport(Protocol):
    def send(self, request: AuditHttpRequest) -> AuditHttpResponse: ...


@dataclass(frozen=True, slots=True)
class LiveAuditConfig:
    supabase_url: str
    publishable_key: str = field(repr=False)
    access_token: str = field(repr=False)
    project_ref: str

    @classmethod
    def create(
        cls, *, supabase_url: str, publishable_key: str, access_token: str
    ) -> LiveAuditConfig:
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
            raise AuditContractError(
                code="wrong_project",
                detail="SUPABASE_URL must identify the Revv production project",
            )
        clean_publishable_key = publishable_key.strip()
        clean_access_token = access_token.strip()
        if (
            not clean_publishable_key
            or not clean_access_token
            or clean_publishable_key == clean_access_token
        ):
            raise AuditContractError(
                code="missing_key",
                detail=(
                    "SUPABASE_PUBLISHABLE_KEY and SUPABASE_AUDIT_ACCESS_TOKEN "
                    "are required"
                ),
            )
        return cls(
            supabase_url=f"https://{expected_host}",
            publishable_key=clean_publishable_key,
            access_token=clean_access_token,
            project_ref=EXPECTED_PROJECT_REF,
        )


@final
class RevvRestAuditSource:
    def __init__(self, config: LiveAuditConfig, transport: AuditTransport) -> None:
        self._config: LiveAuditConfig = config
        self._transport: AuditTransport = transport

    def get_curvy_roads_page(self, *, offset: int, page_size: int) -> JsonDocument:
        if offset < 0 or page_size != 1000:
            raise AuditContractError(
                code="unsafe_page",
                detail="audit pages require a non-negative offset and 1000-row limit",
            )
        query = (
            f"select={_CURVY_ROAD_AUDIT_FIELDS}&order=id.asc"
            f"&limit={page_size}&offset={offset}"
        )
        return self._request_json(
            AuditHttpRequest(
                method="GET",
                url=f"{self._config.supabase_url}/rest/v1/curvy_roads?{query}",
                headers=self._headers(),
            )
        ).payload

    def post_rpc_json(
        self, function_name: str, payload: dict[str, AuditJsonValue]
    ) -> JsonDocument:
        return self.post_rpc_with_metrics(function_name, payload).payload

    def post_rpc_with_metrics(
        self, function_name: str, payload: dict[str, AuditJsonValue]
    ) -> JsonFetch:
        if function_name not in {"find_curvy_roads", "find_curvy_map_segments"}:
            raise AuditContractError(
                code="unsafe_rpc",
                detail="only known stable route lookup RPCs are permitted",
            )
        try:
            body = json.dumps(
                payload,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
        except (TypeError, ValueError) as error:
            raise AuditContractError(
                code="malformed_rpc_payload",
                detail="RPC payload must contain finite JSON values",
            ) from error
        return self._request_json(
            AuditHttpRequest(
                method="POST",
                url=f"{self._config.supabase_url}/rest/v1/rpc/{function_name}",
                headers={**self._headers(), "content-type": "application/json"},
                body=body,
            )
        )

    def _headers(self) -> dict[str, str]:
        return {
            "accept": "application/json",
            "accept-encoding": "identity",
            "apikey": self._config.publishable_key,
            "authorization": f"Bearer {self._config.access_token}",
            "user-agent": "revv-read-only-route-audit/1",
        }

    def _request_json(self, request: AuditHttpRequest) -> JsonFetch:
        started_at = time.perf_counter()
        response: AuditHttpResponse | None = None
        for attempt in range(2):
            response = self._transport.send(request)
            retryable = (
                response.status_code == 429 or 500 <= response.status_code <= 599
            )
            if 200 <= response.status_code < 300:
                break
            if retryable and attempt == 0:
                retry_after = response.headers.get("retry-after")
                try:
                    delay = 0.25 if retry_after is None else float(retry_after)
                except ValueError:
                    delay = 0.25
                time.sleep(min(max(delay, 0.0), 2.0))
                continue
            raise AuditContractError(
                code="http_error",
                detail=f"read-only request failed with HTTP {response.status_code}",
            )
        if response is None:
            raise AuditContractError(
                code="transport_error", detail="request produced no response"
            )
        try:
            payload = _JSON_DOCUMENT_ADAPTER.validate_json(response.body)
            return JsonFetch(
                payload=payload,
                payload_bytes=len(response.body),
                latency_ms=round((time.perf_counter() - started_at) * 1000.0, 3),
            )
        except ValidationError as error:
            raise AuditContractError(
                code="malformed_response",
                detail="read-only endpoint returned invalid JSON",
            ) from error
