# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A compiled node program, and the store that owns them.

`materials.nodes` builds node graphs and compiles them into the
`NodeProgram`s here. The program, its value types and its outputs live
apart from the compiler, so that `core.assets`, which holds a
`NodeProgramStore`, does not compile the whole node system.
"""

from materials.node_program_id import NodeProgramId
from core.ordinal import (
    ordinal_valid,
    require_index_in_count,
    require_valid,
    require_non_negative,
)
from core.search import first_match
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.square_matrix import store_elements
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from render.framebuffer import (
    Color,
    FloatColor,
)
from render.cube_texture_store import CubeTextureId
from render.volume_texture_store import (
    Data3DTextureId,
    DataArrayTextureId,
)
from render.texture_store import TextureId
from std.memory import bitcast
from units.si import (
    Duration,
    SECOND,
)


# How a program begins: where each of the twenty-five outputs starts and how many
# instructions it holds, then the frame's time in seconds, then the view
# matrix, sixteen floats, column-major. The renderer writes the last two
# every frame, as three.js updates its `time` and `cameraViewMatrix` nodes.
comptime NODE_OUTPUT_COUNT = 25


comptime PROGRAM_TIME = NODE_OUTPUT_COUNT * 2


comptime PROGRAM_VIEW = PROGRAM_TIME + 1


comptime PROGRAM_HEADER = PROGRAM_VIEW + 16


comptime Lanes = SIMD[DType.float32, 4]


@fieldwise_init
struct ValueType(Equatable, ImplicitlyCopyable, Writable):
    """What a node's value is, as a type rather than a bare int: a `float`,
    a vector of two, three or four, a `mat3` or a `mat4`, a texture, a
    cube texture, a 3D texture or an array texture. `value` is the
    component count, 32 for a texture, 33 for a cube texture, 34 for a 3D
    texture and 35 for an array texture. Values 41 through 44 name exact
    unsigned integers. Values 45 through 48 name exact signed integers.
    `width` gives their component counts."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a supported value type.

        Returns:
            Whether the value is one to four, 9, 16, 32 to 35, or 41 to 48.
        """
        return (
            (self.value >= 1 and self.value <= 4)
            or self.value == 9
            or self.value == 16
            or (self.value >= 32 and self.value <= 35)
            or self.is_integer()
        )

    def is_vector(self) -> Bool:
        """Return True if a register holds this scalar or vector type.

        Returns:
            Whether this is a float-backed or exact integer register type.
        """
        return (self.value >= 1 and self.value <= 4) or self.is_integer()

    def is_unsigned(self) -> Bool:
        """Return whether this type stores exact UInt32 lanes.

        Returns:
            True for `NODE_UINT` and the unsigned vectors.
        """
        return self.value >= 41 and self.value <= 44

    def is_signed(self) -> Bool:
        """Return whether this type stores exact Int32 lanes.

        Returns:
            True for `NODE_INT` and the exact signed vectors.
        """
        return self.value >= 45 and self.value <= 48

    def is_integer(self) -> Bool:
        """Return whether this type stores exact integer lanes.

        Returns:
            True for exact unsigned or signed scalars and vectors.
        """
        return self.is_unsigned() or self.is_signed()

    def width(self) -> Int:
        """Return the component count, without an integer type tag.

        Returns:
            One through four for register types, otherwise the type value.
        """
        if self.is_unsigned():
            return self.value - 40
        if self.is_signed():
            return self.value - 44
        return self.value

    def name(self) -> String:
        """Return the type's TSL name, for an error message.

        Returns:
            `float`, `vec2` to `vec4`, `mat3`, `mat4`, `texture`,
            `cubeTexture`, `texture3D`, `textureArray`, `uint`, `uvec2` to
            `uvec4`, `int`, or `ivec2` to `ivec4`.
        """
        if self.is_unsigned():
            return "uint" if self.width() == 1 else "uvec" + String(
                self.width()
            )
        if self.is_signed():
            return "int" if self.width() == 1 else "ivec" + String(self.width())
        if self.value == 1:
            return "float"
        if self.value == 9:
            return "mat3"
        if self.value == 16:
            return "mat4"
        if self.value == 32:
            return "texture"
        if self.value == 33:
            return "cubeTexture"
        if self.value == 34:
            return "texture3D"
        if self.value == 35:
            return "textureArray"
        return "vec" + String(self.value)


comptime NODE_FLOAT = ValueType(1)


comptime NODE_VEC2 = ValueType(2)


comptime NODE_VEC3 = ValueType(3)


comptime NODE_VEC4 = ValueType(4)


comptime NODE_MAT3 = ValueType(9)


comptime NODE_MAT4 = ValueType(16)


comptime NODE_SAMPLER = ValueType(32)


comptime NODE_SAMPLER_CUBE = ValueType(33)


comptime NODE_SAMPLER_3D = ValueType(34)


comptime NODE_SAMPLER_ARRAY = ValueType(35)


comptime NODE_UVEC3 = ValueType(43)


@fieldwise_init
struct NodeOutput(Equatable, ImplicitlyCopyable, Writable):
    """Which part of the shading a graph replaces, as a type rather than a
    bare int. See the module's list."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the twenty-five outputs there are.

        Returns:
            Whether the value names an output.
        """
        return ordinal_valid(self.value, NODE_OUTPUT_COUNT - 1)

    def value_type(self) -> ValueType:
        """Return the type a node given this output must have.

        Returns:
            `NODE_FLOAT` for the opacity, the mask, the ambient occlusion,
            the depth, the size, the backdrop's alpha, the roughness, the
            metalness, the five thickness numbers, the scattering and the
            offset, `NODE_VEC4` for the fragment and the cast shadow, and
            `NODE_VEC3` for the rest.
        """
        return NODE_FLOAT if (
            self == OPACITY_NODE
            or self == MASK_NODE
            or self == AO_NODE
            or self == DEPTH_NODE
            or self == SIZE_NODE
            or self == BACKDROP_ALPHA_NODE
            or self == ROUGHNESS_NODE
            or self == METALNESS_NODE
            or self == THICKNESS_DISTORTION_NODE
            or self == THICKNESS_AMBIENT_NODE
            or self == THICKNESS_ATTENUATION_NODE
            or self == THICKNESS_POWER_NODE
            or self == THICKNESS_SCALE_NODE
            or self == SCATTERING_NODE
            or self == OFFSET_NODE
        ) else (
            NODE_VEC4 if self == FRAGMENT_NODE
            or self == CAST_SHADOW_NODE else NODE_VEC3
        )


comptime OPACITY_NODE = NodeOutput(1)


comptime MASK_NODE = NodeOutput(6)


comptime AO_NODE = NodeOutput(7)


comptime DEPTH_NODE = NodeOutput(8)


comptime SIZE_NODE = NodeOutput(9)


comptime BACKDROP_ALPHA_NODE = NodeOutput(11)


comptime FRAGMENT_NODE = NodeOutput(12)


comptime ROUGHNESS_NODE = NodeOutput(13)


comptime METALNESS_NODE = NodeOutput(14)


comptime CAST_SHADOW_NODE = NodeOutput(16)


comptime THICKNESS_DISTORTION_NODE = NodeOutput(18)


comptime THICKNESS_AMBIENT_NODE = NodeOutput(19)


comptime THICKNESS_ATTENUATION_NODE = NodeOutput(20)


comptime THICKNESS_POWER_NODE = NodeOutput(21)


comptime THICKNESS_SCALE_NODE = NodeOutput(22)


# three.js's `VolumeNodeMaterial`: the density at a step of the ray, and
# the share of a step the ray starts at. See
# `materials.volume_node_material`.
comptime SCATTERING_NODE = NodeOutput(23)


comptime OFFSET_NODE = NodeOutput(24)


def require_node_output(output: NodeOutput) raises:
    """Refuse a node output that is none of the twenty-five.

    Nothing. The call returns when the output is named.

    Args:
        output: The output.

    Raises:
        Error: If the output is none of the twenty-five.
    """
    require_valid(
        output.is_valid(), "A node output that is none of the twenty-five"
    )


def _note_texture(mut textures: List[TextureId], map: TextureId):
    """Append a texture to a program's list, once."""
    if first_match(textures, map) >= 0:
        return
    textures.append(map)


def require_unsigned_width(width: Int) raises:
    """Refuse an unsigned uniform wider than four components.

    Nothing. The call returns when the width is four or less.

    Args:
        width: How many components the uniform has.

    Raises:
        Error: If the width is above four.
    """
    if width > 4:
        raise Error("An unsigned uniform has one to four components")


def _uniform_index(names: List[String], name: String) raises -> Int:
    """Return the index of a uniform named `name`.

    Args:
        names: The program's uniform names.
        name: The uniform's name.

    Returns:
        The index in `names`.

    Raises:
        Error: If no uniform has that name.
    """
    var index = first_match(names, name)
    if index < 0:
        raise Error("A node program has no uniform named " + name)
    return index


struct NodeProgram(Copyable, Movable):
    """A compiled `NodeGraph`: the bytecode both rasterizers interpret, and
    where its uniforms are in it.

    `code` is laid out as `PROGRAM_HEADER` floats -- each output's first
    instruction and its count, the time, the view -- then the instructions,
    `INSTRUCTION_FLOATS` each, then every uniform and each constant an
    instruction reads: four floats a value, nine a `mat3`, sixteen a
    `mat4`, and a texture's id in the first of four.
    """

    var code: List[Float32]
    var uniform_names: List[String]
    var uniform_offsets: List[Int]
    var uniform_types: List[ValueType]
    # Every texture a texture node reads, so a renderer can check and upload
    # them before a fragment asks, and where each id is in `code`.
    var textures: List[TextureId]
    var texture_offsets: List[Int]
    # Every cube the cube reads read, each once, and where each read keeps
    # its cube's id; see `set_cube`.
    var cubes: List[CubeTextureId]
    var cube_offsets: List[Int]
    # The same of the 3D and array textures; see `set_volume` and
    # `set_array`.
    var volumes: List[Data3DTextureId]
    var volume_offsets: List[Int]
    var arrays: List[DataArrayTextureId]
    var array_offsets: List[Int]
    # The custom attributes the renderer gives each corner: name, first
    # float and width, as `NodeGraph.attribute` laid them out.
    var attribute_names: List[String]
    var attribute_offsets: List[Int]
    var attribute_widths: List[Int]
    # Whether a node reads the opaque scene behind the surface, so the
    # renderer draws that scene first; see `NodeGraph.viewport_texture`.
    var reads_scene: Bool

    def __init__(out self):
        """Create a program with no outputs, at time zero under an identity
        view. `NodeGraph.compile` fills one."""
        self.code = List[Float32](length=PROGRAM_HEADER, fill=0)
        self.code[PROGRAM_VIEW] = 1
        self.code[PROGRAM_VIEW + 5] = 1
        self.code[PROGRAM_VIEW + 10] = 1
        self.code[PROGRAM_VIEW + 15] = 1
        self.uniform_names = List[String]()
        self.uniform_offsets = List[Int]()
        self.uniform_types = List[ValueType]()
        self.textures = List[TextureId]()
        self.texture_offsets = List[Int]()
        self.cubes = List[CubeTextureId]()
        self.cube_offsets = List[Int]()
        self.volumes = List[Data3DTextureId]()
        self.volume_offsets = List[Int]()
        self.arrays = List[DataArrayTextureId]()
        self.array_offsets = List[Int]()
        self.attribute_names = List[String]()
        self.attribute_offsets = List[Int]()
        self.attribute_widths = List[Int]()
        self.reads_scene = False

    def list_maps(mut self):
        """List every texture, cube, 3D texture and array texture the
        program reads again, each once, after its ids were written in
        place: what a loader calls once it knows each id.
        """
        self._list_textures()
        self._list_cubes()

    def _list_textures(mut self):
        """List every texture the texture nodes read now, each once."""
        self.textures = List[TextureId]()
        for index in range(len(self.texture_offsets)):
            _note_texture(
                self.textures,
                TextureId(Int(self.code[self.texture_offsets[index]])),
            )

    def has(self, output: NodeOutput) raises -> Bool:
        """Return True if the program sets an output.

        Args:
            output: One of the twenty-five outputs.

        Returns:
            Whether a graph node feeds it.

        Raises:
            Error: If the output is none of the twenty-five.
        """
        require_node_output(output)
        return self.code[output.value * 2 + 1] > 0

    def _find(self, name: String, type: ValueType) raises -> Int:
        """Return where a uniform's floats are.

        Raises:
            Error: If no uniform has that name, or its type is not `type`.
        """
        var index = _uniform_index(self.uniform_names, name)
        if self.uniform_types[index] != type:
            raise Error(
                "The uniform "
                + name
                + " is a "
                + self.uniform_types[index].name()
                + ", not a "
                + type.name()
            )
        return self.uniform_offsets[index]

    def _set(mut self, name: String, type: ValueType, value: Lanes) raises:
        """Write a uniform's four floats.

        Raises:
            Error: If no uniform has that name, or its type is not `type`.
        """
        var at = self._find(name, type)
        for lane in range(4):  # pragma: no branch
            self.code[at + lane] = value[lane]

    def set_uniform_uint(mut self, name: String, value: UInt32) raises:
        """Update an exact unsigned scalar uniform.

        Args:
            name: The uniform's name.
            value: The unsigned value, retaining all bits.

        Raises:
            Error: If the name or the declared type is invalid.
        """
        self.set_uniform_uint[1](name, value)

    def set_uniform_uint(
        mut self, name: String, value: SIMD[DType.uint32, 2]
    ) raises:
        """Update an exact unsigned 2-component vector uniform.

        Args:
            name: The uniform's name.
            value: The unsigned value, retaining all bits.

        Raises:
            Error: If the name or the declared type is invalid.
        """
        self.set_uniform_uint[2](name, value)

    def set_uniform_uint(
        mut self, name: String, x: UInt32, y: UInt32, z: UInt32
    ) raises:
        """Update an exact unsigned three-component uniform.

        Mojo SIMD widths are powers of two. This overload supplies three
        components without requiring an unsupported SIMD width.

        Args:
            name: The uniform's name.
            x: The first unsigned component.
            y: The second unsigned component.
            z: The third unsigned component.

        Raises:
            Error: If the name or the declared type is invalid.
        """
        self._set(
            name,
            NODE_UVEC3,
            Lanes(
                bitcast[DType.float32](x),
                bitcast[DType.float32](y),
                bitcast[DType.float32](z),
                0,
            ),
        )

    def set_uniform_uint(
        mut self, name: String, value: SIMD[DType.uint32, 4]
    ) raises:
        """Update an exact unsigned 4-component vector uniform.

        Args:
            name: The uniform's name.
            value: The unsigned value, retaining all bits.

        Raises:
            Error: If the name or the declared type is invalid.
        """
        self.set_uniform_uint[4](name, value)

    def set_uniform_uint[
        width: Int
    ](mut self, name: String, value: SIMD[DType.uint32, width]) raises:
        """Change an exact unsigned scalar or vector uniform.

        Args:
            name: The uniform's name.
            value: Its new unsigned components, without conversion.

        Raises:
            Error: If the name, width, or unsigned type does not match.
        """
        require_unsigned_width(width)
        var lanes = Lanes(0)
        for lane in range(width):  # pragma: no branch
            lanes[lane] = bitcast[DType.float32](value[lane])
        self._set(name, ValueType(40 + width), lanes)

    def set_uniform(mut self, name: String, value: Float32) raises:
        """Change a `float` uniform, as three.js's `uniform.value =` does.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `float`.
        """
        self._set(name, NODE_FLOAT, Lanes(value, 0, 0, 0))

    def set_uniform(mut self, name: String, value: Vector2) raises:
        """Change a `vec2` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `vec2`.
        """
        self._set(name, NODE_VEC2, Lanes(value.x, value.y, 0, 0))

    def set_uniform(mut self, name: String, value: Vector3) raises:
        """Change a `vec3` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `vec3`.
        """
        self._set(name, NODE_VEC3, Lanes(value.x, value.y, value.z, 0))

    def set_uniform(mut self, name: String, value: Vector4) raises:
        """Change a `vec4` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `vec4`.
        """
        self._set(name, NODE_VEC4, Lanes(value.x, value.y, value.z, value.w))

    def set_uniform(mut self, name: String, value: Color) raises:
        """Change a `vec3` uniform to a color, decoded to linear.

        Args:
            name: The uniform's name.
            value: Its new value, as authored in sRGB.

        Raises:
            Error: If no uniform has that name, or it is not a `vec3`.
        """
        var linear = FloatColor(srgb=value)
        self._set(name, NODE_VEC3, Lanes(linear.r, linear.g, linear.b, 0))

    def set_uniform(mut self, name: String, value: Matrix3) raises:
        """Change a `mat3` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `mat3`.
        """
        store_elements(self.code, self._find(name, NODE_MAT3), value.elements)

    def set_uniform(mut self, name: String, value: Matrix4) raises:
        """Change a `mat4` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `mat4`.
        """
        store_elements(self.code, self._find(name, NODE_MAT4), value.elements)

    def _list_cubes(mut self):
        """List every cube, 3D texture and array texture the reads read
        now, each once."""
        var cubes = self._ids(self.cube_offsets)
        self.cubes = List[CubeTextureId]()
        for index in range(len(cubes)):
            self.cubes.append(CubeTextureId(cubes[index]))
        var volumes = self._ids(self.volume_offsets)
        self.volumes = List[Data3DTextureId]()
        for index in range(len(volumes)):
            self.volumes.append(Data3DTextureId(volumes[index]))
        var arrays = self._ids(self.array_offsets)
        self.arrays = List[DataArrayTextureId]()
        for index in range(len(arrays)):
            self.arrays.append(DataArrayTextureId(arrays[index]))

    def _ids(self, offsets: List[Int]) -> List[Int]:
        """Return the ids kept at some offsets, each once."""
        var ids = List[Int]()
        for index in range(len(offsets)):
            var id = Int(self.code[offsets[index]])
            if first_match(ids, id) < 0:
                ids.append(id)
        return ids^

    def set_volume(mut self, name: String, map: Data3DTextureId) raises:
        """Change a 3D texture uniform, and list what the program reads
        again.

        Args:
            name: The uniform's name.
            map: The 3D texture. It must be in the store the renderer
                draws with.

        Raises:
            Error: If `map` is negative, no uniform has that name, or it is
                not a 3D texture.
        """
        require_non_negative(map.value, "A 3D texture uniform needs a texture")
        self.code[self._find(name, NODE_SAMPLER_3D)] = Float32(map.value)
        self._list_cubes()

    def set_array(mut self, name: String, map: DataArrayTextureId) raises:
        """Change an array texture uniform, and list what the program reads
        again.

        Args:
            name: The uniform's name.
            map: The array texture. It must be in the store the renderer
                draws with.

        Raises:
            Error: If `map` is negative, no uniform has that name, or it is
                not an array texture.
        """
        require_non_negative(
            map.value, "An array texture uniform needs a texture"
        )
        self.code[self._find(name, NODE_SAMPLER_ARRAY)] = Float32(map.value)
        self._list_cubes()

    def set_cube(mut self, name: String, map: CubeTextureId) raises:
        """Change a cube texture uniform, and list the cubes the program
        reads again.

        Args:
            name: The uniform's name.
            map: The cube. It must be in the store the renderer draws with.

        Raises:
            Error: If `map` is negative, no uniform has that name, or it is
                not a cube texture.
        """
        require_non_negative(map.value, "A cube uniform needs a cube")
        var at = self._find(name, NODE_SAMPLER_CUBE)
        self.code[at] = Float32(map.value)
        self._list_cubes()

    def set_texture(mut self, name: String, map: TextureId) raises:
        """Change a texture uniform, as three.js's `textureNode.value =`
        does, and list the textures the program reads again.

        Args:
            name: The uniform's name.
            map: The texture. It must be in the store the renderer draws
                with.

        Raises:
            Error: If `map` is negative, no uniform has that name, or it is
                not a texture.
        """
        require_non_negative(map.value, "A texture uniform needs a texture")
        var at = self._find(name, NODE_SAMPLER)
        self.code[at] = Float32(map.value)
        self._list_textures()

    def uniform(self, name: String) raises -> Lanes:
        """Return a uniform's value, in as many lanes as its type has and
        zero past them: a matrix's first four floats, a texture's id.
        Exact unsigned values are raw bitcast words; `read_unsigned`
        returns them as UInt32 lanes.

        Args:
            name: The uniform's name.

        Returns:
            The value.

        Raises:
            Error: If no uniform has that name.
        """
        var index = _uniform_index(self.uniform_names, name)
        var at = self.uniform_offsets[index]
        return Lanes(
            self.code[at],
            self.code[at + 1],
            self.code[at + 2],
            self.code[at + 3],
        )

    def read_unsigned(self, name: String) raises -> SIMD[DType.uint32, 4]:
        """Read all bits of an exact unsigned uniform.

        Args:
            name: The unsigned uniform's name.

        Returns:
            The components as UInt32 lanes, with zero past the stored width.

        Raises:
            Error: If the uniform is missing or is not unsigned.
        """
        var index = _uniform_index(self.uniform_names, name)
        if not self.uniform_types[index].is_unsigned():
            raise Error("read_unsigned requires an unsigned uniform")
        return bitcast[DType.uint32, 4](self.uniform(name))

    def set_frame(mut self, time: Duration, view: Matrix4):
        """Write the frame's time and view, what the `time`, view position
        and view normal nodes read. The renderer does this every frame.

        Args:
            time: The time since the animation began.
            view: The world-to-camera matrix.
        """
        self.code[PROGRAM_TIME] = time.to(SECOND)
        store_elements(self.code, PROGRAM_VIEW, view.elements)


struct NodeProgramStore(Copyable, Movable):
    """Owns node programs and hands out ids naming them, as `TextureStore`
    owns textures: a `Material` names its program by id."""

    var programs: List[NodeProgram]

    def __init__(out self):
        """Create an empty store."""
        self.programs = List[NodeProgram]()

    def count(self) -> Int:
        """Return how many programs the store holds.

        Returns:
            The count.
        """
        return len(self.programs)

    def add(mut self, var program: NodeProgram) -> NodeProgramId:
        """Take ownership of a program and return the id naming it.

        Args:
            program: The program, moved in.

        Returns:
            Its id, valid for the life of the store.
        """
        self.programs.append(program^)
        return NodeProgramId(len(self.programs) - 1)

    def get(
        ref self, id: NodeProgramId
    ) raises -> ref[origin_of(self.programs[0])] NodeProgram:
        """Return the program with that id, borrowed: mutable through a
        mutable store, so `store.get(id).set_uniform(...)` changes it.

        Args:
            id: Which program.

        Returns:
            A reference to it.

        Raises:
            Error: If no program has that id.
        """
        require_index_in_count(
            id.value, len(self.programs), "No node program has that id"
        )
        return self.programs[id.value]

    def set_frame(mut self, time: Duration, view: Matrix4):
        """Write the frame's time and view into every program.

        Args:
            time: The time since the animation began.
            view: The world-to-camera matrix.
        """
        for index in range(len(self.programs)):
            self.programs[index].set_frame(time, view)


# --- the interpreter ----------------------------------------------------------
