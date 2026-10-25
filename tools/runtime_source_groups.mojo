# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the runtime source group token pins.

Six groups keep their reviewed token digests. A live file is used when its
digest already matches. The other files use their reviewed restorations.
"""

from tests._python_tokens import token_sha256
from tools._python_json import PY_DICT, PY_INT, PY_STR, PyJson


def _fail(message: String) raises:
    """Raise a runtime-group error.

    Args:
        message: The failure text.

    Raises:
        Error: The group check failed.
    """
    raise Error(message)


def _has(keys: List[String], name: String) -> Bool:
    """Return whether `keys` contains `name`.

    Args:
        keys: The collected keys.
        name: The key to find.

    Returns:
        True when `name` is present.
    """
    var index = 0
    while index < len(keys):
        if keys[index] == name:
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
    var count = doc.length(node)
    while index < count:
        keys.append(doc.key(node, index))
        index += 1
    return keys^


def _same(actual: List[String], expected: List[String]) -> Bool:
    """Return whether the two key lists hold the same set.

    Args:
        actual: The document keys.
        expected: The reviewed keys.

    Returns:
        True when the sets are equal.
    """
    if len(actual) != len(expected):
        return False
    var index = 0
    while index < len(expected):
        if not _has(actual, expected[index]):
            return False
        index += 1
    return True


def _hex_text(text: String) -> Bool:
    """Return whether `text` is 64 lowercase hex digits.

    Args:
        text: The pin text.

    Returns:
        True for a SHA-256 hex digest.
    """
    if text.byte_length() != 64:
        return False
    for byte in text.as_bytes():
        if not (
            (byte >= 0x30 and byte <= 0x39) or (byte >= 0x61 and byte <= 0x66)
        ):
            return False
    return True


def _module(name: String) -> String:
    """Return one CARLA module path.

    Args:
        name: The module stem.

    Returns:
        The repository path.
    """
    return "extensions/carla/" + name + ".mojo"


def _canonical() -> List[String]:
    """Return the canonical accumulation paths.

    Returns:
        The paths, in review order.
    """
    var paths = List[String]()
    paths.append(_module("curve_sum2"))
    paths.append(_module("lane_geometry"))
    paths.append(_module("curve_interval"))
    paths.append(_module("curve_bounds"))
    paths.append(_module("spiral_roundoff_proof"))
    paths.append(_module("lane_refinement"))
    paths.append(_module("map"))
    paths.append(_module("map_builder"))
    paths.append(_module("spiral_domain_proof"))
    paths.append(_module("spiral_moment_proof"))
    paths.append(_module("spiral_moment_table"))
    return paths^


def _optional() -> List[String]:
    """Return the optional runtime paths.

    Returns:
        The paths, in review order.
    """
    var paths = List[String]()
    paths.append(_module("curve_minimizer_support"))
    paths.append(_module("curve_objective_model"))
    paths.append(_module("curve_sample_dispatch"))
    paths.append(_module("spiral_grouped_lane"))
    paths.append(_module("spiral_grouped_roundoff_proof"))
    paths.append(_module("curve_bounds"))
    paths.append(_module("lane_refinement"))
    paths.append(_module("map"))
    paths.append(_module("lane_value_bounds"))
    paths.append(_module("curve_interval"))
    paths.append(_module("curve_sum2"))
    paths.append(_module("curve_trig"))
    paths.append(_module("lane_geometry"))
    paths.append(_module("geometry"))
    paths.append(_module("road_info"))
    paths.append(_module("polynomial"))
    paths.append(_module("spiral_domain_proof"))
    paths.append(_module("spiral_moment_proof"))
    paths.append(_module("spiral_moment_table"))
    paths.append(_module("spiral_roundoff_proof"))
    paths.append(_module("curve_frozen_arc"))
    return paths^


def _stored() -> List[String]:
    """Return the stored arithmetic paths.

    Returns:
        The one interval path.
    """
    var paths = List[String]()
    paths.append(_module("curve_interval"))
    return paths^


def _eligibility() -> List[String]:
    """Return the eligibility paths.

    Returns:
        The paths, in review order.
    """
    var paths = List[String]()
    paths.append(_module("spiral_domain_proof"))
    paths.append(_module("spiral_moment_proof"))
    paths.append(_module("spiral_moment_table"))
    paths.append(_module("spiral_roundoff_proof"))
    paths.append(_module("curve_rounded_arc"))
    paths.append(_module("curve_rounded_line"))
    paths.append(_module("curve_frozen_arc"))
    paths.append(_module("geometry"))
    paths.append(_module("road_info"))
    paths.append(_module("polynomial"))
    paths.append(_module("curve_trig"))
    paths.append(_module("spiral_moment_table_data"))
    return paths^


def _translation() -> List[String]:
    """Return the translation paths.

    Returns:
        The paths, in review order.
    """
    var paths = List[String]()
    paths.append(_module("curve_bounds"))
    paths.append(_module("spiral_domain_proof"))
    paths.append(_module("curve_frozen_arc"))
    paths.append(_module("lane_refinement"))
    return paths^


def _support() -> List[String]:
    """Return the support paths.

    Returns:
        The paths, in review order.
    """
    var paths = List[String]()
    paths.append(_module("lane_refinement"))
    paths.append(_module("map"))
    paths.append(_module("lane_distance"))
    paths.append(_module("junction_bounds"))
    paths.append(_module("spiral_domain_proof"))
    paths.append(_module("spiral_moment_table"))
    paths.append(_module("spiral_moment_proof"))
    paths.append(_module("spiral_roundoff_proof"))
    return paths^


def _group_names() -> List[String]:
    """Return the reviewed group names.

    Returns:
        The names, in review order.
    """
    var names = List[String]()
    names.append("canonical_accumulation")
    names.append("optional_runtime")
    names.append("stored_arithmetic")
    names.append("eligibility")
    names.append("translation")
    names.append("support")
    return names^


def _group_paths(name: String) -> List[String]:
    """Return the paths of one reviewed group.

    Args:
        name: The group name.

    Returns:
        The paths, in review order.
    """
    if name == "canonical_accumulation":
        return _canonical()
    if name == "optional_runtime":
        return _optional()
    if name == "stored_arithmetic":
        return _stored()
    if name == "eligibility":
        return _eligibility()
    if name == "translation":
        return _translation()
    return _support()


def _qualifier_names() -> List[String]:
    """Return the qualifier file names.

    Returns:
        The four reviewed files.
    """
    var names = List[String]()
    names.append("curve_bounds.mojo")
    names.append("curve_trig.mojo")
    names.append("curve_interval.mojo")
    names.append("lane_value_bounds.mojo")
    return names^


def _source(paths: List[String], texts: List[String], path: String) -> String:
    """Return the supplied source for `path`.

    Args:
        paths: The supplied paths.
        texts: The supplied sources.
        path: The path to find.

    Returns:
        The source, or an empty string when `path` is absent.
    """
    var index = 0
    while index < len(paths):
        if paths[index] == path:
            return String(texts[index])
        index += 1
    return ""


def _append_byte(mut out: List[UInt8], byte: UInt8):
    """Append one byte.

    Args:
        out: The visible source.
        byte: The byte to keep.
    """
    out.append(byte)


def _copy_string(data: Span[UInt8, _], mut index: Int, mut out: List[UInt8]):
    """Copy one string literal, including its quotes.

    Args:
        data: The source bytes.
        index: The opening quote, advanced past the literal.
        out: The visible source.
    """
    var quote = data[index]
    _append_byte(out, quote)
    index += 1
    var triple = (
        index + 1 < len(data)
        and data[index] == quote
        and data[index + 1] == quote
    )
    if triple:
        _append_byte(out, quote)
        _append_byte(out, quote)
        index += 2
        while index < len(data):
            if (
                index + 2 < len(data)
                and data[index] == quote
                and data[index + 1] == quote
                and data[index + 2] == quote
            ):
                _append_byte(out, quote)
                _append_byte(out, quote)
                _append_byte(out, quote)
                index += 3
                return
            _append_byte(out, data[index])
            index += 1
        return
    while index < len(data):
        var byte = data[index]
        _append_byte(out, byte)
        index += 1
        if byte == 92 and index < len(data):
            _append_byte(out, data[index])
            index += 1
            continue
        if byte == quote or byte == 10:
            return


def _visible(source: String) -> String:
    """Return `source` without comments that sit inside brackets.

    Args:
        source: One module.

    Returns:
        The source whose tokens match the Python token digest.
    """
    var data = source.as_bytes()
    var out = List[UInt8]()
    var index = 0
    var depth = 0
    while index < len(data):
        var byte = data[index]
        if byte == 34 or byte == 39:
            _copy_string(data, index, out)
            continue
        if byte == 35 and depth > 0:
            while index < len(data) and data[index] != 10:
                index += 1
            continue
        if byte == 40 or byte == 91 or byte == 123:
            depth += 1
        elif (byte == 41 or byte == 93 or byte == 125) and depth > 0:
            depth -= 1
        _append_byte(out, byte)
        index += 1
    return String(unsafe_from_utf8=Span(out))


def _check_digest(
    doc: PyJson,
    group: Int,
    group_name: String,
    expected: List[String],
    sources: List[String],
    texts: List[String],
) raises:
    """Require each path in `expected` to keep its token pin.

    Args:
        doc: The pin document.
        group: The group dict node.
        group_name: The group name.
        expected: The reviewed paths, in order.
        sources: The supplied paths.
        texts: The supplied sources.

    Raises:
        Error: A digest is invalid, or a token digest changed.
    """
    var index = 0
    while index < len(expected):
        var path = expected[index]
        var pin_node = doc.at(group, path)
        if doc.kind(pin_node) != PY_STR or not _hex_text(doc.text(pin_node)):
            _fail("invalid runtime dependency digest: " + path)
        var got = token_sha256(_visible(_source(sources, texts, path)))
        if got != doc.text(pin_node):
            _fail(
                "runtime source dependency changed ["
                + group_name
                + "]: "
                + path
            )
        index += 1


def runtime_source_groups(
    pins: String, paths: List[String], texts: List[String]
) raises:
    """Require the six runtime groups to keep their token pins.

    Args:
        pins: The runtime source pin document.
        paths: The reviewed module paths.
        texts: The reviewed source for each path.

    Raises:
        Error: The pin document changed, or a token digest changed.
    """
    var doc = PyJson.parse(pins)
    if doc.kind(doc.root) != PY_DICT:
        _fail("wrong runtime source pin keys")
    var root_expected = List[String]()
    root_expected.append("schema")
    root_expected.append("groups")
    root_expected.append("qualifiers")
    if not _same(_keys(doc, doc.root), root_expected):
        _fail("wrong runtime source pin keys")
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "1":
        _fail("unsupported runtime source pin schema")
    var groups = doc.at(doc.root, "groups")
    var names = _group_names()
    if doc.kind(groups) != PY_DICT:
        _fail("wrong runtime dependency group set")
    if not _same(_keys(doc, groups), names):
        _fail("wrong runtime dependency group set")
    var qualifiers = doc.at(doc.root, "qualifiers")
    if doc.kind(qualifiers) != PY_DICT:
        _fail("wrong qualifier file set")
    if not _same(_keys(doc, qualifiers), _qualifier_names()):
        _fail("wrong qualifier file set")
    var index = 0
    while index < len(names):
        var name = names[index]
        var group = doc.at(groups, name)
        var expected = _group_paths(name)
        if doc.kind(group) != PY_DICT:
            _fail("wrong runtime dependency path set: " + name)
        if not _same(_keys(doc, group), expected):
            _fail("wrong runtime dependency path set: " + name)
        _check_digest(doc, group, name, expected, paths, texts)
        index += 1
