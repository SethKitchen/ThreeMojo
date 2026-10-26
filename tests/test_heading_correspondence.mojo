# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The fresh spiral heading graph stays checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._heading_correspondence import heading_correspondence


def _text(path: String) raises -> String:
    """Return one module.

    Args:
        path: The repository path.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path(path).read_text()


def _bounds() raises -> String:
    """Return the live curve-bounds module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/curve_bounds.mojo")


def _domain() raises -> String:
    """Return the live domain-proof module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/spiral_domain_proof.mojo")


def _moment() raises -> String:
    """Return the live moment-proof module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/spiral_moment_proof.mojo")


def _table() raises -> String:
    """Return the live moment-table module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/spiral_moment_table.mojo")


def test_the_heading_graph_holds() raises:
    """The fresh heading graph matches its three consumers."""
    var bounds = _bounds()
    var domain = _domain()
    var moment = _moment()
    var table = _table()
    heading_correspondence(bounds, domain, moment, table)
    heading_correspondence(
        bounds.replace(
            "    var k0 = Expression.constant(geometry.curvature_start)\n",
            (
                "    # reviewed\n    var k0 = "
                "Expression.constant(geometry.curvature_start)\n"
            ),
        ),
        domain,
        moment,
        table,
    )


def test_a_changed_heading_graph_is_refused() raises:
    """A changed fresh graph, consumer, or eligibility phase is refused."""
    var bounds = _bounds()
    var domain = _domain()
    var moment = _moment()
    var table = _table()
    with assert_raises(contains="heading correspondence: fresh k0 changed"):
        heading_correspondence(
            bounds.replace(
                "var k0 = Expression.constant(geometry.curvature_start)",
                "var k0 = Expression.constant(geometry.curvature_end)",
            ),
            domain,
            moment,
            table,
        )
    with assert_raises(
        contains="heading correspondence: fresh stored rate changed"
    ):
        heading_correspondence(
            bounds.replace(
                (
                    "var rate = Expression.constant(\n        "
                    "(geometry.curvature_end - geometry.curvature_start) / "
                    "geometry.length\n    )"
                ),
                (
                    "var rate = Expression.constant(\n        "
                    "(geometry.curvature_end - geometry.curvature_start) + "
                    "geometry.length\n    )"
                ),
            ),
            domain,
            moment,
            table,
        )
    with assert_raises(
        contains="heading correspondence: fresh half heading changed"
    ):
        heading_correspondence(
            bounds.replace(
                "k0 + _stored_half(rate) * d",
                "k0 + _stored_half(rate) * rate",
            ),
            domain,
            moment,
            table,
        )
    with assert_raises(
        contains="heading correspondence: missing/ambiguous assignment rate"
    ):
        heading_correspondence(
            bounds,
            domain.replace(
                "    var rate = _Jet.constant(",
                "    var rates = _Jet.constant(",
            ),
            moment,
            table,
        )
    with assert_raises(
        contains=(
            "heading correspondence: stored rate differs: "
            "spiral_domain_proof.mojo"
        )
    ):
        heading_correspondence(
            bounds,
            domain.replace(
                (
                    "    var rate = _Jet.constant(\n        "
                    "(geometry.curvature_end - geometry.curvature_start) / "
                    "geometry.length\n    )"
                ),
                (
                    "    var rate = _Jet.constant(\n        "
                    "(geometry.curvature_end + geometry.curvature_start) / "
                    "geometry.length\n    )"
                ),
            ),
            moment,
            table,
        )
    with assert_raises(
        contains=(
            "heading correspondence: scalar heading differs: "
            "spiral_domain_proof.mojo"
        )
    ):
        heading_correspondence(
            bounds,
            domain.replace(
                "_stored_half(rate) * d",
                "_stored_half(rate) * rate",
            ),
            moment,
            table,
        )
    with assert_raises(
        contains=(
            "heading correspondence: ideal u graph changed: "
            "spiral_domain_proof.mojo"
        )
    ):
        heading_correspondence(
            bounds,
            domain.replace(
                "var u = _Jet.constant(0.5) * rate * d * d",
                "var u = _Jet.constant(0.5) * rate * d * rate",
            ),
            moment,
            table,
        )
    with assert_raises(
        contains=(
            "heading correspondence: unexpected helper consumer: "
            "spiral_domain_proof.mojo"
        )
    ):
        heading_correspondence(
            bounds,
            domain.replace(
                "    var u = _Jet.constant(0.5) * rate * d * d\n",
                (
                    "    var extra = _stored_half(step)\n"
                    "    var u = _Jet.constant(0.5) * rate * d * d\n"
                ),
            ),
            moment,
            table,
        )
    with assert_raises(
        contains=(
            "heading correspondence: original eligibility phase graph changed"
        )
    ):
        heading_correspondence(
            bounds,
            domain,
            moment.replace(
                (
                    "    var theta = _Jet.constant(geometry.heading) + t * (\n"
                    "        _Jet.constant(geometry.curvature_start) + "
                    "_Jet.constant(0.5) * rate * t\n"
                    "    )"
                ),
                (
                    "    var theta = _Jet.constant(geometry.heading) + t * (\n"
                    "        _Jet.constant(geometry.curvature_end) + "
                    "_Jet.constant(0.5) * rate * t\n"
                    "    )"
                ),
            ),
            table,
        )
    with assert_raises(
        contains=(
            "heading correspondence: stored half introduced into eligibility"
        )
    ):
        heading_correspondence(
            bounds,
            domain,
            moment.replace(
                "    var theta = _Jet.constant(geometry.heading) + t * (\n",
                (
                    "    var extra = _stored_half(rate)\n"
                    "    var theta = _Jet.constant(geometry.heading) + t * (\n"
                ),
            ),
            table,
        )


def main() raises:
    """Run the heading correspondence tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
