from __future__ import annotations

from ..western_graph.model import HubGraph
from .extractor import GENERATOR_VERSION, native_seed_paths
from .model import (
    DEFAULT_NATIVE_SEED_LIMITS,
    NativeSeed,
    NativeSeedBatch,
    NativeSeedLimits,
)


def extract_native_seed_batches(
    graph: HubGraph,
    *,
    limits: NativeSeedLimits = DEFAULT_NATIVE_SEED_LIMITS,
) -> tuple[NativeSeedBatch, ...]:
    batches = tuple(
        _native_seed_batch(graph, path_seeds[start : start + limits.max_seeds])
        for path_seeds in native_seed_paths(graph, limits=limits)
        for start in range(0, len(path_seeds), limits.max_seeds)
    )
    return tuple(
        sorted(
            batches,
            key=lambda batch: tuple(seed.seed_id for seed in batch.seeds),
        )
    )


def _native_seed_batch(
    graph: HubGraph,
    seeds: tuple[NativeSeed, ...],
) -> NativeSeedBatch:
    return NativeSeedBatch(
        schema_version=1,
        generator_version=GENERATOR_VERSION,
        hub_id=graph.hub_id,
        province_code=graph.province_code,
        source_pbf_checksum=graph.source_pbf_checksum,
        hub_pbf_checksum=graph.hub_pbf_checksum,
        seeds=tuple(sorted(seeds, key=lambda seed: seed.seed_id)),
    )
