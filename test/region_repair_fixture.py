from __future__ import annotations

import zipfile
from pathlib import Path

import shapefile
from pyproj import Transformer

_PRUID_TO_CODE = {
    "10": "NL",
    "11": "PE",
    "12": "NS",
    "13": "NB",
    "24": "QC",
    "35": "ON",
    "46": "MB",
    "47": "SK",
    "48": "AB",
    "59": "BC",
    "60": "YT",
    "61": "NT",
    "62": "NU",
}


def write_boundary_archive(directory: Path) -> Path:
    stem = directory / "lpr_000a21a_e"
    writer = shapefile.Writer(str(stem), shapeType=shapefile.POLYGON)
    writer.field("PRUID", "C", size="2")
    writer.field("DGUID", "C", size="21")
    writer.field("PRNAME", "C", size="100")
    writer.field("PRENAME", "C", size="100")
    writer.field("PRFNAME", "C", size="100")
    writer.field("PREABBR", "C", size="10")
    writer.field("PRFABBR", "C", size="10")
    writer.field("LANDAREA", "N", size="12", decimal=4)
    transform = Transformer.from_crs(4326, 3347, always_xy=True)
    local_bounds = {
        "QC": (-74.6, -72.5, 44.5, 46.5),
        "ON": (-76.5, -74.4, 44.5, 46.5),
    }
    for pruid, code in _PRUID_TO_CODE.items():
        bounds = local_bounds.get(code)
        if bounds is None:
            offset = int(pruid)
            bounds = (
                -140.0 + offset / 10,
                -139.9 + offset / 10,
                60.0,
                60.1,
            )
        ring = _projected_ring(transform, *bounds)
        writer.poly([ring])
        writer.record(
            pruid,
            f"2021A0002{pruid}",
            code,
            code,
            code,
            code,
            code,
            1.0,
        )
    writer.close()
    _ = stem.with_suffix(".prj").write_text(
        'PROJCS["NAD83_Statistics_Canada_Lambert"]',
        encoding="ascii",
    )
    _ = stem.with_suffix(".xml").write_text(
        "Government of Canada; Statistics Canada EPSG:3347 2021",
        encoding="utf-8",
    )
    archive = directory / "boundaries.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for suffix in (".dbf", ".prj", ".shp", ".shx", ".xml"):
            output.write(stem.with_suffix(suffix), f"lpr_000a21a_e{suffix}")
    return archive


def _projected_ring(
    transform: Transformer,
    west: float,
    east: float,
    south: float,
    north: float,
) -> list[list[float]]:
    points = (
        (west, south),
        (west, north),
        (east, north),
        (east, south),
        (west, south),
    )
    return [[*transform.transform(lng, lat)] for lng, lat in points]
