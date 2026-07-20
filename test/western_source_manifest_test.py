import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import NotRequired, TypedDict

from tools.curvature_pipeline.western_sources.manifest import (
    ManifestError,
    load_manifest,
)


class BoundsPayload(TypedDict):
    min_lat: float
    min_lng: float
    max_lat: float
    max_lng: float


class SourcePayload(TypedDict):
    province_code: str
    snapshot: NotRequired[str]
    url: str
    checksum_url: str
    checksum: NotRequired[str]
    size_bytes: int


class HubPayload(TypedDict):
    hub_id: str
    province_code: str
    bounds: BoundsPayload


class ManifestPayload(TypedDict):
    schema_version: int
    generator_version: str
    snapshot: str
    sources: list[SourcePayload]
    hubs: list[HubPayload]


def valid_manifest() -> ManifestPayload:
    sources: list[SourcePayload] = []
    hubs: list[HubPayload] = []
    for code, slug in (
        ("AB", "alberta"),
        ("BC", "british-columbia"),
        ("MB", "manitoba"),
        ("SK", "saskatchewan"),
    ):
        filename = f"{slug}-260715.osm.pbf"
        sources.append(
            {
                "province_code": code,
                "snapshot": "2026-07-15",
                "url": f"https://download.geofabrik.de/north-america/canada/{filename}",
                "checksum_url": f"https://download.geofabrik.de/north-america/canada/{filename}.md5",
                "checksum": "0" * 32,
                "size_bytes": 1024,
            }
        )
        hubs.append(
            {
                "hub_id": f"{code.lower()}-fixture",
                "province_code": code,
                "bounds": {
                    "min_lat": 49.0,
                    "min_lng": -120.0,
                    "max_lat": 50.0,
                    "max_lng": -119.0,
                },
            }
        )
    return {
        "schema_version": 1,
        "generator_version": "western-source-v1",
        "snapshot": "2026-07-15",
        "sources": sources,
        "hubs": hubs,
    }


class WesternSourceManifestTest(unittest.TestCase):
    def load(self, payload: ManifestPayload) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            load_manifest(path)

    def test_accepts_exact_four_province_https_manifest(self) -> None:
        payload = valid_manifest()
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            manifest = load_manifest(path)

        self.assertEqual(
            [source.province_code for source in manifest.sources],
            ["AB", "BC", "MB", "SK"],
        )
        self.assertEqual(len(manifest.hubs), 4)

    def test_rejects_unknown_province(self) -> None:
        payload = valid_manifest()
        payload["sources"][0]["province_code"] = "XX"
        with self.assertRaises(ManifestError):
            self.load(payload)

    def test_rejects_invalid_bounds(self) -> None:
        payload = valid_manifest()
        payload["hubs"][0]["bounds"]["max_lat"] = 48.0
        with self.assertRaises(ManifestError):
            self.load(payload)

    def test_rejects_duplicate_hub(self) -> None:
        payload = valid_manifest()
        payload["hubs"].append(copy.deepcopy(payload["hubs"][0]))
        with self.assertRaises(ManifestError):
            self.load(payload)

    def test_rejects_non_https_or_unknown_host(self) -> None:
        for url in (
            "http://download.geofabrik.de/alberta.pbf",
            "https://example.invalid/alberta.pbf",
        ):
            payload = valid_manifest()
            payload["sources"][0]["url"] = url
            with self.subTest(url=url), self.assertRaises(ManifestError):
                self.load(payload)

    def test_rejects_missing_snapshot_or_checksum(self) -> None:
        for field in ("snapshot", "checksum"):
            payload = valid_manifest()
            del payload["sources"][0][field]
            with self.subTest(field=field), self.assertRaises(ManifestError):
                self.load(payload)

    def test_rejects_source_above_two_gibibyte_budget(self) -> None:
        payload = valid_manifest()
        payload["sources"][0]["size_bytes"] = (2 * 1024 * 1024 * 1024) + 1
        with self.assertRaises(ManifestError):
            self.load(payload)

    def test_rejects_manifest_snapshot_disagreement(self) -> None:
        payload = valid_manifest()
        payload["sources"][0]["snapshot"] = "2026-07-14"
        with self.assertRaises(ManifestError):
            self.load(payload)


if __name__ == "__main__":
    unittest.main()
