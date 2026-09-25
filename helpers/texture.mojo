# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh that shows a texture as it is, from three.js
`examples/jsm/helpers/TextureHelper.js`.

A 2D texture is a plane of `width` by `height`. A 3D texture or an array
texture is a stack of `depth` planes, one per slice, spread evenly from
`-depth / 2` to `depth / 2` along z. A cube texture is a box of `width` by
`height` by `depth`, each point showing the cube in the direction of that
point from the center. The color is the texel's color, and the alpha is
not the texel's: it is one for a 2D texture and a cube, and
`max(1 / slices, 0.25)` for a stack, so the slices show through each
other. Both sides are drawn, as three.js's `DoubleSide` says.

**What blends.** three.js's material is `transparent`, and it writes its
depth as it blends. A surface that blends here writes its depth too; see
`render.raster_state`. A part with an alpha of one is drawn opaque, which
keeps the nearer face of a cube in front. A stack's slices blend, in
order from the most negative z, as every part stands on one node. Seen
from +z, each slice blends over the ones behind it, as in three.js. Seen
from -z, the nearest slice is drawn first and its depth hides the rest,
as in three.js.

**How it is drawn.** three.js writes a `ShaderMaterial` that reads a
`sampler2D`, a `sampler3D`, a `sampler2DArray` or a `samplerCube` at a
`uvw` attribute. The rasterizers here sample a 2D map by `uv` alone. So
each plane or face is its own mesh with an unlit `BASIC` material, and its
map is a 2D texture that holds what three.js's shader reads there:

- A 2D texture is copied with its alpha ignored, as the shader keeps only
  `.xyz`. The copy has no offset, repeat, rotation or channel, as the
  shader reads `vUvw.xy` as it is. Its `uv` is three.js's `uvw.xy`: the
  plane's `v` when the texture's `flip_y` is set, else `1 - v`.
- A slice of a 3D texture is read at every texel center of the slice with
  `Data3DTexture.sample`, at three.js's third coordinate `i / (slices - 1)`,
  and kept as floats. Two neighbor slices blend there under `BILINEAR`, as
  the `sampler3D` blends them. Sampling that image with the volume's own
  filter and wraps is the same as sampling the volume, because a bilinear
  blend of blends is the trilinear blend.
- A slice of an array texture is its layer `i`, read the same way with
  `DataArrayTexture.sample`.
- A face of a cube is read with `CubeTexture.sample` at every texel center
  of a grid of the cube's size across that face, in the direction of that
  point. For a box with three equal sides, that grid lies on the cube's
  own texels, and the face shows the cube as three.js's does. For a box of
  other sides, the image is a resampling, and it can differ from three.js
  by a filter step between texels.

The parts are stored in the `Assets` given, and `TextureHelper.add_to` puts
them all on one node. The slices are added from the most negative z to the
most positive, as three.js merges them.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from materials.material import BASIC, DOUBLE_SIDE, Material, MaterialId
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture_store import CubeTextureId
from render.framebuffer import Color, FloatColor
from render.texture import (
    IGNORED,
    UV_CHANNEL_0,
    UV_MAPPING,
    Filter,
    Texture,
    Wrap,
    float_texture,
)
from render.texture_store import TextureId
from render.volume_texture_store import Data3DTextureId, DataArrayTextureId
from std.math import max
from units.si import Angle, Length, METER, RADIAN

# three.js's defaults: a plane, a stack or a box of one unit each way.
comptime DEFAULT_TEXTURE_HELPER_SIZE = Length(1.0, METER)
# The least alpha a slice of a stack is drawn with, three.js's `0.25`.
comptime MIN_SLICE_ALPHA = Float32(0.25)


struct TextureHelper(Copyable, Movable):
    """The meshes that show one texture: a geometry and a material for
    each plane or face. three.js: `TextureHelper`."""

    var geometries: List[GeometryId]
    var materials: List[MaterialId]

    def __init__(out self):
        """Create a helper with no parts."""
        self.geometries = List[GeometryId]()
        self.materials = List[MaterialId]()

    def count(self) -> Int:
        """Return how many planes or faces the helper has.

        Returns:
            One for a 2D texture, the slice count for a stack, and six for
            a cube.
        """
        return len(self.geometries)

    def meshes(self, node: NodeId) raises -> List[Mesh]:
        """Return a mesh for each part, all on one node.

        Args:
            node: Where the helper stands.

        Returns:
            The meshes, in the order they are drawn.

        Raises:
            Error: If `node` is negative.
        """
        var found = List[Mesh]()
        for index in range(self.count()):
            found.append(
                Mesh(self.geometries[index], self.materials[index], node)
            )
        return found^

    def add_to(self, mut scene: Scene, node: NodeId) raises:
        """Add every part to a scene, on one node.

        Args:
            scene: The scene.
            node: Where the helper stands. It must be in the scene.

        Raises:
            Error: If `node` is negative or `Scene.add_mesh` refuses a mesh.
        """
        for mesh in self.meshes(node):
            scene.add_mesh(mesh)

    def _add(
        mut self,
        mut assets: Assets,
        var geometry: BufferGeometry,
        var map: Texture,
        alpha: Float32,
    ) raises:
        """Store one part: its geometry, its map and a material for it."""
        var id = assets.textures.add(map^)
        self.geometries.append(assets.geometries.add(geometry^))
        self.materials.append(
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    map=id,
                    side=DOUBLE_SIDE,
                    opacity=alpha,
                    kind=BASIC,
                    transparent=alpha < 1,
                    fog=False,
                )
            )
        )


def _positive(size: Length, name: String) raises:
    """Refuse a size that is not positive."""
    if size.to(METER) <= 0:
        raise Error("A texture helper needs a positive " + name)


def _slice(
    width: Length,
    height: Length,
    depth: Length,
    index: Int,
    count: Int,
    flip_y: Bool,
) raises -> BufferGeometry:
    """Return one plane of the helper: three.js's `PlaneGeometry`, moved
    along z for a stack, with `uvw.xy` as its `uv`."""
    var geometry = plane(width, height)
    if count > 1:
        var z = depth.to(METER) * (
            Float32(index) / Float32(count - 1) - Float32(0.5)
        )
        var positions = geometry.clone_attribute(String(POSITION))
        for vertex in range(positions.count()):  # pragma: no branch
            positions.set_component(vertex, 2, z)
        geometry.set_attribute(String(POSITION), positions^)
    if not flip_y:
        var uvs = geometry.clone_attribute(String(UV))
        for vertex in range(uvs.count()):  # pragma: no branch
            uvs.set_component(vertex, 1, 1 - uvs.component(vertex, 1))
        geometry.set_attribute(String(UV), uvs^)
    return geometry^


def _slice_alpha(count: Int) -> Float32:
    """Return three.js's `getAlpha` for a stack of `count` slices."""
    return max(Float32(1) / Float32(count), MIN_SLICE_ALPHA)


def _slice_coordinate(index: Int, count: Int, layered: Bool) -> Float32:
    """Return three.js's third coordinate for slice `index`: one for a
    single slice, the layer for an array, and the fraction for a volume."""
    if count == 1:
        return 1
    if layered:
        return Float32(index)
    return Float32(index) / Float32(count - 1)


def _baked(
    var data: List[Float32],
    width: Int,
    height: Int,
    wrap_s: Wrap,
    wrap_t: Wrap,
    filter: Filter,
    flip_y: Bool,
) raises -> Texture:
    """Return floats read off a texture as a map with no mip chain, its
    alpha ignored, sampled as the texture they were read from is."""
    var map = float_texture(
        width, height, data^, wrap_s, filter, False, IGNORED
    )
    map.wrap_t = wrap_t
    map.flip_y = flip_y
    return map^


def _push(mut data: List[Float32], color: FloatColor):
    """Append one texel's four floats."""
    data.append(color.r)
    data.append(color.g)
    data.append(color.b)
    data.append(color.a)


def texture_helper(
    texture: TextureId,
    mut assets: Assets,
    width: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    height: Length = DEFAULT_TEXTURE_HELPER_SIZE,
) raises -> TextureHelper:
    """Return a plane that shows a 2D texture. three.js: `TextureHelper`
    given a `Texture`.

    Args:
        texture: The texture, in `assets.textures`. It must hold an image.
        assets: Where the texture is, and where the parts are stored.
        width: How wide the plane is. Must be positive.
        height: How tall the plane is. Must be positive.

    Returns:
        The helper, of one part, drawn with an alpha of one.

    Raises:
        Error: If a size is not positive, the texture is not in the store
            or is the blank texture, or its copy cannot be built.
    """
    _positive(width, "width")
    _positive(height, "height")
    ref source = assets.textures.get(texture)
    if source.is_blank():
        raise Error("A texture helper needs a texture with an image")
    var shown = source.ignoring_alpha()
    var flip_y = source.flip_y
    # The shader reads `vUvw.xy` as it is: no transform, the first set.
    shown.offset = Vector2(0, 0)
    shown.repeat = Vector2(1, 1)
    shown.rotation = Angle(0.0, RADIAN)
    shown.center = Vector2(0, 0)
    shown.channel = UV_CHANNEL_0
    shown.mapping = UV_MAPPING
    var helper = TextureHelper()
    helper._add(
        assets,
        _slice(width, height, DEFAULT_TEXTURE_HELPER_SIZE, 0, 1, flip_y),
        shown^,
        1,
    )
    return helper^


def texture_helper(
    texture: Data3DTextureId,
    mut assets: Assets,
    width: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    height: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    depth: Length = DEFAULT_TEXTURE_HELPER_SIZE,
) raises -> TextureHelper:
    """Return a stack of planes that shows a 3D texture, one per slice.
    three.js: `TextureHelper` given a `Data3DTexture`.

    Args:
        texture: The texture, in `assets.data_3d_textures`.
        assets: Where the texture is, and where the parts are stored.
        width: How wide each plane is. Must be positive.
        height: How tall each plane is. Must be positive.
        depth: How far the first plane is from the last. Must be positive.

    Returns:
        The helper, one part per slice.

    Raises:
        Error: If a size is not positive or the texture is not in the
            store.
    """
    _positive(width, "width")
    _positive(height, "height")
    _positive(depth, "depth")
    var helper = TextureHelper()
    var count = assets.data_3d_textures.get(texture).image.depth
    for index in range(count):  # pragma: no branch
        var r = _slice_coordinate(index, count, False)
        var data = List[Float32]()
        ref volume = assets.data_3d_textures.get(texture)
        var wide = volume.image.width
        var tall = volume.image.height
        for y in range(tall):  # pragma: no branch
            for x in range(wide):  # pragma: no branch
                _push(
                    data,
                    volume.sample(
                        (Float32(x) + 0.5) / Float32(wide),
                        (Float32(y) + 0.5) / Float32(tall),
                        r,
                    ),
                )
        var map = _baked(
            data^,
            wide,
            tall,
            volume.wrap_s,
            volume.wrap_t,
            volume.filter,
            False,
        )
        helper._add(
            assets,
            _slice(width, height, depth, index, count, False),
            map^,
            _slice_alpha(count),
        )
    return helper^


def texture_helper(
    texture: DataArrayTextureId,
    mut assets: Assets,
    width: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    height: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    depth: Length = DEFAULT_TEXTURE_HELPER_SIZE,
) raises -> TextureHelper:
    """Return a stack of planes that shows an array texture, one per
    layer. three.js: `TextureHelper` given a `DataArrayTexture`.

    Args:
        texture: The texture, in `assets.data_array_textures`.
        assets: Where the texture is, and where the parts are stored.
        width: How wide each plane is. Must be positive.
        height: How tall each plane is. Must be positive.
        depth: How far the first plane is from the last. Must be positive.

    Returns:
        The helper, one part per layer.

    Raises:
        Error: If a size is not positive or the texture is not in the
            store.
    """
    _positive(width, "width")
    _positive(height, "height")
    _positive(depth, "depth")
    var helper = TextureHelper()
    var count = assets.data_array_textures.get(texture).layers()
    for index in range(count):  # pragma: no branch
        var layer = _slice_coordinate(index, count, True)
        var data = List[Float32]()
        ref stack = assets.data_array_textures.get(texture)
        var wide = stack.image.width
        var tall = stack.image.height
        for y in range(tall):  # pragma: no branch
            for x in range(wide):  # pragma: no branch
                _push(
                    data,
                    stack.sample(
                        (Float32(x) + 0.5) / Float32(wide),
                        (Float32(y) + 0.5) / Float32(tall),
                        layer,
                    ),
                )
        var map = _baked(
            data^,
            wide,
            tall,
            stack.wrap_s,
            stack.wrap_t,
            stack.filter,
            False,
        )
        helper._add(
            assets,
            _slice(width, height, depth, index, count, False),
            map^,
            _slice_alpha(count),
        )
    return helper^


def _face_geometry(whole: BufferGeometry, face: Int) raises -> BufferGeometry:
    """Return one face of a box geometry as a geometry of its own."""
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    ref at = whole.attribute_view(String(POSITION))
    ref facing = whole.attribute_view(String(NORMAL))
    ref placed = whole.attribute_view(String(UV))
    for corner in range(4):  # pragma: no branch
        var vertex = face * 4 + corner
        for axis in range(3):  # pragma: no branch
            positions.append(at.component(vertex, axis))
            normals.append(facing.component(vertex, axis))
        uvs.append(placed.component(vertex, 0))
        uvs.append(placed.component(vertex, 1))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    # The face's two triangles, as the box winds them.
    var index = List[Int]()
    for corner in range(6):  # pragma: no branch
        index.append(whole.index[face * 6 + corner] - face * 4)
    geometry.set_index(index^)
    return geometry^


def texture_helper(
    texture: CubeTextureId,
    mut assets: Assets,
    width: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    height: Length = DEFAULT_TEXTURE_HELPER_SIZE,
    depth: Length = DEFAULT_TEXTURE_HELPER_SIZE,
) raises -> TextureHelper:
    """Return a box that shows a cube texture, each point the cube in its
    direction from the center. three.js: `TextureHelper` given a
    `CubeTexture`.

    Args:
        texture: The texture, in `assets.cube_textures`.
        assets: Where the texture is, and where the parts are stored.
        width: How wide the box is. Must be positive.
        height: How tall the box is. Must be positive.
        depth: How deep the box is. Must be positive.

    Returns:
        The helper, one part per face, drawn with an alpha of one.

    Raises:
        Error: If a size is not positive or the texture is not in the
            store.
    """
    _positive(width, "width")
    _positive(height, "height")
    _positive(depth, "depth")
    var whole = box(width, height, depth)
    var helper = TextureHelper()
    for face in range(6):  # pragma: no branch
        var geometry = _face_geometry(whole, face)
        ref at = geometry.attribute_view(String(POSITION))
        # The corners at uv (0, 0), (1, 0) and (0, 1): three.js's grid runs
        # row by row from the top, (0, 1) (1, 1) (0, 0) (1, 0); see
        # `geometries.box`.
        var origin = at.vector3(2)
        var across = at.vector3(3) - origin
        var up = at.vector3(0) - origin
        var data = List[Float32]()
        ref cube = assets.cube_textures.get(texture)
        var size = cube.size
        for row in range(size):  # pragma: no branch
            for column in range(size):  # pragma: no branch
                # The first stored row is the top, at v near one.
                var u = (Float32(column) + 0.5) / Float32(size)
                var v = 1 - (Float32(row) + 0.5) / Float32(size)
                _push(data, cube.sample(origin + across * u + up * v))
        ref first = cube.faces[0]
        var map = _baked(
            data^,
            size,
            size,
            first.wrap_s,
            first.wrap_t,
            first.mag_filter,
            True,
        )
        helper._add(assets, geometry^, map^, 1)
    return helper^
