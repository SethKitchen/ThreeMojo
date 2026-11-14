# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stack DICOM slices into a volume, and cut a volume into slices.

`stack_slices` sorts the slices along the normal of their plane. The
normal is the cross product of the row and the column directions. The
slices must share their size, spacing and orientation, and they must be
evenly spaced along the normal with no sideways shift. A gantry tilt
gives a sideways shift, and the stack refuses it.

`volume_slices` is the inverse. It gives one `DicomSlice` for each `k`.
"""

from extensions.imaging.dicom import DicomSlice
from extensions.imaging.image_volume import ImageVolume
from extensions.sdf.vector import V3, dot, length
from std.math import isfinite, max
from units.si import Length64, METER

# Two slices agree on a direction when their unit vectors differ by less
# than this.
comptime DIRECTION_TOLERANCE = 1.0e-4
# Spacings and gaps agree when they differ by less than this fraction.
comptime SPACING_TOLERANCE = 0.01


def _same_length(a: Length64, b: Length64) -> Bool:
    """Return whether two spacings agree to the spacing tolerance."""
    var x = a.to(METER)
    var y = b.to(METER)
    return abs(x - y) <= SPACING_TOLERANCE * max(abs(x), abs(y))


def _same_direction(a: V3, b: V3) -> Bool:
    """Return whether two unit directions agree."""
    return length(a - b) <= DIRECTION_TOLERANCE


def _check_slice(first: DicomSlice, other: DicomSlice) raises:
    """Refuse a slice that cannot share a volume with the first."""
    if not other.has_position:
        raise Error("Each slice of a stack needs an image position")
    if not other.has_orientation:
        raise Error("Each slice of a stack needs an image orientation")
    if not other.has_spacing:
        raise Error("Each slice of a stack needs a pixel spacing")
    if other.rows != first.rows or other.columns != first.columns:
        raise Error("The slices of a stack must have one size")
    if not _same_length(other.row_spacing, first.row_spacing):
        raise Error("The slices of a stack must have one pixel spacing")
    if not _same_length(other.column_spacing, first.column_spacing):
        raise Error("The slices of a stack must have one pixel spacing")
    if not _same_direction(other.row_direction, first.row_direction):
        raise Error("The slices of a stack must have one orientation")
    if not _same_direction(other.column_direction, first.column_direction):
        raise Error("The slices of a stack must have one orientation")


def _order(keys: List[Float64]) -> List[Int]:
    """Return the indexes of `keys` in increasing order, stable."""
    var order = List[Int]()
    for index in range(len(keys)):  # pragma: no branch
        var at = len(order)
        while at > 0 and keys[order[at - 1]] > keys[index]:
            at -= 1
        order.insert(at, index)
    return order^


def stack_slices(slices: List[DicomSlice]) raises -> ImageVolume:
    """Return the volume that a series of slices fills.

    The slices can come in any order. The first slice after sorting gives
    the origin. The window comes from the first slice that has one. A
    stack without a window fits its window to its values.

    Args:
        slices: The slices of one series.

    Returns:
        A volume with `nx` columns, `ny` rows and one `k` per slice.

    Raises:
        Error: If there are no slices, a slice has no position,
            orientation or pixel spacing, the slices differ in size,
            spacing or orientation, two slices share a position, the gaps
            are not even, or a slice is shifted sideways.
    """
    if len(slices) == 0:
        raise Error("A stack needs at least one slice")
    # The stack holds at least one slice from here on.
    for slice in slices:  # pragma: no branch
        _check_slice(slices[0], slice)
    var normal = slices[0].normal()
    var keys = List[Float64]()
    for slice in slices:  # pragma: no branch
        keys.append(dot(slice.position, normal))
    var order = _order(keys)
    ref first = slices[order[0]]
    var spacing_z = _stack_spacing(slices, order, keys, normal)
    var volume = ImageVolume(
        first.columns,
        first.rows,
        len(slices),
        first.column_spacing,
        first.row_spacing,
        spacing_z,
    )
    volume.origin = first.position
    volume.axis_x = first.row_direction
    volume.axis_y = first.column_direction
    volume.axis_z = normal
    volume.photometric = first.photometric
    var plane = first.rows * first.columns
    var has_window = False
    for k in range(len(order)):  # pragma: no branch
        ref slice = slices[order[k]]
        for index in range(plane):  # pragma: no branch
            volume.values[k * plane + index] = slice.values[index]
        if slice.has_window and not has_window:
            volume.window_center = slice.window_center
            volume.window_width = slice.window_width
            has_window = True
    if not has_window:
        volume.fit_window()
    return volume^


def _stack_spacing(
    slices: List[DicomSlice],
    order: List[Int],
    keys: List[Float64],
    normal: V3,
) raises -> Length64:
    """Return the even gap between sorted slices, or refuse the stack."""
    ref first = slices[order[0]]
    if len(order) == 1:
        if first.thickness.to(METER) > 0:
            return first.thickness
        return first.column_spacing
    var gap = keys[order[1]] - keys[order[0]]
    var shift_limit = SPACING_TOLERANCE * first.column_spacing.to(METER)
    for k in range(1, len(order)):  # pragma: no branch
        var step = keys[order[k]] - keys[order[k - 1]]
        if not (step > SPACING_TOLERANCE * gap):
            raise Error("Two slices of a stack share one position")
        if abs(step - gap) > SPACING_TOLERANCE * gap:
            raise Error("The slices of a stack are not evenly spaced")
        ref slice = slices[order[k]]
        var along = keys[order[k]] - keys[order[0]]
        var shift = slice.position - first.position - normal * along
        if length(shift) > shift_limit:
            raise Error("A slice of the stack is shifted sideways")
    return Length64(gap, METER)


def volume_slices(
    volume: ImageVolume, slope: Float64, intercept: Float64
) raises -> List[DicomSlice]:
    """Return one DICOM slice for each `k` of a volume.

    Each slice has the volume's spacing, orientation, window and
    photometric interpretation, and the position of its first voxel. The
    thickness is the spacing along `k`. The instance numbers count from
    one. The has flags are set. The rescale decides how finely a 16-bit
    file keeps the values: a stored value of one is `slope` apart from the
    next. CT in Hounsfield units uses a slope of 1 and an intercept of 0.

    Args:
        volume: The volume to cut.
        slope: The rescale slope of each slice. Not zero.
        intercept: The rescale intercept of each slice.

    Returns:
        The slices, in order of `k`.

    Raises:
        Error: If the volume has more than 65535 rows or columns, or the
            slope is zero or the rescale is not finite.
    """
    if slope == 0 or not isfinite(slope) or not isfinite(intercept):
        raise Error("A rescale needs a finite slope that is not zero")
    var out = List[DicomSlice]()
    var plane = volume.nx * volume.ny
    for k in range(volume.nz):  # pragma: no branch
        var slice = DicomSlice(volume.ny, volume.nx)
        slice.row_spacing = volume.spacing_y
        slice.column_spacing = volume.spacing_x
        slice.thickness = volume.spacing_z
        slice.position = volume.patient_point(0, 0, Float64(k))
        slice.row_direction = volume.axis_x
        slice.column_direction = volume.axis_y
        slice.has_position = True
        slice.has_orientation = True
        slice.has_spacing = True
        slice.window_center = volume.window_center
        slice.window_width = volume.window_width
        slice.has_window = True
        slice.photometric = volume.photometric
        slice.instance_number = k + 1
        slice.slope = slope
        slice.intercept = intercept
        for index in range(plane):  # pragma: no branch
            slice.values[index] = volume.values[k * plane + index]
        out.append(slice^)
    return out^
