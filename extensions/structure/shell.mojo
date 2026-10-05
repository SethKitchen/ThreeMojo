# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The three-node flat shell element.

The element adds three parts in its own plane:

- The membrane is the constant-strain triangle. Its stress is constant.
- The plate is the discrete Kirchhoff triangle of Batoz, Bathe and Ho, "A
  study of three-node triangular plate bending elements", International
  Journal for Numerical Methods in Engineering 15, 1980. Its rotations
  are quadratic, and the Kirchhoff constraint holds at the corners and the
  side midpoints. Three interior Gauss points integrate it exactly.
- The drilling stiffness ties each corner's rotation about the normal to
  the rotation of the membrane, with the penalty of Hughes and Brezzi,
  "On drilling degrees of freedom", Computer Methods in Applied Mechanics
  and Engineering 72, 1989. Its modulus is a thousandth of G t.

The material is isotropic, in plane stress. The local x axis runs from the
first corner to the second. The local z axis is the normal, by the right
hand rule over the corners. The local y axis is z × x.

The rotation about the local x axis is ∂w/∂y and the rotation about the
local y axis is -∂w/∂x. These are right-handed rotations, the same as the
frame element's.
"""

from std.math import isfinite
from extensions.building.material import BuildingMaterial
from extensions.numerics.dense import DenseMatrix
from extensions.structure.frame import LocalAxes
from generators.utils import Vec3d
from units.si import Force64, Length64, METER, PASCAL, Pressure64

# The drilling penalty modulus, as a share of G t.
comptime _DRILLING = 1e-3


@fieldwise_init
struct ShellResultants(ImplicitlyCopyable):
    """The stresses and moments of a shell element, in its local axes.

    The membrane stresses are constant over the element. The moments are
    per unit length, at the centroid: mx = -D (w,xx + ν w,yy), my = -D
    (w,yy + ν w,xx) and mxy = -D (1 - ν) w,xy.
    """

    var axes: LocalAxes
    var sigma_x: Pressure64
    var sigma_y: Pressure64
    var tau_xy: Pressure64
    # Newton meters per meter.
    var m_x: Force64
    var m_y: Force64
    var m_xy: Force64


def _shape_derivatives(xi: Float64, eta: Float64) -> List[Float64]:
    """Return dN/dξ for the six quadratic shape functions, then dN/dη."""
    var s = 1 - xi - eta
    return [
        1 - 4 * s,
        4 * xi - 1,
        0,
        4 * eta,
        -4 * eta,
        4 * s - 4 * xi,
        1 - 4 * s,
        0,
        4 * eta - 1,
        4 * xi,
        4 * s - 4 * eta,
        -4 * xi,
    ]


def _h_vectors(
    n: List[Float64], offset: Int, side: List[Float64]
) -> List[Float64]:
    """Return Hx then Hy of the DKT, from six values of the shape functions.

    `n[offset + k]` is the k-th shape function value or derivative.
    `side` holds a, b, c, d and e for the sides 4, 5 and 6, in that order.
    """
    var n1 = n[offset]
    var n2 = n[offset + 1]
    var n3 = n[offset + 2]
    var n4 = n[offset + 3]
    var n5 = n[offset + 4]
    var n6 = n[offset + 5]
    var a4 = side[0]
    var b4 = side[1]
    var c4 = side[2]
    var d4 = side[3]
    var e4 = side[4]
    var a5 = side[5]
    var b5 = side[6]
    var c5 = side[7]
    var d5 = side[8]
    var e5 = side[9]
    var a6 = side[10]
    var b6 = side[11]
    var c6 = side[12]
    var d6 = side[13]
    var e6 = side[14]
    return [
        1.5 * (a6 * n6 - a5 * n5),
        b5 * n5 + b6 * n6,
        n1 - c5 * n5 - c6 * n6,
        1.5 * (a4 * n4 - a6 * n6),
        b6 * n6 + b4 * n4,
        n2 - c6 * n6 - c4 * n4,
        1.5 * (a5 * n5 - a4 * n4),
        b4 * n4 + b5 * n5,
        n3 - c4 * n4 - c5 * n5,
        1.5 * (d6 * n6 - d5 * n5),
        -n1 + e5 * n5 + e6 * n6,
        -b5 * n5 - b6 * n6,
        1.5 * (d4 * n4 - d6 * n6),
        -n2 + e6 * n6 + e4 * n4,
        -b6 * n6 - b4 * n4,
        1.5 * (d5 * n5 - d4 * n4),
        -n3 + e4 * n4 + e5 * n5,
        -b4 * n4 - b5 * n5,
    ]


struct ShellElement(Copyable, Movable):
    """A flat triangle: its local axes, corner coordinates and material."""

    var axes: LocalAxes
    # The corners in the local axes. The first corner is the origin and
    # the second lies on the local x axis.
    var x: List[Float64]
    var y: List[Float64]
    var area: Float64
    var thickness: Float64
    var modulus: Float64
    var poisson: Float64
    var density: Float64

    def __init__(
        out self,
        a: Vec3d,
        b: Vec3d,
        c: Vec3d,
        thickness: Length64,
        material: BuildingMaterial,
    ) raises:
        """Create an element from three corners.

        Args:
            a: The first corner, in meters.
            b: The second corner, in meters.
            c: The third corner, in meters.
            thickness: The shell thickness.
            material: The material. Its modulus, Poisson's ratio and
                density are used.

        Raises:
            Error: If a corner is not finite, the corners lie on one line,
                the thickness is not positive and finite, or the material
                is not valid.
        """
        material.check()
        var t = thickness.to(METER)
        if not (t > 0 and isfinite(t)):
            raise Error("A shell thickness must be positive and finite")
        var values = [a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]
        for i in range(len(values)):  # pragma: no branch
            if not isfinite(values[i]):
                raise Error("A shell's corners must be finite")
        var ab = b - a
        var ac = c - a
        var normal = ab.cross(ac)
        var twice_area = normal.length()
        if not (twice_area > 1e-12 * ab.dot(ab) + 1e-300):
            raise Error("A shell's corners must not lie on one line")
        var ex = ab.normalized()
        var ez = normal * (1 / twice_area)
        self.axes = LocalAxes(ex, ez.cross(ex), ez)
        self.x = [0, ab.length(), ac.dot(ex)]
        self.y = [0, 0, ac.dot(self.axes.y)]
        self.area = twice_area / 2
        self.thickness = t
        self.modulus = material.elastic_modulus.to(PASCAL)
        self.poisson = material.poisson_ratio
        self.density = material.density.value

    def _membrane_b(self) -> List[Float64]:
        """Return the 3 by 6 strain matrix of the membrane, row-major."""
        var x = self.x.copy()
        var y = self.y.copy()
        var b1 = y[1] - y[2]
        var b2 = y[2] - y[0]
        var b3 = y[0] - y[1]
        var c1 = x[2] - x[1]
        var c2 = x[0] - x[2]
        var c3 = x[1] - x[0]
        var s = 1 / (2 * self.area)
        return [
            b1 * s,
            0,
            b2 * s,
            0,
            b3 * s,
            0,
            0,
            c1 * s,
            0,
            c2 * s,
            0,
            c3 * s,
            c1 * s,
            b1 * s,
            c2 * s,
            b2 * s,
            c3 * s,
            b3 * s,
        ]

    def _elasticity(self) -> List[Float64]:
        """Return the plane-stress elasticity matrix, 3 by 3, row-major."""
        var nu = self.poisson
        var s = self.modulus / (1 - nu * nu)
        return [s, nu * s, 0, nu * s, s, 0, 0, 0, (1 - nu) / 2 * s]

    def _sides(self) -> List[Float64]:
        """Return a, b, c, d and e of the DKT for the sides 23, 31, 12."""
        var out = List[Float64](capacity=15)
        var ii = [1, 2, 0]
        var jj = [2, 0, 1]
        for k in range(3):  # pragma: no branch
            var xij = self.x[ii[k]] - self.x[jj[k]]
            var yij = self.y[ii[k]] - self.y[jj[k]]
            var l2 = xij * xij + yij * yij
            out.append(-xij / l2)
            out.append(0.75 * xij * yij / l2)
            out.append((0.25 * xij * xij - 0.5 * yij * yij) / l2)
            out.append(-yij / l2)
            out.append((0.25 * yij * yij - 0.5 * xij * xij) / l2)
        return out^

    def _plate_b(self, xi: Float64, eta: Float64) -> List[Float64]:
        """Return the 3 by 9 curvature matrix of the DKT, row-major."""
        var sides = self._sides()
        var dn = _shape_derivatives(xi, eta)
        var h_xi = _h_vectors(dn, 0, sides)
        var h_eta = _h_vectors(dn, 6, sides)
        var x31 = self.x[2] - self.x[0]
        var y31 = self.y[2] - self.y[0]
        var x12 = self.x[0] - self.x[1]
        var y12 = self.y[0] - self.y[1]
        var s = 1 / (2 * self.area)
        var out = List[Float64](length=27, fill=0)
        for k in range(9):  # pragma: no branch
            var hx_xi = h_xi[k]
            var hx_eta = h_eta[k]
            var hy_xi = h_xi[9 + k]
            var hy_eta = h_eta[9 + k]
            out[k] = s * (y31 * hx_xi + y12 * hx_eta)
            out[9 + k] = s * (-x31 * hy_xi - x12 * hy_eta)
            out[18 + k] = s * (
                -x31 * hx_xi - x12 * hx_eta + y31 * hy_xi + y12 * hy_eta
            )
        return out^

    def _drilling_rows(self) -> List[Float64]:
        """Return three rows of 18: each corner's rotation less ω."""
        var b = self._membrane_b()
        # ω = (∂v/∂x - ∂u/∂y) / 2. Row 0 of B gives ∂/∂x of u, so its
        # entries times v give ∂v/∂x. Row 1 gives ∂/∂y of v.
        var out = List[Float64](length=54, fill=0)
        for corner in range(3):  # pragma: no branch
            var row = 18 * corner
            out[row + 6 * corner + 5] = 1
            for k in range(3):  # pragma: no branch
                out[row + 6 * k] += 0.5 * b[6 + 2 * k + 1]
                out[row + 6 * k + 1] -= 0.5 * b[2 * k]
        return out^

    def local_stiffness(self) raises -> DenseMatrix:
        """Return the 18 by 18 stiffness in the local axes.

        Each corner has, in order, u, v, w and the rotations about the
        local x, y and z axes.

        Returns:
            The stiffness.

        Raises:
            Error: Never, for an element made by `__init__`.
        """
        var k = DenseMatrix(18, 18)
        var t = self.thickness
        var d = self._elasticity()
        # Membrane: A t Bᵀ D B.
        var bm = self._membrane_b()
        var membrane = [0, 1, 6, 7, 12, 13]
        for i in range(6):  # pragma: no branch
            for j in range(6):  # pragma: no branch
                var total = Float64(0)
                for p in range(3):  # pragma: no branch
                    for q in range(3):  # pragma: no branch
                        total += bm[6 * p + i] * d[3 * p + q] * bm[6 * q + j]
                k.add(membrane[i], membrane[j], self.area * t * total)
        # Plate: three Gauss points, weight A / 3 each.
        var bending = t * t * t / 12
        var plate = [2, 3, 4, 8, 9, 10, 14, 15, 16]
        var points = [1.0 / 6, 2.0 / 3, 1.0 / 6, 1.0 / 6, 1.0 / 6, 2.0 / 3]
        for g in range(3):  # pragma: no branch
            var bp = self._plate_b(points[g], points[3 + g])
            for i in range(9):  # pragma: no branch
                for j in range(9):  # pragma: no branch
                    var total = Float64(0)
                    for p in range(3):  # pragma: no branch
                        for q in range(3):  # pragma: no branch
                            total += (
                                bp[9 * p + i] * d[3 * p + q] * bp[9 * q + j]
                            )
                    k.add(plate[i], plate[j], self.area / 3 * bending * total)
        # Drilling penalty.
        var rows = self._drilling_rows()
        var gamma = (
            _DRILLING * self.modulus / (2 * (1 + self.poisson)) * t * self.area
        )
        for corner in range(3):  # pragma: no branch
            for i in range(18):  # pragma: no branch
                for j in range(18):  # pragma: no branch
                    k.add(
                        i,
                        j,
                        gamma
                        / 3
                        * rows[18 * corner + i]
                        * rows[18 * corner + j],
                    )
        return k^

    def transformation(self) raises -> DenseMatrix:
        """Return the 18 by 18 matrix T with local = T global.

        Returns:
            Six copies of the 3 by 3 rotation on the diagonal.

        Raises:
            Error: Never, for an element made by `__init__`.
        """
        var t = DenseMatrix(18, 18)
        var rows = [self.axes.x, self.axes.y, self.axes.z]
        for b in range(6):  # pragma: no branch
            for r in range(3):  # pragma: no branch
                var o = 3 * b
                t.set(o + r, o, rows[r].x)
                t.set(o + r, o + 1, rows[r].y)
                t.set(o + r, o + 2, rows[r].z)
        return t^

    def stiffness(self) raises -> DenseMatrix:
        """Return the 18 by 18 stiffness in global axes.

        Each corner has, in order, the translations along global x, y and
        z and the rotations about them.

        Returns:
            Tᵀ K T.

        Raises:
            Error: Never, for an element made by `__init__`.
        """
        return self.transformation().triple_product(self.local_stiffness())

    def lumped_mass(self) -> Float64:
        """Return the translational mass at each corner.

        Each corner takes a third of ρ t A on each translation and that
        mass times t² / 12 on each rotation.

        Returns:
            ρ t A / 3, in kilograms.
        """
        return self.density * self.thickness * self.area / 3

    def resultants(self, u: List[Float64]) raises -> ShellResultants:
        """Return the stresses and moments for corner displacements.

        Args:
            u: Eighteen displacements and rotations in global axes, in
                meters and radians, in the order of `stiffness`.

        Returns:
            The membrane stresses and the centroid moments.

        Raises:
            Error: If `u` does not have eighteen entries.
        """
        if len(u) != 18:
            raise Error("A shell needs eighteen displacements")
        var local = self.transformation().multiply_vector(u)
        var d = self._elasticity()
        var bm = self._membrane_b()
        var membrane = [0, 1, 6, 7, 12, 13]
        var strain = List[Float64](length=3, fill=0)
        for p in range(3):  # pragma: no branch
            for i in range(6):  # pragma: no branch
                strain[p] += bm[6 * p + i] * local[membrane[i]]
        var bp = self._plate_b(1.0 / 3, 1.0 / 3)
        var plate = [2, 3, 4, 8, 9, 10, 14, 15, 16]
        var curvature = List[Float64](length=3, fill=0)
        for p in range(3):  # pragma: no branch
            for i in range(9):  # pragma: no branch
                curvature[p] += bp[9 * p + i] * local[plate[i]]
        var stress = List[Float64](length=3, fill=0)
        var moment = List[Float64](length=3, fill=0)
        var bending = self.thickness * self.thickness * self.thickness / 12
        for p in range(3):  # pragma: no branch
            for q in range(3):  # pragma: no branch
                stress[p] += d[3 * p + q] * strain[q]
                moment[p] += bending * d[3 * p + q] * curvature[q]
        return ShellResultants(
            self.axes,
            Pressure64(stress[0]),
            Pressure64(stress[1]),
            Pressure64(stress[2]),
            Force64(moment[0]),
            Force64(moment[1]),
            Force64(moment[2]),
        )
