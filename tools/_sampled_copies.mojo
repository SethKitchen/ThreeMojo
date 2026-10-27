# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the sampled copies of the jet helpers.

The eight copied helpers stay in historical order. The rename map also
includes the helpers that are projected rather than copied whole.
"""

from tools._python_json import PyJson


def _bind(mut doc: PyJson, names: Int, old: String, new: String):
    """Record one helper rename.

    Args:
        doc: The document.
        names: The rename map.
        old: The jet helper name.
        new: The sampled helper name.
    """
    doc.set(names, old, doc.new_str(new))


def sampled_copies() raises -> String:
    """Return the copy order and the rename map.

    Returns:
        JSON with `copies` and `names`.

    Raises:
        Error: The map cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var copies = doc.new_list()
    var table = doc.new_dict()
    doc.append(copies, doc.new_str("_atan_branch"))
    doc.append(copies, doc.new_str("_atan_jet"))
    doc.append(copies, doc.new_str("_atan2_jet"))
    doc.append(copies, doc.new_str("_polynomial_jet"))
    doc.append(copies, doc.new_str("_unknown_point"))
    doc.append(copies, doc.new_str("_geometry_distance"))
    doc.append(copies, doc.new_str("_sample_blend_jet"))
    doc.append(copies, doc.new_str("_sample_jet"))
    _bind(doc, table, "_polynomial_jet", "_polynomial_value")
    _bind(doc, table, "_unknown_point", "_unknown_value_point")
    _bind(doc, table, "_geometry_distance", "_value_geometry_distance")
    _bind(doc, table, "_sample_blend_jet", "_sample_blend_value")
    _bind(doc, table, "_sample_jet", "_sample_value")
    _bind(doc, table, "_atan_branch", "_atan_value_branch")
    _bind(doc, table, "_atan_jet", "_atan_value")
    _bind(doc, table, "_atan2_jet", "_atan2_value")
    _bind(doc, table, "_jet_polynomial", "_expression_polynomial")
    _bind(doc, table, "_uncertain", "_uncertain_value")
    _bind(doc, table, "_Jet", "_ValueJet")
    _bind(doc, table, "_sinc_jet", "_sinc_value")
    _bind(doc, table, "_sincos_jet", "_sincos_expression")
    _bind(doc, table, "_arc_offset_jet", "_arc_offset_value")
    _bind(doc, table, "_constant_sincos_jet", "_constant_sincos_value")
    _bind(doc, table, "_union_points", "_union_value_points")
    doc.set(root, "copies", copies)
    doc.set(root, "names", table)
    doc.root = root
    return doc.dumps()
