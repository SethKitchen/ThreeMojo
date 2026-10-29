# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fast renderer for games: opaque, vertex-lit meshes in tiles, sixteen
pixels at a time.

`Renderer` draws every material three.js has, one pixel at a time. A game
frame must take a few milliseconds, so `GameRenderer` draws less, and
draws it differently:

1. **The geometry is read once.** Each geometry is copied into flat arrays
   the first time it is drawn, and again only when `GeometryStore.replace`
   gives it a new generation.
2. **The light is reckoned at the vertices.** Each vertex takes its
   ambient and sky light, and the sun's, apart: `ambient` and `sun`. The
   fog veils both there too. A pixel then needs only
   `ambient + sun * shadow`.
3. **Triangles are binned into tiles.** The triangles are clipped at the
   near plane, culled by their facing and their bounds, and listed in each
   64-pixel tile they touch.
4. **Each tile is drawn on its own core, sixteen pixels at a time.** The
   raster writes only the depth and the triangle's number: a visibility
   buffer. A pixel overdrawn ten times costs ten depth tests and one
   shading.
5. **Each tile is resolved.** Each pixel's triangle gives its light, and
   its shadow is looked up. An empty pixel shows the sky. The light is
   tone mapped and encoded as sRGB bytes.

The arithmetic is the general renderer's where it must agree: the same
`Lighting`, the same ACES curve and fog from `render.game_math`, and the
same sRGB bytes from `SrgbBytes`. Lighting at the vertices is where the
two differ: see the wiki page Game renderer.

**What is drawn.** `scene.meshes` and `scene.skinned_meshes`, opaque, with
`BASIC`, `LAMBERT`, `PHONG`, `STANDARD` and `PHYSICAL` materials, vertex
colors, a color and an emissive color. A standard or physical material is
lit as a Lambert one. A map is read at each vertex, or, with `pixel_maps`
set, at each pixel: see `_PixelMaps`. A map read at each pixel scales all
the light of its vertices, so a material that glows or shines, an emissive
or a phong one, keeps reading its map at each vertex, where the map scales
only its albedo. The renderer keeps each map it reads at each pixel by its
texture id: after a texture changes, or with another `Assets`, call
`forget_maps`. A node program is
drawn only as a `GameShading` registered for it says. Lights: ambient,
hemisphere and directional, the cascades of one sun counted once. Fog:
exponential squared or none. The background: a color or a cube.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import COLOR_BACKGROUND, CUBE_BACKGROUND
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION, UV
from core.deform import SkinPose, skin_pose, whole_bone
from objects.skinned_mesh import (
    BONES_PER_VERTEX,
    SKIN_INDEX,
    SKIN_WEIGHT,
    require_skin_width,
)
from core.fog import EXP2_FOG, NO_FOG, exp2_veil
from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.ordinal import ordinal_valid
from core.scene import Scene
from lights.lighting import Lighting
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    BACK_SIDE,
    LAMBERT,
    PHONG,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
    NO_TEXTURE,
)
from math.frustum import Frustum
from math.matrix4 import Matrix4
from math.bounds import Sphere
from math.cross import cross_vectors
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer, SrgbBytes
from render.game_math import (
    GAME_LANES,
    fast_sin,
    hemisphere_share,
    lambert,
)
from render.tasks import TaskGroup
from render.tonemap import aces_tone
from render.texture import MIRROR, REPEAT, Texture
from render.cube_texture import CubeTexture
from render.texture_store import TextureId
from std.math import ceil, exp2, floor, inf, log2, max, min, sin, sqrt
from std.memory import unsafe_memcpy
from std.time import perf_counter_ns
from units.si import METER, PER_METER, SECOND, Duration

comptime TILE = 64
"""The side of a tile, in pixels."""
comptime STRIDE = 16
"""Floats a vertex takes in the frame's vertex array: its clip position,
its ambient and sun light, its shadow coordinates and spare room."""
comptime PLANE = 16
"""Floats a triangle takes in the frame's plane array: three edges, the
depth plane and the inverse w of each corner."""
comptime CHUNK = 4096
"""The most vertices or triangles one task of the vertex or the setup
stage takes."""
comptime NO_TRIANGLE = Int32(-1)
"""The visibility buffer's mark for a pixel no triangle covers."""
comptime F = SIMD[DType.float32, GAME_LANES]
comptime I = SIMD[DType.int32, GAME_LANES]
comptime _FRESNEL_SLOPE = Float32(-5.55473)
comptime _FRESNEL_OFFSET = Float32(-6.98316)
comptime BLINN_PHONG_G = Float32(0.25)
comptime MIP_LEVELS = 16
"""The most levels of a map read at each pixel."""
comptime SKY_TASKS = 16
"""The most tasks that share the sampling of the sky."""
comptime LEVEL_CODE = Float32(32)
"""A triangle's map code is its map's slot times this, plus the level its
pixels read. A triangle with no map read at each pixel has the code -1."""


struct _PixelMaps(Movable):
    """The maps read at each pixel: every level of each, as linear red,
    green and blue floats in one array.

    Each level halves the one before it, by the mean of each 2 by 2 block
    of texels, down to one texel or `MIP_LEVELS` levels. A triangle reads
    the level at which one texel covers about one pixel: the setup finds
    it from the triangle's area on the screen and its area in texels.
    """

    var texels: List[Float32]
    # For each level of each map: where its texels start, its width and
    # its height.
    var starts: List[Int32]
    var widths: List[Int32]
    var heights: List[Int32]
    # For each map: where its levels start in the lists above, how many
    # levels it has, and how it wraps along u and along v: the value of
    # its `Wrap`.
    var firsts: List[Int32]
    var levels: List[Int32]
    var wraps_s: List[Int32]
    var wraps_t: List[Int32]
    # The slot of each texture id read so far.
    var slot_of: Dict[Int, Int]

    def __init__(out self):
        self.texels = List[Float32]()
        self.starts = List[Int32]()
        self.widths = List[Int32]()
        self.heights = List[Int32]()
        self.firsts = List[Int32]()
        self.levels = List[Int32]()
        self.wraps_s = List[Int32]()
        self.wraps_t = List[Int32]()
        self.slot_of = Dict[Int, Int]()

    def slot(mut self, texture: Texture, id: Int) raises -> Int:
        """Return a texture's slot, reading its levels the first time."""
        if id in self.slot_of:
            return self.slot_of[id]
        var slot = len(self.levels)
        var w = max(1, texture.width)
        var h = max(1, texture.height)
        var level = List[Float32](length=w * h * 3, fill=0)
        # Each side holds at least one texel.
        for y in range(h):  # pragma: no branch
            for x in range(w):  # pragma: no branch
                var c = texture.sample(
                    (Float32(x) + 0.5) / Float32(w),
                    (Float32(y) + 0.5) / Float32(h),
                )
                var at = (y * w + x) * 3
                level[at] = c.r
                level[at + 1] = c.g
                level[at + 2] = c.b
        self.firsts.append(Int32(len(self.starts)))
        var count = 0
        for _ in range(MIP_LEVELS):  # pragma: no branch
            self.starts.append(Int32(len(self.texels)))
            self.widths.append(Int32(w))
            self.heights.append(Int32(h))
            self.texels.extend(level.copy())
            count += 1
            if (w == 1 and h == 1) or count == MIP_LEVELS:
                break
            var w2 = max(1, w // 2)
            var h2 = max(1, h // 2)
            var half = List[Float32](length=w2 * h2 * 3, fill=0)
            for y in range(h2):  # pragma: no branch
                for x in range(w2):  # pragma: no branch
                    var x0 = min(w - 1, 2 * x)
                    var x1 = min(w - 1, 2 * x + 1)
                    var y0 = min(h - 1, 2 * y)
                    var y1 = min(h - 1, 2 * y + 1)
                    for k in range(3):  # pragma: no branch
                        half[(y * w2 + x) * 3 + k] = 0.25 * (
                            level[(y0 * w + x0) * 3 + k]
                            + level[(y0 * w + x1) * 3 + k]
                            + level[(y1 * w + x0) * 3 + k]
                            + level[(y1 * w + x1) * 3 + k]
                        )
            level = half^
            w = w2
            h = h2
        self.levels.append(Int32(count))
        self.wraps_s.append(Int32(texture.wrap_s.value))
        self.wraps_t.append(Int32(texture.wrap_t.value))
        self.slot_of[id] = slot
        return slot


@fieldwise_init
struct SwayMotion(ImplicitlyCopyable):
    """How a crown moves in the wind, as `foliage.sway_offset` moves it.

    The offset is `(along * swing + up * flutter) * weight`, where `swing`
    and `flutter` are sines of the time at their rates plus a phase that
    changes through the crown, and `weight` grows with the height and the
    spread of the vertex.
    """

    # The swing's reach along the wind, in meters, on x and on z.
    var along_x: Float32
    var along_z: Float32
    # The flutter's reach up and down, in meters.
    var flutter: Float32
    # The swing's and the flutter's rates, in radians a second.
    var swing_rate: Float32
    var flutter_rate: Float32
    # How the phases change through the crown, per meter.
    var swing_phase: SIMD[DType.float32, 4]
    var flutter_phase: SIMD[DType.float32, 4]
    # The height of full sway, the spread of full sway, and the most share.
    var height: Float32
    var spread: Float32
    var most: Float32


@fieldwise_init
struct GameShading(Copyable, Movable):
    """What a node program does, in the game renderer's terms.

    The game renderer does not run node programs. Each program that a
    drawn material names must be registered with one of these, which says
    what the program does to the light and to the vertices.
    """

    # Whether a back face is lit as its front, as `two_sided_program`.
    var two_sided_light: Bool
    # The float attributes that hold the baked sun and sky of each vertex,
    # as `foliage_program` reads them, or empty for none.
    var sunlit: String
    var skylit: String
    # How the vertices sway in the wind, if they do.
    var sway: Optional[SwayMotion]


struct _Part(Copyable, Movable):
    """The triangles of one material slot of a geometry, with their own
    vertices."""

    # The material slot: which of a mesh's materials the part wears.
    var slot: Int
    # The geometry's vertices the part uses, in its own order.
    var vertices: List[Int32]
    # Three a triangle, as places in `vertices`.
    var triangles: List[Int32]
    # Its vertices' positions, normals, colors and texture coordinates, in
    # its own order, each padded with zeros to a whole number of
    # `GAME_LANES`, so the vertex stage reads them sixteen at a time.
    var px: List[Float32]
    var py: List[Float32]
    var pz: List[Float32]
    var nx: List[Float32]
    var ny: List[Float32]
    var nz: List[Float32]
    var cr: List[Float32]
    var cg: List[Float32]
    var cb: List[Float32]
    # The baked light, by its place in the shape's `baked`.
    var baked: List[List[Float32]]
    # Four bones and four weights a vertex, for a skinned mesh, read on
    # demand; and the highest bone they name.
    var bones: List[Int32]
    var weights: List[Float32]
    var top_bone: Int

    def __init__(out self, slot: Int):
        """Create an empty part for a material slot.

        Args:
            slot: The material slot.
        """
        self.slot = slot
        self.vertices = List[Int32]()
        self.triangles = List[Int32]()
        self.px = List[Float32]()
        self.py = List[Float32]()
        self.pz = List[Float32]()
        self.nx = List[Float32]()
        self.ny = List[Float32]()
        self.nz = List[Float32]()
        self.cr = List[Float32]()
        self.cg = List[Float32]()
        self.cb = List[Float32]()
        self.baked = List[List[Float32]]()
        self.bones = List[Int32]()
        self.weights = List[Float32]()
        self.top_bone = -1


struct _Shape(Movable):
    """One geometry as the game renderer reads it: flat arrays."""

    var generation: Int
    var count: Int
    var px: List[Float32]
    var py: List[Float32]
    var pz: List[Float32]
    var nx: List[Float32]
    var ny: List[Float32]
    var nz: List[Float32]
    # Linear vertex colors, or ones.
    var cr: List[Float32]
    var cg: List[Float32]
    var cb: List[Float32]
    # The texture coordinates, or zeros.
    var u: List[Float32]
    var v: List[Float32]
    var parts: List[_Part]
    # The bounding sphere, in the geometry's own frame.
    var center: Vector3
    var radius: Float32
    # Baked light by attribute name, read on demand.
    var baked_names: List[String]
    var baked: List[List[Float32]]

    def __init__(out self, geometry: BufferGeometry, generation: Int) raises:
        """Read a geometry.

        Args:
            geometry: The geometry.
            generation: Its generation in the store.

        Raises:
            Error: If it has no positions, or an index or a group is out of
                range.
        """
        self.generation = generation
        ref position = geometry.attribute_view(String(POSITION))
        self.count = position.count()
        self.px = List[Float32](length=self.count, fill=0)
        self.py = List[Float32](length=self.count, fill=0)
        self.pz = List[Float32](length=self.count, fill=0)
        _read3(position, self.px, self.py, self.pz, 0)
        self.nx = List[Float32](length=self.count, fill=0)
        self.ny = List[Float32](length=self.count, fill=1)
        self.nz = List[Float32](length=self.count, fill=0)
        if geometry.has_attribute(String(NORMAL)):
            _read3(
                geometry.attribute_view(String(NORMAL)),
                self.nx,
                self.ny,
                self.nz,
                0,
            )
        self.cr = List[Float32](length=self.count, fill=1)
        self.cg = List[Float32](length=self.count, fill=1)
        self.cb = List[Float32](length=self.count, fill=1)
        if geometry.has_attribute(String(COLOR)):
            _read3(
                geometry.attribute_view(String(COLOR)),
                self.cr,
                self.cg,
                self.cb,
                0,
            )
        self.u = List[Float32](length=self.count, fill=0)
        self.v = List[Float32](length=self.count, fill=0)
        if geometry.has_attribute(String(UV)):
            ref uv = geometry.attribute_view(String(UV))
            for i in range(self.count):
                self.u[i] = uv.component(i, 0)
                self.v[i] = uv.component(i, 1)
        self.parts = List[_Part]()
        var corners = (
            len(geometry.index) if len(geometry.index) > 0 else self.count
        )
        if len(geometry.groups) == 0:
            self.parts.append(_part(geometry, 0, corners, 0, self.count))
        else:
            for g in geometry.groups:  # pragma: no branch
                var start = max(0, g.start)
                var past = min(corners, g.start + g.count)
                self.parts.append(
                    _part(
                        geometry,
                        start,
                        past,
                        g.material_index.value,
                        self.count,
                    )
                )
        var low = Vector3(1.0e30, 1.0e30, 1.0e30)
        var high = Vector3(-1.0e30, -1.0e30, -1.0e30)
        for i in range(self.count):
            low = Vector3(
                min(low.x, self.px[i]),
                min(low.y, self.py[i]),
                min(low.z, self.pz[i]),
            )
            high = Vector3(
                max(high.x, self.px[i]),
                max(high.y, self.py[i]),
                max(high.z, self.pz[i]),
            )
        self.center = (low + high) * 0.5
        var reach = Float32(0)
        for i in range(self.count):
            var dx = self.px[i] - self.center.x
            var dy = self.py[i] - self.center.y
            var dz = self.pz[i] - self.center.z
            reach = max(reach, dx * dx + dy * dy + dz * dz)
        self.radius = sqrt(reach)
        self.baked_names = List[String]()
        self.baked = List[List[Float32]]()
        for p in range(len(self.parts)):  # pragma: no branch
            ref part = self.parts[p]
            _gather_into(part.px, self.px, part.vertices)
            _gather_into(part.py, self.py, part.vertices)
            _gather_into(part.pz, self.pz, part.vertices)
            _gather_into(part.nx, self.nx, part.vertices)
            _gather_into(part.ny, self.ny, part.vertices)
            _gather_into(part.nz, self.nz, part.vertices)
            _gather_into(part.cr, self.cr, part.vertices)
            _gather_into(part.cg, self.cg, part.vertices)
            _gather_into(part.cb, self.cb, part.vertices)

    def baked_values(
        mut self, geometry: BufferGeometry, name: String
    ) raises -> Int:
        """Return where the named float attribute's values are kept,
        reading them the first time.

        Args:
            geometry: The geometry the shape was read from.
            name: The attribute.

        Returns:
            Its place in `baked`.

        Raises:
            Error: If the geometry has no such attribute.
        """
        for i in range(len(self.baked_names)):
            if self.baked_names[i] == name:
                return i
        if not geometry.has_attribute(name):
            raise Error("A geometry has no attribute '", name, "' to light by")
        ref values = geometry.attribute_view(name)
        var out = List[Float32](length=self.count, fill=0)
        for i in range(self.count):
            out[i] = values.component(i, 0)
        for p in range(len(self.parts)):  # pragma: no branch
            var gathered = List[Float32]()
            _gather_into(gathered, out, self.parts[p].vertices)
            self.parts[p].baked.append(gathered^)
        self.baked_names.append(name)
        self.baked.append(out^)
        return len(self.baked) - 1

    def read_skin(mut self, geometry: BufferGeometry) raises:
        """Read each part's bones and weights, the first time a skinned
        mesh draws the shape.

        Args:
            geometry: The geometry the shape was read from.

        Raises:
            Error: If the geometry has no skin attributes, either is not
                four numbers a vertex or does not cover every vertex, a
                bone is not a whole number from zero, or a weight is not a
                number or is negative.
        """
        if self.parts[0].top_bone >= 0:
            return
        if not geometry.has_attribute(String(SKIN_INDEX)) or not (
            geometry.has_attribute(String(SKIN_WEIGHT))
        ):
            raise Error("A skinned mesh needs skinIndex and skinWeight")
        ref bones = geometry.attribute_view(String(SKIN_INDEX))
        ref weights = geometry.attribute_view(String(SKIN_WEIGHT))
        require_skin_width(bones.item_size)
        require_skin_width(weights.item_size)
        if bones.count() != self.count or weights.count() != self.count:
            raise Error("A skin attribute must cover every vertex")
        for p in range(len(self.parts)):  # pragma: no branch
            ref part = self.parts[p]
            var n = len(part.vertices)
            part.bones = List[Int32](length=n * 4, fill=0)
            part.weights = List[Float32](length=n * 4, fill=0)
            part.top_bone = 0
            for k in range(n):
                var vertex = Int(part.vertices[k])
                for slot in range(BONES_PER_VERTEX):  # pragma: no branch
                    var bone = whole_bone(
                        bones.component(vertex, slot), 1 << 30
                    )
                    var weight = weights.component(vertex, slot)
                    if not (weight >= 0):
                        raise Error(
                            "A skin weight must be a number, not negative"
                        )
                    part.bones[k * 4 + slot] = Int32(bone)
                    part.weights[k * 4 + slot] = weight
                    part.top_bone = max(part.top_bone, bone)


def _gather_into(
    mut target: List[Float32], source: List[Float32], order: List[Int32]
):
    """Fill `target` with `source` in `order`, padded with zeros to a whole
    number of `GAME_LANES`."""
    var count = len(order)
    var padded = (count + GAME_LANES - 1) // GAME_LANES * GAME_LANES
    target = List[Float32](length=padded, fill=0)
    var out = target.unsafe_ptr()
    var src = source.unsafe_ptr()
    var at = order.unsafe_ptr()
    for k in range(count):
        out[unsafe_offset=k] = src[unsafe_offset=Int(at[unsafe_offset=k])]


def _read3(
    attribute: BufferAttribute,
    mut x: List[Float32],
    mut y: List[Float32],
    mut z: List[Float32],
    first: Int,
) raises:
    """Read the first three components of each item of an attribute."""
    var count = min(attribute.count(), len(x))
    var size = attribute.item_size
    if not attribute.is_interleaved() and size >= 3:
        var data = attribute.data.unsafe_ptr()
        for i in range(count):
            x[i] = data[unsafe_offset=i * size]
            y[i] = data[unsafe_offset=i * size + 1]
            z[i] = data[unsafe_offset=i * size + 2]
        return
    for i in range(count):
        x[i] = attribute.component(i, 0)
        y[i] = attribute.component(i, 1) if size > 1 else 0
        z[i] = attribute.component(i, 2) if size > 2 else 0


def _part(
    geometry: BufferGeometry, start: Int, past: Int, slot: Int, count: Int
) raises -> _Part:
    """Return the triangles from corner `start` to `past`, with their own
    vertices."""
    var part = _Part(slot)
    var seen = List[Int32](length=count, fill=-1)
    var indexed = len(geometry.index) > 0
    var corner = start
    while corner + 2 < past:
        for k in range(3):
            var vertex = geometry.index[corner + k] if indexed else corner + k
            # A negative vertex wraps round to a huge one.
            if UInt(vertex) >= UInt(count):
                raise Error("A triangle names a vertex the geometry lacks")
            if seen[vertex] < 0:
                seen[vertex] = Int32(len(part.vertices))
                part.vertices.append(Int32(vertex))
            part.triangles.append(seen[vertex])
        corner += 3
    return part^


@fieldwise_init
struct _Look(ImplicitlyCopyable):
    """A material as the vertex stage lights it."""

    var basic: Bool
    var phong: Bool
    var color: SIMD[DType.float32, 4]
    var emissive: SIMD[DType.float32, 4]
    var specular: SIMD[DType.float32, 4]
    var shininess: Float32
    var vertex_colors: Bool
    # Which faces are drawn: 0 the front, 1 the back, 2 both.
    var side: Int
    # Whether a back face is lit as its front.
    var two_sided_light: Bool
    var map_color: SIMD[DType.float32, 4]
    var has_map: Bool


@fieldwise_init
struct _Draw(ImplicitlyCopyable):
    """One part of one mesh, placed for the frame."""

    var shape: Int
    var part: Int
    var world: Matrix4
    var look: _Look
    # The baked light's places in the shape's `baked`, or -1.
    var sunlit: Int
    var skylit: Int
    var sway: Optional[SwayMotion]
    # The first of its vertices in the frame's vertex array. A part whose
    # back faces are lit apart has twice as many: front, then back.
    var first: Int
    var lit_twice: Bool
    # Which skinned mesh it is, or -1.
    var skinned: Int
    # Which geometry it reads, for skinning and maps.
    var geometry: GeometryId
    var map: Int
    # Whether the sun's shadows fall on it.
    var receives: Bool
    # Its map's slot when the map is read at each pixel, or -1; and the
    # square root of the map's full-size texel count.
    var pixel: Int
    var texels: Float32


@fieldwise_init
struct _Frame(ImplicitlyCopyable):
    """What every stage of one frame reads: the camera and the light."""

    var view_projection: Matrix4
    var view: Matrix4
    var eye: SIMD[DType.float32, 4]
    var width: Int
    var height: Int
    var ambient: SIMD[DType.float32, 4]
    var sky_up: SIMD[DType.float32, 4]
    var sky: SIMD[DType.float32, 4]
    var ground: SIMD[DType.float32, 4]
    var has_sky: Bool
    var sun_toward: SIMD[DType.float32, 4]
    var sun: SIMD[DType.float32, 4]
    var has_sun: Bool
    var fog: Bool
    var fog_density: Float32
    var fog_color: SIMD[DType.float32, 4]
    var time: Float32
    # Whether the pass writes depth alone, for a shadow map, and whether
    # it culls faces by their facing.
    var depth_only: Bool
    var cull: Bool


@fieldwise_init
struct ShadowMode(Equatable, ImplicitlyCopyable, Writable):
    """How the sun's shadows are drawn, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four modes there are.

        Returns:
            Whether the value names a mode.
        """
        return ordinal_valid(self.value, 3)


# No shadows.
comptime NO_SHADOWS = ShadowMode(0)
# The still casters' map, drawn once; the moving casters cast nothing.
comptime STILL_SHADOWS = ShadowMode(1)
# The still casters' map, drawn once, and the moving casters' small map
# round the focus, drawn every frame.
comptime CACHED_SHADOWS = ShadowMode(2)
# Both maps drawn every frame, so the swaying trees' shadows sway too.
comptime FULL_SHADOWS = ShadowMode(3)


struct _SunMap(Movable):
    """One square depth map of the sun's view: its matrices and texels."""

    var size: Int
    # The texels a row of `depth` holds: the size, rounded up to whole
    # tiles, so the raster's runs of sixteen never leave a tile.
    var stride: Int
    var view: Matrix4
    var clip: Matrix4
    var depth: List[Float32]
    var ids: List[Int32]
    # The depth one meter spans, in the map's NDC.
    var per_meter: Float32
    var ready: Bool

    def __init__(out self, size: Int):
        """Create an empty map.

        Args:
            size: Its texels on a side.
        """
        self.size = size
        self.stride = _padded(size)
        self.view = Matrix4()
        self.clip = Matrix4()
        self.depth = List[Float32](length=self.stride * self.stride, fill=1)
        self.ids = List[Int32](
            length=self.stride * self.stride, fill=NO_TRIANGLE
        )
        self.per_meter = 0
        self.ready = False


def _sun_matrices(
    toward: SIMD[DType.float32, 4], center: Vector3, reach: Float32
) -> Tuple[Matrix4, Matrix4, Float32, Float32]:
    """Return the view and the clip of a square orthographic view down the
    sun's rays, `reach` meters each way round `center`, the depth one meter
    spans in its NDC, and its far distance."""
    var back = Vector3(toward[0], toward[1], toward[2])
    var side = cross_vectors(Vector3(0, 1, 0), back)
    if side.length() < 1.0e-4:
        side = Vector3(1, 0, 0)
    side.normalize()
    var up = cross_vectors(back, side)
    var distance = reach * 4
    var eye = center + back * distance
    var view = Matrix4()
    ref v = view.elements
    v[0] = side.x
    v[4] = side.y
    v[8] = side.z
    v[12] = -side.dot(eye)
    v[1] = up.x
    v[5] = up.y
    v[9] = up.z
    v[13] = -up.dot(eye)
    v[2] = back.x
    v[6] = back.y
    v[10] = back.z
    v[14] = -back.dot(eye)
    var near = Float32(0)
    var far = distance * 2
    var projection = Matrix4()
    ref o = projection.elements
    o[0] = 1 / reach
    o[5] = 1 / reach
    o[10] = -2 / (far - near)
    o[14] = -(far + near) / (far - near)
    var clip = projection
    clip.multiply(view)
    return (view, clip, 2 / (far - near), far)


struct GameRenderer(Movable):
    """Draws a scene's opaque meshes fast, for a game."""

    var width: Int
    var height: Int
    var exposure: Float32
    # The step, in pixels, between the sky's samples.
    var sky_step: Int
    var _shapes: List[Optional[_Shape]]
    var _shadings: Dict[Int, GameShading]
    # The visibility buffer: each pixel's depth and triangle. Its rows
    # hold `_stride` pixels and it has whole tiles of rows, so the
    # raster's runs of sixteen never leave a tile.
    var _stride: Int
    var _depth: List[Float32]
    var _ids: List[Int32]
    var _vertices: List[Float32]
    var _planes: List[Float32]
    var _corners: List[Int32]
    var _bounds: List[Int32]
    # The setup's batches, kept from frame to frame, and how many the last
    # frame used.
    var _batches: List[_Batch]
    var _jobs: Int
    var _encode: SrgbBytes
    # What the last frame drew: its triangles, the pixels they cover, the
    # vertices it lit and the parts of meshes it drew.
    var triangles: Int
    var drawn: Int
    var vertex_count: Int
    var draw_count: Int
    # How long each stage of the last frame took, in milliseconds: the
    # shadow maps, the gathering, the vertices, the setup, the bins, the
    # raster, the sky and the resolve.
    var timings: List[Float64]
    # How the sun's shadows are drawn; the still map's texels on a side,
    # how far it reaches each way round `shadow_center`, in meters; the
    # moving map's texels and reach round `focus`; and the bias that keeps
    # a surface from shadowing itself, in meters.
    var shadows: ShadowMode
    var shadow_size: Int
    var shadow_reach: Float32
    var shadow_center: Vector3
    var moving_size: Int
    var moving_reach: Float32
    var shadow_bias: Float32
    var focus: Vector3
    # Whether each node, by index, moves: its meshes cast into the moving
    # map, not the still one.
    var _moving: List[Bool]
    # The meshes and the skinned meshes the moving nodes carry.
    var _moving_meshes: List[Int]
    var _moving_skins: List[Int]
    # This frame's looks of the materials, by material id, and skinned
    # meshes' bones, twelve floats each, by skinned mesh, after a
    # placeholder.
    var _looks: Dict[Int, Tuple[_Look, Int]]
    var _skins: List[List[Float32]]
    var _skin_of: Dict[Int, Int]
    var _still_map: _SunMap
    var _moving_map: _SunMap
    # Whether a map is read at each pixel rather than at each vertex, and
    # the maps read so.
    var pixel_maps: Bool
    var _pixel: _PixelMaps

    def __init__(
        out self, width: Int, height: Int, exposure: Float32 = 1
    ) raises:
        """Create a renderer of a fixed size.

        Args:
            width: The image's width, in pixels.
            height: The image's height, in pixels.
            exposure: The exposure of the ACES tone mapping.

        Raises:
            Error: If a size is not positive.
        """
        if width <= 0 or height <= 0:
            raise Error("A game renderer's size must be positive")
        self.width = width
        self.height = height
        self.exposure = exposure
        self.sky_step = 4
        self._shapes = List[Optional[_Shape]]()
        self._shadings = Dict[Int, GameShading]()
        self._stride = _padded(width)
        var texels = self._stride * _padded(height)
        self._depth = List[Float32](length=texels, fill=1)
        self._ids = List[Int32](length=texels, fill=NO_TRIANGLE)
        self._vertices = List[Float32]()
        self._planes = List[Float32]()
        self._corners = List[Int32]()
        self._bounds = List[Int32]()
        self._batches = List[_Batch]()
        self._jobs = 0
        self._encode = SrgbBytes()
        self.triangles = 0
        self.drawn = 0
        self.vertex_count = 0
        self.draw_count = 0
        self.timings = List[Float64]()
        self.shadows = NO_SHADOWS
        self.shadow_size = 1024
        self.shadow_reach = 140
        self.shadow_center = Vector3(0, 0, 0)
        self.moving_size = 512
        self.moving_reach = 16
        self.shadow_bias = 0.15
        self.focus = Vector3(0, 0, 0)
        self._moving = List[Bool]()
        self._moving_meshes = List[Int]()
        self._moving_skins = List[Int]()
        self._looks = Dict[Int, Tuple[_Look, Int]]()
        self._skins = [[Float32(0)]]
        self._skin_of = Dict[Int, Int]()
        self._still_map = _SunMap(1)
        self._moving_map = _SunMap(1)
        self.pixel_maps = False
        self._pixel = _PixelMaps()

    def register(mut self, program: Int, var shading: GameShading):
        """Say what a node program does, so materials naming it are drawn.

        Args:
            program: The program's id in `assets.programs`.
            shading: What it does.
        """
        self._shadings[program] = shading^

    def forget_maps(mut self):
        """Forget every map read at each pixel so far, so each is read
        again from its texture when it is next drawn. Call it after a
        texture's texels or wraps change, or before drawing a scene of
        another `Assets`: the renderer keeps each map by its texture id.
        """
        self._pixel = _PixelMaps()

    def render(
        mut self,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
        time: Duration,
    ) raises -> Framebuffer:
        """Draw a scene.

        Args:
            scene: The scene, updated.
            assets: The stores.
            camera: The camera, placed.
            time: The time of the frame, for the wind's sway.

        Returns:
            The image, with each pixel's NDC depth, infinity where the
            sky shows.

        Raises:
            Error: If a drawn material cannot be drawn by this renderer, or
                a geometry or a node is not there.
        """
        var began = perf_counter_ns()
        self._looks.clear()
        self._skins = [[Float32(0)]]
        self._skin_of.clear()
        var frame = self._frame(scene, assets, camera, time)
        if not self.shadows.is_valid():
            raise Error("A shadow mode must be one of the four")
        var shadowing = self.shadows != NO_SHADOWS and frame.has_sun
        if shadowing:
            var still = self._still_map.size != self.shadow_size
            if (
                self.shadows == FULL_SHADOWS
                or still
                or not self._still_map.ready
            ):
                self._still_map = _SunMap(self.shadow_size)
                var center = self.shadow_center
                var reach = self.shadow_reach
                self._draw_map(scene, assets, frame, False, center, reach)
            if self.shadows != STILL_SHADOWS:
                if self._moving_map.size != self.moving_size:
                    self._moving_map = _SunMap(self.moving_size)
                var focus = self.focus
                var reach = self.moving_reach
                self._draw_map(scene, assets, frame, True, focus, reach)
        var mapped = perf_counter_ns()
        var view = camera.view_matrix()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var draws = self._gather(
            scene,
            assets,
            view,
            clip,
            camera.near_distance(),
            camera.far_distance(),
            0,
        )
        self.vertex_count = self._vertex_total(draws)
        self.draw_count = len(draws)
        var gathered = perf_counter_ns()
        self._light_vertices(draws, assets, scene, frame)
        var lit = perf_counter_ns()
        self._setup(draws, frame)
        var set_up = perf_counter_ns()
        var bins = self._bin(self.width, self.height)
        var binned = perf_counter_ns()
        self._raster(
            bins,
            self.width,
            self.height,
            self._stride,
            self._depth.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
            self._ids.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
        )
        var drawn = 0
        for i in range(len(self._ids)):  # pragma: no branch
            if self._ids[i] != NO_TRIANGLE:
                drawn += 1
        self.drawn = drawn
        var rastered = perf_counter_ns()
        var sky = self._sky(scene, assets, camera)
        var skied = perf_counter_ns()
        var image = self._resolve(frame, sky, shadowing)
        var resolved = perf_counter_ns()
        self.timings = [
            _ms(mapped - began),
            _ms(gathered - mapped),
            _ms(lit - gathered),
            _ms(set_up - lit),
            _ms(binned - set_up),
            _ms(rastered - binned),
            _ms(skied - rastered),
            _ms(resolved - skied),
        ]
        return image^

    def set_moving(mut self, scene: Scene, roots: List[NodeId]) raises:
        """Say which nodes move, so their meshes cast into the moving map.

        Each root's whole subtree moves: the meshes the scene holds now
        that hang from it. The still map is drawn again.

        Args:
            scene: The scene.
            roots: The roots of the moving subtrees, such as the people
                and the animals.

        Raises:
            Error: If a root is not a node of the scene.
        """
        self._moving = List[Bool](length=scene.count(), fill=False)
        for root in roots:
            # A root's descendants begin with the root itself.
            for node in scene.descendants(root):  # pragma: no branch
                self._moving[node.value] = True
        self._moving_meshes = List[Int]()
        for index in range(len(scene.meshes)):
            if self._moves(scene.meshes[index].node):
                self._moving_meshes.append(index)
        self._moving_skins = List[Int]()
        for index in range(len(scene.skinned_meshes)):
            if self._moves(scene.skinned_meshes[index].node):
                self._moving_skins.append(index)
        self._still_map.ready = False

    def set_shadows(mut self, mode: ShadowMode, size: Int) raises:
        """Choose how the sun's shadows are drawn, and the still map's size.

        Args:
            mode: How the shadows are drawn.
            size: The still map's texels on a side, from 64 to 8,192.

        Raises:
            Error: If the mode is not one of the four or the size is out of
                range.
        """
        if not mode.is_valid():
            raise Error("A shadow mode must be one of the four")
        if size < 64 or size > 8192:
            raise Error(
                "A shadow map must have from 64 to 8,192 texels on a side"
            )
        self.shadows = mode
        self.shadow_size = size
        self._still_map.ready = False

    def refresh_shadows(mut self):
        """Draw the still shadow map again at the next frame, as after the
        still casters changed."""
        self._still_map.ready = False

    def _moves(self, node: NodeId) -> Bool:
        """Return whether a node was named as moving."""
        return node.value < len(self._moving) and self._moving[node.value]

    def _vertex_total(self, draws: List[_Draw]) raises -> Int:
        """Return how many vertices the draws light."""
        var total = 0
        for d in draws:
            total = max(
                total,
                d.first
                + len(self._shapes[d.shape].value().parts[d.part].vertices)
                * (2 if d.lit_twice else 1),
            )
        return total

    def _draw_map(
        mut self,
        scene: Scene,
        assets: Assets,
        frame: _Frame,
        moving: Bool,
        center: Vector3,
        reach: Float32,
    ) raises:
        """Draw one of the sun's depth maps: the still casters' or the
        moving casters'."""
        var made = _sun_matrices(frame.sun_toward, center, reach)
        var pass_frame = frame
        pass_frame.view_projection = made[1]
        pass_frame.view = made[0]
        pass_frame.depth_only = True
        pass_frame.cull = False
        var size = self._moving_map.size if moving else self._still_map.size
        pass_frame.width = size
        pass_frame.height = size
        var draws = self._gather(
            scene, assets, made[0], made[1], 0, made[3], 2 if moving else 1
        )
        self._light_vertices(draws, assets, scene, pass_frame)
        self._setup(draws, pass_frame)
        var bins = self._bin(size, size)
        if moving:
            self._moving_map.view = made[0]
            self._moving_map.clip = made[1]
            self._moving_map.per_meter = made[2]
            self._raster(
                bins,
                size,
                size,
                self._moving_map.stride,
                self._moving_map.depth.unsafe_ptr().unsafe_origin_cast[
                    MutAnyOrigin
                ](),
                self._moving_map.ids.unsafe_ptr().unsafe_origin_cast[
                    MutAnyOrigin
                ](),
            )
            self._moving_map.ready = True
        else:
            self._still_map.view = made[0]
            self._still_map.clip = made[1]
            self._still_map.per_meter = made[2]
            self._raster(
                bins,
                size,
                size,
                self._still_map.stride,
                self._still_map.depth.unsafe_ptr().unsafe_origin_cast[
                    MutAnyOrigin
                ](),
                self._still_map.ids.unsafe_ptr().unsafe_origin_cast[
                    MutAnyOrigin
                ](),
            )
            self._still_map.ready = True

    def _frame(
        self,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
        time: Duration,
    ) raises -> _Frame:
        """Read the camera, the lights and the fog."""
        var view = camera.view_matrix()
        var vp = camera.projection_matrix()
        vp.multiply(view)
        var lights = Lighting(scene)
        var ambient = _rgb(lights.ambient)
        var sky = SIMD[DType.float32, 4](0)
        var ground = SIMD[DType.float32, 4](0)
        var up = SIMD[DType.float32, 4](0, 1, 0, 0)
        var has_sky = len(lights.skies) > 0
        if len(lights.skies) > 1:
            raise Error("The game renderer draws at most one hemisphere light")
        if has_sky:
            sky = _rgb(lights.skies[0])
            ground = _rgb(lights.grounds[0])
            ref d = lights.sky_directions[0]
            up = SIMD[DType.float32, 4](d.x, d.y, d.z, 0)
        var sun = SIMD[DType.float32, 4](0)
        var toward = SIMD[DType.float32, 4](0, 1, 0, 0)
        var has_sun = False
        for index in range(len(lights.directions)):
            ref d = lights.directions[index]
            if has_sun:
                # A cascade of the sun already counted adds nothing: the
                # cascades share one sun between them.
                var same = d.x * toward[0] + d.y * toward[1] + d.z * toward[2]
                if lights.cascades[index].is_cascade() and same > 0.9999:
                    continue
                raise Error("The game renderer draws one directional light")
            toward = SIMD[DType.float32, 4](d.x, d.y, d.z, 0)
            sun = _rgb(lights.radiances[index])
            has_sun = True
        if len(lights.positions) > 0 or len(lights.spot_positions) > 0:
            raise Error("The game renderer draws no point or spot light")
        var fog = scene.fog.kind == EXP2_FOG
        if not fog and scene.fog.kind != NO_FOG:
            raise Error("The game renderer draws only exponential fog")
        var fog_color = _rgb(FloatColor(srgb=scene.fog.color))
        var eye = camera.position
        # Every light that arrives is scaled as `Lighting` scales it: by
        # three.js's `RECIPROCAL_PI`, from its Lambert BRDF.
        var scale = lights.scale
        return _Frame(
            vp,
            view,
            SIMD[DType.float32, 4](eye.x, eye.y, eye.z, 0),
            self.width,
            self.height,
            ambient * scale,
            up,
            sky * scale,
            ground * scale,
            has_sky,
            toward,
            sun * scale,
            has_sun,
            fog,
            scene.fog.density.to(PER_METER),
            fog_color,
            time.to(SECOND),
            False,
            True,
        )

    def _shape(mut self, assets: Assets, id: GeometryId) raises -> Int:
        """Return the shape of a geometry, reading it if it is new or was
        replaced."""
        while len(self._shapes) <= id.value:
            self._shapes.append(None)
        var generation = assets.geometries.generation(id)
        if (
            not self._shapes[id.value]
            or self._shapes[id.value].value().generation != generation
        ):
            self._shapes[id.value] = _Shape(
                assets.geometries.get(id), generation
            )
        return id.value

    def _look(self, assets: Assets, id: MaterialId) raises -> Tuple[_Look, Int]:
        """Return how a material is lit, and its map's texture id."""
        ref m = assets.materials.get(id)
        var kind = m.kind
        if not (
            kind == BASIC
            or kind == LAMBERT
            or kind == PHONG
            or kind == STANDARD
            or kind == PHYSICAL
        ):
            raise Error(
                "The game renderer cannot draw a material of kind ", kind.value
            )
        var two_sided = False
        if m.nodes.value >= 0:
            if m.nodes.value not in self._shadings:
                raise Error(
                    "The game renderer has no shading for node program ",
                    m.nodes.value,
                )
            two_sided = self._shadings[m.nodes.value].two_sided_light
        var color = _rgb(FloatColor(srgb=m.color))
        var emissive = _rgb(FloatColor(srgb=m.emissive)) * m.emissive_intensity
        var specular = _rgb(FloatColor(srgb=m.specular))
        var map_color = SIMD[DType.float32, 4](1)
        return (
            _Look(
                kind == BASIC,
                kind == PHONG,
                color,
                emissive,
                specular,
                m.shininess,
                m.vertex_colors,
                m.side.value,
                two_sided,
                map_color,
                m.map != NO_TEXTURE,
            ),
            m.map.value,
        )

    def _gather(
        mut self,
        scene: Scene,
        assets: Assets,
        view: Matrix4,
        clip: Matrix4,
        near: Float32,
        far: Float32,
        kind: Int,
    ) raises -> List[_Draw]:
        """List the parts of every shown mesh in a view: for the frame when
        `kind` is 0, the still casters for 1, and the moving casters for 2.
        """
        var frustum = Frustum.from_camera(clip, view, near, far)
        var draws = List[_Draw]()
        var first = 0
        var meshes = self._moving_meshes.copy() if kind == 2 else List[Int]()
        if kind != 2:
            for index in range(len(scene.meshes)):
                meshes.append(index)
        var skins = self._moving_skins.copy() if kind == 2 else List[Int]()
        if kind != 2:
            for index in range(len(scene.skinned_meshes)):
                skins.append(index)
        for index in meshes:
            ref mesh = scene.meshes[index]
            if kind > 0 and (
                not mesh.cast_shadow or self._moves(mesh.node) != (kind == 2)
            ):
                continue
            if not scene.is_shown(mesh.node):
                continue
            var world = scene.world_matrix(mesh.node)
            var shape = self._shape(assets, mesh.geometry)
            if not _seen(self._shapes[shape].value(), world, frustum):
                continue
            first = self._add_parts(
                draws,
                assets,
                shape,
                world,
                mesh.materials,
                mesh.material,
                -1,
                mesh.geometry,
                first,
                mesh.receive_shadow,
            )
        for index in skins:
            ref skinned = scene.skinned_meshes[index]
            if kind > 0 and (
                not skinned.cast_shadow
                or self._moves(skinned.node) != (kind == 2)
            ):
                continue
            if not scene.is_shown(skinned.node):
                continue
            var world = scene.world_matrix(skinned.node)
            var shape = self._shape(assets, skinned.geometry)
            first = self._add_parts(
                draws,
                assets,
                shape,
                world,
                List[MaterialId](),
                skinned.material,
                index,
                skinned.geometry,
                first,
                skinned.receive_shadow,
            )
        if len(self._vertices) < first * STRIDE:
            _grow(self._vertices, first * STRIDE)
        return draws^

    def _add_parts(
        mut self,
        mut draws: List[_Draw],
        assets: Assets,
        shape: Int,
        world: Matrix4,
        materials: List[MaterialId],
        material: MaterialId,
        skinned: Int,
        geometry: GeometryId,
        start: Int,
        receives: Bool,
    ) raises -> Int:
        """Add a mesh's parts to the frame, and return where the next
        mesh's vertices start."""
        var first = start
        var parts = len(self._shapes[shape].value().parts)
        for p in range(parts):  # pragma: no branch
            var slot = self._shapes[shape].value().parts[p].slot
            var id = material
            if len(materials) > 0:
                # A negative slot wraps round to a huge one.
                if UInt(slot) >= UInt(len(materials)):
                    continue
                id = materials[slot]
            if id.value not in self._looks:
                self._looks[id.value] = self._look(assets, id)
            var looked = self._looks[id.value]
            var look = looked[0]
            var sunlit = -1
            var skylit = -1
            var sway = Optional[SwayMotion](None)
            ref m = assets.materials.get(id)
            if m.nodes.value >= 0:
                ref shading = self._shadings[m.nodes.value]
                sway = shading.sway
                if shading.sunlit != "":
                    sunlit = (
                        self._shapes[shape]
                        .value()
                        .baked_values(
                            assets.geometries.get(geometry), shading.sunlit
                        )
                    )
                if shading.skylit != "":
                    skylit = (
                        self._shapes[shape]
                        .value()
                        .baked_values(
                            assets.geometries.get(geometry), shading.skylit
                        )
                    )
            var twice = (
                look.side == DOUBLE_SIDE.value and not look.two_sided_light
            )
            var count = len(self._shapes[shape].value().parts[p].vertices)
            var pixel = -1
            var texels = Float32(1)
            # A map read at each pixel scales all the light of the
            # vertices, so only a material whose light is all its albedo's
            # reads it there.
            var glows = look.phong or look.emissive.reduce_max() > 0
            if self.pixel_maps and look.has_map and not glows:
                ref texture = assets.textures.get(TextureId(looked[1]))
                pixel = self._pixel.slot(texture, looked[1])
                texels = sqrt(
                    Float32(max(1, texture.width) * max(1, texture.height))
                )
            draws.append(
                _Draw(
                    shape,
                    p,
                    world,
                    look,
                    sunlit,
                    skylit,
                    sway,
                    first,
                    twice,
                    skinned,
                    geometry,
                    looked[1],
                    receives,
                    pixel,
                    texels,
                )
            )
            first += count * (2 if twice else 1)
        return first

    def _light_vertices(
        mut self,
        draws: List[_Draw],
        assets: Assets,
        scene: Scene,
        frame: _Frame,
    ) raises:
        """Place and light every drawn vertex, in tasks of `CHUNK`."""
        # Skinning needs the scene and the stores, so the carriers are found
        # here, before the tasks.
        # The first entry of each list is a placeholder, for the draws that
        # have none.
        var carrier_of = List[Int]()
        for d in draws:
            if d.skinned < 0:
                carrier_of.append(-1)
                continue
            self._shapes[d.shape].value().read_skin(
                assets.geometries.get(d.geometry)
            )
            if d.skinned not in self._skin_of:
                self._skins.append(_bone_rows(skin_pose(scene, d.skinned)))
                self._skin_of[d.skinned] = len(self._skins) - 2
            var bones = len(self._skins[self._skin_of[d.skinned] + 1]) // 12
            if self._shapes[d.shape].value().parts[d.part].top_bone >= bones:
                raise Error("A skin names a bone the skeleton does not have")
            carrier_of.append(self._skin_of[d.skinned])
        ref carriers = self._skins
        # The map's color at each vertex is read here too.
        var mapped: List[List[Float32]] = [[Float32(1), 1, 1]]
        var map_of = List[Int]()
        for d in draws:
            if not d.look.has_map or d.pixel >= 0:
                map_of.append(-1)
                continue
            ref shape = self._shapes[d.shape].value()
            ref part = shape.parts[d.part]
            ref texture = assets.textures.get(TextureId(d.map))
            var colors = List[Float32](length=len(part.vertices) * 3, fill=1)
            for k in range(len(part.vertices)):
                var vertex = Int(part.vertices[k])
                var c = texture.sample(shape.u[vertex], shape.v[vertex])
                colors[k * 3] = c.r
                colors[k * 3 + 1] = c.g
                colors[k * 3 + 2] = c.b
            mapped.append(colors^)
            map_of.append(len(mapped) - 2)
        var pieces = List[Tuple[Int, Int, Int]]()
        for di in range(len(draws)):
            var count = len(
                self._shapes[draws[di].shape]
                .value()
                .parts[draws[di].part]
                .vertices
            )
            var begin = 0
            while begin < count:
                var end = min(count, begin + CHUNK)
                pieces.append((di, begin, end))
                begin = end
        var group = TaskGroup()
        var dest = self._vertices.unsafe_ptr().unsafe_origin_cast[
            MutAnyOrigin
        ]()
        var first = 0
        while first < len(pieces):
            # A task takes pieces until it has about `CHUNK` vertices, so
            # many small draws share a task.
            var past = first
            var work = 0
            while past < len(pieces) and (past == first or work < CHUNK):
                work += pieces[past][2] - pieces[past][1]
                past += 1
            group.create_task(
                _light_batch(
                    Pointer(to=self._shapes)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=draws)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=frame)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    dest,
                    Pointer(to=carriers)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=carrier_of)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=mapped)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=map_of)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=pieces)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    first,
                    past,
                )
            )
            first = past
        group.wait()
        _ = len(carriers)
        _ = len(mapped)
        _ = len(draws)
        _ = len(pieces)
        _ = len(carrier_of)
        _ = len(map_of)
        _ = frame.width

    def _setup(mut self, draws: List[_Draw], frame: _Frame) raises:
        """Clip, cull and set up every triangle, and keep its planes."""
        var jobs = List[Tuple[Int, Int, Int]]()
        var room = 0
        for di in range(len(draws)):
            var count = (
                len(
                    self._shapes[draws[di].shape]
                    .value()
                    .parts[draws[di].part]
                    .triangles
                )
                // 3
            )
            var begin = 0
            while begin < count:
                var end = min(count, begin + CHUNK)
                jobs.append((di, begin, end))
                begin = end
        while len(self._batches) < len(jobs):
            self._batches.append(_Batch())
        for j in range(len(jobs)):
            ref batch = self._batches[j]
            batch.first = room
            batch.count = 0
            batch.extra.clear()
            room += (jobs[j][2] - jobs[j][1]) * 2
        if len(self._planes) < room * PLANE:
            _grow(self._planes, room * PLANE)
            _grow(self._corners, room * 3)
            _grow(self._bounds, room * 4)
        var group = TaskGroup()
        var vertices = self._vertices.unsafe_ptr().unsafe_origin_cast[
            MutAnyOrigin
        ]()
        var planes = self._planes.unsafe_ptr().unsafe_origin_cast[
            MutAnyOrigin
        ]()
        var corners = self._corners.unsafe_ptr().unsafe_origin_cast[
            MutAnyOrigin
        ]()
        var bounds = self._bounds.unsafe_ptr().unsafe_origin_cast[
            MutAnyOrigin
        ]()
        for j in range(len(jobs)):
            var di = jobs[j][0]
            group.create_task(
                _setup_task(
                    Pointer(to=self._shapes[draws[di].shape].value())
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=draws[di])
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=frame)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    vertices,
                    Pointer(to=self._batches[j]).unsafe_origin_cast[
                        MutAnyOrigin
                    ](),
                    planes,
                    corners,
                    bounds,
                    jobs[j][1],
                    jobs[j][2],
                )
            )
        group.wait()
        _ = len(draws)
        _ = len(jobs)
        _ = frame.width
        # The clipped vertices go after the drawn ones, and each batch's
        # corners that name them are renamed.
        var base = 0
        for d in draws:
            base = max(
                base,
                d.first
                + len(self._shapes[d.shape].value().parts[d.part].vertices)
                * (2 if d.lit_twice else 1),
            )
        var extra = 0
        var triangles = 0
        for j in range(len(jobs)):
            extra += len(self._batches[j].extra) // STRIDE
            triangles += self._batches[j].count
        if len(self._vertices) < (base + extra) * STRIDE:
            _grow(self._vertices, (base + extra) * STRIDE)
        var verts = self._vertices.unsafe_ptr()
        var next_extra = base
        for j in range(len(jobs)):
            ref batch = self._batches[j]
            var made = len(batch.extra)
            if made == 0:
                continue
            unsafe_memcpy(
                dest=verts.unsafe_offset(next_extra * STRIDE),
                src=batch.extra.unsafe_ptr(),
                count=made,
            )
            var named = self._corners.unsafe_ptr().unsafe_offset(
                batch.first * 3
            )
            var shift = Int32(next_extra) - 1
            for k in range(batch.count * 3):
                var c = named[unsafe_offset=k]
                if c < 0:
                    named[unsafe_offset=k] = shift - c
            next_extra += made // STRIDE
        self._jobs = len(jobs)
        self.triangles = triangles

    def _bin(self, width: Int, height: Int) raises -> List[List[Int32]]:
        """List each tile's triangles, in order, for an image of a size."""
        var tiles_x = (width + TILE - 1) // TILE
        var tiles_y = (height + TILE - 1) // TILE
        var bins = List[List[Int32]](
            length=tiles_x * tiles_y, fill=List[Int32]()
        )
        var bounds = self._bounds.unsafe_ptr()
        for j in range(self._jobs):
            var first = self._batches[j].first
            for t in range(first, first + self._batches[j].count):
                var bx0 = Int(bounds[unsafe_offset=t * 4]) // TILE
                var by0 = Int(bounds[unsafe_offset=t * 4 + 1]) // TILE
                var bx1 = Int(bounds[unsafe_offset=t * 4 + 2]) // TILE
                var by1 = Int(bounds[unsafe_offset=t * 4 + 3]) // TILE
                for by in range(by0, by1 + 1):  # pragma: no branch
                    for bx in range(bx0, bx1 + 1):  # pragma: no branch
                        bins[by * tiles_x + bx].append(Int32(t))
        return bins^

    def _raster(
        mut self,
        bins: List[List[Int32]],
        width: Int,
        height: Int,
        stride: Int,
        depth: MutPointer[Float32, MutAnyOrigin],
        ids: MutPointer[Int32, MutAnyOrigin],
    ) raises:
        """Fill a visibility buffer of a size, whose rows hold `stride`
        pixels, a task a tile."""
        var tiles_x = (width + TILE - 1) // TILE
        var group = TaskGroup()
        for tile in range(len(bins)):  # pragma: no branch
            group.create_task(
                _raster_task(
                    Pointer(to=bins[tile])
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self._planes.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self._bounds.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    depth,
                    ids,
                    tile,
                    tiles_x,
                    stride,
                )
            )
        group.wait()
        _ = len(bins)

    def _sky(
        self, scene: Scene, assets: Assets, camera: PerspectiveCamera
    ) raises -> List[Float32]:
        """Sample the background on a grid of `sky_step` pixels, linear."""
        var step = max(1, self.sky_step)
        var columns = (self.width + step - 1) // step + 1
        var rows = (self.height + step - 1) // step + 1
        var out = List[Float32](length=columns * rows * 3, fill=0)
        ref background = scene.background
        if background.kind == COLOR_BACKGROUND:
            var c = FloatColor(srgb=background.color)
            for i in range(columns * rows):  # pragma: no branch
                out[i * 3] = c.r
                out[i * 3 + 1] = c.g
                out[i * 3 + 2] = c.b
            return out^
        if background.kind != CUBE_BACKGROUND:
            return out^
        ref cube = assets.cube_textures.get(background.cube)
        var inverse = camera.projection_matrix()
        var view = camera.view_matrix()
        inverse.multiply(view)
        inverse.invert()
        # The far plane's points are an affine map of the NDC, so a
        # sample's direction is mixed from those through three corners.
        var eye = camera.position
        var d00 = inverse.transform_point(Vector3(-1, 1, 1)) - eye
        var across = inverse.transform_point(Vector3(1, 1, 1)) - eye - d00
        var down = inverse.transform_point(Vector3(-1, -1, 1)) - eye - d00
        # Each task takes a band of rows: there are two rows or more.
        var tasks = min(rows, SKY_TASKS)
        var group = TaskGroup()
        for t in range(tasks):  # pragma: no branch
            group.create_task(
                _sky_task(
                    Pointer(to=cube)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    d00,
                    across,
                    down,
                    scene.background_intensity,
                    columns,
                    step,
                    self.width,
                    self.height,
                    t * rows // tasks,
                    (t + 1) * rows // tasks,
                )
            )
        group.wait()
        return out^

    def _resolve(
        self, frame: _Frame, sky: List[Float32], shadowing: Bool
    ) raises -> Framebuffer:
        """Shade each pixel once, tone map and encode it."""
        # The tiles write every pixel and its depth, so neither list is
        # filled first.
        var pixels = List[UInt8]()
        pixels.resize(unsafe_uninit_length=self.width * self.height * 4)
        var depth = List[Float32]()
        depth.resize(unsafe_uninit_length=self.width * self.height)
        var tiles_x = (self.width + TILE - 1) // TILE
        var tiles_y = (self.height + TILE - 1) // TILE
        # When the sun casts, `render` has drawn the still map, and the
        # moving map unless the mode is `STILL_SHADOWS`.
        var moving = shadowing and self.shadows != STILL_SHADOWS
        var group = TaskGroup()
        for tile in range(tiles_x * tiles_y):  # pragma: no branch
            group.create_task(
                _resolve_task(
                    self._ids.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self._depth.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self._planes.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self._corners.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    self._vertices.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    sky.unsafe_ptr()
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    Pointer(to=self._encode)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    depth.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    tile,
                    tiles_x,
                    self.width,
                    self.height,
                    self._stride,
                    max(1, self.sky_step),
                    self.exposure,
                    Pointer(to=self._still_map)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    shadowing,
                    Pointer(to=self._moving_map)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    moving,
                    self.shadow_bias,
                    Pointer(to=self._pixel)
                    .unsafe_mut_cast[False]()
                    .unsafe_origin_cast[ImmutAnyOrigin](),
                    frame.fog,
                    frame.fog_color,
                )
            )
        group.wait()
        _ = len(sky)
        return Framebuffer(self.width, self.height, pixels^, depth^)


@always_inline
def _blend(
    vertices: Pointer[Float32, ImmutAnyOrigin],
    va: SIMD[DType.int64, GAME_LANES],
    vb: SIMD[DType.int64, GAME_LANES],
    vc: SIMD[DType.int64, GAME_LANES],
    slot: Int,
    q0: F,
    q1: F,
    q2: F,
    one: Bool,
) -> F:
    """Return one of the three corners' floats, mixed by the pixels'
    shares. With `one`, every lane names the same corners."""
    return (
        q0 * _pick(vertices, va, slot, one)
        + q1 * _pick(vertices, vb, slot, one)
        + q2 * _pick(vertices, vc, slot, one)
    )


@always_inline
def _pick[
    dtype: DType
](
    values: Pointer[Scalar[dtype], ImmutAnyOrigin],
    at: SIMD[DType.int64, GAME_LANES],
    slot: Int,
    one: Bool,
) -> SIMD[dtype, GAME_LANES]:
    """Return each lane's value `slot` past its index in `at`. With `one`,
    every lane holds the same index, so one load serves them all."""
    if one:
        return SIMD[dtype, GAME_LANES](values[unsafe_offset=Int(at[0]) + slot])
    return values.unsafe_gather(at + Int64(slot))


@always_inline
def _mix4(
    grid: Pointer[Float32, ImmutAnyOrigin],
    s00: SIMD[DType.int64, GAME_LANES],
    s10: SIMD[DType.int64, GAME_LANES],
    s01: SIMD[DType.int64, GAME_LANES],
    s11: SIMD[DType.int64, GAME_LANES],
    channel: Int,
    fx: F,
    fy: F,
) -> F:
    """Return one channel mixed from four grid samples."""
    var a = grid.unsafe_gather(s00 + Int64(channel))
    var b = grid.unsafe_gather(s10 + Int64(channel))
    var c = grid.unsafe_gather(s01 + Int64(channel))
    var d = grid.unsafe_gather(s11 + Int64(channel))
    var top = a + (b - a) * fx
    var bottom = c + (d - c) * fx
    return top + (bottom - top) * fy


@always_inline
def _encode_bytes(
    value: F,
    buckets: Pointer[UInt8, ImmutAnyOrigin],
    thresholds: Pointer[Float32, ImmutAnyOrigin],
) -> I:
    """Return `SrgbBytes.byte` of each lane: the byte at the value's
    bucket, and one more if the value reaches that byte's threshold."""
    var high = value.ge(1)
    var positive = value.gt(0)
    var clamped = positive.select(min(value, F(0.99999994)), F(0))
    var bucket = (clamped * Float32(SrgbBytes.BUCKETS)).cast[DType.int64]()
    var reached = buckets.unsafe_gather(bucket).cast[DType.int32]()
    var limit = min(reached, I(254)).cast[DType.int64]()
    var reaches = reached.lt(255) & thresholds.unsafe_gather(limit).le(clamped)
    reached = reaches.select(reached + 1, reached)
    reached = positive.select(reached, I(0))
    return high.select(I(255), reached)


@always_inline
def _sun_shadows(map: _SunMap, wx: F, wy: F, wz: F, bias: Float32) -> F:
    """Return how much of the sun reaches each lane, by a 2 by 2
    comparison of one depth map: 1 in full sun, 0 in full shadow, and 1
    outside the map."""
    ref e = map.clip.elements
    var cx = wx * e[0] + wy * e[4] + wz * e[8] + e[12]
    var cy = wx * e[1] + wy * e[5] + wz * e[9] + e[13]
    var cz = wx * e[2] + wy * e[6] + wz * e[10] + e[14]
    var on = cx.gt(-1) & cx.lt(1) & cy.gt(-1) & cy.lt(1)
    var size = Float32(map.size)
    var tx = (cx * 0.5 + 0.5) * size - 0.5
    var ty = (0.5 - cy * 0.5) * size - 0.5
    var x0f = floor(tx)
    var y0f = floor(ty)
    var fx = tx - x0f
    var fy = ty - y0f
    var x0 = on.select(x0f, F(0)).cast[DType.int32]()
    var y0 = on.select(y0f, F(0)).cast[DType.int32]()
    var reach = cz - bias * map.per_meter
    var texels = map.depth.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var last = Int32(map.size - 1)
    var side = Int32(map.stride)
    var x1 = x0 + 1
    var y1 = y0 + 1
    var l00 = _texel_lit(texels, x0, y0, last, side, on, reach)
    var l10 = _texel_lit(texels, x1, y0, last, side, on, reach)
    var l01 = _texel_lit(texels, x0, y1, last, side, on, reach)
    var l11 = _texel_lit(texels, x1, y1, last, side, on, reach)
    var top = l00 + (l10 - l00) * fx
    var bottom = l01 + (l11 - l01) * fx
    return on.select(top + (bottom - top) * fy, F(1))


@always_inline
def _texel_lit(
    texels: Pointer[Float32, ImmutAnyOrigin],
    x: I,
    y: I,
    last: Int32,
    side: Int32,
    on: SIMD[DType.bool, GAME_LANES],
    reach: F,
) -> F:
    """Return 0 for each lane whose texel is nearer the sun than `reach`,
    and 1 for the others and for a texel off the map. A row of the map
    holds `side` texels."""
    var valid = on & x.ge(0) & x.le(last) & y.ge(0) & y.le(last)
    var index = (valid.select(y, I(0)) * side + valid.select(x, I(0))).cast[
        DType.int64
    ]()
    var depth = texels.unsafe_gather(index)
    return (valid & depth.lt(reach)).select(F(0), F(1))


def _padded(count: Int) -> Int:
    """Return a count rounded up to whole tiles."""
    return (count + TILE - 1) // TILE * TILE


def _grow[
    T: Copyable & Defaultable & Deinitable
](mut values: List[T], length: Int):
    """Lengthen a list that is shorter than `length` to at least `length`,
    by half again at least, so a frame that needs a little more than the
    last does not copy it all."""
    values.resize(max(length, len(values) + len(values) // 2), T())


def _ms(nanoseconds: Int) -> Float64:
    """Return nanoseconds as milliseconds."""
    return Float64(nanoseconds) / 1.0e6


def _rgb(c: FloatColor) -> SIMD[DType.float32, 4]:
    """Return a color's red, green and blue as the first three lanes."""
    return SIMD[DType.float32, 4](c.r, c.g, c.b, 0)


def _seen(shape: _Shape, world: Matrix4, frustum: Frustum) -> Bool:
    """Return whether a shape's bounding sphere, placed, is in the view."""
    var center = world.transform_point(shape.center)
    ref e = world.elements
    var sx = sqrt(e[0] * e[0] + e[1] * e[1] + e[2] * e[2])
    var sy = sqrt(e[4] * e[4] + e[5] * e[5] + e[6] * e[6])
    var sz = sqrt(e[8] * e[8] + e[9] * e[9] + e[10] * e[10])
    var scale = max(sx, max(sy, sz))
    return frustum.intersects_sphere(Sphere(center, shape.radius * scale))


struct _Batch(Copyable, Movable):
    """The triangles one setup task kept: a range of the frame's triangle
    arrays, and the vertices its clipping made."""

    # Where its range starts, and how many triangles it holds. Its range
    # has room for twice the triangles it sets up, since clipping splits a
    # triangle into two.
    var first: Int
    var count: Int
    # The vertices clipping made, `STRIDE` floats each. A corner names the
    # batch's own vertex `k` as `-(k + 1)` until the join.
    var extra: List[Float32]

    def __init__(out self):
        """Create an empty batch."""
        self.first = 0
        self.count = 0
        self.extra = List[Float32]()


def _carrier_pointer(
    carriers: List[List[Float32]], index: Int
) -> Pointer[Float32, ImmutAnyOrigin]:
    """Return the first carrier of a skinned draw, or of the placeholder
    list that `carriers` starts with."""
    return (
        carriers[max(index, -1) + 1]
        .unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )


def _map_pointer(
    mapped: List[List[Float32]], index: Int
) -> Pointer[Float32, ImmutAnyOrigin]:
    """Return the map colors of a draw, or of the placeholder list that
    `mapped` starts with."""
    return (
        mapped[max(index, -1) + 1]
        .unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )


def _bone_rows(pose: SkinPose) -> List[Float32]:
    """Return each bone's `bind_inverse * bone * bind`, the top three rows
    of each, twelve floats a bone, and four floats more at the end so the
    last bone can be read sixteen floats at a time.

    A vertex's carrier is the weighted sum of its bones' matrices, so the
    sum of these is the carrier `core.deform.skin_carriers` makes."""
    var out = List[Float32](length=len(pose.palette) * 12 + 4, fill=0)
    # A skeleton has at least one bone.
    for bone in range(len(pose.palette)):  # pragma: no branch
        var carry = Matrix4(copy=pose.bind_inverse)
        carry.multiply(pose.palette[bone])
        carry.multiply(pose.bind)
        ref e = carry.elements
        for row in range(3):
            for column in range(4):
                out[bone * 12 + row * 4 + column] = e[column * 4 + row]
    return out^


@always_inline
def _row(m: Matrix4, r: Int) -> SIMD[DType.float32, 4]:
    """Return a row of a column-major matrix."""
    ref e = m.elements
    return SIMD[DType.float32, 4](e[r], e[4 + r], e[8 + r], e[12 + r])


__async def _light_batch(
    shapes: Pointer[List[Optional[_Shape]], ImmutAnyOrigin],
    draws: Pointer[List[_Draw], ImmutAnyOrigin],
    frame: Pointer[_Frame, ImmutAnyOrigin],
    dest: MutPointer[Float32, MutAnyOrigin],
    carriers: Pointer[List[List[Float32]], ImmutAnyOrigin],
    carrier_of: Pointer[List[Int], ImmutAnyOrigin],
    mapped: Pointer[List[List[Float32]], ImmutAnyOrigin],
    map_of: Pointer[List[Int], ImmutAnyOrigin],
    pieces: Pointer[List[Tuple[Int, Int, Int]], ImmutAnyOrigin],
    first: Int,
    past: Int,
):
    """Place and light pieces `first` to `past` of the frame's draws."""
    for p in range(first, past):  # pragma: no branch
        var piece = pieces[][p]
        var di = piece[0]
        ref d = draws[][di]
        _light_range(
            Pointer(to=shapes[][d.shape].value())
            .unsafe_mut_cast[False]()
            .unsafe_origin_cast[ImmutAnyOrigin](),
            Pointer(to=d)
            .unsafe_mut_cast[False]()
            .unsafe_origin_cast[ImmutAnyOrigin](),
            frame,
            dest,
            _carrier_pointer(carriers[], carrier_of[][di]),
            carrier_of[][di] >= 0,
            _map_pointer(mapped[], map_of[][di]),
            map_of[][di] >= 0,
            piece[1],
            piece[2],
        )


def _light_range(
    shape_ptr: Pointer[_Shape, ImmutAnyOrigin],
    draw_ptr: Pointer[_Draw, ImmutAnyOrigin],
    frame_ptr: Pointer[_Frame, ImmutAnyOrigin],
    dest: MutPointer[Float32, MutAnyOrigin],
    carriers: Pointer[Float32, ImmutAnyOrigin],
    skinned: Bool,
    mapped: Pointer[Float32, ImmutAnyOrigin],
    has_map: Bool,
    begin: Int,
    end: Int,
):
    """Place and light vertices `begin` to `end` of one draw."""
    ref shape = shape_ptr[]
    ref d = draw_ptr[]
    ref fr = frame_ptr[]
    ref part = shape.parts[d.part]
    var count = len(part.vertices)
    var world = d.world
    var mvp = fr.view_projection
    mvp.multiply(world)
    var mv = fr.view
    mv.multiply(world)
    var normal_matrix = world
    try:
        normal_matrix = world.normal_matrix()
    except:
        pass
    var w0 = _row(world, 0)
    var w1 = _row(world, 1)
    var w2 = _row(world, 2)
    var c0 = _row(mvp, 0)
    var c1 = _row(mvp, 1)
    var c2 = _row(mvp, 2)
    var c3 = _row(mvp, 3)
    var v2 = _row(mv, 2)
    var n0 = _row(normal_matrix, 0)
    var n1 = _row(normal_matrix, 1)
    var n2 = _row(normal_matrix, 2)
    var verts = part.vertices.unsafe_ptr()
    var px = part.px.unsafe_ptr()
    var py = part.py.unsafe_ptr()
    var pz = part.pz.unsafe_ptr()
    var nxs = part.nx.unsafe_ptr()
    var nys = part.ny.unsafe_ptr()
    var nzs = part.nz.unsafe_ptr()
    var crs = part.cr.unsafe_ptr()
    var cgs = part.cg.unsafe_ptr()
    var cbs = part.cb.unsafe_ptr()
    var sun_values = px
    var sky_values = px
    if d.sunlit >= 0:
        sun_values = part.baked[d.sunlit].unsafe_ptr()
    if d.skylit >= 0:
        sky_values = part.baked[d.skylit].unsafe_ptr()
    ref look = d.look
    var pixel = d.pixel >= 0
    var k = begin
    while k < end:
        var lanes = min(GAME_LANES, end - k)
        # The part's arrays are padded to whole runs of lanes, so a run
        # past the end reads zeros.
        var x = px.unsafe_load[width=GAME_LANES](k)
        var y = py.unsafe_load[width=GAME_LANES](k)
        var z = pz.unsafe_load[width=GAME_LANES](k)
        var nx = nxs.unsafe_load[width=GAME_LANES](k)
        var ny = nys.unsafe_load[width=GAME_LANES](k)
        var nz = nzs.unsafe_load[width=GAME_LANES](k)
        var r = F(1)
        var g = F(1)
        var b = F(1)
        if look.vertex_colors:
            r = crs.unsafe_load[width=GAME_LANES](k)
            g = cgs.unsafe_load[width=GAME_LANES](k)
            b = cbs.unsafe_load[width=GAME_LANES](k)
        var sunlit = F(1)
        var skylit = F(1)
        if d.sunlit >= 0:
            sunlit = sun_values.unsafe_load[width=GAME_LANES](k)
        if d.skylit >= 0:
            skylit = sky_values.unsafe_load[width=GAME_LANES](k)
        if skinned or has_map:
            for lane in range(lanes):  # pragma: no branch
                var src = Int(verts[unsafe_offset=k + lane])
                if skinned:
                    # The weighted sum of the vertex's four bones, as
                    # `core.deform.skin_carriers` makes it.
                    var m = SIMD[DType.float32, 16](0)
                    for slot in range(BONES_PER_VERTEX):  # pragma: no branch
                        var w = part.weights[(k + lane) * 4 + slot]
                        var bone = Int(part.bones[(k + lane) * 4 + slot])
                        m += carriers.unsafe_load[width=16](bone * 12) * w
                    var lx = x[lane]
                    var ly = y[lane]
                    var lz = z[lane]
                    x[lane] = m[0] * lx + m[1] * ly + m[2] * lz + m[3]
                    y[lane] = m[4] * lx + m[5] * ly + m[6] * lz + m[7]
                    z[lane] = m[8] * lx + m[9] * ly + m[10] * lz + m[11]
                    var mx0 = nx[lane]
                    var my0 = ny[lane]
                    var mz0 = nz[lane]
                    nx[lane] = m[0] * mx0 + m[1] * my0 + m[2] * mz0
                    ny[lane] = m[4] * mx0 + m[5] * my0 + m[6] * mz0
                    nz[lane] = m[8] * mx0 + m[9] * my0 + m[10] * mz0
                if has_map:
                    r[lane] *= mapped[unsafe_offset=(k + lane) * 3]
                    g[lane] *= mapped[unsafe_offset=(k + lane) * 3 + 1]
                    b[lane] *= mapped[unsafe_offset=(k + lane) * 3 + 2]
        if d.sway:
            var s = d.sway.value()
            var high = min(F(s.most), max(F(0), y * (1 / s.height)))
            var spread = min(
                F(1), max(F(0), sqrt(x * x + z * z) * (1 / s.spread))
            )
            var weight = (high * high) * (0.35 + spread * 0.65)
            var swing = fast_sin[GAME_LANES](
                fr.time * s.swing_rate
                + (
                    x * s.swing_phase[0]
                    + y * s.swing_phase[1]
                    + z * s.swing_phase[2]
                )
            )
            var flutter = fast_sin[GAME_LANES](
                fr.time * s.flutter_rate
                + (
                    x * s.flutter_phase[0]
                    + y * s.flutter_phase[1]
                    + z * s.flutter_phase[2]
                )
            )
            x = x + (s.along_x * swing) * weight
            y = y + (s.flutter * flutter) * weight
            z = z + (s.along_z * swing) * weight
        # The world position, the clip position and the view depth.
        var wx = x * w0[0] + y * w0[1] + z * w0[2] + w0[3]
        var wy = x * w1[0] + y * w1[1] + z * w1[2] + w1[3]
        var wz = x * w2[0] + y * w2[1] + z * w2[2] + w2[3]
        var cx = x * c0[0] + y * c0[1] + z * c0[2] + c0[3]
        var cy = x * c1[0] + y * c1[1] + z * c1[2] + c1[3]
        var cz = x * c2[0] + y * c2[1] + z * c2[2] + c2[3]
        var cw = x * c3[0] + y * c3[1] + z * c3[2] + c3[3]
        var depth = -(x * v2[0] + y * v2[1] + z * v2[2] + v2[3])
        var mx = nx * n0[0] + ny * n0[1] + nz * n0[2]
        var my = nx * n1[0] + ny * n1[1] + nz * n1[2]
        var mz = nx * n2[0] + ny * n2[1] + nz * n2[2]
        var length = sqrt(mx * mx + my * my + mz * mz)
        var inv = length.gt(0).select(1 / length, F(0))
        mx *= inv
        my *= inv
        mz *= inv
        if fr.depth_only:
            # A shadow map needs only where each vertex is.
            for lane in range(lanes):  # pragma: no branch
                var at = dest.unsafe_offset((d.first + k + lane) * STRIDE)
                at[unsafe_offset=0] = cx[lane]
                at[unsafe_offset=1] = cy[lane]
                at[unsafe_offset=2] = cz[lane]
                at[unsafe_offset=3] = cw[lane]
            k += lanes
            continue
        var albedo_r = r * look.color[0] * look.map_color[0]
        var albedo_g = g * look.color[1] * look.map_color[1]
        var albedo_b = b * look.color[2] * look.map_color[2]
        for face in range(2 if d.lit_twice else 1):  # pragma: no branch
            # A back face, and a `BACK_SIDE` material's front, is lit on
            # the normal turned round, as three.js's `FLIP_SIDED` does.
            var away = (face == 1) != (look.side == BACK_SIDE.value)
            var fx = -mx if away else mx
            var fy = -my if away else my
            var fz = -mz if away else mz
            var ar = F(0)
            var ag = F(0)
            var ab = F(0)
            var sr = F(0)
            var sg = F(0)
            var sb = F(0)
            if look.basic:
                ar = albedo_r
                ag = albedo_g
                ab = albedo_b
            else:
                var ir = F(fr.ambient[0])
                var ig = F(fr.ambient[1])
                var ib = F(fr.ambient[2])
                if fr.has_sky:
                    var share = hemisphere_share[GAME_LANES](
                        fx, fy, fz, fr.sky_up
                    )
                    ir = ir + (
                        fr.ground[0] + (fr.sky[0] - fr.ground[0]) * share
                    )
                    ig = ig + (
                        fr.ground[1] + (fr.sky[1] - fr.ground[1]) * share
                    )
                    ib = ib + (
                        fr.ground[2] + (fr.sky[2] - fr.ground[2]) * share
                    )
                ar = albedo_r * ir * skylit + look.emissive[0]
                ag = albedo_g * ig * skylit + look.emissive[1]
                ab = albedo_b * ib * skylit + look.emissive[2]
                if fr.has_sun:
                    var catch = (
                        lambert[GAME_LANES](fx, fy, fz, fr.sun_toward) * sunlit
                    )
                    sr = albedo_r * fr.sun[0] * catch
                    sg = albedo_g * fr.sun[1] * catch
                    sb = albedo_b * fr.sun[2] * catch
                    if look.phong:
                        var sent = _blinn_phong(
                            fx, fy, fz, wx, wy, wz, fr, look
                        )
                        sr = sr + sent[0] * fr.sun[0] * catch
                        sg = sg + sent[1] * fr.sun[1] * catch
                        sb = sb + sent[2] * fr.sun[2] * catch
            # A map read at each pixel tints the light before the fog
            # veils it, so the resolve veils it there.
            var keep = F(1)
            if fr.fog:
                var veil = exp2_veil[GAME_LANES](fr.fog_density, depth)
                keep = 1 - veil
                if not pixel:
                    ar = ar * keep + fr.fog_color[0] * veil
                    ag = ag * keep + fr.fog_color[1] * veil
                    ab = ab * keep + fr.fog_color[2] * veil
                    sr = sr * keep
                    sg = sg * keep
                    sb = sb * keep
            var base = dest.unsafe_offset((d.first + face * count + k) * STRIDE)
            # A baked sun replaces the shadow map: no lookup.
            var lookup = Float32(-1) if (
                d.sunlit >= 0 or not d.receives
            ) else Float32(0)
            for lane in range(lanes):  # pragma: no branch
                var at = base.unsafe_offset(lane * STRIDE)
                if pixel:
                    # The fog's share kept, for a lookup, or -1 less it,
                    # for none; and the texture coordinates.
                    var src = Int(verts[unsafe_offset=k + lane])
                    at[unsafe_offset=13] = (
                        keep[lane] if lookup == 0 else -1 - keep[lane]
                    )
                    at[unsafe_offset=14] = shape.u[src]
                    at[unsafe_offset=15] = shape.v[src]
                else:
                    at[unsafe_offset=13] = lookup
                at[unsafe_offset=0] = cx[lane]
                at[unsafe_offset=1] = cy[lane]
                at[unsafe_offset=2] = cz[lane]
                at[unsafe_offset=3] = cw[lane]
                at[unsafe_offset=4] = ar[lane]
                at[unsafe_offset=5] = ag[lane]
                at[unsafe_offset=6] = ab[lane]
                at[unsafe_offset=7] = sr[lane]
                at[unsafe_offset=8] = sg[lane]
                at[unsafe_offset=9] = sb[lane]
                at[unsafe_offset=10] = wx[lane]
                at[unsafe_offset=11] = wy[lane]
                at[unsafe_offset=12] = wz[lane]
        k += lanes


@always_inline
def _blinn_phong(
    nx: F,
    ny: F,
    nz: F,
    wx: F,
    wy: F,
    wz: F,
    fr: _Frame,
    look: _Look,
) -> Tuple[F, F, F]:
    """Return three.js's `BRDF_BlinnPhong` for the sun, as
    `lights.lighting.blinn_phong` gives it, on each lane."""
    var ex = fr.eye[0] - wx
    var ey = fr.eye[1] - wy
    var ez = fr.eye[2] - wz
    var el = sqrt(ex * ex + ey * ey + ez * ez)
    var ei = el.gt(0).select(1 / el, F(0))
    ex *= ei
    ey *= ei
    ez *= ei
    var hx = fr.sun_toward[0] + ex
    var hy = fr.sun_toward[1] + ey
    var hz = fr.sun_toward[2] + ez
    var hl = sqrt(hx * hx + hy * hy + hz * hz)
    var hi = hl.gt(0).select(1 / hl, F(0))
    hx *= hi
    hy *= hi
    hz *= hi
    var facing = nx * hx + ny * hy + nz * hz
    var lit = facing.gt(0)
    facing = min(F(1), max(F(1.0e-30), facing))
    var grazing = min(F(1), max(F(0), ex * hx + ey * hy + ez * hz))
    var fresnel = exp2((_FRESNEL_SLOPE * grazing + _FRESNEL_OFFSET) * grazing)
    var keep = 1 - fresnel
    var lobe = (look.shininess * 0.5 + 1) * exp2(look.shininess * log2(facing))
    var scale = lit.select(BLINN_PHONG_G * lobe, F(0))
    return (
        (look.specular[0] * keep + fresnel) * scale,
        (look.specular[1] * keep + fresnel) * scale,
        (look.specular[2] * keep + fresnel) * scale,
    )


@always_inline
def _corner(
    vertices: MutPointer[Float32, MutAnyOrigin],
    batch: MutPointer[_Batch, MutAnyOrigin],
    c: Int32,
) -> MutPointer[Float32, MutAnyOrigin]:
    """Return where a corner's `STRIDE` floats are."""
    if c >= 0:
        return vertices.unsafe_offset(Int(c) * STRIDE)
    return (
        batch[]
        .extra.unsafe_ptr()
        .unsafe_origin_cast[MutAnyOrigin]()
        .unsafe_offset(Int(-c - 1) * STRIDE)
    )


__async def _setup_task(
    shape_ptr: Pointer[_Shape, ImmutAnyOrigin],
    draw_ptr: Pointer[_Draw, ImmutAnyOrigin],
    frame_ptr: Pointer[_Frame, ImmutAnyOrigin],
    vertices: MutPointer[Float32, MutAnyOrigin],
    batch: MutPointer[_Batch, MutAnyOrigin],
    planes: MutPointer[Float32, MutAnyOrigin],
    corners: MutPointer[Int32, MutAnyOrigin],
    bounds: MutPointer[Int32, MutAnyOrigin],
    begin: Int,
    end: Int,
):
    """Clip, cull and set up triangles `begin` to `end` of one draw."""
    ref shape = shape_ptr[]
    ref d = draw_ptr[]
    ref fr = frame_ptr[]
    ref part = shape.parts[d.part]
    var count = len(part.vertices)
    var tris = part.triangles.unsafe_ptr()
    var width = Float32(fr.width)
    var height = Float32(fr.height)
    # A shadow map reads no map.
    var slot = Float32(-1)
    if d.pixel >= 0 and not fr.depth_only:
        slot = Float32(d.pixel)
    for t in range(begin, end):  # pragma: no branch
        var i0 = Int32(d.first) + tris[unsafe_offset=t * 3]
        var i1 = Int32(d.first) + tris[unsafe_offset=t * 3 + 1]
        var i2 = Int32(d.first) + tris[unsafe_offset=t * 3 + 2]
        var a = vertices.unsafe_offset(Int(i0) * STRIDE)
        var b = vertices.unsafe_offset(Int(i1) * STRIDE)
        var c = vertices.unsafe_offset(Int(i2) * STRIDE)
        # The facing, from the homogeneous determinant: positive for a
        # triangle that winds counterclockwise on the screen.
        var det = (
            a[unsafe_offset=0]
            * (
                b[unsafe_offset=1] * c[unsafe_offset=3]
                - c[unsafe_offset=1] * b[unsafe_offset=3]
            )
            - b[unsafe_offset=0]
            * (
                a[unsafe_offset=1] * c[unsafe_offset=3]
                - c[unsafe_offset=1] * a[unsafe_offset=3]
            )
            + c[unsafe_offset=0]
            * (
                a[unsafe_offset=1] * b[unsafe_offset=3]
                - b[unsafe_offset=1] * a[unsafe_offset=3]
            )
        )
        if fr.cull and d.look.side == 0 and not (det > 0):
            continue
        if fr.cull and d.look.side == BACK_SIDE.value and not (det < 0):
            continue
        if d.lit_twice and det < 0 and not fr.depth_only:
            i0 += Int32(count)
            i1 += Int32(count)
            i2 += Int32(count)
        var inside0 = a[unsafe_offset=2] > -a[unsafe_offset=3]
        var inside1 = b[unsafe_offset=2] > -b[unsafe_offset=3]
        var inside2 = c[unsafe_offset=2] > -c[unsafe_offset=3]
        if (
            a[unsafe_offset=2] > a[unsafe_offset=3]
            and b[unsafe_offset=2] > b[unsafe_offset=3]
            and c[unsafe_offset=2] > c[unsafe_offset=3]
        ):
            continue
        if inside0 and inside1 and inside2:
            _emit(
                vertices,
                batch,
                planes,
                corners,
                bounds,
                i0,
                i1,
                i2,
                width,
                height,
                slot,
                d.texels,
            )
            continue
        if not (inside0 or inside1 or inside2):
            continue
        # Clip at the near plane: z = -w.
        var polygon = List[Int32]()
        var ring: List[Int32] = [i0, i1, i2]
        for k in range(3):
            var p = ring[k]
            var q = ring[(k + 1) % 3]
            var pp = _corner(vertices, batch, p)
            var qp = _corner(vertices, batch, q)
            var dp = pp[unsafe_offset=2] + pp[unsafe_offset=3]
            var dq = qp[unsafe_offset=2] + qp[unsafe_offset=3]
            if dp > 0:
                polygon.append(p)
            if (dp > 0) != (dq > 0):
                var s = dp / (dp - dq)
                ref extra = batch[].extra
                var at = len(extra)
                for j in range(STRIDE):  # pragma: no branch
                    extra.append(0)
                var pq = _corner(vertices, batch, p)
                var qq = _corner(vertices, batch, q)
                var outp = extra.unsafe_ptr().unsafe_offset(at)
                for j in range(STRIDE):  # pragma: no branch
                    outp[unsafe_offset=j] = (
                        pq[unsafe_offset=j]
                        + (qq[unsafe_offset=j] - pq[unsafe_offset=j]) * s
                    )
                polygon.append(Int32(-(at // STRIDE) - 1))
        for k in range(1, len(polygon) - 1):  # pragma: no branch
            _emit(
                vertices,
                batch,
                planes,
                corners,
                bounds,
                polygon[0],
                polygon[k],
                polygon[k + 1],
                width,
                height,
                slot,
                d.texels,
            )


def _emit(
    vertices: MutPointer[Float32, MutAnyOrigin],
    batch: MutPointer[_Batch, MutAnyOrigin],
    planes: MutPointer[Float32, MutAnyOrigin],
    corners: MutPointer[Int32, MutAnyOrigin],
    bounds: MutPointer[Int32, MutAnyOrigin],
    i0: Int32,
    i1: Int32,
    i2: Int32,
    width: Float32,
    height: Float32,
    slot: Float32,
    texels: Float32,
):
    """Set up one triangle in front of the near plane, if it covers a
    pixel. A triangle whose map `slot` is not negative reads the level of
    its map, `texels` on a side, at which a texel covers about a pixel."""
    var a = _corner(vertices, batch, i0)
    var b = _corner(vertices, batch, i1)
    var c = _corner(vertices, batch, i2)
    var iw0 = 1 / a[unsafe_offset=3]
    var iw1 = 1 / b[unsafe_offset=3]
    var iw2 = 1 / c[unsafe_offset=3]
    var x0 = (a[unsafe_offset=0] * iw0 * 0.5 + 0.5) * width
    var y0 = (0.5 - a[unsafe_offset=1] * iw0 * 0.5) * height
    var x1 = (b[unsafe_offset=0] * iw1 * 0.5 + 0.5) * width
    var y1 = (0.5 - b[unsafe_offset=1] * iw1 * 0.5) * height
    var x2 = (c[unsafe_offset=0] * iw2 * 0.5 + 0.5) * width
    var y2 = (0.5 - c[unsafe_offset=1] * iw2 * 0.5) * height
    var area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    if not (abs(area) > 1.0e-12):
        return
    var mnx = max(Float32(0), ceil(min(x0, min(x1, x2)) - 0.5))
    var mny = max(Float32(0), ceil(min(y0, min(y1, y2)) - 0.5))
    var mxx = min(width - 1, floor(max(x0, max(x1, x2)) - 0.5))
    var mxy = min(height - 1, floor(max(y0, max(y1, y2)) - 0.5))
    if mnx > mxx or mny > mxy:
        return
    var inv = 1 / area
    var a0 = (y1 - y2) * inv
    var b0 = (x2 - x1) * inv
    var c0 = (x1 * y2 - x2 * y1) * inv
    var a1 = (y2 - y0) * inv
    var b1 = (x0 - x2) * inv
    var c1 = (x2 * y0 - x0 * y2) * inv
    var a2 = (y0 - y1) * inv
    var b2 = (x1 - x0) * inv
    var c2 = (x0 * y1 - x1 * y0) * inv
    var z0 = a[unsafe_offset=2] * iw0
    var z1 = b[unsafe_offset=2] * iw1
    var z2 = c[unsafe_offset=2] * iw2
    ref bt = batch[]
    var n = bt.first + bt.count
    var corner = corners.unsafe_offset(n * 3)
    corner[unsafe_offset=0] = i0
    corner[unsafe_offset=1] = i1
    corner[unsafe_offset=2] = i2
    var plane = planes.unsafe_offset(n * PLANE)
    plane[unsafe_offset=0] = a0
    plane[unsafe_offset=1] = b0
    plane[unsafe_offset=2] = c0
    plane[unsafe_offset=3] = a1
    plane[unsafe_offset=4] = b1
    plane[unsafe_offset=5] = c1
    plane[unsafe_offset=6] = a2
    plane[unsafe_offset=7] = b2
    plane[unsafe_offset=8] = c2
    # The depth plane, from the first corner's depth and the other two's
    # differences from it. The edge terms of a long thin triangle are huge
    # and cancel; weighting them by the small differences, rather than by
    # the depths near one, keeps a distant sliver from coming out nearer
    # than it is.
    var d1 = z1 - z0
    var d2 = z2 - z0
    plane[unsafe_offset=9] = a1 * d1 + a2 * d2
    plane[unsafe_offset=10] = b1 * d1 + b2 * d2
    plane[unsafe_offset=11] = z0 + (c1 * d1 + c2 * d2)
    plane[unsafe_offset=12] = iw0
    plane[unsafe_offset=13] = iw1
    plane[unsafe_offset=14] = iw2
    var code = Float32(-1)
    if slot >= 0:
        var du1 = b[unsafe_offset=14] - a[unsafe_offset=14]
        var dv1 = b[unsafe_offset=15] - a[unsafe_offset=15]
        var du2 = c[unsafe_offset=14] - a[unsafe_offset=14]
        var dv2 = c[unsafe_offset=15] - a[unsafe_offset=15]
        var mapped = abs(du1 * dv2 - du2 * dv1) * texels * texels
        var level = 0.5 * log2(max(mapped, Float32(1.0e-20)) / abs(area))
        code = slot * LEVEL_CODE + min(LEVEL_CODE - 1, max(Float32(0), level))
    plane[unsafe_offset=15] = code
    var bound = bounds.unsafe_offset(n * 4)
    bound[unsafe_offset=0] = Int32(Int(mnx))
    bound[unsafe_offset=1] = Int32(Int(mny))
    bound[unsafe_offset=2] = Int32(Int(mxx))
    bound[unsafe_offset=3] = Int32(Int(mxy))
    bt.count += 1


__async def _raster_task(
    bin_ptr: Pointer[List[Int32], ImmutAnyOrigin],
    planes: Pointer[Float32, ImmutAnyOrigin],
    bounds: Pointer[Int32, ImmutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    ids: MutPointer[Int32, MutAnyOrigin],
    tile: Int,
    tiles_x: Int,
    stride: Int,
):
    """Fill one tile of the visibility buffer, whose rows hold `stride`
    pixels. Each run of sixteen starts at a multiple of sixteen from the
    tile's corner, so it stays inside the tile."""
    var tx0 = (tile % tiles_x) * TILE
    var ty0 = (tile // tiles_x) * TILE
    for y in range(ty0, ty0 + TILE):  # pragma: no branch
        for x in range(tx0, tx0 + TILE, GAME_LANES):  # pragma: no branch
            depth.unsafe_offset(y * stride + x).unsafe_store(F(1))
            ids.unsafe_offset(y * stride + x).unsafe_store(I(NO_TRIANGLE))
    var lanes = F(0)
    for i in range(GAME_LANES):  # pragma: no branch
        lanes[i] = Float32(i)
    ref bin = bin_ptr[]
    var list = bin.unsafe_ptr()
    for k in range(len(bin)):
        var t = Int(list[unsafe_offset=k])
        var bx0 = max(Int(bounds[unsafe_offset=t * 4]), tx0)
        var by0 = max(Int(bounds[unsafe_offset=t * 4 + 1]), ty0)
        var bx1 = min(Int(bounds[unsafe_offset=t * 4 + 2]), tx0 + TILE - 1)
        var by1 = min(Int(bounds[unsafe_offset=t * 4 + 3]), ty0 + TILE - 1)
        var p = planes.unsafe_offset(t * PLANE)
        var a0 = p[unsafe_offset=0]
        var b0 = p[unsafe_offset=1]
        var c0 = p[unsafe_offset=2]
        var a1 = p[unsafe_offset=3]
        var b1 = p[unsafe_offset=4]
        var c1 = p[unsafe_offset=5]
        var a2 = p[unsafe_offset=6]
        var b2 = p[unsafe_offset=7]
        var c2 = p[unsafe_offset=8]
        var za = p[unsafe_offset=9]
        var zb = p[unsafe_offset=10]
        var zc = p[unsafe_offset=11]
        var id = I(Int32(t))
        var start = tx0 + (bx0 - tx0) // GAME_LANES * GAME_LANES
        for y in range(by0, by1 + 1):  # pragma: no branch
            var py = Float32(y) + 0.5
            var r0 = py * b0 + c0
            var r1 = py * b1 + c1
            var r2 = py * b2 + c2
            var rz = py * zb + zc
            var x = start
            while x <= bx1:
                var px = lanes + (Float32(x) + 0.5)
                var e0 = px * a0 + r0
                var e1 = px * a1 + r1
                var e2 = px * a2 + r2
                var inside = (
                    e0.ge(0)
                    & e1.ge(0)
                    & e2.ge(0)
                    & lanes.ge(Float32(bx0 - x))
                    & lanes.le(Float32(bx1 - x))
                )
                if inside.reduce_or():
                    var row = y * stride + x
                    var z = px * za + rz
                    var old = depth.unsafe_offset(row).unsafe_load[
                        width=GAME_LANES
                    ]()
                    var keep = inside & z.le(old) & z.ge(-1)
                    if keep.reduce_or():
                        depth.unsafe_offset(row).unsafe_store(
                            keep.select(z, old)
                        )
                        var was = ids.unsafe_offset(row).unsafe_load[
                            width=GAME_LANES
                        ]()
                        ids.unsafe_offset(row).unsafe_store(
                            keep.select(id, was)
                        )
                x += GAME_LANES


@always_inline
def _pixel_texel(
    maps: _PixelMaps, one: Bool, code: F, u: F, v: F
) -> Tuple[F, F, F]:
    """Return each lane's color of its triangle's map at its texture
    coordinates, bilinear within the level its code names.

    Every lane must name a map: a lane with nothing to read names the
    code 0, as some other lane's map. With `one`, every lane names the
    same code."""
    var slot = floor(code / LEVEL_CODE)
    var wanted = (code - slot * LEVEL_CODE + 0.5).cast[DType.int32]()
    var slots = slot.cast[DType.int64]()
    var firsts = maps.firsts.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var counts = maps.levels.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var wraps_s = maps.wraps_s.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var wraps_t = maps.wraps_t.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var widths = maps.widths.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var heights = maps.heights.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var starts = maps.starts.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var level = min(wanted, _pick(counts, slots, 0, one) - 1)
    var entry = (_pick(firsts, slots, 0, one) + level).cast[DType.int64]()
    var w = _pick(widths, entry, 0, one)
    var h = _pick(heights, entry, 0, one)
    var start = _pick(starts, entry, 0, one)
    var wrap_s = _pick(wraps_s, slots, 0, one)
    var wrap_t = _pick(wraps_t, slots, 0, one)
    var wf = w.cast[DType.float32]()
    var hf = h.cast[DType.float32]()
    # `v` counts up from the bottom row, as `Texture.sample` reads it.
    var tx = u * wf - 0.5
    var ty = v * hf - 0.5
    var x0f = floor(tx)
    var y0f = floor(ty)
    var fx = tx - x0f
    var fy = ty - y0f
    var xs = _wrap_texel(x0f, wf, wrap_s)
    var xs1 = _wrap_texel(x0f + 1, wf, wrap_s)
    var ys = _wrap_texel(y0f, hf, wrap_t)
    var ys1 = _wrap_texel(y0f + 1, hf, wrap_t)
    var row0 = ys * w
    var row1 = ys1 * w
    # `start` counts floats, and a texel is three.
    var i00 = (start + (row0 + xs) * 3).cast[DType.int64]()
    var i10 = (start + (row0 + xs1) * 3).cast[DType.int64]()
    var i01 = (start + (row1 + xs) * 3).cast[DType.int64]()
    var i11 = (start + (row1 + xs1) * 3).cast[DType.int64]()
    var texels = maps.texels.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    return (
        _bilinear(texels, i00, i10, i01, i11, 0, fx, fy),
        _bilinear(texels, i00, i10, i01, i11, 1, fx, fy),
        _bilinear(texels, i00, i10, i01, i11, 2, fx, fy),
    )


@always_inline
def _bilinear(
    texels: Pointer[Float32, ImmutAnyOrigin],
    i00: SIMD[DType.int64, GAME_LANES],
    i10: SIMD[DType.int64, GAME_LANES],
    i01: SIMD[DType.int64, GAME_LANES],
    i11: SIMD[DType.int64, GAME_LANES],
    channel: Int,
    fx: F,
    fy: F,
) -> F:
    """Return one channel mixed from four texels."""
    var a = texels.unsafe_gather(i00 + Int64(channel))
    var b = texels.unsafe_gather(i10 + Int64(channel))
    var c = texels.unsafe_gather(i01 + Int64(channel))
    var d = texels.unsafe_gather(i11 + Int64(channel))
    var top = a + (b - a) * fx
    var bottom = c + (d - c) * fx
    return top + (bottom - top) * fy


@always_inline
def _wrap_texel(x: F, size: F, mode: I) -> I:
    """Return each lane's texel index along one side of `size` texels, as
    `render.texture.wrap_index` returns it for the lane's `Wrap` value:
    wrapped round for a repeating map, folded back on every other tile for
    a mirrored one, and held at the edge for a clamped one."""
    var wrapped = x - size * floor(x / size)
    var folded = x - 2 * size * floor(x / (2 * size))
    var mirrored = folded.ge(size).select(2 * size - 1 - folded, folded)
    var held = min(max(x, F(0)), size - 1)
    var index = mode.eq(Int32(REPEAT.value)).select(
        wrapped, mode.eq(Int32(MIRROR.value)).select(mirrored, held)
    )
    return index.cast[DType.int32]()


__async def _sky_task(
    cube: Pointer[CubeTexture, ImmutAnyOrigin],
    samples: MutPointer[Float32, MutAnyOrigin],
    d00: Vector3,
    across: Vector3,
    down: Vector3,
    scale: Float32,
    columns: Int,
    step: Int,
    width: Int,
    height: Int,
    first: Int,
    past: Int,
):
    """Sample the background cube on rows `first` to `past` of the sky's
    grid. A sample's direction is `d00`, through the window's top left
    corner, plus `across` and `down` times its share of the window."""
    for row in range(first, past):  # pragma: no branch
        var y = min(Float32(row * step), Float32(height)) / Float32(height)
        for column in range(columns):  # pragma: no branch
            var x = min(Float32(column * step), Float32(width)) / Float32(width)
            var c = cube[].sample(d00 + across * x + down * y)
            var i = (row * columns + column) * 3
            samples[unsafe_offset=i] = c.r * scale
            samples[unsafe_offset=i + 1] = c.g * scale
            samples[unsafe_offset=i + 2] = c.b * scale


__async def _resolve_task(
    ids: Pointer[Int32, ImmutAnyOrigin],
    depth: Pointer[Float32, ImmutAnyOrigin],
    planes: Pointer[Float32, ImmutAnyOrigin],
    corners: Pointer[Int32, ImmutAnyOrigin],
    vertices: Pointer[Float32, ImmutAnyOrigin],
    sky: Pointer[Float32, ImmutAnyOrigin],
    encode: Pointer[SrgbBytes, ImmutAnyOrigin],
    pixels: MutPointer[UInt8, MutAnyOrigin],
    out_depth: MutPointer[Float32, MutAnyOrigin],
    tile: Int,
    tiles_x: Int,
    width: Int,
    height: Int,
    stride: Int,
    step: Int,
    exposure: Float32,
    still: Pointer[_SunMap, ImmutAnyOrigin],
    use_still: Bool,
    moving: Pointer[_SunMap, ImmutAnyOrigin],
    use_moving: Bool,
    bias: Float32,
    maps: Pointer[_PixelMaps, ImmutAnyOrigin],
    fog: Bool,
    fog_color: SIMD[DType.float32, 4],
):
    """Shade, tone map and encode one tile, sixteen pixels at a time. A
    row of the visibility buffer holds `stride` pixels."""
    var tx0 = (tile % tiles_x) * TILE
    var ty0 = (tile // tiles_x) * TILE
    var tx1 = min(tx0 + TILE, width)
    var ty1 = min(ty0 + TILE, height)
    var columns = (width + step - 1) // step + 1
    var lane = I(0)
    for k in range(GAME_LANES):  # pragma: no branch
        lane[k] = Int32(k)
    var lane_f = lane.cast[DType.float32]()
    ref bytes = encode[]
    var buckets = bytes.buckets.unsafe_ptr()
    var thresholds = bytes.thresholds.unsafe_ptr()
    var infinite = F(inf[DType.float32]())
    for y in range(ty0, ty1):  # pragma: no branch
        var x = tx0
        var gy = y // step
        var fy = F(Float32(y - gy * step) / Float32(step))
        while x < tx1:
            var lanes = min(GAME_LANES, tx1 - x)
            var at = y * width + x
            var inside = lane.lt(Int32(lanes))
            var t = ids.unsafe_load[width=GAME_LANES](y * stride + x)
            var here = depth.unsafe_load[width=GAME_LANES](y * stride + x)
            var drawn = inside & t.ge(0)
            var r = F(0)
            var g = F(0)
            var b = F(0)
            if not drawn.reduce_and():
                # The sky, mixed from the four grid samples round each pixel.
                # A lane past the image's right edge reads the last
                # column, so no gather goes past the grid.
                var column = min(lane + Int32(x), Int32(width - 1))
                var gx = column / Int32(step)
                var fx = (column - gx * Int32(step)).cast[
                    DType.float32
                ]() / Float32(step)
                var s00 = ((gx + Int32(gy * columns)) * 3).cast[DType.int64]()
                var s10 = s00 + 3
                var s01 = s00 + Int64(columns * 3)
                var s11 = s01 + 3
                r = _mix4(sky, s00, s10, s01, s11, 0, fx, fy)
                g = _mix4(sky, s00, s10, s01, s11, 1, fx, fy)
                b = _mix4(sky, s00, s10, s01, s11, 2, fx, fy)
            if drawn.reduce_or():
                var tri = drawn.select(t, I(0)).cast[DType.int64]()
                # Lanes that all show one triangle read its floats once.
                var one = drawn.reduce_and() and t.eq(t[0]).reduce_and()
                var p = tri * PLANE
                var px = lane_f + (Float32(x) + 0.5)
                var py = F(Float32(y) + 0.5)
                var q0 = (
                    _pick(planes, p, 0, one) * px
                    + _pick(planes, p, 1, one) * py
                    + _pick(planes, p, 2, one)
                ) * _pick(planes, p, 12, one)
                var q1 = (
                    _pick(planes, p, 3, one) * px
                    + _pick(planes, p, 4, one) * py
                    + _pick(planes, p, 5, one)
                ) * _pick(planes, p, 13, one)
                var q2 = (
                    _pick(planes, p, 6, one) * px
                    + _pick(planes, p, 7, one) * py
                    + _pick(planes, p, 8, one)
                ) * _pick(planes, p, 14, one)
                var norm = 1 / (q0 + q1 + q2)
                q0 *= norm
                q1 *= norm
                q2 *= norm
                var c = tri * 3
                var va = _pick(corners, c, 0, one).cast[DType.int64]() * STRIDE
                var vb = _pick(corners, c, 1, one).cast[DType.int64]() * STRIDE
                var vc = _pick(corners, c, 2, one).cast[DType.int64]() * STRIDE
                var shadow = F(1)
                if use_still:
                    var wants = drawn & _pick(vertices, va, 13, one).ge(0)
                    if wants.reduce_or():
                        var wx = _blend(
                            vertices, va, vb, vc, 10, q0, q1, q2, one
                        )
                        var wy = _blend(
                            vertices, va, vb, vc, 11, q0, q1, q2, one
                        )
                        var wz = _blend(
                            vertices, va, vb, vc, 12, q0, q1, q2, one
                        )
                        shadow = _sun_shadows(still[], wx, wy, wz, bias)
                        if use_moving:
                            shadow = min(
                                shadow, _sun_shadows(moving[], wx, wy, wz, bias)
                            )
                        shadow = wants.select(shadow, F(1))
                var lit_r = (
                    _blend(vertices, va, vb, vc, 4, q0, q1, q2, one)
                    + _blend(vertices, va, vb, vc, 7, q0, q1, q2, one) * shadow
                )
                var lit_g = (
                    _blend(vertices, va, vb, vc, 5, q0, q1, q2, one)
                    + _blend(vertices, va, vb, vc, 8, q0, q1, q2, one) * shadow
                )
                var lit_b = (
                    _blend(vertices, va, vb, vc, 6, q0, q1, q2, one)
                    + _blend(vertices, va, vb, vc, 9, q0, q1, q2, one) * shadow
                )
                var code = _pick(planes, p, 15, one)
                var mapped = drawn & code.ge(0)
                if mapped.reduce_or():
                    var texel = _pixel_texel(
                        maps[],
                        one,
                        mapped.select(code, F(0)),
                        mapped.select(
                            _blend(vertices, va, vb, vc, 14, q0, q1, q2, one),
                            F(0),
                        ),
                        mapped.select(
                            _blend(vertices, va, vb, vc, 15, q0, q1, q2, one),
                            F(0),
                        ),
                    )
                    lit_r = mapped.select(lit_r * texel[0], lit_r)
                    lit_g = mapped.select(lit_g * texel[1], lit_g)
                    lit_b = mapped.select(lit_b * texel[2], lit_b)
                    if fog:
                        # The fog's share kept, packed with the lookup.
                        var packed = _blend(
                            vertices, va, vb, vc, 13, q0, q1, q2, one
                        )
                        var keep = packed.ge(0).select(packed, -1 - packed)
                        lit_r = mapped.select(
                            lit_r * keep + fog_color[0] * (1 - keep), lit_r
                        )
                        lit_g = mapped.select(
                            lit_g * keep + fog_color[1] * (1 - keep), lit_g
                        )
                        lit_b = mapped.select(
                            lit_b * keep + fog_color[2] * (1 - keep), lit_b
                        )
                r = drawn.select(lit_r, r)
                g = drawn.select(lit_g, g)
                b = drawn.select(lit_b, b)
            var toned = aces_tone[GAME_LANES](r, g, b, exposure)
            var red = _encode_bytes(toned[0], buckets, thresholds)
            var green = _encode_bytes(toned[1], buckets, thresholds)
            var blue = _encode_bytes(toned[2], buckets, thresholds)
            var kept = drawn.select(here, infinite)
            for k in range(lanes):  # pragma: no branch
                var out = pixels.unsafe_offset((at + k) * 4)
                out[unsafe_offset=0] = UInt8(red[k])
                out[unsafe_offset=1] = UInt8(green[k])
                out[unsafe_offset=2] = UInt8(blue[k])
                out[unsafe_offset=3] = 255
                out_depth[unsafe_offset=at + k] = kept[k]
            x += lanes
