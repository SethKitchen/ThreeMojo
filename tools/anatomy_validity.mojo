# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Produce bounded canonical-template evidence, never certification.

    mojo run -I . tools/anatomy_validity.mojo --build --output FILE

Use --build once, then reuse the source-bound probe. Each native measurement
has the unchanged five-second runtime limit. This tool needs no GPU, network
connection or rendered mesh.

The tool works on the repository in the current directory. It writes the
report as `json.dumps(report, indent=2)` did in the Python tool it replaces,
with the same floats, the same member order and the same messages.
"""

from std.collections import Set
from std.math import ceil, isinf, isnan, sqrt
from std.os import makedirs
from std.os.path import exists, isfile, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr

from loaders.json import ARRAY, BOOLEAN, NULL, NUMBER, OBJECT, STRING
from tools._fraction import Fraction
from tools._imports import mojo_files, resolve
from tools._json_tools import quote_ascii
from tools._json_tree import NOTHING, JsonTree, equal, type_name
from tools._process import run_program
from tools._python_float import parse_float, python_repr
from tools._python_math import py_sum
from tools._sha256 import Sha256, sha256_hex
from tools._text import split_lines

comptime ROUNDING_TOLERANCE = 5e-6
"""The relative roundoff tolerance of the tensor checks."""
comptime PINNED_TOOLCHAIN = "Mojo 1.1.0 (8189361e)"
"""The compiler version the report requires."""
comptime BINDING_VERSION = "anatomy-binding-v4"
"""The binding rule. Bump it when the rule changes. Version 4 binds the Mojo
binding code in place of the Python code that version 3 bound."""
comptime PROBE = "tools/anatomy_probe.mojo"
"""The native probe source."""
comptime INVENTORY = "docs/validation/anatomy-provenance.json"
"""The provenance inventory."""
comptime REPORT_LOGIC = "tools/anatomy_validity.mojo"
"""This tool, which the report binds as its logic."""
comptime PAIR_FRAME = "canonical/selected-side/lower-limb/knee-origin"
"""The frame of the lower-limb pair diagnostics."""
comptime SPINE_FRAME = "canonical/spine/hip-midpoint-origin"
"""The frame of the spine diagnostics."""
comptime PROGRAM = "anatomy_validity.mojo"
"""The program name in usage messages."""
comptime USAGE = (
    "usage: anatomy_validity.mojo [-h] [--build] [--mojo MOJO] [--probe"
    " PROBE]\n                             --output OUTPUT\n                   "
    "          [--steps-mm STEPS_MM [STEPS_MM ...]]\n                          "
    "   [--stature-m STATURE_M] [--sex {male,female}]\n                        "
    "     [--side {right,left}]\n                             [--athleticism"
    " {untoned,toned}]\n                             [--use"
    " {template-estimate,game-fantasy,engineering,whole-body,dynamic-constitutive,patient-specific,clinical-safety}]\n"
    "                             [--pair-scope {full,representative}]\n"
)
"""The usage text, as `argparse` wraps it."""
comptime HELP = (
    "\nProduce bounded canonical-template evidence, never certification. Use"
    " --build\nonce, then reuse the source-bound probe. Each native measurement"
    " has the\nunchanged five-second runtime limit. This tool needs no GPU,"
    " network connection\nor rendered mesh.\n\noptions:\n  -h, --help          "
    "  show this help message and exit\n  --build\n  --mojo MOJO\n  --probe"
    " PROBE\n  --output OUTPUT\n  --steps-mm STEPS_MM [STEPS_MM ...]\n "
    " --stature-m STATURE_M\n  --sex {male,female}\n  --side {right,left}\n "
    " --athleticism {untoned,toned}\n  --use"
    " {template-estimate,game-fantasy,engineering,whole-body,dynamic-constitutive,patient-specific,clinical-safety}\n"
    "  --pair-scope {full,representative}\n                        full named"
    " lower-limb catalog, or explicit\n                        representative"
    " subset\n"
)
"""The help text after the usage."""


def regions() -> List[String]:
    """Return the seven exclusive accounting regions, in precedence order.

    Returns:
        The region names.
    """
    return [
        "dermis",
        "cortical_apparent",
        "trabecular_apparent",
        "marrow_fat_proxy",
        "muscle",
        "tendon",
        "unresolved_fat_proxy",
    ]


def segments() -> List[String]:
    """Return the three canonical cuts.

    Returns:
        The segment names.
    """
    return ["thigh", "shank", "foot"]


def uses() -> List[String]:
    """Return the requested uses the gate knows.

    Returns:
        The use names.
    """
    return [
        "template-estimate",
        "game-fantasy",
        "engineering",
        "whole-body",
        "dynamic-constitutive",
        "patient-specific",
        "clinical-safety",
    ]


def build_flags() -> List[String]:
    """Return the pinned probe build flags.

    Returns:
        The flags.
    """
    return ["--Werror", "--num-threads", "1"]


def binding_code() -> List[String]:
    """Return the code that decides the binding, which the binding holds.

    Returns:
        This tool and the import resolver it uses.
    """
    return [REPORT_LOGIC, "tools/_imports.mojo"]


def pair_families() -> List[Tuple[String, Int]]:
    """Return each catalog family and its component count.

    Counts are an explicit catalog contract. A changed named-part enumerator
    must update the contract and its tests, rather than silently change
    report scope.

    Returns:
        The families, in catalog order.
    """
    return [
        ("bone", 30),
        ("knee", 5),
        ("muscle", 49),
        ("ligament", 10),
        ("vascular", 19),
        ("nerve", 13),
        ("lymphatic", 8),
    ]


def pair_region_counts(region: String) -> List[Tuple[String, Int]]:
    """Return each family of a catalog region and its component count.

    Args:
        region: `leg` or `foot`.

    Returns:
        The families, in catalog order, or none for another region.
    """
    if region == "leg":
        return [
            ("bone", 4),
            ("knee", 5),
            ("muscle", 28),
            ("vascular", 10),
            ("nerve", 6),
            ("lymphatic", 4),
        ]
    if region == "foot":
        return [
            ("bone", 26),
            ("muscle", 21),
            ("ligament", 10),
            ("vascular", 9),
            ("nerve", 7),
            ("lymphatic", 4),
        ]
    return []


def pair_component_ids() -> Set[String]:
    """Return every component identity the catalog contract names.

    Returns:
        The identities.
    """
    var found = Set[String]()
    for region in ["leg", "foot"]:
        for family in pair_region_counts(region):
            for part in range(family[1]):
                var name: String
                if region == "leg" and family[0] == "bone":
                    name = ["femur", "tibia", "fibula", "patella"][part]
                elif family[0] == "knee":
                    name = ["cartilage", "medial", "lateral", "mcl", "lcl"][
                        part
                    ]
                else:
                    name = String(part)
                found.add(region + "/" + family[0] + "/" + name)
    return found^


def _contains(items: List[String], item: String) -> Bool:
    """Return whether a list holds a string."""
    for entry in items:
        if entry == item:
            return True
    return False


# --- numbers -------------------------------------------------------------------


@fieldwise_init
struct Num(ImplicitlyCopyable, Movable):
    """A Python number: an int or a float."""

    var value: Float64
    """The value."""
    var integral: Bool
    """True for an int."""

    def text(self) raises -> String:
        """Return `str()` of the number.

        Returns:
            The digits of an int, or the `repr` of a float.

        Raises:
            Error: Never for a double.
        """
        if self.integral:
            return String(Int(self.value))
        return python_repr(self.value)

    def put(self, mut tree: JsonTree) -> Int:
        """Add the number to a tree.

        Args:
            tree: The tree.

        Returns:
            The new value.
        """
        if self.integral:
            return tree.integer(Int(self.value))
        return tree.number(self.value)


def _number(tree: JsonTree, node: Int) raises -> Num:
    """Return a value as a Python number, with a Boolean as an int."""
    return Num(tree.value(node), not tree.is_float(node))


def _difference(a: Num, b: Num) -> Num:
    """Return `a - b`, an int for two ints."""
    return Num(a.value - b.value, a.integral and b.integral)


@no_inline
def product(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded once.

    A call is a boundary that the compiler cannot fuse with a later add, so
    the result matches Python's separate rounding of each operation.

    Args:
        a: A factor.
        b: A factor.

    Returns:
        The rounded product.
    """
    return a * b


def fsum(values: List[Float64]) raises -> Float64:
    """Return the correctly rounded sum, as `math.fsum` does.

    Args:
        values: Finite floats.

    Returns:
        The sum. An exact zero is `0.0`.

    Raises:
        Error: If a value is not finite or the sum overflows.
    """
    var total = Fraction(0)
    for value in values:
        total = total + Fraction.from_float(value)
    return total.to_float()


def isclose(a: Float64, b: Float64, rel_tol: Float64, abs_tol: Float64) -> Bool:
    """Return `math.isclose(a, b, rel_tol=..., abs_tol=...)`.

    Args:
        a: A value.
        b: A value.
        rel_tol: The relative tolerance.
        abs_tol: The absolute tolerance.

    Returns:
        True when the values are close.
    """
    if a == b:
        return True
    if isinf(a) or isinf(b):
        return False
    var difference = abs(b - a)
    return (
        difference <= abs(product(rel_tol, b))
        or difference <= abs(product(rel_tol, a))
        or difference <= abs_tol
    )


def finite(tree: JsonTree, node: Int, name: String) raises -> Float64:
    """Require a finite scalar; a Boolean is not a measurement.

    Args:
        tree: The tree.
        node: A value or `NOTHING`.
        name: The quantity, for the message.

    Returns:
        The value.

    Raises:
        Error: `<name> must be a finite number` for anything else.
    """
    if tree.kind(node) != NUMBER:
        raise Error(name + " must be a finite number")
    var value = tree.value(node)
    if isnan(value) or isinf(value):
        raise Error(name + " must be a finite number")
    return value


def finite_value(value: Float64, name: String) raises -> Float64:
    """Require a finite number.

    Args:
        value: The number.
        name: The quantity, for the message.

    Returns:
        The value.

    Raises:
        Error: `<name> must be a finite number` for a NaN or an infinity.
    """
    if isnan(value) or isinf(value):
        raise Error(name + " must be a finite number")
    return value


def finite_tree(tree: JsonTree, node: Int) raises:
    """Require every float inside a value to be finite.

    Args:
        tree: The tree.
        node: A value or `NOTHING`.

    Raises:
        Error: `report number must be a finite number` for a NaN or an
            infinity.
    """
    var kind = tree.kind(node)
    if kind == NUMBER and tree.is_float(node):
        _ = finite(tree, node, "report number")
    elif kind == ARRAY or kind == OBJECT:
        for child in tree.values[node].items:
            finite_tree(tree, child)


def grid_steps(values: List[Num]) raises -> List[Num]:
    """Return distinct grid steps, coarsest first.

    Args:
        values: The requested steps, in millimeters.

    Returns:
        The steps, sorted from largest to smallest.

    Raises:
        Error: For a step that is not finite or not 2 through 20 mm, a
            repeated step, or fewer than 3 or more than 10 steps.
    """
    for value in values:
        var step = finite_value(value.value, "grid step")
        if not (2.0 <= step and step <= 20.0):
            raise Error("grid steps must be between 2 and 20 mm")
    var ordered = List[Num]()
    for value in values:
        var seen = False
        for other in ordered:
            if other.value == value.value:
                seen = True
        if not seen:
            ordered.append(value)
    # Sort from largest to smallest; the values are distinct.
    for i in range(1, len(ordered)):
        var j = i
        while j > 0 and ordered[j - 1].value < ordered[j].value:
            var swap = ordered[j - 1]
            ordered[j - 1] = ordered[j]
            ordered[j] = swap
            j -= 1
    if len(ordered) != len(values) or not (
        3 <= len(ordered) and len(ordered) <= 10
    ):
        raise Error("use 3 through 10 distinct grid steps")
    return ordered^


# --- tensors -------------------------------------------------------------------


struct TensorChecks(Copyable, Movable):
    """The algebraic invariants of one inertia tensor."""

    var positive_semidefinite: Bool
    """All principal minors are at least the negative tolerance."""
    var triangle_inequalities: Bool
    """All central second-moment minors are at least the negative
    tolerance."""
    var covariance_minors: List[Float64]
    """The scaled central second-moment principal minors."""
    var minors: List[Float64]
    """The scaled principal minors."""

    def __init__(out self):
        """Start with no checks."""
        self.positive_semidefinite = False
        self.triangle_inequalities = False
        self.covariance_minors = List[Float64]()
        self.minors = List[Float64]()

    def put(self, mut tree: JsonTree) raises -> Int:
        """Add the checks to a tree as the report records them.

        Args:
            tree: The tree.

        Returns:
            The new object.

        Raises:
            Error: Never for an object.
        """
        var node = tree.object()
        tree.set_flag(node, "symmetric_by_representation", True)
        tree.set_flag(node, "positive_semidefinite", self.positive_semidefinite)
        tree.set_flag(node, "triangle_inequalities", self.triangle_inequalities)
        tree.set(
            node,
            "scaled_central_second_moment_principal_minors",
            tree.numbers(self.covariance_minors),
        )
        tree.set(node, "scaled_principal_minors", tree.numbers(self.minors))
        tree.set(
            node,
            "relative_roundoff_tolerance",
            tree.number(ROUNDING_TOLERANCE),
        )
        return node


def _minors(
    x: Float64, y: Float64, z: Float64, a: Float64, b: Float64, c: Float64
) -> List[Float64]:
    """Return the seven principal minors of a symmetric matrix, with each
    product rounded as Python rounds it."""
    var full = (
        product(product(x, y), z)
        + product(product(product(2.0, a), b), c)
        - product(product(x, c), c)
        - product(product(y, b), b)
        - product(product(z, a), a)
    )
    return [
        x,
        y,
        z,
        product(x, y) - product(a, a),
        product(x, z) - product(b, b),
        product(y, z) - product(c, c),
        full,
    ]


def _minimum(values: List[Float64]) -> Float64:
    """Return the smallest value, as Python's `min` does."""
    var found = values[0]
    for value in values:
        if value < found:
            found = value
    return found


def tensor_checks(values: List[Float64]) raises -> TensorChecks:
    """Check all principal minors, using a numerical roundoff tolerance.

    Physical inertia additionally requires a positive-semidefinite central
    second-moment matrix C = trace(I)/2 Identity - I. Coordinate-diagonal
    triangles alone miss rotated counterexamples.

    Args:
        values: The six entries xx, yy, zz, xy, xz and yz.

    Returns:
        The checks.

    Raises:
        Error: If there are not six finite entries.
    """
    if len(values) != 6:
        raise Error("a tensor needs six entries")
    var scale = 0.0
    for value in values:
        _ = finite_value(value, "inertia")
        if abs(value) > scale:
            scale = abs(value)
    var checks = TensorChecks()
    if scale == 0:
        checks.minors = List[Float64](length=7, fill=0.0)
        checks.covariance_minors = List[Float64](length=7, fill=0.0)
    else:
        var x = values[0] / scale
        var y = values[1] / scale
        var z = values[2] / scale
        var a = values[3] / scale
        var b = values[4] / scale
        var c = values[5] / scale
        checks.minors = _minors(x, y, z, a, b, c)
        checks.covariance_minors = _minors(
            (y + z - x) / 2, (x + z - y) / 2, (x + y - z) / 2, -a, -b, -c
        )
    checks.positive_semidefinite = (
        _minimum(checks.minors) >= -ROUNDING_TOLERANCE
    )
    checks.triangle_inequalities = (
        _minimum(checks.covariance_minors) >= -ROUNDING_TOLERANCE
    )
    return checks^


def tensor_values(tree: JsonTree, node: Int) raises -> List[Float64]:
    """Return a tensor's entries, as `tensor_checks` reads them.

    Args:
        tree: The tree.
        node: The tensor value.

    Returns:
        The finite entries.

    Raises:
        Error: If the value does not hold six finite numbers.
    """
    if tree.length(node) != 6:
        raise Error("a tensor needs six entries")
    if tree.kind(node) != ARRAY:
        raise Error("inertia must be a finite number")
    var values = List[Float64]()
    for child in tree.items(node):
        values.append(finite(tree, child, "inertia"))
    return values^


def vector(tree: JsonTree, node: Int, name: String) raises -> List[Float64]:
    """Return three finite coordinates.

    Args:
        tree: The tree.
        node: A value or `NOTHING`.
        name: The quantity, for the message.

    Returns:
        The coordinates.

    Raises:
        Error: If the value is not a list of three finite numbers.
    """
    if tree.kind(node) != ARRAY or tree.length(node) != 3:
        raise Error(name + " must contain three coordinates")
    var values = List[Float64]()
    for child in tree.items(node):
        values.append(finite(tree, child, name))
    return values^


def _in(tree: JsonTree, node: Int, names: List[String]) raises -> Bool:
    """Return whether a value is one of some strings."""
    for name in names:
        if tree.is_text(node, name):
            return True
    return False


def validate_segment(tree: JsonTree, row: Int) raises -> TensorChecks:
    """Check one segment record and return its tensor checks.

    Args:
        tree: The tree.
        row: The segment record.

    Returns:
        The tensor checks.

    Raises:
        Error: If the record breaks a segment invariant.
    """
    if not tree.is_text(tree.get(row, "record"), "segment") or not _in(
        tree, tree.get(row, "segment"), segments()
    ):
        raise Error("a probe must name one supported segment")
    var mass = finite(tree, tree.get(row, "mass_kg"), "mass")
    if mass <= 0 or finite(tree, tree.get(row, "length_m"), "length") <= 0:
        raise Error("segment mass and length must be positive")
    var step = finite(tree, tree.get(row, "step_m"), "step")
    if not (0.001999999 <= step and step <= 0.020000001):
        raise Error("unsupported segment grid step")
    var low = vector(tree, tree.get(row, "low_m"), "low_m")
    var high = vector(tree, tree.get(row, "high_m"), "high_m")
    var center = vector(tree, tree.get(row, "center_m"), "center_m")
    for axis in range(3):
        if high[axis] <= low[axis]:
            raise Error("segment bounds must be strictly ordered")
    for axis in range(3):
        if center[axis] < low[axis] - 1e-7 or center[axis] > high[axis] + 1e-7:
            raise Error("the center must be within its sampled box")
    var checks = tensor_checks(
        tensor_values(tree, tree.item(row, "inertia_kg_m2"))
    )
    if not checks.positive_semidefinite or not checks.triangle_inequalities:
        raise Error("a segment tensor fails its algebraic invariants")
    var accounts = tree.get(row, "regions")
    var complete = tree.kind(accounts) == OBJECT
    if complete:
        var names = tree.names(accounts)
        complete = len(names) == len(regions())
        for name in regions():
            if not _contains(names, name):
                complete = False
    if not complete:
        raise Error("all seven exclusive accounting regions must be present")
    var names = tree.names(accounts)
    var masses = List[Float64]()
    var volumes = List[Float64]()
    for index in range(len(names)):
        var region = tree.at(accounts, index)
        for quantity in ["mass_kg", "volume_m3"]:
            if (
                finite(
                    tree,
                    tree.get(region, quantity),
                    names[index] + "." + quantity,
                )
                < 0
            ):
                raise Error("region quantities cannot be negative")
        masses.append(tree.value(tree.item(region, "mass_kg")))
        volumes.append(tree.value(tree.item(region, "volume_m3")))
    if not isclose(fsum(masses), mass, ROUNDING_TOLERANCE, 1e-9):
        raise Error("exclusive region masses must sum to the segment mass")
    var box = 1.0
    for axis in range(3):
        box = product(box, high[axis] - low[axis])
    if fsum(volumes) > product(box, 1.000005):
        raise Error("exclusive region volumes exceed their sample box")
    finite_tree(tree, row)
    return checks^


def _numbers(tree: JsonTree, node: Int) raises -> List[Num]:
    """Return the numbers of an array."""
    var found = List[Num]()
    for child in tree.items(node):
        found.append(_number(tree, child))
    return found^


def _square_sum(values: List[Num], start: Int, stop: Int) raises -> Float64:
    """Return `sum(v*v for v in values[start:stop])` as CPython adds it."""
    var squares = List[Float64]()
    var kinds = List[Bool]()
    for index in range(start, min(stop, len(values))):
        squares.append(product(values[index].value, values[index].value))
        kinds.append(values[index].integral)
    return py_sum(squares, kinds)[0]


def _frobenius(values: List[Num]) raises -> Float64:
    """Return the tensor norm that counts each off-diagonal entry twice."""
    return sqrt(_square_sum(values, 0, 3) + 2 * _square_sum(values, 3, 6))


def _put_numbers(mut tree: JsonTree, values: List[Num]) raises -> Int:
    """Add an array of Python numbers."""
    var node = tree.array()
    for value in values:
        tree.append(node, value.put(tree))
    return node


def sampling_sensitivity(mut tree: JsonTree, rows: List[Int]) raises -> Int:
    """Record the differences between consecutive grids of one segment.

    Args:
        tree: The tree.
        rows: The segment records, coarsest first.

    Returns:
        The new sensitivity object.

    Raises:
        Error: For fewer than three grids or steps that do not decrease.
    """
    if len(rows) < 3:
        raise Error("at least three grids are required")
    var steps = List[Float64]()
    for row in rows:
        steps.append(finite(tree, tree.item(row, "step_m"), "step"))
    for index in range(len(steps) - 1):
        if steps[index] <= steps[index + 1]:
            raise Error("grid steps must be strictly decreasing")
    var changes = tree.array()
    for index in range(len(rows) - 1):
        var coarse = rows[index]
        var fine = rows[index + 1]
        var coarse_center = _numbers(tree, tree.item(coarse, "center_m"))
        var fine_center = _numbers(tree, tree.item(fine, "center_m"))
        var dc = List[Num]()
        for axis in range(min(len(coarse_center), len(fine_center))):
            dc.append(_difference(coarse_center[axis], fine_center[axis]))
        var coarse_tensor = _numbers(tree, tree.item(coarse, "inertia_kg_m2"))
        var fine_tensor = _numbers(tree, tree.item(fine, "inertia_kg_m2"))
        var di = List[Num]()
        for entry in range(min(len(coarse_tensor), len(fine_tensor))):
            di.append(_difference(coarse_tensor[entry], fine_tensor[entry]))
        var norm = _frobenius(di)
        var fnorm = _frobenius(fine_tensor)
        var coarse_mass = _number(tree, tree.item(coarse, "mass_kg"))
        var fine_mass = _number(tree, tree.item(fine, "mass_kg"))
        var mass_delta = _difference(coarse_mass, fine_mass)
        mass_delta.value = abs(mass_delta.value)
        var change = tree.object()
        tree.set(
            change, "coarse_step_m", tree.clone(tree.item(coarse, "step_m"))
        )
        tree.set(change, "fine_step_m", tree.clone(tree.item(fine, "step_m")))
        tree.set(change, "mass_abs_delta_kg", mass_delta.put(tree))
        tree.set(
            change,
            "mass_relative_delta",
            tree.number(mass_delta.value / fine_mass.value),
        )
        tree.set(change, "center_delta_m", _put_numbers(tree, dc))
        tree.set(
            change,
            "center_delta_norm_m",
            tree.number(sqrt(_square_sum(dc, 0, len(dc)))),
        )
        tree.set(change, "tensor_delta_kg_m2", _put_numbers(tree, di))
        tree.set(change, "tensor_delta_frobenius_kg_m2", tree.number(norm))
        if fnorm != 0:
            tree.set(
                change,
                "tensor_relative_frobenius_delta",
                tree.number(norm / fnorm),
            )
        else:
            tree.set_null(change, "tensor_relative_frobenius_delta")
        tree.append(changes, change)
    var result = tree.object()
    tree.set(result, "comparisons", changes)
    tree.set_null(result, "error_bound")
    tree.set_null(result, "observed_order")
    tree.set_flag(result, "converged_to_physical_reference", False)
    tree.set_text(
        result,
        "interpretation",
        (
            "Observed sampling sensitivity only. Thin regions, grid phase and"
            " discontinuous density assignments can be nonmonotone. Differences"
            " are not proven sampling-error or anatomical-uncertainty bounds."
        ),
    )
    return result


def compose_segments(mut tree: JsonTree, rows: List[Int]) raises -> Int:
    """Accept one set of three disjoint cuts, not arbitrary part totals.

    Args:
        tree: The tree.
        rows: The finest segment record of each cut.

    Returns:
        The new composition object.

    Raises:
        Error: For a missing or repeated cut, different steps, gaps,
            overlaps or different envelopes.
    """
    if len(rows) != 3:
        raise Error("composition needs exactly one thigh, shank and foot")
    var names = List[String]()
    var bad = False
    for row in rows:
        var segment = tree.item(row, "segment")
        if not _in(tree, segment, segments()):
            bad = True
        elif not _contains(names, tree.text(segment)):
            names.append(tree.text(segment))
    if bad or len(names) != 3:
        raise Error("composition needs exactly one thigh, shank and foot")
    for row in rows:
        _ = validate_segment(tree, row)
    var steps = List[Float64]()
    for row in rows:
        var step = tree.value(tree.item(row, "step_m"))
        var seen = False
        for other in steps:
            if other == step:
                seen = True
        if not seen:
            steps.append(step)
    if len(steps) != 1:
        raise Error("composition requires the same requested grid step")
    var ordered = rows.copy()
    for i in range(1, len(ordered)):
        var j = i
        while j > 0 and tree.value(
            tree.at(tree.item(ordered[j], "low_m"), 1)
        ) < tree.value(tree.at(tree.item(ordered[j - 1], "low_m"), 1)):
            var swap = ordered[j - 1]
            ordered[j - 1] = ordered[j]
            ordered[j] = swap
            j -= 1
    for index in range(len(ordered) - 1):
        var a = ordered[index]
        var b = ordered[index + 1]
        if tree.value(tree.at(tree.item(a, "high_m"), 1)) != tree.value(
            tree.at(tree.item(b, "low_m"), 1)
        ):
            raise Error(
                "segment cut planes must meet exactly without overlap or gaps"
            )
        for key in ["low_m", "high_m"]:
            for axis in [0, 2]:
                if tree.value(tree.at(tree.item(a, key), axis)) != tree.value(
                    tree.at(tree.item(b, key), axis)
                ):
                    raise Error(
                        "composition requires the same limb envelope bounds"
                    )
    var masses = List[Float64]()
    for row in rows:
        masses.append(tree.value(tree.item(row, "mass_kg")))
    var mass = fsum(masses)
    var center = List[Float64]()
    for axis in range(3):
        var moments = List[Float64]()
        for index in range(len(rows)):
            moments.append(
                product(
                    masses[index],
                    tree.value(
                        tree.at(tree.item(rows[index], "center_m"), axis)
                    ),
                )
            )
        center.append(fsum(moments) / mass)
    var total = List[Float64](length=6, fill=0.0)
    for index in range(len(rows)):
        var row = rows[index]
        var x = tree.value(tree.at(tree.item(row, "center_m"), 0)) - center[0]
        var y = tree.value(tree.at(tree.item(row, "center_m"), 1)) - center[1]
        var z = tree.value(tree.at(tree.item(row, "center_m"), 2)) - center[2]
        var offset: List[Float64] = [
            product(y, y) + product(z, z),
            product(x, x) + product(z, z),
            product(x, x) + product(y, y),
            product(-x, y),
            product(-x, z),
            product(-y, z),
        ]
        var tensor = tree.item(row, "inertia_kg_m2")
        var count = min(6, tree.length(tensor))
        var next = List[Float64]()
        for entry in range(count):
            next.append(
                total[entry]
                + tree.value(tree.at(tensor, entry))
                + product(masses[index], offset[entry])
            )
        total = next^
    var result = tree.object()
    tree.set_text(result, "label", "selected-side lower-limb template estimate")
    tree.set_flag(result, "is_whole_body", False)
    tree.set(result, "mass_kg", tree.number(mass))
    tree.set(result, "center_m", tree.numbers(center))
    tree.set(result, "inertia_kg_m2", tree.numbers(total))
    var checks = tensor_checks(total)
    tree.set(result, "tensor_checks", checks.put(tree))
    tree.set_text(
        result,
        "scope",
        (
            "Only these three canonical cuts. Pore-fluid/marrow mass and other"
            " body segments are not added."
        ),
    )
    return result


def use_gate(mut tree: JsonTree, use: String) raises -> Int:
    """Record whether a requested use is permitted as labeled.

    Args:
        tree: The tree.
        use: The requested use.

    Returns:
        The new gate object.

    Raises:
        Error: For an unknown use.
    """
    if not _contains(uses(), use):
        raise Error("unknown requested use")
    var gate = tree.object()
    tree.set_text(gate, "requested_use", use)
    tree.set_flag(
        gate,
        "permitted_as_labeled",
        use == "template-estimate" or use == "game-fantasy",
    )
    tree.set_text(gate, "result_label", "template estimate")
    tree.set_flag(gate, "engineering_validated", False)
    tree.set_flag(gate, "clinical_or_safety_certification", False)
    tree.set_null(gate, "task_specific_reference_evidence")
    tree.set_null(gate, "task_specific_acceptance_thresholds")
    tree.set_text(
        gate,
        "reason",
        (
            "Template and game/fantasy use is permitted. Other claims lack"
            " task-specific independent reference evidence and acceptance"
            " thresholds."
        ),
    )
    return gate


# --- legacy diagnostics --------------------------------------------------------


def _sorted_pair(a: String, b: String) -> String:
    """Return two names in order, joined by `|`."""
    if b < a:
        return b + "|" + a
    return a + "|" + b


def _pair_key(a: String, b: String) -> String:
    """Return a key for an unordered pair of labels."""
    if b < a:
        return b + "\n" + a
    return a + "\n" + b


def annotate_diagnostics(mut tree: JsonTree, groups: Int) raises -> Int:
    """Add stable pair IDs, retaining labels and every sampled hit.

    Args:
        tree: The tree.
        groups: An object of diagnostic groups, each an array of records.

    Returns:
        The same object.

    Raises:
        Error: For an unknown record, an unexpected sacral placeholder or a
            repeated identity.
    """
    var seen = Set[String]()
    var names = tree.names(groups)
    for position in range(len(names)):
        var group = names[position]
        for row in tree.items(tree.at(groups, position)):
            tree.set_text(
                row, "frame_id", SPINE_FRAME if group == "spine" else PAIR_FRAME
            )
            var record = tree.get(row, "record")
            var identity: String
            if tree.is_text(record, "pair"):
                var first = tree.text(tree.item(row, "first")).replace(" ", "_")
                var second = tree.text(tree.item(row, "second")).replace(
                    " ", "_"
                )
                identity = (
                    "canonical/" + group + "/" + _sorted_pair(first, second)
                )
                tree.set_text(row, "pair_id", identity)
                if tree.is_number(tree.get(row, "samples"), 0):
                    tree.set_null(row, "signed_field_witness_m")
                tree.set_flag(row, "allowlist_applied", False)
                tree.set_text(
                    row,
                    "geometry_kind",
                    "implicit component envelope intersection",
                )
                tree.set_text(
                    row,
                    "contact_intent",
                    (
                        "unclassified; an anatomical attachment is not an"
                        " established volume allowance"
                    ),
                )
            elif tree.is_text(record, "endplane"):
                var body = tree.text(tree.item(row, "body"))
                identity = "canonical/spine/endplane/" + body
                tree.set_text(row, "endplane_id", identity)
                tree.set_text(
                    row,
                    "boundary_contact_rule",
                    "spine_endplane_boundary_contact",
                )
                if body == "thoracolumbar/16":
                    # This is an authored plane, not a sampled sacral solid.
                    # Refuse protocol drift rather than discard a measurement.
                    if not tree.is_number(
                        tree.item(row, "next_body_outside_field_m"), 0
                    ):
                        raise Error(
                            "unexpected sacral support-plane placeholder"
                        )
                    tree.set_flag(row, "next_body_sampled", False)
                    tree.set_null(row, "next_body_outside_field_m")
                    tree.set_text(
                        row,
                        "next_reference_kind",
                        "authored sacral support plane",
                    )
                else:
                    tree.set_flag(row, "next_body_sampled", True)
                    tree.set_text(
                        row,
                        "next_reference_kind",
                        "neighboring vertebral body",
                    )
            else:
                raise Error("unknown diagnostic record")
            if identity in seen:
                raise Error("duplicate diagnostic identity")
            seen.add(identity)
    return groups


def diagnostic_findings(mut tree: JsonTree, groups: Int) raises -> Int:
    """Name incompatible geometry without redefining measured parameters.

    Args:
        tree: The tree.
        groups: An object of diagnostic groups.

    Returns:
        The new array of findings.

    Raises:
        Error: For an unknown record or a missing measurement.
    """
    var findings = tree.array()
    var names = tree.names(groups)
    for position in range(len(names)):
        var group = names[position]
        for row in tree.items(tree.at(groups, position)):
            var record = tree.get(row, "record")
            if tree.is_text(record, "pair"):
                if tree.value(tree.item(row, "overlap_samples")) > 0:
                    var finding = tree.object()
                    tree.set_text(
                        finding, "kind", "unallowlisted_sampled_overlap"
                    )
                    tree.set_text(finding, "group", group)
                    tree.set(
                        finding, "pair_id", tree.clone(tree.get(row, "pair_id"))
                    )
                    tree.set(
                        finding, "first", tree.clone(tree.item(row, "first"))
                    )
                    tree.set(
                        finding, "second", tree.clone(tree.item(row, "second"))
                    )
                    tree.set(
                        finding,
                        "overlap_volume_m3",
                        tree.clone(tree.item(row, "overlap_volume_m3")),
                    )
                    tree.set_text(
                        finding,
                        "interpretation",
                        (
                            "Common interior was sampled. A construction-union"
                            " allowance within one field does not exempt these"
                            " distinct named fields."
                        ),
                    )
                    tree.append(findings, finding)
            elif tree.is_text(record, "endplane"):
                var reasons = List[String]()
                if tree.value(tree.item(row, "disc_gap_m")) <= 0:
                    reasons.append("disc endplanes are reversed or coincident")
                for key in [
                    "body_disc_endplane_error_m",
                    "next_body_disc_endplane_error_m",
                ]:
                    if tree.value(tree.item(row, key)) > 1e-6:
                        reasons.append(key)
                for key in [
                    "body_outside_field_m",
                    "disc_outside_upper_field_m",
                    "disc_outside_lower_field_m",
                ]:
                    if tree.value(tree.item(row, key)) <= 0:
                        reasons.append(key)
                # L5 uses an authored support plane, not a sampled flat sacrum.
                if (
                    tree.truthy(tree.item(row, "next_body_sampled"))
                    and tree.value(tree.item(row, "next_body_outside_field_m"))
                    <= 0
                ):
                    reasons.append("next_body_outside_field_m")
                if len(reasons) > 0:
                    var finding = tree.object()
                    tree.set_text(finding, "kind", "incompatible_endplanes")
                    tree.set(
                        finding, "body", tree.clone(tree.item(row, "body"))
                    )
                    tree.set(finding, "reasons", tree.strings(reasons))
                    tree.append(findings, finding)
            else:
                raise Error("unknown diagnostic record")
    return findings


# --- the source binding --------------------------------------------------------


def _space(byte: UInt8) -> Bool:
    """Return whether a byte is white space for Python's `\\s`."""
    return (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 32)


def _letter(byte: UInt8) -> Bool:
    """Return whether a byte is an ASCII letter."""
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)


def _name_byte(byte: UInt8) -> Bool:
    """Return whether a byte is in `[A-Za-z0-9_]`."""
    return _letter(byte) or (byte >= 48 and byte <= 57) or byte == 95


def _strip(text: String) -> String:
    """Return text without leading and trailing white space."""
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end and _space(bytes[start]):
        start += 1
    while end > start and _space(bytes[end - 1]):
        end -= 1
    return String(text[byte=start:end])


def read_text(path: String) raises -> String:
    """Read a file as Python's `read_text` does, with universal newlines.

    Args:
        path: The file.

    Returns:
        The text, with each CR LF and lone CR read as LF.

    Raises:
        Error: If the file cannot be read or is not UTF-8.
    """
    var bytes = Path(path).read_bytes()
    var text = String(from_utf8=Span(bytes))
    if text.find("\r") < 0:
        return text^
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _raw_prefix(window: List[UInt8]) -> Bool:
    """Return whether one or two letters before a quote, as
    `(?<![A-Za-z0-9_])[A-Za-z]{1,2}$` finds them, include an `r`."""
    var end = len(window)
    if end > 0 and window[end - 1] == 10:
        end -= 1
    var start = end
    while start > 0 and _letter(window[start - 1]):
        start -= 1
    var count = end - start
    if count < 1 or count > 2:
        return False
    if start > 0 and _name_byte(window[start - 1]):
        return False
    for index in range(start, end):
        if window[index] == 114 or window[index] == 82:
            return True
    return False


def code_only(text: String) raises -> String:
    """Return `text` with each comment and string literal blanked.

    Newlines stay, so a docstring cannot join or split the lines around it.
    A string prefix such as `r` stays, which no import can contain.

    Args:
        text: The source.

    Returns:
        The source, with one space for each blanked character.

    Raises:
        Error: If a string literal does not end.
    """
    var bytes = text.as_bytes()
    var size = len(bytes)
    var out = List[UInt8](capacity=size)
    var starts = List[Int]()
    var index = 0
    while index < size:
        var char = bytes[index]
        var end: Int
        if char == 35:
            end = index
            while end < size and bytes[end] != 10:
                end += 1
        elif char == 34 or char == 39:
            var width = 1
            if (
                index + 2 < size
                and bytes[index + 1] == char
                and bytes[index + 2] == char
            ):
                width = 3
            var window = List[UInt8]()
            var first = starts[len(starts) - 3] if len(starts) >= 3 else 0
            for position in range(first, len(out)):
                window.append(out[position])
            # A backslash escapes the next character, except in a raw string.
            var raw = _raw_prefix(window)
            end = index + width
            while True:
                var closed = end + width <= size
                if closed:
                    for offset in range(width):
                        if bytes[end + offset] != char:
                            closed = False
                if closed:
                    break
                if end >= size or (width == 1 and bytes[end] == 10):
                    raise Error("a string literal does not end")
                end += 1 if raw or bytes[end] != 92 else 2
            end += width
        else:
            starts.append(len(out))
            out.append(char)
            index += 1
            continue
        starts.append(len(out))
        for position in range(index, end):
            var byte = bytes[position]
            if byte == 10:
                out.append(10)
            elif (byte & 0xC0) != 0x80:
                out.append(32)
        index = end
    return String(unsafe_from_utf8=Span(out))


def statements(text: String) raises -> List[String]:
    """Return each logical statement of `text`, comments and strings blanked.

    A statement goes on over lines inside brackets and after a backslash,
    and a semicolon ends one.

    Args:
        text: The source.

    Returns:
        The statements, stripped, without empty ones.

    Raises:
        Error: If a string literal does not end or a bracket does not
            close.
    """
    var code = code_only(text).replace("\\\n", "  ") + "\n"
    var bytes = code.as_bytes()
    var found = List[String]()
    var current = List[UInt8]()
    var depth = 0
    for char in bytes:
        if char == 40 or char == 91 or char == 123:
            depth += 1
        elif char == 41 or char == 93 or char == 125:
            depth = max(0, depth - 1)
        if (char == 10 and depth == 0) or char == 59:
            var statement = _strip(String(unsafe_from_utf8=Span(current)))
            if statement.byte_length() > 0:
                found.append(statement)
            current = List[UInt8]()
        else:
            current.append(32 if char == 10 else char)
    if depth:
        raise Error("a bracket does not close")
    return found^


@fieldwise_init
struct Import(Copyable, Movable):
    """One imported module, as the compiler reads it."""

    var module: String
    """The dotted module."""
    var names: List[String]
    """The names after `import` in a `from` import."""
    var plain: Bool
    """True for a plain `import`, which has no names."""


def _skip_space(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return the first position at or after `start` that is not space."""
    var index = start
    while index < len(bytes) and _space(bytes[index]):
        index += 1
    return index


def _name_end(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return the end of a name at `start`, or `start` when there is none."""
    if start >= len(bytes) or not (_letter(bytes[start]) or bytes[start] == 95):
        return start
    var index = start + 1
    while index < len(bytes) and _name_byte(bytes[index]):
        index += 1
    return index


def _dotted_end(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return the end of a dotted name at `start`, or `start`."""
    var end = _name_end(bytes, start)
    if end == start:
        return start
    while end < len(bytes) and bytes[end] == 46:
        var next = _name_end(bytes, end + 1)
        if next == end + 1:
            break
        end = next
    return end


def is_dotted(text: String) -> Bool:
    """Return whether text is a whole dotted name.

    Args:
        text: The text.

    Returns:
        True for names joined by dots.
    """
    var bytes = text.as_bytes()
    return len(bytes) > 0 and _dotted_end(bytes, 0) == len(bytes)


def import_item(item: String) -> Optional[String]:
    """Read `a.b` or `a.b as c`, as `(DOTTED)(?:\\s+as\\s+NAME)?` does.

    Args:
        item: One stripped item of an import list.

    Returns:
        The dotted name, or nothing when the item cannot be read.
    """
    var bytes = item.as_bytes()
    var end = _dotted_end(bytes, 0)
    if end == 0:
        return None
    var name = String(item[byte=:end])
    if end == len(bytes):
        return name
    var index = _skip_space(bytes, end)
    if index == end or index + 2 > len(bytes):
        return None
    if bytes[index] != 97 or bytes[index + 1] != 115:
        return None
    var after = _skip_space(bytes, index + 2)
    if after == index + 2:
        return None
    if _name_end(bytes, after) != len(bytes) or after == len(bytes):
        return None
    return name


def _starts_import(statement: String) -> Bool:
    """Return whether a statement starts with `from` or `import` as a word."""
    var bytes = statement.as_bytes()
    for word in ["from", "import"]:
        var size = word.byte_length()
        if statement.startswith(word) and (
            len(bytes) == size
            or not (_name_byte(bytes[size]) or bytes[size] >= 0x80)
        ):
            return True
    return False


def _unreadable(statement: String) -> Error:
    """Return the error for an import the tool cannot read."""
    return Error("cannot read the import: " + statement)


def imports_of(text: String) raises -> List[Import]:
    """Return the imports in a Mojo source, as the compiler reads them.

    Each is the dotted module, and for a `from` import the names after
    `import`, which can be symbols or submodules. Comments and string
    literals, docstrings among them, hold no imports. An alias can follow
    any white space.

    Args:
        text: The source.

    Returns:
        The imports, in order.

    Raises:
        Error: If an import is relative, or a statement that starts with
            `from` or `import` cannot be read.
    """
    var found = List[Import]()
    for statement in statements(text):
        if not _starts_import(statement):
            continue
        var bytes = statement.as_bytes()
        # `from\s+(\S+)\s+import\s+(.*)`
        if statement.startswith("from"):
            var index = _skip_space(bytes, 4)
            var module_end = index
            while module_end < len(bytes) and not _space(bytes[module_end]):
                module_end += 1
            var after = _skip_space(bytes, module_end)
            if (
                index > 4
                and module_end > index
                and after > module_end
                and String(statement[byte=after:]).startswith("import")
            ):
                var rest_start = _skip_space(bytes, after + 6)
                if rest_start > after + 6:
                    var module = String(statement[byte=index:module_end])
                    var rest = _strip(String(statement[byte=rest_start:]))
                    if module.startswith("."):
                        raise Error(
                            "relative imports are not supported: " + statement
                        )
                    if rest.startswith("(") and rest.endswith(")"):
                        var inner = String(
                            rest[byte = 1 : max(1, rest.byte_length() - 1)]
                        )
                        rest = inner
                    var items = List[String]()
                    for part in rest.split(","):
                        items.append(_strip(String(part)))
                    # A parenthesized list can end with a comma.
                    if (
                        len(items) > 0
                        and items[len(items) - 1].byte_length() == 0
                    ):
                        _ = items.pop()
                    var names = List[String]()
                    for item in items:
                        var parsed = import_item(item)
                        if item != "*" and not (
                            parsed and parsed.value().find(".") < 0
                        ):
                            raise _unreadable(statement)
                        if parsed:
                            names.append(parsed.value())
                    if not is_dotted(module) or len(items) == 0:
                        raise _unreadable(statement)
                    found.append(Import(module, names^, False))
                    continue
        # `import\s+(.*)`
        var items = List[String]()
        if statement.startswith("import"):
            var start = _skip_space(bytes, 6)
            if start > 6:
                for part in String(statement[byte=start:]).split(","):
                    items.append(_strip(String(part)))
        if len(items) == 0:
            raise _unreadable(statement)
        for item in items:
            var parsed = import_item(item)
            if not parsed:
                raise _unreadable(statement)
            found.append(Import(parsed.value(), List[String](), True))
    return found^


def module_file(name: String, entry: String, known: Set[String]) -> String:
    """Return the file a dotted module name names, or an empty string.

    The compiler looks in the entry point's directory first, then in the
    root. The file is `a/b.mojo` or the package `a/b/__init__.mojo` for
    `a.b`. An ancestor package alone does not satisfy the name.

    Args:
        name: The dotted module name.
        entry: The entry point's directory, relative to the root.
        known: Every `.mojo` file, relative to the root.

    Returns:
        The file, or an empty string.
    """
    for base in [entry, String()]:
        var stem = (base + "/" if base else String()) + name.replace(".", "/")
        for candidate in [stem + ".mojo", stem + "/__init__.mojo"]:
            if candidate in known:
                return candidate
    return String()


def _join(root: String, name: String) -> String:
    """Return `Path(root) / name`: an absolute name stands alone."""
    if name.startswith("/"):
        return name
    return root + "/" + name


def probe_closure(root: String, known: Set[String]) raises -> List[String]:
    """Return the sorted files the probe reaches through its imports.

    Each import's own module must resolve to a file of its own: a missing
    module under an existing package is refused. A `std` or `max` module
    with no local file comes from the pinned SDK, which the toolchain string
    binds. A local file under either name is bound. The edges come from
    `tools._imports.resolve`, which also keeps the ancestor packages and the
    shadowing candidates, so the closure can only be larger than what the
    compiler reads.

    Args:
        root: The repository root.
        known: Every `.mojo` file, relative to the root.

    Returns:
        The files, sorted.

    Raises:
        Error: If an import cannot be read, is relative, or names a module
            that resolves to no file.
    """
    var entry = String("tools")
    var seen = Set[String]()
    seen.add(PROBE)
    var stack: List[String] = [PROBE]
    var entries: List[String] = [entry]
    while len(stack) > 0:
        var path = stack.pop()
        for found in imports_of(read_text(_join(root, path))):
            # A local file can shadow a toolchain package: the pinned
            # compiler reads a local max/sentinel.mojo for `max.sentinel`.
            # So every local candidate is bound, whatever the prefix. Only a
            # toolchain name with no local file may resolve to no file here;
            # the toolchain string binds the SDK.
            var top = String(found.module.split(".")[0])
            if (
                top != "std"
                and top != "max"
                and module_file(found.module, entry, known).byte_length() == 0
            ):
                raise Error(
                    "an anatomy probe import resolves to no module: "
                    + found.module
                    + " in "
                    + path
                )
            # A name after `import` is a submodule when its file exists, and
            # a symbol otherwise, which the compiler checks.
            var names: List[String] = [found.module]
            for name in found.names:
                names.append(found.module + "." + name)
            for name in names:
                for target in resolve(name, known, entries):
                    if not target in seen:
                        seen.add(target)
                        stack.append(target)
    return _sorted(seen)


def _sorted(items: Set[String]) -> List[String]:
    """Return a set's members in order."""
    var found = List[String]()
    for item in items:
        found.append(item)
    sort(found)
    return found^


def cited_inputs(text: String) raises -> Set[String]:
    """Return every source file the provenance inventory cites.

    Args:
        text: The inventory's JSON text.

    Returns:
        The cited paths.

    Raises:
        Error: If the text is not JSON or lacks `parameters` or
            `source_files`.
    """
    var tree = JsonTree()
    var inventory = tree.parse(text)
    var cited = Set[String]()
    for item in tree.items(tree.item(inventory, "parameters")):
        for name in tree.items(tree.item(item, "source_files")):
            cited.add(tree.text(name))
    return cited^


def bound_paths(root: String) raises -> List[String]:
    """Return the sorted inputs the anatomy report depends on.

    They are the probe's import closure as the pinned compiler resolves it,
    every source file the inventory cites, the inventory, and the code that
    computes this list. The closure is worked out again from the imports on
    every call, so a new import, module or shadowing file joins it.

    Args:
        root: The repository root.

    Returns:
        The paths, relative to the root, sorted.

    Raises:
        Error: If the probe or a cited input is missing, an import is
            relative or unreadable, or a local import resolves to no file.
    """
    var known = Set[String]()
    for path in mojo_files(root):
        known.add(path)
    if not PROBE in known:
        raise Error("the anatomy probe is missing: " + PROBE)
    var all = Set[String]()
    for path in probe_closure(root, known):
        all.add(path)
    var cited = cited_inputs(read_text(_join(root, INVENTORY)))
    for name in _sorted(cited):
        if not isfile(_join(root, name)):
            raise Error("an inventory-cited input is missing: " + name)
        all.add(name)
    for name in binding_code():
        if not isfile(_join(root, name)):
            raise Error("binding code is missing: " + name)
        all.add(name)
    all.add(INVENTORY)
    return _sorted(all)


def contract_text(
    binding: String, toolchain: String, flags: List[String]
) -> String:
    """Return the build contract as `json.dumps(..., sort_keys=True)`.

    Args:
        binding: The binding version.
        toolchain: The pinned compiler version.
        flags: The probe build flags.

    Returns:
        The JSON text.
    """
    var text = '{"binding": ' + quote_ascii(binding) + ', "flags": ['
    for index in range(len(flags)):
        if index > 0:
            text += ", "
        text += quote_ascii(flags[index])
    return text + '], "toolchain": ' + quote_ascii(toolchain) + "}"


struct Snapshot(Copyable, Movable):
    """The bound inputs, read once."""

    var digest: String
    """The source digest."""
    var names: List[String]
    """The bound paths, sorted."""
    var hashes: Dict[String, String]
    """Each bound path and its SHA-256."""
    var inventory: List[UInt8]
    """The exact inventory bytes."""

    def __init__(out self):
        """Start an empty snapshot."""
        self.digest = String()
        self.names = List[String]()
        self.hashes = Dict[String, String]()
        self.inventory = List[UInt8]()

    def same(self, other: Snapshot) -> Bool:
        """Return whether two snapshots read the same inputs.

        Args:
            other: The other snapshot.

        Returns:
            True for equal digests, hashes and inventory bytes.
        """
        if (
            self.digest != other.digest
            or self.names != other.names
            or self.inventory != other.inventory
        ):
            return False
        for name in self.names:
            if self.hashes.get(name) != other.hashes.get(name):
                return False
        return True

    def hash(self, name: String) raises -> String:
        """Return one bound file's SHA-256.

        Args:
            name: The bound path.

        Returns:
            The hexadecimal digest.

        Raises:
            Error: `'name'` when the path is not bound.
        """
        var found = self.hashes.get(name)
        if not found:
            raise Error("'" + name + "'")
        return found.value()


def source_snapshot(
    root: String,
    binding: String = BINDING_VERSION,
    toolchain: String = PINNED_TOOLCHAIN,
    flags: List[String] = build_flags(),
) raises -> Snapshot:
    """Read bound inputs once, retaining hashes and the exact inventory
    bytes.

    The pinned build contract is part of what the report depends on.

    Args:
        root: The repository root.
        binding: The binding version.
        toolchain: The pinned compiler version.
        flags: The probe build flags.

    Returns:
        The snapshot.

    Raises:
        Error: If the inputs cannot be bound or read.
    """
    var digest = Sha256()
    var contract = contract_text(binding, toolchain, flags)
    digest.update(contract.as_bytes())
    digest.update([UInt8(0)])
    var snapshot = Snapshot()
    for name in bound_paths(root):
        var content = Path(_join(root, name)).read_bytes()
        digest.update(name.as_bytes())
        digest.update([UInt8(0)])
        digest.update(content)
        digest.update([UInt8(0)])
        snapshot.names.append(name)
        snapshot.hashes[name] = sha256_hex(content)
        if name == INVENTORY:
            snapshot.inventory = content^
    snapshot.digest = digest^.hexdigest()
    return snapshot^


def source_digest(root: String) raises -> String:
    """Return the source digest of the bound inputs.

    Args:
        root: The repository root.

    Returns:
        The hexadecimal digest.

    Raises:
        Error: If the inputs cannot be bound or read.
    """
    return source_snapshot(root).digest


def file_sha256(path: String) raises -> String:
    """Return a file's SHA-256.

    Args:
        path: The file.

    Returns:
        The hexadecimal digest.

    Raises:
        Error: If the file cannot be read.
    """
    return sha256_hex(Path(path).read_bytes())


def sidecar(probe: String) -> String:
    """Return the provenance file beside a probe.

    Args:
        probe: The probe path.

    Returns:
        The path with `.provenance.json` added.
    """
    return probe + ".provenance.json"


def _read_bytes(path: String) raises -> List[UInt8]:
    """Return a file's bytes, with Python's message when it is missing."""
    if not exists(path):
        raise Error("[Errno 2] No such file or directory: " + py_repr(path))
    return Path(path).read_bytes()


def verify_report_inputs(
    root: String,
    probe: String,
    tree: JsonTree,
    provenance: Int,
    snapshot: Snapshot,
    metadata: List[UInt8],
) raises:
    """Reject observed input changes; this is not an atomic filesystem
    transaction.

    Args:
        root: The repository root.
        probe: The probe path.
        tree: The tree that holds the provenance.
        provenance: The probe provenance object.
        snapshot: The snapshot taken when the report began.
        metadata: The provenance file's bytes when the report began.

    Raises:
        Error: `report inputs changed during execution; rebuild before
            reporting` for any observed change.
    """
    var changed = Error(
        "report inputs changed during execution; rebuild before reporting"
    )
    var current: Snapshot
    try:
        current = source_snapshot(root)
    except:
        # The inputs were bindable when the report began.
        raise changed^
    if not current.same(snapshot) or not tree.is_text(
        tree.item(provenance, "source_sha256"), current.digest
    ):
        raise changed^
    if not tree.is_text(
        tree.item(provenance, "binary_sha256"), file_sha256(probe)
    ):
        raise changed^
    var now = _read_bytes(sidecar(probe))
    if now != metadata:
        raise changed^
    var scratch = JsonTree()
    var read = scratch.parse(String(from_utf8=Span(metadata)))
    if not equal(scratch, read, tree, provenance):
        raise changed^


# --- processes -----------------------------------------------------------------


def py_repr(text: String) -> String:
    """Return `repr()` of a string, as Python quotes it.

    Args:
        text: The string.

    Returns:
        The quoted string.
    """
    var quote = "'"
    if text.find("'") >= 0 and text.find('"') < 0:
        quote = '"'
    var out = String(quote)
    for codepoint in text.codepoints():
        var code = Int(codepoint.to_u32())
        if code == 92:
            out += "\\\\"
        elif chr(code) == quote:
            out += "\\" + quote
        elif code == 10:
            out += "\\n"
        elif code == 13:
            out += "\\r"
        elif code == 9:
            out += "\\t"
        elif code < 32 or code == 127:
            var hex = "0123456789abcdef"
            out += (
                "\\x"
                + String(hex[byte = code >> 4 : (code >> 4) + 1])
                + String(hex[byte = code & 15 : (code & 15) + 1])
            )
        else:
            out += chr(code)
    return out + quote


def command_repr(command: List[String]) -> String:
    """Return `repr()` of a command list.

    Args:
        command: The program and its arguments.

    Returns:
        The list as Python prints it.
    """
    var out = String("[")
    for index in range(len(command)):
        if index > 0:
            out += ", "
        out += py_repr(command[index])
    return out + "]"


def run_checked(
    command: List[String],
    timeout: Int,
    directory: String,
    mut output: String,
    mut errors: String,
) raises:
    """Run a program as `subprocess.run(check=True, timeout=...)` does.

    Args:
        command: The program and its arguments.
        timeout: The time limit in seconds.
        directory: The working directory, or empty for the current one.
        output: Receives the standard output.
        errors: Receives the standard error.

    Raises:
        Error: Python's message for a missing program, a timeout or a
            nonzero exit status.
    """
    var result = run_program(
        command, Float64(timeout), merge_errors=False, directory=directory
    )
    if result.timed_out:
        raise Error(
            "Command '"
            + command_repr(command)
            + "' timed out after "
            + String(timeout)
            + " seconds"
        )
    if result.status == 127 and result.output.byte_length() == 0:
        raise Error(
            "[Errno 2] No such file or directory: " + py_repr(command[0])
        )
    if result.status == 126 and result.output.byte_length() == 0:
        raise Error("[Errno 13] Permission denied: " + py_repr(command[0]))
    output = result.output
    errors = result.errors
    if result.status != 0:
        raise Error(
            "Command '"
            + command_repr(command)
            + "' returned non-zero exit status "
            + String(result.status)
            + "."
        )


def absolute(path: String) raises -> String:
    """Return a normalized absolute path, as `os.path.abspath` does.

    Args:
        path: A path.

    Returns:
        The absolute path, with `.` and `..` resolved by name.

    Raises:
        Error: If the current directory cannot be found.
    """
    var full = path if path.startswith("/") else realpath(".") + "/" + path
    var parts = List[String]()
    for part in full.split("/"):
        var name = String(part)
        if name.byte_length() == 0 or name == ".":
            continue
        if name == "..":
            if len(parts) > 0:
                _ = parts.pop()
            continue
        parts.append(name)
    return "/" + "/".join(parts)


def resolve_path(path: String) raises -> String:
    """Return a path with its links resolved, as `Path.resolve()` does.

    Args:
        path: A path, which need not exist.

    Returns:
        The absolute path.

    Raises:
        Error: If the current directory cannot be found.
    """
    var full = absolute(path)
    if exists(full):
        return realpath(full)
    var slash = full.rfind("/")
    var parent = String(full[byte=:slash]) if slash > 0 else String("/")
    if exists(parent):
        var real = realpath(parent)
        return (real if real != "/" else String()) + full[byte=slash:]
    return full


def relpath(path: String, start: String) raises -> String:
    """Return `os.path.relpath(path, start)`.

    Args:
        path: A path.
        start: The directory to be relative to.

    Returns:
        The relative path.

    Raises:
        Error: If the current directory cannot be found.
    """
    var target = absolute(path).split("/")
    var base = absolute(start).split("/")
    var common = 0
    while (
        common < len(target)
        and common < len(base)
        and target[common] == base[common]
    ):
        common += 1
    var parts = List[String]()
    for index in range(common, len(base)):
        if String(base[index]).byte_length() > 0:
            parts.append("..")
    for index in range(common, len(target)):
        if String(target[index]).byte_length() > 0:
            parts.append(String(target[index]))
    if len(parts) == 0:
        return "."
    return "/".join(parts)


def _parent(path: String) -> String:
    """Return a path's directory, or empty for none."""
    var slash = path.rfind("/")
    if slash < 0:
        return String()
    if slash == 0:
        return "/"
    return String(path[byte=:slash])


def prepare_probe(
    mut tree: JsonTree, root: String, probe: String, mojo: String, build: Bool
) raises -> Int:
    """Build the source-bound probe, or check the one already built.

    Args:
        tree: The tree for the provenance record.
        root: The repository root, absolute.
        probe: The probe path, absolute.
        mojo: The compiler.
        build: True to build the probe.

    Returns:
        The provenance record.

    Raises:
        Error: For another compiler version, a failed build, a source change
            during the build, or a missing or stale probe.
    """
    var digest = source_digest(root)
    var metadata = sidecar(probe)
    if build:
        var output = String()
        var errors = String()
        run_checked([mojo, "--version"], 600, String(), output, errors)
        var version = _strip(output)
        if version != PINNED_TOOLCHAIN:
            raise Error("the report requires pinned Mojo 1.1.0 (8189361e)")
        var parent = _parent(probe)
        if parent.byte_length() > 0:
            makedirs(parent, exist_ok=True)
        # Use the repository's relative invocation. The pinned compiler can
        # crash for the equivalent all-absolute include/source/output form.
        # Bound compiler concurrency: the pinned parallel build can crash
        # during probe compilation. Keep this setting in the provenance.
        var command: List[String] = [mojo, "build"]
        command.extend(build_flags())
        command.extend(["-I", ".", PROBE, "-o", relpath(probe, root)])
        run_checked(command, 600, root, output, errors)
        print(output, end="")
        print(errors, end="", file=stderr)
        if source_digest(root) != digest:
            raise Error(
                "source changed during compilation; rebuild before reporting"
            )
        var record = tree.object()
        tree.set_text(record, "source_sha256", digest)
        tree.set_text(record, "toolchain", version)
        tree.set(record, "flags", tree.strings(build_flags()))
        tree.set_text(record, "binary_sha256", file_sha256(probe))
        Path(metadata).write_text(tree.dumps(record) + "\n")
        return record
    if not isfile(probe) or not isfile(metadata):
        raise Error("build the source-bound probe with --build first")
    var record = tree.parse(read_text(metadata))
    var flags = tree.get(record, "flags")
    var pinned = tree.kind(flags) == ARRAY and tree.length(flags) == len(
        build_flags()
    )
    if pinned:
        var expected = build_flags()
        for index in range(len(expected)):
            if not tree.is_text(tree.at(flags, index), expected[index]):
                pinned = False
    if not tree.is_text(tree.get(record, "toolchain"), PINNED_TOOLCHAIN) or (
        not pinned
    ):
        raise Error(
            "probe provenance must record the exact pinned compiler and build"
            " flags"
        )
    if not tree.is_text(tree.get(record, "source_sha256"), digest) or (
        not tree.is_text(tree.get(record, "binary_sha256"), file_sha256(probe))
    ):
        raise Error("probe provenance is stale; rebuild with --build")
    return record


@fieldwise_init
struct Spec(Copyable, Movable):
    """The canonical template a probe measures."""

    var stature_m: Float64
    """The stature, in meters."""
    var sex: String
    """`male` or `female`."""
    var side: String
    """`right` or `left`."""
    var athleticism: String
    """`untoned` or `toned`."""


trait Prober:
    """Something that answers probe requests with JSON records."""

    def rows(
        mut self,
        mut tree: JsonTree,
        probe: String,
        mode: String,
        part: String,
        step: Num,
    ) raises -> List[Int]:
        """Run one probe request.

        Args:
            tree: The tree for the records.
            probe: The probe path.
            mode: The probe mode.
            part: The part or request.
            step: The grid step, in millimeters.

        Returns:
            The records.

        Raises:
            Error: If the request fails.
        """
        ...


struct NativeProbe(Prober):
    """The built probe, run under the five-second limit."""

    var spec: Spec
    """The template."""
    var root: String
    """The working directory."""
    var require: Bool
    """True to refuse a request that returns no record."""

    def __init__(out self, spec: Spec, root: String, require: Bool):
        """Run the probe for one template.

        Args:
            spec: The template.
            root: The working directory.
            require: True to refuse a request that returns no record.
        """
        self.spec = spec.copy()
        self.root = root
        self.require = require

    def rows(
        mut self,
        mut tree: JsonTree,
        probe: String,
        mode: String,
        part: String,
        step: Num,
    ) raises -> List[Int]:
        """Run one probe request; parse its JSON lines.

        Args:
            tree: The tree for the records.
            probe: The probe path.
            mode: The probe mode.
            part: The part or request.
            step: The grid step, in millimeters.

        Returns:
            The records.

        Raises:
            Error: If the probe fails, times out, prints a line that is not
                JSON or a value that is not finite, or prints nothing when
                a record is required.
        """
        var command: List[String] = [
            probe,
            mode,
            part,
            step.text(),
            python_repr(self.spec.stature_m),
            self.spec.sex,
            self.spec.side,
            self.spec.athleticism,
        ]
        var output = String()
        var errors = String()
        run_checked(command, 5, self.root, output, errors)
        var found = List[Int]()
        for line in split_lines(output):
            if _strip(line).byte_length() > 0:
                found.append(tree.parse(line))
        if self.require and len(found) == 0:
            raise Error(mode + " probe produced no evidence")
        for row in found:
            finite_tree(tree, row)
        return found^


# --- the pair catalog ----------------------------------------------------------


@fieldwise_init
struct Component(Copyable, Movable):
    """One validated catalog component."""

    var node: Int
    """The component record."""
    var component_id: String
    """The stable identity."""
    var label: String
    """The display label."""
    var family: String
    """The part family."""
    var low: List[Float64]
    """The box's low corner, in meters."""
    var high: List[Float64]
    """The box's high corner, in meters."""

    def region(self) -> String:
        """Return the component's region, `leg` or `foot`.

        Returns:
            The first part of the identity.
        """
        var slash = self.component_id.find("/")
        if slash < 0:
            return self.component_id
        return String(self.component_id[byte=:slash])


def _unhashable(tree: JsonTree, node: Int) raises:
    """Refuse a list or a dict where Python hashes a value."""
    var kind = tree.kind(node)
    if kind == ARRAY or kind == OBJECT:
        raise Error("unhashable type: '" + type_name(tree, node) + "'")


def validate_catalog(
    mut tree: JsonTree, rows: List[Int]
) raises -> List[Component]:
    """Refuse incomplete catalogs, aliases, invalid bounds and frame drift.

    Args:
        tree: The tree.
        rows: The component records, in catalog order.

    Returns:
        The validated components. Each record gains its frame and geometry
        source.

    Raises:
        Error: For a catalog that breaks the named-part contract.
    """
    var total = 0
    for family in pair_families():
        total += family[1]
    if len(rows) != total:
        raise Error(
            "canonical pair catalog must contain all 134 named components"
        )
    var counts = Dict[String, Int]()
    var identities = Set[String]()
    var labels = Set[String]()
    var families = List[String]()
    for family in pair_families():
        families.append(family[0])
    var found = List[Component]()
    for index in range(len(rows)):
        var row = rows[index]
        var identity_node = tree.get(row, "component_id")
        var identity = String()
        if identity_node != NOTHING:
            if tree.kind(identity_node) != STRING:
                raise Error("component identity must be text")
            identity = tree.text(identity_node)
        var region = String(identity.split("/")[0])
        var family_node = tree.get(row, "family")
        var label_node = tree.get(row, "label")
        var bad = (
            not tree.is_text(tree.get(row, "record"), "component")
            or not tree.is_int(tree.get(row, "index"))
            or tree.int_value(tree.get(row, "index")) != index
            or not (region == "leg" or region == "foot")
        )
        if not bad:
            _unhashable(tree, family_node)
            bad = not _in(tree, family_node, families)
        if not bad:
            var family = tree.text(family_node)
            bad = not identity.startswith(region + "/" + family + "/") or (
                identity in identities
            )
        if not bad:
            _unhashable(tree, label_node)
            bad = (
                (
                    tree.kind(label_node) == STRING
                    and tree.text(label_node) in labels
                )
                or tree.kind(label_node) != STRING
                or tree.text(label_node).byte_length() == 0
            )
        if bad:
            raise Error("invalid or duplicate canonical component identity")
        var family = tree.text(family_node)
        var low = vector(tree, tree.get(row, "low_m"), "low_m")
        var high = vector(tree, tree.get(row, "high_m"), "high_m")
        for axis in range(3):
            if low[axis] >= high[axis]:
                raise Error(
                    "canonical component bounds must be strictly ordered"
                )
        var translation = vector(
            tree, tree.get(row, "translation_m"), "translation_m"
        )
        # Leg muscles, knee tissues and neural/vascular/lymphatic fields
        # are already in the knee frame. Only local bones and foot translate.
        if (
            region == "leg"
            and family != "bone"
            and (
                translation[0] != 0
                or translation[1] != 0
                or translation[2] != 0
            )
        ):
            raise Error("unexpected canonical frame translation")
        tree.set_text(row, "frame_id", PAIR_FRAME)
        tree.set_text(
            row,
            "geometry_source",
            "canonical physical field, not display field",
        )
        var key = region + "/" + family
        counts[key] = counts.get(key).or_else(0) + 1
        identities.add(identity)
        var label = tree.text(label_node)
        labels.add(label)
        found.append(Component(row, identity, label, family, low^, high^))
    var matches = identities == pair_component_ids()
    var expected = 0
    for region in ["leg", "foot"]:
        for family in pair_region_counts(region):
            expected += 1
            if counts.get(region + "/" + family[0]).or_else(0) != family[1]:
                matches = False
    if len(counts) != expected:
        matches = False
    if not matches:
        raise Error(
            "canonical pair catalog does not match the named-part contract"
        )
    var ankles = List[List[Float64]]()
    for component in found:
        if component.component_id.startswith("foot/"):
            var translation = _numbers(
                tree, tree.item(component.node, "translation_m")
            )
            var seen = False
            for ankle in ankles:
                var same = len(ankle) == len(translation)
                if same:
                    for axis in range(len(ankle)):
                        if ankle[axis] != translation[axis].value:
                            same = False
                if same:
                    seen = True
            if not seen:
                var values = List[Float64]()
                for value in translation:
                    values.append(value.value)
                ankles.append(values^)
    if len(ankles) != 1:
        raise Error(
            "all foot fields must use the same assembled ankle translation"
        )
    return found^


def pair_identity(first: Component, second: Component) -> String:
    """Build a label-independent, order-independent canonical pair identity.

    Args:
        first: A component.
        second: Another component.

    Returns:
        The identity.
    """
    return "canonical/lower-limb/" + _sorted_pair(
        first.component_id, second.component_id
    )


def box_low(first: Component, second: Component, axis: Int) -> Float64:
    """Return the low side of two components' box intersection on an axis.

    Args:
        first: A component.
        second: Another component.
        axis: 0, 1 or 2.

    Returns:
        The larger of the two low sides.
    """
    return max(first.low[axis], second.low[axis])


def box_high(first: Component, second: Component, axis: Int) -> Float64:
    """Return the high side of two components' box intersection on an axis.

    Args:
        first: A component.
        second: Another component.
        axis: 0, 1 or 2.

    Returns:
        The smaller of the two high sides.
    """
    return min(first.high[axis], second.high[axis])


def pair_box_volume(first: Component, second: Component) -> Float64:
    """Return the volume of two components' box intersection.

    Args:
        first: A component.
        second: Another component.

    Returns:
        The volume, zero for disjoint boxes.
    """
    var volume = 1.0
    for axis in range(3):
        var side = box_high(first, second, axis) - box_low(first, second, axis)
        volume = product(volume, side if side > 0 else 0.0)
    return volume


def legacy_pair_group(first: Component, second: Component) -> String:
    """Return the legacy diagnostic group of a pair.

    Args:
        first: A component.
        second: Another component.

    Returns:
        `bones`, `knee`, or an empty string for a pair with none.
    """
    if first.family == "bone" and second.family == "bone":
        return "bones"
    var knee = first.family == "knee" or second.family == "knee"
    var other = (first.family == "knee" or first.family == "bone") and (
        second.family == "knee" or second.family == "bone"
    )
    if (first.family == "knee" and second.family == "knee") or (
        knee
        and other
        and first.component_id.startswith("leg/")
        and second.component_id.startswith("leg/")
    ):
        return "knee"
    return String()


@fieldwise_init
struct PlanEntry(Copyable, Movable):
    """One unordered catalog pair and its execution status."""

    var pair_id: String
    """The canonical pair identity."""
    var first_id: String
    """The first component's identity."""
    var second_id: String
    """The second component's identity."""
    var klass: String
    """The sorted families, joined by `|`."""
    var status: String
    """`checked` or `intentionally_omitted`."""
    var first: Int
    """The first component's catalog index."""
    var second: Int
    """The second component's catalog index."""
    var legacy_group: String
    """`bones`, `knee`, or empty."""
    var reason: String
    """Why the pair was omitted, or empty."""
    var diagnostic_id: String
    """The legacy diagnostic identity, or empty."""

    def put(self, mut tree: JsonTree) raises -> Int:
        """Add the entry to a tree as the inventory records it.

        Args:
            tree: The tree.

        Returns:
            The new object.

        Raises:
            Error: Never for an object.
        """
        var node = tree.object()
        tree.set_text(node, "pair_id", self.pair_id)
        tree.set_text(node, "first_id", self.first_id)
        tree.set_text(node, "second_id", self.second_id)
        tree.set_text(node, "class", self.klass)
        tree.set_text(node, "status", self.status)
        if self.reason.byte_length() > 0:
            tree.set_text(node, "reason", self.reason)
        if self.diagnostic_id.byte_length() > 0:
            tree.set_text(node, "diagnostic_id", self.diagnostic_id)
        return node


def pair_plan(
    catalog: List[Component], scope: String
) raises -> List[PlanEntry]:
    """Enumerate every unordered pair; representative selection is explicit.

    Args:
        catalog: The validated components.
        scope: `full` or `representative`.

    Returns:
        The plan, in catalog order.

    Raises:
        Error: For an unknown scope.
    """
    if scope != "full" and scope != "representative":
        raise Error("unknown pair scope")
    var plan = List[PlanEntry]()
    var scores = Dict[String, Float64]()
    var chosen = Dict[String, String]()
    for i in range(len(catalog)):
        for j in range(i + 1, len(catalog)):
            var family = _sorted_pair(catalog[i].family, catalog[j].family)
            var old = legacy_pair_group(catalog[i], catalog[j])
            var identity = pair_identity(catalog[i], catalog[j])
            plan.append(
                PlanEntry(
                    identity,
                    catalog[i].component_id,
                    catalog[j].component_id,
                    family,
                    "checked",
                    i,
                    j,
                    old,
                    String(),
                    String(),
                )
            )
            if old.byte_length() == 0:
                var key = (
                    family
                    + "\n"
                    + _sorted_pair(catalog[i].region(), catalog[j].region())
                )
                var score = pair_box_volume(catalog[i], catalog[j])
                # Prefer the largest intersecting box in each region/class.
                # Ties keep catalog order. This is reproducible, not a claim
                # that this pair is the worst physical overlap.
                var best = scores.get(key)
                if not best or score > best.value():
                    scores[key] = score
                    chosen[key] = identity
    var selected = Set[String]()
    for entry in chosen.items():
        selected.add(entry.value)
    if scope == "representative":
        for index in range(len(plan)):
            if (
                plan[index].legacy_group.byte_length() == 0
                and not plan[index].pair_id in selected
            ):
                plan[index].status = "intentionally_omitted"
                plan[
                    index
                ].reason = "representative run; executable in full scope"
    return plan^


def pair_batches(
    plan: List[PlanEntry], catalog: List[Component], step_mm: Num
) raises -> List[List[Int]]:
    """Bound each process request; the native preflight is authoritative.

    Args:
        plan: The pair plan.
        catalog: The validated components.
        step_mm: The grid step, in millimeters.

    Returns:
        Each batch, as plan positions of contiguous pairs.

    Raises:
        Error: For a step that is not 2 through 20 mm, or a pair over the
            work budget.
    """
    var step = finite_value(step_mm.value, "pair step") / 1000
    if not (0.002 <= step and step <= 0.020):
        raise Error("pair grid step must be 2 through 20 mm")
    var batches = List[List[Int]]()
    var batch = List[Int]()
    var work = 0
    for index in range(len(plan)):
        if (
            plan[index].status != "checked"
            or plan[index].legacy_group.byte_length() > 0
        ):
            continue
        var first = plan[index].first
        var second = plan[index].second
        var cells = 1
        for axis in range(3):
            var low = box_low(catalog[first], catalog[second], axis)
            var high = box_high(catalog[first], catalog[second], axis)
            if high <= low:
                cells = 0
        if cells != 0:
            for axis in range(3):
                var low = box_low(catalog[first], catalog[second], axis)
                var high = box_high(catalog[first], catalog[second], axis)
                cells *= Int(ceil((high - low) / step))
        if cells > 2_000_000:
            raise Error(
                "pair exceeds the work budget: "
                + plan[index].pair_id
                + "; no complete report was produced"
            )
        var contiguous = len(batch) > 0
        if contiguous:
            var last = batch[len(batch) - 1]
            contiguous = (
                plan[last].first == first and plan[last].second == second - 1
            )
        if len(batch) > 0 and (
            not contiguous or len(batch) >= 16 or work + cells > 250_000
        ):
            batches.append(batch^)
            batch = List[Int]()
            work = 0
        batch.append(index)
        work += cells
    if len(batch) > 0:
        batches.append(batch^)
    return batches^


def validate_pair_row(
    mut tree: JsonTree, row: Int, first: Component, second: Component
) raises -> Int:
    """Validate probe protocol and retain unmeasured witnesses as unknown.

    Args:
        tree: The tree.
        row: The pair record.
        first: The first component.
        second: The second component.

    Returns:
        The same record, with its identity and allowance fields.

    Raises:
        Error: For another component, bad counts, or evidence outside its
            box or inconsistent with itself.
    """
    if (
        not tree.is_text(tree.get(row, "record"), "pair")
        or not tree.is_text(tree.get(row, "first_id"), first.component_id)
        or not tree.is_text(tree.get(row, "second_id"), second.component_id)
        or not tree.is_text(tree.get(row, "first"), first.label)
        or not tree.is_text(tree.get(row, "second"), second.label)
    ):
        raise Error("pair probe returned a different component")
    for key in ["samples", "overlap_samples"]:
        var value = tree.get(row, key)
        if not tree.is_int(value) or not (
            0 <= tree.int_value(value) and tree.int_value(value) <= 2_000_000
        ):
            raise Error("pair counts must be bounded integers")
    var samples = tree.int_value(tree.item(row, "samples"))
    var overlap = tree.int_value(tree.item(row, "overlap_samples"))
    if overlap > samples:
        raise Error("overlap count exceeds sampled count")
    var gap = finite(tree, tree.get(row, "bounds_gap_m"), "bounds gap")
    var volume = finite(
        tree, tree.get(row, "overlap_volume_m3"), "overlap volume"
    )
    var witness = finite(
        tree, tree.get(row, "signed_field_witness_m"), "field witness"
    )
    var box_volume = pair_box_volume(first, second)
    if gap < 0 or volume < 0 or volume > product(box_volume, 1.00002) + 1e-12:
        raise Error("pair evidence exceeds its conservative box")
    if (
        (samples == 0) != (box_volume == 0)
        or (samples == 0 and (overlap != 0 or volume != 0 or witness != 0))
        or (samples > 0 and (witness < 0) != (overlap > 0))
        or (overlap == 0 and volume != 0)
        or (overlap > 0 and (volume <= 0 or witness >= 0))
        or (gap > 0 and samples != 0)
    ):
        raise Error("inconsistent pair evidence")
    if samples == 0:
        tree.set_null(row, "signed_field_witness_m")
    tree.set_text(row, "frame_id", PAIR_FRAME)
    tree.set_text(row, "pair_id", pair_identity(first, second))
    tree.set_flag(row, "allowlist_applied", False)
    tree.set(row, "allowed_positive_overlap_volume_m3", tree.integer(0))
    tree.set_text(
        row, "geometry_kind", "implicit component envelope intersection"
    )
    tree.set_text(
        row,
        "contact_intent",
        (
            "unknown; attachment or shared centerline does not establish a"
            " volume allowance"
        ),
    )
    return row


def _excluded(
    mut tree: JsonTree,
    identity: String,
    status: String,
    selection: String,
    reason: String,
    bound: String,
) raises -> Int:
    """Return one excluded-domain object."""
    var node = tree.object()
    tree.set_text(node, "id", identity)
    tree.set_text(node, "status", status)
    tree.set_text(node, "selection", selection)
    tree.set_text(node, "reason", reason)
    if bound.byte_length() > 0:
        tree.set_text(node, "allowance_bound", bound)
    return node


def collect_pair_diagnostics[
    P: Prober
](
    mut tree: JsonTree,
    mut prober: P,
    probe: String,
    step_mm: Num,
    scope: String,
    legacy: Int,
) raises -> Tuple[List[Int], Int]:
    """Execute a complete selected plan or fail, never drop costly pairs.

    Args:
        tree: The tree.
        prober: The probe runner.
        probe: The probe path.
        step_mm: The grid step, in millimeters.
        scope: `full` or `representative`.
        legacy: The annotated legacy diagnostic groups.

    Returns:
        The measured pair records and the new pair inventory.

    Raises:
        Error: For an invalid catalog, an incomplete or extra legacy
            inventory, or a batch that omits or adds a measurement.
    """
    var catalog = validate_catalog(
        tree, prober.rows(tree, probe, "pairs", "catalog", step_mm)
    )
    var plan = pair_plan(catalog, scope)
    var groups: List[String] = ["bones", "knee"]
    var legacy_rows = List[Dict[String, String]]()
    for group in groups:
        var found = Dict[String, String]()
        for row in tree.items(tree.item(legacy, group)):
            if tree.is_text(tree.item(row, "record"), "pair"):
                var key = _pair_key(
                    tree.text(tree.item(row, "first")),
                    tree.text(tree.item(row, "second")),
                )
                found[key] = tree.text(tree.item(row, "pair_id"))
        legacy_rows.append(found^)
    var used = List[Set[String]]()
    used.append(Set[String]())
    used.append(Set[String]())
    for index in range(len(plan)):
        var group = plan[index].legacy_group
        if group.byte_length() > 0:
            var key = _pair_key(
                catalog[plan[index].first].label,
                catalog[plan[index].second].label,
            )
            var slot = 0 if group == "bones" else 1
            var found = legacy_rows[slot].get(key)
            if not found:
                raise Error("legacy diagnostic inventory is incomplete")
            plan[index].diagnostic_id = found.value()
            used[slot].add(key)
    for slot in range(2):
        if len(used[slot]) != len(legacy_rows[slot]):
            raise Error("legacy diagnostic inventory contains unplanned pairs")
    var rows = List[Int]()
    for batch in pair_batches(plan, catalog, step_mm):
        var request = (
            String(plan[batch[0]].first)
            + ":"
            + String(plan[batch[0]].second)
            + ":"
            + String(plan[batch[len(batch) - 1]].second + 1)
        )
        var found = prober.rows(tree, probe, "pairs", request, step_mm)
        if len(found) != len(batch):
            raise Error("pair batch omitted or added a measurement")
        for position in range(len(found)):
            var entry = batch[position]
            rows.append(
                validate_pair_row(
                    tree,
                    found[position],
                    catalog[plan[entry].first],
                    catalog[plan[entry].second],
                )
            )
    var class_names = List[String]()
    var class_counts = Dict[String, List[Int]]()
    for entry in plan:
        if not entry.klass in class_counts:
            class_names.append(entry.klass)
            class_counts[entry.klass] = [0, 0, 0]
        var slot = 0 if entry.status == "checked" else 1
        class_counts[entry.klass][slot] += 1
    var inventory = tree.object()
    tree.set(inventory, "schema_version", tree.integer(1))
    tree.set_text(
        inventory,
        "scope",
        (
            "all unordered distinct pairs among 134 named selected-side"
            " lower-limb canonical component fields"
        ),
    )
    tree.set_text(inventory, "run_scope", scope)
    tree.set_text(inventory, "frame_id", PAIR_FRAME)
    var components = tree.array()
    for component in catalog:
        tree.append(components, component.node)
    tree.set(inventory, "components", components)
    var pairs = tree.array()
    var complete = True
    for entry in plan:
        tree.append(pairs, entry.put(tree))
        if entry.status != "checked":
            complete = False
    tree.set(inventory, "pairs", pairs)
    tree.set(inventory, "total_pairs", tree.integer(len(plan)))
    var classes = tree.object()
    for name in class_names:
        var counts = tree.object()
        var values = class_counts[name].copy()
        tree.set(counts, "checked", tree.integer(values[0]))
        tree.set(counts, "intentionally_omitted", tree.integer(values[1]))
        tree.set(counts, "unsupported", tree.integer(values[2]))
        tree.set(classes, name, counts)
    tree.set(inventory, "classes", classes)
    var additional = tree.array()
    var spine = tree.get(legacy, "spine")
    if spine != NOTHING:
        for row in tree.items(spine):
            var item = tree.object()
            var record = tree.item(row, "record")
            if tree.is_text(record, "pair"):
                tree.set(
                    item, "diagnostic_id", tree.clone(tree.item(row, "pair_id"))
                )
            else:
                tree.set(
                    item,
                    "diagnostic_id",
                    tree.clone(tree.item(row, "endplane_id")),
                )
            tree.set(item, "record", tree.clone(record))
            tree.set_text(item, "status", "checked")
            tree.set_text(item, "frame_id", SPINE_FRAME)
            tree.append(additional, item)
    tree.set(inventory, "additional_checked_diagnostics", additional)
    tree.set_flag(inventory, "all_catalog_pairs_checked", complete)
    tree.set_flag(inventory, "selected_execution_complete", True)
    tree.set(inventory, "positive_volume_attachment_allowances", tree.array())
    tree.set(
        inventory,
        "unknowns",
        tree.strings(
            [
                (
                    "Individual dermis/fat material interfaces are not"
                    " modeled by these fields."
                ),
                (
                    "Anatomical attachment volumes and biological"
                    " calibration tolerances are unknown."
                ),
                (
                    "Thin overlap can be missed even when conservative"
                    " boxes intersect."
                ),
            ]
        ),
    )
    var excluded = tree.array()
    tree.append(
        excluded,
        _excluded(
            tree,
            "self-construction-unions",
            "intentionally_omitted",
            (
                "each catalog component paired with itself or its internal"
                " primitives"
            ),
            (
                "One named field already represents its construction union."
                " This rule never exempts two distinct catalog fields."
            ),
            (
                "inside that one named field only; zero exemption for"
                " distinct-pair positive volume"
            ),
        ),
    )
    tree.append(
        excluded,
        _excluded(
            tree,
            "skin-envelope-domain",
            "intentionally_omitted",
            (
                "skin envelope against its contained components and the"
                " leg/foot envelope union"
            ),
            (
                "The envelope is an occupancy domain, not a separate internal"
                " material. Containment is not independently validated here."
            ),
            (
                "domain bookkeeping only; no dermis collision or clearance"
                " allowance"
            ),
        ),
    )
    tree.append(
        excluded,
        _excluded(
            tree,
            "unresolved-material-interfaces",
            "unsupported",
            (
                "dermis/fat partitions, hair, individual primitives inside"
                " named grouped fields"
            ),
            (
                "No separate canonical pair contract is supplied; this does not"
                " count as checked coverage."
            ),
            String(),
        ),
    )
    tree.append(
        excluded,
        _excluded(
            tree,
            "outside-lower-limb-and-neighbor-spine",
            "unsupported",
            (
                "other body regions, cross-region whole-body pairs, nonneighbor"
                " spine pairs, dynamic and visual/rig/bake pairs"
            ),
            (
                "Outside this static selected-side catalog; no whole-body,"
                " contact, clinical or safety claim."
            ),
            String(),
        ),
    )
    tree.set(inventory, "excluded_domains", excluded)
    return (rows^, inventory)


# --- the report ----------------------------------------------------------------


struct Options(Copyable, Movable):
    """The parsed command line."""

    var status: Int
    """0 to run, 2 for an argument error, or -1 after `--help`."""
    var message: String
    """The usage error or help text."""
    var build: Bool
    """True to build the probe."""
    var mojo: String
    """The compiler."""
    var probe: String
    """The probe path."""
    var output: String
    """The report path."""
    var steps_mm: List[Num]
    """The grid steps, in millimeters."""
    var stature_m: Float64
    """The stature, in meters."""
    var sex: String
    """`male` or `female`."""
    var side: String
    """`right` or `left`."""
    var athleticism: String
    """`untoned` or `toned`."""
    var use: String
    """The requested use."""
    var pair_scope: String
    """`full` or `representative`."""

    def __init__(out self):
        """Start with the defaults."""
        self.status = 0
        self.message = String()
        self.build = False
        self.mojo = ".venv/bin/mojo"
        self.probe = ".cache/anatomy-probe"
        self.output = String()
        self.steps_mm = [Num(20, True), Num(10, True), Num(5, True)]
        self.stature_m = 1.8288
        self.sex = "male"
        self.side = "right"
        self.athleticism = "untoned"
        self.use = "template-estimate"
        self.pair_scope = "full"

    def spec(self) -> Spec:
        """Return the template the options select.

        Returns:
            The template.
        """
        return Spec(self.stature_m, self.sex, self.side, self.athleticism)


def _choices(name: String) -> List[String]:
    """Return the choices of an option, or none for a free option."""
    if name == "--sex":
        return ["male", "female"]
    if name == "--side":
        return ["right", "left"]
    if name == "--athleticism":
        return ["untoned", "toned"]
    if name == "--use":
        return uses()
    if name == "--pair-scope":
        return ["full", "representative"]
    return []


def _negative_number(word: String) -> Bool:
    """Return whether a word looks like `-5` or `-.5`, which `argparse`
    reads as a value."""
    var bytes = word.as_bytes()
    if len(bytes) < 2 or bytes[0] != 45:
        return False
    var digits = 0
    var point = False
    for index in range(1, len(bytes)):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            digits += 1
        elif byte == 46 and not point:
            point = True
        else:
            return False
    return digits > 0 and (not point or bytes[len(bytes) - 1] != 46)


def _option_like(word: String) -> Bool:
    """Return whether `argparse` reads a word as an option."""
    return (
        word.startswith("-")
        and word.byte_length() > 1
        and not _negative_number(word)
    )


def parse_float_argument(text: String) raises -> Float64:
    """Return `float(text)` for a command-line value.

    Args:
        text: The value.

    Returns:
        The double.

    Raises:
        Error: If the text is not a number.
    """
    return parse_float(text)


def parse_options(
    arguments: List[String],
    program: String = PROGRAM,
    usage: String = USAGE,
    help: String = HELP,
    report_options: Bool = True,
) -> Options:
    """Parse the command line as the Python tool's `argparse` parser did.

    A unique prefix of a long option selects it, and `--name=value` gives
    its value.

    Args:
        arguments: The arguments, without the program name.
        program: The program name for error messages.
        usage: The usage text.
        help: The text after the usage for `--help`.
        report_options: True for this tool's options; False for the overlap
            tool, which takes only `--build`, `--mojo`, `--probe` and
            `--output`.

    Returns:
        The options. A nonzero status carries the text to print.
    """
    var options = Options()
    var names: List[String] = [
        "--help",
        "--build",
        "--mojo",
        "--probe",
        "--output",
    ]
    if report_options:
        names.extend(
            [
                "--steps-mm",
                "--stature-m",
                "--sex",
                "--side",
                "--athleticism",
                "--use",
                "--pair-scope",
            ]
        )
    var unknown = List[String]()
    var has_output = False
    var problem = String()
    var index = 0
    var positional = False
    while index < len(arguments) and not problem:
        var word = arguments[index]
        index += 1
        if positional or not _option_like(word):
            unknown.append(word)
            continue
        if word == "--":
            positional = True
            continue
        if word == "-h":
            word = "--help"
        if not word.startswith("--"):
            unknown.append(word)
            continue
        var value = Optional[String]()
        var equals = word.find("=")
        var key = word
        if equals >= 0:
            key = String(word[byte=:equals])
            value = String(word[byte = equals + 1 :])
        var matches = List[String]()
        for name in names:
            if name == key:
                matches = [name]
                break
            if name.startswith(key):
                matches.append(name)
        if len(matches) == 0:
            unknown.append(word)
            continue
        if len(matches) > 1:
            problem = (
                "ambiguous option: "
                + key
                + " could match "
                + ", ".join(matches)
            )
            break
        var name = matches[0]
        if name == "--help":
            options.status = -1
            options.message = usage + help
            return options^
        if name == "--build":
            if value:
                problem = (
                    "argument --build: ignored explicit argument "
                    + py_repr(value.value())
                )
                break
            options.build = True
            continue
        var values = List[String]()
        if value:
            values.append(value.value())
        elif name == "--steps-mm":
            while index < len(arguments) and not _option_like(arguments[index]):
                if arguments[index] == "--":
                    break
                values.append(arguments[index])
                index += 1
            if len(values) == 0:
                problem = "argument --steps-mm: expected at least one argument"
                break
        else:
            if index >= len(arguments) or _option_like(arguments[index]):
                problem = "argument " + name + ": expected one argument"
                break
            values.append(arguments[index])
            index += 1
        var choices = _choices(name)
        if len(choices) > 0 and not _contains(choices, values[0]):
            var listed = List[String]()
            for choice in choices:
                listed.append(py_repr(choice))
            problem = (
                "argument "
                + name
                + ": invalid choice: "
                + py_repr(values[0])
                + " (choose from "
                + ", ".join(listed)
                + ")"
            )
            break
        if name == "--mojo":
            options.mojo = values[0]
        elif name == "--probe":
            options.probe = values[0]
        elif name == "--output":
            options.output = values[0]
            has_output = True
        elif name == "--steps-mm":
            var steps = List[Num]()
            for text in values:
                try:
                    steps.append(Num(parse_float_argument(text), False))
                except:
                    problem = (
                        "argument --steps-mm: invalid float value: "
                        + py_repr(text)
                    )
                    break
            options.steps_mm = steps^
        elif name == "--stature-m":
            try:
                options.stature_m = parse_float_argument(values[0])
            except:
                problem = (
                    "argument --stature-m: invalid float value: "
                    + py_repr(values[0])
                )
        elif name == "--sex":
            options.sex = values[0]
        elif name == "--side":
            options.side = values[0]
        elif name == "--athleticism":
            options.athleticism = values[0]
        elif name == "--use":
            options.use = values[0]
        else:
            options.pair_scope = values[0]
    if not problem and not has_output:
        problem = "the following arguments are required: --output"
    if not problem and len(unknown) > 0:
        problem = "unrecognized arguments: " + " ".join(unknown)
    if problem:
        options.status = 2
        options.message = usage + program + ": error: " + problem + "\n"
    return options^


def report[
    P: Prober
](
    mut tree: JsonTree, mut prober: P, options: Options, root: String
) raises -> Int:
    """Measure the canonical template and assemble the report.

    Args:
        tree: The tree for the report.
        prober: The probe runner.
        options: The command line.
        root: The repository root, absolute.

    Returns:
        The report object.

    Raises:
        Error: For an invalid request, a stale or failed probe, invalid
            evidence, or an observed input change.
    """
    var steps = grid_steps(options.steps_mm)
    var stature = finite_value(options.stature_m, "stature")
    if not (1.2 <= stature and stature <= 2.5):
        raise Error("stature must be in the software range 1.2 through 2.5 m")
    var probe = resolve_path(options.probe)
    var provenance = prepare_probe(
        tree, root, probe, options.mojo, options.build
    )
    var snapshot = source_snapshot(root)
    var metadata = _read_bytes(sidecar(probe))
    verify_report_inputs(root, probe, tree, provenance, snapshot, metadata)
    var inventory = tree.parse(String(from_utf8=Span(snapshot.inventory)))
    var cited = Set[String]()
    for item in tree.items(tree.item(inventory, "parameters")):
        for name in tree.items(tree.item(item, "source_files")):
            cited.add(tree.text(name))
    var source_files = _sorted(cited)
    var controls = prober.rows(tree, probe, "controls", "none", Num(5, True))
    if (
        len(controls) != 1
        or not tree.is_text(tree.get(controls[0], "record"), "controls")
        or tree.kind(tree.get(controls[0], "passed")) != BOOLEAN
        or not tree.flag(tree.get(controls[0], "passed"))
    ):
        raise Error("independent controls did not pass")
    var segment_records = tree.object()
    var finest = List[Int]()
    for segment in segments():
        var rows = List[Int]()
        for step in steps:
            var found = prober.rows(tree, probe, "segment", segment, step)
            if len(found) != 1 or not tree.is_text(
                tree.get(found[0], "segment"), segment
            ):
                raise Error("probe returned the wrong segment")
            var row = found[0]
            if not isclose(
                tree.value(tree.item(row, "step_m")),
                step.value / 1000,
                1e-6,
                0.0,
            ):
                raise Error("probe returned the wrong grid step")
            var checks = validate_segment(tree, row)
            tree.set(row, "tensor_checks", checks.put(tree))
            rows.append(row)
        var entry = tree.object()
        var grids = tree.array()
        for row in rows:
            tree.append(grids, row)
        tree.set(entry, "grids", grids)
        tree.set(
            entry, "sampling_sensitivity", sampling_sensitivity(tree, rows)
        )
        tree.set(segment_records, segment, entry)
        finest.append(rows[len(rows) - 1])
    var smallest = steps[len(steps) - 1]
    var diagnostics = tree.object()
    for mode in ["bones", "knee", "spine"]:
        var array = tree.array()
        for row in prober.rows(tree, probe, mode, "none", smallest):
            tree.append(array, row)
        tree.set(diagnostics, mode, array)
    _ = annotate_diagnostics(tree, diagnostics)
    var collected = collect_pair_diagnostics(
        tree, prober, probe, smallest, options.pair_scope, diagnostics
    )
    var additional = tree.array()
    for row in collected[0]:
        tree.append(additional, row)
    tree.set(diagnostics, "lower_limb_tissues", additional)
    var result = tree.object()
    tree.set(result, "schema_version", tree.integer(2))
    tree.set_text(result, "result_label", "template estimate")
    tree.set(result, "gate", use_gate(tree, options.use))
    tree.set(result, "build_provenance", provenance)
    var hashes = tree.object()
    for path in source_files:
        tree.set_text(hashes, path, snapshot.hash(path))
    tree.set(result, "source_file_sha256", hashes)
    tree.set_text(result, "report_logic_sha256", snapshot.hash(REPORT_LOGIC))
    tree.set_text(result, "inventory_sha256", snapshot.hash(INVENTORY))
    tree.set(
        result,
        "follow_ups",
        tree.strings(["https://github.com/SethKitchen/ThreeMojo/issues/297"]),
    )
    var spec = tree.object()
    tree.set(spec, "stature_m", tree.number(options.stature_m))
    tree.set_text(spec, "sex", options.sex)
    tree.set_text(spec, "side", options.side)
    tree.set_text(spec, "athleticism", options.athleticism)
    tree.set_text(spec, "genome", "template")
    tree.set(result, "spec", spec)
    tree.set(result, "frame", _frame(tree, "tibiofemoral joint line"))
    var frames = tree.object()
    tree.set(frames, PAIR_FRAME, _frame(tree, "tibiofemoral joint line"))
    tree.set(
        frames,
        SPINE_FRAME,
        _frame(tree, "midpoint of the two hip joint centers"),
    )
    tree.set(result, "diagnostic_frames", frames)
    var convention = tree.object()
    tree.set(
        convention, "order", tree.strings(["xx", "yy", "zz", "xy", "xz", "yz"])
    )
    tree.set_text(convention, "reference", "center of mass")
    tree.set_text(convention, "off_diagonal", "negative products of inertia")
    tree.set(result, "tensor_convention", convention)
    tree.set(result, "controls", controls[0])
    tree.set(result, "segments", segment_records)
    tree.set(result, "pair_inventory", collected[1])
    tree.set(result, "composition", compose_segments(tree, finest))
    tree.set(result, "diagnostics", diagnostics)
    tree.set(
        result, "geometry_findings", diagnostic_findings(tree, diagnostics)
    )
    var limits = tree.object()
    tree.set(limits, "step_m", tree.number(smallest.value / 1000))
    tree.set_flag(limits, "absence_of_hits_proves_clearance", False)
    tree.set_flag(limits, "field_values_are_true_clearance", False)
    tree.set_flag(limits, "bone_fields_are_disjoint_material_regions", False)
    tree.set(
        limits,
        "not_evaluated",
        tree.strings(
            [
                "whole-body overlap",
                "dynamic contact",
                "visual/rig/bake mapping (#297)",
                "separate dermis/fat material interfaces",
            ]
        ),
    )
    tree.set(result, "diagnostic_limits", limits)
    var accounting = tree.object()
    tree.set(
        accounting, "exclusive_density_precedence", tree.strings(regions())
    )
    var bones: List[String] = ["femur", "tibia", "fibula", "patella"]
    for row in tree.items(tree.item(diagnostics, "bones")):
        if tree.is_text(tree.item(row, "first"), "femur"):
            var second = tree.text(tree.item(row, "second"))
            if second.startswith("foot/"):
                bones.append(second)
    tree.set(accounting, "bone_precedence", tree.strings(bones))
    tree.set_text(
        accounting,
        "soft_precedence",
        (
            "First leg muscle/tendon, then first foot muscle/tendon, then"
            " unresolved fat proxy."
        ),
    )
    tree.set(
        accounting,
        "do_not_add",
        tree.strings(
            [
                "individual bone/soft-part mass reports",
                "skin envelope mass a second time",
                "SweepField.volume totals",
            ]
        ),
    )
    tree.set(
        accounting,
        "missing",
        tree.strings(
            [
                "contralateral limb",
                "pelvis/trunk/head/arms/hands",
                "tissue above the hip cut",
                "bone pore-fluid and pore-marrow mass",
                "separate unresolved tissue densities",
            ]
        ),
    )
    tree.set(result, "accounting", accounting)
    tree.set(result, "provenance_inventory", inventory)
    finite_tree(tree, result)
    verify_report_inputs(root, probe, tree, provenance, snapshot, metadata)
    return result


def _frame(mut tree: JsonTree, origin: String) raises -> Int:
    """Return one frame description."""
    var frame = tree.object()
    tree.set_text(frame, "origin", origin)
    tree.set_text(frame, "x", "body-right")
    tree.set_text(frame, "y", "proximal")
    tree.set_text(frame, "z", "anterior")
    return frame


def display_path(path: String) -> String:
    """Return a path as `str(Path(path))` writes it.

    Args:
        path: A path.

    Returns:
        The path without empty or `.` parts and without a final slash.
    """
    var parts = List[String]()
    for part in path.split("/"):
        var name = String(part)
        if name.byte_length() > 0 and name != ".":
            parts.append(name)
    var text = "/".join(parts)
    if path.startswith("//") and not path.startswith("///"):
        return "//" + text
    if path.startswith("/"):
        return "/" + text
    if text.byte_length() == 0:
        return "."
    return text


def write_report(path: String, text: String) raises:
    """Write a report file, and make its directory.

    Args:
        path: The file.
        text: The text.

    Raises:
        Error: If the directory or the file cannot be written.
    """
    var parent = _parent(display_path(path))
    if parent.byte_length() > 0:
        makedirs(parent, exist_ok=True)
    Path(path).write_text(text)


def run(arguments: List[String]) raises -> Tuple[Int, String, String]:
    """Run the tool from the repository root.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The exit status, the standard output and the standard error.

    Raises:
        Error: Never for a report failure, which is a message and status 1.
    """
    var options = parse_options(arguments)
    if options.status == -1:
        return (0, options.message, String())
    if options.status != 0:
        return (options.status, String(), options.message)
    var permitted: Bool
    try:
        var root = realpath(".")
        var tree = JsonTree()
        var prober = NativeProbe(options.spec(), root, True)
        var result = report(tree, prober, options, root)
        permitted = tree.flag(
            tree.path(result, ["gate", "permitted_as_labeled"])
        )
        write_report(options.output, tree.dumps(result) + "\n")
    except error:
        return (
            1,
            String(),
            "anatomy validity report failed: " + String(error) + "\n",
        )
    return (
        0 if permitted else 2,
        display_path(options.output)
        + ": template estimate; engineering validation remains unsupported\n",
        String(),
    )


def main() raises:
    """Run the tool and exit with its status.

    Raises:
        Error: Never; a failure is a message and a status.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var outcome = run(arguments)
    print(outcome[1], end="")
    print(outcome[2], end="", file=stderr)
    exit(outcome[0])
