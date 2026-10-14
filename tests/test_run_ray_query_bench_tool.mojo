# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ray-query runner's statistics reproduce the published #550 summaries.

The retained trials are the rows the Python runner measured. Its summaries
are in `docs/validation/ray-query-550.json`.
"""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from bench.run_ray_query_bench import (
    Num,
    canonical_digest,
    median,
    parse_options,
    quartiles,
    read_trials,
    summarize,
)
from tools._json_tools import json_tokens

comptime EVIDENCE = "docs/validation/ray-query-550"


def _summary_tokens(run: String) raises -> List[String]:
    """Return the tokens of a published summary object."""
    var text = Path(EVIDENCE + ".json").read_text()
    var found = json_tokens(text)[0].copy()
    # Find "runs": { ... "<run>": { ... "summary": { ... } } }.
    var index = 0
    var depth = 0
    var in_runs = False
    var in_run = False
    while index < len(found):
        var token = found[index]
        if token == '"runs"' and depth == 1:
            in_runs = True
        elif in_runs and token == '"' + run + '"' and depth == 2:
            in_run = True
        elif in_run and token == '"summary"' and depth == 3:
            var start = index + 2
            var level = 0
            var stop = start
            while True:
                if found[stop] == "{" or found[stop] == "[":
                    level += 1
                elif found[stop] == "}" or found[stop] == "]":
                    level -= 1
                    if level == 0:
                        break
                stop += 1
            return List[String](found[start : stop + 1])
        if token == "{" or token == "[":
            depth += 1
        elif token == "}" or token == "]":
            depth -= 1
        index += 1
    raise Error("summary not found: " + run)


def test_the_published_summaries_are_reproduced() raises:
    for run in ["primary", "long"]:
        var rows = read_trials(
            Path(EVIDENCE + "-" + run + "-trials.csv").read_text()
        )
        var mine = json_tokens(summarize(rows, 8))[0].copy()
        assert_true(mine == _summary_tokens(run), run)


def test_quantiles_follow_python() raises:
    # statistics.quantiles([1.0, 2.0, 3.0, 4.0, 10.0]) == [1.5, 3.0, 7.0]
    var values: List[Float64] = [10.0, 1.0, 3.0, 2.0, 4.0]
    var quarters = quartiles(values)
    assert_equal(quarters[0], 1.5)
    assert_equal(quarters[1], 7.0)
    with assert_raises():
        var one: List[Float64] = [1.0]
        _ = quartiles(one)
    var even: List[Num] = [Num(1.0, True), Num(4.0, True)]
    assert_equal(median(even).value, 2.5)


def test_canonical_digest_hashes_compact_sorted_json() raises:
    var entries: List[Tuple[String, String]] = [("a", "b")]
    # hashlib.sha256(b'{"a":"b"}').hexdigest()
    assert_equal(
        canonical_digest(entries),
        "db4a7ecb114bc66c623a06c4ff6fe8daa2f49cc270ebbf7a1f81e22ab061c837",
    )


def test_options_are_checked() raises:
    var good: List[String] = [
        "--baseline",
        "b",
        "--candidate",
        "c",
        "--output",
        "o",
        "--cpu",
        "0",
    ]
    var options = parse_options(good)
    assert_equal(options.pairs, 8)
    var odd = good.copy()
    odd.extend(["--pairs", "3"])
    with assert_raises(contains="even"):
        _ = parse_options(odd)
    var missing: List[String] = ["--baseline", "b"]
    with assert_raises(contains="required"):
        _ = parse_options(missing)
    var unknown: List[String] = ["--speed", "1"]
    with assert_raises(contains="unrecognized"):
        _ = parse_options(unknown)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
