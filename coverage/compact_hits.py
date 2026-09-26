#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Compact coverage probe records into a stream the report can hold in RAM.

A meshed bone writes tens of millions of repeated records. Line and branch
coverage only need each id once. MC-DC only needs each distinct evaluation
vector once. This program streams every hits file and writes that compact
form to stdout.

    python3 coverage/compact_hits.py coverage/build/hits > coverage/build/hits.txt
"""

from __future__ import annotations

import sys
from pathlib import Path

LINE_PREFIX = "COVLINE:"
BRANCH_PREFIX = "COVBRANCH:"
MASKED = -1
FALSE = 0
TRUE = 1


def split_last(text: str, separator: str) -> list[str]:
    index = text.rfind(separator)
    if index < 0:
        return [text]
    return [text[:index], text[index + len(separator) :]]


def eval_key(values: list[int], outcome: bool) -> tuple:
    return (tuple(values), outcome)


def emit_eval(base: str, values: list[int], outcome: bool, out: list[str]) -> None:
    for position, state in enumerate(values):
        if state == MASKED:
            continue
        flag = "T" if state == TRUE else "F"
        out.append(f"{BRANCH_PREFIX}{base}.{position}:{flag}")
    flag = "T" if outcome else "F"
    out.append(f"{BRANCH_PREFIX}{base}:{flag}")


def compact_file(path: Path, unique: set[str], traces: dict[str, set]) -> None:
    pending_ids: list[str] = []
    pending_values: list[list[int]] = []

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(LINE_PREFIX):
                unique.add(line)
                continue
            if not line.startswith(BRANCH_PREFIX):
                continue
            unique.add(line)

            payload = line[len(BRANCH_PREFIX) :]
            halves = split_last(payload, ":")
            if len(halves) != 2:
                raise SystemExit(f"Malformed branch record: {line}")
            state = TRUE if halves[1] == "T" else FALSE
            parts = split_last(halves[0], ".")
            base = parts[0]

            slot = -1
            for index, pending in enumerate(pending_ids):
                if pending == base:
                    slot = index
                    break
            if slot < 0:
                pending_ids.append(base)
                pending_values.append([])
                slot = len(pending_ids) - 1

            if len(parts) == 2:
                position = int(parts[1])
                while len(pending_values[slot]) <= position:
                    pending_values[slot].append(MASKED)
                pending_values[slot][position] = state
                continue

            traces.setdefault(base, set()).add(
                eval_key(pending_values[slot], state == TRUE)
            )
            pending_values[slot] = []


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: compact_hits.py <hits-dir>")
    hits_dir = Path(sys.argv[1])
    files = sorted(hits_dir.glob("*.txt"))
    if not files:
        raise SystemExit(f"no hit files in {hits_dir}")

    unique: set[str] = set()
    traces: dict[str, set] = {}
    for path in files:
        compact_file(path, unique, traces)

    lines = sorted(line for line in unique if line.startswith(LINE_PREFIX))
    for line in lines:
        print(line)

    compact_branches: list[str] = []
    for base in sorted(traces):
        for values, outcome in sorted(traces[base]):
            emit_eval(base, list(values), outcome, compact_branches)
    for line in compact_branches:
        print(line)


if __name__ == "__main__":
    main()
