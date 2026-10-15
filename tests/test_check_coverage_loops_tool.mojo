# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compiler-free controls for the loop coverage check.

The fixture digests are those of the sources and manifests that the Python
tool wrote. A shell script stands in for the compiler, so no test builds
Mojo.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._cli import parse_command_line
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.check_coverage_loops import (
    HELP,
    PROGRAM,
    USAGE,
    cases,
    check,
    check_records,
    fixture,
)
from tools.check_coverage_sources import manifest

comptime SOURCES = [
    "2575d6c73f442566d8eb67caef263393369bafbe246891d5b82b782a22e381a7",
    "596b060dce7fadc614a097cec3db6fd31fee6b50402568824699093feb31f3a2",
    "219ba1accb69c97a1ff97009c622fc1f3ae669d847ad6daeadefc96764fd6763",
    "e8f32bb2e33e5a39de99aa65e613ed948af9117e455c66b0c301aa448c0e9866",
    "8d220849db2b918997911d8c1c31c5e564f192a03e940af36a8da39d375267c5",
    "1ce9d6d895493410b82be6a85a5e4d1a5ed840146c566dfdd8f0ee83f4ec737d",
    "1ce219eb059a4cf36799c16a2891d2a95ac03ae332c07e7f036f73399a97b194",
    "a706e136c71478a3e0489da0cd4422387cf3b0c597dbd81e6fba97280f9753f5",
    "063edc7e790e839cc20d921065410ec0953b5bf1c98880fdce5941bea58ebeff",
]
"""The SHA-256 of each case's native source, in case order."""

comptime MANIFESTS = [
    "a46e684e1da4f4dd6d2f72e0890c19a78baf3bd4cba23ff51851ac5e3a3b8882",
    "fb09b842d722f7b1e1937917210a9ee7a606624e5fdee25938a3ecbe3b3610d0",
    "e33415098170b19f81c7a9d4984dcd02c0060cdaf736ecdbdaee030241d7ecfb",
    "3d7116ae286d04d4b55dc69ddc1fa27b9fc2007135be458d97733255a1b19618",
    "e581b58f1490fd4f8b451206d3ab5319fcf6b79d09d8c03888dd1642ec26f888",
    "d55c1bd5c7cb844b4dc7d87f69204c6ab4301adce50ba984e9a6f70e0862e5c0",
    "dff53ca556c25bba9ebecd194a86f9379ba32766fc5678be2683b58244b62936",
    "6e483c1c56e4cb56a8f0eccc178d59db5ecc0b16f4551413a53ccf81d76637e6",
    "dbc3c76dba7813d7c6b74daf2600cb598598a9641c2c21be2ff64bccf3354f2e",
]
"""The SHA-256 of each case's expected manifest, in case order."""


def _module(number: Int) -> String:
    """Return the module name of a case."""
    var all = cases()
    return (
        "loops_"
        + String(all[number][0])
        + "_"
        + String(all[number][1])
        + "_"
        + String(number)
    )


def test_fixtures_and_manifests_match_the_python_tool() raises:
    var all = cases()
    assert_equal(len(all), 9)
    var sources = materialize[SOURCES]()
    var manifests = materialize[MANIFESTS]()
    for number in range(len(all)):
        var made = fixture(
            all[number][0], all[number][1], all[number][2], all[number][3]
        )
        assert_equal(
            sha256_hex(made[0].as_bytes()), sources[number], String(number)
        )
        var text = manifest(_module(number), made[1].lines, made[1].decisions)
        assert_equal(
            sha256_hex(text.as_bytes()), manifests[number], String(number)
        )


def test_fixture_labels_and_line_endings() raises:
    var made = fixture(4, 4)
    assert_equal(made[1].labels["simple"], 4)
    assert_equal(made[1].labels["inner"], 24)
    assert_equal(made[1].labels["main_flow"], 62)
    var carriage = fixture(2, 2, "\r", True)
    assert_true(carriage[0].endswith('print("RESULT loops")\r'))
    assert_true(carriage[0].find('"literal\\tvalue\\rfor fake') >= 0)
    assert_true(carriage[0].find("- 2\r") >= 0)
    var open_end = fixture(2, 2, "\n", False)
    assert_true(open_end[0].endswith('print("RESULT loops")'))
    var windows = fixture(2, 2, "\r\n", True)
    assert_true(windows[0].find("- 3\r\n") >= 0)


def _raw() -> List[String]:
    """Return the records that the four-space fixture must write."""
    var rows: List[String] = [
        "COVLINE:m:61",
        "COVLINE:m:3",
        "COVLINE:m:4",
        "COVLINE:m:4:T",
        "COVLINE:m:8",
        "COVLINE:m:4:T",
        "COVLINE:m:8",
        "COVLINE:m:4:T",
        "COVLINE:m:9",
        "COVLINE:m:62",
    ]
    var outcomes: List[Tuple[Int, String]] = [
        (13, "FTTTTTTT"),
        (24, "TTTTTTTTTTTT"),
        (40, "FTF"),
        (49, "T"),
        (53, "TT"),
    ]
    for entry in outcomes:
        for byte in entry[1].as_bytes():
            rows.append("COVLINE:m:" + String(entry[0]) + ":" + chr(Int(byte)))
    return rows^


def test_records_accept_the_exact_loop_outcomes() raises:
    var made = fixture(4, 4)
    check_records("\n".join(_raw()) + "\n", "m", made[1])


def test_records_reject_extra_missing_and_reordered_records() raises:
    var made = fixture(4, 4)
    var extra = _raw()
    extra.append("COVLINE:m:5")
    with assert_raises(contains="AssertionError: {'COVLINE:m:5'}"):
        check_records("\n".join(extra) + "\n", "m", made[1])
    var missing = _raw()
    _ = missing.pop()
    with assert_raises(
        contains="AssertionError: ('literal_header', ['T'], 'TT')"
    ):
        check_records("\n".join(missing) + "\n", "m", made[1])
    var order = _raw()
    var first = order[0]
    order[0] = order[1]
    order[1] = first
    with assert_raises(contains="AssertionError: ['COVLINE:m:3'"):
        check_records("\n".join(order) + "\n", "m", made[1])
    var outcome = _raw()
    outcome[10] = "COVLINE:m:13:T"
    with assert_raises(contains="'outer'"):
        check_records("\n".join(outcome) + "\n", "m", made[1])


def test_a_failing_compiler_stops_the_check() raises:
    var tree = Tree()
    tree.write("mojo", "#!/bin/sh\necho broken compiler >&2\nexit 9\n")
    _ = run_program(["chmod", "+x", tree.root + "/mojo"], 10)
    with assert_raises(contains="broken compiler"):
        check(tree.root + "/mojo", None, None)
    tree.close()


def test_help_and_usage_errors_match_argparse() raises:
    var valued: List[String] = ["--mojo", "--output", "--baseline-build"]
    var help = parse_command_line(
        ["-h"], PROGRAM, USAGE, HELP, List[String](), valued
    )
    assert_equal(help.status, -1)
    assert_true(help.message.find("Optional frozen build_cli") >= 0)
    var bad = parse_command_line(
        ["--base"], PROGRAM, USAGE, HELP, List[String](), valued
    )
    assert_equal(bad.status, 2)
    assert_true(
        bad.message.endswith(
            "check_coverage_loops.mojo: error: argument --baseline-build:"
            " expected one argument\n"
        )
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
