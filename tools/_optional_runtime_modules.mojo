# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the optional-runtime modules that the result records.

The names stay in the order the migration checked them.
"""

from tools._python_json import PyJson


def _append(mut doc: PyJson, names: Int, var words: List[String]):
    """Append every module name.

    Args:
        doc: The document.
        names: The list node.
        words: The module names.
    """
    for word in words:
        doc.append(names, doc.new_str(word))


def optional_runtime_modules() raises -> String:
    """Return the five optional-runtime module names.

    Returns:
        A JSON list in reviewed order.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var names = doc.new_list()
    var words = List[String]()
    words.append("curve_minimizer_support")
    words.append("curve_objective_model")
    words.append("curve_sample_dispatch")
    words.append("spiral_grouped_lane")
    words.append("spiral_grouped_roundoff_proof")
    _append(doc, names, words^)
    doc.root = names
    return doc.dumps()
