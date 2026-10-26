# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the Sum2 protected-helper inventory.

The live production files that use a protected helper match the pin. Eight
live files keep the pinned use digest.
"""

from std.os import listdir
from std.os.path import isdir, islink
from std.pathlib import Path

from tests._python_tokens import _tokenize
from tools._python_json import PY_DICT, PY_STR, PyJson
from tools._sha256 import sha256_hex
from tools._sum2_guard_callers import _esc, _routing


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _NAME = 1


def _fail(message: String) raises:
    """Raise a Sum2 inventory error.

    Args:
        message: The failure text.

    Raises:
        Error: The protected-helper inventory changed.
    """
    raise Error(message)


def _skipped_top(name: String) -> Bool:
    """Return whether a top-level name is outside production.

    Args:
        name: The directory or file name.

    Returns:
        True for a non-production tree.
    """
    if name == "tests" or name == "examples" or name == "bench":
        return True
    if name == "tools" or name == "docs" or name == "assets":
        return True
    if name == "out" or name == "coverage" or name == "cache":
        return True
    return name == "build" or name == "node_modules"


def _collect(root: String, relative: String, mut paths: List[String]) raises:
    """Append production `.mojo` paths.

    Args:
        root: The repository root.
        relative: The directory to read, relative to `root`.
        paths: The collected paths, appended by this call.

    Raises:
        Error: A directory cannot be read.
    """
    var full = root if relative == "" else root + "/" + relative
    var names = listdir(full)
    for name in names:
        if name.startswith("."):
            continue
        if relative == "" and _skipped_top(name):
            continue
        var child = full + "/" + name
        var path = name if relative == "" else relative + "/" + name
        if isdir(child):
            if not islink(child):
                _collect(root, path, paths)
        elif name.endswith(".mojo"):
            paths.append(path)


def _protected(name: String) -> Bool:
    """Return whether `name` is a protected helper or module.

    Args:
        name: One identifier.

    Returns:
        True for a reviewed protected name.
    """
    if name == "_seed_exact_interval" or name == "_seed_reference_domain":
        return True
    if name == "_winner_seed_room" or name == "_try_winner_seed":
        return True
    if name == "_sum2_update" or name == "_require_sum2_environment":
        return True
    if name == "_sum2_supported_environment" or name == "_sum2_error":
        return True
    if name == "_sum2_error_checked" or name == "_spiral_proof_branch":
        return True
    if (
        name == "_grouped_origin_error"
        or name == "_try_spiral_grouped_roundoff_envelope"
    ):
        return True
    if name == "_try_objective_model" or name == "_restrict_objective_model":
        return True
    if name == "_objective_followup_room" or name == "_objective_recheck_room":
        return True
    if name == "_minimizer_support" or name == "_sample_dispatch_predicate":
        return True
    if name == "_sample_dispatch_cut" or name == "_try_sample_dispatch_cuts":
        return True
    if name == "_try_grouped_lane_jet" or name == "curve_sum2":
        return True
    if name == "spiral_domain_proof" or name == "curve_bounds":
        return True
    if name == "curve_objective_model" or name == "curve_minimizer_support":
        return True
    if name == "curve_sample_dispatch" or name == "spiral_grouped_lane":
        return True
    return name == "spiral_grouped_roundoff_proof"


def _mentioned(text: String) -> Bool:
    """Return whether `text` can contain a protected name.

    Args:
        text: One module.

    Returns:
        True when a protected spelling occurs anywhere in the text.
    """
    if text.find("_sum2_") >= 0 or text.find("_minimizer_support") >= 0:
        return True
    if (
        text.find("_try_objective_model") >= 0
        or text.find("_restrict_objective_model") >= 0
    ):
        return True
    if (
        text.find("_objective_followup_room") >= 0
        or text.find("_objective_recheck_room") >= 0
    ):
        return True
    if (
        text.find("_sample_dispatch_") >= 0
        or text.find("_try_grouped_lane_jet") >= 0
    ):
        return True
    if (
        text.find("_grouped_origin_error") >= 0
        or text.find("_spiral_proof_branch") >= 0
    ):
        return True
    if text.find("_try_spiral_grouped_roundoff_envelope") >= 0:
        return True
    if (
        text.find("_seed_exact_interval") >= 0
        or text.find("_seed_reference_domain") >= 0
    ):
        return True
    if (
        text.find("_winner_seed_room") >= 0
        or text.find("_try_winner_seed") >= 0
    ):
        return True
    if text.find("curve_sum2") >= 0 or text.find("spiral_domain_proof") >= 0:
        return True
    if (
        text.find("curve_bounds") >= 0
        or text.find("curve_objective_model") >= 0
    ):
        return True
    if (
        text.find("curve_minimizer_support") >= 0
        or text.find("curve_sample_dispatch") >= 0
    ):
        return True
    if text.find("spiral_grouped_lane") >= 0:
        return True
    return text.find("spiral_grouped_roundoff_proof") >= 0


def _uses(source: String) raises -> String:
    """Return the protected-name uses, or empty when there are none.

    Args:
        source: One module.

    Returns:
        A JSON list of identifier index and name, or empty.

    Raises:
        Error: The module cannot be tokenized.
    """
    if not _mentioned(source):
        return ""
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var uses = String("[")
    var count = 0
    var ident = 0
    var index = 0
    while index < len(kinds):
        if kinds[index] == _NAME:
            var token = texts[index]
            if _protected(token):
                if count > 0:
                    uses += ","
                uses += "[" + String(ident) + "," + _esc(token) + "]"
                count += 1
            ident += 1
        index += 1
    if count == 0:
        return ""
    uses += "]"
    return uses


def _digest(source: String) raises -> String:
    """Return the protected-use digest, or empty when there is no use.

    Args:
        source: One module.

    Returns:
        The SHA-256 hex digest, or empty.

    Raises:
        Error: The module cannot be tokenized.
    """
    var uses = _uses(source)
    if uses == "":
        return ""
    var record = (
        '{"routing":'
        + _esc(_routing(source))
        + ',"protected_names":'
        + uses
        + "}"
    )
    return sha256_hex(record.as_bytes())


def _live_digest(path: String) -> Bool:
    """Return whether `path` keeps the pinned use digest.

    Args:
        path: A production module path.

    Returns:
        True for a live file whose digest matches the pin.
    """
    if path == "extensions/carla/curve_frozen_arc.mojo":
        return True
    if path == "extensions/carla/curve_minimizer_support.mojo":
        return True
    if path == "extensions/carla/curve_objective_model.mojo":
        return True
    if path == "extensions/carla/curve_sum2.mojo":
        return True
    if path == "extensions/carla/spiral_grouped_roundoff_proof.mojo":
        return True
    if path == "extensions/carla/spiral_moment_proof.mojo":
        return True
    if path == "extensions/carla/spiral_moment_table.mojo":
        return True
    return path == "extensions/carla/spiral_roundoff_proof.mojo"


def _has(names: List[String], name: String) -> Bool:
    """Return whether `name` is present.

    Args:
        names: The names.
        name: The name to find.

    Returns:
        True when the name is present.
    """
    var index = 0
    while index < len(names):
        if names[index] == name:
            return True
        index += 1
    return False


def _keys(doc: PyJson, node: Int) -> List[String]:
    """Return the keys of one dict.

    Args:
        doc: The pin document.
        node: The dict node.

    Returns:
        The keys, in document order.
    """
    var keys = List[String]()
    var index = 0
    while index < doc.length(node):
        keys.append(doc.key(node, index))
        index += 1
    return keys^


def sum2_guard_inventory(root: String) raises:
    """Require the reviewed protected-helper inventory.

    Args:
        root: The repository root.

    Raises:
        Error: The file set or a live use digest changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var inventory = doc.at(doc.root, "protected_inventory")
    if doc.kind(inventory) != PY_DICT:
        _fail("global protected-helper use/import inventory changed")
    var pinned = _keys(doc, inventory)
    var paths = List[String]()
    _collect(base, "", paths)
    var live = List[String]()
    var index = 0
    while index < len(paths):
        var path = paths[index]
        var text = Path(base + "/" + path).read_text()
        if _uses(text) != "":
            live.append(path)
        index += 1
    if len(live) != len(pinned):
        _fail("global protected-helper use/import inventory changed")
    index = 0
    while index < len(pinned):
        if not _has(live, pinned[index]):
            _fail("global protected-helper use/import inventory changed")
        index += 1
    index = 0
    while index < len(live):
        var path = live[index]
        if _live_digest(path):
            var node = doc.at(inventory, path)
            var digest = _digest(Path(base + "/" + path).read_text())
            if (
                doc.kind(node) != PY_STR
                or digest == ""
                or digest != doc.text(node)
            ):
                _fail("global protected-helper use/import inventory changed")
        index += 1
