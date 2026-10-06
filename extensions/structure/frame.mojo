# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The two-node Euler-Bernoulli frame element in three dimensions.

Each node has six degrees of freedom, so the element has twelve. In the
local axes they are, per node: the translations along x, y and z and the
rotations about x, y and z. The local x axis runs from the start node to
the end node. The local z axis is the part of a reference vector normal to
x; it is the direction of the section depth. The local y axis is z × x,
the direction of the section width.

Bending in the x-z plane, about the local y axis, uses the strong second
moment of the section. Bending in the x-y plane, about the local z axis,
uses the weak one. Torsion uses Saint-Venant's constant and the shear
modulus. The matrices are those of Przemieniecki, "Theory of Matrix
Structural Analysis", 1968, sections 5.6 and 11.3. The element has no
shear deformation and no end releases.
"""

from std.math import isfinite
from extensions.building.material import BuildingMaterial
from extensions.building.model import Section
from extensions.numerics.dense import DenseMatrix
from generators.utils import Vec3d
from units.si import (
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    LineLoad64,
    METER,
    METER_TO_THE_FOURTH,
    NEWTON_PER_METER,
    PASCAL,
    SQUARE_METER,
)

# Below this sine, a reference vector is parallel to the member axis.
comptime _PARALLEL = 1e-6


@fieldwise_init
struct LocalAxes(ImplicitlyCopyable):
    """The unit local axes of a member, in global coordinates."""

    # Along the member, from the start node to the end node.
    var x: Vec3d
    # Across the section width.
    var y: Vec3d
    # Across the section depth.
    var z: Vec3d

    def to_local(self, v: Vec3d) -> Vec3d:
        """Return a global vector in the local axes.

        Args:
            v: The vector in global coordinates.

        Returns:
            Its components along the local x, y and z axes.
        """
        return Vec3d(v.dot(self.x), v.dot(self.y), v.dot(self.z))

    def to_global(self, v: Vec3d) -> Vec3d:
        """Return a local vector in global coordinates.

        Args:
            v: The components along the local x, y and z axes.

        Returns:
            The vector in global coordinates.
        """
        return self.x * v.x + self.y * v.y + self.z * v.z


def member_axes(start: Vec3d, end: Vec3d, reference: Vec3d) raises -> LocalAxes:
    """Return the local axes of a member.

    The local z axis is the part of the reference vector normal to the
    member. If the reference vector is parallel to the member, the global
    z axis is used instead. If the member is vertical too, the global x
    axis is used. So a column with any reference has its depth along x.

    Args:
        start: The start node, in meters.
        end: The end node, in meters.
        reference: A vector in the plane of the local x and z axes.

    Returns:
        The local axes.

    Raises:
        Error: If a point or the reference is not finite, the ends are the
            same point, or the reference is zero.
    """
    var values = [
        start.x,
        start.y,
        start.z,
        end.x,
        end.y,
        end.z,
        reference.x,
        reference.y,
        reference.z,
    ]
    for i in range(len(values)):  # pragma: no branch
        if not isfinite(values[i]):
            raise Error("A member's ends and reference must be finite")
    var axis = end - start
    var length = axis.length()
    if not (length > 0):
        raise Error("A member's ends must differ")
    if not (reference.length() > 0):
        raise Error("A member's reference vector must not be zero")
    var x = axis * (1 / length)
    var c = reference.normalized()
    if x.cross(c).length() <= _PARALLEL:
        c = Vec3d(0, 0, 1)
        if x.cross(c).length() <= _PARALLEL:
            c = Vec3d(1, 0, 0)
    var z = (c - x * c.dot(x)).normalized()
    return LocalAxes(x, z.cross(x), z)


def _check(
    length: Length64, section: Section, material: BuildingMaterial
) raises:
    """Refuse a member length, section or material that cannot be used."""
    var l = length.to(METER)
    if not (l > 0 and isfinite(l)):
        raise Error("A member length must be positive and finite")
    section.check()
    material.check()


def _put(
    mut m: DenseMatrix,
    index: List[Int],
    block: List[Float64],
    scale: Float64,
):
    """Add a scaled 4 by 4 block, row-major, at the given indices."""
    for r in range(4):  # pragma: no branch
        for c in range(4):  # pragma: no branch
            m.add(index[r], index[c], scale * block[4 * r + c])


def _put_pair(mut m: DenseMatrix, i: Int, diagonal: Float64, coupling: Float64):
    """Add a two-node term of one degree of freedom at both ends."""
    m.add(i, i, diagonal)
    m.add(i + 6, i + 6, diagonal)
    m.add(i, i + 6, coupling)
    m.add(i + 6, i, coupling)


def frame_local_stiffness(
    length: Length64, section: Section, material: BuildingMaterial
) raises -> DenseMatrix:
    """Return the 12 by 12 stiffness of a member in its local axes.

    The axial terms are EA/L, the torsion terms GJ/L and the bending terms
    the cubic Hermite values 12EI/L³, 6EI/L², 4EI/L and 2EI/L.

    Args:
        length: The member length.
        section: The cross-section.
        material: The material. Its modulus and Poisson's ratio are used.

    Returns:
        The stiffness, in newtons per meter, newtons per radian and newton
        meters per radian.

    Raises:
        Error: If the length is not positive and finite, or the section or
            the material is not valid.
    """
    _check(length, section, material)
    var l = length.to(METER)
    var e = material.elastic_modulus.to(PASCAL)
    var g = material.shear_modulus().to(PASCAL)
    var a = section.area().to(SQUARE_METER)
    var iy = section.strong_inertia().to(METER_TO_THE_FOURTH)
    var iz = section.weak_inertia().to(METER_TO_THE_FOURTH)
    var j = section.torsion_constant().to(METER_TO_THE_FOURTH)
    var k = DenseMatrix(12, 12)
    var axial = e * a / l
    var torsion = g * j / l
    _put_pair(k, 0, axial, -axial)
    _put_pair(k, 3, torsion, -torsion)
    # Bending in the x-y plane: v and the rotation about z.
    var xy: List[Float64] = [
        12,
        6 * l,
        -12,
        6 * l,
        6 * l,
        4 * l * l,
        -6 * l,
        2 * l * l,
        -12,
        -6 * l,
        12,
        -6 * l,
        6 * l,
        2 * l * l,
        -6 * l,
        4 * l * l,
    ]
    _put(k, [1, 5, 7, 11], xy, e * iz / (l * l * l))
    # Bending in the x-z plane: w and the rotation about y = -dw/dx.
    var xz: List[Float64] = [
        12,
        -6 * l,
        -12,
        -6 * l,
        -6 * l,
        4 * l * l,
        6 * l,
        2 * l * l,
        -12,
        6 * l,
        12,
        6 * l,
        -6 * l,
        2 * l * l,
        6 * l,
        4 * l * l,
    ]
    _put(k, [2, 4, 8, 10], xz, e * iy / (l * l * l))
    return k^


def frame_local_mass(
    length: Length64, section: Section, material: BuildingMaterial
) raises -> DenseMatrix:
    """Return the 12 by 12 consistent mass of a member in its local axes.

    The translational terms come from the cubic Hermite shape functions.
    The rotary inertia of the section in bending and its polar inertia in
    torsion are included, as in Przemieniecki, section 11.3.

    Args:
        length: The member length.
        section: The cross-section.
        material: The material. Its density is used.

    Returns:
        The mass, in kilograms and kilogram square meters.

    Raises:
        Error: If the length is not positive and finite, or the section or
            the material is not valid.
    """
    _check(length, section, material)
    var l = length.to(METER)
    var rho = material.density.to(KILOGRAM_PER_CUBIC_METER)
    var a = section.area().to(SQUARE_METER)
    var iy = section.strong_inertia().to(METER_TO_THE_FOURTH)
    var iz = section.weak_inertia().to(METER_TO_THE_FOURTH)
    var m = DenseMatrix(12, 12)
    var mass = rho * a * l
    var polar = rho * (iy + iz) * l
    _put_pair(m, 0, mass / 3, mass / 6)
    _put_pair(m, 3, polar / 3, polar / 6)
    var trans_xy: List[Float64] = [
        156,
        22 * l,
        54,
        -13 * l,
        22 * l,
        4 * l * l,
        13 * l,
        -3 * l * l,
        54,
        13 * l,
        156,
        -22 * l,
        -13 * l,
        -3 * l * l,
        -22 * l,
        4 * l * l,
    ]
    var rot_xy: List[Float64] = [
        36,
        3 * l,
        -36,
        3 * l,
        3 * l,
        4 * l * l,
        -3 * l,
        -l * l,
        -36,
        -3 * l,
        36,
        -3 * l,
        3 * l,
        -l * l,
        -3 * l,
        4 * l * l,
    ]
    # The x-z plane flips the sign of each term that couples a translation
    # to a rotation, because the rotation about y is -dw/dx.
    var trans_xz = trans_xy.copy()
    var rot_xz = rot_xy.copy()
    for r in range(4):  # pragma: no branch
        for c in range(4):  # pragma: no branch
            if (r == 1 or r == 3) != (c == 1 or c == 3):
                trans_xz[4 * r + c] = -trans_xz[4 * r + c]
                rot_xz[4 * r + c] = -rot_xz[4 * r + c]
    var xy_index: List[Int] = [1, 5, 7, 11]
    var xz_index: List[Int] = [2, 4, 8, 10]
    _put(m, xy_index, trans_xy, mass / 420)
    _put(m, xy_index, rot_xy, rho * iz / (30 * l))
    _put(m, xz_index, trans_xz, mass / 420)
    _put(m, xz_index, rot_xz, rho * iy / (30 * l))
    return m^


def frame_transformation(axes: LocalAxes) raises -> DenseMatrix:
    """Return the 12 by 12 matrix T with local = T global.

    T has four copies of the 3 by 3 rotation on its diagonal. Its rows are
    the local axes. A global matrix is Tᵀ K T.

    Args:
        axes: The member's local axes.

    Returns:
        The transformation.

    Raises:
        Error: Never, for axes made by `member_axes`.
    """
    var t = DenseMatrix(12, 12)
    var rows = [axes.x, axes.y, axes.z]
    for b in range(4):  # pragma: no branch
        for r in range(3):  # pragma: no branch
            var o = 3 * b
            t.set(o + r, o, rows[r].x)
            t.set(o + r, o + 1, rows[r].y)
            t.set(o + r, o + 2, rows[r].z)
    return t^


def uniform_load_vector(
    length: Length64, wx: LineLoad64, wy: LineLoad64, wz: LineLoad64
) raises -> List[Float64]:
    """Return the consistent nodal loads of a uniform load, in local axes.

    Each node takes half the force. The bending moments are w L² / 12 at
    each end, with the signs that the fixed-end moments oppose.

    Args:
        length: The member length.
        wx: The load per length along the local x axis.
        wy: The load per length along the local y axis.
        wz: The load per length along the local z axis.

    Returns:
        Twelve nodal loads, in newtons and newton meters.

    Raises:
        Error: If the length is not positive and finite, or a load is not
            finite.
    """
    var l = length.to(METER)
    if not (l > 0 and isfinite(l)):
        raise Error("A member length must be positive and finite")
    var x = wx.to(NEWTON_PER_METER)
    var y = wy.to(NEWTON_PER_METER)
    var z = wz.to(NEWTON_PER_METER)
    if not (isfinite(x) and isfinite(y) and isfinite(z)):
        raise Error("A line load must be finite")
    var f = List[Float64](length=12, fill=0)
    var half = l / 2
    var twelfth = l * l / 12
    f[0] = x * half
    f[6] = x * half
    f[1] = y * half
    f[7] = y * half
    f[5] = y * twelfth
    f[11] = -y * twelfth
    f[2] = z * half
    f[8] = z * half
    f[4] = -z * twelfth
    f[10] = z * twelfth
    return f^
