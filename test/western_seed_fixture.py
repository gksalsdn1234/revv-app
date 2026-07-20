from __future__ import annotations

import math

from tools.curvature_pipeline.western_graph.builder import (
    HubGraphSpec,
    WayInput,
    build_graph,
)
from tools.curvature_pipeline.western_graph.model import HubGraph


def native_seed_graph(
    *,
    segment_count: int = 24,
    one_way: bool = False,
    straight: bool = False,
) -> HubGraph:
    latitude_step = 1_000.0 / 111_195.0
    coordinates = tuple(
        (
            51.0 + index * latitude_step,
            -114.0 + (0.0 if straight else 0.004 * math.sin(index * math.pi / 2.0)),
        )
        for index in range(segment_count + 1)
    )
    tags = {
        "highway": "secondary",
        "name": "Fixture Curves",
        "ref": "R1",
        "surface": "asphalt",
        **({"oneway": "yes"} if one_way else {}),
    }
    return build_graph(
        HubGraphSpec(
            hub_id="ab-native-seed",
            province_code="AB",
            source_pbf_checksum="c" * 32,
            hub_pbf_checksum="d" * 64,
        ),
        (
            WayInput(
                osm_way_id=50_000,
                osm_node_ids=tuple(range(1, segment_count + 2)),
                coordinates=coordinates,
                tags=tuple(sorted(tags.items())),
            ),
        ),
    )
