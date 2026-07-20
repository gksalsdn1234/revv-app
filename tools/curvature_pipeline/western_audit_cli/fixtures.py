from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Final

from ..western_graph.builder import HubGraphSpec, WayInput, build_graph
from ..western_graph.model import Coordinate, HubGraph
from ..western_routes.model import SeedFragment, SeedSource
from ..western_sources.manifest import ProvinceCode

# Fixed 32-hex-char stand-ins for a checksum-pinned provincial PBF. Dry-run
# fixture mode never touches the network, so these are constant labels, not
# real Geofabrik checksums.
_AB_SOURCE_CHECKSUM: Final = "a" * 32
_BC_SOURCE_CHECKSUM: Final = "b" * 32
_SK_SOURCE_CHECKSUM: Final = "c" * 32
_HUB_PBF_CHECKSUM: Final = "d" * 64


@dataclass(frozen=True, slots=True)
class FixtureHub:
    graph: HubGraph
    seeds: tuple[SeedFragment, ...]


def _curvy_chain(
    *,
    hub_id: str,
    province_code: ProvinceCode,
    source_checksum: str,
    segment_count: int,
    spacing_m: float,
    base_lat: float,
    base_lng: float,
    amplitude_deg: float,
    period_segments: float,
    id_base: int,
) -> HubGraph:
    """A deterministic zig-zag chain of ``highway=secondary`` ways.

    Amplitude/period were picked empirically (see task-9 evidence) so the
    resulting route clears the Todo 7 curved-distance and curved-ratio
    quality gates without any human curation of a real KML seed.

    ``id_base`` keeps each hub's synthetic OSM way/node IDs in a disjoint
    range: ``canonical_route_id`` hashes way IDs, segment indices, and node
    IDs (not coordinates), so two hubs built from the same 0-based ID scheme
    would otherwise collide onto the identical route ID.
    """
    lat_step = spacing_m / 111_195.0
    coordinates = tuple(
        (
            base_lat + index * lat_step,
            base_lng
            + amplitude_deg * math.sin(2.0 * math.pi * index / period_segments),
        )
        for index in range(segment_count + 1)
    )
    ways = tuple(
        WayInput(
            osm_way_id=id_base + index,
            osm_node_ids=(id_base + index + 1, id_base + index + 2),
            coordinates=(coordinates[index], coordinates[index + 1]),
            tags=(("highway", "secondary"), ("ref", "F1")),
        )
        for index in range(segment_count)
    )
    return build_graph(
        HubGraphSpec(
            hub_id=hub_id,
            province_code=province_code,
            source_pbf_checksum=source_checksum,
            hub_pbf_checksum=_HUB_PBF_CHECKSUM,
        ),
        ways,
    )


def _point_between(
    graph: HubGraph, id_base: int, edge_index: int, fraction: float
) -> Coordinate:
    nodes = {node.osm_node_id: node.coordinate for node in graph.nodes}
    start = nodes[id_base + edge_index + 1]
    end = nodes[id_base + edge_index + 2]
    return Coordinate(
        lat=start.lat + (end.lat - start.lat) * fraction,
        lng=start.lng + (end.lng - start.lng) * fraction,
    )


def _licensed_seed(
    graph: HubGraph, id_base: int, seed_id: str, first_edge: int, last_edge: int
) -> SeedFragment:
    points = (
        _point_between(graph, id_base, first_edge, 0.2),
        _point_between(graph, id_base, last_edge, 0.8),
    )
    return SeedFragment(
        seed_id=seed_id,
        points=points,
        road_refs=("F1",),
        source=SeedSource.OSM,
        source_license="ODbL-1.0",
    )


def build_default_fixture_hubs() -> tuple[FixtureHub, ...]:
    """Two viable curvy hubs (AB, BC) plus one deliberately sparse hub (SK).

    The SK hub is intentionally too short to ever produce a 15-80 km route,
    which is the plan's own documented expectation for western Saskatchewan
    coverage ("Include expected Saskatchewan sparsity ... do not fill quotas
    with poor routes") - it exercises that behavior directly instead of
    hiding it.
    """
    ab_id_base = 20_000
    bc_id_base = 30_000
    sk_id_base = 40_000
    ab_graph = _curvy_chain(
        hub_id="ab-audit-fixture",
        province_code="AB",
        source_checksum=_AB_SOURCE_CHECKSUM,
        segment_count=24,
        spacing_m=1_000.0,
        base_lat=51.00,
        base_lng=-114.00,
        amplitude_deg=0.01,
        period_segments=4.0,
        id_base=ab_id_base,
    )
    bc_graph = _curvy_chain(
        hub_id="bc-audit-fixture",
        province_code="BC",
        source_checksum=_BC_SOURCE_CHECKSUM,
        segment_count=24,
        spacing_m=1_000.0,
        base_lat=49.50,
        base_lng=-123.00,
        amplitude_deg=0.02,
        period_segments=6.0,
        id_base=bc_id_base,
    )
    sk_graph = _curvy_chain(
        hub_id="sk-audit-fixture",
        province_code="SK",
        source_checksum=_SK_SOURCE_CHECKSUM,
        segment_count=4,
        spacing_m=500.0,
        base_lat=50.20,
        base_lng=-107.80,
        amplitude_deg=0.002,
        period_segments=4.0,
        id_base=sk_id_base,
    )
    ab_seeds = (
        _licensed_seed(ab_graph, ab_id_base, "ab-seed-a", 0, 3),
        _licensed_seed(ab_graph, ab_id_base, "ab-seed-b", 9, 12),
        _licensed_seed(ab_graph, ab_id_base, "ab-seed-c", 18, 21),
    )
    bc_seeds = (
        _licensed_seed(bc_graph, bc_id_base, "bc-seed-a", 0, 3),
        _licensed_seed(bc_graph, bc_id_base, "bc-seed-b", 9, 12),
        _licensed_seed(bc_graph, bc_id_base, "bc-seed-c", 18, 21),
    )
    sk_seeds = (_licensed_seed(sk_graph, sk_id_base, "sk-seed-a", 0, 2),)
    return (
        FixtureHub(ab_graph, ab_seeds),
        FixtureHub(bc_graph, bc_seeds),
        FixtureHub(sk_graph, sk_seeds),
    )


def build_empty_fixture_hubs() -> tuple[FixtureHub, ...]:
    """A hub with zero seeds, for the deliberate zero-viable-routes QA case."""
    ab_graph = _curvy_chain(
        hub_id="ab-audit-empty",
        province_code="AB",
        source_checksum=_AB_SOURCE_CHECKSUM,
        segment_count=6,
        spacing_m=500.0,
        base_lat=51.00,
        base_lng=-114.00,
        amplitude_deg=0.002,
        period_segments=4.0,
        id_base=50_000,
    )
    return (FixtureHub(ab_graph, ()),)


def fixture_overpass_body() -> bytes:
    return (
        b'{"elements":['
        b'{"type":"node","id":9001,"lat":51.0005,"lon":-114.0005,'
        b'"tags":{"highway":"stop"}},'
        b'{"type":"way","id":9002,"tags":{"highway":"secondary",'
        b'"name":"Fixture Ridge Road","surface":"asphalt"}}]}'
    )


def incomplete_overpass_body() -> bytes:
    """A syntactically valid response with no usable highway context."""
    return b'{"elements":[]}'
