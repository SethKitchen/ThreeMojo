# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a coat painter reads and returns, and the helpers painters share.

A painter sees one vertex at a time: the tag and the bone of the solid
it lies on, and its position and normal in the reference animal's bind
pose. Painting in reference space keeps every mark on the skin as the
animal moves. The painter returns a linear color and a surface class.
"""

from extensions.sdf.ids import SurfacePart
from extensions.animals.noise import fbm3
from extensions.sdf.vector import (
    V3,
    clamp,
    mix,
    smoothstep,
)
from render.srgb import srgb_to_linear
from std.collections import Dict

# How many surface classes there are.
comptime SURFACE_CLASS_COUNT = 9


@fieldwise_init
struct SurfaceClass(Equatable, ImplicitlyCopyable, Writable):
    """What a vertex is made of, which picks its material.

    `FUR` and `FEATHER` are matte. `SKIN` is a bare, soft sheen. `NOSE`
    and `WET` are moist leather and wet skin, with a tight highlight.
    `KERATIN` is claw, hoof, horn, beak and tooth. `SCALES` is a reptile's
    or a fish's skin. `CHITIN` is an arthropod's shell. `EYE` is the
    cornea, the glossiest of all.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the classes.

        Returns:
            Whether the value is from zero to `SURFACE_CLASS_COUNT - 1`.
        """
        return self.value >= 0 and self.value < SURFACE_CLASS_COUNT


comptime FUR = SurfaceClass(0)
comptime SKIN = SurfaceClass(1)
comptime NOSE = SurfaceClass(2)
comptime WET = SurfaceClass(3)
comptime KERATIN = SurfaceClass(4)
comptime SCALES = SurfaceClass(5)
comptime CHITIN = SurfaceClass(6)
comptime FEATHER = SurfaceClass(7)
comptime EYE = SurfaceClass(8)


@fieldwise_init
struct Paint(ImplicitlyCopyable):
    """One painted vertex: a linear color and what it is made of."""

    var color: V3
    var surface: SurfaceClass


@fieldwise_init
struct CoatSample(ImplicitlyCopyable):
    """What a painter knows of one vertex.

    `p` and `n` are in the reference animal's bind pose. `local` is the
    vertex in the frame of the solid it lies on: the eye painters read
    the iris from it. `tag` and `bone` index the sculpt's tags and the
    rig's bones.
    """

    var p: V3
    var n: V3
    var local: V3
    var tag: Int
    var bone: Int
    var part: SurfacePart


def srgb(hex: Int) -> V3:
    """Return an sRGB hex color in linear light.

    Args:
        hex: `0xRRGGBB`.

    Returns:
        The linear color, decoded by `render.srgb`.
    """
    return V3(
        Float64(srgb_to_linear(Float32((hex >> 16) & 255) / 255.0)),
        Float64(srgb_to_linear(Float32((hex >> 8) & 255) / 255.0)),
        Float64(srgb_to_linear(Float32(hex & 255) / 255.0)),
    )


def mix3(a: V3, b: V3, t: Float64) -> V3:
    """Return the linear blend of two colors.

    Args:
        a: The color at zero.
        b: The color at one.
        t: The fraction.

    Returns:
        The blend.
    """
    return a + (b - a) * t


def grizzle(c: V3, p: V3, scale: Float64, amount: Float64) -> V3:
    """Return a color broken up by fur-scale noise.

    The noise is stretched along the body, so it reads as hair lying
    back rather than as blotches.

    Args:
        c: The color.
        p: The reference position.
        scale: Features per meter across the body.
        amount: The largest change, as a fraction.

    Returns:
        The color, lighter or darker by up to `amount`.
    """
    var q = V3(p.x * scale, p.y * scale, p.z * scale * 0.35)
    var f = 1.0 + amount * (2.0 * fbm3(q, 3) - 1.0)
    return c * f


def band(x: Float64, a: Float64, b: Float64, c: Float64, d: Float64) -> Float64:
    """Return a soft window: rises from `a` to `b`, falls from `c` to `d`.

    Args:
        x: The value.
        a: Where the rise starts.
        b: Where the rise ends.
        c: Where the fall starts.
        d: Where the fall ends.

    Returns:
        A weight from zero to one.
    """
    return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))


def shade(c: V3, k: Float64) -> V3:
    """Return a color scaled, held to the range a surface can reflect.

    Args:
        c: The color.
        k: The factor.

    Returns:
        The scaled color, each channel at most 0.95.
    """
    return V3(
        clamp(c.x * k, 0.0, 0.95),
        clamp(c.y * k, 0.0, 0.95),
        clamp(c.z * k, 0.0, 0.95),
    )


@fieldwise_init
struct EyeLook(ImplicitlyCopyable):
    """How one species' eye is colored.

    The iris runs from `inner` at the pupil through `mid` to `outer` at
    its rim. `pupil` is the pupil's radius as a fraction of the iris's.
    `slit` above one stretches the pupil vertically, as a cat's or a
    goat's is stretched sideways when negative.
    """

    var inner: V3
    var mid: V3
    var outer: V3
    var sclera: V3
    var pupil: Float64
    var slit: Float64


def paint_eye(
    look: EyeLook, local: V3, radius: Float64, iris_r: Float64
) -> Paint:
    """Paint one point of an eyeball: pupil, iris, limbal ring, sclera.

    Args:
        look: The species' eye colors.
        local: The point in the eyeball's frame, `z` out of the eye.
        radius: The eyeball's radius.
        iris_r: The iris's radius.

    Returns:
        The paint, of class `EYE`.
    """
    var stretch = look.slit if look.slit > 0.0 else 1.0
    var squash = -look.slit if look.slit < 0.0 else 1.0
    var px = local.x * stretch
    var py = local.y * squash
    var across = (px * px + py * py) ** 0.5 / iris_r
    var plain = (local.x * local.x + local.y * local.y) ** 0.5 / iris_r
    var front = smoothstep(0.0, 0.35 * radius, local.z)
    var pupil_edge = smoothstep(look.pupil * 0.85, look.pupil * 1.05, across)
    var iris = mix3(look.inner, look.mid, smoothstep(look.pupil, 0.7, plain))
    iris = mix3(iris, look.outer, smoothstep(0.75, 1.0, plain))
    # Radial fibers of the stroma, so the iris is not a flat disc.
    var fiber = 0.85 + 0.3 * fbm3(
        V3(local.x / iris_r * 9.0, local.y / iris_r * 9.0, 0.0), 2
    )
    iris = iris * fiber
    var c = mix3(V3(0.004, 0.004, 0.005), iris, pupil_edge)
    var rim = smoothstep(0.97, 1.08, plain)
    c = mix3(c, look.sclera, rim)
    c = mix3(look.sclera, c, front)
    return Paint(c, SurfaceClass(8))


struct Palette(Copyable, Movable):
    """Named linear colors, as a species' palette names its swatches."""

    var names: List[String]
    var colors: List[V3]
    var at: Dict[String, Int]

    def __init__(out self):
        """Make an empty palette."""
        self.names = List[String]()
        self.colors = List[V3]()
        self.at = Dict[String, Int]()

    def set(mut self, name: String, color: V3):
        """Store a color, replacing any earlier one of that name.

        Args:
            name: The swatch.
            color: Its linear color.
        """
        var i = self.at.get(name, -1)
        if i >= 0:
            self.colors[i] = color
            return
        self.at[name] = len(self.names)
        self.names.append(name)
        self.colors.append(color)

    def get(self, name: String) -> V3:
        """Return a swatch.

        Args:
            name: The swatch.

        Returns:
            Its linear color, or mid gray for a swatch the palette lacks.
        """
        var i = self.at.get(name, -1)
        return self.colors[i] if i >= 0 else V3(0.18, 0.18, 0.18)


def palette_of(names: List[String], hexes: List[Int]) raises -> Palette:
    """Return a palette from parallel lists of names and sRGB hex colors.

    Args:
        names: The swatches.
        hexes: Their `0xRRGGBB` colors.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the lists differ in length.
    """
    if len(names) != len(hexes):
        raise Error("A palette needs one color per name")
    var out = Palette()
    for i in range(len(names)):
        out.set(names[i], srgb(hexes[i]))
    return out^
