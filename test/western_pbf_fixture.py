"""Synthetic hub-PBF writer shared by western audit CLI tests.

Kept outside the strict Todo 9 basedpyright include on purpose: pyosmium's
``osmium.osm.mutable`` writer API ships no type information, so the typed
test module imports this annotated helper instead of touching osmium
directly (same pattern as ``test/western_source_fixture.py``).
"""

from __future__ import annotations

import hashlib
import math
from pathlib import Path

import osmium


def write_curvy_hub_pbf(
    path: Path, *, id_base: int, base_lat: float, base_lng: float
) -> str:
    """Write a ~36 km zig-zag secondary-road chain PBF; return its sha256.

    The chain mirrors the fixture-hub geometry (1 km spacing, 0.01 deg
    amplitude, 4-segment period) so the real-hub seed derivation finds a
    20-35 km shortest path and the generated route clears the 15 km floor.
    """
    lat_step = 1_000.0 / 111_195.0
    coordinates = [
        (
            base_lng + 0.01 * math.sin(2.0 * math.pi * index / 4.0),
            base_lat + index * lat_step,
        )
        for index in range(31)
    ]
    with osmium.SimpleWriter(str(path), overwrite=True) as writer:
        for index, (lon, lat) in enumerate(coordinates):
            writer.add_node(
                osmium.osm.mutable.Node(id=id_base + index + 1, location=(lon, lat))
            )
        for index in range(30):
            writer.add_way(
                osmium.osm.mutable.Way(
                    id=id_base + 1_000 + index,
                    nodes=[id_base + index + 1, id_base + index + 2],
                    tags={"highway": "secondary", "ref": "T1"},
                )
            )
    return hashlib.sha256(path.read_bytes()).hexdigest()
