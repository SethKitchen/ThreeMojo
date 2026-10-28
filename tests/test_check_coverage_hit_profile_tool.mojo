# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Altered compiled-coverage evidence is refused.

The checks are the ones in `tools/check_coverage_hit_profile.mojo`.
"""

from std.collections import Dict
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools._cli import absolute_path
from tools.check_coverage_hit_profile import (
    capture_program,
    profile_command,
    validate_capture,
    validate_streams,
)


def _stdout() -> String:
    """Return a passing two-test summary."""
    return (
        "Running 2 tests for fixture.mojo\n"
        "    PASS [ 1.000 ] test_phase\n"
        "    PASS [ 1.000 ] test_vectors\n"
        "Summary [ 2.000 ] 2 tests run: 2 passed , 0 failed , 0 skipped\n"
    )


def _warm() -> String:
    """Return warm stderr with three diagnostics and three vectors."""
    return (
        "COVLINE:fact:1\n"
        + "COVLINE:diagnostic:1\n"
        + "COVLINE:diagnostic:1\n"
        + "COVLINE:diagnostic:1\n"
        + "COVEVAL2:runtime:decision:F:TF;\n"
        + "COVEVAL2:cached:3:F:TF;\n"
        + "COVEVAL2:cached:3:F:TF;\n"
        + "COVEVAL2:cached:3:F:TF;\n"
    )


def _cold() -> String:
    """Return cold stderr, which also has the compile-time vector."""
    return "COVEVAL2:compile:decision:F:TF;\n" + _warm()


def _streams() -> Dict[String, String]:
    """Return matching streams for raw, aot and aot-hits."""
    var streams = Dict[String, String]()
    for profile in ["raw", "aot", "aot-hits"]:
        streams[profile + "\ncold"] = _cold()
        streams[profile + "\nwarm"] = _warm()
    return streams^


def _identities() -> Dict[String, String]:
    """Return matching argv text for every profile."""
    var identities = Dict[String, String]()
    for profile in ["raw", "aot", "aot-hits"]:
        for source in ["absolute", "relative"]:
            identities[profile + "\n" + source] = source + "\nargument\ncwd\n"
    return identities^


def _profiles() -> List[String]:
    """Return the profiles compared with raw."""
    var profiles = List[String]()
    profiles.append("aot")
    profiles.append("aot-hits")
    return profiles^


def _sources() -> List[String]:
    """Return the two source identities."""
    var sources = List[String]()
    sources.append("absolute")
    sources.append("relative")
    return sources^


def test_valid_evidence_is_accepted() raises:
    validate_capture(_stdout(), _cold(), "cold")
    validate_capture(_stdout(), _warm(), "warm")
    validate_streams(_streams(), _profiles(), _identities(), _sources())


def test_a_missing_vector_is_refused() raises:
    var streams = _streams()
    var cold = streams["aot-hits\ncold"]
    var needle = "COVEVAL2:cached:3:F:TF;\n"
    var cut = cold.find(needle)
    var head = String(cold[byte=:cut])
    var tail = String(cold[byte = cut + needle.byte_length() :])
    streams["aot-hits\ncold"] = head + tail
    with assert_raises(contains="complete vector sequence changed"):
        validate_streams(streams, _profiles(), _identities(), _sources())


def test_a_changed_vector_is_refused() raises:
    var streams = _streams()
    streams["aot-hits\ncold"] = streams["aot-hits\ncold"].replace(
        "cached:3:F:TF", "cached:3:T:TT"
    )
    with assert_raises(contains="complete vector sequence changed"):
        validate_streams(streams, _profiles(), _identities(), _sources())


def test_a_lost_hit_is_refused() raises:
    var streams = _streams()
    streams["aot-hits\nwarm"] = streams["aot-hits\nwarm"].replace(
        "COVLINE:fact:1\n", ""
    )
    with assert_raises(contains="hit/evaluation evidence changed"):
        validate_streams(streams, _profiles(), _identities(), _sources())


def test_a_slow_test_is_refused() raises:
    var stdout = _stdout().replace("1.000", "5001.000")
    with assert_raises():
        validate_capture(stdout, _warm(), "warm")


def test_missing_results_are_refused() raises:
    with assert_raises():
        validate_capture(
            "program exited without test results\n", _warm(), "warm"
        )


def test_changed_argv_is_refused() raises:
    var identities = _identities()
    identities["aot-hits\nrelative"] = "wrong argv0\n"
    with assert_raises(contains="working directory changed"):
        validate_streams(_streams(), _profiles(), identities, _sources())


def test_a_missing_diagnostic_is_refused() raises:
    var cold = _cold().replace("COVLINE:diagnostic:1\n", "")
    with assert_raises(contains="ordinary diagnostic multiplicity changed"):
        validate_capture(_stdout(), cold, "cold")


def test_a_warm_compile_vector_is_refused() raises:
    with assert_raises(contains="compile-time vector/cache-scope mismatch"):
        validate_capture(_stdout(), _cold(), "warm")


def test_the_adapter_command_stays_in_the_repository() raises:
    var arguments = List[String]()
    arguments.append("argument with spaces")
    var command = profile_command(
        "/opt/mojo",
        "/tmp/work dir",
        "/tmp/work dir/probe.mojo",
        "identity.mojo",
        "aot",
        arguments,
        "aot",
        "/repo",
    )
    var text = "\n".join(command)
    assert_equal(command[0], "env")
    assert_true(
        text.find(
            "/opt/mojo\nrun\n-I\n/repo\n/repo/tools/coverage_hit_aot.mojo\n"
        )
        >= 0
    )
    assert_true(text.find("-I\n/repo\nidentity.mojo\n") >= 0)
    assert_true(text.find("--\n/opt/mojo\nrun\n") >= 0)
    assert_equal(command[len(command) - 1], "argument with spaces")
    var root = absolute_path(".")
    var compiler = absolute_path(".venv/bin/mojo")
    assert_true(root.startswith("/"))
    assert_true(compiler.startswith("/"))


def test_a_profile_capture_keeps_standard_error_on_a_pipe() raises:
    var command = List[String]()
    command.append("python3")
    command.append("-c")
    command.append(
        "import os, stat, sys\n"
        "sys.stdout.write('out')\n"
        "kind = 'fifo' if stat.S_ISFIFO(os.fstat(2).st_mode) else 'file'\n"
        "sys.stderr.write(kind)\n"
    )
    var result = capture_program(command, 10.0)
    assert_equal(result.status, 0)
    assert_equal(result.output, "out")
    assert_equal(result.errors, "fifo")
    assert_false(result.timed_out)


def test_a_profile_capture_stops_at_its_time_limit() raises:
    var command = List[String]()
    command.append("sh")
    command.append("-c")
    command.append("echo started; echo err 1>&2; exec sleep 30")
    var result = capture_program(command, 0.3)
    assert_true(result.timed_out)
    assert_equal(result.status, 128 + 9)
    assert_equal(result.output, "started\n")
    assert_equal(result.errors, "err\n")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
