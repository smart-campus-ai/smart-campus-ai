#!/usr/bin/env python3
"""Self-test of the custom Checkov policies (policies/CKV_SC_*) against the fixtures of policies/tests/.

Convention: in policies/tests/ckv_sc_<n>/, every block named pass_* must PASS check CKV_SC_<n> and every block named
fail_* must FAIL it. A block that produces neither result (the check returned UNKNOWN or did not run) is an error, so
a check that silently stops matching cannot go unnoticed.

Usage (from anywhere, checkov on the PATH, e.g. through `mise exec --`):
    python3 tests/iac/check_policies.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "policies" / "tests"
BLOCK = re.compile(r'^(?:resource|data)\s+"[^"]+"\s+"((?:pass|fail)_[A-Za-z0-9_]+)"', re.MULTILINE)


def run_checkov(check_ids: list[str]) -> list[dict]:
    command = [
        "checkov",
        "-d", str(FIXTURES),
        "--external-checks-dir", str(ROOT / "policies"),
        "--framework", "terraform",
        "--check", ",".join(check_ids),
        "--skip-download",
        "--download-external-modules", "false",
        "--output", "json",
    ]
    # Exit code 1 is expected: the fail_* fixtures are meant to fail. Only unreadable output is an error.
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    try:
        report = json.loads(completed.stdout)
    except ValueError:
        sys.exit(f"checkov did not return JSON (exit {completed.returncode}):\n{completed.stderr[-2000:]}")
    reports = report if isinstance(report, list) else [report]
    records: list[dict] = []
    for item in reports:
        results = item.get("results", {})
        for key in ("passed_checks", "failed_checks"):
            for record in results.get(key, []):
                records.append({**record, "verdict": "pass" if key == "passed_checks" else "fail"})
    return records


def main() -> int:
    directories = sorted(p for p in FIXTURES.iterdir() if p.is_dir() and p.name.startswith("ckv_sc_"))
    if not directories:
        sys.exit(f"no fixture directory found in {FIXTURES}")

    check_ids = [d.name.upper() for d in directories]
    records = run_checkov(check_ids)
    errors: list[str] = []

    for directory in directories:
        check_id = directory.name.upper()
        expected = {
            name: ("pass" if name.startswith("pass_") else "fail")
            for tf_file in directory.glob("*.tf")
            for name in BLOCK.findall(tf_file.read_text(encoding="utf-8"))
        }
        if "pass" not in expected.values() or "fail" not in expected.values():
            errors.append(f"{check_id}: needs at least one pass_* and one fail_* fixture")
        observed: dict[str, set[str]] = {}
        for record in records:
            file_path = str(record.get("file_path", "")).replace("\\", "/")
            if record["check_id"] == check_id and f"/{directory.name}/" in file_path:
                name = str(record["resource"]).rsplit(".", 1)[-1]
                observed.setdefault(name, set()).add(record["verdict"])
        for name, wanted in sorted(expected.items()):
            got = observed.get(name, set())
            if got != {wanted}:
                errors.append(f"{check_id}: {name} expected {wanted.upper()}, got {sorted(got) or 'no result'}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"OK: {len(directories)} custom checks verified against their fixtures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
