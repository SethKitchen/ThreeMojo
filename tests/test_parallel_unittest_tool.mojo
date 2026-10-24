# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`tools/parallel_unittest.mojo` schedules unittest modules the way the
Python runner did.
"""

from std.os import getenv, setenv
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tools.parallel_unittest import (
    is_exclusive,
    modules,
    parse_shard,
    run,
    units,
)


def _write(directory: String, name: String, body: String) raises:
    """Write one Python file."""
    Path(directory + "/" + name).write_text(body)


def _passed(output: String) raises -> Int:
    """Return the total in `N of TOTAL units passed`.

    Args:
        output: The runner's standard output.

    Returns:
        The total unit count.

    Raises:
        Error: If the summary is missing.
    """
    var marker = " of "
    var at = output.find(marker)
    var rest = String(output[byte = at + marker.byte_length() :])
    var end = rest.find(" ")
    var digits = String(rest[byte=:end])
    return Int(digits)


def test_independent_tests_run_one_per_process() raises:
    var directory = mkdtemp(prefix="parallel tests ")
    _write(
        directory,
        "test_a.py",
        (
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_one(self):\n"
            "        self.assertTrue(True)\n"
            "    def test_two(self):\n"
            "        self.assertTrue(True)\n"
        ),
    )
    _write(directory, "helper.py", "import unittest\n")
    var names = modules(directory)
    assert_equal(len(names), 1)
    assert_equal(names[0], "test_a.py")
    var listed = units(directory, "test_a.py")
    assert_equal(len(listed), 2)
    assert_equal(listed[0].label, "test_a.T.test_one")
    assert_equal(listed[1].label, "test_a.T.test_two")
    var report = run(["--jobs", "2", directory])
    assert_equal(report.code, 0)
    assert_true(report.output.find("2 of 2 units passed (1 modules)") >= 0)
    assert_equal(report.errors, "")


def test_shared_set_up_groups_one_class() raises:
    var directory = mkdtemp(prefix="parallel shared ")
    _write(
        directory,
        "test_m.py",
        (
            "import unittest\n"
            "STATE = []\n"
            "def setUpModule():\n"
            "    STATE.append(1)\n"
            "class T(unittest.TestCase):\n"
            "    def test_shared(self):\n"
            "        self.assertEqual(STATE, [1])\n"
        ),
    )
    _write(
        directory,
        "test_c.py",
        (
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    @classmethod\n"
            "    def setUpClass(cls):\n"
            "        cls.value = 3\n"
            "    def test_shared(self):\n"
            "        self.assertEqual(self.value, 3)\n"
        ),
    )
    var module_units = units(directory, "test_m.py")
    var class_units = units(directory, "test_c.py")
    assert_equal(len(module_units), 1)
    assert_equal(len(class_units), 1)
    assert_false(module_units[0].command[3] == "discover")
    var body = String(
        "import unittest\n"
        "class A(unittest.TestCase):\n"
        "    @classmethod\n"
        "    def setUpClass(cls):\n"
        "        cls.value = 1\n"
    )
    var index = 0
    while index < 5:
        body += (
            "    def test_"
            + String(index)
            + "(self):\n"
            + "        self.assertEqual(self.value, 1)\n"
        )
        index += 1
    body += (
        "class B(unittest.TestCase):\n"
        "    @classmethod\n"
        "    def tearDownClass(cls):\n"
        "        pass\n"
        "    def test_0(self):\n"
        "        pass\n"
        "class C(unittest.TestCase):\n"
        "    def test_0(self):\n"
        "        pass\n"
    )
    _write(directory, "test_k.py", body)
    var chunked = units(directory, "test_k.py")
    assert_equal(len(chunked), 4)
    assert_equal(chunked[0].label, "test_k.A.test_0 (+3)")
    assert_equal(chunked[1].label, "test_k.A.test_4")
    assert_equal(chunked[2].label, "test_k.B.test_0")
    assert_equal(chunked[3].label, "test_k.C.test_0")
    var report = run([directory])
    assert_equal(report.code, 0, report.output)
    assert_true(report.output.find("6 of 6 units passed (3 modules)") >= 0)


def test_shards_partition_the_units_and_reject_bad_text() raises:
    var one = parse_shard("1/1")
    assert_equal(one[0], 1)
    assert_equal(one[1], 1)
    var wide = parse_shard("10/12")
    assert_equal(wide[0], 10)
    assert_equal(wide[1], 12)
    var directory = mkdtemp(prefix="parallel shard ")
    _write(
        directory,
        "test_a.py",
        (
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_one(self):\n"
            "        self.assertTrue(True)\n"
            "    def test_two(self):\n"
            "        self.assertTrue(True)\n"
        ),
    )
    _write(
        directory,
        "test_b.py",
        (
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_bad(self):\n"
            "        self.assertEqual(1, 2)\n"
        ),
    )
    var total = 0
    var codes = List[Int]()
    var index = 1
    while index <= 3:
        var report = run(["--shard", String(index) + "/3", directory])
        codes.append(report.code)
        total += _passed(report.output)
        index += 1
    assert_equal(total, 3)
    var failures = 0
    for code in codes:
        if code != 0:
            failures += 1
    assert_equal(failures, 1)
    for bad in ["0/3", "4/3", "1", "a/b", "01/6", "1/06", "+1/6"]:
        var report = run(["--shard", bad, directory])
        assert_equal(report.code, 2, bad)


def test_import_error_and_failure_are_reported() raises:
    var directory = mkdtemp(prefix="parallel fail ")
    _write(directory, "test_x.py", "import missing_module_for_this_test\n")
    var listed = units(directory, "test_x.py")
    assert_equal(listed[0].command[3], "discover")
    var broken = run([directory])
    assert_equal(broken.code, 1)
    assert_true(broken.output.find("missing_module_for_this_test") >= 0)
    assert_true(broken.errors.find("failed: test_x.py") >= 0)
    directory = mkdtemp(prefix="parallel fail ")
    _write(
        directory,
        "test_a.py",
        (
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_one(self):\n"
            "        self.assertTrue(True)\n"
            "    def test_two(self):\n"
            "        self.assertTrue(True)\n"
        ),
    )
    _write(
        directory,
        "test_b.py",
        (
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_bad(self):\n"
            "        self.assertEqual(1, 2)\n"
        ),
    )
    var failed = run(["--jobs", "1", directory])
    assert_equal(failed.code, 1)
    assert_true(failed.output.find("2 of 3 units passed") >= 0)
    assert_true(failed.output.find("AssertionError") >= 0)
    assert_true(failed.errors.find("failed: test_b.T.test_bad") >= 0)


def test_empty_directory_and_jobs_are_refused() raises:
    var directory = mkdtemp(prefix="parallel empty ")
    var report = run([directory])
    assert_equal(report.code, 1)
    assert_true(report.errors.find("no test modules") >= 0)
    var jobs = run(["--jobs", "0", directory])
    assert_equal(jobs.code, 2)


def test_unreadable_listing_falls_back_to_discovery() raises:
    var directory = mkdtemp(prefix="parallel list ")
    _write(
        directory,
        "test_a.py",
        (
            "import unittest\nclass T(unittest.TestCase):\n"
            "    def test_one(self):\n        pass\n"
        ),
    )
    var listed = units(directory, "test_a.py", "true")
    assert_equal(len(listed), 1)
    assert_equal(listed[0].label, "test_a.py")
    assert_equal(listed[0].command[3], "discover")


def test_exclusive_commands_match_the_pinned_proofs() raises:
    var target = (
        "test_coverage_invariant_contracts.CoverageInvariantContracts."
        "test_historical_direct_and_qualified_package_verification"
    )
    var hit = List[String]()
    hit.append("python3")
    hit.append("-m")
    hit.append("unittest")
    hit.append("test_other.T.test_a")
    hit.append(target)
    assert_true(is_exclusive(hit))
    var discover = List[String]()
    discover.append("python3")
    discover.append("-m")
    discover.append("unittest")
    discover.append("discover")
    discover.append("-s")
    discover.append("/tmp/tests")
    discover.append("-p")
    discover.append("test_coverage_invariant_contracts.py")
    assert_true(is_exclusive(discover))
    var other = List[String]()
    other.append("python3")
    other.append("-m")
    other.append("unittest")
    other.append(target + "_other")
    assert_false(is_exclusive(other))


def test_ordinary_units_overlap() raises:
    var directory = mkdtemp(prefix="parallel overlap ")
    var mark = directory + "/marks"
    _ = getenv("PATH", "")
    _ = setenv("PARALLEL_MARK", mark, True)
    var body = (
        "import os, time, unittest\n"
        "class T(unittest.TestCase):\n"
        "    def test_wait(self):\n"
        "        name = os.environ['PARALLEL_MARK']\n"
        "        os.makedirs(name, exist_ok=True)\n"
        "        open(name + '/' + os.path.basename(__file__), 'w').close()\n"
        "        for _ in range(200):\n"
        "            names = os.listdir(name)\n"
        "            if len(names) >= 2:\n"
        "                return\n"
        "            time.sleep(0.01)\n"
        "        self.fail('the other unit did not start')\n"
    )
    _write(directory, "test_a.py", body)
    _write(directory, "test_b.py", body)
    var report = run(["--jobs", "2", directory])
    assert_equal(report.code, 0, report.output + report.errors)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
