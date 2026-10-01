# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Validate serialized surface programs before either interpreter reads them."""

from materials import nodes
from std.math import floor, isfinite, max


def _whole(value: Float32, limit: Int) raises -> Int:
    """Read a finite, nonnegative integer only after checking its range."""
    if (
        not isfinite(value)
        or value < 0
        or Float64(value) > Float64(limit)
        or floor(value) != value
    ):
        raise Error("Object JSON: a node program has an invalid integer")
    return Int(value)


def _span(first: Int, count: Int, low: Int, size: Int) raises:
    """Check a span without overflowing its endpoint."""
    if first < low or first > size or count < 0 or count > size - first:
        raise Error("Object JSON: a node program span is outside its storage")


def _contains(values: List[Int], value: Int) -> Bool:
    """Return whether a list contains one address."""
    for item in values:
        if item == value:
            return True
    return False


def _addresses(values: List[Int], low: Int, size: Int) raises:
    """Check each texture's four-float value and reject duplicate entries."""
    for index in range(len(values)):
        _span(values[index], 4, low, size)
        for prior in range(index):
            if values[prior] == values[index]:
                raise Error("Object JSON: a node texture offset is repeated")


def validate_surface_program(program: nodes.NodeProgram) raises:
    """Check the storage read by a serialized surface node program.

    Compiled graphs establish these bounds when they lay out instructions.
    A JSON file must prove them before its bytecode reaches a rasterizer.

    Args:
        program: The program read from JSON, before texture ids are replaced.

    Raises:
        Error: If an output, register, constant, matrix, custom attribute,
            uniform or texture address is outside its storage, an opcode
            cannot run on a surface, or texture metadata omits a read.
    """
    var size = len(program.code)
    if size < nodes.PROGRAM_HEADER:
        raise Error("Object JSON: a node program's code is too short")
    for value in program.code:
        if not isfinite(value):
            raise Error("Object JSON: a node program needs finite code")
    var starts = List[Int]()
    var counts = List[Int]()
    var pool = nodes.PROGRAM_HEADER
    for output in range(nodes.NODE_OUTPUT_COUNT):
        var start = _whole(program.code[output * 2], size)
        var count = _whole(program.code[output * 2 + 1], nodes.MAX_INSTRUCTIONS)
        if count > 0:
            _span(
                start,
                count * nodes.INSTRUCTION_FLOATS,
                nodes.PROGRAM_HEADER,
                size,
            )
            for prior in range(len(starts)):
                if counts[prior] > 0:
                    var prior_end = (
                        starts[prior] + counts[prior] * nodes.INSTRUCTION_FLOATS
                    )
                    if (
                        start < prior_end
                        and starts[prior]
                        < start + count * nodes.INSTRUCTION_FLOATS
                    ):
                        raise Error(
                            "Object JSON: node output instructions overlap"
                        )
            pool = max(pool, start + count * nodes.INSTRUCTION_FLOATS)
        starts.append(start)
        counts.append(count)
    if len(program.uniform_names) != len(program.uniform_offsets) or len(
        program.uniform_names
    ) != len(program.uniform_types):
        raise Error("Object JSON: node uniform metadata lengths differ")
    for index in range(len(program.uniform_names)):
        var type = program.uniform_types[index]
        if not type.is_valid() or program.uniform_names[index] == "":
            raise Error("Object JSON: invalid node uniform metadata")
        _span(
            program.uniform_offsets[index], nodes._pool_size(type), pool, size
        )
        for prior in range(index):
            if program.uniform_names[prior] == program.uniform_names[index]:
                raise Error("Object JSON: a node uniform name is repeated")
    if len(program.attribute_names) != len(program.attribute_offsets) or len(
        program.attribute_names
    ) != len(program.attribute_widths):
        raise Error("Object JSON: node attribute metadata lengths differ")
    for index in range(len(program.attribute_names)):
        var width = program.attribute_widths[index]
        if width < 1 or width > 4:
            raise Error(
                "Object JSON: a node attribute width must be one through four"
            )
        _span(
            program.attribute_offsets[index],
            width,
            0,
            nodes.MAX_ATTRIBUTE_FLOATS,
        )
    _addresses(program.texture_offsets, pool, size)
    _addresses(program.cube_offsets, pool, size)
    var graph = nodes.NodeGraph()
    for output in range(nodes.NODE_OUTPUT_COUNT):
        for instruction in range(counts[output]):
            var at = starts[output] + instruction * nodes.INSTRUCTION_FLOATS
            var kind = nodes.NodeKind(
                _whole(program.code[at], nodes.NODE_COMPUTE_RESULT.value)
            )
            if (
                kind == nodes.NODE_VARYING
                or kind == nodes.NODE_DFDX
                or kind == nodes.NODE_DFDY
                or kind == nodes.NODE_COPY
                or kind == nodes.NODE_VIEW_MATRIX
                or kind == nodes.NODE_MATRIX_COLUMNS
                or kind == nodes.NODE_MATRIX_TAIL
                or nodes._is_compute(kind)
                or kind == nodes.NODE_TEXTURE_3D
                or kind == nodes.NODE_TEXTURE_ARRAY
            ):
                raise Error(
                    "Object JSON: an opcode is not a serialized surface"
                    " instruction"
                )
            graph._check_stage(nodes.NodeOutput(output), kind)
            for slot in [
                nodes.INSTRUCTION_A,
                nodes.INSTRUCTION_B,
                nodes.INSTRUCTION_C,
                nodes.INSTRUCTION_DEST,
            ]:
                _ = _whole(program.code[at + slot], nodes.MAX_REGISTERS - 1)
            if nodes._is_attribute(kind):
                _ = _whole(
                    program.code[at + nodes.INSTRUCTION_C],
                    nodes.NODE_CONTEXT_COUNT - 1,
                )
            var immediate = _whole(
                program.code[at + nodes.INSTRUCTION_IMMEDIATE], (1 << 24) - 1
            )
            if kind == nodes.NODE_CONSTANT or kind == nodes.NODE_UNIFORM:
                _span(immediate, 4, pool, size)
            elif (
                kind == nodes.NODE_MATRIX_VECTOR
                or kind == nodes.NODE_VECTOR_MATRIX
            ):
                var width = immediate % 8
                if width != 3 and width != 4:
                    raise Error(
                        "Object JSON: a node matrix must be three or four wide"
                    )
                var first = immediate // 8
                _span(
                    first,
                    width * width,
                    nodes.PROGRAM_VIEW if first == nodes.PROGRAM_VIEW else pool,
                    size,
                )
            elif (
                kind == nodes.NODE_TEXTURE
                or kind == nodes.NODE_TEXTURE_LEVEL
                or kind == nodes.NODE_TEXEL_FETCH
                or kind == nodes.NODE_TEXTURE_SIZE
            ):
                if not _contains(program.texture_offsets, immediate):
                    raise Error(
                        "Object JSON: a texture instruction lacks its offset"
                    )
            elif kind == nodes.NODE_TEXTURE_CUBE:
                if not _contains(program.cube_offsets, immediate):
                    raise Error(
                        "Object JSON: a cube instruction lacks its offset"
                    )
            elif kind == nodes.NODE_ATTRIBUTE:
                var width = immediate // 8
                if width < 1 or width > 4:
                    raise Error(
                        "Object JSON: invalid node attribute instruction width"
                    )
                _span(immediate % 8, width, 0, nodes.MAX_ATTRIBUTE_FLOATS)
            elif kind == nodes.NODE_JOIN:
                var a = immediate % 5
                var b = (immediate // 5) % 5
                var c = immediate // 25
                if a + b + c > 4 or a + b + c < 1:
                    raise Error("Object JSON: a node join exceeds four lanes")
            elif kind == nodes.NODE_INTERPOLATE:
                _ = _whole(Float32(immediate), nodes.NODE_CONTEXT_COUNT - 1)
            elif (
                kind == nodes.NODE_CELL_NOISE
                or kind == nodes.NODE_CELL_NOISE_VEC3
                or kind == nodes.NODE_DOT
                or kind == nodes.NODE_LENGTH
                or kind == nodes.NODE_NORMALIZE
                or kind == nodes.NODE_DISTANCE
                or kind == nodes.NODE_REFLECT
                or kind == nodes.NODE_REFRACT
                or kind == nodes.NODE_FACEFORWARD
            ):
                if immediate < 1 or immediate > 4:
                    raise Error(
                        "Object JSON: a node vector width must be one through"
                        " four"
                    )
            elif kind == nodes.NODE_NOISE or kind == nodes.NODE_NOISE_VEC3:
                if immediate != 2 and immediate != 3:
                    raise Error(
                        "Object JSON: a Perlin node needs two or three lanes"
                    )
            elif kind == nodes.NODE_WORLEY:
                if (
                    (immediate % 4 != 2 and immediate % 4 != 3)
                    or immediate // 4 < 1
                    or immediate // 4 > 3
                ):
                    raise Error("Object JSON: a Worley node has invalid widths")
            elif (
                kind == nodes.NODE_VIEWPORT_TEXTURE and not program.reads_scene
            ):
                raise Error(
                    "Object JSON: a viewport texture must declare readsScene"
                )
