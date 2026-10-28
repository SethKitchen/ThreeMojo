# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Keep the sampled reference, primitive, and shared graph digests.

The digests are the reviewed pins. The Python checker still hashes the
graphs and compares those hashes with these pins.
"""

from tools._json_tools import quote_ascii
from tools._moment_guards import require_name_set
from tools._python_json import PY_DICT, PyJson
from tools._sampled_closure import sampled_closure


def _dump(doc: PyJson, node: Int) -> String:
    """Return JSON in stored key order, with no spaces.

    Args:
        doc: The document.
        node: A string or an object of strings.

    Returns:
        The text `json.dumps` writes with `separators=(',', ':')`.
    """
    if doc.kind(node) == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        var index = 0
        while index < count:
            if index > 0:
                out += ","
            out += quote_ascii(doc.key(node, index))
            out += ":"
            out += _dump(doc, doc.value(node, index))
            index += 1
        out += "}"
        return out
    return quote_ascii(doc.text(node))


def _pin(mut doc: PyJson, node: Int, key: String, digest: String):
    """Add one digest.

    Args:
        doc: The document.
        node: The object that stores the digest.
        key: The module or helper name.
        digest: The reviewed SHA-256 text.
    """
    doc.set(node, key, doc.new_str(digest))


def sampled_graph_pins() -> String:
    """Return the reviewed graph digests in historical order.

    Returns:
        JSON with `reference`, `primitive`, and `shared`.
    """
    var doc = PyJson()
    var spec = doc.new_dict()
    var reference = doc.new_dict()
    _pin(
        doc,
        reference,
        "curve_bounds.mojo",
        "51f99d745612d217762d8f39bde1ded5b269d239f05cb765532de631cc64791f",
    )
    _pin(
        doc,
        reference,
        "curve_trig.mojo",
        "4ca47db55caa96ba9ad6c6f43fa65d30a8fefe419f555d46a1a948a2fc606ecc",
    )
    _pin(
        doc,
        reference,
        "curve_interval.mojo",
        "32b7bce9ad0b996fa87a7bc63ff0c905065751d164f7d673342234716523fd8e",
    )
    doc.set(spec, "reference", reference)
    doc.set(
        spec,
        "primitive",
        doc.new_str(
            "e2e0257a0f42a95bac586638fc5d532f4bc69b882127201bbf343006f2143484"
        ),
    )
    var shared = doc.new_dict()
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_expression_polynomial",
        "031856283e36ac8dbaef6e455eb6a1502c0c465f70ba809ace51ec5782abb04a",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_jet_polynomial",
        "9a773f471ac8ac236f808d0f072ac5372315a3dd2683b16c41899a1b56cfd470",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_sincos_expression",
        "89921637fc52fad38092e2c283d238287b3f33035dcc0a33a2b07fddc6042509",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_sincos_branch_expression",
        "8ba6cc52dff85cbca95fa9c58142de28140c97d711911bd1f437b11ca2bc857f",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_sincos_branch",
        "a99d1be1594ceeea7edf3709312217af35035b590dd621c57c3e6bdf97a26a8a",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_sincos_jet",
        "f76f149a0ee85c2e5e3b1dc6b1d8a9cd68a053582fbe4c9d8e562b1848c91b3f",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_uncertain_expression",
        "c883bc5e3e7046309b145f178f73848cecc20013551852a80f993f793c1ff00f",
    )
    _pin(
        doc,
        shared,
        "curve_trig.mojo:_uncertain",
        "e32b28fd29a051ebb13cb14f22cc61a12f137124cc9b9938adf113e606baa21e",
    )
    _pin(
        doc,
        shared,
        "curve_bounds.mojo:_sample_index",
        "91a5c643d73e15e2b5d3838fff658dc2986e0b28852a0c66ceacdd84e71ca01e",
    )
    _pin(
        doc,
        shared,
        "curve_bounds.mojo:_intersect_ideal_bounds",
        "0f6d271eb25f2e19f9cfd4c4f8f93691f4452cb50ac5303d7ff898398f8deda3",
    )
    _pin(
        doc,
        shared,
        "curve_bounds.mojo:_lane_jet",
        "c1d76e057272bbb71d1066e4669a3b7d0e5e87c4497e9d96abf21edc007e2f85",
    )
    _pin(
        doc,
        shared,
        "curve_bounds.mojo:_lane_jet_model",
        "470c29ee518a71ecc8c6bce3268d38da93d8c27770b9bdf6e6c82989a1032ab0",
    )
    _pin(
        doc,
        shared,
        "curve_bounds.mojo:_lane_jet_model_proof",
        "17eea195f5bcd6e90781bbc3370f16e5404b67620aad1807b24101ceaebd7218",
    )
    _pin(
        doc,
        shared,
        "curve_bounds.mojo:_reference_jet_capture",
        "0ebd93d524b35c30cdd27fabc23dd40f1a53241477b0689c37b07b18bce5ad05",
    )
    doc.set(spec, "shared", shared)
    doc.root = spec
    return _dump(doc, doc.root)


def sampled_graphs_and_names() raises -> String:
    """Read the graph digests, then check the reference names.

    Returns:
        JSON with `graphs` and `closure`. `graphs` is the digest table.
        `closure` is the reference-name record.

    Raises:
        Error: The reference names differ from the digest keys. The
            digests are read before the names are checked.
    """
    var graphs = sampled_graph_pins()
    var closure = sampled_closure()
    var graphs_doc = PyJson.parse(graphs)
    var closure_doc = PyJson.parse(closure)
    var reference = graphs_doc.at(graphs_doc.root, "reference")
    var names_doc = PyJson()
    var root = names_doc.new_dict()
    var found = names_doc.new_list()
    var count = graphs_doc.length(reference)
    var index = 0
    while index < count:
        names_doc.append(
            found, names_doc.new_str(graphs_doc.key(reference, index))
        )
        index += 1
    names_doc.set(root, "names", found)
    var expected = names_doc.new_list()
    var wanted = closure_doc.at(closure_doc.root, "reference_names")
    var name_count = closure_doc.length(wanted)
    index = 0
    while index < name_count:
        names_doc.append(
            expected,
            names_doc.new_str(
                closure_doc.text(closure_doc.item(wanted, index))
            ),
        )
        index += 1
    names_doc.set(root, "expected", expected)
    names_doc.set(
        root,
        "message",
        names_doc.new_str(
            closure_doc.text(closure_doc.at(closure_doc.root, "closure"))
        ),
    )
    names_doc.root = root
    require_name_set(names_doc.dumps())
    return '{"graphs":' + graphs + ',"closure":' + closure + "}"
