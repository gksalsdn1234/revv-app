# Western OSM source and attribution policy

Receipt date: 2026-07-16. Generator: `western-source-v1`.

## Accepted production source

New western generated routes use only checksum-pinned OpenStreetMap extracts
served by Geofabrik. Geofabrik identifies the extract as data processed by
Geofabrik, created by OpenStreetMap contributors, and licensed under ODbL 1.0:

- https://download.geofabrik.de/north-america/canada.html
- https://www.openstreetmap.org/copyright
- https://opendatacommons.org/licenses/odbl/1-0/

REVV must display `© OpenStreetMap contributors` and a link that makes the
ODbL license clear on the existing legal/catalog surface before any generated
route is imported into production. A distributed OSM-derived database must
retain the ODbL terms and attribution. Provincial PBFs, bounded extracts, and
cache files are build inputs only and are not bundled with the app or committed.

## RoadCurvature seed decision

RoadCurvature states that its road input comes from OpenStreetMap and publishes
free downloadable generated KML/KMZ files, but the reviewed official pages do
not state an explicit license for reusing those generated downloads:

- https://roadcurvature.com/how-it-works/
- https://roadcurvature.com/how-it-works/osm/
- https://kml.roadcurvature.com/

Therefore `western-source-v1` does not ingest or reuse RoadCurvature KML/KMZ
seeds. Existing legacy rows are outside this generator. Reuse remains prohibited
until the publisher provides an explicit compatible license.

## Overpass decision

Overpass returns selected OpenStreetMap data. Any later enrichment obtained
from Overpass carries the same OSM attribution and ODbL disclosure policy:

- https://wiki.openstreetmap.org/wiki/Overpass_API
- https://www.openstreetmap.org/copyright

Overpass is not a Todo 2 PBF source, is not queried by this acquisition stage,
and is subject to the separately bounded enrichment budget.

## Update policy

Source snapshots, package versions, container images, and osmium-tool are never
auto-updated during a batch. Updates are manual quarterly work, require a new
generator version, refresh every checksum/receipt, and require a complete dry
run before use.
