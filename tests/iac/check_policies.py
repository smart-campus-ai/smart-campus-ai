#!/usr/bin/env python3
"""Self-test of the custom Checkov policies (policies/CKV_SC_*) against the fixtures of policies/tests/.

Convention: in policies/tests/ckv_sc_<n>/, every block named pass_* must PASS check CKV_SC_<n> and every block named
fail_* must FAIL it. A block that produces neither result (the check returned UNKNOWN or did not run) is an error, so
a check that silently stops matching cannot go unnoticed.

Each fixture directory is scanned on its own (`-d policies/tests/<check>`): checkov then builds one graph per check and
reports every evaluated resource and data source by address in passed_checks / failed_checks.

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
BLOCK = re.compile(r'^(resource|data)\s+"([^"]+)"\s+"((?:pass|fail)_[A-Za-z0-9_]+)"', re.MULTILINE)


def run_checkov(directory: Path, check_id: str) -> dict[str, set[str]]:
    """Return {resource address: {"pass", "fail"}} for one fixture directory and one check."""
    command = [
        "checkov",
        "-d", str(directory),
        "--external-checks-dir", str(ROOT / "policies"),
        "--framework", "terraform",
        "--check", check_id,
        "--skip-download",
        "--download-external-modules", "false",
        "--compact",
        "--quiet",
        "--output", "json",
    ]
    # Exit code 1 is expected: the fail_* fixtures are meant to fail. Only unreadable output is an error.
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    try:
        report = json.loads(completed.stdout)
    except ValueError:
        sys.exit(f"{check_id}: checkov did not return JSON (exit {completed.returncode}):\n{completed.stderr[-2000:]}")
    observed: dict[str, set[str]] = {}
    for item in report if isinstance(report, list) else [report]:
        results = item.get("results", {})
        for key, verdict in (("passed_checks", "pass"), ("failed_checks", "fail")):
            for record in results.get(key, []):
                if record.get("check_id") == check_id:
                    observed.setdefault(str(record["resource"]), set()).add(verdict)
    return observed


def main() -> int:
    directories = sorted(p for p in FIXTURES.iterdir() if p.is_dir() and p.name.startswith("ckv_sc_"))
    if not directories:
        sys.exit(f"no fixture directory found in {FIXTURES}")

    errors: list[str] = []
    for directory in directories:
        check_id = directory.name.upper()
        # Only the top-level files hold fixtures: sub-directories are local modules referenced by them.
        expected = {
            # Checkov addresses: "<type>.<name>" for a resource, "data.<type>.<name>" for a data source.
            (f"data.{block_type}.{name}" if keyword == "data" else f"{block_type}.{name}"): (
                "pass" if name.startswith("pass_") else "fail"
            )
            for tf_file in directory.glob("*.tf")
            for keyword, block_type, name in BLOCK.findall(tf_file.read_text(encoding="utf-8"))
        }
        if "pass" not in expected.values() or "fail" not in expected.values():
            errors.append(f"{check_id}: needs at least one pass_* and one fail_* fixture")
        observed = run_checkov(directory, check_id)
        for address, wanted in sorted(expected.items()):
            got = observed.get(address, set())
            if got != {wanted}:
                errors.append(f"{check_id}: {address} expected {wanted.upper()}, got {sorted(got) or 'no result'}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"OK: {len(directories)} custom checks verified against their fixtures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
