# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find one unique line in the native loop source.

The source text stays in the driver record. This lookup only reports where
one fragment occurs.
"""

from tools._coverage_loop_drivers import coverage_loop_drivers
from tools._coverage_loop_labels import coverage_loop_labels
from tools._python_json import PyJson
from tools._text import split_lines


def unique_source_line(fragment: String) raises -> Int:
    """Return the one line that contains `fragment`.

    Args:
        fragment: The text that must occur on exactly one source line.

    Returns:
        The line number, starting at 1.

    Raises:
        Error: The fragment is missing or occurs on more than one line.
    """
    var labels = PyJson.parse(coverage_loop_labels())
    var admission = labels.at(labels.root, "admission")
    var prefix = labels.text(labels.at(admission, "fixture_identity"))
    var drivers = PyJson.parse(coverage_loop_drivers())
    var source = drivers.text(drivers.at(drivers.root, "source"))
    var matches = 0
    var found = 0
    var number = 0
    for line in split_lines(source):
        number += 1
        if line.find(fragment) >= 0:
            matches += 1
            found = number
    if matches != 1:
        raise Error(prefix + fragment)
    return found
