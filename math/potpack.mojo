# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Packing rectangles into a square-ish container: mapbox's `potpack`,
which three.js ships as `examples/jsm/libs/potpack.module.js` and
`ProgressiveLightMap` lays its objects' texture squares out with.

The boxes are sorted tallest first, stably, and each goes into the
smallest free space that holds it, scanning from the newest space back.
A box that fills a space's height or width shrinks the space; one that
fills neither splits it in two.
"""

from std.math import ceil, inf, max, sqrt


@fieldwise_init
struct PackedBox(Copyable, Movable):
    """A box to pack: its size, where `potpack` puts it, and a tag the
    caller keeps it by, three.js's `{ w, h, x, y, index }`."""

    var w: Float64
    var h: Float64
    var x: Float64
    var y: Float64
    var index: Int


@fieldwise_init
struct Packing(ImplicitlyCopyable):
    """What `potpack` returns: the container's size and how much of it the
    boxes fill."""

    var w: Float64
    var h: Float64
    var fill: Float64


@fieldwise_init
struct _Space(Copyable, Movable):
    """A free space: its corner and size. The bottom one is unbounded."""

    var x: Float64
    var y: Float64
    var w: Float64
    var h: Float64


def potpack(mut boxes: List[PackedBox]) -> Packing:
    """Place each box, and return the container: mapbox's `potpack`.

    The boxes are reordered tallest first, as `potpack` sorts its array in
    place. Each box's `x` and `y` is where it goes.

    Args:
        boxes: The boxes, sized. Their places are written.

    Returns:
        The container's width and height, and the share of it filled, or
        zero for no boxes.
    """
    var area = Float64(0)
    var widest = Float64(0)
    for index in range(len(boxes)):
        area += boxes[index].w * boxes[index].h
        widest = max(widest, boxes[index].w)
    # Tallest first, and in the order given among equals, as JavaScript's
    # stable sort keeps them.
    for index in range(1, len(boxes)):
        var at = index
        while at > 0 and boxes[at - 1].h < boxes[at].h:
            boxes.swap_elements(at - 1, at)
            at -= 1
    # A square-ish start, a little wider for a fill below one.
    var start = max(ceil(sqrt(area / 0.95)), widest)
    var spaces: List[_Space] = [_Space(0, 0, start, inf[DType.float64]())]
    var width = Float64(0)
    var height = Float64(0)
    for index in range(len(boxes)):
        # The spaces backwards, so the smaller ones are tried first. One
        # always holds the box: the bottom space is unbounded and as wide
        # as the widest box, so the search never runs out.
        var at = len(spaces) - 1
        while at >= 0:  # pragma: no branch
            if boxes[index].w > spaces[at].w or boxes[index].h > spaces[at].h:
                at -= 1
                continue
            boxes[index].x = spaces[at].x
            boxes[index].y = spaces[at].y
            height = max(height, boxes[index].y + boxes[index].h)
            width = max(width, boxes[index].x + boxes[index].w)
            if (
                boxes[index].w == spaces[at].w
                and boxes[index].h == spaces[at].h
            ):
                # The box fills the space: the last space takes its place.
                var last = spaces.pop()
                if at < len(spaces):
                    spaces[at] = last^
            elif boxes[index].h == spaces[at].h:
                spaces[at].x += boxes[index].w
                spaces[at].w -= boxes[index].w
            elif boxes[index].w == spaces[at].w:
                spaces[at].y += boxes[index].h
                spaces[at].h -= boxes[index].h
            else:
                # The box splits the space: a new one beside it, and the
                # old one below it.
                spaces.append(
                    _Space(
                        spaces[at].x + boxes[index].w,
                        spaces[at].y,
                        spaces[at].w - boxes[index].w,
                        boxes[index].h,
                    )
                )
                spaces[at].y += boxes[index].h
                spaces[at].h -= boxes[index].h
            break
    var fill = Float64(0)
    if width * height > 0:
        fill = area / (width * height)
    return Packing(width, height, fill)
