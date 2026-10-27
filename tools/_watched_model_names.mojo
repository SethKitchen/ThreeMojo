# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the watched model helpers and the removed search names.

The model names come first. The removed search names follow. A name is
not repeated.
"""

from tools._python_json import PyJson


def _append(mut doc: PyJson, names: Int, var words: List[String]):
    """Append every word to the name list.

    Args:
        doc: The document.
        names: The list node.
        words: The names to append.
    """
    for word in words:
        doc.append(names, doc.new_str(word))


def watched_model_names() raises -> String:
    """Return the watched names in historical order.

    Returns:
        A JSON list of model names, then removed search names.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var names = doc.new_list()
    var models = List[String]()
    models.append("curve_objective_model")
    models.append("_ObjectiveModel")
    models.append("_try_objective_model")
    models.append("_restrict_objective_model")
    models.append("_objective_followup_room")
    models.append("_objective_recheck_room")
    _append(doc, names, models^)
    var removed = List[String]()
    removed.append("cached_model")
    removed.append("reused_domain")
    removed.append("reused_delta")
    removed.append("reused_lower")
    removed.append("reused_tolerance")
    removed.append("reused_center_s")
    removed.append("reused_center_work")
    removed.append("reused_center")
    removed.append("ideal_center")
    removed.append("reused_support")
    removed.append("needs_model")
    removed.append("packed_model")
    _append(doc, names, removed^)
    doc.root = names
    return doc.dumps()
