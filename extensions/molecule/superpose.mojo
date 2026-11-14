# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Superpose two sets of atoms, and measure how far apart they are.

Two models of one molecule, such as the models of an NMR ensemble or a
crystal structure and a prediction, must be put on top of each other
before they can be compared. `superpose` finds the rotation and the
translation that put the moving points on the fixed points with the
least root mean square deviation (RMSD). This is the problem of Kabsch.

The method is Horn's. Both sets are centered on their centroids. The
best rotation is the unit quaternion of the largest eigenvalue of a
symmetric 4 by 4 matrix built from their cross-covariance. A quaternion
is always a proper rotation, so the fit never mirrors a set.

`matched_atoms` pairs the atoms of two models by chain label, residue
number, insertion code and atom name, such as the CA atoms.
"""

from extensions.molecule.ids import ModelId
from extensions.molecule.structure import Structure
from extensions.sdf.vector import V3, dot, v3
from std.collections import Dict
from std.math import isfinite, sqrt
from units.si import Length64, METER

# Cyclic Jacobi sweeps of a symmetric 4 by 4 matrix.
comptime JACOBI_SWEEPS_4 = 16


struct Superposition(Copyable, Movable):
    """A rotation and a translation that move one set onto another."""

    var rotation: List[Float64]
    """The 3 by 3 rotation, row by row."""
    var translation: V3
    """The translation after the rotation, in meters."""
    var rmsd: Length64
    """The RMSD of the moved set from the fixed set."""

    def __init__(
        out self, rotation: List[Float64], translation: V3, rmsd: Length64
    ):
        """Create a superposition.

        Args:
            rotation: Nine numbers, row by row.
            translation: The translation, in meters.
            rmsd: The deviation after the move.
        """
        self.rotation = rotation.copy()
        self.translation = translation
        self.rmsd = rmsd

    def apply(self, p: V3) -> V3:
        """Return a point moved by the superposition.

        Args:
            p: The point, in meters.

        Returns:
            `R p + t`.
        """
        ref r = self.rotation
        return (
            v3(
                r[0] * p.x + r[1] * p.y + r[2] * p.z,
                r[3] * p.x + r[4] * p.y + r[5] * p.z,
                r[6] * p.x + r[7] * p.y + r[8] * p.z,
            )
            + self.translation
        )


def rmsd(fixed: List[V3], moving: List[V3]) raises -> Length64:
    """Return the RMSD of two sets of points, without moving them.

    Args:
        fixed: The points, in meters.
        moving: The same number of points, in meters.

    Returns:
        `sqrt(mean(|fixed[i] - moving[i]|^2))`.

    Raises:
        Error: If the sets are empty or differ in size.
    """
    if len(fixed) == 0 or len(fixed) != len(moving):
        raise Error("An RMSD needs two sets of points of one size")
    var total = 0.0
    for index in range(len(fixed)):  # pragma: no branch
        var d = fixed[index] - moving[index]
        total += dot(d, d)
    return Length64(sqrt(total / Float64(len(fixed))), METER)


def _centroid(points: List[V3]) -> V3:
    """Return the mean of some points."""
    var sum = v3(0, 0, 0)
    for p in points:  # pragma: no branch
        sum = sum + p
    return sum * (1.0 / Float64(len(points)))


def _jacobi_rotate(mut a: List[Float64], mut r: List[Float64], p: Int, q: Int):
    """Zero `a[p][q]` of a 4 by 4 matrix, and keep the rotation in `r`."""
    var apq = a[4 * p + q]
    if apq == 0:
        return
    var theta = (a[4 * q + q] - a[4 * p + p]) / (2.0 * apq)
    var t = 1.0 / (abs(theta) + sqrt(theta * theta + 1.0))
    if theta < 0:
        t = -t
    var c = 1.0 / sqrt(t * t + 1.0)
    var s = t * c
    for k in range(4):  # pragma: no branch
        var akp = a[4 * k + p]
        var akq = a[4 * k + q]
        a[4 * k + p] = c * akp - s * akq
        a[4 * k + q] = s * akp + c * akq
    for k in range(4):  # pragma: no branch
        var apk = a[4 * p + k]
        var aqk = a[4 * q + k]
        a[4 * p + k] = c * apk - s * aqk
        a[4 * q + k] = s * apk + c * aqk
    for k in range(4):  # pragma: no branch
        var rkp = r[4 * k + p]
        var rkq = r[4 * k + q]
        r[4 * k + p] = c * rkp - s * rkq
        r[4 * k + q] = s * rkp + c * rkq


def superpose(fixed: List[V3], moving: List[V3]) raises -> Superposition:
    """Return the move that puts `moving` on `fixed` with the least RMSD.

    Args:
        fixed: The points that stay, in meters.
        moving: The points to move, in the same order. At least three.

    Returns:
        The rotation, the translation and the RMSD after the move.

    Raises:
        Error: If the sets differ in size or hold fewer than three points,
            or a coordinate is not finite.
    """
    if len(fixed) != len(moving) or len(fixed) < 3:
        raise Error("A superposition needs two sets of three or more points")
    for index in range(len(fixed)):  # pragma: no branch
        var f = fixed[index]
        var m = moving[index]
        var sum = f.x + f.y + f.z + m.x + m.y + m.z
        if not isfinite(sum):
            raise Error("A superposition needs finite coordinates")
    var fixed_center = _centroid(fixed)
    var moving_center = _centroid(moving)
    # The cross-covariance, s[3 i + j] = sum of moving_i * fixed_j.
    var s = List[Float64](length=9, fill=0)
    for index in range(len(fixed)):  # pragma: no branch
        var a = moving[index] - moving_center
        var b = fixed[index] - fixed_center
        var ma = [a.x, a.y, a.z]
        var fb = [b.x, b.y, b.z]
        for i in range(3):  # pragma: no branch
            for j in range(3):  # pragma: no branch
                s[3 * i + j] += ma[i] * fb[j]
    var xx = s[0]
    var xy = s[1]
    var xz = s[2]
    var yx = s[3]
    var yy = s[4]
    var yz = s[5]
    var zx = s[6]
    var zy = s[7]
    var zz = s[8]
    var n: List[Float64] = [
        xx + yy + zz,
        yz - zy,
        zx - xz,
        xy - yx,
        yz - zy,
        xx - yy - zz,
        xy + yx,
        zx + xz,
        zx - xz,
        xy + yx,
        -xx + yy - zz,
        yz + zy,
        xy - yx,
        zx + xz,
        yz + zy,
        -xx - yy + zz,
    ]
    var vectors: List[Float64] = [
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
    ]
    for _ in range(JACOBI_SWEEPS_4):  # pragma: no branch
        for pair in [  # pragma: no branch
            (0, 1),
            (0, 2),
            (0, 3),
            (1, 2),
            (1, 3),
            (2, 3),
        ]:
            _jacobi_rotate(n, vectors, pair[0], pair[1])
    var best = 0
    for k in range(1, 4):  # pragma: no branch
        if n[5 * k] > n[5 * best]:
            best = k
    var w = vectors[best]
    var x = vectors[4 + best]
    var y = vectors[8 + best]
    var z = vectors[12 + best]
    var rotation: List[Float64] = [
        1 - 2 * (y * y + z * z),
        2 * (x * y - w * z),
        2 * (x * z + w * y),
        2 * (x * y + w * z),
        1 - 2 * (x * x + z * z),
        2 * (y * z - w * x),
        2 * (x * z - w * y),
        2 * (y * z + w * x),
        1 - 2 * (x * x + y * y),
    ]
    var placed = Superposition(rotation, v3(0, 0, 0), Length64(0, METER))
    placed.translation = fixed_center - placed.apply(moving_center)
    var moved = List[V3]()
    for p in moving:  # pragma: no branch
        moved.append(placed.apply(p))
    placed.rmsd = rmsd(fixed, moved)
    return placed^


def matched_atoms(
    fixed: Structure,
    fixed_model: ModelId,
    moving: Structure,
    moving_model: ModelId,
    name: String,
) raises -> List[Tuple[Int, Int]]:
    """Return the pairs of atoms of one name that two models share.

    Two atoms pair when their chains have one label, their residues one
    number and insertion code, and both have the name. Of atoms with one
    key, such as alternate locations, the first in the file pairs.

    Args:
        fixed: The structure that stays.
        fixed_model: Its model.
        moving: The structure to move. It can be `fixed`.
        moving_model: Its model.
        name: The atom name, such as `CA`.

    Returns:
        The indexes of the paired atoms in `fixed.atoms` and
        `moving.atoms`, in the order of the fixed model.

    Raises:
        Error: If a model id names no model.
    """
    var keys = Dict[String, Int]()
    var span = moving.model_atoms(moving_model)
    for index in range(span[0], span[0] + span[1]):  # pragma: no branch
        if moving.atoms[index].name == name:
            var key = _key(moving, index)
            if key not in keys:
                keys[key] = index
    var pairs = List[Tuple[Int, Int]]()
    var own = fixed.model_atoms(fixed_model)
    var seen = Dict[String, Bool]()
    for index in range(own[0], own[0] + own[1]):  # pragma: no branch
        if fixed.atoms[index].name != name:
            continue
        var key = _key(fixed, index)
        if key in seen:
            continue
        seen[key] = True
        var other = keys.get(key)
        if other:
            pairs.append((index, other.value()))
    return pairs^


def _key(structure: Structure, atom: Int) -> String:
    """Return the chain label, residue number and insertion of an atom."""
    ref residue = structure.residues[structure.atoms[atom].residue.value]
    ref chain = structure.chains[residue.chain.value]
    return (
        String(chain.label, "|", residue.seq_id, "|", residue.auth_seq_id, "|")
        + residue.insertion
    )
