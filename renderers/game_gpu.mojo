# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The frame that a GPU draws the game from.

`GameRenderer.prepare_gpu` does the work of a frame that the CPU does well:
the shadow maps, the gathering, the light at the vertices and the setup of
each triangle. It stops before the raster. This module names what it leaves
for a GPU, in three plain arrays that a host reads by number:

- `ints`, the counts and the sizes, as 64-bit integers;
- `floats`, the scalars, as 32-bit floats;
- `pointers`, the addresses of the data, as 64-bit integers.

The numbers below are the indexes. `window/threemojo.h` lists the same
numbers for a host that is not in Mojo, and a test keeps the two together.
Every address stays valid until the next call that draws or prepares a frame.

**The vertices.** A vertex takes `VERTEX_FLOATS` floats: its clip position
(four), its ambient light (three), its sun light (three), its world position
(three), a packed fog share (one) and its texture coordinates (two). The
triangles are `corners`, three vertex numbers each, in the order the CPU
raster draws them. A triangle's code is the map it reads at each pixel and
the level of that map, as `renderers.game_renderer.LEVEL_CODE` packs them
(the slot times 32, plus the level), or -1 for none.
"""

comptime VERTEX_FLOATS = 16
"""The floats of one vertex in the vertex array."""

comptime INT_WIDTH = 0
"""The image's width, in pixels."""
comptime INT_HEIGHT = 1
"""The image's height, in pixels."""
comptime INT_VERTICES = 2
"""How many vertices the vertex array holds."""
comptime INT_TRIANGLES = 3
"""How many triangles the corner and code arrays hold."""
comptime INT_SKY_COLUMNS = 4
"""The columns of the sky's grid."""
comptime INT_SKY_ROWS = 5
"""The rows of the sky's grid."""
comptime INT_SKY_STEP = 6
"""The pixels between two samples of the sky's grid."""
comptime INT_FOG = 7
"""1 if the scene has fog, else 0."""
comptime INT_STILL_ON = 8
"""1 if the still shadow map shades the frame, else 0."""
comptime INT_STILL_SIZE = 9
"""The still map's texels on a side."""
comptime INT_STILL_STRIDE = 10
"""The floats in a row of the still map."""
comptime INT_STILL_MADE = 11
"""How many times the still map has been drawn: it changes when the map
does."""
comptime INT_MOVING_ON = 12
"""1 if the moving shadow map shades the frame, else 0."""
comptime INT_MOVING_SIZE = 13
"""The moving map's texels on a side."""
comptime INT_MOVING_STRIDE = 14
"""The floats in a row of the moving map."""
comptime INT_MOVING_MADE = 15
"""How many times the moving map has been drawn."""
comptime INT_MAP_SLOTS = 16
"""How many maps are read at each pixel."""
comptime INT_MAP_LEVELS = 17
"""How many levels the maps hold, in all."""
comptime INT_MAP_FLOATS = 18
"""How many floats the maps' texels take."""
comptime INT_PASSES = 19
"""1 if the library leaves the sky's weather and night, the pond's water and
the smoothing of edges to the host's GPU, else 0. The host asks for this
with `tm_village_passes`."""
comptime INT_DEPTH = 20
"""1 if the host must read the depths back into the image, else 0. The
passes that need them are the ones the GPU does."""
comptime INT_COVER_COLUMNS = 21
"""The columns of the clouds' grid."""
comptime INT_COVER_ROWS = 22
"""The rows of the clouds' grid."""
comptime INT_COVER_STEP = 23
"""The pixels between two points of the clouds' grid."""
comptime INT_NIGHT_ON = 24
"""1 if the night, the dusk and the stars change the sky, else 0."""
comptime INT_SMOOTH_ON = 25
"""1 if the GPU smooths the frame's edges, else 0."""
comptime INT_WATER_ON = 26
"""1 if the GPU composes the pond's water into the frame, else 0."""
comptime INT_WATER_STEP = 27
"""The pixels between two shaded samples of the water."""
comptime INT_WATER_GRID_WIDTH = 28
"""The samples of the water along the frame's width."""
comptime INT_WATER_GRID_HEIGHT = 29
"""The samples of the water along the frame's height."""
comptime INT_WATER_SURFACE_MADE = 30
"""How many times the water's surface and caustics were packed: they
change when the number does."""
comptime INT_WATER_RIPPLE_MADE = 31
"""How many times the water's ripples were copied."""
comptime INT_WATER_BED_MADE = 32
"""How many times the pebble photograph was packed."""
comptime INT_WATER_SURFACE_FLOATS = 33
"""How many floats the water's surface takes."""
comptime INT_WATER_RIPPLE_FLOATS = 34
"""How many floats the water's ripples take."""
comptime INT_WATER_CAUSTIC_FLOATS = 35
"""How many floats the water's caustics take."""
comptime INT_WATER_PEBBLE_FLOATS = 36
"""How many floats the pebble photograph takes."""
comptime INT_WATER_WORDS = 37
"""How many 32-bit words the water's frame words take."""
comptime INT_COUNT = 38
"""How many integers there are."""

comptime FLOAT_EXPOSURE = 0
"""The exposure of the ACES tone mapping."""
comptime FLOAT_BIAS = 1
"""The bias that keeps a surface from shadowing itself, in meters."""
comptime FLOAT_FOG_RED = 2
"""The fog's color, red, linear."""
comptime FLOAT_FOG_GREEN = 3
"""The fog's color, green, linear."""
comptime FLOAT_FOG_BLUE = 4
"""The fog's color, blue, linear."""
comptime FLOAT_STILL_PER_METER = 5
"""The depth that one meter spans in the still map's NDC."""
comptime FLOAT_MOVING_PER_METER = 6
"""The depth that one meter spans in the moving map's NDC."""
comptime FLOAT_WATER_EYE = 7
"""The camera's place in the world: three floats."""
comptime FLOAT_WATER_CLIP = 10
"""The camera's projection and view, column by column: 16 floats. It takes
a world point to the NDC depth that the frame holds."""
comptime FLOAT_WATER_SHARE = 26
"""How much of its own light the water keeps, from 0 at night to 1."""
comptime FLOAT_WATER_NIGHT = 27
"""The color that the water turns toward at night, in bytes: three floats."""
comptime FLOAT_COVER_GRAY = 30
"""The color of a cloud's face, in bytes: three floats."""
comptime FLOAT_COVER_FOG = 33
"""The color of the mist, in bytes: three floats."""
comptime FLOAT_COVER_VEIL = 36
"""How much of the sky an overcast layer hides everywhere."""
comptime FLOAT_COVER_MIST = 37
"""How much the mist takes of what shows."""
comptime FLOAT_COVER_BRIGHT = 38
"""The lightning's gain on what shows."""
comptime FLOAT_COVER_GLOOM = 39
"""How dark the clouds are."""
comptime FLOAT_NIGHT_DAY = 40
"""The hour's daylight, from 0 to 1."""
comptime FLOAT_NIGHT_DUSK = 41
"""The hour's dusk, from 0 to 1."""
comptime FLOAT_NIGHT_STARS = 42
"""How bright the stars show, from 0 to 1."""
comptime FLOAT_NIGHT_D00 = 43
"""The direction through the frame's top left corner: three floats."""
comptime FLOAT_NIGHT_ACROSS = 46
"""The step from that direction to the top right corner: three floats."""
comptime FLOAT_NIGHT_DOWN = 49
"""The step from that direction to the bottom left corner: three floats."""
comptime FLOAT_NIGHT_GLOW = 52
"""The color that the dusk gives the low sky, as a gain: three floats."""
comptime FLOAT_NIGHT_SKY = 55
"""The color that the sky turns toward at night, in bytes: three floats."""
comptime FLOAT_NIGHT_STAR_GRID = 58
"""The cells of the stars' lattice across a unit direction."""
comptime FLOAT_NIGHT_STAR_RATE = 59
"""The share of the lattice's cells that hold a star."""
comptime FLOAT_COUNT = 60
"""How many floats there are."""

comptime POINTER_VERTICES = 0
"""The vertices: `INT_VERTICES` times `VERTEX_FLOATS` floats."""
comptime POINTER_CORNERS = 1
"""The corners: `INT_TRIANGLES` times three 32-bit integers."""
comptime POINTER_CODES = 2
"""The map codes: `INT_TRIANGLES` floats."""
comptime POINTER_SKY = 3
"""The sky's grid: columns times rows times three linear floats."""
comptime POINTER_STILL_DEPTH = 4
"""The still map's depths: `INT_STILL_STRIDE` floats a row."""
comptime POINTER_STILL_CLIP = 5
"""The still map's clip matrix: 16 floats, column by column."""
comptime POINTER_MOVING_DEPTH = 6
"""The moving map's depths."""
comptime POINTER_MOVING_CLIP = 7
"""The moving map's clip matrix."""
comptime POINTER_MAP_TEXELS = 8
"""The maps' texels: `INT_MAP_FLOATS` linear floats, three a texel."""
comptime POINTER_MAP_STARTS = 9
"""Where each level's texels start, in floats: `INT_MAP_LEVELS` integers."""
comptime POINTER_MAP_WIDTHS = 10
"""Each level's width, in texels."""
comptime POINTER_MAP_HEIGHTS = 11
"""Each level's height, in texels."""
comptime POINTER_MAP_FIRSTS = 12
"""Where each map's levels start in the lists above: `INT_MAP_SLOTS`
integers."""
comptime POINTER_MAP_COUNTS = 13
"""How many levels each map has."""
comptime POINTER_MAP_WRAPS_S = 14
"""How each map wraps along u: the value of its `Wrap`."""
comptime POINTER_MAP_WRAPS_T = 15
"""How each map wraps along v."""
comptime POINTER_COLOR = 16
"""The image the GPU's colors go into, RGBA bytes, row by row from the top.
The game that owns the renderer sets it."""
comptime POINTER_DEPTH = 17
"""The image the GPU's depths go into: NDC depth, infinity for the sky."""
comptime POINTER_COVER = 18
"""The clouds' grid: `INT_COVER_COLUMNS` times `INT_COVER_ROWS` floats."""
comptime POINTER_WATER_SURFACE = 19
"""The water's surface texels: `INT_WATER_SURFACE_FLOATS` floats."""
comptime POINTER_WATER_RIPPLE = 20
"""The water's ripple texture: `INT_WATER_RIPPLE_FLOATS` floats."""
comptime POINTER_WATER_CAUSTIC = 21
"""The water's caustic texels: `INT_WATER_CAUSTIC_FLOATS` floats."""
comptime POINTER_WATER_PEBBLE = 22
"""The pebble photograph: `INT_WATER_PEBBLE_FLOATS` floats."""
comptime POINTER_WATER_WORDS = 23
"""The water's frame words: `INT_WATER_WORDS` 32-bit integers."""
comptime POINTER_COUNT = 24
"""How many addresses there are."""


struct GpuFrame(Movable):
    """The three arrays that describe a frame to a GPU."""

    var ints: List[Int64]
    """The counts and the sizes, by `INT_*`."""
    var floats: List[Float32]
    """The scalars, by `FLOAT_*`."""
    var pointers: List[Int64]
    """The addresses of the data, by `POINTER_*`."""

    def __init__(out self):
        """Create a frame that describes nothing: every entry is zero."""
        self.ints = List[Int64](length=INT_COUNT, fill=0)
        self.floats = List[Float32](length=FLOAT_COUNT, fill=0)
        self.pointers = List[Int64](length=POINTER_COUNT, fill=0)


def address[
    mut: Bool, //, T: AnyType, origin: Origin[mut=mut]
](pointer: Pointer[T, origin]) -> Int64:
    """Return where a pointer points, as a number a host can read.

    Parameters:
        mut: Whether the pointer can write.
        T: The type that the pointer points at.
        origin: The origin of the pointer.

    Args:
        pointer: The pointer.

    Returns:
        Its address.
    """
    return Int64(Int(pointer))
