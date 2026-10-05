#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Validate and summarize the complete owned-snapshot benchmark CSV files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import median

INTEGER_FIELDS = (
    "static", "moving", "distribution", "repetition", "ns", "peak_bytes",
    "total_bytes", "allocations", "live_bytes", "work", "pairs",
    "geometry_bytes", "index_bytes", "metadata_bytes",
)
LAYOUTS = ("grid", "overlapping_x", "clusters", "coincident")


def load(path: Path, repeats: int) -> dict:
    """Read rows, reject incomplete or inconsistent measurements, and group."""
    grouped = defaultdict(list)
    with path.open(newline="") as stream:
        for raw in csv.DictReader(stream):
            row = dict(raw)
            for key in INTEGER_FIELDS:
                row[key] = int(row[key])
            row["checksum"] = float(row["checksum"])
            key = tuple(row[k] for k in ("group", "static", "moving", "distribution", "phase"))
            grouped[key].append(row)
    required = {}
    for n in (100, 1000, 10000):
        for moving in (1, 10, 100):
            for layout in range(4):
                prefix = ("corpus", n, moving, layout)
                for phase in ("sweep_query", "dynamic_prepare", "dynamic_query", "snapshot_build", "forced_index_build"):
                    required[(*prefix, phase)] = repeats
                if moving == 10:
                    for phase in ("ray_linear_1024", "ray_frozen_linear_1024", "ray_snapshot_1024", "ray_forced_index_1024"):
                        required[(*prefix, phase)] = repeats
                    required[(*prefix, "frozen_after_release_1024")] = 1
    for n in (0, 1, 4, 8, 16, 32, 64):
        for layout in range(4):
            for phase in ("snapshot_build", "forced_index_build", "ray_linear_1024", "ray_frozen_linear_1024", "ray_snapshot_1024", "ray_forced_index_1024"):
                required[("small", n, 0, layout, phase)] = repeats
    for n in (100, 1000, 10000):
        for percent in (0, 25, 50, 100):
            for phase in ("index_refit", "index_rebuild", "refit_ray_1024", "rebuilt_ray_1024"):
                required[("refit", n, percent, 0, phase)] = repeats
    if grouped.keys() != required.keys():
        raise ValueError(f"Case set differs: missing {required.keys() - grouped.keys()}, extra {grouped.keys() - required.keys()}")
    for key, count in required.items():
        rows = grouped[key]
        expected_reps = [repeats - 1] if key[-1] == "frozen_after_release_1024" else list(range(count))
        if sorted(r["repetition"] for r in rows) != expected_reps:
            raise ValueError(f"Wrong sample set for {key}")
        for row in rows:
            if row["ns"] < 0 or not 0 <= row["live_bytes"] <= row["peak_bytes"] <= row["total_bytes"]:
                raise ValueError(f"Invalid timing or memory counters for {key}")
    for key, rows in grouped.items():
        if key[-1] not in ("ray_frozen_linear_1024", "ray_snapshot_1024", "ray_forced_index_1024", "frozen_after_release_1024"):
            continue
        expected = {r["repetition"]: r["checksum"] for r in grouped[(*key[:-1], "ray_linear_1024")]}
        for row in rows:
            if row["checksum"] != expected[row["repetition"]]:
                raise ValueError(f"Answer checksum mismatch for {key}")
    return grouped


def value(rows: dict, prefix: tuple, phase: str, field: str = "ns") -> float:
    """Return a phase's sample median without mixing native and hooked runs."""
    return median(r[field] for r in rows[(*prefix, phase)])


def break_even(build: float, live: float, frozen: float) -> int | None:
    """Estimate strict query-count break-even from per-batch medians."""
    saved = (live - frozen) / 1024
    return math.floor(build / saved) + 1 if saved > 0 else None


def summarize(native: dict, hooked: dict) -> dict:
    """Return measured medians and explicitly derived amortization estimates."""
    out = {"corpus": [], "small": [], "dynamic_sweep": [], "refit": []}
    for group, ns, moving in (("corpus", (100, 1000, 10000), 10), ("small", (0, 1, 4, 8, 16, 32, 64), 0)):
        for n in ns:
            for layout in range(4):
                prefix = (group, n, moving, layout)
                build = value(native, prefix, "snapshot_build")
                index_build = value(native, prefix, "forced_index_build")
                live = value(native, prefix, "ray_linear_1024")
                frozen = value(native, prefix, "ray_snapshot_1024")
                owned_linear = value(native, prefix, "ray_frozen_linear_1024")
                indexed = value(native, prefix, "ray_forced_index_1024")
                out[group].append({
                    "static": n, "moving": moving, "layout": LAYOUTS[layout],
                    "snapshot_build_ns": build, "forced_index_build_ns": index_build,
                    "world_batch_ns": live, "snapshot_batch_ns": frozen, "frozen_linear_batch_ns": owned_linear, "forced_index_batch_ns": indexed,
                    "world_over_snapshot": live / frozen, "linear_over_snapshot": owned_linear / frozen, "snapshot_over_forced_index": frozen / indexed,
                    "estimated_snapshot_break_even_rays": break_even(build, live, frozen),
                    "estimated_experimental_index_break_even_rays": break_even(index_build, owned_linear, indexed),
                    "estimated_amortized_snapshot_ns_per_ray": {str(q): build / q + frozen / 1024 for q in (1, 16, 128, 1024, 8192)},
                    "indexed_primitive_entries": value(hooked, prefix, "snapshot_build", "pairs"),
                    "retained_requested_bytes": value(hooked, prefix, "snapshot_build", "live_bytes"),
                    "owned_geometry_capacity_bytes": value(hooked, prefix, "snapshot_build", "geometry_bytes"),
                    "owned_bounds_and_indexes_capacity_bytes": value(hooked, prefix, "snapshot_build", "index_bytes"),
                    "owner_material_capacity_bytes": value(hooked, prefix, "snapshot_build", "metadata_bytes"),
                    "forced_primitive_index_capacity_bytes": value(hooked, prefix, "forced_index_build", "index_bytes"),
                    "world_query_total_bytes": value(hooked, prefix, "ray_linear_1024", "total_bytes"),
                    "world_query_allocations": value(hooked, prefix, "ray_linear_1024", "allocations"),
                    "frozen_linear_query_total_bytes": value(hooked, prefix, "ray_frozen_linear_1024", "total_bytes"),
                    "frozen_linear_query_allocations": value(hooked, prefix, "ray_frozen_linear_1024", "allocations"),
                    "snapshot_query_peak_bytes": value(hooked, prefix, "ray_snapshot_1024", "peak_bytes"),
                    "snapshot_query_total_bytes": value(hooked, prefix, "ray_snapshot_1024", "total_bytes"),
                    "snapshot_query_allocations": value(hooked, prefix, "ray_snapshot_1024", "allocations"),
                    "forced_index_query_peak_bytes": value(hooked, prefix, "ray_forced_index_1024", "peak_bytes"),
                })
    for n in (100, 1000, 10000):
        for moving in (1, 10, 100):
            for layout in range(4):
                prefix = ("corpus", n, moving, layout)
                out["dynamic_sweep"].append({
                    "static": n, "moving": moving, "layout": LAYOUTS[layout],
                    "historical_sweep_query_ns": value(native, prefix, "sweep_query"),
                    "dynamic_prepare_ns": value(native, prefix, "dynamic_prepare"),
                    "dynamic_ordered_query_ns": value(native, prefix, "dynamic_query"),
                    "historical_visited": value(native, prefix, "sweep_query", "work"),
                    "dynamic_visited": value(native, prefix, "dynamic_query", "work"),
                    "pairs": value(native, prefix, "dynamic_query", "pairs"),
                    "pair_scratch_peak_bytes": value(hooked, prefix, "dynamic_query", "peak_bytes"),
                    "pair_scratch_live_bytes": value(hooked, prefix, "dynamic_query", "live_bytes"),
                })
    for n in (100, 1000, 10000):
        for percent in (0, 25, 50, 100):
            prefix = ("refit", n, percent, 0)
            refit = value(native, prefix, "index_refit")
            rebuild = value(native, prefix, "index_rebuild")
            degraded = value(native, prefix, "refit_ray_1024")
            fresh = value(native, prefix, "rebuilt_ray_1024")
            out["refit"].append({
                "entries": n, "permuted_percent": percent,
                "refit_ns": refit, "rebuild_ns": rebuild,
                "refitted_batch_ns": degraded, "rebuilt_batch_ns": fresh,
                "refitted_nodes_visited": value(native, prefix, "refit_ray_1024", "work"),
                "rebuilt_nodes_visited": value(native, prefix, "rebuilt_ray_1024", "work"),
                "candidates": value(native, prefix, "refit_ray_1024", "pairs"),
                "query_time_degradation": degraded / fresh,
                "estimated_rebuild_break_even_batches": math.floor(max(0, rebuild - refit) / (degraded - fresh)) + 1 if degraded > fresh else None,
            })
    return out



def summarize_small_recheck(path: Path) -> dict:
    """Validate the separate nine-sample tiny repeat without replacing rows."""
    phases = ("snapshot_build", "forced_index_build", "ray_linear_1024", "ray_frozen_linear_1024", "ray_snapshot_1024", "ray_forced_index_1024")
    rows = defaultdict(list)
    with path.open(newline="") as stream:
        for raw in csv.DictReader(stream):
            row = dict(raw)
            for key in INTEGER_FIELDS:
                row[key] = int(row[key])
            row["checksum"] = float(row["checksum"])
            if row["group"] != "small" or row["moving"] != 0 or row["ns"] < 0:
                raise ValueError("Invalid tiny-repeat group, participant count, or timing")
            if any(row[k] for k in ("peak_bytes", "total_bytes", "allocations", "live_bytes")):
                raise ValueError("The tiny repeat must be native, without allocation hooks")
            rows[(row["static"], row["distribution"], row["phase"])].append(row)
    required = {(n, d, phase) for n in (0, 1, 4, 8, 16, 32, 64) for d in range(4) for phase in phases}
    if rows.keys() != required:
        raise ValueError("Incomplete or expanded tiny-repeat case set")
    for key, samples in rows.items():
        if sorted(row["repetition"] for row in samples) != list(range(9)):
            raise ValueError(f"Wrong tiny-repeat samples for {key}")
    cases = []
    for n in (0, 1, 4, 8, 16, 32, 64):
        for layout in range(4):
            expected = {r["repetition"]: r["checksum"] for r in rows[(n, layout, "ray_linear_1024")]}
            for phase in phases[3:]:
                for row in rows[(n, layout, phase)]:
                    if row["checksum"] != expected[row["repetition"]]:
                        raise ValueError(f"Tiny-repeat answer mismatch at {n}/{layout}/{phase}")
            timing = {phase: median(r["ns"] for r in rows[(n, layout, phase)]) for phase in phases}
            captures = rows[(n, layout, "ray_snapshot_1024")]
            cases.append({
                "static": n, "layout": LAYOUTS[layout], "phase_median_ns": timing,
                "snapshot_min_ns": min(r["ns"] for r in captures),
                "snapshot_max_ns": max(r["ns"] for r in captures),
                "linear_over_snapshot": timing["ray_frozen_linear_1024"] / timing["ray_snapshot_1024"],
                "estimated_snapshot_break_even_rays": break_even(timing["snapshot_build"], timing["ray_linear_1024"], timing["ray_snapshot_1024"]),
                "indexed_primitive_entries": median(r["pairs"] for r in rows[(n, layout, "snapshot_build")]),
            })
    return {"source": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "samples": sum(map(len, rows.values())), "repetitions": 9, "cases": cases}

def main() -> None:
    """Write a JSON report after verifying the complete native/hooked corpus."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native", type=Path)
    parser.add_argument("allocations", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--small-recheck", type=Path)
    parser.add_argument("--source-manifest", type=Path)
    args = parser.parse_args()
    native = load(args.native, 3)
    hooked = load(args.allocations, 1)
    result = {
        "schema": 1,
        "native_samples": sum(map(len, native.values())),
        "allocation_samples": sum(map(len, hooked.values())),
        "measurements": summarize(native, hooked),
        "raw_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.native, args.allocations)},
        "limitations": [
            "Native timings are shared-host samples, not CPU-isolated claims.",
            "Hooked times are excluded from speedup calculations.",
            "Allocation counters cover requested Mojo bytes on the query thread, not RSS or allocator metadata.",
            "Capacity payloads omit inline headers and capture-token metadata; live_bytes includes all measured surviving runtime allocations.",
            "Amortization values are estimates from independently measured phase medians, not end-to-end samples.",
            "The forced index is experimental and ordinary-corpus parity does not prove safe culling for all accepted Float32 inputs.",
            "Dynamic sweep includes pair output and ordering; historical sweep_query only counts pairs. Neither measures world-step narrow phase or solving.",
            "Refit probes permute entry bounds; they do not add a public snapshot refit API.",
        ],
    }
    if args.small_recheck:
        result["tiny_repeat"] = summarize_small_recheck(args.small_recheck)
    if args.source_manifest:
        result["measured_source"] = json.loads(args.source_manifest.read_text())
    result["analysis_source_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Validated {result['native_samples']} native rows and {result['allocation_samples']} allocation rows")


if __name__ == "__main__":
    main()
