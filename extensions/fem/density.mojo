# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""FEM materials from the CT numbers of a volume.

The stiffness of bone follows its density. A finite element model of a
bone takes the density from CT. A calibration line turns each CT number
into an apparent density, and a power law turns the density into a
modulus:

    rho = intercept + slope * CT
    E = coefficient * (rho / (1 g/cm^3))^exponent

The coefficient is the modulus at a density of 1 g/cm^3. A density
below `minimum_density` is held at it, so that air and fat give a small
positive modulus. Morgan and others (2003) give a coefficient of
6850 MPa and an exponent of 1.49 for the human femoral neck. The
calibration line comes from a phantom of known densities in the scan.

`element_ct` reads the CT number of the voxel that holds the centroid
of each element. `density_materials` puts the elements in bins of equal
modulus width, and makes one material for each bin that holds an
element. A material has the mean modulus and the mean density of its
elements, weighted by volume.
"""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import ElementId
from extensions.fem.mesh import TetMesh
from extensions.imaging.image_volume import ImageVolume
from std.math import floor, isfinite, max, min
from units.si import (
    CUBIC_METER,
    Density64,
    GRAM_PER_CUBIC_CENTIMETER,
    METER,
    PASCAL,
    Pressure64,
)

# The most bins `density_materials` takes.
comptime MAX_DENSITY_BINS = 1024


struct CtDensityLaw(Copyable, Movable):
    """A calibration from CT numbers to density, and a power law to modulus."""

    var intercept: Density64
    """The density at a CT number of zero."""
    var slope: Density64
    """The change of density for each CT number."""
    var coefficient: Pressure64
    """The modulus at a density of 1 g/cm^3."""
    var exponent: Float64
    """The power of the density."""
    var minimum_density: Density64
    """The least density, for air and fat."""
    var poisson: Float64
    """Poisson's ratio of every material."""

    def __init__(
        out self,
        intercept: Density64,
        slope: Density64,
        coefficient: Pressure64,
        exponent: Float64,
        minimum_density: Density64,
        poisson: Float64,
    ) raises:
        """Create a law.

        Args:
            intercept: The density at a CT number of zero. Finite.
            slope: The density for each CT number. Finite.
            coefficient: The modulus at 1 g/cm^3. Positive and finite.
            exponent: The power of the density. Positive and finite.
            minimum_density: The least density. Positive and finite.
            poisson: Poisson's ratio. Above -1 and below 0.5.

        Raises:
            Error: If a constant is out of its range.
        """
        if not isfinite(intercept.to(GRAM_PER_CUBIC_CENTIMETER)):
            raise Error("A density intercept must be finite")
        if not isfinite(slope.to(GRAM_PER_CUBIC_CENTIMETER)):
            raise Error("A density slope must be finite")
        var c = coefficient.to(PASCAL)
        if not (c > 0) or not isfinite(c):
            raise Error("A modulus coefficient must be positive and finite")
        if not (exponent > 0) or not isfinite(exponent):
            raise Error("A density exponent must be positive and finite")
        var least = minimum_density.to(GRAM_PER_CUBIC_CENTIMETER)
        if not (least > 0) or not isfinite(least):
            raise Error("A minimum density must be positive and finite")
        # The material check refuses a bad ratio.
        _ = IsotropicMaterial(coefficient, poisson)
        self.intercept = intercept
        self.slope = slope
        self.coefficient = coefficient
        self.exponent = exponent
        self.minimum_density = minimum_density
        self.poisson = poisson

    def density(self, ct: Float64) -> Density64:
        """Return the density of a CT number.

        Args:
            ct: The CT number, such as Hounsfield units.

        Returns:
            `intercept + slope * ct`, or `minimum_density` if that is
            larger.
        """
        var rho = self.intercept.to(GRAM_PER_CUBIC_CENTIMETER) + ct * (
            self.slope.to(GRAM_PER_CUBIC_CENTIMETER)
        )
        var least = self.minimum_density.to(GRAM_PER_CUBIC_CENTIMETER)
        return Density64(max(rho, least), GRAM_PER_CUBIC_CENTIMETER)

    def modulus(self, ct: Float64) -> Pressure64:
        """Return Young's modulus of a CT number.

        Args:
            ct: The CT number.

        Returns:
            `coefficient * (density / 1 g/cm^3)^exponent`.
        """
        var rho = self.density(ct).to(GRAM_PER_CUBIC_CENTIMETER)
        return Pressure64(
            self.coefficient.to(PASCAL) * rho**self.exponent, PASCAL
        )


struct DensityMaterials(Movable):
    """The materials of the bins, and the density of each."""

    var materials: List[IsotropicMaterial]
    """One material for each bin that holds an element."""
    var densities: List[Density64]
    """The mean density of each material, for `apply_gravity`."""

    def __init__(out self):
        """Create an empty list of materials."""
        self.materials = List[IsotropicMaterial]()
        self.densities = List[Density64]()


def element_ct(mesh: TetMesh, volume: ImageVolume) raises -> List[Float64]:
    """Return the CT number at each element of a mesh.

    The mesh is in the volume frame: voxel `(i, j, k)` has its center at
    `(i * spacing_x, j * spacing_y, k * spacing_z)`, as in `voxel_mesh`.
    Each element takes the value of the voxel that holds the centroid of
    its four corners.

    Args:
        mesh: The mesh.
        volume: The CT volume.

    Returns:
        One value per element.

    Raises:
        Error: If the centroid of an element is outside the volume.
    """
    var sx = volume.spacing_x.to(METER)
    var sy = volume.spacing_y.to(METER)
    var sz = volume.spacing_z.to(METER)
    var values = List[Float64](capacity=mesh.element_count())
    var per = mesh.nodes_per_element()
    for e in range(mesh.element_count()):
        var c = (
            mesh.nodes[mesh.corners[per * e]]
            + mesh.nodes[mesh.corners[per * e + 1]]
            + mesh.nodes[mesh.corners[per * e + 2]]
            + mesh.nodes[mesh.corners[per * e + 3]]
        ) * 0.25
        var i = Int(floor(c.x / sx + 0.5))
        var j = Int(floor(c.y / sy + 0.5))
        var k = Int(floor(c.z / sz + 0.5))
        if not volume.contains(i, j, k):
            raise Error("An element lies outside the CT volume")
        values.append(Float64(volume.values[volume.index(i, j, k)]))
    return values^


def density_materials(
    mut mesh: TetMesh, volume: ImageVolume, law: CtDensityLaw, bins: Int
) raises -> DensityMaterials:
    """Give each element of a mesh a material from its CT number.

    The elements go in `bins` bins of equal width, from the least to the
    largest modulus. Each bin that holds an element becomes a material,
    in the order of the bins, and its elements take that material.

    Args:
        mesh: The mesh. Its material ids change.
        volume: The CT volume, in the frame of the mesh.
        law: The calibration and the power law.
        bins: The number of bins, from 1 to 1024.

    Returns:
        The materials and their densities, for `StaticProblem` and
        `apply_gravity`.

    Raises:
        Error: If the bins are out of range, the mesh has no elements, or
            an element is outside the volume.
    """
    if bins < 1 or bins > MAX_DENSITY_BINS:
        raise Error("Density materials need from 1 to 1024 bins")
    if mesh.element_count() == 0:
        raise Error("Density materials need a mesh with an element")
    var ct = element_ct(mesh, volume)
    var moduli = List[Float64]()
    var low = law.modulus(ct[0]).to(PASCAL)
    var high = low
    for value in ct:  # pragma: no branch
        var e = law.modulus(value).to(PASCAL)
        moduli.append(e)
        low = min(low, e)
        high = max(high, e)
    var width = (high - low) / Float64(bins)
    var sums = List[Float64](length=bins, fill=0)
    var masses = List[Float64](length=bins, fill=0)
    var weights = List[Float64](length=bins, fill=0)
    var bin_of = List[Int]()
    for e in range(len(moduli)):  # pragma: no branch
        var bin = 0
        if width > 0:
            bin = min(Int((moduli[e] - low) / width), bins - 1)
        bin_of.append(bin)
        var size = mesh.volume(ElementId(e)).to(CUBIC_METER)
        sums[bin] += moduli[e] * size
        var rho = law.density(ct[e]).to(GRAM_PER_CUBIC_CENTIMETER)
        masses[bin] += rho * size
        weights[bin] += size
    var out = DensityMaterials()
    var material = List[Int](length=bins, fill=-1)
    for bin in range(bins):  # pragma: no branch
        if weights[bin] == 0:
            continue
        material[bin] = len(out.materials)
        var modulus = Pressure64(sums[bin] / weights[bin], PASCAL)
        out.materials.append(IsotropicMaterial(modulus, law.poisson))
        out.densities.append(
            Density64(masses[bin] / weights[bin], GRAM_PER_CUBIC_CENTIMETER)
        )
    for e in range(len(bin_of)):  # pragma: no branch
        mesh.materials[e] = material[bin_of[e]]
    return out^
