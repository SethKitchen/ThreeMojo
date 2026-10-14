# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Immutable canonical SI snapshots and explicit visual derivatives.

This boundary packages supplied canonical geometry. It does not rebuild
anatomy from a visual mesh, and it does not certify the geometry. Keep the
complete #289 report as evidence. No raw probe row is an engineering
validity certificate. The command line uses local files only. It never
fetches or rehosts source assets:

    mojo run -I . tools/humanoid_fidelity.mojo SNAPSHOT --sha256 DIGEST

The command reads the snapshot, compares its SHA-256 with the digest, and
validates the packaging. It writes the same text and exit status as the
Python tool that it replaces, for the same files and arguments. Values are
Python values (`tools._python_json`): an int stays an int, and the snapshot
bytes are Python's canonical `json.dumps` bytes.

Two Python failures that the old tool did not catch, `OverflowError` and
`RecursionError`, end with status 1 and the exception's last line, without
Python's traceback.
"""

from std.ffi import c_int, external_call
from std.math import isinf, isnan
from std.os import getenv, remove
from std.os.path import exists, isdir
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr

from tools._bigint import BigInt
from tools._python_json import (
    MISSING,
    OVERFLOW,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    RECURSION,
    PyJson,
    canonical_bytes as json_bytes,
    check_canonical,
    code_points,
    is_blank,
    loads,
    py_equal,
    py_repr,
)
from tools._sha256 import sha256_hex


comptime SCHEMA = 1
"""The snapshot and derivative schema version."""
comptime Y_UP_TEXT = "right-handed-y-up-x-right-z-anterior"
"""The y-up frame name: +x body-right, +y up, +z anterior."""
comptime Z_UP_TEXT = "right-handed-z-up-x-right-minus-y-anterior"
"""The z-up frame name: +x body-right, +z up, -y anterior."""
comptime SCOPE = (
    "Supplied canonical part meshes and reported properties; no clinical"
    " calibration or visual correspondence."
)
"""The scope that every snapshot states."""
comptime VERIFIED = (
    "Canonical snapshot bytes and SI packaging verified; engineering use"
    " remains unsupported."
)
"""The line that the command prints for a valid snapshot."""
comptime PROGRAM = "humanoid_fidelity.mojo"
"""The program name when the command line gives none."""
comptime DESCRIPTION = (
    "Immutable canonical SI snapshots and explicit visual derivatives. This"
    " boundary packages supplied canonical geometry; it does not reconstruct"
    " anatomy from a visual mesh or certify the geometry. Keep the complete"
    " #289 report as evidence. No raw probe row is an engineering validity"
    " certificate. The CLI uses local files only and never fetches or"
    " rehosts source assets."
)
"""The help description, as the Python tool's `argparse` showed it."""
comptime SEGMENTS = ["thigh", "shank", "foot"]
"""The three limb segments of a canonical report."""

comptime _NOT_FINITE = "an SI quantity must be finite and numeric"
comptime _NOT_VECTOR = "a vector must contain three coordinates"
comptime _TOO_LARGE = OVERFLOW + "int too large to convert to float"
comptime _FAILED = "Canonical snapshot validation failed: "


@fieldwise_init
struct Frame(Equatable, ImplicitlyCopyable, Writable):
    """A named right-handed SI axis convention. Origins are separate."""

    var value: Int
    """The frame number."""

    def is_valid(self) -> Bool:
        """Return whether this is one of the two named conventions.

        Returns:
            True for `Y_UP` and `Z_UP`.
        """
        return self == Y_UP or self == Z_UP

    def text(self) raises -> String:
        """Return the convention's name, as the Python enum value.

        Returns:
            The name.

        Raises:
            Error: If the frame is not valid.
        """
        if self == Y_UP:
            return Y_UP_TEXT
        if self == Z_UP:
            return Z_UP_TEXT
        raise Error("source and target must be typed frames")


comptime Y_UP = Frame(0)
"""+x is body-right, +y is up and +z is anterior."""
comptime Z_UP = Frame(1)
"""+x is body-right, +z is up and -y is anterior."""


# --- Python numbers ------------------------------------------------------------------


struct _Num(Copyable, Movable):
    """A Python int or float, for arithmetic with Python's rules."""

    var is_int: Bool
    var whole: BigInt
    var real: Float64

    def __init__(out self, real: Float64):
        self.is_int = False
        self.whole = BigInt(0)
        self.real = real

    def __init__(out self, var whole: BigInt):
        self.is_int = True
        self.whole = whole^
        self.real = 0.0


@no_inline
def _product(a: Float64, b: Float64) -> Float64:
    """Return a * b rounded once. A call is never fused with an addition,
    so a product always rounds as Python's does."""
    return a * b


def _num(doc: PyJson, node: Int) raises -> _Num:
    """Read an int or a float."""
    if doc.kind(node) == PY_INT:
        return _Num(BigInt.parse(doc.text(node)))
    return _Num(doc.number(node))


def _float(value: _Num) raises -> Float64:
    """Convert to a float, as Python does before float arithmetic."""
    if not value.is_int:
        return value.real
    var result = value.whole.to_float()
    if isinf(result):
        raise Error(_TOO_LARGE)
    return result


def _mul(a: _Num, b: _Num) raises -> _Num:
    """Return a * b."""
    if a.is_int and b.is_int:
        return _Num(a.whole * b.whole)
    return _Num(_product(_float(a), _float(b)))


def _sub(a: _Num, b: _Num) raises -> _Num:
    """Return a - b."""
    if a.is_int and b.is_int:
        return _Num(a.whole - b.whole)
    return _Num(_float(a) - _float(b))


def _add(a: _Num, b: _Num) raises -> _Num:
    """Return a + b."""
    if a.is_int and b.is_int:
        return _Num(a.whole + b.whole)
    return _Num(_float(a) + _float(b))


struct _FSum(Movable):
    """CPython's `math.fsum`: exact partials, rounded once at the end."""

    var partials: List[Float64]
    var special: Float64
    var infinite: Float64

    def __init__(out self):
        self.partials = List[Float64]()
        self.special = 0.0
        self.infinite = 0.0

    def add(mut self, value: Float64) raises:
        """Add one item."""
        var x = value
        var kept = 0
        for index in range(len(self.partials)):
            var y = self.partials[index]
            if abs(x) < abs(y):
                var t = x
                x = y
                y = t
            var high = x + y
            var low = y - (high - x)
            if low != 0.0:
                self.partials[kept] = low
                kept += 1
            x = high
        while len(self.partials) > kept:
            _ = self.partials.pop()
        if x != 0.0:
            if isnan(x) or isinf(x):
                if not (isnan(value) or isinf(value)):
                    raise Error(OVERFLOW + "intermediate overflow in fsum")
                if isinf(value):
                    self.infinite += value
                self.special += value
                self.partials.clear()
            else:
                self.partials.append(x)

    def total(self) raises -> Float64:
        """Return the correctly rounded sum."""
        if self.special != 0.0 or isnan(self.special):
            if isnan(self.infinite):
                raise Error("-inf + inf in fsum")
            return self.special
        var n = len(self.partials)
        var high = 0.0
        if n > 0:
            n -= 1
            high = self.partials[n]
            var low = 0.0
            while n > 0:
                var x = high
                n -= 1
                var y = self.partials[n]
                high = x + y
                low = y - (high - x)
                if low != 0.0:
                    break
            if n > 0 and (
                (low < 0.0 and self.partials[n - 1] < 0.0)
                or (low > 0.0 and self.partials[n - 1] > 0.0)
            ):
                var y = low * 2.0
                var x = high + y
                if y == x - high:
                    high = x
        return high


def _py_sum(items: List[_Num]) raises -> _Num:
    """Return `sum(items)` as CPython 3.12 adds from an int zero."""
    var whole = BigInt(0)
    var index = 0
    while index < len(items) and items[index].is_int:
        whole = whole + items[index].whole
        index += 1
    if index == len(items):
        return _Num(whole^)
    var total = _float(_Num(whole^)) + items[index].real
    var compensation = 0.0
    index += 1
    while index < len(items):
        if items[index].is_int:
            total += _float(items[index])
        else:
            var x = items[index].real
            var t = total + x
            if abs(total) >= abs(x):
                compensation += (total - t) + x
            else:
                compensation += (x - t) + total
            total = t
        index += 1
    if (
        compensation != 0.0
        and not isinf(compensation)
        and not isnan(compensation)
    ):
        total += compensation
    return _Num(total)


def _isclose(a: Float64, b: Float64) -> Bool:
    """Return `math.isclose(a, b, rel_tol=0, abs_tol=1e-12)`."""
    if a == b:
        return True
    if isinf(a) or isinf(b):
        return False
    var diff = abs(b - a)
    return (
        diff <= abs(_product(0.0, b))
        or diff <= abs(_product(0.0, a))
        or diff <= 1e-12
    )


# --- Values ----------------------------------------------------------------------


def _check_finite(doc: PyJson, node: Int) raises:
    """Require a finite int or float, as the Python `finite` does."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        var value = doc.number(node)
        if isnan(value) or isinf(value):
            raise Error(_NOT_FINITE)
        return
    if kind != PY_INT:
        raise Error(_NOT_FINITE)
    var digits = doc.text(node)
    if digits.byte_length() > 300:
        if isinf(BigInt.parse(digits).to_float()):
            raise Error(_TOO_LARGE)


def _sign(doc: PyJson, node: Int) -> Int:
    """Return -1, 0 or 1 for a finite int or float."""
    if doc.kind(node) == PY_INT:
        var digits = doc.text(node)
        if digits == "0":
            return 0
        return -1 if digits.startswith("-") else 1
    var value = doc.number(node)
    if value < 0:
        return -1
    return 1 if value > 0 else 0


def _vector(doc: PyJson, node: Int) raises -> List[Int]:
    """Validate three finite coordinates and return their nodes."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 3:
        raise Error(_NOT_VECTOR)
    var out = List[Int]()
    for index in range(3):
        var item = doc.value(node, index)
        _check_finite(doc, item)
        out.append(item)
    return out^


def _label(doc: PyJson, node: Int, name: String) raises -> String:
    """Require a nonempty label and return it."""
    if doc.kind(node) != PY_STR or is_blank(doc.text(node)):
        raise Error(name + " must be a nonempty label")
    return doc.text(node)


def _is_text(doc: PyJson, node: Int, text: String) -> Bool:
    """Return whether a value is the str `text`."""
    return doc.kind(node) == PY_STR and doc.text(node) == text


def _matrix(rows: List[List[Int]]) -> PyJson:
    """Return a 3x3 int matrix."""
    var doc = PyJson()
    doc.root = doc.new_list()
    for row in rows:
        var made = doc.new_list()
        for value in row:
            doc.append(made, doc.new_int(value))
        doc.append(doc.root, made)
    return doc^


def identity() -> PyJson:
    """Return the identity rotation.

    Returns:
        `((1, 0, 0), (0, 1, 0), (0, 0, 1))`.
    """
    return _matrix([[1, 0, 0], [0, 1, 0], [0, 0, 1]])


def y_to_z() -> PyJson:
    """Return the y-up to z-up rotation, which maps (x, y, z) to (x, -z, y).

    Returns:
        `((1, 0, 0), (0, 0, -1), (0, 1, 0))`.
    """
    return _matrix([[1, 0, 0], [0, 0, -1], [0, 1, 0]])


def z_to_y() -> PyJson:
    """Return the z-up to y-up rotation, which maps (x, y, z) to (x, z, -y).

    Returns:
        `((1, 0, 0), (0, 0, 1), (0, -1, 0))`.
    """
    return _matrix([[1, 0, 0], [0, 0, 1], [0, -1, 0]])


def finite(value: PyJson) raises -> PyJson:
    """Require a finite numeric SI value, excluding bool values.

    Args:
        value: The value.

    Returns:
        The value.

    Raises:
        Error: If the value is not a finite int or float.
    """
    _check_finite(value, value.root)
    return value.copy()


def vector(value: PyJson) raises -> PyJson:
    """Validate a three-coordinate SI vector.

    Args:
        value: The value.

    Returns:
        A list of the three coordinates.

    Raises:
        Error: If the value is not three finite numbers.
    """
    var nodes = _vector(value, value.root)
    var out = PyJson()
    out.root = out.new_list()
    for node in nodes:
        out.append(out.root, out.adopt(value, node))
    return out^


def _rotation(doc: PyJson, node: Int) raises -> List[_Num]:
    """Require a proper orthonormal rotation; return it row by row."""
    if doc.kind(node) != PY_LIST or doc.length(node) != 3:
        raise Error("a rotation must have three rows")
    var rows = List[_Num]()
    for index in range(3):
        for item in _vector(doc, doc.value(node, index)):
            rows.append(_num(doc, item))
    for i in range(3):
        for j in range(3):
            var products = List[_Num]()
            for k in range(3):
                products.append(_mul(rows[3 * i + k], rows[3 * j + k]))
            var total = _float(_py_sum(products))
            if not _isclose(total, 1.0 if i == j else 0.0):
                raise Error("a rotation must be orthonormal")
    ref r = rows
    var det = _add(
        _sub(
            _mul(r[0], _sub(_mul(r[4], r[8]), _mul(r[5], r[7]))),
            _mul(r[1], _sub(_mul(r[3], r[8]), _mul(r[5], r[6]))),
        ),
        _mul(r[2], _sub(_mul(r[3], r[7]), _mul(r[4], r[6]))),
    )
    if not _isclose(_float(det), 1.0):
        raise Error("a rotation must preserve handedness")
    return rows^


def rotation(value: PyJson) raises -> PyJson:
    """Require a proper orthonormal rotation, never a reflection or scale.

    Args:
        value: Three rows of three numbers.

    Returns:
        The rows.

    Raises:
        Error: If the value is not three rows, or is not a proper rotation
            within 1e-12.
    """
    _ = _rotation(value, value.root)
    var out = PyJson()
    out.root = out.new_list()
    for index in range(3):
        var row = out.new_list()
        for node in _vector(value, value.value(value.root, index)):
            out.append(row, out.adopt(value, node))
        out.append(out.root, row)
    return out^


def frame_rotation(source: Frame, target: Frame) raises -> PyJson:
    """Return a named y-up/z-up coordinate adapter. Both frames stay SI.

    Args:
        source: The source frame.
        target: The target frame.

    Returns:
        The identity, `y_to_z()` or `z_to_y()`.

    Raises:
        Error: If a frame is not valid.
    """
    if not source.is_valid() or not target.is_valid():
        raise Error("source and target must be typed frames")
    if source == target:
        return identity()
    return y_to_z() if source == Y_UP else z_to_y()


def _zeros() -> PyJson:
    """Return `(0, 0, 0)`."""
    var doc = PyJson()
    doc.root = doc.new_list()
    for _ in range(3):
        doc.append(doc.root, doc.new_int(0))
    return doc^


def _transform_point(
    pdoc: PyJson,
    point: Int,
    rdoc: PyJson,
    rotate: Int,
    tdoc: PyJson,
    translation: Int,
) raises -> List[Float64]:
    """Rotate and translate a point, as the Python `transform_point` does."""
    var p = _vector(pdoc, point)
    var r = _rotation(rdoc, rotate)
    var t = _vector(tdoc, translation)
    var out = List[Float64]()
    for i in range(3):
        var total = _FSum()
        for j in range(3):
            total.add(_float(_mul(r[3 * i + j], _num(pdoc, p[j]))))
        var value = total.total() + _float(_num(tdoc, t[i]))
        out.append(value)
    for value in out:
        if isnan(value) or isinf(value):
            raise Error(_NOT_FINITE)
    return out^


def _float_list(mut doc: PyJson, values: List[Float64]) raises -> Int:
    """Add a list of floats."""
    var node = doc.new_list()
    for value in values:
        doc.append(node, doc.new_float(value))
    return node


def transform_point(
    point_m: PyJson, rotate: PyJson, translation_m: Optional[PyJson] = None
) raises -> PyJson:
    """Apply a proper rotation and a translation in target-frame meters.

    Args:
        point_m: Three coordinates in meters.
        rotate: A proper rotation.
        translation_m: Three target-frame meters, or none for zero.

    Returns:
        The three transformed coordinates, as floats.

    Raises:
        Error: If an input is not valid or a result is not finite.
    """
    var t = translation_m.value().copy() if translation_m else _zeros()
    var values = _transform_point(
        point_m, point_m.root, rotate, rotate.root, t, t.root
    )
    var out = PyJson()
    out.root = _float_list(out, values)
    return out^


def _transform_inertia(
    mut out: PyJson,
    mdoc: PyJson,
    mass_kg: Int,
    cdoc: PyJson,
    center_m: Int,
    idoc: PyJson,
    inertia: Int,
    rdoc: PyJson,
    rotate: Int,
    tdoc: PyJson,
    translation: Int,
    fdoc: PyJson,
    reference: Int,
) raises -> Int:
    """Port of the Python `transform_inertia`; adds its dict to `out`.

    `reference` is `MISSING` to keep the tensor about the transformed
    center of mass.
    """
    _check_finite(mdoc, mass_kg)
    if _sign(mdoc, mass_kg) < 0:
        raise Error("mass cannot be negative")
    if idoc.kind(inertia) != PY_LIST or idoc.length(inertia) != 6:
        raise Error("a symmetric inertia tensor needs six entries")
    var entries = List[_Num]()
    for index in range(6):
        var item = idoc.value(inertia, index)
        _check_finite(idoc, item)
        entries.append(_num(idoc, item))
    # xx, yy, zz, xy, xz, yz as the full symmetric tensor.
    var at: List[Int] = [0, 3, 4, 3, 1, 5, 4, 5, 2]
    var r = _rotation(rdoc, rotate)
    var center = _transform_point(
        cdoc, center_m, rdoc, rotate, tdoc, translation
    )
    var reference_nodes = List[Int]()
    var references = List[_Num]()
    if reference == MISSING:
        for value in center:
            references.append(_Num(value))
    else:
        reference_nodes = _vector(fdoc, reference)
        for node in reference_nodes:
            references.append(_num(fdoc, node))
    var d = List[Float64]()
    for index in range(3):
        d.append(_float(_sub(_Num(center[index]), references[index])))
    var squares = _FSum()
    for x in d:
        squares.add(_product(x, x))
    var norm = squares.total()
    var mass = _num(mdoc, mass_kg)
    var result = List[Float64]()
    for i in range(3):
        for j in range(3):
            var rotated = _FSum()
            for k in range(3):
                for l in range(3):
                    rotated.add(
                        _float(
                            _mul(
                                _mul(r[3 * i + k], entries[at[3 * k + l]]),
                                r[3 * j + l],
                            )
                        )
                    )
            var shift = _product(norm, 1.0 if i == j else 0.0) - _product(
                d[i], d[j]
            )
            var moved = _float(_mul(mass, _Num(shift)))
            result.append(rotated.total() + moved)
    var tensor: List[Float64] = [
        result[0],
        result[4],
        result[8],
        result[1],
        result[2],
        result[5],
    ]
    for value in center:
        if isnan(value) or isinf(value):
            raise Error(_NOT_FINITE)
    for value in tensor:
        if isnan(value) or isinf(value):
            raise Error(_NOT_FINITE)
    var made = out.new_dict()
    out.set(made, "mass_kg", out.adopt(mdoc, mass_kg))
    out.set(made, "center_m", _float_list(out, center))
    if reference == MISSING:
        out.set(made, "reference_m", _float_list(out, center))
    else:
        var list = out.new_list()
        for node in reference_nodes:
            out.append(list, out.adopt(fdoc, node))
        out.set(made, "reference_m", list)
    out.set(made, "inertia_kg_m2", _float_list(out, tensor))
    return made


def transform_inertia(
    mass_kg: PyJson,
    center_m: PyJson,
    inertia_com_kg_m2: PyJson,
    rotate: PyJson,
    translation_m: Optional[PyJson] = None,
    reference_m: Optional[PyJson] = None,
) raises -> PyJson:
    """Rotate the full COM tensor, then shift it to the target reference.

    The six entries are xx, yy, zz, xy, xz, yz with tensor signs, as in
    #289. The result is R I Rᵀ + m ((d·d) Identity - d dᵀ), where d is the
    center of mass minus the reference. Omit the reference to keep the
    tensor about the transformed center of mass. Never pass a tensor about
    another reference as if it were a COM tensor.

    Args:
        mass_kg: The mass in kilograms.
        center_m: The center of mass in source meters.
        inertia_com_kg_m2: The six tensor entries about the center of mass.
        rotate: A proper rotation.
        translation_m: Three target-frame meters, or none for zero.
        reference_m: The target-frame reference point, or none.

    Returns:
        A dict with `mass_kg`, `center_m`, `reference_m` and
        `inertia_kg_m2`.

    Raises:
        Error: If an input is not valid or a result is not finite.
    """
    var t = translation_m.value().copy() if translation_m else _zeros()
    var f = reference_m.value().copy() if reference_m else PyJson()
    var out = PyJson()
    out.root = _transform_inertia(
        out,
        mass_kg,
        mass_kg.root,
        center_m,
        center_m.root,
        inertia_com_kg_m2,
        inertia_com_kg_m2.root,
        rotate,
        rotate.root,
        t,
        t.root,
        f,
        f.root if reference_m else MISSING,
    )
    return out^


def _type_name(doc: PyJson, node: Int) -> String:
    """Return the Python type name of a value."""
    var kind = doc.kind(node)
    if kind == PY_NONE:
        return "NoneType"
    if kind == PY_BOOL:
        return "bool"
    if kind == PY_INT:
        return "int"
    return "float"


def adapt_part(
    part: PyJson,
    source_frame: Frame,
    target_frame: Frame,
    translation_m: Optional[PyJson] = None,
    reference_m: Optional[PyJson] = None,
    target_origin_label: Optional[String] = None,
) raises -> PyJson:
    """Copy geometry and COM properties into a coherent target frame.

    The part's frame and its property frame must match the source frame. A
    translation needs an explicit target-origin label. A shifted output
    tensor cannot be used as a COM tensor in a later adaptation.

    Args:
        part: The part, a dict.
        source_frame: The part's frame.
        target_frame: The frame of the copy.
        translation_m: Three target-frame meters, or none for zero.
        reference_m: The target-frame tensor reference, or none for the
            center of mass.
        target_origin_label: The copy's origin label, or none to keep the
            part's origin label.

    Returns:
        The adapted copy.

    Raises:
        Error: If the part, the frames or a value contradict each other or
            are not valid.
    """
    var r = frame_rotation(source_frame, target_frame)
    var t = translation_m.value().copy() if translation_m else _zeros()
    var translated = _vector(t, t.root)
    var root = part.root
    if part.kind(root) != PY_DICT or not _is_text(
        part, part.get(root, "frame"), source_frame.text()
    ):
        raise Error("part frame contradicts the declared source frame")
    var origin = _label(part, part.get(root, "origin_label"), "part origin")
    var target_label: String
    if target_origin_label:
        target_label = target_origin_label.value()
    else:
        for node in translated:
            if _sign(t, node) != 0:
                raise Error("translation requires an explicit target origin")
        target_label = origin
    if is_blank(target_label):
        raise Error("target origin must be a nonempty label")
    var physical = part.get(root, "physical_properties")
    if not part.is_none(physical):
        if part.kind(physical) != PY_DICT or not _is_text(
            part, part.get(physical, "frame"), source_frame.text()
        ):
            raise Error("physical property frame contradicts the source frame")
        if not _is_text(part, part.get(physical, "origin_label"), origin):
            raise Error("physical property origin contradicts the part origin")
        if not _is_text(
            part, part.get(physical, "tensor_reference"), "center-of-mass"
        ):
            raise Error("adaptation requires a source tensor about the COM")
    var out = part.copy()
    var vertices = part.at(root, "vertices_m")
    var moved = out.new_list()
    var kind = part.kind(vertices)
    if kind == PY_LIST:
        for index in range(part.length(vertices)):
            var values = _transform_point(
                part, part.value(vertices, index), r, r.root, t, t.root
            )
            out.append(moved, _float_list(out, values))
    elif kind == PY_DICT or kind == PY_STR:
        if (kind == PY_DICT and part.length(vertices) > 0) or (
            kind == PY_STR and part.text(vertices).byte_length() > 0
        ):
            raise Error(_NOT_VECTOR)
    else:
        raise Error(
            "TypeError: '"
            + _type_name(part, vertices)
            + "' object is not iterable"
        )
    out.set(out.root, "vertices_m", moved)
    out.set(out.root, "frame", out.new_str(target_frame.text()))
    out.set(out.root, "origin_label", out.new_str(target_label))
    out.set(out.root, "source_frame", out.new_str(source_frame.text()))
    out.set(out.root, "source_origin_label", out.new_str(origin))
    var kept = out.new_list()
    for node in translated:
        out.append(kept, out.adopt(t, node))
    out.set(out.root, "translation_m", kept)
    var held = out.get(out.root, "physical_properties")
    if not out.is_none(held):
        var f = reference_m.value().copy() if reference_m else PyJson()
        var mass = out.at(held, "mass_kg")
        var center = out.at(held, "center_m")
        var inertia = out.at(held, "inertia_kg_m2")
        var source = out.copy()
        var made = _transform_inertia(
            out,
            source,
            mass,
            source,
            center,
            source,
            inertia,
            r,
            r.root,
            t,
            t.root,
            f,
            f.root if reference_m else MISSING,
        )
        for name in ["mass_kg", "center_m", "reference_m", "inertia_kg_m2"]:
            out.set(held, name, out.find(made, name))
        out.set(
            held,
            "tensor_reference",
            out.new_str(
                "explicit-target-reference" if reference_m else "center-of-mass"
            ),
        )
        out.set(held, "frame", out.new_str(target_frame.text()))
        out.set(held, "origin_label", out.new_str(target_label))
    return out^


# --- Canonical bytes ------------------------------------------------------------------


def canonical_bytes(value: PyJson) raises -> List[UInt8]:
    """Return a stable finite JSON representation, suitable for SHA-256.

    Args:
        value: The value.

    Returns:
        `json.dumps(value, sort_keys=True, separators=(",", ":"),
        ensure_ascii=True, allow_nan=False)` as bytes.

    Raises:
        Error: With Python's text if a float is not finite.
    """
    return json_bytes(value, value.root)


def digest(value: PyJson) raises -> String:
    """Return the SHA-256 of the canonical JSON representation.

    Args:
        value: The value.

    Returns:
        Sixty-four lowercase hexadecimal digits.

    Raises:
        Error: With Python's text if a float is not finite.
    """
    var data = canonical_bytes(value)
    return sha256_hex(data)


# --- The canonical report ----------------------------------------------------------------


def _expected(text: StaticString) raises -> PyJson:
    """Read a fixed expected value."""
    return PyJson.parse(String(text))


def _check_report(doc: PyJson, report: Int) raises:
    """Require the complete typed #289 envelope and its tensor convention.

    This validates structure and coordinate meaning, not anatomy or
    numerical convergence. Versions 1 and 2 share the sampled-property
    contract. Version 2 also keeps its diagnostic frames and its versioned
    pair inventory as separate evidence.
    """
    var version = doc.get(report, "schema_version")
    if (
        doc.kind(report) != PY_DICT
        or doc.kind(version) != PY_INT
        or (doc.text(version) != "1" and doc.text(version) != "2")
    ):
        raise Error(
            "a complete versioned canonical validity report is required"
        )
    var second = doc.text(version) == "2"
    var mappings: List[String] = [
        "gate",
        "build_provenance",
        "source_file_sha256",
        "spec",
        "frame",
        "tensor_convention",
        "controls",
        "segments",
        "composition",
        "diagnostics",
        "diagnostic_limits",
        "accounting",
        "provenance_inventory",
    ]
    if second:
        mappings.append("diagnostic_frames")
        mappings.append("pair_inventory")
    for key in mappings:
        if doc.kind(doc.get(report, key)) != PY_DICT:
            raise Error(
                "use the complete typed canonical validity report, not raw"
                " probe rows"
            )
    if second:
        var inventory = doc.get(report, "pair_inventory")
        var inventory_version = doc.get(inventory, "schema_version")
        if (
            doc.kind(inventory_version) != PY_INT
            or doc.text(inventory_version) != "1"
        ):
            raise Error("unsupported canonical report pair inventory schema")
        var typed = doc.kind(doc.get(inventory, "classes")) == PY_DICT
        for key in [
            "components",
            "pairs",
            "additional_checked_diagnostics",
            "positive_volume_attachment_allowances",
            "unknowns",
            "excluded_domains",
        ]:
            if doc.kind(doc.get(inventory, key)) != PY_LIST:
                typed = False
        if not typed:
            raise Error(
                "a canonical report must retain its typed pair inventory"
            )
        var frame = _label(
            doc, doc.get(inventory, "frame_id"), "pair inventory frame"
        )
        if not py_equal(
            doc,
            doc.get(doc.get(report, "diagnostic_frames"), frame),
            doc,
            doc.get(report, "frame"),
        ):
            raise Error(
                "pair inventory frame must retain the canonical report"
                " coordinate frame"
            )
    for key in ["follow_ups", "geometry_findings"]:
        if doc.kind(doc.get(report, key)) != PY_LIST:
            raise Error("canonical validity report arrays are missing")
    for key in ["result_label", "report_logic_sha256", "inventory_sha256"]:
        _ = _label(doc, doc.get(report, key), key)
    var granted = doc.get(doc.get(report, "gate"), "engineering_validated")
    if doc.kind(granted) != PY_BOOL or doc.flag(granted):
        raise Error("canonical report cannot grant engineering validity")
    var convention = _expected(
        '{"order": ["xx", "yy", "zz", "xy", "xz", "yz"], "reference": "center'
        ' of mass", "off_diagonal": "negative products of inertia"}'
    )
    if not py_equal(
        doc, doc.get(report, "tensor_convention"), convention, convention.root
    ):
        raise Error(
            "unsupported canonical report tensor order, reference or sign"
        )
    var axes = _expected(
        '{"origin": "tibiofemoral joint line", "x": "body-right", "y":'
        ' "proximal", "z": "anterior"}'
    )
    if not py_equal(doc, doc.get(report, "frame"), axes, axes.root):
        raise Error("unsupported canonical report coordinate frame")
    var segments = doc.get(report, "segments")
    var complete = doc.length(segments) == 3
    for name in materialize[SEGMENTS]():
        if doc.find(segments, name) == MISSING:
            complete = False
    if not complete:
        raise Error("a complete canonical report needs all three limb segments")
    var labels = doc.get(
        doc.get(report, "accounting"), "exclusive_density_precedence"
    )
    var names = List[String]()
    var counted = doc.kind(labels) == PY_LIST and doc.length(labels) == 7
    if counted:
        for index in range(7):
            var item = doc.value(labels, index)
            if doc.kind(item) != PY_STR or doc.text(item).byte_length() == 0:
                counted = False
                break
            for seen in names:
                if seen == doc.text(item):
                    counted = False
            names.append(doc.text(item))
    if not counted:
        raise Error(
            "a canonical report needs its seven exclusive region labels"
        )
    for index in range(doc.length(segments)):
        var segment = doc.key(segments, index)
        var entry = doc.value(segments, index)
        if (
            doc.kind(entry) != PY_DICT
            or doc.kind(doc.get(entry, "sampling_sensitivity")) != PY_DICT
        ):
            raise Error("a segment must retain its sampling sensitivity report")
        var grids = doc.get(entry, "grids")
        if doc.kind(grids) != PY_LIST or doc.length(grids) < 3:
            raise Error("a segment must retain at least three sampled grids")
        for slot in range(doc.length(grids)):
            _check_row(doc, doc.value(grids, slot), segment, names)
    check_canonical(doc, report)


def _check_row(
    doc: PyJson, row: Int, segment: String, names: List[String]
) raises:
    """Validate one sampled grid row of a canonical report."""
    if (
        doc.kind(row) != PY_DICT
        or not _is_text(doc, doc.get(row, "record"), "segment")
        or not _is_text(doc, doc.get(row, "segment"), segment)
    ):
        raise Error("a sampled grid must retain its segment identity")
    for key in ["mass_kg", "step_m", "length_m"]:
        var value = doc.get(row, key)
        _check_finite(doc, value)
        if _sign(doc, value) <= 0:
            raise Error("sampled mass, grid step and length must be positive")
    for key in ["center_m", "low_m", "high_m"]:
        _ = _vector(doc, doc.get(row, key))
    var tensor = doc.get(row, "inertia_kg_m2")
    if doc.kind(tensor) != PY_LIST or doc.length(tensor) != 6:
        raise Error("a sampled grid must retain its full inertia tensor")
    for index in range(6):
        _check_finite(doc, doc.value(tensor, index))
    var regions = doc.get(row, "regions")
    var complete = doc.kind(regions) == PY_DICT and doc.length(regions) == len(
        names
    )
    if complete:
        for name in names:
            if doc.find(regions, name) == MISSING:
                complete = False
    if not complete:
        raise Error("a sampled grid must retain all accounting regions")
    for index in range(doc.length(regions)):
        var region = doc.value(regions, index)
        if doc.kind(region) != PY_DICT:
            raise Error("a sampled region must retain its quantities")
        for key in ["mass_kg", "volume_m3"]:
            var value = doc.get(region, key)
            _check_finite(doc, value)
            if _sign(doc, value) < 0:
                raise Error("sampled region quantities cannot be negative")


def report_properties(
    report: PyJson, segment: String, grid_index: Int
) raises -> PyJson:
    """Copy one #289 segment's complete sampled properties, unchanged.

    The tensor is about the center of mass in the report's leg frame. The
    copy keeps that frame and the seven density-assignment labels. It does
    not establish correspondence to any separately supplied part mesh.

    Args:
        report: A complete schema-version-1 or -2 canonical report.
        segment: `thigh`, `shank` or `foot`.
        grid_index: The sampled grid's position.

    Returns:
        The row's mass, center, tensor, regions and step, with their frame,
        origin and source record.

    Raises:
        Error: If the report is not complete, or the segment or the grid
            does not exist.
    """
    _check_report(report, report.root)
    var known = False
    for name in materialize[SEGMENTS]():
        if segment == name:
            known = True
    if not known:
        raise Error("a report segment must be thigh, shank or foot")
    if grid_index < 0:
        raise Error("a grid index must be a nonnegative integer")
    var grids = report.at(
        report.at(report.at(report.root, "segments"), segment), "grids"
    )
    if grid_index >= report.length(grids):
        raise Error("the complete segment/grid record is missing")
    var row = report.value(grids, grid_index)
    var out = PyJson()
    out.root = out.new_dict()
    for key in ["mass_kg", "center_m", "inertia_kg_m2", "regions", "step_m"]:
        out.set(out.root, key, out.adopt(report, report.at(row, key)))
    var frame = report.at(report.root, "frame")
    out.set(out.root, "frame", out.new_str(Y_UP_TEXT))
    out.set(
        out.root, "origin_label", out.adopt(report, report.at(frame, "origin"))
    )
    out.set(out.root, "source_report_frame", out.adopt(report, frame))
    out.set(out.root, "tensor_reference", out.new_str("center-of-mass"))
    out.set(
        out.root,
        "source_report_record",
        out.new_str("segments/" + segment + "/grids/" + String(grid_index)),
    )
    return out^


# --- Snapshots ----------------------------------------------------------------------


def _check_snapshot(doc: PyJson, snapshot: Int) raises:
    """Validate packaging and SI shape, without inferring anatomy."""
    if doc.kind(snapshot) != PY_DICT:
        raise Error("a canonical snapshot must be an object")
    var version = doc.get(snapshot, "schema_version")
    if doc.kind(version) != PY_INT or doc.text(version) != String(SCHEMA):
        raise Error("unsupported canonical snapshot schema")
    var units = _expected(
        '{"length": "meter", "mass": "kilogram", "inertia":'
        ' "kilogram-meter-squared"}'
    )
    if not py_equal(doc, doc.get(snapshot, "units"), units, units.root):
        raise Error("canonical snapshot quantities must use SI units")
    if not _is_text(doc, doc.get(snapshot, "frame"), Y_UP_TEXT):
        raise Error("canonical snapshots must retain the y-up source frame")
    _ = _vector(doc, doc.get(snapshot, "origin_m"))
    var origin = _label(doc, doc.get(snapshot, "origin_label"), "source origin")
    _ = _label(doc, doc.get(snapshot, "source_revision"), "source revision")
    var inputs = doc.get(snapshot, "canonical_inputs")
    if doc.kind(inputs) != PY_DICT or doc.length(inputs) == 0:
        raise Error("canonical SI inputs are required")
    var certified = doc.get(snapshot, "engineering_validated")
    if doc.kind(certified) != PY_BOOL or doc.flag(certified):
        raise Error("a snapshot cannot certify engineering validity")
    _check_report(doc, doc.get(snapshot, "canonical_validity_report"))
    var parts = doc.get(snapshot, "parts")
    if doc.kind(parts) != PY_LIST or doc.length(parts) == 0:
        raise Error("a snapshot needs explicit canonical parts")
    var seen = List[String]()
    var rotate = identity()
    var zero = _zeros()
    for index in range(doc.length(parts)):
        var part = doc.value(parts, index)
        if doc.kind(part) != PY_DICT:
            raise Error("a canonical part must be an object")
        var label = _label(doc, doc.get(part, "part_id"), "part id")
        for other in seen:
            if other == label:
                raise Error("canonical part ids must be unique")
        seen.append(label)
        _ = _label(doc, doc.get(part, "tissue_label"), "tissue label")
        if not _is_text(doc, doc.get(part, "frame"), Y_UP_TEXT):
            raise Error("canonical part frame contradicts its snapshot frame")
        if not _is_text(doc, doc.get(part, "origin_label"), origin):
            raise Error("canonical part origin contradicts its snapshot origin")
        var vertices = doc.get(part, "vertices_m")
        var indices = doc.get(part, "triangles")
        if doc.kind(vertices) != PY_LIST or doc.length(vertices) == 0:
            raise Error("a canonical part needs SI vertices")
        for slot in range(doc.length(vertices)):
            _ = _vector(doc, doc.value(vertices, slot))
        if doc.kind(indices) != PY_LIST or doc.length(indices) == 0:
            raise Error("a canonical part needs triangle topology")
        var count = doc.length(vertices)
        for slot in range(doc.length(indices)):
            var face = doc.value(indices, slot)
            if doc.kind(face) != PY_LIST or doc.length(face) != 3:
                raise Error("a canonical triangle needs three indices")
            for corner in range(3):
                var item = doc.value(face, corner)
                if doc.kind(item) != PY_INT or not _index_below(
                    doc.text(item), count
                ):
                    raise Error(
                        "a canonical triangle index is outside its part"
                    )
        var physical = doc.get(part, "physical_properties")
        if not doc.is_none(physical):
            if doc.kind(physical) != PY_DICT or not _is_text(
                doc, doc.get(physical, "tensor_reference"), "center-of-mass"
            ):
                raise Error("canonical part tensors must be about the COM")
            if not _is_text(doc, doc.get(physical, "frame"), Y_UP_TEXT):
                raise Error(
                    "physical property frame contradicts its canonical part"
                    " frame"
                )
            if not _is_text(doc, doc.get(physical, "origin_label"), origin):
                raise Error(
                    "physical property origin contradicts its canonical part"
                    " origin"
                )
            var scratch = PyJson()
            _ = _transform_inertia(
                scratch,
                doc,
                doc.get(physical, "mass_kg"),
                doc,
                doc.get(physical, "center_m"),
                doc,
                doc.get(physical, "inertia_kg_m2"),
                rotate,
                rotate.root,
                zero,
                zero.root,
                zero,
                MISSING,
            )
            _ = _label(
                doc,
                doc.get(physical, "source_report_record"),
                "physical source record",
            )
    check_canonical(doc, snapshot)


def _index_below(digits: String, count: Int) -> Bool:
    """Return whether an int's digits name an index from 0 below `count`."""
    if digits.startswith("-") or digits.byte_length() > 18:
        return False
    try:
        return Int(digits) < count
    except:
        return False


def validate_snapshot(snapshot: PyJson) raises:
    """Validate packaging and SI shape, without inferring anatomical validity.

    A part's `physical_properties` is explicit or null. Null stays
    unsupported. It is never replaced by visual volume or a guessed tissue
    density. Tissue labels are source labels, including the named
    accounting proxies of #289.

    Args:
        snapshot: The snapshot.

    Raises:
        Error: With the Python tool's text for the first problem.
    """
    _check_snapshot(snapshot, snapshot.root)


def make_snapshot(
    canonical_inputs: PyJson,
    source_revision: String,
    parts: PyJson,
    report: PyJson,
    origin_label: String,
    origin_m: Optional[PyJson] = None,
) raises -> PyJson:
    """Copy canonical inputs, part meshes and properties and a full report.

    The report is kept as JSON, with no recalculation or narrowing. An
    empty report is refused. Packaging does not assert that the supplied
    meshes match the report.

    Args:
        canonical_inputs: The canonical SI inputs, a nonempty dict.
        source_revision: The source revision label.
        parts: The canonical parts, a nonempty list.
        report: A complete schema-version-1 or -2 canonical report.
        origin_label: The source origin label.
        origin_m: The origin in meters, or none for zero.

    Returns:
        The validated snapshot.

    Raises:
        Error: With the Python tool's text for the first problem.
    """
    _check_report(report, report.root)
    var origin = origin_m.value().copy() if origin_m else _zeros()
    var coordinates = _vector(origin, origin.root)
    var out = PyJson()
    var root = out.new_dict()
    out.root = root
    out.set(root, "schema_version", out.new_int(SCHEMA))
    var units = out.new_dict()
    out.set(units, "length", out.new_str("meter"))
    out.set(units, "mass", out.new_str("kilogram"))
    out.set(units, "inertia", out.new_str("kilogram-meter-squared"))
    out.set(root, "units", units)
    out.set(root, "frame", out.new_str(Y_UP_TEXT))
    var placed = out.new_list()
    for node in coordinates:
        out.append(placed, out.adopt(origin, node))
    out.set(root, "origin_m", placed)
    out.set(root, "origin_label", out.new_str(origin_label))
    out.set(root, "source_revision", out.new_str(source_revision))
    out.set(
        root,
        "canonical_inputs",
        out.adopt(canonical_inputs, canonical_inputs.root),
    )
    out.set(root, "parts", out.adopt(parts, parts.root))
    out.set(root, "canonical_validity_report", out.adopt(report, report.root))
    out.set(root, "engineering_validated", out.new_bool(False))
    out.set(root, "scope", out.new_str(SCOPE))
    _check_snapshot(out, root)
    return out^


# --- Files ----------------------------------------------------------------------------


def normalize_path(path: String) -> String:
    """Return `str(pathlib.Path(path))` for a POSIX path.

    Args:
        path: The path as given.

    Returns:
        The path without empty and `.` parts or a final slash; `.` for none.
    """
    var root = String()
    if path.startswith("/"):
        root = (
            "//" if path.startswith("//")
            and not path.startswith("///") else "/"
        )
    var parts = List[String]()
    for part in path.split("/"):
        if part.byte_length() > 0 and String(part) != ".":
            parts.append(String(part))
    var joined = root + "/".join(parts)
    return joined if joined.byte_length() > 0 else "."


def _errno(message: String) -> Int:
    """Return the error number of a C library message, or 0."""
    var table: List[Tuple[Int, String]]
    comptime if CompilationTarget.is_macos():
        table = [
            (2, "No such file or directory"),
            (13, "Permission denied"),
            (20, "Not a directory"),
            (21, "Is a directory"),
            (63, "File name too long"),
            (62, "Too many levels of symbolic links"),
            (1, "Operation not permitted"),
            (5, "Input/output error"),
            (6, "Device not configured"),
            (24, "Too many open files"),
            (23, "Too many open files in system"),
        ]
    else:
        table = [
            (2, "No such file or directory"),
            (13, "Permission denied"),
            (20, "Not a directory"),
            (21, "Is a directory"),
            (36, "File name too long"),
            (40, "Too many levels of symbolic links"),
            (1, "Operation not permitted"),
            (5, "Input/output error"),
            (6, "No such device or address"),
            (19, "No such device"),
            (24, "Too many open files"),
            (23, "Too many open files in system"),
            (12, "Cannot allocate memory"),
            (75, "Value too large for defined data type"),
            (116, "Stale file handle"),
        ]
    for entry in table:
        if message.endswith(entry[1]):
            return entry[0]
    return 0


def read_bytes(path: String) raises -> List[UInt8]:
    """Read a file, as `pathlib.Path(path).read_bytes()` does.

    Args:
        path: The path.

    Returns:
        The bytes.

    Raises:
        Error: With Python's `OSError` text, such as
            `[Errno 2] No such file or directory: 'x.json'`.
    """
    var name = normalize_path(path)
    try:
        return Path(name).read_bytes()
    except error:
        var text = String(error)
        var number = _errno(text)
        var reason = text
        var cut = text.rfind(": ")
        if cut >= 0:
            reason = String(text[byte = cut + 2 :])
        var head = "[Errno " + (String(number) if number else "?") + "] "
        raise Error(head + reason + ": " + py_repr(name))


comptime _TEMPORARY = "XXXXXX"


def _write_all(descriptor: c_int, data: List[UInt8]) raises:
    """Write every byte to a file descriptor."""
    var done = 0
    var base = data.unsafe_ptr()
    while done < len(data):
        var written = external_call["write", Int](
            Int(descriptor),
            base.unsafe_offset(done).unsafe_bitcast[NoneType](),
            len(data) - done,
        )
        if written <= 0:
            raise Error("cannot write the canonical snapshot")
        done += written


def _write_snapshot(
    path: String, snapshot: PyJson, interrupt: Bool
) raises -> String:
    """Write a snapshot; `interrupt` fails after the write, as a full disk
    does at `fsync`, so a test can see what an interrupted write leaves."""
    _check_snapshot(snapshot, snapshot.root)
    var data = canonical_bytes(snapshot)
    var name = normalize_path(path)
    var cut = name.rfind("/")
    var parent = String(name[byte=:cut]) if cut > 0 else (
        String("/") if cut == 0 else String(".")
    )
    var leaf = String(name[byte = cut + 1 :])
    # Write a private sibling, then link it into place. A link fails when
    # the path exists, as exclusive creation does, but an interrupted write
    # leaves only the sibling, never a truncated snapshot at the path.
    var template = List[UInt8]()
    for byte in (parent + "/." + leaf + "." + _TEMPORARY).as_bytes():
        template.append(byte)
    template.append(0)
    var descriptor = external_call["mkstemp", c_int](template.unsafe_ptr())
    if descriptor < 0:
        raise Error("cannot create a temporary file beside " + py_repr(name))
    _ = template.pop()
    var temporary = String(unsafe_from_utf8=template)
    try:
        try:
            _write_all(descriptor, data)
            if interrupt:
                raise Error("disk full")
            if external_call["fsync", c_int](descriptor) != 0:
                raise Error("cannot sync the canonical snapshot")
        finally:
            _ = external_call["close", c_int](descriptor)
        var linked = external_call["link", c_int](
            temporary.as_c_string_span().ptr(), name.as_c_string_span().ptr()
        )
        if linked != 0:
            if not exists(name):
                raise Error(
                    "cannot link the canonical snapshot to " + py_repr(name)
                )
            var saved = read_bytes(name)
            var same = len(saved) == len(data)
            if same:
                for index in range(len(data)):
                    if saved[index] != data[index]:
                        same = False
                        break
            if not same:
                raise Error(
                    "canonical snapshot is immutable; choose a new versioned"
                    " path"
                )
    finally:
        remove(temporary)
    return sha256_hex(data)


def write_snapshot(path: String, snapshot: PyJson) raises -> String:
    """Write an immutable snapshot. An existing path must hold its bytes.

    Args:
        path: The versioned path.
        snapshot: The snapshot.

    Returns:
        The SHA-256 of the canonical bytes.

    Raises:
        Error: If the snapshot is not valid, the path holds other bytes, or
            the write fails.
    """
    return _write_snapshot(path, snapshot, False)


def read_snapshot(path: String, expected_sha256: String) raises -> PyJson:
    """Verify immutable bytes before exposing a canonical snapshot.

    Args:
        path: The snapshot path.
        expected_sha256: The SHA-256 that `write_snapshot` returned.

    Returns:
        The validated snapshot.

    Raises:
        Error: With the Python tool's text, if the file cannot be read, its
            bytes changed, or it is not a valid snapshot.
    """
    var data = read_bytes(path)
    if sha256_hex(data) != expected_sha256:
        raise Error("canonical snapshot content changed")
    var snapshot = loads(data)
    _check_snapshot(snapshot, snapshot.root)
    return snapshot^


def visual_derivative(
    snapshot: PyJson, visual_asset: String, recipe: PyJson
) raises -> PyJson:
    """Bind a visual asset to immutable canonical data without replacing it.

    The asset's byte digest detects an external change that a recipe alone
    does not. Every new identity, expression, topology, source or transform
    needs a new recipe. No map is inferred from equal part names or a
    realistic look.

    Args:
        snapshot: A valid snapshot.
        visual_asset: The visual asset's path.
        recipe: The explicit recipe, a nonempty dict.

    Returns:
        The derivative manifest. Every mapping is unsupported.

    Raises:
        Error: If the snapshot or the recipe is not valid, or the asset
            cannot be read.
    """
    _check_snapshot(snapshot, snapshot.root)
    if recipe.kind(recipe.root) != PY_DICT or recipe.length(recipe.root) == 0:
        raise Error("a visual derivative needs an explicit recipe")
    var out = PyJson()
    var root = out.new_dict()
    out.root = root
    out.set(root, "schema_version", out.new_int(SCHEMA))
    out.set(root, "canonical_snapshot_sha256", out.new_str(digest(snapshot)))
    var asset = read_bytes(visual_asset)
    out.set(root, "visual_asset_sha256", out.new_str(sha256_hex(asset)))
    out.set(root, "recipe", out.adopt(recipe, recipe.root))
    out.set(root, "recipe_sha256", out.new_str(digest(recipe)))
    out.set(root, "engineering_use", out.new_bool(False))
    var mappings = out.new_dict()
    for name in [
        "identity",
        "expression_jaw",
        "eyes",
        "dental",
        "skin_weights",
        "lod",
    ]:
        out.set(mappings, name, out.new_str("unsupported"))
    out.set(root, "mappings", mappings)
    var dental = out.new_list()
    out.append(dental, out.new_str("authored-canonical"))
    out.append(dental, out.new_str("scanned-expression"))
    out.set(root, "dental_representations", dental)
    return out^


def validate_derivative(
    manifest: PyJson, snapshot: PyJson, visual_asset: String, recipe: PyJson
) raises:
    """Refuse stale or edited recipes, assets, snapshots and capabilities.

    Args:
        manifest: The derivative manifest.
        snapshot: The snapshot.
        visual_asset: The visual asset's path.
        recipe: The recipe.

    Raises:
        Error: If the manifest does not match a fresh derivative.
    """
    var expected = visual_derivative(snapshot, visual_asset, recipe)
    var held = canonical_bytes(manifest)
    var fresh = canonical_bytes(expected)
    var same = len(held) == len(fresh)
    if same:
        for index in range(len(held)):
            if held[index] != fresh[index]:
                same = False
                break
    if not same:
        raise Error(
            "visual derivative is stale or altered; regenerate its provenance"
        )


# --- The command line -------------------------------------------------------------------


@fieldwise_init
struct Outcome(Copyable, Movable):
    """What the command prints and its exit status."""

    var status: Int
    """The exit status."""
    var output: String
    """The standard output."""
    var errors: String
    """The standard error."""


def _length(text: String) -> Int:
    """Return the number of characters, as Python's `len` counts them."""
    return len(code_points(text, True))


def _wrap(text: String, width: Int) -> List[String]:
    """Wrap single-spaced words as `textwrap.wrap` does without hyphens."""
    var chunks = List[String]()
    var first = True
    for word in text.split(" "):
        if not first:
            chunks.append(" ")
        chunks.append(String(word))
        first = False
    var lines = List[String]()
    var at = 0
    while at < len(chunks):
        var line = List[String]()
        var used = 0
        if chunks[at] == " " and len(lines) > 0:
            at += 1
        while at < len(chunks):
            var size = _length(chunks[at])
            if used + size <= width:
                line.append(chunks[at])
                used += size
                at += 1
            else:
                break
        if at < len(chunks) and _length(chunks[at]) > width:
            var room = 1 if width < 1 else width - used
            var points = code_points(chunks[at], True)
            var head = List[UInt8]()
            var tail = List[UInt8]()
            for index in range(len(points)):
                _append_code(head if index < room else tail, points[index])
            line.append(String(unsafe_from_utf8=head))
            chunks[at] = String(unsafe_from_utf8=tail)
        if len(line) > 0 and line[len(line) - 1] == " ":
            _ = line.pop()
        if len(line) > 0:
            lines.append("".join(line))
    return lines^


def _append_code(mut out: List[UInt8], point: Int):
    """Append a code point; an escaped byte becomes its byte again."""
    if point >= 0xDC80 and point <= 0xDCFF:
        out.append(UInt8(point - 0xDC00))
        return
    if point < 0x80:
        out.append(UInt8(point))
    elif point < 0x800:
        out.append(UInt8(0xC0 | (point >> 6)))
        out.append(UInt8(0x80 | (point & 0x3F)))
    elif point < 0x10000:
        out.append(UInt8(0xE0 | (point >> 12)))
        out.append(UInt8(0x80 | ((point >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (point & 0x3F)))
    else:
        out.append(UInt8(0xF0 | (point >> 18)))
        out.append(UInt8(0x80 | ((point >> 12) & 0x3F)))
        out.append(UInt8(0x80 | ((point >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (point & 0x3F)))


def _usage(program: String, width: Int) -> String:
    """Return the usage text, as `argparse` wraps it, with one newline."""
    var prefix = "usage: "
    var parts: List[String] = ["[-h]", "--sha256", "SHA256"]
    var usage = program + " [-h] --sha256 SHA256 snapshot"
    if _length(prefix) + _length(usage) <= width:
        return prefix + usage + "\n"
    var lines: List[String]
    var prog_length = _length(program)
    if Float64(_length(prefix) + prog_length) <= 0.75 * Float64(width):
        var indent = " " * (_length(prefix) + prog_length + 1)
        var first: List[String] = [program]
        first.extend(parts.copy())
        lines = _usage_lines(first, indent, True, width)
        lines.extend(_usage_lines(["snapshot"], indent, False, width))
    else:
        var indent = " " * _length(prefix)
        var all = parts.copy()
        all.append("snapshot")
        lines = _usage_lines(all, indent, False, width)
        if len(lines) > 1:
            lines = _usage_lines(parts, indent, False, width)
            lines.extend(_usage_lines(["snapshot"], indent, False, width))
        lines.insert(0, program)
    return prefix + "\n".join(lines) + "\n"


def _usage_lines(
    parts: List[String], indent: String, prefixed: Bool, width: Int
) -> List[String]:
    """Return `get_lines` of `argparse`'s usage wrapping."""
    var lines = List[String]()
    var line = List[String]()
    var indent_length = _length(indent)
    var used = 6 if prefixed else indent_length - 1
    for part in parts:
        if used + 1 + _length(part) > width and len(line) > 0:
            lines.append(indent + " ".join(line))
            line = List[String]()
            used = indent_length - 1
        line.append(part)
        used += _length(part) + 1
    if len(line) > 0:
        lines.append(indent + " ".join(line))
    if prefixed:
        var head = String(lines[0][byte=indent_length:])
        lines[0] = head
    return lines^


def _help(program: String, width: Int) -> String:
    """Return the `--help` text, as `argparse` formats it."""
    var text = _usage(program, width) + "\n"
    text += "\n".join(_wrap(DESCRIPTION, max(width, 11))) + "\n\n"
    text += "positional arguments:\n  snapshot\n\noptions:\n"
    var maximum = min(24, max(width - 20, 4))
    var position = min(17 + 2, maximum)
    var help_width = max(width - position, 11)
    var action_width = position - 2 - 2
    var header = "-h, --help"
    var lines = _wrap("show this help message and exit", help_width)
    if _length(header) <= action_width:
        text += "  " + header + " " * (action_width - _length(header)) + "  "
        text += lines[0] + "\n"
    else:
        text += "  " + header + "\n" + " " * position + lines[0] + "\n"
    for index in range(1, len(lines)):
        text += " " * position + lines[index] + "\n"
    text += "  --sha256 SHA256\n"
    return text


def _columns(value: String) -> Int:
    """Return the terminal width that `shutil.get_terminal_size` gives for
    a `COLUMNS` value when the output is not a terminal."""
    var text = String(value.strip())
    var bytes = text.as_bytes()
    var at = 0
    var negative = False
    if len(bytes) > 0 and (bytes[0] == 43 or bytes[0] == 45):
        negative = bytes[0] == 45
        at = 1
    var number = 0
    var digits = 0
    var previous_digit = False
    while at < len(bytes):
        var byte = bytes[at]
        if byte >= 48 and byte <= 57:
            if number < 100000000:
                number = number * 10 + Int(byte) - 48
            digits += 1
            previous_digit = True
        elif byte == 95 and previous_digit and at + 1 < len(bytes):
            previous_digit = False
        else:
            return 80
        at += 1
    if digits == 0 or not previous_digit:
        return 80
    if negative or number <= 0:
        return 80
    return number


@fieldwise_init
struct _Option(Copyable, Movable):
    """An argument as `argparse._parse_optional` classifies it."""

    var kind: Int
    """0 positional, 1 `-h`, 2 `--sha256`, 3 unknown option, 4 ambiguous."""
    var option: String
    """The option string, or the ambiguous matches joined."""
    var sep: Int
    """0 for no explicit argument, 1 for `=`, 2 for a joined argument."""
    var explicit: String
    """The explicit argument."""


def _positional() -> _Option:
    """Return the classification of a positional argument."""
    return _Option(0, String(), 0, String())


def _option(argument: String) -> _Option:
    """Classify an argument as `argparse._parse_optional` does.

    Returns:
        The classification.
    """
    if argument.byte_length() == 0 or not argument.startswith("-"):
        return _positional()
    if argument == "-h" or argument == "--help":
        return _Option(1, argument, 0, String())
    if argument == "--sha256":
        return _Option(2, argument, 0, String())
    if argument.byte_length() == 1:
        return _positional()
    var equals = argument.find("=")
    var prefix = argument
    var sep = 0
    var explicit = String()
    if equals >= 0:
        prefix = String(argument[byte=:equals])
        sep = 1
        explicit = String(argument[byte = equals + 1 :])
        if prefix == "-h" or prefix == "--help":
            return _Option(1, prefix, 1, explicit)
        if prefix == "--sha256":
            return _Option(2, prefix, 1, explicit)
    var matches = List[_Option]()
    var options: List[Tuple[Int, String]] = [
        (1, "-h"),
        (1, "--help"),
        (2, "--sha256"),
    ]
    if argument.startswith("--"):
        for entry in options:
            if entry[1].startswith(prefix):
                matches.append(_Option(entry[0], entry[1], sep, explicit))
    else:
        var short = _first_chars(argument, 2)
        var rest = String(argument[byte = short.byte_length() :])
        for entry in options:
            if entry[1] == short:
                matches.append(_Option(entry[0], entry[1], 2, rest))
            elif entry[1].startswith(prefix):
                matches.append(_Option(entry[0], entry[1], sep, explicit))
    if len(matches) == 1:
        return matches[0].copy()
    if len(matches) > 1:
        var names = List[String]()
        for entry in matches:
            names.append(entry.option)
        return _Option(4, ", ".join(names), 0, String())
    if _negative_number(argument):
        return _positional()
    if argument.find(" ") >= 0:
        return _positional()
    return _Option(3, argument, 0, String())


def _first_chars(text: String, count: Int) -> String:
    """Return the first characters of a str."""
    var points = code_points(text, True)
    var out = List[UInt8]()
    for index in range(min(count, len(points))):
        _append_code(out, points[index])
    return String(unsafe_from_utf8=out)


def _negative_number(text: String) -> Bool:
    """Return whether text matches `^-\\d+$|^-\\d*\\.\\d+$`."""
    var bytes = text.as_bytes()
    if len(bytes) < 2 or bytes[0] != 45:
        return False
    var at = 1
    var before = 0
    while at < len(bytes) and bytes[at] >= 48 and bytes[at] <= 57:
        at += 1
        before += 1
    if at == len(bytes):
        return before > 0
    if bytes[at] != 46:
        return False
    at += 1
    var after = 0
    while at < len(bytes) and bytes[at] >= 48 and bytes[at] <= 57:
        at += 1
        after += 1
    return at == len(bytes) and after > 0


@fieldwise_init
struct _Parsed(Copyable, Movable):
    """The parsed command line, or the reason it was refused."""

    var help: Bool
    """True when `-h` asked for the help text."""
    var error: String
    """The `argparse` error, or empty."""
    var snapshot: String
    """The snapshot path."""
    var digest: String
    """The expected SHA-256."""


def _help_flags(found: _Option, mut extras: List[String]) -> String:
    """Follow `-h` with an explicit argument as `consume_optional` does.

    Returns:
        The error, or empty when the help text is shown.
    """
    var option = found.option
    var sep = found.sep
    var explicit = found.explicit
    while sep != 0:
        if option.startswith("--") or explicit.byte_length() == 0:
            return "argument -h/--help: ignored explicit argument " + py_repr(
                explicit
            )
        if sep == 1 or explicit.startswith("-"):
            return "argument -h/--help: ignored explicit argument " + py_repr(
                explicit
            )
        var letter = _first_chars(explicit, 1)
        if letter != "h":
            extras.append("-" + explicit)
            return String()
        var tail = String(explicit[byte=1:])
        explicit = tail
        option = "-h"
        if explicit.byte_length() == 0:
            sep = 0
        elif explicit.startswith("="):
            sep = 1
            var value = String(explicit[byte=1:])
            explicit = value
        else:
            sep = 2
    return String()


def _parse(arguments: List[String]) -> _Parsed:
    """Parse the command line as the Python tool's `argparse` parser did."""
    var pattern = List[UInt8]()
    var found = List[_Option]()
    var dashes = False
    for argument in arguments:
        if dashes:
            pattern.append(65)
            found.append(_positional())
        elif argument == "--":
            dashes = True
            pattern.append(45)
            found.append(_positional())
        else:
            var option = _option(argument)
            pattern.append(UInt8(65 if option.kind == 0 else 79))
            found.append(option^)
    var result = _Parsed(False, String(), String(), String())
    var have_snapshot = False
    var have_digest = False
    var extras = List[String]()
    var last_option = -1
    for index in range(len(pattern)):
        if pattern[index] == 79:
            last_option = index
    var start = 0
    while start <= last_option:
        var next_option = start
        while pattern[next_option] != 79:
            next_option += 1
        if start != next_option and not have_snapshot:
            var stop = _positionals(arguments, pattern, start, result)
            if stop > start:
                have_snapshot = True
                start = stop
                continue
        if pattern[start] != 79:
            for index in range(start, next_option):
                extras.append(arguments[index])
            start = next_option
        ref option = found[start]
        if option.kind == 4:
            result.error = (
                "ambiguous option: "
                + arguments[start]
                + " could match "
                + option.option
            )
            return result^
        if option.kind == 3:
            extras.append(arguments[start])
            start += 1
            continue
        if option.kind == 1:
            var problem = _help_flags(option, extras)
            if problem:
                result.error = problem
                return result^
            result.help = True
            return result^
        # --sha256 takes exactly one argument.
        if option.sep != 0:
            result.digest = option.explicit
            have_digest = True
            start += 1
            continue
        if start + 1 >= len(pattern) or pattern[start + 1] != 65:
            result.error = "argument --sha256: expected one argument"
            return result^
        result.digest = arguments[start + 1]
        have_digest = True
        start += 2
    var stop = start
    if not have_snapshot:
        stop = _positionals(arguments, pattern, start, result)
        if stop > start:
            have_snapshot = True
    for index in range(stop, len(arguments)):
        extras.append(arguments[index])
    var required = List[String]()
    if not have_snapshot:
        required.append("snapshot")
    if not have_digest:
        required.append("--sha256")
    if len(required) > 0:
        result.error = "the following arguments are required: " + ", ".join(
            required
        )
        return result^
    if len(extras) > 0:
        result.error = "unrecognized arguments: " + " ".join(extras)
    return result^


def _positionals(
    arguments: List[String],
    pattern: List[UInt8],
    start: Int,
    mut result: _Parsed,
) -> Int:
    """Consume the snapshot argument as `consume_positionals` does.

    Returns:
        The index after the consumed arguments, or `start` for none.
    """
    # Match (-*A-*) at `start`.
    var at = start
    while at < len(pattern) and pattern[at] == 45:
        at += 1
    if at >= len(pattern) or pattern[at] != 65:
        return start
    at += 1
    while at < len(pattern) and pattern[at] == 45:
        at += 1
    var values = List[String]()
    var removed = False
    for index in range(start, at):
        if pattern[index] == 45 and not removed:
            removed = True
            continue
        values.append(arguments[index])
    result.snapshot = values[0]
    return at


def run(arguments: List[String], program: String, columns: Int) -> Outcome:
    """Validate a snapshot by its supplied SHA-256, without changing it.

    Args:
        arguments: The command-line arguments, without the program name.
        program: The program name for the usage line.
        columns: The terminal width that Python's `argparse` would use.

    Returns:
        The exit status and the text for each stream.
    """
    var width = columns - 2
    var parsed = _parse(arguments)
    if parsed.help:
        return Outcome(0, _help(program, width), String())
    if parsed.error:
        return Outcome(
            2,
            String(),
            _usage(program, width)
            + program
            + ": error: "
            + parsed.error
            + "\n",
        )
    try:
        _ = read_snapshot(parsed.snapshot, parsed.digest)
    except error:
        var text = String(error)
        if text.startswith(OVERFLOW) or text.startswith(RECURSION):
            return Outcome(1, String(), text + "\n")
        return Outcome(2, String(), _FAILED + text + "\n")
    return Outcome(0, VERIFIED + "\n", String())


def main() raises:
    """Run the command line and exit with its status.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var program = String(PROGRAM)
    if len(given) > 0:
        var first = String(given[0])
        var cut = first.rfind("/")
        var name = String(first[byte = cut + 1 :])
        if name.byte_length() > 0:
            program = name
    var outcome = run(arguments, program, _columns(getenv("COLUMNS")))
    print(outcome.output, end="")
    print(outcome.errors, end="", file=stderr)
    exit(outcome.status)
