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


def _sampler_spans(
    program: nodes.NodeProgram, offsets: List[Int], expected: nodes.ValueType
) raises:
    """Keep sampler ids out of numeric uniforms that can overwrite them."""
    for address in offsets:
        for index in range(len(program.uniform_offsets)):
            var first = program.uniform_offsets[index]
            var type = program.uniform_types[index]
            if address < first + nodes._pool_size(type) and first < address + 4:
                if address != first or type != expected:
                    raise Error(
                        "Object JSON: a sampler overlaps a uniform of another"
                        " type"
                    )


def _payload_span(
    mut types: List[Int],
    mut starts: List[Int],
    first: Int,
    count: Int,
    type: Int = -1,
) raises:
    """Mark checked data words, keeping integer bits separate from floats.

    Zero means unclassified, minus one means ordinary finite float data,
    and a positive value is an exact integer ValueType. Integer aliases
    must name the same complete value with the same type.
    """
    for offset in range(count):
        var at = first + offset
        var before = types[at]
        if before != 0 and (before > 0 or type > 0):
            if before != type or starts[at] != first:
                raise Error(
                    "Object JSON: integer payload spans overlap another type"
                )
        types[at] = type
        starts[at] = first


def _integer_arity(kind: nodes.NodeKind) -> Int:
    """Return the input count for a validated exact integer opcode."""
    if kind == nodes.NODE_UINT_CLAMP or kind == nodes.NODE_INT_CLAMP:
        return 3
    if (
        kind == nodes.NODE_UINT_NEGATE
        or kind == nodes.NODE_UINT_BIT_NOT
        or kind == nodes.NODE_INT_NEGATE
        or kind == nodes.NODE_INT_BIT_NOT
        or (
            kind.value >= nodes.NODE_TO_UINT.value
            and kind.value <= nodes.NODE_UINT_LAST.value
        )
        or kind.value >= nodes.NODE_TO_INT.value
    ):
        return 1
    return 2


def _read_register(written: List[Bool], register: Int) raises:
    """Require a new instruction's input to have an earlier producer."""
    if not written[register]:
        raise Error("Object JSON: an integer or gradient input has no producer")


def _integer_instruction(
    kind: nodes.NodeKind,
    a: Int,
    b: Int,
    c: Int,
    immediate: Int,
    written: List[Bool],
) raises:
    """Check operand arity and the optional unary width of integer code."""
    var arity = _integer_arity(kind)
    _read_register(written, a)
    if arity >= 2:
        _read_register(written, b)
    elif b != 0:
        raise Error(
            "Object JSON: an integer unary instruction has a second input"
        )
    if arity == 3:
        _read_register(written, c)
    elif c != 0:
        raise Error("Object JSON: an integer instruction has an extra input")
    var width = (
        kind == nodes.NODE_UINT_NEGATE
        or kind == nodes.NODE_UINT_BIT_NOT
        or kind == nodes.NODE_INT_NEGATE
        or kind == nodes.NODE_INT_BIT_NOT
        or kind == nodes.NODE_INT_ABS
        or kind == nodes.NODE_INT_SIGN
    )
    if (width and (immediate < 1 or immediate > 4)) or (
        not width and immediate != 0
    ):
        raise Error(
            "Object JSON: an integer instruction has an invalid immediate"
        )


def validate_surface_program(program: nodes.NodeProgram) raises:
    """Check the storage read by a serialized surface node program.

    Compiled graphs establish these bounds when they lay out instructions.
    A JSON file must prove them before its bytecode reaches a rasterizer.

    Args:
        program: The program read from JSON, before texture ids are replaced.

    Raises:
        Error: If an output, register, constant, matrix, custom attribute,
            uniform or texture address is outside its storage, an opcode
            cannot run on a surface, texture metadata omits a read, integer
            metadata aliases another type, or a new opcode has invalid
            operands. Only declared integer data can hold nonfinite bits.
    """
    var size = len(program.code)
    if size < nodes.PROGRAM_HEADER:
        raise Error("Object JSON: a node program's code is too short")
    # Control words stay finite even when the pool contains integer bits.
    for index in range(nodes.PROGRAM_HEADER):  # pragma: no branch
        if not isfinite(program.code[index]):
            raise Error("Object JSON: a node program needs finite code")
    var starts = List[Int]()
    var counts = List[Int]()
    var pool = nodes.PROGRAM_HEADER
    # The serialized header always has NODE_OUTPUT_COUNT output entries.
    for output in range(nodes.NODE_OUTPUT_COUNT):  # pragma: no branch
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
    var payload_types = List[Int](length=size, fill=0)
    var payload_starts = List[Int](length=size, fill=-1)
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
            var before = program.uniform_offsets[prior]
            var first = program.uniform_offsets[index]
            if first < before + nodes._pool_size(
                program.uniform_types[prior]
            ) and before < first + nodes._pool_size(type):
                raise Error("Object JSON: node uniform spans overlap")
            if program.uniform_names[prior] == program.uniform_names[index]:
                raise Error("Object JSON: a node uniform name is repeated")
        _payload_span(
            payload_types,
            payload_starts,
            program.uniform_offsets[index],
            nodes._pool_size(type),
            type.value if type.is_integer() else -1,
        )
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
        for prior in range(index):
            if program.attribute_names[prior] == program.attribute_names[index]:
                raise Error("Object JSON: a node attribute name is repeated")
    _addresses(program.texture_offsets, pool, size)
    _addresses(program.cube_offsets, pool, size)
    _sampler_spans(program, program.texture_offsets, nodes.NODE_SAMPLER)
    _sampler_spans(program, program.cube_offsets, nodes.NODE_SAMPLER_CUBE)
    for address in program.texture_offsets:
        _payload_span(payload_types, payload_starts, address, 4)
    for address in program.cube_offsets:
        _payload_span(payload_types, payload_starts, address, 4)
    for texture in program.texture_offsets:
        for cube in program.cube_offsets:
            if texture < cube + 4 and cube < texture + 4:
                raise Error(
                    "Object JSON: texture and cube sampler spans overlap"
                )
    var graph = nodes.NodeGraph()
    # The serialized header always has NODE_OUTPUT_COUNT output entries.
    for output in range(nodes.NODE_OUTPUT_COUNT):  # pragma: no branch
        var written = List[Bool](length=nodes.MAX_REGISTERS, fill=False)
        for instruction in range(counts[output]):
            var at = starts[output] + instruction * nodes.INSTRUCTION_FLOATS
            for slot in range(nodes.INSTRUCTION_FLOATS):  # pragma: no branch
                if not isfinite(program.code[at + slot]):
                    raise Error("Object JSON: a node program needs finite code")
            var kind = nodes.NodeKind(
                _whole(program.code[at], nodes.NODE_INT_LAST.value)
            )
            if not kind.is_valid():
                raise Error(
                    "Object JSON: an opcode is not a serialized surface"
                    " instruction"
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
            # Every instruction has these four register slots.
            for slot in [
                nodes.INSTRUCTION_A,
                nodes.INSTRUCTION_B,
                nodes.INSTRUCTION_C,
                nodes.INSTRUCTION_DEST,
            ]:  # pragma: no branch
                _ = _whole(program.code[at + slot], nodes.MAX_REGISTERS - 1)
            if nodes._is_attribute(kind):
                _ = _whole(
                    program.code[at + nodes.INSTRUCTION_C],
                    nodes.NODE_CONTEXT_COUNT - 1,
                )
            var immediate = _whole(
                program.code[at + nodes.INSTRUCTION_IMMEDIATE], (1 << 24) - 1
            )
            var a = Int(program.code[at + nodes.INSTRUCTION_A])
            var b = Int(program.code[at + nodes.INSTRUCTION_B])
            var c = Int(program.code[at + nodes.INSTRUCTION_C])
            var dest = Int(program.code[at + nodes.INSTRUCTION_DEST])
            if kind.value >= nodes.NODE_UINT_FIRST.value:
                _integer_instruction(kind, a, b, c, immediate, written)
            elif kind == nodes.NODE_TEXTURE_GRAD:
                if b != 0:
                    raise Error(
                        "Object JSON: a texture gradient has an extra input"
                    )
                _read_register(written, a)
                _read_register(written, c)
            written[dest] = True
            if kind == nodes.NODE_CONSTANT or kind == nodes.NODE_UNIFORM:
                _span(immediate, 4, pool, size)
                if kind == nodes.NODE_UNIFORM and not _contains(
                    program.uniform_offsets, immediate
                ):
                    raise Error(
                        "Object JSON: a uniform instruction lacks its offset"
                    )
                if a != 0 or c != 0:
                    raise Error("Object JSON: a constant or uniform has inputs")
                if kind == nodes.NODE_CONSTANT:
                    if b > 8:
                        raise Error(
                            "Object JSON: invalid integer constant type tag"
                        )
                    _payload_span(
                        payload_types,
                        payload_starts,
                        immediate,
                        4,
                        40 + b if b > 0 else -1,
                    )
                elif b != 0:
                    raise Error(
                        "Object JSON: a uniform has a constant type tag"
                    )
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
                if first == nodes.PROGRAM_VIEW:
                    _span(
                        first,
                        width * width,
                        nodes.PROGRAM_VIEW,
                        nodes.PROGRAM_VIEW + 16,
                    )
                else:
                    _span(first, width * width, pool, size)
                    _payload_span(
                        payload_types, payload_starts, first, width * width
                    )
            elif (
                kind == nodes.NODE_TEXTURE
                or kind == nodes.NODE_TEXTURE_LEVEL
                or kind == nodes.NODE_TEXTURE_GRAD
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
    # Unused words and gaps remain finite too. An integer declaration can
    # exempt only a checked four-word data span, never control or float data.
    for index in range(size):  # pragma: no branch
        if payload_types[index] <= 0 and not isfinite(program.code[index]):
            raise Error("Object JSON: a node program needs finite code")
