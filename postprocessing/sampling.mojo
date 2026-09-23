# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reading a frame the way a shader reads a texture: bilinear, clamped at
the edges, with `v` running up from the bottom.

Every pass in `postprocessing` reads its frame through these, so a tap
past the edge means one thing everywhere: the edge pixel, as a texture
with `ClampToEdgeWrapping` gives it. The GPU backend reads its device
buffers through the same `LightView`; see `render.gpu.GpuComposer`.
"""

from render.framebuffer import FloatColor


# A view's pointer is not tracked by the compiler: whoever builds one keeps
# the pixels alive for as long as it is read. See `LightView`.
comptime Untracked = UntrackedOrigin[mut=False]


struct LightView(ImplicitlyCopyable):
    """A frame's light as a shader's `sampler2D` reads it: a pointer to its
    pixels, row by row from the top, and its size.

    The host builds one over a `List[FloatColor]`, and a GPU kernel builds
    one over a device buffer of four floats a pixel. Both then read
    through the same `tap` and `sample`, so a pass's taps are one piece
    of arithmetic on both backends. The view does not own the pixels:
    the list or the buffer must outlive every read.
    """

    var colors: Pointer[FloatColor, Untracked]
    var width: Int
    var height: Int

    def __init__(out self, colors: List[FloatColor], width: Int, height: Int):
        """View a list of pixels.

        Args:
            colors: The frame's pixels, row by row, `width` times `height`
                of them. The list must outlive the view.
            width: The frame's width in pixels.
            height: The frame's height in pixels.
        """
        self.colors = colors.unsafe_ptr().unsafe_origin_cast[Untracked]()
        self.width = width
        self.height = height

    def __init__(
        out self,
        *,
        floats: MutPointer[Float32, MutAnyOrigin],
        width: Int,
        height: Int,
    ):
        """View four floats a pixel, red, green, blue and alpha: how a
        device buffer holds a frame.

        Args:
            floats: The first pixel's red. The memory must outlive the
                view.
            width: The frame's width in pixels.
            height: The frame's height in pixels.
        """
        self.colors = (
            floats.unsafe_bitcast[FloatColor]()
            .unsafe_mut_cast[False]()
            .unsafe_origin_cast[Untracked]()
        )
        self.width = width
        self.height = height

    def at(self, x: Int, y: Int) -> FloatColor:
        """Return one pixel, unchecked.

        Args:
            x: The column, inside the frame.
            y: The row, down from the top, inside the frame.

        Returns:
            The light stored there.
        """
        return self.colors[unsafe_offset=y * self.width + x]

    def tap(self, x: Float32, y: Float32) -> FloatColor:
        """Return the light at a point in pixel coordinates, blended from
        the four pixels around it and held at the edges.

        Pixel centers are on the integers and rows count down from the top.

        Args:
            x: The column, fractional.
            y: The row, fractional.

        Returns:
            The bilinear blend of the four pixels around the point.
        """
        var px = x
        var py = y
        if px < 0:
            px = 0
        if py < 0:
            py = 0
        if px > Float32(self.width - 1):
            px = Float32(self.width - 1)
        if py > Float32(self.height - 1):
            py = Float32(self.height - 1)
        var x0 = Int(px)
        var y0 = Int(py)
        var fx = px - Float32(x0)
        var fy = py - Float32(y0)
        var x1 = x0 + 1
        var y1 = y0 + 1
        if x1 >= self.width:
            x1 = self.width - 1
        if y1 >= self.height:
            y1 = self.height - 1
        var top = mix(self.at(x0, y0), self.at(x1, y0), fx)
        var bottom = mix(self.at(x0, y1), self.at(x1, y1), fx)
        return mix(top, bottom, fy)

    def sample(self, u: Float32, v: Float32) -> FloatColor:
        """Return the light at a texture coordinate, as a shader's
        `texture` reads it.

        Args:
            u: Across, zero at the left edge and one at the right.
            v: Up, zero at the bottom edge and one at the top, as `vUv`
                runs.

        Returns:
            The bilinear blend at that point, held at the edges.
        """
        return self.tap(
            u * Float32(self.width) - 0.5,
            (1 - v) * Float32(self.height) - 0.5,
        )


def sample(
    colors: List[FloatColor], width: Int, height: Int, u: Float32, v: Float32
) -> FloatColor:
    """Return the light at a texture coordinate, as a shader's `texture`
    reads it: `LightView.sample` on a list.

    Args:
        colors: The frame's pixels, row by row.
        width: The frame's width in pixels.
        height: The frame's height in pixels.
        u: Across, zero at the left edge and one at the right.
        v: Up, zero at the bottom edge and one at the top, as `vUv` runs.

    Returns:
        The bilinear blend at that point, held at the edges.
    """
    return LightView(colors, width, height).sample(u, v)


def mix(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return `a` moved toward `b` by `t`, every channel: GLSL's `mix`.

    Args:
        a: Where `t` of zero lands.
        b: Where `t` of one lands.
        t: How far from `a` toward `b`.

    Returns:
        The blend.
    """
    return FloatColor(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t,
    )


def u_of(x: Int, width: Int) -> Float32:
    """Return a column's texture coordinate, at its center.

    Args:
        x: The column.
        width: The frame's width in pixels.

    Returns:
        The `u` of the column's center.
    """
    return (Float32(x) + 0.5) / Float32(width)


def v_of(y: Int, height: Int) -> Float32:
    """Return a row's texture coordinate, at its center, up from the bottom.

    Args:
        y: The row, down from the top.
        height: The frame's height in pixels.

    Returns:
        The `v` of the row's center.
    """
    return 1 - (Float32(y) + 0.5) / Float32(height)
