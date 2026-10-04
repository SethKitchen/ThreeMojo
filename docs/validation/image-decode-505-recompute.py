# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Recompute #505 summaries from checked-in data without native execution."""

import argparse
from collections import defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import statistics

PREFIX = "image-decode-505"
CHECK_FIELDS = ("textures", "base_bytes", "payload_bytes", "mip_levels",
                "all_fnv64", "base_fnv64", "shape_fnv64")
TEXT_FIELDS = {"run", "dataset", "api", "variant", "recorded_utc"}
FLOAT_FIELDS = {"user_seconds", "system_seconds"}


def distribution(values):
    middle = statistics.median(values)
    return {"n": len(values), "median": middle, "min": min(values),
            "max": max(values),
            "mad": statistics.median(abs(value - middle) for value in values)}


def read_trials(directory):
    with (directory / (PREFIX + "-trials.csv")).open("r", encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    return [{key: value if key in TEXT_FIELDS else float(value) if key in FLOAT_FIELDS
             else int(value) for key, value in row.items()} for row in rows]


def summarize(rows):
    groups = defaultdict(lambda: defaultdict(dict))
    for row in rows:
        key = (row["run"], row["dataset"], row["api"], row["workers"])
        variant = groups[key][row["variant"]]
        assert row["repetition"] not in variant, "Duplicate trial"
        variant[row["repetition"]] = row
    cases = []
    for (run, dataset, api, workers), variants in sorted(groups.items()):
        assert set(variants) == {"baseline", "dynamic", "stride"}
        repetitions = set(variants["dynamic"])
        assert all(set(samples) == repetitions for samples in variants.values())
        item = {"run": run, "dataset": dataset, "api": api, "workers": workers,
                "repetitions": len(repetitions), "variants": {}, "paired": {}}
        for variant, samples in sorted(variants.items()):
            sample_rows = list(samples.values())
            item["variants"][variant] = {
                "load_ns": distribution([r["load_ns"] for r in sample_rows]),
                "peak_rss_bytes": distribution([r["peak_rss_bytes"] for r in sample_rows]),
                "images_per_second": distribution([r["textures"] * 1e9 / r["load_ns"] for r in sample_rows]),
                "base_megapixels_per_second": distribution([r["base_bytes"] * 250 / r["load_ns"] for r in sample_rows]),
            }
        for reference in ("baseline", "stride"):
            pairs = [(variants["dynamic"][i], variants[reference][i]) for i in sorted(repetitions)]
            item["paired"][reference] = {
                "speedup": distribution([ref["load_ns"] / dyn["load_ns"] for dyn, ref in pairs]),
                "rss_ratio": distribution([dyn["peak_rss_bytes"] / ref["peak_rss_bytes"] for dyn, ref in pairs]),
            }
        cases.append(item)
    return {"schema": 1, "description": "All dynamic cases with each variant's distributions and paired dynamic comparisons.",
            "units": {"load_ns": "nanoseconds", "peak_rss_bytes": "bytes", "speedup": "reference load_ns / dynamic load_ns",
                      "rss_ratio": "dynamic peak_rss_bytes / reference peak_rss_bytes", "mad": "unscaled median absolute deviation"},
            "cases": cases}


def summary_csv(summary):
    flattened = []
    for item in summary["cases"]:
        row = {key: item[key] for key in ("run", "dataset", "api", "workers", "repetitions")}
        for variant, metrics in item["variants"].items():
            for metric, stats in metrics.items():
                for stat, value in stats.items():
                    if stat != "n":
                        row[f"{variant}_{metric}_{stat}"] = value
        for reference, metrics in item["paired"].items():
            for metric, stats in metrics.items():
                for stat, value in stats.items():
                    if stat != "n":
                        row[f"dynamic_vs_{reference}_{metric}_{stat}"] = value
        flattened.append(row)
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=list(flattened[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(flattened)
    return stream.getvalue()


def verify(rows, provenance):
    signatures = {}
    fixtures = {dataset["name"]: dataset for dataset in provenance["fixtures"]["datasets"]}
    for row in rows:
        assert row["exit_code"] == row["native_exit_code"] == row["native_signal"] == row["exec_errno"] == 0
        assert row["timed_out"] == row["measurement_error"] == 0
        assert row["load_ns"] > 0 and row["peak_rss_bytes"] > 0
        assert row["peak_rss_bytes"] == row["maxrss_raw"] * 1024
        assert row["runtime_parallelism"] == 9
        for key, value in fixtures[row["dataset"]]["expected"].items():
            assert row[key] == value, (row["dataset"], key)
        signature = tuple(row[key] for key in CHECK_FIELDS)
        assert signatures.setdefault(row["dataset"], signature) == signature
    for run, metadata in provenance["runs"].items():
        subset = [row for row in rows if row["run"] == run]
        assert len(subset) == metadata["planned_rows"] == metadata["completed_rows"]
        assert metadata["status"] == "complete"
        counts = defaultdict(int)
        positions = defaultdict(list)
        for row in subset:
            key = (row["dataset"], row["api"], row["workers"], row["variant"])
            counts[key] += 1
            positions[key].append(row["variant_order"])
        expected = {(ds, api, w, v) for ds in fixtures for api in ("gltf", "registry")
                    for w in (1, 2, 4, 17) for v in ("baseline", "dynamic", "stride")}
        assert set(counts) == expected
        assert all(n == metadata["repetitions"] for n in counts.values())
        assert all(sorted(value) == sorted(list(range(3)) * (metadata["repetitions"] // 3))
                   for value in positions.values())
    base = provenance["baseline_mojo_files"]
    for variant in provenance["build"]["variants"].values():
        source = variant["source"]
        files = {key: value for key, value in base.items() if key not in source["removed_from_baseline"]}
        files.update(source["file_updates_from_baseline"])
        digest = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        assert digest == source["mojo_tree_sha256"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--write", action="store_true", help="replace JSON/CSV summaries after successful validation")
    args = parser.parse_args()
    with (args.directory / (PREFIX + "-provenance.json")).open("r", encoding="utf-8") as stream:
        provenance = json.load(stream)
    trials_path = args.directory / (PREFIX + "-trials.csv")
    assert hashlib.sha256(trials_path.read_bytes()).hexdigest() == provenance["normalized_trials_sha256"]
    rows = read_trials(args.directory)
    verify(rows, provenance)
    summary = summarize(rows)
    json_path = args.directory / (PREFIX + "-summary.json")
    csv_path = args.directory / (PREFIX + "-summary.csv")
    csv_text = summary_csv(summary)
    if args.write:
        json_path.write_text(json.dumps(summary, sort_keys=True, separators=(",", ":")) + "\n")
        csv_path.write_text(csv_text)
    else:
        assert json.loads(json_path.read_text()) == summary, "JSON summary differs"
        assert csv_path.read_text() == csv_text, "CSV summary differs"
    print(f"PASS: {len(rows)} trials, {len(summary['cases'])} case summaries, all output oracles and source inventory hashes")


if __name__ == "__main__":
    main()
