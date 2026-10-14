# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The LWO generator writes the saved LightWave files byte for byte."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from assets.lwo.make_lwo import files, write_all


def test_the_generator_writes_the_saved_files() raises:
    var root = mkdtemp()
    write_all(root)
    var entries = files()
    assert_equal(len(entries), 38)
    for entry in entries:
        var written = Path(root + "/" + entry[0]).read_bytes()
        var saved = Path("assets/lwo/" + entry[0]).read_bytes()
        assert_true(written == saved, entry[0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
