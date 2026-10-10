# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The water textures as flat arrays, for a GPU or any other plain memory.

A `WaterPack` copies the surface, the ripple window, the caustics and the
pebble photograph into flat float arrays, each with a small table of mip
levels. The views read those arrays through the same texel traits as the
original fields, so `lit_radiance` gives the same result from either.

A view holds an untracked pointer. Keep its pack, or the device buffers
copied from the pack, alive and unchanged while the view is in use. Mojo
ends a value at its last use, so use the pack after the last view read.

Each table starts with the level count after the base. Then each level
has its side, or its width and height for the photograph, and the float
offset of its first texel.
"""

from extensions.water.caustics import CausticField, CausticTexels
from extensions.water.pebbles import PebbleBed, PebbleSample, PebbleTexels
from extensions.water.ripple import RippleField, RippleTexels
from extensions.water.surface import (
    SurfaceField,
    SurfaceSample,
    SurfaceTexels,
)
from std.memory import AddressSpace

comptime _Untracked = UntrackedOrigin[mut=False]


struct SurfaceView[space: AddressSpace](ImplicitlyCopyable, SurfaceTexels):
    """A packed surface and its mips, read in place.

    Parameters:
        space: The address space of the arrays.
    """

    var texels: Pointer[Float32, _Untracked, address_space=Self.space]
    """Four floats a texel, every level after the one before."""
    var table: Pointer[Int64, _Untracked, address_space=Self.space]
    """The level count, then each level's side and offset."""
    var patch: Float32
    """The world length of one tile, in meters."""

    def __init__(
        out self,
        texels: Pointer[Float32, _Untracked, address_space=Self.space],
        table: Pointer[Int64, _Untracked, address_space=Self.space],
        patch: Float32,
    ):
        """Read a packed surface.

        Args:
            texels: The packed texels.
            table: The packed level table.
            patch: The world length of one tile, in meters.
        """
        self.texels = texels
        self.table = table
        self.patch = patch

    def surface_patch(self) -> Float32:
        """Return the world length of one tile, in meters.

        Returns:
            The patch length.
        """
        return self.patch

    def surface_levels(self) -> Int:
        """Return how many mip levels follow the base grid.

        Returns:
            The count of coarser levels.
        """
        return Int(self.table[unsafe_offset=0])

    def surface_side(self, level: Int) -> Int:
        """Return the texels on one side of a level.

        Args:
            level: The level. Zero or less is the base grid.

        Returns:
            The side length.
        """
        return Int(self.table[unsafe_offset=1 + 2 * max(level, 0)])

    def surface_texel(self, level: Int, x: Int, y: Int) -> SurfaceSample:
        """Return one texel of a level.

        Args:
            level: The level. Zero or less is the base grid.
            x: Column inside that level.
            y: Row inside that level.

        Returns:
            Height, slopes and squared slope.
        """
        var entry = 1 + 2 * max(level, 0)
        var side = Int(self.table[unsafe_offset=entry])
        var at = Int(self.table[unsafe_offset=entry + 1]) + (y * side + x) * 4
        return SurfaceSample(
            self.texels[unsafe_offset=at],
            self.texels[unsafe_offset=at + 1],
            self.texels[unsafe_offset=at + 2],
            self.texels[unsafe_offset=at + 3],
        )


struct RippleView[space: AddressSpace](ImplicitlyCopyable, RippleTexels):
    """A ripple window's normal texture, read in place.

    Parameters:
        space: The address space of the array.
    """

    var normal: Pointer[Float32, _Untracked, address_space=Self.space]
    """Four floats a texel: height, both slopes and the Laplacian."""
    var side: Int
    """Texels on one side."""
    var size: Float32
    """The window length, in meters."""
    var center_x: Float32
    """The world x of the window center, in meters."""
    var center_z: Float32
    """The world z of the window center, in meters."""

    def __init__(
        out self,
        normal: Pointer[Float32, _Untracked, address_space=Self.space],
        side: Int,
        size: Float32,
        center_x: Float32,
        center_z: Float32,
    ):
        """Read a packed ripple window.

        Args:
            normal: The normal texture.
            side: Texels on one side.
            size: The window length, in meters.
            center_x: The world x of the window center, in meters.
            center_z: The world z of the window center, in meters.
        """
        self.normal = normal
        self.side = side
        self.size = size
        self.center_x = center_x
        self.center_z = center_z

    def ripple_side(self) -> Int:
        """Return the texels on one side of the window.

        Returns:
            The side length.
        """
        return self.side

    def ripple_size(self) -> Float32:
        """Return the window length, in meters.

        Returns:
            The world length of one side.
        """
        return self.size

    def ripple_center_x(self) -> Float32:
        """Return the world x of the window center, in meters.

        Returns:
            The center x.
        """
        return self.center_x

    def ripple_center_z(self) -> Float32:
        """Return the world z of the window center, in meters.

        Returns:
            The center z.
        """
        return self.center_z

    def ripple_normal(self, index: Int) -> Float32:
        """Return one float of the normal texture.

        Args:
            index: `(y * side + x) * 4 + channel`.

        Returns:
            The stored float.
        """
        return self.normal[unsafe_offset=index]


struct CausticView[space: AddressSpace](CausticTexels, ImplicitlyCopyable):
    """A packed caustic texture and its mips, read in place.

    Parameters:
        space: The address space of the arrays.
    """

    var texels: Pointer[Float32, _Untracked, address_space=Self.space]
    """Three floats a texel, every level after the one before."""
    var table: Pointer[Int64, _Untracked, address_space=Self.space]
    """The level count, then each level's side and offset."""
    var patch: Float32
    """The ocean patch length the texture tiles, in meters."""
    var shift_x: Float32
    """The x registration shift, in meters."""
    var shift_z: Float32
    """The z registration shift, in meters."""

    def __init__(
        out self,
        texels: Pointer[Float32, _Untracked, address_space=Self.space],
        table: Pointer[Int64, _Untracked, address_space=Self.space],
        patch: Float32,
        shift_x: Float32,
        shift_z: Float32,
    ):
        """Read a packed caustic texture.

        Args:
            texels: The packed texels.
            table: The packed level table.
            patch: The ocean patch length, in meters.
            shift_x: The x registration shift, in meters.
            shift_z: The z registration shift, in meters.
        """
        self.texels = texels
        self.table = table
        self.patch = patch
        self.shift_x = shift_x
        self.shift_z = shift_z

    def caustic_patch(self) -> Float32:
        """Return the ocean patch length the texture tiles, in meters.

        Returns:
            The patch length.
        """
        return self.patch

    def caustic_shift_x(self) -> Float32:
        """Return the x registration shift, in meters.

        Returns:
            The flat-surface shift along x.
        """
        return self.shift_x

    def caustic_shift_z(self) -> Float32:
        """Return the z registration shift, in meters.

        Returns:
            The flat-surface shift along z.
        """
        return self.shift_z

    def caustic_levels(self) -> Int:
        """Return how many mip levels follow the base texture.

        Returns:
            The count of coarser levels.
        """
        return Int(self.table[unsafe_offset=0])

    def caustic_side(self, level: Int) -> Int:
        """Return the texels on one side of a level.

        Args:
            level: The level. Zero or less is the base texture.

        Returns:
            The side length.
        """
        return Int(self.table[unsafe_offset=1 + 2 * max(level, 0)])

    def caustic_channel(self, level: Int, x: Int, y: Int, c: Int) -> Float32:
        """Return one channel of one texel of a level.

        Args:
            level: The level. Zero or less is the base texture.
            x: Column inside that level.
            y: Row inside that level.
            c: 0 red, 1 green, 2 blue.

        Returns:
            The stored intensity.
        """
        var entry = 1 + 2 * max(level, 0)
        var side = Int(self.table[unsafe_offset=entry])
        var at = Int(self.table[unsafe_offset=entry + 1])
        return self.texels[unsafe_offset=at + (y * side + x) * 3 + c]


struct PebbleView[space: AddressSpace](ImplicitlyCopyable, PebbleTexels):
    """A packed pebble photograph and its mips, read in place.

    Parameters:
        space: The address space of the arrays.
    """

    var texels: Pointer[Float32, _Untracked, address_space=Self.space]
    """Three floats a texel, every level after the one before."""
    var table: Pointer[Int64, _Untracked, address_space=Self.space]
    """The level count, then each level's width, height and offset."""

    def __init__(
        out self,
        texels: Pointer[Float32, _Untracked, address_space=Self.space],
        table: Pointer[Int64, _Untracked, address_space=Self.space],
    ):
        """Read a packed photograph.

        Args:
            texels: The packed texels.
            table: The packed level table.
        """
        self.texels = texels
        self.table = table

    def pebble_levels(self) -> Int:
        """Return how many mip levels follow the photograph.

        Returns:
            The count of coarser levels.
        """
        return Int(self.table[unsafe_offset=0])

    def pebble_width(self, level: Int) -> Int:
        """Return the texels across a level.

        Args:
            level: The level. Zero or less is the photograph.

        Returns:
            The width.
        """
        return Int(self.table[unsafe_offset=1 + 3 * max(level, 0)])

    def pebble_height(self, level: Int) -> Int:
        """Return the texels down a level.

        Args:
            level: The level. Zero or less is the photograph.

        Returns:
            The height.
        """
        return Int(self.table[unsafe_offset=2 + 3 * max(level, 0)])

    def pebble_texel(self, level: Int, x: Int, y: Int) -> PebbleSample:
        """Return one linear texel of a level.

        Args:
            level: The level. Zero or less is the photograph.
            x: Column inside that level.
            y: Row inside that level.

        Returns:
            The linear color.
        """
        var entry = 1 + 3 * max(level, 0)
        var width = Int(self.table[unsafe_offset=entry])
        var at = Int(self.table[unsafe_offset=entry + 2]) + (y * width + x) * 3
        return PebbleSample(
            self.texels[unsafe_offset=at],
            self.texels[unsafe_offset=at + 1],
            self.texels[unsafe_offset=at + 2],
        )


def _untracked[
    T: Copyable
](values: List[T]) -> Pointer[
    T, _Untracked, address_space=AddressSpace.GENERIC
]:
    return values.unsafe_ptr().unsafe_origin_cast[_Untracked]()


def _entry(count: Int) -> Int64:
    # A kernel argument needs a fixed-width integer, not `Int`.
    return Int64(count)


struct WaterPack(Movable):
    """Flat copies of every texture one water frame reads.

    The arrays are the layout a GPU kernel receives. The `*_view` methods
    read them in host memory.
    """

    var surface: List[Float32]
    """The surface texels, base grid first."""
    var surface_table: List[Int64]
    """The surface level table."""
    var surface_patch: Float32
    """The ocean tile length, in meters."""
    var ripple: List[Float32]
    """The ripple normal texture."""
    var ripple_side: Int
    """Ripple texels on one side."""
    var ripple_size: Float32
    """The ripple window length, in meters."""
    var ripple_center_x: Float32
    """The world x of the ripple window center, in meters."""
    var ripple_center_z: Float32
    """The world z of the ripple window center, in meters."""
    var caustic: List[Float32]
    """The caustic texels, base texture first."""
    var caustic_table: List[Int64]
    """The caustic level table."""
    var caustic_patch: Float32
    """The ocean patch length the caustics tile, in meters."""
    var caustic_shift_x: Float32
    """The caustic x registration shift, in meters."""
    var caustic_shift_z: Float32
    """The caustic z registration shift, in meters."""
    var pebble: List[Float32]
    """The photograph texels, base level first."""
    var pebble_table: List[Int64]
    """The photograph level table."""

    def __init__(
        out self,
        surface: SurfaceField,
        ripples: RippleField,
        caustics: CausticField,
        bed: PebbleBed,
    ):
        """Copy one frame's textures.

        Args:
            surface: The resolved ocean surface.
            ripples: The ripple window.
            caustics: The caustic texture.
            bed: The pebble photograph.
        """
        self.surface = List[Float32]()
        self.surface_table = [_entry(surface.surface_levels())]
        for level in range(surface.surface_levels() + 1):  # pragma: no branch
            var side = surface.surface_side(level)
            self.surface_table.append(_entry(side))
            self.surface_table.append(_entry(len(self.surface)))
            if level == 0:
                self.surface.extend(surface.field.samples.copy())
            else:
                self.surface.extend(surface.mips[level - 1].samples.copy())
        self.surface_patch = surface.surface_patch()
        self.ripple = ripples.normal.copy()
        self.ripple_side = ripples.n
        self.ripple_size = ripples.size
        self.ripple_center_x = ripples.center_x
        self.ripple_center_z = ripples.center_z
        self.caustic = caustics.samples.copy()
        self.caustic.extend(caustics.mip_px.copy())
        var base = len(caustics.samples)
        self.caustic_table = [_entry(caustics.caustic_levels())]
        self.caustic_table.append(_entry(caustics.n))
        self.caustic_table.append(0)
        for level in range(len(caustics.mip_n)):  # pragma: no branch
            self.caustic_table.append(_entry(caustics.mip_n[level]))
            self.caustic_table.append(_entry(base + caustics.mip_off[level]))
        self.caustic_patch = caustics.patch
        self.caustic_shift_x = caustics.shift_x
        self.caustic_shift_z = caustics.shift_z
        self.pebble = bed.pixels.copy()
        self.pebble.extend(bed.mip_px.copy())
        base = len(bed.pixels)
        self.pebble_table = [_entry(bed.pebble_levels())]
        self.pebble_table.append(_entry(bed.width))
        self.pebble_table.append(_entry(bed.height))
        self.pebble_table.append(0)
        for level in range(len(bed.mip_w)):  # pragma: no branch
            self.pebble_table.append(_entry(bed.mip_w[level]))
            self.pebble_table.append(_entry(bed.mip_h[level]))
            self.pebble_table.append(_entry(base + bed.mip_off[level]))

    def surface_view(self) -> SurfaceView[AddressSpace.GENERIC]:
        """Read the packed surface in host memory.

        Returns:
            A view that is valid while this pack lives unchanged.
        """
        return SurfaceView[AddressSpace.GENERIC](
            _untracked(self.surface),
            _untracked(self.surface_table),
            self.surface_patch,
        )

    def ripple_view(self) -> RippleView[AddressSpace.GENERIC]:
        """Read the packed ripple window in host memory.

        Returns:
            A view that is valid while this pack lives unchanged.
        """
        return RippleView[AddressSpace.GENERIC](
            _untracked(self.ripple),
            self.ripple_side,
            self.ripple_size,
            self.ripple_center_x,
            self.ripple_center_z,
        )

    def caustic_view(self) -> CausticView[AddressSpace.GENERIC]:
        """Read the packed caustics in host memory.

        Returns:
            A view that is valid while this pack lives unchanged.
        """
        return CausticView[AddressSpace.GENERIC](
            _untracked(self.caustic),
            _untracked(self.caustic_table),
            self.caustic_patch,
            self.caustic_shift_x,
            self.caustic_shift_z,
        )

    def pebble_view(self) -> PebbleView[AddressSpace.GENERIC]:
        """Read the packed photograph in host memory.

        Returns:
            A view that is valid while this pack lives unchanged.
        """
        return PebbleView[AddressSpace.GENERIC](
            _untracked(self.pebble), _untracked(self.pebble_table)
        )
