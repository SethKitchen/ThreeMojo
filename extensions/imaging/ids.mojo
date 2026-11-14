# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds and ids that medical image volumes carry.

Each is a type, so a bare integer cannot stand in for one. A value the
type can hold but the code does not accept is refused where it is read.
"""

from core.ordinal import ordinal_valid, require_valid

# The largest label a label map can hold. Label zero is the background.
comptime MAX_LABEL = 255


@fieldwise_init
struct TransferSyntax(Equatable, ImplicitlyCopyable, Writable):
    """How the data set of a DICOM file is encoded.

    `EXPLICIT_LITTLE` is explicit VR little endian,
    `1.2.840.10008.1.2.1`. `IMPLICIT_LITTLE` is implicit VR little endian,
    `1.2.840.10008.1.2`. `DEFLATED_EXPLICIT` is explicit VR little endian
    with the data set compressed by DEFLATE, `1.2.840.10008.1.2.1.99`.
    `RLE_LOSSLESS` is explicit VR little endian with the pixel data
    compressed by run-length encoding, `1.2.840.10008.1.2.5`. The reader
    refuses every other syntax.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four syntaxes.

        Returns:
            Whether the value is from zero to three.
        """
        return ordinal_valid(self.value, 3)


comptime EXPLICIT_LITTLE = TransferSyntax(0)
comptime IMPLICIT_LITTLE = TransferSyntax(1)
comptime DEFLATED_EXPLICIT = TransferSyntax(2)
comptime RLE_LOSSLESS = TransferSyntax(3)


def require_syntax(syntax: TransferSyntax) raises:
    """Refuse a transfer syntax that is not one of the four.

    Args:
        syntax: The syntax to check.

    Raises:
        Error: If `syntax` is not valid.
    """
    require_valid(syntax.is_valid(), "A transfer syntax must be from 0 to 3")


@fieldwise_init
struct Photometric(Equatable, ImplicitlyCopyable, Writable):
    """How a grayscale DICOM image is shown.

    `MONOCHROME2` shows the lowest value as black. `MONOCHROME1` shows it
    as white.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two interpretations.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime MONOCHROME2 = Photometric(0)
comptime MONOCHROME1 = Photometric(1)


def require_photometric(photometric: Photometric) raises:
    """Refuse a photometric interpretation that is not one of the two.

    Args:
        photometric: The interpretation to check.

    Raises:
        Error: If `photometric` is not valid.
    """
    require_valid(
        photometric.is_valid(), "A photometric interpretation must be 0 or 1"
    )


@fieldwise_init
struct PixelRepresentation(Equatable, ImplicitlyCopyable, Writable):
    """Whether the stored pixel values of a DICOM image have a sign.

    `UNSIGNED_PIXELS` is DICOM value 0. `SIGNED_PIXELS` is DICOM value 1,
    two's complement.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two representations.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime UNSIGNED_PIXELS = PixelRepresentation(0)
comptime SIGNED_PIXELS = PixelRepresentation(1)


def require_representation(representation: PixelRepresentation) raises:
    """Refuse a pixel representation that is not one of the two.

    Args:
        representation: The representation to check.

    Raises:
        Error: If `representation` is not valid.
    """
    require_valid(
        representation.is_valid(), "A pixel representation must be 0 or 1"
    )


@fieldwise_init
struct SliceAxis(Equatable, ImplicitlyCopyable, Writable):
    """The volume index that a slice holds constant.

    `I_AXIS` cuts across the columns, `J_AXIS` across the rows and
    `K_AXIS` across the slices. In an axial series, `K_AXIS` gives axial
    slices, `J_AXIS` coronal slices and `I_AXIS` sagittal slices.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three axes.

        Returns:
            Whether the value is from zero to two.
        """
        return ordinal_valid(self.value, 2)


comptime I_AXIS = SliceAxis(0)
comptime J_AXIS = SliceAxis(1)
comptime K_AXIS = SliceAxis(2)


def require_axis(axis: SliceAxis) raises:
    """Refuse a slice axis that is not one of the three.

    Args:
        axis: The axis to check.

    Raises:
        Error: If `axis` is not valid.
    """
    require_valid(axis.is_valid(), "A slice axis must be from 0 to 2")


@fieldwise_init
struct RenderMode(Equatable, ImplicitlyCopyable, Writable):
    """How a ray through a volume becomes a pixel.

    `COMPOSITE` blends the colors of a transfer function from front to
    back. `MAXIMUM_INTENSITY` keeps the largest value on the ray and shows
    it through a window. `ISOSURFACE` stops where the value first reaches
    an iso value and shades the surface there.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three modes.

        Returns:
            Whether the value is from zero to two.
        """
        return ordinal_valid(self.value, 2)


comptime COMPOSITE = RenderMode(0)
comptime MAXIMUM_INTENSITY = RenderMode(1)
comptime ISOSURFACE = RenderMode(2)


def require_mode(mode: RenderMode) raises:
    """Refuse a render mode that is not one of the three.

    Args:
        mode: The mode to check.

    Raises:
        Error: If `mode` is not valid.
    """
    require_valid(mode.is_valid(), "A render mode must be from 0 to 2")


@fieldwise_init
struct LabelId(Equatable, ImplicitlyCopyable, Writable):
    """One label of a label map. Label zero is the background."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if a label map can hold this label.

        Returns:
            Whether the value is from zero to `MAX_LABEL`.
        """
        return ordinal_valid(self.value, MAX_LABEL)


comptime BACKGROUND = LabelId(0)


def require_label(label: LabelId) raises:
    """Refuse a label that a label map cannot hold.

    Args:
        label: The label to check.

    Raises:
        Error: If `label` is not from 0 to 255.
    """
    require_valid(label.is_valid(), "A label must be from 0 to 255")
