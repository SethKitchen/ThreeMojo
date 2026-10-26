# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the fresh spiral heading graph.

The fresh k0, rate, and heading match the stored half graph. Three
consumers keep that rate, heading, and ideal u. The eligibility phase
keeps the original half product.
"""

from tests._python_tokens import _tokenize
from tools._sampled_value_copies import _body_statements


def _fail(message: String) raises:
    """Raise a heading-correspondence error.

    Args:
        message: The failure text.

    Raises:
        Error: The heading graph changed.
    """
    raise Error(message)


def _jets(text: String) -> String:
    """Rename the fresh `Expression` alias to `_Jet`.

    Args:
        text: One normalized statement.

    Returns:
        The statement with that alias renamed.
    """
    var out = text
    if out.byte_length() >= 11 and String(out[byte=0:11]) == "Expression ":
        out = "_Jet " + String(out[byte=11:])
    return out.replace(" Expression ", " _Jet ")


def _rows(source: String, name: String) raises -> List[String]:
    """Return the normalized statements of `name`.

    Args:
        source: The module text.
        name: The function name.

    Returns:
        Each direct body statement.

    Raises:
        Error: The function is missing or has no body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var raw = _body_statements(kinds, texts, name, False)
    var rows = List[String]()
    var index = 0
    while index < len(raw):
        rows.append(_jets(raw[index]))
        index += 1
    return rows^


def _rhs(rows: List[String], name: String) raises -> String:
    """Return the one assignment to `name`.

    Args:
        rows: The function statements.
        name: The assigned name.

    Returns:
        The right-hand side.

    Raises:
        Error: The assignment is missing or repeated.
    """
    var prefix = name + " = "
    var found = 0
    var rhs = String("")
    var index = 0
    while index < len(rows):
        var row = rows[index]
        if (
            row.byte_length() >= prefix.byte_length()
            and String(row[byte = 0 : prefix.byte_length()]) == prefix
        ):
            found += 1
            rhs = String(row[byte = prefix.byte_length() :])
        index += 1
    if found != 1:
        _fail("heading correspondence: missing/ambiguous assignment " + name)
    return rhs


def _count(text: String, needle: String) -> Int:
    """Return the number of times `needle` occurs.

    Args:
        text: The statement text.
        needle: The text to count.

    Returns:
        The number of occurrences.
    """
    var count = 0
    var rest = text
    var at = rest.find(needle)
    while at >= 0:
        count += 1
        var tail = String(rest[byte = at + needle.byte_length() :])
        rest = tail
        at = rest.find(needle)
    return count


def _join(rows: List[String]) -> String:
    """Join statements for a whole-function scan.

    Args:
        rows: The function statements.

    Returns:
        The statements separated by spaces.
    """
    var out = String("")
    var index = 0
    while index < len(rows):
        if index > 0:
            out += " "
        out += rows[index]
        index += 1
    return out


def _consumer(source: String, name: String, filename: String) raises:
    """Require one consumer to keep the stored heading graph.

    Args:
        source: The consumer module.
        name: The consumer function.
        filename: The module name in the failure text.

    Raises:
        Error: The rate, heading, ideal u, or stored-half call changed.
    """
    var rows = _rows(source, name)
    var rate = (
        "_Jet . constant ( ( geometry . curvature_end - geometry ."
        " curvature_start ) / geometry . length )"
    )
    if _rhs(rows, "rate") != rate:
        _fail("heading correspondence: stored rate differs: " + filename)
    var heading = (
        "_Jet . constant ( geometry . heading ) + d * ( _Jet . constant ( "
        "geometry . curvature_start ) + _stored_half ( rate ) * d )"
    )
    if _rhs(rows, "heading") != heading:
        _fail("heading correspondence: scalar heading differs: " + filename)
    var ideal = "_Jet . constant ( 0.5 ) * rate * d * d"
    if _rhs(rows, "u") != ideal:
        _fail("heading correspondence: ideal u graph changed: " + filename)
    var body = _join(rows)
    if (
        _count(body, "_stored_half") != 1
        or _count(body, "_stored_half ( rate )") != 1
    ):
        _fail("heading correspondence: unexpected helper consumer: " + filename)


def heading_correspondence(
    bounds: String, domain: String, moment: String, table: String
) raises:
    """Require the fresh heading graph and its three consumers.

    Args:
        bounds: The `curve_bounds` module.
        domain: The `spiral_domain_proof` module.
        moment: The `spiral_moment_proof` module.
        table: The `spiral_moment_table` module.

    Raises:
        Error: A fresh assignment, a consumer graph, or the eligibility
        phase changed.
    """
    var fresh = _rows(bounds, "_spiral_expression")
    var k0 = "_Jet . constant ( geometry . curvature_start )"
    if _rhs(fresh, "k0") != k0:
        _fail("heading correspondence: fresh k0 changed")
    var rate = (
        "_Jet . constant ( ( geometry . curvature_end - geometry ."
        " curvature_start ) / geometry . length )"
    )
    if _rhs(fresh, "rate") != rate:
        _fail("heading correspondence: fresh stored rate changed")
    var heading = _rhs(fresh, "heading")
    var expanded = heading.replace(" k0 ", " " + k0 + " ")
    var expected = (
        "_Jet . constant ( geometry . heading ) + d * ( "
        + k0
        + " + _stored_half ( rate ) * d )"
    )
    if expanded != expected:
        _fail("heading correspondence: fresh half heading changed")
    _consumer(domain, "_spiral_proof_branch", "spiral_domain_proof.mojo")
    _consumer(
        moment, "_try_spiral_moment_expansion", "spiral_moment_proof.mojo"
    )
    _consumer(table, "_try_spiral_moment_expansion", "spiral_moment_table.mojo")
    var eligibility = _rows(moment, "_all_spiral_nodes_quadrant_zero")
    var theta = (
        "_Jet . constant ( geometry . heading ) + t * ( _Jet . constant ( "
        "geometry . curvature_start ) + _Jet . constant ( 0.5 ) * rate * t )"
    )
    if _rhs(eligibility, "theta") != theta:
        _fail(
            "heading correspondence: original eligibility phase graph changed"
        )
    if _count(_join(eligibility), "_stored_half") != 0:
        _fail("heading correspondence: stored half introduced into eligibility")
