# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Published density, porosity and moduli for cortical and trabecular bone.

The numbers come from Morgan, Unnikrishnan and Hussein, *Bone Mechanical
Properties in Healthy and Diseased States*, Annu. Rev. Biomed. Eng. 2018
(PMC6053074). Tissue density is 2.0 g/cm^3 for cortical and trabecular
bone. Cortical porosity is 5% to 15%; the template uses 10%. Table 1 lists
two femoral cortical longitudinal moduli, 17.9 GPa and 18.16 GPa, from
different source footnotes. The table does not label those rows tension
and compression. Apparent density is tissue density times one minus
porosity.

These values are sourced research metadata. They are not an isotropic
elastic material. Poisson's ratio 0.62 is a directional cortical figure.
The isotropic bulk-modulus formula is not valid at that ratio. This
module does not implement a constitutive model.

Mass of a bone uses apparent density times regional volume, with porosity
applied once. The Phong look lives in `bone.mojo`, not here.

    var tissue = cortical_tissue()
    var mass = tissue.apparent_density() * volume
    var weight = mass * STANDARD_GRAVITY
"""

from std.math import isfinite
from units.si import (
    Density,
    GRAM_PER_CUBIC_CENTIMETER,
    GIGAPASCAL,
    MEGAPASCAL,
    Pressure,
)


@fieldwise_init
struct BoneKind(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue a `BoneTissue` describes, as a type rather than a bare int.

    The type stops a bare integer at compile time. A value that is not
    `CORTICAL` or `TRABECULAR` is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `CORTICAL` or `TRABECULAR`."""
        return self == CORTICAL or self == TRABECULAR


# Compact bone of the diaphysis and the thin shell of the ends.
comptime CORTICAL = BoneKind(0)
# Cancellous bone that fills the head, neck and condyles.
comptime TRABECULAR = BoneKind(1)


@fieldwise_init
struct BoneTissue(ImplicitlyCopyable):
    """Published density, porosity and longitudinal moduli of one tissue.

    `elastic_modulus` is Table 1's 17.9 GPa longitudinal figure.
    `elastic_modulus_secondary` is the 18.16 GPa figure from a different
    footnote in the same table. Neither name is a tension or compression
    label. Poisson's ratio is the Table 1 cortical figure; trabecular
    bone uses 0.3 as an authored stand-in.

    The constructor does not refuse a bad kind. `validate` does that, the
    same way a `Material` can hold a kind that `is_valid` then rejects.
    """

    var kind: BoneKind
    var tissue_density: Density
    var porosity: Float32
    var elastic_modulus: Pressure
    var elastic_modulus_secondary: Pressure
    var poisson_ratio: Float32

    def apparent_density(self) -> Density:
        """Return mass per total volume, including pore space.

        Returns:
            `tissue_density` scaled by one minus porosity.
        """
        return self.tissue_density.scaled(Float32(1) - self.porosity)

    def validate(self) raises:
        """Refuse a kind, density, porosity, modulus or Poisson ratio
        that this tissue cannot hold.

        Raises:
            Error: If `kind` is not `CORTICAL` or `TRABECULAR`, if a
                quantity is not finite or not positive, if porosity is
                outside 0 through 1, or if Poisson's ratio is outside
                0 through 1.
        """
        if not self.kind.is_valid():
            raise Error("Bone tissue must be cortical or trabecular")
        if not isfinite(self.tissue_density.value):
            raise Error("A bone tissue density must be finite")
        if self.tissue_density.value <= 0:
            raise Error("A bone tissue density must be positive")
        if not isfinite(self.porosity):
            raise Error("A bone porosity must be finite")
        if self.porosity < 0:
            raise Error("A bone porosity cannot be negative")
        if self.porosity > 1:
            raise Error("A bone porosity cannot exceed one")
        if not isfinite(self.elastic_modulus.value):
            raise Error("A bone elastic modulus must be finite")
        if self.elastic_modulus.value <= 0:
            raise Error("A bone elastic modulus must be positive")
        if not isfinite(self.elastic_modulus_secondary.value):
            raise Error("A bone secondary modulus must be finite")
        if self.elastic_modulus_secondary.value <= 0:
            raise Error("A bone secondary modulus must be positive")
        if not isfinite(self.poisson_ratio):
            raise Error("A bone Poisson ratio must be finite")
        if self.poisson_ratio < 0:
            raise Error("A bone Poisson ratio cannot be negative")
        if self.poisson_ratio > 1:
            raise Error("A bone Poisson ratio cannot exceed one")


def cortical_tissue() -> BoneTissue:
    """Return adult femoral cortical bone from Morgan et al. 2018.

    Tissue density is 2.0 g/cm^3. Porosity is 10%, the middle of the
    5% to 15% range. The two Table 1 longitudinal moduli are 17.9 GPa
    and 18.16 GPa. Poisson's ratio is 0.62, stored as directional
    metadata.

    Returns:
        The cortical template.
    """
    return BoneTissue(
        CORTICAL,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.10),
        Pressure(17.9, GIGAPASCAL),
        Pressure(18.16, GIGAPASCAL),
        Float32(0.62),
    )


def trabecular_tissue() -> BoneTissue:
    """Return adult femoral trabecular bone from Morgan et al. 2018.

    Tissue density is 2.0 g/cm^3, the same as cortical bone. Porosity is
    80%, a typical metaphyseal fill inside the 40% to 95% range.
    Apparent modulus is 400 MPa, inside the 10 MPa to 3000 MPa range
    the paper reports. Poisson's ratio is 0.3, an authored stand-in.

    Returns:
        The trabecular template.
    """
    return BoneTissue(
        TRABECULAR,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.80),
        Pressure(400.0, MEGAPASCAL),
        Pressure(400.0, MEGAPASCAL),
        Float32(0.30),
    )
