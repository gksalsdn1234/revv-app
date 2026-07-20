from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import final

import anyio
from pydantic import ValidationError

from .bridge import BridgeInputs, SelectionBridgeError, load_bridge
from .model import EnrichmentRuntime, OverpassHttpResponse, TileRequest
from .pipeline import run_enrichment
from .receipt import EnrichmentReceipt, write_receipt
from .transport import Httpx2OverpassTransport, create_overpass_client


@dataclass(frozen=True, slots=True)
class CliArguments:
    selection_manifest: Path
    enrichment_manifest: Path
    state_dir: Path
    output: Path
    fixture_overpass_response: Path | None


@final
class FixtureTransport:
    def __init__(self, body: bytes) -> None:
        self._body: bytes = body

    async def fetch(
        self,
        endpoint: str,
        request: TileRequest,
        timeout_seconds: float,
    ) -> OverpassHttpResponse:
        return OverpassHttpResponse(status_code=200, body=self._body)


def parse_args(argv: list[str] | None) -> CliArguments:
    parser = argparse.ArgumentParser(
        description="Enrich Todo 7 selected western routes without uploading"
    )
    parser.add_argument("selection_manifest", type=Path)
    parser.add_argument("enrichment_manifest", type=Path)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fixture-overpass-response", type=Path)
    parsed = parser.parse_args(argv)
    return CliArguments(
        selection_manifest=parsed.selection_manifest,
        enrichment_manifest=parsed.enrichment_manifest,
        state_dir=parsed.state_dir,
        output=parsed.output,
        fixture_overpass_response=parsed.fixture_overpass_response,
    )


async def execute(inputs: BridgeInputs, args: CliArguments) -> int:
    fixture_path = args.fixture_overpass_response
    if fixture_path is not None:
        runtime = EnrichmentRuntime(FixtureTransport(fixture_path.read_bytes()))
        result = await run_enrichment(inputs.manifest, args.state_dir, runtime)
    else:
        async with create_overpass_client() as client:
            runtime = EnrichmentRuntime(Httpx2OverpassTransport(client))
            result = await run_enrichment(inputs.manifest, args.state_dir, runtime)
    write_receipt(
        args.output,
        EnrichmentReceipt(
            selection_checksum=inputs.selection_checksum,
            enrichment_manifest_checksum=inputs.enrichment_manifest_checksum,
            result=result,
        ),
    )
    return result.exit_code


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        inputs = load_bridge(args.selection_manifest, args.enrichment_manifest)
        return anyio.run(execute, inputs, args)
    except (OSError, ValidationError, SelectionBridgeError) as error:
        print(f"western enrichment rejected: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
