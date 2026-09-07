"""Build a rollback-only SQL fixture from the actual migration definitions."""
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
migration = root / 'supabase/migrations/20260907131716_route_catalog_ordinal_lookup.sql'
sql = migration.read_text()
functions = '\n'.join(re.findall(r'CREATE OR REPLACE FUNCTION.*?\$function\$;', sql, re.S))
assert functions.count('CREATE OR REPLACE FUNCTION') == 2
for name in ['get_route_nodes_v2', 'get_route_overview_v2', 'curvy_roads',
             'route_catalog_state', 'route_generation_batches']:
    functions = functions.replace('public.' + name, 'pg_temp.' + name)
fixture = (root / 'supabase/tests/route_catalog_ordinal_lookup.sql').read_text()
assert fixture.count('-- CANDIDATE_FUNCTIONS') == 1
args.output.write_text(fixture.replace('-- CANDIDATE_FUNCTIONS', functions))
print(args.output)
