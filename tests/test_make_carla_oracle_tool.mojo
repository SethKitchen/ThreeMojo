# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Keep the portable CARLA oracle checks in the official tool and CI gate.

Each test copies the `test-tools` recipe from the `Makefile` into a
temporary project. The recipe runs Python `unittest` discovery, so each
stage is a small Python test module that writes its name to an event file.
The workflow test reads `.github/workflows/ci.yml`.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._make_recipe import clean_command, section
from tools._process import ProcessResult, run_program

comptime STAGES = [
    ("tools", "tools"),
    ("assets", "assets/carla/tools"),
    ("nested", "tools/carla_lane_oracle"),
]
"""Each discovery stage and its directory."""


def _repr(text: String) -> String:
    """Return a Python string literal for a plain ASCII text."""
    return (
        "'"
        + text.replace("\\", "\\\\").replace("\n", "\\n").replace("'", "\\'")
        + "'"
    )


struct Project(Movable):
    """A temporary project with the real `test-tools` recipe."""

    var root: String
    var events: String

    def __init__(out self) raises:
        self.root = mkdtemp(prefix="carla oracle wiring ")
        self.events = self.root + "/events.txt"
        for stage in materialize[STAGES]():
            var folder = self.root + "/" + stage[1]
            _ = run_program(["mkdir", "-p", folder], 10)
            Path(folder + "/test_sentinel.py").write_text(
                "import os\nfrom pathlib import Path\nimport unittest\n"
                + "class Sentinel(unittest.TestCase):\n"
                + "    def test_selected(self):\n"
                + '        with Path(os.environ["ORACLE_WIRING_EVENTS"])'
                + '.open("a") as output:\n'
                + "            output.write("
                + _repr(stage[0] + "\n")
                + ")\n"
                + "       "
                ' self.assertNotEqual(os.environ.get("ORACLE_WIRING_FAIL"), '
                + _repr(stage[0])
                + ")\n"
            )
        # Match the real non-package directory: root discovery cannot find it.
        assert_false(
            Path(self.root + "/tools/carla_lane_oracle/__init__.py").exists()
        )
        Path(
            self.root + "/tools/carla_lane_oracle/spiral_moments.py"
        ).write_text(
            "import os, sys\nfrom pathlib import Path\n"
            + 'if sys.argv[1:] != ["--check"]:\n'
            + '    raise SystemExit("expected the read-only --check mode")\n'
            + 'with Path(os.environ["ORACLE_WIRING_EVENTS"]).open("a") as'
            " output:\n"
            + '    output.write("check\\n")\n'
            + 'if os.environ.get("ORACLE_WIRING_FAIL") == "check":\n'
            + "    raise SystemExit(7)\n"
        )
        var source = Path("Makefile").read_text()
        var recipe = section(
            source,
            "test-tools:\n",
            "\n# The negative-fixture manifest names exactly",
        )
        # The nested stage runs through the real parallel runner.
        var runner = "tools/parallel_unittest.py"
        Path(self.root + "/" + runner).write_bytes(Path(runner).read_bytes())
        Path(self.root + "/Makefile").write_text(
            ".PHONY: test-tools repository-check\nJOBS ?= 2\n"
            + recipe
            + "\nrepository-check:\n"
            + '\t@echo repository >> "$$ORACLE_WIRING_EVENTS"\n'
        )

    def make(
        self, fail: String = "", shard: String = ""
    ) raises -> Tuple[ProcessResult, List[String]]:
        Path(self.events).write_text("")
        var settings: List[String] = [
            "PYTHONDONTWRITEBYTECODE=1",
            "ORACLE_WIRING_EVENTS=" + self.events,
        ]
        var command: List[String] = ["env", "-u", "ORACLE_WIRING_FAIL"]
        if fail:
            command.append("ORACLE_WIRING_FAIL=" + fail)
        command.extend(["make", "-s", "test-tools"])
        if shard:
            command.append("TOOLS_SHARD=" + shard)
        var result = run_program(
            clean_command(settings, command),
            5,
            merge_errors=False,
            directory=self.root,
        )
        var events = List[String]()
        for line in Path(self.events).read_text().splitlines():
            events.append(String(line))
        return (result^, events^)

    def close(self) raises:
        _ = run_program(["rm", "-rf", self.root], 10)


def _words(var items: List[String]) -> String:
    return " ".join(items)


def test_official_target_runs_all_discoveries_and_read_only_check_once() raises:
    var project = Project()
    var run = project.make()
    assert_equal(run[0].status, 0, run[0].output + run[0].errors)
    assert_equal(_words(run[1].copy()), "tools assets nested check repository")
    project.close()


def test_each_discovery_failure_fails_target_before_later_stages() raises:
    var project = Project()
    var stages: List[String] = ["tools", "assets", "nested"]
    for index in range(len(stages)):
        var run = project.make(stages[index])
        assert_true(run[0].status != 0, run[0].output + run[0].errors)
        var expected = List[String]()
        for done in range(index + 1):
            expected.append(stages[done])
        assert_true(run[1] == expected, stages[index])
    project.close()


def test_read_only_checker_failure_fails_the_official_target() raises:
    var project = Project()
    var run = project.make("check")
    assert_true(run[0].status != 0, run[0].output + run[0].errors)
    assert_equal(_words(run[1].copy()), "tools assets nested check")
    project.close()


def _job(workflow: String, name: String) raises -> String:
    """Return a job's text up to the next two-space key, as the workflow
    test splits it."""
    var header = "\n  " + name + ":\n"
    var at = workflow.find(header)
    assert_true(at >= 0, name)
    var rest = String(workflow[byte = at + header.byte_length() :])
    var lines = rest.split("\n")
    var out = String()
    for index in range(len(lines)):
        var line = String(lines[index])
        if index > 0 and index < len(lines) - 1 and _is_key(line):
            # The split also takes the line end before the key.
            return String(out[byte = : out.byte_length() - 1])
        out += line
        if index < len(lines) - 1:
            out += "\n"
    return out


def _is_key(line: String) -> Bool:
    """Return whether a line is `  NAME:` with a lowercase first letter."""
    var bytes = line.as_bytes()
    if len(bytes) < 4 or not line.startswith("  "):
        return False
    if not (bytes[2] >= 97 and bytes[2] <= 122):
        return False
    for index in range(3, len(bytes) - 1):
        var byte = bytes[index]
        if not (
            (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 95
            or byte == 45
        ):
            return False
    return bytes[len(bytes) - 1] == 58


def test_linux_and_macos_ci_invoke_the_official_tool_target() raises:
    var workflow = Path(".github/workflows/ci.yml").read_text()
    for name in ["tools", "tools-macos"]:
        var job = _job(workflow, name)
        var commands = List[String]()
        for line in job.split("\n"):
            var text = String(line)
            var stripped = String(text.lstrip())
            if (
                stripped.byte_length() < text.byte_length()
                and stripped.startswith("run: ")
                and stripped.byte_length() > 5
            ):
                commands.append(String(stripped[byte=5:]))
        var start = job.find("shard: [")
        assert_true(start >= 0)
        var end = job.find("]", start)
        var count = len(String(job[byte = start + 8 : end]).split(","))
        var expected = (
            "sh tools/tool.sh .venv/bin/mojo ci_scope run -- test-tools "
            + "TOOLS_SHARD=${{ matrix.shard }}/"
            + String(count)
        )
        var found = False
        for command in commands:
            if command == expected:
                found = True
        assert_true(found, name)
        assert_true(
            job.find("if: needs.scope.outputs.run_tools == 'true'") >= 0
        )


def test_groups_together_run_every_stage_once() raises:
    var project = Project()
    var seen = List[String]()
    for index in [1, 2]:
        var run = project.make(shard=String(index) + "/2")
        assert_equal(run[0].status, 0, run[0].output + run[0].errors)
        if index > 1:
            for name in ["tools", "assets", "check", "repository"]:
                for event in run[1]:
                    assert_true(event != name, name)
        seen.extend(run[1].copy())
    sort(seen)
    assert_equal(_words(seen^), "assets check nested repository tools")
    project.close()


def test_job_split_stops_at_the_next_key() raises:
    assert_equal(_job("x\n  a:\n    one\n  b:\n    two\n", "a"), "    one")
    assert_false(_is_key("  B:"))
    assert_false(_is_key("  a b:"))
    assert_true(_is_key("  a-b_1:"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
