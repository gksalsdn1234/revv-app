from __future__ import annotations

import hashlib
import json
from datetime import date
from pathlib import Path
from typing import ClassVar, Final, Literal, final
from urllib.parse import ParseResult, urlparse

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)

ProvinceCode = Literal["AB", "BC", "MB", "SK"]

ALLOWED_PROVINCES: Final[tuple[ProvinceCode, ...]] = ("AB", "BC", "MB", "SK")
GEOFABRIK_HOST: Final = "download.geofabrik.de"
MAX_SOURCE_BYTES: Final = 2 * 1024 * 1024 * 1024
PROVINCE_SLUGS: Final[dict[ProvinceCode, str]] = {
    "AB": "alberta",
    "BC": "british-columbia",
    "MB": "manitoba",
    "SK": "saskatchewan",
}


@final
class ManifestError(RuntimeError):
    def __init__(self, path: Path, detail: str) -> None:
        self.path = path
        self.detail = detail
        super().__init__(f"invalid western source manifest {path}: {detail}")


@final
class ManifestFieldError(ValueError):
    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


class Bounds(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    min_lat: float = Field(ge=-90.0, le=90.0)
    min_lng: float = Field(ge=-180.0, le=180.0)
    max_lat: float = Field(ge=-90.0, le=90.0)
    max_lng: float = Field(ge=-180.0, le=180.0)

    @model_validator(mode="after")
    def ordered(self) -> "Bounds":
        if self.min_lat >= self.max_lat or self.min_lng >= self.max_lng:
            raise ManifestFieldError(
                "bounds must have increasing latitude and longitude"
            )
        return self


class Source(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    province_code: ProvinceCode
    snapshot: date
    url: str
    checksum_url: str
    checksum: str = Field(pattern=r"^[0-9a-f]{32}$")
    size_bytes: int = Field(gt=0, le=MAX_SOURCE_BYTES)

    @field_validator("url", "checksum_url")
    @classmethod
    def absolute_url(cls, value: str) -> str:
        parsed = urlparse(value)
        if not parsed.scheme or not parsed.hostname:
            raise ManifestFieldError("source URLs must be absolute")
        return value

    @model_validator(mode="after")
    def internally_consistent(self) -> "Source":
        slug = PROVINCE_SLUGS[self.province_code]
        snapshot_token = self.snapshot.strftime("%y%m%d")
        expected_name = f"{slug}-{snapshot_token}.osm.pbf"
        if not self.url.endswith(f"/{expected_name}"):
            raise ManifestFieldError(
                "source URL filename does not match province and snapshot"
            )
        if self.checksum_url != f"{self.url}.md5":
            raise ManifestFieldError("checksum URL must be the source URL plus .md5")
        return self

    @property
    def filename(self) -> str:
        return self.url.rsplit("/", 1)[-1]


class Hub(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    hub_id: str = Field(
        pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", min_length=3, max_length=64
    )
    province_code: ProvinceCode
    bounds: Bounds


class WesternManifest(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")

    schema_version: Literal[1]
    generator_version: str = Field(pattern=r"^western-source-v[1-9][0-9]*$")
    snapshot: date
    sources: tuple[Source, ...]
    hubs: tuple[Hub, ...]

    @model_validator(mode="after")
    def complete_western_set(self) -> "WesternManifest":
        source_codes = tuple(source.province_code for source in self.sources)
        if source_codes != ALLOWED_PROVINCES:
            raise ManifestFieldError(
                "sources must be ordered AB, BC, MB, SK exactly once"
            )
        if any(source.snapshot != self.snapshot for source in self.sources):
            raise ManifestFieldError(
                "every source snapshot must match the manifest snapshot"
            )
        hub_ids = tuple(hub.hub_id for hub in self.hubs)
        if len(set(hub_ids)) != len(hub_ids):
            raise ManifestFieldError("hub IDs must be unique")
        hub_codes = {hub.province_code for hub in self.hubs}
        if hub_codes != set(ALLOWED_PROVINCES):
            raise ManifestFieldError(
                "every western province must have at least one hub"
            )
        return self


def _validate_source_url(value: str, fixture_origin: str | None) -> ParseResult:
    parsed = urlparse(value)
    if (
        parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ManifestFieldError(
            "source URLs cannot contain credentials, query, or fragment"
        )
    if fixture_origin is not None:
        fixture = urlparse(fixture_origin)
        if (
            fixture.scheme != "http"
            or fixture.hostname != "127.0.0.1"
            or fixture.port is None
        ):
            raise ManifestFieldError(
                "fixture origin must be an explicit loopback HTTP port"
            )
        if (parsed.scheme, parsed.hostname, parsed.port) != (
            fixture.scheme,
            fixture.hostname,
            fixture.port,
        ):
            raise ManifestFieldError(
                "fixture source URL must stay on the exact fixture origin"
            )
        return parsed
    if (
        parsed.scheme != "https"
        or parsed.hostname != GEOFABRIK_HOST
        or parsed.port not in (None, 443)
    ):
        raise ManifestFieldError(
            "source URL must use the allowlisted Geofabrik HTTPS origin"
        )
    return parsed


def load_manifest(path: Path, *, fixture_origin: str | None = None) -> WesternManifest:
    try:
        manifest = WesternManifest.model_validate_json(path.read_bytes())
        for source in manifest.sources:
            _ = _validate_source_url(source.url, fixture_origin)
            _ = _validate_source_url(source.checksum_url, fixture_origin)
        return manifest
    except (OSError, ValidationError, ManifestFieldError) as error:
        raise ManifestError(path, str(error)) from error


def canonical_manifest_digest(manifest: WesternManifest) -> str:
    return _canonical_digest(manifest)


def canonical_hub_spec_digest(hub: Hub) -> str:
    return _canonical_digest(hub)


def _canonical_digest(model: BaseModel) -> str:
    payload = json.dumps(
        model.model_dump(mode="json"),
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()
