from __future__ import annotations

from ..western_sources.checkpoint import AcquisitionCheckpoint
from ..western_sources.manifest import (
    WesternManifest,
    canonical_hub_spec_digest,
    canonical_manifest_digest,
)
from .builder import GraphBuildError, HubGraphSpec


def spec_from_acquisition(
    manifest: WesternManifest,
    checkpoint: AcquisitionCheckpoint,
    hub_id: str,
) -> HubGraphSpec:
    if checkpoint.generator_version != manifest.generator_version:
        raise GraphBuildError("checkpoint generator does not match the manifest")
    if checkpoint.snapshot != manifest.snapshot.isoformat():
        raise GraphBuildError("checkpoint snapshot does not match the manifest")
    if checkpoint.manifest_digest != canonical_manifest_digest(manifest):
        raise GraphBuildError("checkpoint digest does not match the manifest")

    hub = next((item for item in manifest.hubs if item.hub_id == hub_id), None)
    if hub is None:
        raise GraphBuildError("hub is absent from the source manifest")
    source = next(
        (item for item in manifest.sources if item.province_code == hub.province_code),
        None,
    )
    if source is None:
        raise GraphBuildError("hub province has no source PBF")
    completed_source = next(
        (
            item
            for item in checkpoint.completed_sources
            if item.province_code == hub.province_code
        ),
        None,
    )
    completed_hub = next(
        (item for item in checkpoint.completed_hubs if item.hub_id == hub_id),
        None,
    )
    if completed_source is None or completed_source.source_checksum != source.checksum:
        raise GraphBuildError("provincial source checksum is not completed")
    if completed_hub is None:
        raise GraphBuildError("bounded hub PBF is not completed")
    if completed_hub.hub_spec_digest != canonical_hub_spec_digest(hub):
        raise GraphBuildError("bounded hub specification is stale")
    if completed_hub.source_checksum != source.checksum:
        raise GraphBuildError("bounded hub PBF belongs to another provincial source")
    return HubGraphSpec(
        hub_id=hub.hub_id,
        province_code=hub.province_code,
        source_pbf_checksum=source.checksum,
        hub_pbf_checksum=completed_hub.output_checksum,
    )
