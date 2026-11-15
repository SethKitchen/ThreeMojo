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


@fieldwise_init
struct DicomNode(Equatable, ImplicitlyCopyable, Writable):
    """A node of a `DicomTree`: its index. Node 0 is the data set, and
    each item of a sequence is a node of its own."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a node.
        """
        return self.value >= 0


comptime DATA_SET = DicomNode(0)


@fieldwise_init
struct SlabMode(Equatable, ImplicitlyCopyable, Writable):
    """How a thick slab is projected onto its plane.

    `SLAB_MAXIMUM` keeps the largest sample along the normal, as for
    vessels with contrast. `SLAB_MINIMUM` keeps the least, as for airways.
    `SLAB_MEAN` averages the samples, like a thicker slice.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three projections.

        Returns:
            Whether the value is from zero to two.
        """
        return ordinal_valid(self.value, 2)


comptime SLAB_MAXIMUM = SlabMode(0)
comptime SLAB_MINIMUM = SlabMode(1)
comptime SLAB_MEAN = SlabMode(2)


def require_slab_mode(mode: SlabMode) raises:
    """Refuse a slab projection that is not one of the three.

    Args:
        mode: The projection to check.

    Raises:
        Error: If `mode` is not valid.
    """
    require_valid(mode.is_valid(), "A slab mode must be from 0 to 2")


@fieldwise_init
struct Connectivity(Equatable, ImplicitlyCopyable, Writable):
    """Which neighbors of a voxel connect to it.

    `FACES` connects the 6 voxels that share a face. `EDGES` also connects
    the 12 that share an edge, 18 in all. `CORNERS` also connects the 8
    that share a corner, 26 in all. A thin vessel that runs at a slant
    through the grid holds together only with `EDGES` or `CORNERS`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three connectivities.

        Returns:
            Whether the value is from zero to two.
        """
        return ordinal_valid(self.value, 2)

    def neighbors(self) -> Int:
        """Return the number of neighbors of a voxel inside the grid.

        Returns:
            6, 18 or 26.
        """
        if self.value == 2:
            return 26
        if self.value == 1:
            return 18
        return 6


comptime FACES = Connectivity(0)
comptime EDGES = Connectivity(1)
comptime CORNERS = Connectivity(2)


def require_connectivity(connectivity: Connectivity) raises:
    """Refuse a connectivity that is not one of the three.

    Args:
        connectivity: The connectivity to check.

    Raises:
        Error: If `connectivity` is not valid.
    """
    require_valid(connectivity.is_valid(), "A connectivity must be from 0 to 2")


@fieldwise_init
struct RegistrationMetric(Equatable, ImplicitlyCopyable, Writable):
    """How a registration compares two volumes.

    `MEAN_SQUARES` takes the mean squared difference, for two scans of
    one kind. `MUTUAL_INFORMATION` takes the mutual information of their
    joint histogram, for two kinds of scans.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two metrics.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime MEAN_SQUARES = RegistrationMetric(0)
comptime MUTUAL_INFORMATION = RegistrationMetric(1)


def require_metric(metric: RegistrationMetric) raises:
    """Refuse a metric that is not one of the two.

    Args:
        metric: The metric to check.

    Raises:
        Error: If `metric` is not valid.
    """
    require_valid(metric.is_valid(), "A registration metric must be 0 or 1")


@fieldwise_init
struct ResponseCategory(Equatable, ImplicitlyCopyable, Writable):
    """The response of target lesions after RECIST 1.1.

    `COMPLETE_RESPONSE`, `PARTIAL_RESPONSE`, `STABLE_DISEASE` and
    `PROGRESSIVE_DISEASE`, from 0 to 3.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four responses.

        Returns:
            Whether the value is from zero to three.
        """
        return ordinal_valid(self.value, 3)


comptime COMPLETE_RESPONSE = ResponseCategory(0)
comptime PARTIAL_RESPONSE = ResponseCategory(1)
comptime STABLE_DISEASE = ResponseCategory(2)
comptime PROGRESSIVE_DISEASE = ResponseCategory(3)


def require_response(response: ResponseCategory) raises:
    """Refuse a response that is not one of the four.

    Args:
        response: The response to check.

    Raises:
        Error: If `response` is not valid.
    """
    require_valid(response.is_valid(), "A RECIST response must be from 0 to 3")


@fieldwise_init
struct ToftsModel(Equatable, ImplicitlyCopyable, Writable):
    """Which Tofts model a DCE-MRI fit takes.

    `STANDARD_TOFTS` has Ktrans and ve. `EXTENDED_TOFTS` adds vp, the
    plasma volume fraction.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two models.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime STANDARD_TOFTS = ToftsModel(0)
comptime EXTENDED_TOFTS = ToftsModel(1)


def require_tofts_model(model: ToftsModel) raises:
    """Refuse a Tofts model that is not one of the two.

    Args:
        model: The model to check.

    Raises:
        Error: If `model` is not valid.
    """
    require_valid(model.is_valid(), "A Tofts model must be 0 or 1")


@fieldwise_init
struct EdgeMode(Equatable, ImplicitlyCopyable, Writable):
    """Which values a filter reads past the edge of a volume.

    `EDGE_NEAREST` repeats the edge value: `a a a | a b c d | d d d`.
    `EDGE_REFLECT` mirrors the values about the edge, with the edge value
    once more: `c b a | a b c d | d c b`. These are the `nearest` and
    `reflect` modes of scipy.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two edge modes.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime EDGE_NEAREST = EdgeMode(0)
comptime EDGE_REFLECT = EdgeMode(1)


def require_edge_mode(mode: EdgeMode) raises:
    """Refuse an edge mode that is not one of the two.

    Args:
        mode: The edge mode to check.

    Raises:
        Error: If `mode` is not valid.
    """
    require_valid(mode.is_valid(), "An edge mode must be 0 or 1")
