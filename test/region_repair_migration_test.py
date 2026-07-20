"""Adversarial replay tests for 20260716040000_repair_empty_quebec_regions.sql.

Replays the full plain-SQL migration stack, in filename order, against a
temporary local Supabase PostgreSQL 17.6 container and proves the Quebec
empty-region repair migration fails closed on every receipt violation,
rolls back atomically, is idempotent, and unblocks the later
20260716043420_western_route_publication_v2.sql legacy backfill.

The 230-row receipt embedded in the migration is bound to the read-only
preflight snapshot SHA-256
e586c43de9425a47c54f20d0b68fb8a3161aef264e5771b47b152046fd999217; the
binding is re-verified here from the checked-in preflight report before any
database work. No production project is contacted: the only database is a
throwaway local container that is force-removed on exit.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
import unittest
from pathlib import Path
from typing import cast, final, override

_REPO = Path(__file__).resolve().parents[1]
_MIGRATIONS = _REPO / "supabase" / "migrations"
_REPAIR_NAME = "20260716040000_repair_empty_quebec_regions.sql"
_PUBLICATION_NAME = "20260716043420_western_route_publication_v2.sql"
_REPORT = (
    _REPO / "tools" / "route_audit" / "output" / "region_repair_preflight_20260717.json"
)
_PINNED_SNAPSHOT = "e586c43de9425a47c54f20d0b68fb8a3161aef264e5771b47b152046fd999217"
_IMAGE = "public.ecr.aws/supabase/postgres:17.6.1.106"
_CONTAINER = f"revv-qcrepair-{os.getpid()}"
_PSQL_BASE = ("psql", "-U", "supabase_admin", "-h", "localhost")
_READY_TIMEOUT_S = 180.0
_REPAIRED_VALUE = "quebec"

_STACK_STUBS = """
-- Test-harness stubs for service-owned objects that a full Supabase stack
-- (GoTrue / Realtime) provides but the bare postgres image does not.
create or replace function auth.jwt() returns jsonb
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;
create table if not exists realtime.messages (
  id uuid not null default gen_random_uuid(),
  topic text not null,
  extension text not null,
  payload jsonb,
  event text,
  private boolean default false,
  inserted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (id, inserted_at)
);
alter table realtime.messages enable row level security;
create or replace function realtime.topic() returns text
language sql stable
as $$
  select nullif(current_setting('realtime.topic', true), '')::text
$$;
"""


def _load_receipt_ids() -> tuple[str, ...]:
    report = cast("dict[str, object]", json.loads(_REPORT.read_bytes()))
    updates = cast("list[dict[str, object]]", report["proposed_updates"])
    targets: list[dict[str, object]] = []
    for update in updates:
        row_id = update["id"]
        if not isinstance(row_id, str):
            raise AssertionError("non-string id in preflight report")
        targets.append(
            {
                "id": row_id,
                "region": update["expected_region"],
                "center_lat": update["center_lat"],
                "center_lng": update["center_lng"],
            }
        )
    targets.sort(key=lambda target: str(target["id"]))
    target_bytes = json.dumps(
        targets,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    recomputed = hashlib.sha256(target_bytes).hexdigest()
    if recomputed != _PINNED_SNAPSHOT:
        raise AssertionError(
            f"preflight snapshot drifted: {recomputed} != {_PINNED_SNAPSHOT}"
        )
    return tuple(str(target["id"]) for target in targets)


def _seed_sql(row_specs: tuple[tuple[str, str | None], ...]) -> str:
    values: list[str] = []
    for ordinal, (row_id, region) in enumerate(row_specs):
        latitude = 46.0 + ordinal / 1000.0
        longitude = -73.0 - ordinal / 1000.0
        region_literal = "null" if region is None else "'" + region + "'"
        nodes = (
            f'[{{"lat":{latitude},"lng":{longitude}}},'
            + f'{{"lat":{latitude + 0.01},"lng":{longitude - 0.01}}}]'
        )
        point = f"st_makepoint({longitude}, {latitude})"
        values.append(
            f"('{row_id}', 'Seed {ordinal}', {latitude}, {longitude},"
            + f" st_setsrid({point}, 4326)::geography,"
            + f" '{nodes}'::jsonb, 6.0, 40.0, {region_literal})"
        )
    joined = ",\n".join(values)
    return (
        "insert into public.curvy_roads (\n"
        "  id, name, center_lat, center_lng, center_point, nodes,\n"
        "  distance_km, winding_score, region\n"
        f") values\n{joined};\n"
    )


@final
class RegionRepairMigrationTest(unittest.TestCase):
    receipt_ids: tuple[str, ...] = ()
    _database_serial: int = 0

    @classmethod
    @override
    def setUpClass(cls) -> None:
        cls.receipt_ids = _load_receipt_ids()
        _ = subprocess.run(
            ("docker", "rm", "-f", _CONTAINER),
            capture_output=True,
            check=False,
        )
        cls.addClassCleanup(cls._remove_container)
        run = subprocess.run(
            (
                "docker",
                "run",
                "-d",
                "--name",
                _CONTAINER,
                "-e",
                "POSTGRES_PASSWORD=revv-qcrepair-test",
                _IMAGE,
            ),
            capture_output=True,
            text=True,
            check=False,
        )
        if run.returncode != 0:
            raise unittest.SkipTest(f"docker unavailable: {run.stderr.strip()}")
        cls._wait_ready()
        cls._psql_ok("postgres", _STACK_STUBS)
        cls._clone_database("postgres", "pristine")
        copy = subprocess.run(
            ("docker", "cp", str(_MIGRATIONS) + "/.", f"{_CONTAINER}:/tmp/migrations"),
            capture_output=True,
            text=True,
            check=False,
        )
        if copy.returncode != 0:
            raise AssertionError(f"docker cp failed: {copy.stderr}")
        for name in cls._migration_names():
            if name >= _REPAIR_NAME:
                continue
            cls._apply_file_ok("postgres", name)

    @classmethod
    def _remove_container(cls) -> None:
        _ = subprocess.run(
            ("docker", "rm", "-f", _CONTAINER),
            capture_output=True,
            check=False,
        )

    @classmethod
    def _clone_database(cls, source: str, name: str) -> None:
        # The supabase image keeps pg_net / pg_cron background workers
        # connected to the postgres database; CREATE DATABASE needs the
        # source connection-free, so evict them and retry briefly.
        terminate = (
            "select pg_terminate_backend(pid) from pg_stat_activity"
            + f" where datname = '{source}' and pid <> pg_backend_pid()"
        )
        failure = ""
        for _ in range(20):
            _ = cls._exec((*_PSQL_BASE, "-d", "template1", "-Atc", terminate))
            result = cls._exec(
                (
                    "createdb",
                    "-U",
                    "supabase_admin",
                    "-h",
                    "localhost",
                    f"--template={source}",
                    name,
                )
            )
            if result.returncode == 0:
                return
            failure = result.stderr
            time.sleep(0.5)
        raise AssertionError(f"could not clone database {source}: {failure}")

    @classmethod
    def _wait_ready(cls) -> None:
        deadline = time.monotonic() + _READY_TIMEOUT_S
        while time.monotonic() < deadline:
            probe = subprocess.run(
                (
                    "docker",
                    "exec",
                    _CONTAINER,
                    *_PSQL_BASE,
                    "-d",
                    "postgres",
                    "-Atc",
                    "select 1",
                ),
                capture_output=True,
                text=True,
                check=False,
            )
            if probe.returncode == 0 and probe.stdout.strip() == "1":
                return
            time.sleep(2.0)
        raise AssertionError("temporary postgres container never became ready")

    @classmethod
    def _migration_names(cls) -> tuple[str, ...]:
        return tuple(sorted(path.name for path in _MIGRATIONS.glob("*.sql")))

    @classmethod
    def _exec(cls, command: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ("docker", "exec", _CONTAINER, *command),
            capture_output=True,
            text=True,
            check=False,
        )

    @classmethod
    def _psql(cls, database: str, sql: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            (
                "docker",
                "exec",
                "-i",
                _CONTAINER,
                *_PSQL_BASE,
                "-v",
                "ON_ERROR_STOP=1",
                "--single-transaction",
                "-d",
                database,
                "-f",
                "-",
            ),
            input=sql,
            capture_output=True,
            text=True,
            check=False,
        )

    @classmethod
    def _psql_ok(cls, database: str, sql: str) -> None:
        result = cls._psql(database, sql)
        if result.returncode != 0:
            raise AssertionError(f"seed/setup sql failed: {result.stderr}")

    @classmethod
    def _apply_file(
        cls, database: str, migration_name: str
    ) -> subprocess.CompletedProcess[str]:
        return cls._exec(
            (
                *_PSQL_BASE,
                "-v",
                "ON_ERROR_STOP=1",
                "--single-transaction",
                "-d",
                database,
                "-f",
                f"/tmp/migrations/{migration_name}",
            )
        )

    @classmethod
    def _apply_file_ok(cls, database: str, migration_name: str) -> None:
        result = cls._apply_file(database, migration_name)
        if result.returncode != 0:
            raise AssertionError(f"{migration_name} failed: {result.stderr}")

    def _scalar(self, database: str, query: str) -> str:
        result = self._exec((*_PSQL_BASE, "-d", database, "-Atc", query))
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def _fresh_database(self, template: str = "postgres") -> str:
        type(self)._database_serial += 1
        name = f"scenario_{type(self)._database_serial}"
        self._clone_database(template, name)
        return name

    def _seed(self, database: str, rows: tuple[tuple[str, str | None], ...]) -> None:
        self._psql_ok(database, _seed_sql(rows))

    def _control_rows(self) -> tuple[tuple[str, str | None], ...]:
        return (
            ("control-alberta-row", "Alberta"),
            ("control-messy-quebec-row", " Quebec "),
            ("control-lower-quebec-row", "quebec"),
        )

    def _empty_region_count(self, database: str) -> int:
        return int(
            self._scalar(
                database,
                "select count(*) from public.curvy_roads where coalesce(region, '') = ''",
            )
        )

    def _repaired_count(self, database: str) -> int:
        return int(
            self._scalar(
                database,
                f"select count(*) from public.curvy_roads where region = '{_REPAIRED_VALUE}'",
            )
        )

    def test_receipt_embeds_exactly_the_snapshot_ids(self) -> None:
        # Given: the checked-in migration text and the verified 230-row
        # preflight snapshot.
        migration_text = (_MIGRATIONS / _REPAIR_NAME).read_text(encoding="ascii")
        embedded = tuple(
            str(match.group(1))
            for match in re.finditer(r"'([0-9a-f]{64})'", migration_text)
        )

        # Then: the receipt is exactly the sorted snapshot ids, once each,
        # and the pinned snapshot checksum is bound in the header.
        self.assertEqual(embedded, self.receipt_ids)
        self.assertEqual(len(embedded), 230)
        self.assertIn(_PINNED_SNAPSHOT, migration_text)
        lowered = migration_text.lower()
        self.assertIsNone(re.search(r"\bdelete\b", lowered))
        self.assertIsNone(re.search(r"\btruncate\b", lowered))
        self.assertIsNone(re.search(r"\bdrop\b", lowered))

    def test_a_missing_receipt_row_fails_closed(self) -> None:
        # Given: 229 of the 230 receipt rows (one absent).
        database = self._fresh_database()
        seeded = tuple((row_id, "") for row_id in self.receipt_ids[1:])
        self._seed(database, seeded + self._control_rows())

        # When: the repair migration runs.
        result = self._apply_file(database, _REPAIR_NAME)

        # Then: it aborts naming the missing receipt row and modifies nothing.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("receipt row missing", result.stderr)
        self.assertIn(self.receipt_ids[0], result.stderr)
        self.assertEqual(self._empty_region_count(database), 229)
        self.assertEqual(self._repaired_count(database), 1)

    def test_b_receipt_row_with_different_region_fails_closed(self) -> None:
        # Given: all 230 receipt rows, one already holding a different value.
        database = self._fresh_database()
        seeded = tuple(
            (row_id, "ontario" if row_id == self.receipt_ids[3] else "")
            for row_id in self.receipt_ids
        )
        self._seed(database, seeded + self._control_rows())

        # When: the repair migration runs.
        result = self._apply_file(database, _REPAIR_NAME)

        # Then: it refuses to overwrite and modifies nothing.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected region", result.stderr)
        self.assertIn("ontario", result.stderr)
        self.assertEqual(self._empty_region_count(database), 229)
        self.assertEqual(self._repaired_count(database), 1)

    def test_c_extra_empty_region_row_fails_closed(self) -> None:
        # Given: all 230 receipt rows plus one empty-region row outside the
        # receipt.
        database = self._fresh_database()
        seeded = tuple((row_id, "") for row_id in self.receipt_ids)
        extra = (("extra-unexpected-empty-row", ""),)
        self._seed(database, seeded + extra + self._control_rows())

        # When: the repair migration runs.
        result = self._apply_file(database, _REPAIR_NAME)

        # Then: it aborts on snapshot drift and modifies nothing.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the repair receipt", result.stderr)
        self.assertIn("extra-unexpected-empty-row", result.stderr)
        self.assertEqual(self._empty_region_count(database), 231)
        self.assertEqual(self._repaired_count(database), 1)

    def test_c2_null_region_row_fails_closed(self) -> None:
        # Given: all 230 receipt rows plus a null-region row, which the
        # snapshot says cannot exist (preflight observed zero nulls).
        database = self._fresh_database()
        seeded = tuple((row_id, "") for row_id in self.receipt_ids)
        null_row: tuple[tuple[str, str | None], ...] = (
            ("extra-null-region-row", None),
        )
        self._seed(database, seeded + null_row + self._control_rows())

        # When: the repair migration runs.
        result = self._apply_file(database, _REPAIR_NAME)

        # Then: it aborts and modifies nothing.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the repair receipt", result.stderr)
        self.assertEqual(self._repaired_count(database), 1)

    def test_d_failed_run_rolls_back_with_zero_rows_modified(self) -> None:
        # Given: the LAST sorted receipt row poisoned with a different value,
        # so a non-atomic or unchecked implementation would already have
        # updated earlier rows before noticing.
        database = self._fresh_database()
        poisoned = self.receipt_ids[-1]
        seeded = tuple(
            (row_id, "british_columbia" if row_id == poisoned else "")
            for row_id in self.receipt_ids
        )
        self._seed(database, seeded)

        # When: the repair migration fails.
        result = self._apply_file(database, _REPAIR_NAME)

        # Then: zero receipt rows became 'quebec' and all 229 empty rows are
        # still empty -- the failure left the table byte-for-byte unmodified.
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self._repaired_count(database), 0)
        self.assertEqual(self._empty_region_count(database), 229)
        self.assertEqual(
            self._scalar(
                database,
                f"select region from public.curvy_roads where id = '{poisoned}'",
            ),
            "british_columbia",
        )

    def test_e_rerun_after_success_is_a_clean_noop(self) -> None:
        # Given: a successful repair of all 230 receipt rows.
        database = self._fresh_database()
        seeded = tuple((row_id, "") for row_id in self.receipt_ids)
        self._seed(database, seeded + self._control_rows())
        first = self._apply_file(database, _REPAIR_NAME)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(self._repaired_count(database), 231)

        # When: the migration is applied again.
        second = self._apply_file(database, _REPAIR_NAME)

        # Then: the re-run is a clean no-op, not an error, and state is
        # unchanged.
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("idempotent no-op", second.stderr)
        self.assertEqual(self._repaired_count(database), 231)
        self.assertEqual(self._empty_region_count(database), 0)

    def test_f_happy_path_repairs_and_unblocks_publication(self) -> None:
        # Given: the production-shaped table -- 230 empty receipt rows plus
        # classifiable control rows.
        database = self._fresh_database()
        seeded = tuple((row_id, "") for row_id in self.receipt_ids)
        self._seed(database, seeded + self._control_rows())

        # When: the repair migration runs, then the western publication
        # migration runs.
        repair = self._apply_file(database, _REPAIR_NAME)
        self.assertEqual(repair.returncode, 0, repair.stderr)
        self.assertIn("updated 230 rows", repair.stderr)
        publication = self._apply_file(database, _PUBLICATION_NAME)

        # Then: all 230 receipt rows are 'quebec', control rows kept their
        # own regions, and the publication backfill completed with the
        # receipt rows classified as QC.
        self.assertEqual(publication.returncode, 0, publication.stderr)
        self.assertEqual(self._empty_region_count(database), 0)
        self.assertEqual(
            self._scalar(
                database,
                "select region from public.curvy_roads where id = 'control-alberta-row'",
            ),
            "Alberta",
        )
        self.assertEqual(
            self._scalar(
                database,
                "select '[' || region || ']' from public.curvy_roads"
                + " where id = 'control-messy-quebec-row'",
            ),
            "[ Quebec ]",
        )
        self.assertEqual(
            int(
                self._scalar(
                    database,
                    "select count(*) from public.curvy_roads where province_code = 'QC'"
                    + f" and region = '{_REPAIRED_VALUE}' and id ~ '^[0-9a-f]{{64}}$'",
                )
            ),
            230,
        )
        self.assertEqual(
            self._scalar(
                database,
                "select province_code from public.curvy_roads where id = 'control-alberta-row'",
            ),
            "AB",
        )

    def test_g_full_stack_replays_in_order_on_a_fresh_database(self) -> None:
        # Given: a pristine database with none of the app migrations applied.
        database = self._fresh_database(template="pristine")
        names = self._migration_names()
        self.assertIn(_REPAIR_NAME, names)
        self.assertEqual(len(names), 34)
        self.assertLess(names.index(_REPAIR_NAME), names.index(_PUBLICATION_NAME))

        # When: every migration is applied in filename order.
        applied = 0
        for name in names:
            result = self._apply_file(database, name)
            self.assertEqual(result.returncode, 0, f"{name}: {result.stderr}")
            applied += 1

        # Then: the whole 34-file stack replays cleanly, with the repair a
        # fresh-database no-op that leaves the publication backfill green.
        self.assertEqual(applied, 34)
        self.assertEqual(
            self._scalar(
                database,
                "select count(*) from public.curvy_roads",
            ),
            "0",
        )


if __name__ == "__main__":
    _ = unittest.main()
