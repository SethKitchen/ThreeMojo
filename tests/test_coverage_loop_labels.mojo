# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The coverage-loop qualification labels stay reviewed."""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools._coverage_loop_labels import coverage_loop_labels
from tools._python_json import PyJson


def test_coverage_loop_qualification_labels_stay_reviewed() raises:
    """The receipt counts, the pass line, and the result order stay reviewed."""
    var doc = PyJson.parse(coverage_loop_labels())
    var dependencies = doc.at(doc.root, "dependencies")
    assert_equal(doc.length(dependencies), 3)
    assert_equal(doc.text(doc.item(dependencies, 0)), "core/__init__.mojo")
    assert_equal(doc.text(doc.item(dependencies, 1)), "core/search.mojo")
    assert_equal(doc.text(doc.item(dependencies, 2)), "core/binary.mojo")
    var owner = doc.at(doc.root, "owner")
    assert_equal(doc.text(doc.at(owner, "fresh_receipts")), "3")
    assert_equal(doc.text(doc.at(owner, "counted_receipts")), "2")
    assert_true(doc.flag(doc.at(owner, "conditioned_authority_refusal")))
    var completed = doc.at(doc.at(doc.root, "root_only"), "completed")
    assert_equal(doc.length(completed), 3)
    assert_equal(
        doc.text(doc.item(completed, 0)), "root-only-seed-and-shared-positive"
    )
    var results = doc.at(doc.root, "results")
    assert_equal(doc.key(results, 0), "entry-probe-mutation")
    assert_equal(doc.key(results, 8), "interrupted-generation")
    var hang = doc.at(results, "test_production_hang")
    assert_equal(doc.text(doc.at(hang, "status")), "142")
    assert_false(doc.flag(doc.at(hang, "success_receipt")))
    var conditioned = doc.at(doc.root, "conditioned")
    assert_equal(
        doc.text(doc.at(conditioned, "error")),
        "conditioned cubic authority namespace changed",
    )
    assert_equal(doc.text(doc.item(doc.at(conditioned, "steps"), 0)), "active")
    assert_equal(doc.text(doc.item(doc.at(conditioned, "steps"), 2)), "sticky")
    assert_equal(
        doc.text(doc.at(doc.root, "mutation_key")), "current_mutation_controls"
    )
    var mutation = doc.at(doc.root, "mutation")
    var faults = doc.at(mutation, "faults")
    assert_equal(doc.length(faults), 15)
    assert_equal(doc.text(doc.item(faults, 0)), "source")
    assert_equal(doc.text(doc.item(faults, 14)), "nested-owner")
    assert_equal(doc.text(doc.at(mutation, "unreviewed")), "unreviewed")
    assert_equal(doc.text(doc.at(mutation, "seed_change")), " changed")
    assert_equal(doc.text(doc.at(mutation, "origin_suffix")), ".cov-origin")
    assert_equal(doc.text(doc.at(mutation, "foreign_root")), "foreign")
    assert_equal(
        doc.text(doc.at(mutation, "foreign")),
        "Foreign current owner context was accepted",
    )
    assert_equal(doc.text(doc.at(mutation, "open_mode")), "xb")
    assert_equal(doc.text(doc.at(mutation, "frame_seed")), "_receipt_seed")
    assert_equal(
        doc.text(doc.at(mutation, "source")),
        "extensions/carla/curve_rounded_arc.mojo",
    )
    var admission = doc.at(doc.root, "admission")
    var helpers = doc.at(admission, "helpers")
    assert_equal(doc.length(helpers), 2)
    assert_equal(
        doc.text(doc.item(helpers, 0)), "extensions/carla/render_sky.mojo"
    )
    assert_equal(doc.text(doc.item(doc.at(admission, "steps"), 0)), "scaled")
    assert_equal(doc.text(doc.item(doc.at(admission, "steps"), 1)), "render")
    assert_equal(doc.text(doc.at(admission, "render_prefix")), "render/")
    assert_equal(doc.text(doc.at(admission, "mojo_suffix")), ".mojo")
    assert_equal(doc.text(doc.at(doc.root, "theorem_count")), "6")
    assert_equal(doc.text(doc.at(doc.root, "runtime_seconds")), "5")
    assert_equal(doc.text(doc.at(doc.root, "integration_seconds")), "180")
    var commands = doc.at(doc.root, "commands")
    assert_equal(doc.text(doc.at(commands, "coverage_io")), "coverage_io")
    assert_equal(doc.text(doc.at(commands, "seal")), "coverage_loop_seal")
    assert_equal(doc.text(doc.at(commands, "flags")), "-Werror -I .")
    assert_equal(doc.text(doc.at(commands, "receipt")), "loop-proofs.json")
    assert_equal(doc.text(doc.at(commands, "raw_suffix")), ".raw.txt")
    assert_equal(doc.text(doc.at(commands, "reduced_suffix")), ".txt.gz")
    var options = doc.at(commands, "options")
    assert_equal(doc.text(doc.at(options, "out")), "--out")
    assert_equal(doc.text(doc.at(options, "loop_proof")), "--loop-proof")
    assert_equal(doc.text(doc.at(options, "separator")), "--")
    var profile = doc.at(doc.root, "profile")
    assert_equal(doc.text(doc.at(profile, "call")), "call")
    assert_equal(doc.text(doc.at(profile, "return")), "return")
    assert_equal(doc.text(doc.at(profile, "full")), "full")
    assert_equal(doc.text(doc.at(profile, "generated")), "generated_receipt")
    assert_equal(doc.text(doc.at(profile, "full_count")), "1")
    assert_equal(doc.text(doc.at(commands, "mojo_env")), "MOJO")
    assert_equal(doc.text(doc.at(commands, "mojo_bin")), ".venv/bin/mojo")
    assert_equal(
        doc.text(doc.at(commands, "oracle")), "tools/carla_lane_oracle"
    )
    var fields = doc.at(doc.root, "fields")
    assert_equal(doc.text(doc.at(fields, "root_inputs")), "root_inputs")
    assert_equal(doc.text(doc.at(fields, "capture_cache")), "capture_cache")
    assert_equal(
        doc.text(doc.at(doc.root, "pass_line")),
        (
            "PASS: unchanged native loop streams; constant reachable"
            " outcomes; dynamic-empty negative; raw/reduced report parity;"
            " actual native entry-probe mutation rejected; shadowed range"
            " stays unknown"
        ),
    )


def main() raises:
    """Run the coverage-loop label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
