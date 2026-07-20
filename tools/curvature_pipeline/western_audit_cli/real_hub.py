from __future__ import annotations

import heapq
from pathlib import Path
from typing import Final

from pydantic import ValidationError

from ..western_graph.builder import GraphBuildError, build_graph_from_pbf
from ..western_graph.graph import weak_components
from ..western_graph.model import Coordinate, HubGraph
from ..western_graph.source import spec_from_acquisition
from ..western_routes.geometry import distance_m
from ..western_routes.model import SeedFragment, SeedSource
from ..western_sources.checkpoint import AcquisitionCheckpoint
from ..western_sources.manifest import ManifestError, WesternManifest, load_manifest
from .model import DryRunError

# Offsets along the chosen shortest path used to place three deterministic
# seed windows (start / middle / end). Picked empirically (task-9 evidence)
# to avoid landing exactly on a real intersection node, which the generator
# rejects as SNAP_AMBIGUOUS.
_SEED_PATH_OFFSETS: Final = (0.15, 0.5, 0.85)
_TARGET_PATH_DISTANCE_RANGE_M: Final = (20_000.0, 35_000.0)
_TARGET_PATH_DISTANCE_PREFERRED_M: Final = 25_000.0
_SEED_MIN_DISTANCE_M: Final = 300.0
_SEED_MAX_DISTANCE_M: Final = 4_000.0
_SEED_MAX_PATH_SPAN_M: Final = 4_000.0
_SEED_WINDOW_MAX_RADIUS_NODES: Final = 60


def load_acquisition_inputs(
    manifest_path: Path, checkpoint_path: Path
) -> tuple[WesternManifest, AcquisitionCheckpoint]:
    """Parse the source manifest and acquisition checkpoint exactly once.

    real-all mode reuses the parsed pair across every hub instead of
    re-reading both files fifteen times.
    """
    try:
        manifest = load_manifest(manifest_path)
    except ManifestError as error:
        raise DryRunError(f"source manifest invalid: {error}") from error
    try:
        checkpoint = AcquisitionCheckpoint.model_validate_json(
            checkpoint_path.read_bytes()
        )
    except (OSError, ValidationError) as error:
        raise DryRunError(f"acquisition checkpoint unreadable: {error}") from error
    return manifest, checkpoint


def build_verified_hub_graph(
    manifest: WesternManifest,
    checkpoint: AcquisitionCheckpoint,
    pbf_path: Path,
    hub_id: str,
) -> HubGraph:
    """Re-verify one hub's checksum chain and re-parse its bounded PBF."""
    try:
        spec = spec_from_acquisition(manifest, checkpoint, hub_id)
        return build_graph_from_pbf(spec, pbf_path)
    except GraphBuildError as error:
        raise DryRunError(
            f"real hub checksum/graph verification failed: {error}"
        ) from error


def load_real_hub_graph(
    manifest_path: Path, checkpoint_path: Path, pbf_path: Path, hub_id: str
) -> HubGraph:
    """Local-file-only equivalent of the acquisition+graph stages.

    No network call happens here: the manifest, the acquisition checkpoint,
    and the bounded hub PBF are all already on disk from a prior real
    ``acquire_western_sources.py`` run (see ``.pipeline-cache/western/``).
    This only re-verifies the checksum chain and re-parses the PBF.
    """
    manifest, checkpoint = load_acquisition_inputs(manifest_path, checkpoint_path)
    return build_verified_hub_graph(manifest, checkpoint, pbf_path, hub_id)


def derive_seeds_from_graph(graph: HubGraph) -> tuple[SeedFragment, ...]:
    """Deterministically place three seeds on a real hub's largest component.

    The whole derivation is a pure function of the checksum-pinned hub
    graph's node/edge IDs (lowest node ID as source, Dijkstra shortest
    paths, midpoint interpolation) - no wall-clock time or randomness, so
    the same real PBF always yields the same seeds and therefore the same
    generated route.
    """
    if not graph.nodes:
        return ()
    components = weak_components(graph)
    largest = max(components, key=lambda component: (len(component), component))
    source_node = min(largest)
    distances, parents = _dijkstra(graph, source_node)
    low, high = _TARGET_PATH_DISTANCE_RANGE_M
    candidates = sorted(
        (
            (distance, node)
            for node, distance in distances.items()
            if low <= distance <= high
        ),
        key=lambda item: (abs(item[0] - _TARGET_PATH_DISTANCE_PREFERRED_M), item[1]),
    )
    if not candidates:
        return ()
    _, target_node = candidates[0]
    path = _reconstruct_path(parents, source_node, target_node)
    coordinates = {node.osm_node_id: node.coordinate for node in graph.nodes}
    cumulative = [0.0]
    for previous, current in zip(path, path[1:]):
        cumulative.append(
            cumulative[-1] + distance_m(coordinates[previous], coordinates[current])
        )
    total_distance_m = cumulative[-1]
    seeds: list[SeedFragment] = []
    for index, offset in enumerate(_SEED_PATH_OFFSETS):
        window = _find_seed_window(
            path, cumulative, coordinates, total_distance_m, offset
        )
        if window is None:
            return ()
        start_point, end_point = window
        seeds.append(
            SeedFragment(
                seed_id=f"real-hub-seed-{index}",
                points=(start_point, end_point),
                road_refs=(),
                source=SeedSource.OSM,
                source_license="ODbL-1.0",
            )
        )
    return tuple(seeds)


def _dijkstra(
    graph: HubGraph, source_node: int
) -> tuple[dict[int, float], dict[int, int]]:
    """Deterministic single-source shortest paths over directed graph edges.

    Neighbors are visited in sorted order and heap ties resolve by node ID,
    so the returned parent tree is a pure function of the graph.
    """
    adjacency: dict[int, list[tuple[int, float]]] = {}
    for edge in graph.edges:
        adjacency.setdefault(edge.from_node_id, []).append(
            (edge.to_node_id, edge.length_m)
        )
    for neighbors in adjacency.values():
        neighbors.sort()
    distances: dict[int, float] = {source_node: 0.0}
    parents: dict[int, int] = {}
    heap: list[tuple[float, int]] = [(0.0, source_node)]
    settled: set[int] = set()
    while heap:
        distance, node = heapq.heappop(heap)
        if node in settled:
            continue
        settled.add(node)
        for neighbor, length_m in adjacency.get(node, ()):
            candidate = distance + length_m
            known = distances.get(neighbor)
            if known is None or candidate < known:
                distances[neighbor] = candidate
                parents[neighbor] = node
                heapq.heappush(heap, (candidate, neighbor))
    return distances, parents


def _reconstruct_path(
    parents: dict[int, int], source_node: int, target_node: int
) -> list[int]:
    reversed_path = [target_node]
    while reversed_path[-1] != source_node:
        reversed_path.append(parents[reversed_path[-1]])
    return list(reversed(reversed_path))


def _interpolate(start: Coordinate, end: Coordinate, fraction: float) -> Coordinate:
    return Coordinate(
        lat=start.lat + (end.lat - start.lat) * fraction,
        lng=start.lng + (end.lng - start.lng) * fraction,
    )


def _find_seed_window(
    path: list[int],
    cumulative: list[float],
    coordinates: dict[int, Coordinate],
    total_distance_m: float,
    center_fraction: float,
) -> tuple[Coordinate, Coordinate] | None:
    center_distance_m = total_distance_m * center_fraction
    center_index = next(
        index for index, value in enumerate(cumulative) if value >= center_distance_m
    )
    for radius in range(1, _SEED_WINDOW_MAX_RADIUS_NODES):
        start_index = max(0, center_index - radius)
        end_index = min(len(path) - 1, center_index + radius)
        if (
            end_index <= start_index
            or start_index + 1 >= len(path)
            or end_index - 1 < 0
        ):
            continue
        # Interpolate a half-step inside each boundary edge so the seed
        # point never lands exactly on a real intersection node (which the
        # generator can reject as SNAP_AMBIGUOUS at busy junctions).
        start_point = _interpolate(
            coordinates[path[start_index]], coordinates[path[start_index + 1]], 0.5
        )
        end_point = _interpolate(
            coordinates[path[end_index - 1]], coordinates[path[end_index]], 0.5
        )
        straight_distance_m = distance_m(start_point, end_point)
        path_span_m = cumulative[end_index] - cumulative[start_index]
        if (
            _SEED_MIN_DISTANCE_M <= straight_distance_m <= _SEED_MAX_DISTANCE_M
            and path_span_m <= _SEED_MAX_PATH_SPAN_M
        ):
            return start_point, end_point
    return None
