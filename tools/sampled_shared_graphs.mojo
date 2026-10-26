# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live shared bridge graphs.

Eight trig helpers keep their reviewed function graphs. Six curve-bounds
helpers keep the graphs from the reviewed reference source. A changed
bridge is refused.
"""

from std.pathlib import Path

from tests._winner_pin_predecessor import restored_count_bounds
from tools._python_json import PY_STR, loads
from tools._sha256 import sha256_hex
from tools.sampled_bounds_graph import reviewed_bounds_source
from tools.sampled_module_graphs import function_graph


comptime _TRIG = "extensions/carla/curve_trig.mojo"
comptime _RECORD = "tools/carla_lane_oracle/envelope-budget-contract.json"
comptime _RECORD_SHA = (
    "c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be"
)


def _fail(message: String) raises:
    """Raise a shared-bridge error.

    Args:
        message: The failure text.

    Raises:
        Error: The bridge check failed.
    """
    raise Error(message)


def _check(
    source: String, filename: String, name: String, expected: String
) raises:
    """Require one function to keep its reviewed graph.

    Args:
        source: The module source.
        filename: The file name used in a failure.
        name: The function name.
        expected: The reviewed function digest.

    Raises:
        Error: The function graph changed.
    """
    if function_graph(source, name) != expected:
        _fail(
            "shared generic or full-Jet bridge changed: "
            + filename
            + ":"
            + name
        )


def shared_bridges(trig: String, bounds: String) raises:
    """Require the reviewed shared bridge graphs.

    Args:
        trig: The trig module.
        bounds: The reviewed curve-bounds module.

    Raises:
        Error: A shared function graph changed.
    """
    _check(
        trig,
        "curve_trig.mojo",
        "_expression_polynomial",
        "031856283e36ac8dbaef6e455eb6a1502c0c465f70ba809ace51ec5782abb04a",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_jet_polynomial",
        "9a773f471ac8ac236f808d0f072ac5372315a3dd2683b16c41899a1b56cfd470",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_sincos_expression",
        "89921637fc52fad38092e2c283d238287b3f33035dcc0a33a2b07fddc6042509",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_sincos_branch_expression",
        "8ba6cc52dff85cbca95fa9c58142de28140c97d711911bd1f437b11ca2bc857f",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_sincos_branch",
        "a99d1be1594ceeea7edf3709312217af35035b590dd621c57c3e6bdf97a26a8a",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_sincos_jet",
        "f76f149a0ee85c2e5e3b1dc6b1d8a9cd68a053582fbe4c9d8e562b1848c91b3f",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_uncertain_expression",
        "c883bc5e3e7046309b145f178f73848cecc20013551852a80f993f793c1ff00f",
    )
    _check(
        trig,
        "curve_trig.mojo",
        "_uncertain",
        "e32b28fd29a051ebb13cb14f22cc61a12f137124cc9b9938adf113e606baa21e",
    )
    _check(
        bounds,
        "curve_bounds.mojo",
        "_sample_index",
        "91a5c643d73e15e2b5d3838fff658dc2986e0b28852a0c66ceacdd84e71ca01e",
    )
    _check(
        bounds,
        "curve_bounds.mojo",
        "_intersect_ideal_bounds",
        "0f6d271eb25f2e19f9cfd4c4f8f93691f4452cb50ac5303d7ff898398f8deda3",
    )
    _check(
        bounds,
        "curve_bounds.mojo",
        "_lane_jet",
        "c1d76e057272bbb71d1066e4669a3b7d0e5e87c4497e9d96abf21edc007e2f85",
    )
    _check(
        bounds,
        "curve_bounds.mojo",
        "_lane_jet_model",
        "470c29ee518a71ecc8c6bce3268d38da93d8c27770b9bdf6e6c82989a1032ab0",
    )
    _check(
        bounds,
        "curve_bounds.mojo",
        "_lane_jet_model_proof",
        "17eea195f5bcd6e90781bbc3370f16e5404b67620aad1807b24101ceaebd7218",
    )
    _check(
        bounds,
        "curve_bounds.mojo",
        "_reference_jet_capture",
        "0ebd93d524b35c30cdd27fabc23dd40f1a53241477b0689c37b07b18bce5ad05",
    )


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _reviewed(root: String) raises -> String:
    """Return the reviewed curve-bounds source.

    Args:
        root: The repository root.

    Returns:
        The reviewed module.

    Raises:
        Error: The envelope record changed.
    """
    var path = _root(root) + "/" + _RECORD
    var raw = Path(path).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA:
        _fail("Unreviewed envelope budget predecessor record")
    var doc = loads(raw)
    var before_node = doc.at(doc.root, "before_complete_function")
    var after_node = doc.at(doc.root, "after_complete_function")
    if doc.kind(before_node) != PY_STR or doc.kind(after_node) != PY_STR:
        _fail("Unreviewed envelope budget predecessor record")
    return reviewed_bounds_source(
        restored_count_bounds(),
        doc.text(before_node),
        doc.text(after_node),
    )


def sampled_shared_graphs(root: String) raises:
    """Require the live shared bridge graphs.

    Args:
        root: The repository root. The live trig module is read from that
            root. The curve-bounds restoration reads the process directory.

    Raises:
        Error: A shared function graph changed.
    """
    var base = _root(root)
    var trig = Path(base + "/" + _TRIG).read_text()
    shared_bridges(trig, _reviewed(root))
