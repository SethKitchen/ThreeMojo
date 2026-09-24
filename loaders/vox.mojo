# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""MagicaVoxel VOX files, from three.js `examples/jsm/loaders/VOXLoader.js`.

A VOX file is `VOX `, the version 150, and a tree of chunks. Each chunk
is a four-letter id, the size of its content, the size of its children,
the content, and the children. `parse_vox` reads the three chunks
three.js reads: `SIZE` starts a model, `XYZI` gives its voxels, and
`RGBA` gives a palette. The others are stepped over, their children read
in turn.

**The palette.** A model takes three.js's default palette. An `RGBA`
chunk gives its palette to the model read last before it, as three.js
gives it to its last chunk. A voxel's color index picks a palette entry,
red in the low byte.

**A mesh.** `vox_geometry` is three.js's `VOXMesh` geometry: two
triangles for each face of a voxel that has no voxel beside it, centered
on the model with y up. Each vertex has a color, decoded from sRGB, when
any voxel is not black. `vox_material` is its `MeshStandardMaterial`, and
`add_vox_mesh` adds both to a scene.

**A volume.** `vox_data_3d_texture` is three.js's `VOXData3DTexture`: one
red byte a cell, 255 where a voxel is and zero where one is not.
three.js filters it nearest when it shrinks and linearly when it grows;
a `Data3DTexture` here has one filter, and it is linear.

**What is refused.** Where three.js logs and returns nothing: a file that
is not `VOX ` or not version 150. Where it throws a `RangeError` or a
`TypeError`: a file that ends inside a chunk, and voxels before any
`SIZE`. Also a `SIZE` whose content is less than its three sizes, which
three.js reads backward, and a voxel outside its model, which three.js
writes past its volume.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from materials.material import STANDARD, Material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import srgb_to_linear
from render.texture import BILINEAR
from render.volume_texture import Data3DTexture, VolumeImage
from std.pathlib import Path

# three.js's `DEFAULT_PALETTE`: 256 colors, red in the low byte.
comptime DEFAULT_PALETTE: List[UInt32] = [
    0x00000000,
    0xFFFFFFFF,
    0xFFCCFFFF,
    0xFF99FFFF,
    0xFF66FFFF,
    0xFF33FFFF,
    0xFF00FFFF,
    0xFFFFCCFF,
    0xFFCCCCFF,
    0xFF99CCFF,
    0xFF66CCFF,
    0xFF33CCFF,
    0xFF00CCFF,
    0xFFFF99FF,
    0xFFCC99FF,
    0xFF9999FF,
    0xFF6699FF,
    0xFF3399FF,
    0xFF0099FF,
    0xFFFF66FF,
    0xFFCC66FF,
    0xFF9966FF,
    0xFF6666FF,
    0xFF3366FF,
    0xFF0066FF,
    0xFFFF33FF,
    0xFFCC33FF,
    0xFF9933FF,
    0xFF6633FF,
    0xFF3333FF,
    0xFF0033FF,
    0xFFFF00FF,
    0xFFCC00FF,
    0xFF9900FF,
    0xFF6600FF,
    0xFF3300FF,
    0xFF0000FF,
    0xFFFFFFCC,
    0xFFCCFFCC,
    0xFF99FFCC,
    0xFF66FFCC,
    0xFF33FFCC,
    0xFF00FFCC,
    0xFFFFCCCC,
    0xFFCCCCCC,
    0xFF99CCCC,
    0xFF66CCCC,
    0xFF33CCCC,
    0xFF00CCCC,
    0xFFFF99CC,
    0xFFCC99CC,
    0xFF9999CC,
    0xFF6699CC,
    0xFF3399CC,
    0xFF0099CC,
    0xFFFF66CC,
    0xFFCC66CC,
    0xFF9966CC,
    0xFF6666CC,
    0xFF3366CC,
    0xFF0066CC,
    0xFFFF33CC,
    0xFFCC33CC,
    0xFF9933CC,
    0xFF6633CC,
    0xFF3333CC,
    0xFF0033CC,
    0xFFFF00CC,
    0xFFCC00CC,
    0xFF9900CC,
    0xFF6600CC,
    0xFF3300CC,
    0xFF0000CC,
    0xFFFFFF99,
    0xFFCCFF99,
    0xFF99FF99,
    0xFF66FF99,
    0xFF33FF99,
    0xFF00FF99,
    0xFFFFCC99,
    0xFFCCCC99,
    0xFF99CC99,
    0xFF66CC99,
    0xFF33CC99,
    0xFF00CC99,
    0xFFFF9999,
    0xFFCC9999,
    0xFF999999,
    0xFF669999,
    0xFF339999,
    0xFF009999,
    0xFFFF6699,
    0xFFCC6699,
    0xFF996699,
    0xFF666699,
    0xFF336699,
    0xFF006699,
    0xFFFF3399,
    0xFFCC3399,
    0xFF993399,
    0xFF663399,
    0xFF333399,
    0xFF003399,
    0xFFFF0099,
    0xFFCC0099,
    0xFF990099,
    0xFF660099,
    0xFF330099,
    0xFF000099,
    0xFFFFFF66,
    0xFFCCFF66,
    0xFF99FF66,
    0xFF66FF66,
    0xFF33FF66,
    0xFF00FF66,
    0xFFFFCC66,
    0xFFCCCC66,
    0xFF99CC66,
    0xFF66CC66,
    0xFF33CC66,
    0xFF00CC66,
    0xFFFF9966,
    0xFFCC9966,
    0xFF999966,
    0xFF669966,
    0xFF339966,
    0xFF009966,
    0xFFFF6666,
    0xFFCC6666,
    0xFF996666,
    0xFF666666,
    0xFF336666,
    0xFF006666,
    0xFFFF3366,
    0xFFCC3366,
    0xFF993366,
    0xFF663366,
    0xFF333366,
    0xFF003366,
    0xFFFF0066,
    0xFFCC0066,
    0xFF990066,
    0xFF660066,
    0xFF330066,
    0xFF000066,
    0xFFFFFF33,
    0xFFCCFF33,
    0xFF99FF33,
    0xFF66FF33,
    0xFF33FF33,
    0xFF00FF33,
    0xFFFFCC33,
    0xFFCCCC33,
    0xFF99CC33,
    0xFF66CC33,
    0xFF33CC33,
    0xFF00CC33,
    0xFFFF9933,
    0xFFCC9933,
    0xFF999933,
    0xFF669933,
    0xFF339933,
    0xFF009933,
    0xFFFF6633,
    0xFFCC6633,
    0xFF996633,
    0xFF666633,
    0xFF336633,
    0xFF006633,
    0xFFFF3333,
    0xFFCC3333,
    0xFF993333,
    0xFF663333,
    0xFF333333,
    0xFF003333,
    0xFFFF0033,
    0xFFCC0033,
    0xFF990033,
    0xFF660033,
    0xFF330033,
    0xFF000033,
    0xFFFFFF00,
    0xFFCCFF00,
    0xFF99FF00,
    0xFF66FF00,
    0xFF33FF00,
    0xFF00FF00,
    0xFFFFCC00,
    0xFFCCCC00,
    0xFF99CC00,
    0xFF66CC00,
    0xFF33CC00,
    0xFF00CC00,
    0xFFFF9900,
    0xFFCC9900,
    0xFF999900,
    0xFF669900,
    0xFF339900,
    0xFF009900,
    0xFFFF6600,
    0xFFCC6600,
    0xFF996600,
    0xFF666600,
    0xFF336600,
    0xFF006600,
    0xFFFF3300,
    0xFFCC3300,
    0xFF993300,
    0xFF663300,
    0xFF333300,
    0xFF003300,
    0xFFFF0000,
    0xFFCC0000,
    0xFF990000,
    0xFF660000,
    0xFF330000,
    0xFF0000EE,
    0xFF0000DD,
    0xFF0000BB,
    0xFF0000AA,
    0xFF000088,
    0xFF000077,
    0xFF000055,
    0xFF000044,
    0xFF000022,
    0xFF000011,
    0xFF00EE00,
    0xFF00DD00,
    0xFF00BB00,
    0xFF00AA00,
    0xFF008800,
    0xFF007700,
    0xFF005500,
    0xFF004400,
    0xFF002200,
    0xFF001100,
    0xFFEE0000,
    0xFFDD0000,
    0xFFBB0000,
    0xFFAA0000,
    0xFF880000,
    0xFF770000,
    0xFF550000,
    0xFF440000,
    0xFF220000,
    0xFF110000,
    0xFFEEEEEE,
    0xFFDDDDDD,
    0xFFBBBBBB,
    0xFFAAAAAA,
    0xFF888888,
    0xFF777777,
    0xFF555555,
    0xFF444444,
    0xFF222222,
    0xFF111111,
]


struct VoxModel(Copyable, Movable):
    """One model of a file, three.js's chunk `{ size, data, palette }`."""

    # Voxels across, deep and up, as the file gives them.
    var size_x: Int
    var size_y: Int
    var size_z: Int
    # Four bytes a voxel: x, y, z and a color index.
    var data: List[UInt8]
    # The colors the indices pick.
    var palette: List[UInt32]

    def __init__(out self, size_x: Int, size_y: Int, size_z: Int):
        """Start a model with no voxels and the default palette.

        Args:
            size_x: Voxels across.
            size_y: Voxels deep.
            size_z: Voxels up.
        """
        self.size_x = size_x
        self.size_y = size_y
        self.size_z = size_z
        self.data = List[UInt8]()
        self.palette = materialize[DEFAULT_PALETTE]()

    def voxel_count(self) -> Int:
        """Return how many voxels the model has."""
        return len(self.data) // 4


def _u32(bytes: List[UInt8], at: Int) raises -> Int:
    """Return the little-endian 32-bit value at `at`.

    Raises:
        Error: If it runs past the end of the file.
    """
    if at + 4 > len(bytes):
        raise Error("VOX: the file ends inside a chunk, at byte " + String(at))
    var value = 0
    for k in range(4):  # pragma: no branch
        value |= Int(bytes[at + k]) << (8 * k)
    return value


def parse_vox(bytes: List[UInt8]) raises -> List[VoxModel]:
    """Read a VOX file's models, three.js's `VOXLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The models, in file order.

    Raises:
        Error: If the file is not `VOX ` version 150, it ends inside a
            chunk, voxels come before a `SIZE`, a `SIZE` is too short, or
            a voxel lies outside its model.
    """
    if _u32(bytes, 0) != 542658390:
        raise Error("VOX: not a VOX file")
    var version = _u32(bytes, 4)
    if version != 150:
        raise Error("VOX: version " + String(version) + " is not supported")
    var models = List[VoxModel]()
    var i = 8
    while i < len(bytes):
        _ = _u32(bytes, i)
        var id = String()
        for k in range(4):  # pragma: no branch
            id += chr(Int(bytes[i + k]))
        var content = _u32(bytes, i + 4)
        _ = _u32(bytes, i + 8)
        i += 12
        if id == "SIZE":
            if content < 12:
                raise Error("VOX: a SIZE chunk too short for its sizes")
            models.append(
                VoxModel(_u32(bytes, i), _u32(bytes, i + 4), _u32(bytes, i + 8))
            )
            i += content
        elif id == "XYZI":
            if len(models) == 0:
                raise Error("VOX: voxels before any SIZE")
            var count = _u32(bytes, i)
            i += 4
            if i + count * 4 > len(bytes):
                raise Error("VOX: the file ends inside its voxels")
            ref model = models[len(models) - 1]
            model.data = List[UInt8](bytes[i : i + count * 4])
            for v in range(count):
                var outside = (
                    Int(model.data[v * 4]) >= model.size_x
                    or Int(model.data[v * 4 + 1]) >= model.size_y
                    or Int(model.data[v * 4 + 2]) >= model.size_z
                )
                if outside:
                    raise Error("VOX: a voxel outside its model")
            i += count * 4
        elif id == "RGBA":
            if len(models) == 0:
                raise Error("VOX: a palette before any SIZE")
            var palette: List[UInt32] = [0]
            for j in range(256):  # pragma: no branch
                palette.append(UInt32(_u32(bytes, i + j * 4)))
            models[len(models) - 1].palette = palette^
            i += 1024
        else:
            i += content
    return models^


# The six faces of a voxel, three.js's `px`, `nx`, `py`, `ny`, `pz` and
# `nz`: two triangles of three corners each.
comptime _PX: List[Int] = [1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0]
comptime _NX: List[Int] = [0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1]
comptime _PY: List[Int] = [0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1]
comptime _NY: List[Int] = [0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0]
comptime _PZ: List[Int] = [0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1]
comptime _NZ: List[Int] = [0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0]


def _occupancy(model: VoxModel) -> List[UInt8]:
    """Return 255 for each cell a voxel fills and zero for the others,
    `x` fastest, then `y`, then `z`."""
    var cells = List[UInt8](
        length=model.size_x * model.size_y * model.size_z, fill=0
    )
    for v in range(model.voxel_count()):
        var x = Int(model.data[v * 4])
        var y = Int(model.data[v * 4 + 1])
        var z = Int(model.data[v * 4 + 2])
        cells[x + y * model.size_x + z * model.size_x * model.size_y] = 255
    return cells^


def _empty(cells: List[UInt8], index: Int) -> Bool:
    """Return True if a cell is there and holds no voxel, three.js's
    `array[ index ] === 0`."""
    return index >= 0 and index < len(cells) and cells[index] == 0


struct _Faces:
    """The vertices and colors of the faces added so far."""

    var vertices: List[Float32]
    var colors: List[Float32]
    var half: SIMD[DType.float64, 4]

    def __init__(out self, model: VoxModel):
        """Start with no faces."""
        self.vertices = List[Float32]()
        self.colors = List[Float32]()
        self.half = SIMD[DType.float64, 4](
            Float64(model.size_x) / 2,
            Float64(model.size_y) / 2,
            Float64(model.size_z) / 2,
            0,
        )

    def add(
        mut self,
        tile: List[Int],
        x: Int,
        y: Int,
        z: Int,
        rgb: SIMD[DType.float32, 4],
    ):
        """Add one face, three.js's `add`: called with the voxel's `x`,
        `z` and `-y`, so y is up."""
        var fx = Float64(x) - self.half[0]
        var fy = Float64(y) - self.half[2]
        var fz = Float64(z) + self.half[1]
        for i in range(0, 18, 3):  # pragma: no branch
            self.vertices.append(Float32(Float64(tile[i]) + fx))
            self.vertices.append(Float32(Float64(tile[i + 1]) + fy))
            self.vertices.append(Float32(Float64(tile[i + 2]) + fz))
            self.colors.append(rgb[0])
            self.colors.append(rgb[1])
            self.colors.append(rgb[2])


def vox_has_colors(model: VoxModel) -> Bool:
    """Return True if any voxel's color is not black, three.js's
    `hasColors`.

    Args:
        model: The model.

    Returns:
        Whether a voxel has red, green or blue.
    """
    for v in range(model.voxel_count()):
        if model.palette[Int(model.data[v * 4 + 3])] & 0xFFFFFF != 0:
            return True
    return False


def vox_geometry(model: VoxModel) raises -> BufferGeometry:
    """Return the faces of a model, three.js's `VOXMesh` geometry.

    Args:
        model: The model.

    Returns:
        A geometry with `position` and `normal`, and `color` when
        `vox_has_colors` is True. It has no index.

    Raises:
        Error: If a voxel's color index is past the palette.
    """
    var cells = _occupancy(model)
    var faces = _Faces(model)
    var dy = model.size_x
    var dz = model.size_x * model.size_y
    var px = materialize[_PX]()
    var nx = materialize[_NX]()
    var py = materialize[_PY]()
    var ny = materialize[_NY]()
    var pz = materialize[_PZ]()
    var nz = materialize[_NZ]()
    for v in range(model.voxel_count()):
        var x = Int(model.data[v * 4])
        var y = Int(model.data[v * 4 + 1])
        var z = Int(model.data[v * 4 + 2])
        var c = Int(model.data[v * 4 + 3])
        if c >= len(model.palette):
            raise Error("VOX: a color index past the palette")
        var hex = model.palette[c]
        var rgb = SIMD[DType.float32, 4](0)
        for k in range(3):  # pragma: no branch
            var byte = Float32((hex >> UInt32(8 * k)) & 0xFF) / 255
            rgb[k] = srgb_to_linear(byte)
        var index = x + y * dy + z * dz
        var right = _empty(cells, index + 1) or x == model.size_x - 1
        if right:
            faces.add(px, x, z, -y, rgb)
        var left = _empty(cells, index - 1) or x == 0
        if left:
            faces.add(nx, x, z, -y, rgb)
        var back = _empty(cells, index + dy) or y == model.size_y - 1
        if back:
            faces.add(ny, x, z, -y, rgb)
        var front = _empty(cells, index - dy) or y == 0
        if front:
            faces.add(py, x, z, -y, rgb)
        var top = _empty(cells, index + dz) or z == model.size_z - 1
        if top:
            faces.add(pz, x, z, -y, rgb)
        var bottom = _empty(cells, index - dz) or z == 0
        if bottom:
            faces.add(nz, x, z, -y, rgb)
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(faces.vertices.copy(), 3)
    )
    geometry.compute_vertex_normals()
    if vox_has_colors(model):
        geometry.set_attribute(
            String(COLOR), BufferAttribute(faces.colors.copy(), 3)
        )
    return geometry^


def vox_material(model: VoxModel) raises -> Material:
    """Return three.js's `VOXMesh` material: a default
    `MeshStandardMaterial`, with vertex colors when the model has colors.

    Args:
        model: The model.

    Returns:
        The material.

    Raises:
        Error: If `Material` refuses it.
    """
    return Material(
        Color(255, 255, 255),
        kind=STANDARD,
        vertex_colors=vox_has_colors(model),
    )


def add_vox_mesh(
    model: VoxModel,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> NodeId:
    """Add a model to a scene as three.js's `VOXMesh`.

    Args:
        model: The model.
        scene: Where its node and mesh go.
        assets: Where its geometry and material go.
        parent: The node its node goes under.

    Returns:
        Its node.

    Raises:
        Error: If `vox_geometry` or `vox_material` refuses the model.
    """
    var node = Object3D()
    node.parent = parent
    var at = scene.add(node^)
    var geometry = assets.geometries.add(vox_geometry(model))
    var material = assets.materials.add(vox_material(model))
    scene.add_mesh(Mesh(geometry, material, at))
    return at


def vox_data_3d_texture(model: VoxModel) raises -> Data3DTexture:
    """Return a model as a volume, three.js's `VOXData3DTexture`.

    Args:
        model: The model.

    Returns:
        A red-only texture as big as the model, 255 where a voxel is.

    Raises:
        Error: If the model has a size of zero, which `Data3DTexture`
            refuses.
    """
    var image = VolumeImage.of_bytes(
        model.size_x, model.size_y, model.size_z, _occupancy(model), 1
    )
    return Data3DTexture(image^, filter=BILINEAR)


def read_vox(path: String) raises -> List[VoxModel]:
    """Read a VOX file.

    Args:
        path: The file.

    Returns:
        What `parse_vox` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_vox`
            refuses.
    """
    return parse_vox(Path(path).read_bytes())
