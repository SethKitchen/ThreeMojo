# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The `test-tools` recipe keeps its original commands when it is sharded.

A stand-in `python3` records each argument list. The expensive checks do
not run.
"""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._make_recipe import clean_command, section
from tests._tree import Tree
from tools._process import run_program
from tools._python_json import PyJson


def _python() raises -> String:
    """Return the real Python interpreter.

    Returns:
        An absolute `python3`.

    Raises:
        Error: If Python is not on `PATH`.
    """
    var found = run_program(["sh", "-c", "command -v python3"], 5)
    if found.status != 0:
        raise Error("python3 is not on PATH")
    return String(found.output.split("\n")[0])


def _recipe() raises -> String:
    """Return the shard rule and the `test-tools` recipes.

    Returns:
        The Makefile text.

    Raises:
        Error: If the markers are missing.
    """
    return section(
        Path("Makefile").read_text(),
        "TOOLS_SHARD ?=\n",
        "\n# The negative-fixture",
    )


def _calls(path: String) raises -> List[List[String]]:
    """Return the recorded argument lists.

    Args:
        path: The `calls` file.

    Returns:
        Each command's arguments after `python3`.

    Raises:
        Error: If a line is not a JSON list of strings.
    """
    var calls = List[List[String]]()
    if not Path(path).exists():
        return calls^
    for line in Path(path).read_text().splitlines():
        var doc = PyJson.parse(String(line))
        var call = List[String]()
        for index in range(doc.length(doc.root)):
            call.append(doc.text(doc.item(doc.root, index)))
        calls.append(call^)
    return calls^


def _sq(text: String) -> String:
    """Return `text` as a single-quoted Makefile word."""
    var out = String("'")
    var raw = text.as_bytes()
    for index in range(len(raw)):
        if raw[index] == 39:
            out += "'\"'\"'"
        else:
            out += chr(Int(raw[index]))
    out += "'"
    return out


def _project(interpreter: String) raises -> Tree:
    """Return a project whose `python3` only records its arguments.

    Args:
        interpreter: The real Python used by the stand-in's shebang.

    Returns:
        The project.

    Raises:
        Error: If the project cannot be written.
    """
    var tree = Tree()
    var stub = (
        "#!"
        + interpreter
        + "\n"
        + "import json, os, sys\n"
        + "with open('calls', 'a') as out:\n"
        + "    out.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        + "if os.environ.get('FAIL_COMMAND') in sys.argv[1:]:\n"
        + "    raise SystemExit(7)\n"
    )
    tree.write("bin/python3", stub)
    _ = run_program(["chmod", "755", tree.root + "/bin/python3"], 5)
    tree.write(
        "Makefile",
        ".PHONY: test-tools test-tools-discovery test-tools-oracle"
        " repository-check\n"
        + "JOBS := 3\n"
        + "TOOL := "
        + _sq(tree.root + "/bin/python3")
        + "\n"
        + _recipe()
        + "\nrepository-check:\n\t@python3 repository-check\n",
    )
    return tree^


def _run(
    interpreter: String, target: String, shard: String = "", fail: String = ""
) raises -> Tuple[Int, String, List[List[String]]]:
    """Run one recipe and return its status, errors, and calls.

    Args:
        interpreter: The real Python.
        target: The make target.
        shard: `I/N`, or empty for an unsharded run.
        fail: An argument that makes the stand-in exit 7.

    Returns:
        The status, the combined output, and the recorded calls.

    Raises:
        Error: If make cannot start.
    """
    var tree = _project(interpreter)
    # PATH keeps the system tools make needs, with the stand-in first.
    var path = run_program(["sh", "-c", 'printf %s "$PATH"'], 5)
    var settings = List[String]()
    settings.append("PATH=" + tree.root + "/bin:" + path.output)
    if fail.byte_length() > 0:
        settings.append("FAIL_COMMAND=" + fail)
    var make = List[String]()
    make.append("make")
    make.append("-s")
    make.append(target)
    if shard.byte_length() > 0:
        make.append("TOOLS_SHARD=" + shard)
    var command = clean_command(settings, make)
    var full = List[String]()
    full.append("env")
    full.append("-u")
    full.append("TOOLS_SHARD")
    for index in range(1, len(command)):
        full.append(command[index])
    var result = run_program(full, 10, merge_errors=True, directory=tree.root)
    var calls = _calls(tree.root + "/calls")
    var status = result.status
    var output = result.output
    tree.close()
    return (status, output, calls^)


def _equal(actual: List[String], expected: List[String]) raises:
    """Require two argument lists to match.

    Args:
        actual: The recorded arguments.
        expected: The required arguments.

    Raises:
        Error: If they differ.
    """
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _format() -> List[String]:
    var call = List[String]()
    call.append("check_format_arguments")
    return call^


def _discover_tools() -> List[String]:
    var call = List[String]()
    call.append("-m")
    call.append("unittest")
    call.append("discover")
    call.append("-s")
    call.append("tools")
    call.append("-p")
    call.append("test_*.py")
    return call^


def _oracle(shard: String) -> List[String]:
    var call = List[String]()
    call.append("parallel_unittest")
    call.append("--jobs")
    call.append("3")
    if shard.byte_length() > 0:
        call.append("--shard")
        call.append(shard)
    call.append("tools/carla_lane_oracle")
    return call^


def _spiral() -> List[String]:
    var call = List[String]()
    call.append("tools/carla_lane_oracle/spiral_moments.py")
    call.append("--check")
    return call^


def _repository() -> List[String]:
    var call = List[String]()
    call.append("repository-check")
    return call^


def _has(call: List[String], word: String) -> Bool:
    for argument in call:
        if argument == word:
            return True
    return False


def test_unsharded_runs_all_original_commands_in_order() raises:
    var python = _python()
    var result = _run(python, "test-tools")
    assert_equal(result[0], 0, result[1])
    var calls = result[2].copy()
    assert_equal(len(calls), 5)
    _equal(calls[0], _format())
    _equal(calls[1], _discover_tools())
    _equal(calls[2], _oracle(""))
    _equal(calls[3], _spiral())
    _equal(calls[4], _repository())


def test_small_shard_counts_keep_each_auxiliary_check_once() raises:
    var python = _python()
    for count in [1, 2, 3, 4]:
        var seen = List[String]()
        for index in range(1, count + 1):
            var shard = String(index) + "/" + String(count)
            var result = _run(python, "test-tools", shard)
            assert_equal(result[0], 0, shard + "\n" + result[1])
            var discovery = 0
            var tail = 0
            var oracle = List[String]()
            for call in result[2]:
                if len(call) >= 2 and call[0] == "-m" and call[1] == "unittest":
                    discovery += 1
                    seen.append(call[4])
                elif len(call) > 0 and call[0] == "parallel_unittest":
                    oracle = call.copy()
                elif len(call) > 0 and (
                    call[0] == "tools/carla_lane_oracle/spiral_moments.py"
                    or call[0] == "repository-check"
                ):
                    tail += 1
                    seen.append(call[0])
            var expected_discovery = 0
            if index == 1:
                expected_discovery = 1
            assert_equal(discovery, expected_discovery, shard)
            var expected_tail = 0
            if index == 1:
                expected_tail = 2
            assert_equal(tail, expected_tail, shard)
            _equal(oracle, _oracle(shard))
        assert_true(_has(seen, "tools"))


def test_large_shard_counts_keep_discovery_on_shard_five() raises:
    var python = _python()
    for count in [5, 6, 7, 12]:
        var tools = 0
        var spiral = 0
        var repository = 0
        for index in range(1, count + 1):
            var shard = String(index) + "/" + String(count)
            var result = _run(python, "test-tools", shard)
            assert_equal(result[0], 0, shard + "\n" + result[1])
            var discovery = 0
            var tail = 0
            var oracle = List[String]()
            for call in result[2]:
                if len(call) >= 2 and call[0] == "-m" and call[1] == "unittest":
                    discovery += 1
                    if call[4] == "tools":
                        tools += 1
                elif len(call) > 0 and call[0] == "parallel_unittest":
                    oracle = call.copy()
                elif (
                    len(call) > 0
                    and call[0] == "tools/carla_lane_oracle/spiral_moments.py"
                ):
                    tail += 1
                    spiral += 1
                elif len(call) > 0 and call[0] == "repository-check":
                    tail += 1
                    repository += 1
            var expected_discovery = 0
            if index == 5:
                expected_discovery = 1
            var expected_tail = 0
            if index == 1:
                expected_tail = 2
            assert_equal(discovery, expected_discovery, shard)
            assert_equal(tail, expected_tail, shard)
            _equal(oracle, _oracle(shard))
        assert_equal(tools, 1, String(count))
        assert_equal(spiral, 1, String(count))
        assert_equal(repository, 1, String(count))


def test_auxiliary_failures_stop_the_owning_shard() raises:
    var python = _python()
    var cases = List[String]()
    cases.append("5/6|tools")
    cases.append("1/6|tools/carla_lane_oracle/spiral_moments.py")
    cases.append("1/6|repository-check")
    for entry in cases:
        var parts = entry.split("|")
        var shard = String(parts[0])
        var failed = String(parts[1])
        var result = _run(python, "test-tools", shard, failed)
        assert_true(result[0] != 0, entry)
        assert_true(_has(result[2][len(result[2]) - 1], failed), entry)


def test_oracle_failures_remain_fatal_on_every_shard() raises:
    var python = _python()
    for index in range(1, 7):
        var shard = String(index) + "/6"
        var result = _run(python, "test-tools", shard, "parallel_unittest")
        assert_true(result[0] != 0, shard)
        assert_equal(result[2][len(result[2]) - 1][0], "parallel_unittest")


def test_dedicated_discovery_runs_only_the_plain_discoveries() raises:
    var python = _python()
    for shard in ["", "1/6", "5/6"]:
        var result = _run(python, "test-tools-discovery", shard)
        assert_equal(result[0], 0, shard + "\n" + result[1])
        assert_equal(len(result[2]), 2, shard)
        _equal(result[2][0], _format())
        _equal(result[2][1], _discover_tools())


def test_discovery_and_oracle_shards_partition_every_command() raises:
    var python = _python()
    var discovery = _run(python, "test-tools-discovery")
    assert_equal(discovery[0], 0, discovery[1])
    var spiral = 0
    var repository = 0
    var oracle_runs = 0
    for index in range(1, 7):
        var shard = String(index) + "/6"
        var result = _run(python, "test-tools-oracle", shard)
        assert_equal(result[0], 0, shard + "\n" + result[1])
        _equal(result[2][0], _oracle(shard))
        oracle_runs += 1
        if index == 1:
            assert_equal(len(result[2]), 3)
            _equal(result[2][1], _spiral())
            _equal(result[2][2], _repository())
            spiral += 1
            repository += 1
        else:
            assert_equal(len(result[2]), 1, shard)
    assert_equal(oracle_runs, 6)
    assert_equal(spiral, 1)
    assert_equal(repository, 1)
    assert_equal(len(discovery[2]), 2)


def test_each_component_failure_stops_its_target() raises:
    var python = _python()
    var result = _run(python, "test-tools-discovery", "", "tools")
    assert_true(result[0] != 0)
    assert_true(_has(result[2][len(result[2]) - 1], "tools"))
    result = _run(
        python,
        "test-tools-oracle",
        "1/6",
        "tools/carla_lane_oracle/spiral_moments.py",
    )
    assert_true(result[0] != 0)
    assert_true(
        _has(
            result[2][len(result[2]) - 1],
            "tools/carla_lane_oracle/spiral_moments.py",
        )
    )
    result = _run(python, "test-tools-oracle", "1/6", "repository-check")
    assert_true(result[0] != 0)
    assert_true(_has(result[2][len(result[2]) - 1], "repository-check"))
    for index in range(1, 7):
        var shard = String(index) + "/6"
        result = _run(python, "test-tools-oracle", shard, "parallel_unittest")
        assert_true(result[0] != 0, shard)
        assert_equal(result[2][len(result[2]) - 1][0], "parallel_unittest")


def test_component_targets_are_phony_in_the_real_makefile() raises:
    var source = Path("Makefile").read_text()
    var start = source.find(".PHONY:")
    var rest = String(source[byte=start:])
    var end = rest.find("\n\n")
    var block = String(rest[byte=:end])
    for name in ["test-tools", "test-tools-discovery", "test-tools-oracle"]:
        assert_true(block.find(name) >= 0, name)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
