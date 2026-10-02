# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node material's program as JSON, three.js's node material JSON as this
port has it: what `exporters.object_json` writes in a material's `nodes`
field, and what `loaders.object_loader` reads back.

three.js writes each node of the graph with its own type and inputs. This
port writes the compiled program instead: its floats, its uniforms, its
custom attributes, and where it keeps the id of each texture and cube it
reads. A texture is written as the uuid of its entry in the file's
`textures` list, so the loader can give the program the id the texture gets
in its own store. three.js's loaders read the other fields of the material
and leave this one alone.
"""

from exporters.json_writer import JsonWriter
from loaders.json import JsonDocument
from materials.nodes import PROGRAM_HEADER, NodeProgram, ValueType
from materials.node_validation import validate_surface_program


@fieldwise_init
struct NodeProgramJson(Movable):
    """A program read from JSON, and the textures and cubes it reads by the
    uuids of their entries, for the loader to put ids in place of."""

    var program: NodeProgram
    # Where the program keeps a texture's id, and the uuid of that texture.
    var texture_offsets: List[Int]
    var texture_uuids: List[String]
    # The same of the cubes.
    var cube_offsets: List[Int]
    var cube_uuids: List[String]


def write_node_program(
    mut writer: JsonWriter,
    program: NodeProgram,
    textures: List[String],
    cubes: List[String],
) raises:
    """Write a program as a JSON object.

    Args:
        writer: Where the object goes, after its key.
        program: The program.
        textures: The uuid of the texture each of `program.texture_offsets`
            names, or an empty string for a texture uniform that names none.
        cubes: The same of `program.cube_offsets`.

    Raises:
        Error: If the program reads a 3D or an array texture, which object
            JSON does not write, or a list is not as long as its offsets.
    """
    if len(program.volume_offsets) > 0 or len(program.array_offsets) > 0:
        raise Error(
            "Object JSON: a node program that reads a 3D or an array texture"
            " is not written"
        )
    if len(textures) != len(program.texture_offsets) or len(cubes) != len(
        program.cube_offsets
    ):
        raise Error("Object JSON: a node program's textures do not match it")
    writer.begin_object()
    writer.key("code")
    writer.begin_array()
    # A compiled program holds its header, so the loop runs.
    for index in range(len(program.code)):  # pragma: no branch
        writer.number(program.code[index])
    writer.end_array()
    writer.key("uniforms")
    writer.begin_array()
    for index in range(len(program.uniform_names)):
        writer.begin_object()
        writer.key("name")
        writer.string(program.uniform_names[index])
        writer.key("offset")
        writer.integer(program.uniform_offsets[index])
        writer.key("type")
        writer.integer(program.uniform_types[index].value)
        writer.end_object()
    writer.end_array()
    _places(writer, "textures", program.texture_offsets, textures)
    _places(writer, "cubes", program.cube_offsets, cubes)
    writer.key("attributes")
    writer.begin_array()
    for index in range(len(program.attribute_names)):
        writer.begin_object()
        writer.key("name")
        writer.string(program.attribute_names[index])
        writer.key("offset")
        writer.integer(program.attribute_offsets[index])
        writer.key("width")
        writer.integer(program.attribute_widths[index])
        writer.end_object()
    writer.end_array()
    writer.key("readsScene")
    writer.boolean(program.reads_scene)
    writer.end_object()


def _places(
    mut writer: JsonWriter,
    key: String,
    offsets: List[Int],
    uuids: List[String],
) raises:
    """Write where a program keeps each texture's id and the texture's
    uuid, `null` for none."""
    writer.key(key)
    writer.begin_array()
    for index in range(len(offsets)):
        writer.begin_object()
        writer.key("offset")
        writer.integer(offsets[index])
        writer.key("uuid")
        if uuids[index] == "":
            writer.null()
        else:
            writer.string(uuids[index])
        writer.end_object()
    writer.end_array()


def read_node_program(
    document: JsonDocument, item: Int
) raises -> NodeProgramJson:
    """Read a program `write_node_program` wrote.

    Every texture and cube the program reads names none until the caller
    puts the ids of `texture_uuids` and `cube_uuids` at their offsets and
    calls `NodeProgram.list_maps`.

    Args:
        document: The parsed file.
        item: The program's object.

    Returns:
        The program, and the uuids of what it reads.

    Raises:
        Error: If a field is missing or of the wrong kind, the code is
            shorter than a program's header, a uniform's type is none there
            is, or an offset is outside the program.
    """
    var program = NodeProgram()
    var code = document.get(item, "code")
    if document.length(code) < PROGRAM_HEADER:
        raise Error("Object JSON: a node program's code is too short")
    program.code = List[Float32](capacity=document.length(code))
    # At least a header, as asked above, so the loop runs.
    for index in range(document.length(code)):  # pragma: no branch
        program.code.append(Float32(document.number(document.at(code, index))))
    var uniforms = document.get(item, "uniforms")
    for index in range(document.length(uniforms)):
        var entry = document.at(uniforms, index)
        var type = ValueType(document.integer(document.get(entry, "type")))
        if not type.is_valid():
            raise Error("Object JSON: a node uniform's type is none there is")
        program.uniform_names.append(
            document.string(document.get(entry, "name"))
        )
        program.uniform_offsets.append(
            _offset(document, entry, len(program.code))
        )
        program.uniform_types.append(type)
    var textures = _read_places(document, item, "textures", len(program.code))
    var cubes = _read_places(document, item, "cubes", len(program.code))
    program.texture_offsets = textures[0].copy()
    program.cube_offsets = cubes[0].copy()
    var attributes = document.get(item, "attributes")
    for index in range(document.length(attributes)):
        var entry = document.at(attributes, index)
        program.attribute_names.append(
            document.string(document.get(entry, "name"))
        )
        program.attribute_offsets.append(
            document.integer(document.get(entry, "offset"))
        )
        program.attribute_widths.append(
            document.integer(document.get(entry, "width"))
        )
    program.reads_scene = document.boolean(document.get(item, "readsScene"))
    validate_surface_program(program)
    # Every read names nothing until the loader says which texture it is.
    for index in range(len(program.texture_offsets)):
        program.code[program.texture_offsets[index]] = -1
    for index in range(len(program.cube_offsets)):
        program.code[program.cube_offsets[index]] = -1
    program.list_maps()
    return NodeProgramJson(
        program^,
        textures[0].copy(),
        textures[1].copy(),
        cubes[0].copy(),
        cubes[1].copy(),
    )


def _offset(document: JsonDocument, entry: Int, size: Int) raises -> Int:
    """Return an entry's `offset`, once it is known to be inside a program
    of `size` floats."""
    var at = document.integer(document.get(entry, "offset"))
    if at < 0 or at >= size:
        raise Error("Object JSON: a node program's offset is outside it")
    return at


def _read_places(
    document: JsonDocument, item: Int, key: String, size: Int
) raises -> Tuple[List[Int], List[String]]:
    """Return where a program keeps each texture's id, and each texture's
    uuid, an empty string for none."""
    var offsets = List[Int]()
    var uuids = List[String]()
    var list = document.get(item, key)
    for index in range(document.length(list)):
        var entry = document.at(list, index)
        offsets.append(_offset(document, entry, size))
        var uuid = document.get(entry, "uuid")
        uuids.append("" if document.is_null(uuid) else document.string(uuid))
    return (offsets^, uuids^)
