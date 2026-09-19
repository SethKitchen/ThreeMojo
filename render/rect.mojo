# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A rectangle of pixels, for the viewport and the scissor.

three.js's `setViewport` and `setScissor` each take four numbers: a
corner and a size. Four bare integers would pass in any order, and a
`Rect` is the type that stops that. It also carries the one convention
both need, which is where the corner is measured from.

## Up from the bottom

The corner is measured from the *bottom* left of the image, as three.js
and WebGL measure it, and the image's own rows run down from the top.
`contains_pixel` is the one place the two meet: it turns a pixel's row
into a distance from the bottom and asks whether that lands inside. Both
rasterizers ask it, so the host's scissor and the device's are the same
scissor. Nothing here allocates or raises, so it compiles for a device
as readily as for the host.
"""


@fieldwise_init
struct Rect(Equatable, ImplicitlyCopyable, Writable):
    """A rectangle of pixels: a corner, measured from the bottom left of
    the image, and a size."""

    var x: Int
    var y: Int
    var width: Int
    var height: Int

    @staticmethod
    def whole(width: Int, height: Int) -> Rect:
        """Return the rectangle that covers an image of that size.

        Args:
            width: The image's width in pixels.
            height: Its height.

        Returns:
            The rectangle from the bottom left corner to the top right.
        """
        return Rect(0, 0, width, height)

    def is_valid(self) -> Bool:
        """Return True if this rectangle holds at least one pixel.

        A size of zero or less is not a rectangle. A negative corner is
        allowed: a viewport can hang off the image's edge, and the pixels
        it puts outside are simply not drawn.
        """
        return self.width > 0 and self.height > 0

    def fits(self, width: Int, height: Int) -> Bool:
        """Return True if this rectangle lies wholly inside an image of
        that size.

        What a scissor must do: a scissor reaching outside the image would
        promise to keep pixels that are not there.

        Args:
            width: The image's width in pixels.
            height: Its height.

        Returns:
            True if every pixel of the rectangle is on the image.
        """
        return (
            self.is_valid()
            and self.x >= 0
            and self.y >= 0
            and self.x + self.width <= width
            and self.y + self.height <= height
        )

    def top(self, height: Int) -> Int:
        """Return the row this rectangle's top edge is on, counting down
        from the top of an image of that height.

        Where a viewport puts the top of its image, since the corner is
        measured from the bottom and the rows run from the top.

        Args:
            height: The image's height in pixels.

        Returns:
            The row, which is negative for a rectangle reaching above the
            image.
        """
        return height - self.y - self.height

    def contains_pixel(self, x: Int, y: Int, height: Int) -> Bool:
        """Return True if the pixel at column `x` and row `y` is inside.

        The row counts down from the top, as an image's rows do; the
        rectangle's corner counts up from the bottom, as three.js's does.
        Both rasterizers ask this, so they agree about every edge.

        Args:
            x: The pixel's column.
            y: The pixel's row, from the top.
            height: The image's height in pixels.

        Returns:
            True if the pixel is inside the rectangle.
        """
        var from_bottom = height - 1 - y
        return (
            x >= self.x
            and x < self.x + self.width
            and from_bottom >= self.y
            and from_bottom < self.y + self.height
        )
