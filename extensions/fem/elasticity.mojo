# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Small-strain linear elasticity on four-node tetrahedra.

A four-node tetrahedron has linear shape functions, so its strain is the
same everywhere in it. Its stiffness is the volume times the integrand
of the isotropic material:

    K[3a + i, 3b + j] = V (lambda g_a[i] g_b[j] + mu g_a[j] g_b[i]
                           + mu delta_ij g_a . g_b)

where `g_a` is the gradient of the shape function of node `a`, and
`lambda` and `mu` are the Lame constants.

A strain or a stress has six parts in Voigt order: xx, yy, zz, yz, xz
and xy. A strain's shear parts are engineering shears, twice the tensor
parts.
"""

from extensions.fem.mesh import signed_volume
from extensions.sdf.vector import V3, cross, dot, v3
from std.math import isfinite, sqrt
from units.si import Pressure64, PASCAL


struct IsotropicMaterial(ImplicitlyCopyable):
    """A linear elastic material that is the same in every direction."""

    var young: Pressure64
    """Young's modulus."""
    var poisson: Float64
    """Poisson's ratio."""

    def __init__(out self, young: Pressure64, poisson: Float64) raises:
        """Create a material.

        Args:
            young: Young's modulus. Positive and finite.
            poisson: Poisson's ratio. Above -1 and below 0.5.

        Raises:
            Error: If the modulus is not positive and finite, or the ratio
                is out of range.
        """
        var e = young.to(PASCAL)
        if not (e > 0) or not isfinite(e):
            raise Error("Young's modulus must be positive and finite")
        if not (poisson > -1.0) or not (poisson < 0.5):
            raise Error("Poisson's ratio must be above -1 and below 0.5")
        self.young = young
        self.poisson = poisson

    def lame(self) -> Tuple[Float64, Float64]:
        """Return the Lame constants, in pascals.

        Returns:
            `lambda = E nu / ((1 + nu)(1 - 2 nu))` and
            `mu = E / (2 (1 + nu))`.
        """
        var e = self.young.to(PASCAL)
        var nu = self.poisson
        return (
            e * nu / ((1.0 + nu) * (1.0 - 2.0 * nu)),
            e / (2.0 * (1.0 + nu)),
        )


def shape_gradients(a: V3, b: V3, c: V3, d: V3) -> List[V3]:
    """Return the gradients of the four linear shape functions.

    Args:
        a: The first corner.
        b: The second corner.
        c: The third corner.
        d: The fourth corner. The volume of `a b c d` is not zero.

    Returns:
        The gradient of the shape function of each corner, per meter. The
        four sum to zero.
    """
    var six = 6.0 * signed_volume(a, b, c, d)
    var e1 = b - a
    var e2 = c - a
    var e3 = d - a
    # The rows of the inverse of the matrix with columns e1, e2, e3.
    var g1 = cross(e2, e3) * (1.0 / six)
    var g2 = cross(e3, e1) * (1.0 / six)
    var g3 = cross(e1, e2) * (1.0 / six)
    var g0 = -(g1 + g2 + g3)
    return [g0, g1, g2, g3]


def _part(g: V3, axis: Int) -> Float64:
    """Return one component of a vector."""
    if axis == 0:
        return g.x
    if axis == 1:
        return g.y
    return g.z


def element_stiffness(
    corners: List[V3], material: IsotropicMaterial
) -> List[Float64]:
    """Return the 12 by 12 stiffness of one tetrahedron, row by row.

    Args:
        corners: The four corners, with a positive volume.
        material: The material.

    Returns:
        144 entries in newtons per meter. Row `3a + i` is the force on
        node `a` along axis `i`.
    """
    var g = shape_gradients(corners[0], corners[1], corners[2], corners[3])
    var volume = signed_volume(corners[0], corners[1], corners[2], corners[3])
    var constants = material.lame()
    var lam = constants[0]
    var mu = constants[1]
    var out = List[Float64](length=144, fill=0)
    for a in range(4):
        for b in range(4):
            var shared = mu * dot(g[a], g[b])
            for i in range(3):
                var ga_i = _part(g[a], i)
                var gb_i = _part(g[b], i)
                for j in range(3):
                    var value = (
                        lam * ga_i * _part(g[b], j) + mu * _part(g[a], j) * gb_i
                    )
                    if i == j:
                        value += shared
                    out[(3 * a + i) * 12 + 3 * b + j] = volume * value
    return out^


def element_strain(
    gradients: List[V3], displacements: List[V3]
) -> List[Float64]:
    """Return the strain of one tetrahedron from its corner displacements.

    Args:
        gradients: The four shape function gradients.
        displacements: The four corner displacements, in meters.

    Returns:
        Six strains in Voigt order, with engineering shears.
    """
    var out = List[Float64](length=6, fill=0)
    for a in range(4):
        var g = gradients[a]
        var u = displacements[a]
        out[0] += g.x * u.x
        out[1] += g.y * u.y
        out[2] += g.z * u.z
        out[3] += g.z * u.y + g.y * u.z
        out[4] += g.z * u.x + g.x * u.z
        out[5] += g.y * u.x + g.x * u.y
    return out^


def stress_of(
    strain: List[Float64], material: IsotropicMaterial
) -> List[Float64]:
    """Return the stress of a strain.

    Args:
        strain: Six strains in Voigt order, with engineering shears.
        material: The material.

    Returns:
        Six stresses in Voigt order, in pascals.
    """
    var constants = material.lame()
    var lam = constants[0]
    var mu = constants[1]
    var trace = strain[0] + strain[1] + strain[2]
    return [
        lam * trace + 2.0 * mu * strain[0],
        lam * trace + 2.0 * mu * strain[1],
        lam * trace + 2.0 * mu * strain[2],
        mu * strain[3],
        mu * strain[4],
        mu * strain[5],
    ]


def von_mises(stress: List[Float64]) -> Pressure64:
    """Return the von Mises stress of a stress.

    Args:
        stress: Six stresses in Voigt order, in pascals.

    Returns:
        `sqrt(((sx - sy)^2 + (sy - sz)^2 + (sz - sx)^2) / 2
        + 3 (tyz^2 + txz^2 + txy^2))`.
    """
    var dx = stress[0] - stress[1]
    var dy = stress[1] - stress[2]
    var dz = stress[2] - stress[0]
    var shear = stress[3] ** 2 + stress[4] ** 2 + stress[5] ** 2
    return Pressure64(
        sqrt((dx * dx + dy * dy + dz * dz) / 2.0 + 3.0 * shear), PASCAL
    )
