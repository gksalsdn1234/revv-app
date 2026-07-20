# Western source acquisition: current-behavior characterization

Recorded before Todo 2 implementation on 2026-07-16.

The existing curvature pipeline has one network acquisition path,
`download_kmz.py`. It limits individual KMZ downloads to 512 MiB and accepts
only HTTPS URLs on `kml.roadcurvature.com`. It does not provide any of the
following OSM-specific behavior:

- checksum-pinned provincial PBF snapshots;
- a fixed western province and hub manifest;
- a content-addressed verified cache;
- request, elapsed-time, or extraction-process budgets;
- interruption checkpoints;
- bounded per-hub `osmium extract` output;
- source, container, package, or license receipts.

Therefore the red-first tests for this task intentionally import modules that
do not exist at this characterization point. They define the new boundary
without changing the existing KMZ path.
