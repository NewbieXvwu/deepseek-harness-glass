#!/usr/bin/env python3
"""Reject unreviewed official transport-contract drift with a readable field diff."""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE = ROOT / "glass" / "Sources" / "Spec" / "Fixtures" / "official-transport-contract-manifest.json"
GENERATOR = ROOT / "tools" / "spec-generation" / "generate_official_transport_contract_manifest.py"
COMMIT = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"
FIELDS = ("kind", "symbols", "requestFields", "valueFields", "enums", "sourceSHA256", "contractSignatureSHA256")


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"could not load contract manifest {path}: {error}") from error
    if data.get("schemaVersion") != 1:
        raise SystemExit(f"unsupported transport contract manifest schema: {data.get('schemaVersion')}")
    if data.get("officialSourceCommit") != COMMIT:
        raise SystemExit(f"transport contract source commit mismatch: {data.get('officialSourceCommit')!r}")
    if data.get("contractRevision") != "official-b150a55-transport-contract-r1":
        raise SystemExit(f"transport contract revision mismatch: {data.get('contractRevision')!r}")
    contracts = data.get("contracts")
    if not isinstance(contracts, list):
        raise SystemExit("transport contract manifest has no contracts array")
    return data


def index(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for item in data["contracts"]:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise SystemExit("transport contract entry lacks string id")
        if item["id"] in result:
            raise SystemExit(f"duplicate transport contract id: {item['id']}")
        result[item["id"]] = item
    return result


def format_list(values: Any) -> str:
    return ", ".join(values) if isinstance(values, list) else repr(values)


def diff(baseline: dict[str, Any], candidate: dict[str, Any]) -> list[str]:
    old = index(baseline)
    new = index(candidate)
    report: list[str] = []
    for contract_id in sorted(new.keys() - old.keys()):
        report.append(f"ADDED contract {contract_id}")
    for contract_id in sorted(old.keys() - new.keys()):
        report.append(f"REMOVED contract {contract_id}")
    for contract_id in sorted(old.keys() & new.keys()):
        before, after = old[contract_id], new[contract_id]
        for field in FIELDS:
            if before.get(field) != after.get(field):
                if field in {"requestFields", "valueFields", "enums", "symbols"}:
                    old_values = set(before.get(field, []))
                    new_values = set(after.get(field, []))
                    for value in sorted(new_values - old_values):
                        report.append(f"MODIFIED {contract_id} {field}: ADDED {value}")
                    for value in sorted(old_values - new_values):
                        report.append(f"MODIFIED {contract_id} {field}: REMOVED {value}")
                    if not (new_values - old_values or old_values - new_values):
                        report.append(f"MODIFIED {contract_id} {field}: {format_list(before.get(field))} -> {format_list(after.get(field))}")
                else:
                    report.append(f"MODIFIED {contract_id} {field}: {before.get(field)!r} -> {after.get(field)!r}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-root", required=True, type=pathlib.Path)
    parser.add_argument("--baseline", type=pathlib.Path, default=BASELINE)
    parser.add_argument("--candidate-manifest", type=pathlib.Path)
    args = parser.parse_args()
    baseline = load(args.baseline)
    if args.candidate_manifest:
        candidate = load(args.candidate_manifest)
    else:
        with tempfile.TemporaryDirectory(prefix="dsh-glass-contract-") as temporary:
            generated = pathlib.Path(temporary) / "candidate.json"
            subprocess.run([sys.executable, str(GENERATOR), "--official-root", str(args.official_root), "--output", str(generated)], check=True)
            candidate = load(generated)
    changes = diff(baseline, candidate)
    if changes:
        print("T4.6 official transport contract drift requires review:", file=sys.stderr)
        print("\n".join(changes), file=sys.stderr)
        raise SystemExit(1)
    print(f"official transport contract OK: {len(baseline['contracts'])} contracts at {COMMIT[:12]}")


if __name__ == "__main__":
    main()
