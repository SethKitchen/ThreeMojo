# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The LDraw generator writes the saved kitchen files byte for byte."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal

from tools.make_ldraw_kitchen import files, write_all


def test_the_generator_writes_the_saved_files() raises:
    var root = mkdtemp()
    write_all(root)
    var entries = files()
    assert_equal(len(entries), 13)
    for entry in entries:
        assert_equal(
            Path(root + "/" + entry[0]).read_text(),
            Path("assets/ldraw/" + entry[0]).read_text(),
            entry[0],
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
