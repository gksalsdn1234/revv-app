#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#     "osmium==4.3.1",
#     "pydantic==2.13.2",
#     "typer==0.21.0",
# ]
# ///

# ─── How to run ───
# 1. Install uv (if not installed):
#      curl -LsSf https://astral.sh/uv/install.sh | sh
# 2. Run from the repository root (no venv or pip install needed):
#      uv run python -m tools.curvature_pipeline.generate_native_route GRAPH DIR
# ─────────────────

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Never

import typer

from tools.curvature_pipeline.western_routes.codec import route_batch_bytes
from tools.curvature_pipeline.western_routes.model import RouteGenerationError
from tools.curvature_pipeline.western_seeds import (
    NativeSeedError,
    NativeRouteBatchStatus,
    extract_native_seed_batches,
    generate_native_routes,
    seed_batches_bytes,
)
from tools.curvature_pipeline.western_seeds.input import (
    GraphInputError,
    load_bounded_graph,
)
from tools.curvature_pipeline.western_seeds.publish import (
    ArtifactPublishError,
    publish_artifact_pair,
)


def main(graph_path: Path, output_dir: Path) -> None:
    try:
        graph = load_bounded_graph(graph_path)
        batches = extract_native_seed_batches(graph)
        result = generate_native_routes(graph, batches)
        if result.receipt.status is NativeRouteBatchStatus.NO_GO:
            _fail("native_routes:no_go")
        seeds = seed_batches_bytes(batches)
        generated_routes = route_batch_bytes(result.routes)
        publish_artifact_pair(output_dir, seeds=seeds, routes=generated_routes)
    except GraphInputError as error:
        _fail(f"graph_input:{error.reason}")
    except NativeSeedError as error:
        _fail(f"native_seed:{error.reason}")
    except RouteGenerationError as error:
        _fail(f"route_generation:{error.reason}")
    except ArtifactPublishError:
        _fail("artifact_publish")
    typer.echo(
        json.dumps(
            {
                "candidate_count": result.receipt.candidate_count,
                "rejected_start_count": result.receipt.rejected_start_count,
                "route_ids": [route.route_id for route in result.routes],
                "routes_sha256": hashlib.sha256(generated_routes).hexdigest(),
                "seed_cluster_count": len(batches),
                "seed_count": result.receipt.input_seed_count,
                "seed_sha256": hashlib.sha256(seeds).hexdigest(),
                "status": result.receipt.status,
                "unused_seed_count": result.receipt.unused_seed_count,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def _fail(reason: str) -> Never:
    typer.echo(f"error:{reason}", err=True)
    raise typer.Exit(2) from None


if __name__ == "__main__":
    typer.run(main)
