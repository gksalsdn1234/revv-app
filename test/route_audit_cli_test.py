from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from tools.route_audit.export_western_baseline import (
    atomic_write,
    validate_output_paths,
)
from tools.route_audit.western_baseline import audit_fixture
from tools.route_audit.western_source import AuditContractError


class WesternAuditOutputSafetyTest(unittest.TestCase):
    def test_fixture_and_outputs_must_be_distinct(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = Path(temp_dir) / "fixture.json"
            _ = fixture.write_text("{}", encoding="utf-8")
            with self.assertRaises(AuditContractError):
                validate_output_paths(
                    fixture=fixture,
                    json_out=fixture,
                    summary_out=Path(temp_dir) / "summary.txt",
                )
            with self.assertRaises(AuditContractError):
                validate_output_paths(
                    fixture=fixture,
                    json_out=Path(temp_dir) / "same",
                    summary_out=Path(temp_dir) / "same",
                )

    def test_symlink_and_special_outputs_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "target"
            _ = target.write_bytes(b"old")
            link = Path(temp_dir) / "link"
            link.symlink_to(target)
            with self.assertRaises(AuditContractError):
                validate_output_paths(
                    fixture=None, json_out=link, summary_out=Path(temp_dir) / "ok"
                )

    def test_special_fixture_is_rejected_without_blocking(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            pipe = Path(temp_dir) / "fixture-pipe"
            os.mkfifo(pipe)
            with self.assertRaises(AuditContractError):
                _ = audit_fixture(pipe)
            pipe = Path(temp_dir) / "pipe"
            os.mkfifo(pipe)
            with self.assertRaises(AuditContractError):
                validate_output_paths(
                    fixture=None,
                    json_out=pipe,
                    summary_out=Path(temp_dir) / "other",
                )

    def test_symlinked_output_parent_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "target"
            target.mkdir()
            linked_parent = Path(temp_dir) / "linked-parent"
            linked_parent.symlink_to(target, target_is_directory=True)
            output = linked_parent / "report.json"
            with self.assertRaises(AuditContractError):
                validate_output_paths(
                    fixture=None,
                    json_out=output,
                    summary_out=Path(temp_dir) / "summary.txt",
                )
            with self.assertRaises(AuditContractError):
                atomic_write(output, b"secret")
            self.assertFalse((target / "report.json").exists())

    def test_atomic_write_replaces_regular_file_without_temp_leak(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "report.json"
            _ = output.write_bytes(b"old")
            atomic_write(output, b"new")
            self.assertEqual(output.read_bytes(), b"new")
            self.assertEqual(list(Path(temp_dir).glob(".report.json.*")), [])


if __name__ == "__main__":
    _ = unittest.main()
