from __future__ import annotations

import json
import re
import zipfile
from pathlib import Path

from bs4 import BeautifulSoup
from lxml import etree

KML_NS = {"kml": "http://www.opengis.net/kml/2.2"}
MAX_KML_BYTES = 32 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 50
MAX_COMPRESSION_RATIO = 100
MAX_PLACEMARKS = 50000
MAX_NODES_PER_PLACEMARK = 10000
SCORE_PATTERNS = (
    re.compile(r"(?:curvature|score)[^0-9]*([0-9]+(?:\.[0-9]+)?)", re.I),
    re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*(?:pts?|score)", re.I),
)


def extract_kml_bytes_from_kmz(
    kmz_path: str | Path,
    max_kml_bytes: int = MAX_KML_BYTES,
) -> bytes:
    with zipfile.ZipFile(kmz_path, "r") as archive:
        members = archive.infolist()
        if len(members) > MAX_ARCHIVE_MEMBERS:
            raise ValueError("KMZ archive contains too many members")
        for member in members:
            if not member.filename.lower().endswith(".kml"):
                continue
            compressed_size = max(member.compress_size, 1)
            if (
                member.file_size > max_kml_bytes
                or member.file_size / compressed_size > MAX_COMPRESSION_RATIO
            ):
                raise ValueError("KML member exceeds the extraction budget")
            with archive.open(member) as source:
                payload = source.read(max_kml_bytes + 1)
            if len(payload) > max_kml_bytes:
                raise ValueError("KML member exceeds the extraction budget")
            return payload
    raise FileNotFoundError("KMZ archive does not contain a KML file")


def parse_description_score(description_html: str | None) -> float:
    if not description_html:
        return 0.0
    soup = BeautifulSoup(description_html, "html.parser")
    text = soup.get_text(" ", strip=True)
    for pattern in SCORE_PATTERNS:
        match = pattern.search(text)
        if match:
            try:
                return float(match.group(1))
            except ValueError:
                continue
    return 0.0


def parse_coordinates(text: str | None) -> list[dict[str, float]]:
    if not text:
        return []
    points: list[dict[str, float]] = []
    for chunk in text.strip().split()[:MAX_NODES_PER_PLACEMARK]:
        parts = chunk.split(",")
        if len(parts) < 2:
            continue
        lng, lat = parts[0], parts[1]
        try:
            points.append({"lat": float(lat), "lng": float(lng)})
        except ValueError:
            continue
    return points


def extract_placemarks_from_kml_bytes(kml_bytes: bytes) -> list[dict[str, object]]:
    if len(kml_bytes) > MAX_KML_BYTES:
        raise ValueError("KML document exceeds the parsing budget")
    parser = etree.XMLParser(resolve_entities=False, no_network=True, huge_tree=False)
    root = etree.fromstring(kml_bytes, parser=parser)
    placemarks = root.xpath(".//kml:Placemark", namespaces=KML_NS)
    if len(placemarks) > MAX_PLACEMARKS:
        raise ValueError("KML document contains too many placemarks")
    records: list[dict[str, object]] = []
    for placemark in placemarks:
        name = (placemark.findtext("kml:name", namespaces=KML_NS) or "").strip()
        description = placemark.findtext("kml:description", namespaces=KML_NS) or ""
        coords_text = placemark.findtext(".//kml:coordinates", namespaces=KML_NS) or ""
        nodes = parse_coordinates(coords_text)
        if len(nodes) < 2:
            continue
        records.append({
            "name": name,
            "description": description,
            "curvature_score": parse_description_score(description),
            "nodes": nodes,
        })
    return records


def extract_placemarks_from_kmz(kmz_path: str | Path) -> list[dict[str, object]]:
    return extract_placemarks_from_kml_bytes(extract_kml_bytes_from_kmz(kmz_path))


def parse_kmz_file(kmz_path: str | Path) -> list[dict[str, object]]:
    return extract_placemarks_from_kmz(kmz_path)


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Extract placemarks from a KMZ file")
    parser.add_argument("kmz", help="Path to KMZ file")
    parser.add_argument("-o", "--output", help="Write JSON output to file")
    args = parser.parse_args(argv)

    placemarks = parse_kmz_file(args.kmz)
    payload = json.dumps(placemarks, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(payload, encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
