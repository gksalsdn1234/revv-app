from __future__ import annotations

import hashlib
import io
import json
import math
import stat
import zipfile
from collections import Counter
from pathlib import Path

import shapefile
from pydantic import TypeAdapter, ValidationError
from pyproj import Transformer
from shapely.geometry import Point, shape

from .region_repair_model import (
    ARCHIVE_MEMBERS,
    ARCHIVE_STEM,
    CODE_TO_REGION,
    MAX_ARCHIVE_BYTES,
    MAX_EXPANDED_BYTES,
    PRUID_TO_CODE,
    STATCAN_ARCHIVE_SHA256,
    STATCAN_ARCHIVE_URL,
    STATCAN_LICENSE_URL,
    STATCAN_PRODUCT_VERSION,
    BoundaryArchiveError,
    ProvinceBoundary,
    ProposedRegionUpdate,
    RegionAmbiguity,
    RegionRepairReport,
    RegionRepairTarget,
)
from .western_contract import EXPECTED_PROJECT_REF


def parse_targets(payload: bytes) -> tuple[RegionRepairTarget, ...]:
    try:
        targets = TypeAdapter(tuple[RegionRepairTarget, ...]).validate_json(payload)
    except ValidationError as error:
        raise BoundaryArchiveError(
            "malformed_targets", "target rows do not match the read-only schema"
        ) from error
    if len({target.id for target in targets}) != len(targets):
        raise BoundaryArchiveError("duplicate_target", "target ids must be unique")
    if any(target.region not in (None, "") for target in targets):
        raise BoundaryArchiveError(
            "unsafe_target", "preflight accepts only null or empty region rows"
        )
    return tuple(sorted(targets, key=lambda target: target.id))


def load_statcan_boundaries(
    archive_path: Path, expected_sha256: str = STATCAN_ARCHIVE_SHA256
) -> tuple[ProvinceBoundary, ...]:
    metadata = archive_path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or archive_path.is_symlink():
        raise BoundaryArchiveError("unsafe_archive", "archive must be a regular file")
    if metadata.st_size > MAX_ARCHIVE_BYTES:
        raise BoundaryArchiveError("archive_too_large", "archive exceeds 8 MiB")
    archive_bytes = archive_path.read_bytes()
    actual_checksum = hashlib.sha256(archive_bytes).hexdigest()
    if actual_checksum != expected_sha256:
        raise BoundaryArchiveError("checksum_mismatch", "boundary checksum differs")
    try:
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            infos = archive.infolist()
            if {info.filename for info in infos} != ARCHIVE_MEMBERS:
                raise BoundaryArchiveError(
                    "archive_members", "boundary archive members differ"
                )
            if sum(info.file_size for info in infos) > MAX_EXPANDED_BYTES:
                raise BoundaryArchiveError(
                    "expanded_too_large", "expanded boundary archive exceeds 8 MiB"
                )
            content = {info.filename: archive.read(info) for info in infos}
    except zipfile.BadZipFile as error:
        raise BoundaryArchiveError("malformed_archive", "archive is not ZIP") from error
    projection = content[f"{ARCHIVE_STEM}.prj"].decode("ascii")
    metadata_xml = content[f"{ARCHIVE_STEM}.xml"].decode("utf-8")
    if "NAD83_Statistics_Canada_Lambert" not in projection:
        raise BoundaryArchiveError("wrong_crs", "boundary CRS is not EPSG:3347")
    if "Statistics Canada" not in metadata_xml or "2021" not in metadata_xml:
        raise BoundaryArchiveError(
            "wrong_source", "boundary metadata is not Statistics Canada 2021"
        )
    reader = shapefile.Reader(
        shp=io.BytesIO(content[f"{ARCHIVE_STEM}.shp"]),
        shx=io.BytesIO(content[f"{ARCHIVE_STEM}.shx"]),
        dbf=io.BytesIO(content[f"{ARCHIVE_STEM}.dbf"]),
        encoding="latin1",
    )
    boundaries: list[ProvinceBoundary] = []
    try:
        for record, raw_shape in zip(reader.records(), reader.shapes(), strict=True):
            pruid = str(record["PRUID"])
            code = PRUID_TO_CODE.get(pruid)
            if code is None or str(record["DGUID"]) != f"2021A0002{pruid}":
                raise BoundaryArchiveError(
                    "unknown_province", "archive contains an unexpected PRUID"
                )
            geometry = shape(raw_shape.__geo_interface__)
            if geometry.is_empty or not geometry.is_valid:
                raise BoundaryArchiveError(
                    "invalid_geometry", f"{code} boundary geometry is invalid"
                )
            boundaries.append(ProvinceBoundary(code=code, geometry=geometry))
    finally:
        reader.close()
    if {boundary.code for boundary in boundaries} != set(CODE_TO_REGION):
        raise BoundaryArchiveError(
            "province_coverage", "archive must contain all 13 provinces/territories"
        )
    return tuple(sorted(boundaries, key=lambda boundary: boundary.code))


def build_preflight_report(
    targets: tuple[RegionRepairTarget, ...],
    boundaries: tuple[ProvinceBoundary, ...],
    *,
    boundary_sha256: str,
    expected_target_count: int,
) -> RegionRepairReport:
    ordered_targets = tuple(sorted(targets, key=lambda target: target.id))
    if len(ordered_targets) != expected_target_count:
        raise BoundaryArchiveError(
            "target_count_changed",
            f"expected {expected_target_count} targets, received {len(ordered_targets)}",
        )
    target_bytes = json.dumps(
        [target.model_dump(mode="json") for target in ordered_targets],
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    transform = Transformer.from_crs(4326, 3347, always_xy=True)
    updates: list[ProposedRegionUpdate] = []
    ambiguities: list[RegionAmbiguity] = []
    for target in ordered_targets:
        expected_region = target.region
        if expected_region is not None and expected_region != "":
            raise BoundaryArchiveError(
                "unsafe_target",
                "preflight accepts only null or empty region rows",
            )
        x, y = transform.transform(target.center_lng, target.center_lat)
        if not math.isfinite(x) or not math.isfinite(y):
            raise BoundaryArchiveError(
                "projection_failed", "canonical coordinate could not be projected"
            )
        point = Point(x, y)
        matches = tuple(
            boundary for boundary in boundaries if boundary.geometry.covers(point)
        )
        if len(matches) != 1:
            ambiguities.append(
                RegionAmbiguity(
                    id=target.id,
                    center_lat=target.center_lat,
                    center_lng=target.center_lng,
                    province_codes=tuple(match.code for match in matches),
                )
            )
            continue
        match = matches[0]
        updates.append(
            ProposedRegionUpdate(
                id=target.id,
                expected_region=expected_region,
                center_lat=target.center_lat,
                center_lng=target.center_lng,
                province_code=match.code,
                region=CODE_TO_REGION[match.code],
                boundary_distance_m=round(match.geometry.boundary.distance(point), 3),
            )
        )
    counts = Counter(update.province_code for update in updates)
    return RegionRepairReport(
        schema_version="revv-region-repair-preflight-v1",
        project_ref=EXPECTED_PROJECT_REF,
        source_url=STATCAN_ARCHIVE_URL,
        source_product=STATCAN_PRODUCT_VERSION,
        source_license_url=STATCAN_LICENSE_URL,
        boundary_sha256=boundary_sha256,
        target_snapshot_sha256=hashlib.sha256(target_bytes).hexdigest(),
        target_count=len(ordered_targets),
        unique_count=len(updates),
        ambiguous_count=len(ambiguities),
        province_counts=dict(sorted(counts.items())),
        proposed_updates=tuple(updates),
        ambiguities=tuple(ambiguities),
        production_writes=0,
    )


def canonical_json(report: RegionRepairReport) -> bytes:
    return (
        json.dumps(
            report.model_dump(mode="json"),
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")
