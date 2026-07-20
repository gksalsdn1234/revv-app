from __future__ import annotations

import heapq
from collections import Counter
from collections.abc import Callable
from typing import Final

from ..western_graph.model import GraphEdge, HubGraph
from ..western_routes.generator import generate_route_from_edges
from ..western_routes.model import (
    GeneratedRoute,
    GenerationLimits,
    RouteGenerationError,
    RouteRejection,
    SeedFragment,
    SeedSource,
)
from .integration import resolve_native_seed_batches
from .model import (
    DEFAULT_NATIVE_ROUTE_BATCH_LIMITS,
    NativeRouteBatchLimits,
    NativeRouteBatchReceipt,
    NativeRouteBatchResult,
    NativeRouteBatchStatus,
    NativeSeedBatch,
    NativeSeedError,
    NativeSeedRejection,
    ResolvedNativeSeed,
)

# Generation-side mirror of the highway classes the (unchanged) Todo 7
# residential/service exposure gate measures. Used only to steer candidate
# assembly away from exposure-heavy edges; the quality gate itself still
# runs downstream on the exact same signal.
_RESIDENTIAL_HIGHWAY_VALUES: Final = frozenset({"residential", "service"})
# Connector search prefers non-residential detours up to this cost factor
# while the legal cluster rule (<= 12 km actual graph distance) is still
# enforced on the real, unpenalized connector length.
_RESIDENTIAL_CONNECTOR_COST_FACTOR: Final = 4.0
# Assembly keeps stitching curvature seeds past the 15 km floor while the
# running exposure would still fail the (unchanged) >= 0.15 quality gate.
# The 0.14 target leaves deterministic float-summation margin below 0.15.
_REPAIR_TARGET_EXPOSURE: Final = 0.14
# Bounded number of exposure-repair extensions per candidate so hub work
# stays deterministic AND bounded even in residential-dense city graphs.
_MAX_REPAIR_ADDITIONS: Final = 24
# Hard assembly ceiling kept 100 m under the (unchanged) 80 km route gate
# so incremental float accounting can never tip a candidate over the gate.
_MAX_ASSEMBLY_DISTANCE_M: Final = 79_900.0
_MIN_ASSEMBLY_DISTANCE_M: Final = 15_000.0

_AcceptAddition = Callable[[tuple[GraphEdge, ...]], bool]


def generate_native_routes(
    graph: HubGraph,
    batches: tuple[NativeSeedBatch, ...],
    *,
    limits: NativeRouteBatchLimits = DEFAULT_NATIVE_ROUTE_BATCH_LIMITS,
) -> NativeRouteBatchResult:
    if (
        not 1 <= limits.max_candidates <= 25
        or not 1 <= limits.max_start_attempts <= 256
        or not 1 <= limits.max_seeds_per_candidate <= 256
        or not 0.0 < limits.max_connector_distance_m <= 12_000.0
    ):
        raise NativeSeedError(
            NativeSeedRejection.RESOURCE_LIMIT,
            "native route batch limits exceed the fixed hub budgets",
        )
    resolved = resolve_native_seed_batches(graph, batches)
    ranked = tuple(sorted(resolved, key=_seed_rank))
    available = {item.seed.seed_id for item in ranked}
    starts = _starts_by_node(ranked)
    ends = _ends_by_node(ranked)
    adjacency = _adjacency(graph)
    reverse_adjacency = _reverse_adjacency(graph)
    routes: list[GeneratedRoute] = []
    rejections: Counter[RouteRejection] = Counter()
    rejected_details: list[tuple[str, RouteRejection]] = []
    rejected_starts = 0
    attempts = 0
    for start in ranked:
        if (
            len(routes) >= limits.max_candidates
            or attempts >= limits.max_start_attempts
        ):
            break
        if start.seed.seed_id not in available:
            continue
        attempts += 1
        seed_cluster, edges = _assemble_candidate(
            start,
            available,
            starts,
            ends,
            adjacency,
            reverse_adjacency,
            limits,
        )
        fragments = tuple(_fragment(item) for item in seed_cluster)
        mandatory = frozenset(
            node_id
            for item in seed_cluster
            for node_id in (item.edges[0].from_node_id, item.edges[-1].to_node_id)
        )
        try:
            route = generate_route_from_edges(
                graph,
                fragments,
                edges,
                mandatory,
                limits=GenerationLimits(
                    max_seed_connector_m=limits.max_connector_distance_m
                ),
            )
        except RouteGenerationError as error:
            rejected_starts += 1
            rejections[error.reason] += 1
            rejected_details.append((start.seed.seed_id, error.reason))
            available.remove(start.seed.seed_id)
            continue
        routes.append(route)
        available.difference_update(item.seed.seed_id for item in seed_cluster)
    ordered_routes = tuple(sorted(routes, key=lambda route: route.route_id))
    status = (
        NativeRouteBatchStatus.READY if ordered_routes else NativeRouteBatchStatus.NO_GO
    )
    return NativeRouteBatchResult(
        routes=ordered_routes,
        receipt=NativeRouteBatchReceipt(
            hub_id=graph.hub_id,
            status=status,
            input_seed_count=len(resolved),
            candidate_count=len(ordered_routes),
            rejected_start_count=rejected_starts,
            unused_seed_count=len(available),
            rejection_counts=tuple(
                sorted(rejections.items(), key=lambda item: item[0])
            ),
            rejected_start_details=tuple(sorted(rejected_details)),
        ),
    )


def _is_residential(edge: GraphEdge) -> bool:
    return any(
        tag.key == "highway" and tag.value in _RESIDENTIAL_HIGHWAY_VALUES
        for tag in edge.tags
    )


def _residential_length_m(edges: tuple[GraphEdge, ...]) -> float:
    return sum(edge.length_m for edge in edges if _is_residential(edge))


def _seed_residential_ratio(item: ResolvedNativeSeed) -> float:
    total_m = sum(edge.length_m for edge in item.edges)
    if total_m <= 0.0:
        return 0.0
    return _residential_length_m(item.edges) / total_m


def _residential_bucket(item: ResolvedNativeSeed) -> int:
    """Coarse start-priority bucket from the seed's own exposure signal.

    0 = fully non-residential, 1 = below the downstream 15% gate on its
    own, 2 = would fail the gate standing alone. Buckets (not raw floats)
    keep the ordering robust while staying a pure function of the graph.
    """
    ratio = _seed_residential_ratio(item)
    if ratio == 0.0:
        return 0
    return 1 if ratio < 0.15 else 2


def _assemble_candidate(
    start: ResolvedNativeSeed,
    available: set[str],
    starts: dict[int, tuple[ResolvedNativeSeed, ...]],
    ends: dict[int, tuple[ResolvedNativeSeed, ...]],
    adjacency: dict[int, tuple[GraphEdge, ...]],
    reverse_adjacency: dict[int, tuple[GraphEdge, ...]],
    limits: NativeRouteBatchLimits,
) -> tuple[tuple[ResolvedNativeSeed, ...], tuple[GraphEdge, ...]]:
    seeds = [start]
    edges = list(start.edges)
    used_edge_ids = {edge.edge_id for edge in edges}
    total_m = sum(edge.length_m for edge in edges)
    residential_m = _residential_length_m(start.edges)
    repair_additions = 0
    while len(seeds) < limits.max_seeds_per_candidate:
        growing = total_m < _MIN_ASSEMBLY_DISTANCE_M
        exposure = residential_m / total_m if total_m > 0.0 else 0.0
        repairing = (
            not growing
            and exposure >= _REPAIR_TARGET_EXPOSURE
            and repair_additions < _MAX_REPAIR_ADDITIONS
        )
        if not growing and not repairing:
            break
        accepts = _addition_predicate(total_m, residential_m, exposure, repairing)
        current_seed_ids = {item.seed.seed_id for item in seeds}
        prepend = False
        found = _nearest_seed(
            edges[-1].to_node_id,
            available,
            current_seed_ids,
            used_edge_ids,
            starts,
            adjacency,
            limits.max_connector_distance_m,
            accepts,
        )
        if found is None:
            # Head-side (reverse) extension: seed windows frequently
            # terminate at junctions, so a start whose forward frontier is
            # exhausted can still legally grow by stitching an earlier
            # seed whose path ends at the current route head.
            found = _nearest_seed_reverse(
                edges[0].from_node_id,
                available,
                current_seed_ids,
                used_edge_ids,
                ends,
                reverse_adjacency,
                limits.max_connector_distance_m,
                accepts,
            )
            prepend = True
        if found is None:
            break
        connector, following = found
        proposed = (
            (*following.edges, *connector)
            if prepend
            else (*connector, *following.edges)
        )
        proposed_ids = {edge.edge_id for edge in proposed}
        if used_edge_ids.intersection(proposed_ids):
            break
        if prepend:
            edges[0:0] = proposed
        else:
            edges.extend(proposed)
        used_edge_ids.update(proposed_ids)
        total_m += sum(edge.length_m for edge in proposed)
        residential_m += _residential_length_m(proposed)
        if repairing:
            repair_additions += 1
        seeds.append(following)
    return tuple(seeds), tuple(edges)


def _addition_predicate(
    total_m: float,
    residential_m: float,
    exposure: float,
    repairing: bool,
) -> _AcceptAddition:
    def accepts(addition: tuple[GraphEdge, ...]) -> bool:
        addition_m = sum(edge.length_m for edge in addition)
        if total_m + addition_m > _MAX_ASSEMBLY_DISTANCE_M:
            return False
        if not repairing:
            return True
        addition_residential_m = _residential_length_m(addition)
        return (residential_m + addition_residential_m) / (
            total_m + addition_m
        ) < exposure

    return accepts


def _nearest_seed(
    start_node_id: int,
    available: set[str],
    current_seed_ids: set[str],
    used_edge_ids: set[str],
    starts: dict[int, tuple[ResolvedNativeSeed, ...]],
    adjacency: dict[int, tuple[GraphEdge, ...]],
    max_distance_m: float,
    accepts: _AcceptAddition,
) -> tuple[tuple[GraphEdge, ...], ResolvedNativeSeed] | None:
    """Find the closest stitchable seed forward of ``start_node_id``.

    Priority is a residential-penalized connector cost so continuations
    prefer primary/secondary/tertiary pavement, while the legal <= 12 km
    cluster rule is enforced on the real (unpenalized) connector length -
    the reachable set can only shrink versus a pure-distance search, never
    grow.
    """
    queue: list[tuple[float, int]] = [(0.0, start_node_id)]
    best = {start_node_id: 0.0}
    actual = {start_node_id: 0.0}
    parent: dict[int, GraphEdge] = {}
    while queue:
        cost, node_id = heapq.heappop(queue)
        if cost != best.get(node_id):
            continue
        connector = _reconstruct(parent, start_node_id, node_id)
        connector_ids = {edge.edge_id for edge in connector}
        choices = tuple(
            item
            for item in starts.get(node_id, ())
            if item.seed.seed_id in available
            and item.seed.seed_id not in current_seed_ids
            and not used_edge_ids.intersection(edge.edge_id for edge in item.edges)
            and not connector_ids.intersection(edge.edge_id for edge in item.edges)
            and not any(
                _antiparallel_id(edge.edge_id) in used_edge_ids
                or _antiparallel_id(edge.edge_id) in connector_ids
                for edge in item.edges
            )
            and accepts((*connector, *item.edges))
        )
        if choices:
            return connector, min(
                choices,
                key=lambda item: (_seed_residential_ratio(item), item.seed.seed_id),
            )
        for edge in adjacency.get(node_id, ()):
            # Never retrace the assembled route on its reverse carriageway:
            # such U-turn connectors consume both directions of the same
            # physical segment and dead-end the candidate below 15 km (the
            # dominant route_too_short signature in the task-13 evidence).
            if (
                edge.edge_id in used_edge_ids
                or _antiparallel_id(edge.edge_id) in used_edge_ids
            ):
                continue
            candidate_actual = actual[node_id] + edge.length_m
            if candidate_actual > max_distance_m:
                continue
            candidate = cost + _connector_cost(edge)
            previous = best.get(edge.to_node_id)
            if previous is None or candidate < previous - 1e-9:
                best[edge.to_node_id] = candidate
                actual[edge.to_node_id] = candidate_actual
                parent[edge.to_node_id] = edge
                heapq.heappush(queue, (candidate, edge.to_node_id))
    return None


def _nearest_seed_reverse(
    end_node_id: int,
    available: set[str],
    current_seed_ids: set[str],
    used_edge_ids: set[str],
    ends: dict[int, tuple[ResolvedNativeSeed, ...]],
    reverse_adjacency: dict[int, tuple[GraphEdge, ...]],
    max_distance_m: float,
    accepts: _AcceptAddition,
) -> tuple[tuple[GraphEdge, ...], ResolvedNativeSeed] | None:
    """Find the closest stitchable seed that legally leads INTO the head.

    Mirrors ``_nearest_seed`` on the reversed graph: a settled node ``n``
    means a legal forward path ``n -> ... -> end_node_id`` exists whose
    real length is <= 12 km, so a seed whose path ends at ``n`` can be
    prepended without any synthetic join.
    """
    queue: list[tuple[float, int]] = [(0.0, end_node_id)]
    best = {end_node_id: 0.0}
    actual = {end_node_id: 0.0}
    child: dict[int, GraphEdge] = {}
    while queue:
        cost, node_id = heapq.heappop(queue)
        if cost != best.get(node_id):
            continue
        connector = _reconstruct_forward(child, node_id, end_node_id)
        connector_ids = {edge.edge_id for edge in connector}
        choices = tuple(
            item
            for item in ends.get(node_id, ())
            if item.seed.seed_id in available
            and item.seed.seed_id not in current_seed_ids
            and not used_edge_ids.intersection(edge.edge_id for edge in item.edges)
            and not connector_ids.intersection(edge.edge_id for edge in item.edges)
            and not any(
                _antiparallel_id(edge.edge_id) in used_edge_ids
                or _antiparallel_id(edge.edge_id) in connector_ids
                for edge in item.edges
            )
            and accepts((*item.edges, *connector))
        )
        if choices:
            return connector, min(
                choices,
                key=lambda item: (_seed_residential_ratio(item), item.seed.seed_id),
            )
        for edge in reverse_adjacency.get(node_id, ()):
            # Same U-turn guard as the forward search (see _nearest_seed).
            if (
                edge.edge_id in used_edge_ids
                or _antiparallel_id(edge.edge_id) in used_edge_ids
            ):
                continue
            candidate_actual = actual[node_id] + edge.length_m
            if candidate_actual > max_distance_m:
                continue
            candidate = cost + _connector_cost(edge)
            previous = best.get(edge.from_node_id)
            if previous is None or candidate < previous - 1e-9:
                best[edge.from_node_id] = candidate
                actual[edge.from_node_id] = candidate_actual
                child[edge.from_node_id] = edge
                heapq.heappush(queue, (candidate, edge.from_node_id))
    return None


def _connector_cost(edge: GraphEdge) -> float:
    if _is_residential(edge):
        return edge.length_m * _RESIDENTIAL_CONNECTOR_COST_FACTOR
    return edge.length_m


def _antiparallel_id(edge_id: str) -> str:
    """Directed counterpart of one edge ID (``...:f`` <-> ``...:r``)."""
    if edge_id.endswith(":f"):
        return f"{edge_id[:-2]}:r"
    return f"{edge_id[:-2]}:f"


def _reconstruct(
    parent: dict[int, GraphEdge],
    start_node_id: int,
    end_node_id: int,
) -> tuple[GraphEdge, ...]:
    edges: list[GraphEdge] = []
    node_id = end_node_id
    while node_id != start_node_id:
        edge = parent[node_id]
        edges.append(edge)
        node_id = edge.from_node_id
    return tuple(reversed(edges))


def _reconstruct_forward(
    child: dict[int, GraphEdge],
    start_node_id: int,
    end_node_id: int,
) -> tuple[GraphEdge, ...]:
    edges: list[GraphEdge] = []
    node_id = start_node_id
    while node_id != end_node_id:
        edge = child[node_id]
        edges.append(edge)
        node_id = edge.to_node_id
    return tuple(edges)


def _starts_by_node(
    seeds: tuple[ResolvedNativeSeed, ...],
) -> dict[int, tuple[ResolvedNativeSeed, ...]]:
    grouped: dict[int, list[ResolvedNativeSeed]] = {}
    for seed in seeds:
        grouped.setdefault(seed.edges[0].from_node_id, []).append(seed)
    return {
        node_id: tuple(sorted(items, key=lambda item: item.seed.seed_id))
        for node_id, items in grouped.items()
    }


def _ends_by_node(
    seeds: tuple[ResolvedNativeSeed, ...],
) -> dict[int, tuple[ResolvedNativeSeed, ...]]:
    grouped: dict[int, list[ResolvedNativeSeed]] = {}
    for seed in seeds:
        grouped.setdefault(seed.edges[-1].to_node_id, []).append(seed)
    return {
        node_id: tuple(sorted(items, key=lambda item: item.seed.seed_id))
        for node_id, items in grouped.items()
    }


def _adjacency(graph: HubGraph) -> dict[int, tuple[GraphEdge, ...]]:
    grouped: dict[int, list[GraphEdge]] = {}
    for edge in graph.edges:
        grouped.setdefault(edge.from_node_id, []).append(edge)
    return {
        node_id: tuple(sorted(edges, key=lambda edge: edge.edge_id))
        for node_id, edges in grouped.items()
    }


def _reverse_adjacency(graph: HubGraph) -> dict[int, tuple[GraphEdge, ...]]:
    grouped: dict[int, list[GraphEdge]] = {}
    for edge in graph.edges:
        grouped.setdefault(edge.to_node_id, []).append(edge)
    return {
        node_id: tuple(sorted(edges, key=lambda edge: edge.edge_id))
        for node_id, edges in grouped.items()
    }


def _seed_rank(item: ResolvedNativeSeed) -> tuple[int, float, str]:
    density = item.seed.total_turn_degrees / (item.seed.distance_m / 1_000.0)
    return _residential_bucket(item), -density, item.seed.seed_id


def _fragment(item: ResolvedNativeSeed) -> SeedFragment:
    return SeedFragment(
        seed_id=item.seed.seed_id,
        points=item.seed.points,
        road_refs=item.seed.road_refs,
        source=SeedSource.OSM,
        source_license=item.seed.source_license,
    )
