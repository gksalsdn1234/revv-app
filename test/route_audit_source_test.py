from __future__ import annotations

import unittest
from dataclasses import dataclass, field
from unittest.mock import patch

import httpx2

from tools.route_audit.western_baseline import (
    AuditContractError,
    AuditHttpRequest,
    AuditHttpResponse,
    LiveAuditConfig,
    RevvRestAuditSource,
)
from tools.route_audit.western_httpx2 import (
    Httpx2AuditTransport,
    collect_bounded_identity_body,
)


@dataclass(frozen=True, slots=True)
class ScriptedTransport:
    responses: list[AuditHttpResponse]
    requests: list[AuditHttpRequest] = field(default_factory=list)

    def send(self, request: AuditHttpRequest) -> AuditHttpResponse:
        self.requests.append(request)
        if not self.responses:
            raise AssertionError("unexpected transport call")
        return self.responses.pop(0)


class WesternBaselineSourceContractTest(unittest.TestCase):
    def _config(self) -> LiveAuditConfig:
        return LiveAuditConfig.create(
            supabase_url="https://zvwgnduuumksuqazpvsf.supabase.co",
            publishable_key="publishable-key",
            access_token="authenticated-user-token",
        )

    def test_success_status_with_malformed_json_is_not_reported_as_success(
        self,
    ) -> None:
        transport = ScriptedTransport(
            responses=[AuditHttpResponse(status_code=200, body=b"not-json", headers={})]
        )
        source = RevvRestAuditSource(
            self._config(),
            transport,
        )

        with self.assertRaises(AuditContractError):
            _ = source.get_curvy_roads_page(offset=0, page_size=1000)
        self.assertEqual(len(transport.requests), 1)

    def test_live_source_retries_429_once_and_never_mutates(self) -> None:
        transport = ScriptedTransport(
            responses=[
                AuditHttpResponse(
                    status_code=429, body=b"{}", headers={"retry-after": "0"}
                ),
                AuditHttpResponse(
                    status_code=200, body=b'[{"id":"route-1"}]', headers={}
                ),
            ]
        )
        source = RevvRestAuditSource(
            self._config(),
            transport,
        )

        payload = source.get_curvy_roads_page(offset=0, page_size=1000)

        self.assertEqual(payload, [{"id": "route-1"}])
        self.assertEqual(len(transport.requests), 2)
        self.assertTrue(all(request.method == "GET" for request in transport.requests))
        self.assertTrue(all(request.body is None for request in transport.requests))

    def test_retry_after_is_capped_at_two_seconds(self) -> None:
        transport = ScriptedTransport(
            responses=[
                AuditHttpResponse(
                    status_code=429,
                    body=b"{}",
                    headers={"retry-after": "999999"},
                ),
                AuditHttpResponse(status_code=200, body=b"[]", headers={}),
            ]
        )
        source = RevvRestAuditSource(self._config(), transport)

        with patch("tools.route_audit.western_source.time.sleep") as sleep:
            self.assertEqual(source.get_curvy_roads_page(offset=0, page_size=1000), [])

        sleep.assert_called_once_with(2.0)

    def test_live_source_fails_before_io_for_wrong_project_or_missing_key(self) -> None:
        transport = ScriptedTransport(responses=[])
        with self.assertRaises(AuditContractError):
            _ = LiveAuditConfig.create(
                supabase_url="https://wrongprojectref0000.supabase.co",
                publishable_key="publishable-key",
                access_token="authenticated-user-token",
            )
        with self.assertRaises(AuditContractError):
            _ = LiveAuditConfig.create(
                supabase_url="https://zvwgnduuumksuqazpvsf.supabase.co",
                publishable_key="publishable-key",
                access_token="",
            )
        with self.assertRaises(AuditContractError):
            _ = LiveAuditConfig.create(
                supabase_url="https://zvwgnduuumksuqazpvsf.supabase.co",
                publishable_key="anon-alone",
                access_token="anon-alone",
            )
        self.assertEqual(transport.requests, [])

    def test_live_source_rejects_unknown_rpc_before_io(self) -> None:
        transport = ScriptedTransport(responses=[])
        source = RevvRestAuditSource(self._config(), transport)

        with self.assertRaises(AuditContractError):
            _ = source.post_rpc_json("delete_users", {})
        self.assertEqual(transport.requests, [])

    def test_nonfinite_rpc_payload_is_rejected_before_io(self) -> None:
        transport = ScriptedTransport(responses=[])
        source = RevvRestAuditSource(self._config(), transport)
        with self.assertRaises(AuditContractError):
            _ = source.post_rpc_json("find_curvy_roads", {"min_score": float("nan")})
        self.assertEqual(transport.requests, [])

    def test_redirect_is_rejected_without_following_it(self) -> None:
        transport = ScriptedTransport(
            responses=[AuditHttpResponse(status_code=302, body=b"[]", headers={})]
        )
        source = RevvRestAuditSource(self._config(), transport)
        with self.assertRaises(AuditContractError):
            _ = source.get_curvy_roads_page(offset=0, page_size=1000)
        self.assertEqual(len(transport.requests), 1)

    def test_page_request_is_fixed_and_uses_separate_authentication(self) -> None:
        transport = ScriptedTransport(
            responses=[AuditHttpResponse(status_code=200, body=b"[]", headers={})]
        )
        source = RevvRestAuditSource(self._config(), transport)
        _ = source.get_curvy_roads_page(offset=2000, page_size=1000)
        request = transport.requests[0]
        self.assertIn("/rest/v1/curvy_roads?select=id,region,name", request.url)
        self.assertIn("limit=1000&offset=2000", request.url)
        self.assertEqual(request.headers["apikey"], "publishable-key")
        self.assertEqual(
            request.headers["authorization"], "Bearer authenticated-user-token"
        )
        self.assertEqual(request.headers["accept-encoding"], "identity")
        self.assertNotIn("publishable-key", repr(self._config()))
        self.assertNotIn("authenticated-user-token", repr(self._config()))
        self.assertNotIn("publishable-key", repr(request))
        self.assertNotIn("authenticated-user-token", repr(request))

    def test_response_body_and_encoding_are_bounded(self) -> None:
        self.assertEqual(
            collect_bounded_identity_body(
                [b"abc", b"def"], content_encoding="identity", max_bytes=6
            ),
            b"abcdef",
        )
        with self.assertRaises(AuditContractError):
            _ = collect_bounded_identity_body(
                [b"abcdef", b"g"], content_encoding=None, max_bytes=6
            )
        with self.assertRaises(AuditContractError):
            _ = collect_bounded_identity_body(
                [b"abc"], content_encoding="gzip", max_bytes=6
            )

    def test_transport_failure_is_redacted_and_fail_closed(self) -> None:
        request = AuditHttpRequest(
            method="GET",
            url="https://zvwgnduuumksuqazpvsf.supabase.co/rest/v1/curvy_roads",
            headers={"authorization": "Bearer audit-secret"},
        )
        with Httpx2AuditTransport() as transport:
            with patch(
                "tools.route_audit.western_httpx2.httpx2.Client.stream",
                side_effect=httpx2.ConnectTimeout("sensitive transport detail"),
            ):
                with self.assertRaises(AuditContractError) as caught:
                    _ = transport.send(request)

        self.assertEqual(caught.exception.code, "transport_error")
        self.assertNotIn("audit-secret", str(caught.exception))
        self.assertNotIn("sensitive", str(caught.exception))


if __name__ == "__main__":
    _ = unittest.main()
