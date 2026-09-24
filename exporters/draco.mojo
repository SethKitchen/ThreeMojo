# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh or a point cloud written as a Draco file: three.js's
`DRACOExporter`, and the other half of `loaders.draco`.

three.js hands the geometry to Draco's own encoder, compiled to
WebAssembly. This module and the four beside it port that encoder, from
Draco 1.5.6, the version of the `draco3d` package that three.js 0.180
runs, and they write the same bytes.

- `export_draco` turns a geometry into the bytes of a `.drc` file, as
  `DRACOExporter.parse` does for a `Mesh` or a `Points`.
- `write_draco` writes the file.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**The options** are three.js's. `encode_speed` and `decode_speed` pick
the compression: the larger of the two is Draco's speed, from 0, the
smallest file, to 10, the fastest. `encoder_method` picks Edgebreaker or
sequential connectivity for a mesh, and a KD-tree or a sequence for a
point cloud. `quantization` gives the bits of `POSITION`, `NORMAL`,
`COLOR`, `TEX_COORD` and `GENERIC`, in that order; zero or less stores
the floats as they are. `export_uvs`, `export_normals` and `export_color`
pick the attributes.

**What is written.** A mesh's `position`, and its `normal`, `uv` and
`color` when they are asked for and there. A point cloud's `position`,
and its `color`. A color is converted from linear to sRGB first, as
three.js converts it. Draco merges equal values and equal points before
it encodes, and so does this.

**Where this port differs.** three.js passes a geometry without an index
to Draco as one triangle for each vertex, and Draco reads the missing
two thirds of the index from memory past the end of the array. The file
then depends on what that memory holds. This port writes one triangle for
each three vertices, as three.js means to. The WebAssembly encoder runs
out of memory for some geometries quantized to more than 24 bits; this
port writes them. three.js passes Draco any item size; this port refuses
a `position` or `normal` that is not three components, a `uv` that is
not two, a `color` that is not three or four, a geometry without
vertices, and an attribute whose count is not the position's.

**What is refused**, as three.js throws: a geometry without positions;
a quantization above 30 bits, or of one bit for normals; a value to
quantize that is not finite; a KD-tree for a point cloud with an
attribute that is not quantized; and a mesh whose triangles all repeat a
vertex, for Edgebreaker. A speed outside 0 to 10 and an encoder method or
object kind that is not known are refused too.
"""

from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from exporters.draco_connectivity import (
    EdgebreakerData,
    EncodingData,
    encode_edgebreaker,
    traverse,
)
from exporters.draco_kd_tree import encode_kd_tree
from exporters.draco_predict import (
    EncoderAttribute,
    MeshData,
    Positions,
    Quantization,
    encode_integers,
    octahedral,
    quantization_of,
    quantize,
)
from exporters.draco_writer import DracoWriter
from loaders.draco import (
    DRACO_COMPRESSED,
    DRACO_NORMALS,
    DRACO_POINT_CLOUD,
    DRACO_QUANTIZED,
    DRACO_RAW,
    DRACO_SEQUENTIAL,
    DRACO_TRIANGULAR_MESH,
    DracoAttributeCoding,
    DracoEncoding,
    DracoGeometryType,
    sequential_index_width,
)
from loaders.draco_attributes import (
    DRACO_COLOR,
    DRACO_CONSTRAINED_MULTI_PARALLELOGRAM,
    DRACO_DIFFERENCE,
    DRACO_FLOAT32,
    DRACO_GEOMETRIC_NORMAL,
    DRACO_NORMAL,
    DRACO_PARALLELOGRAM,
    DRACO_POSITION,
    DRACO_TEX_COORD,
    DRACO_TEX_COORDS_PORTABLE,
    DracoAttributeType,
    DracoPrediction,
)
from loaders.draco_buffer import MASK32, draco_require
from loaders.draco_mesh import (
    DRACO_DEPTH_FIRST,
    DRACO_PREDICTION_DEGREE,
    DRACO_STANDARD_TRAVERSAL,
    DRACO_VALENCE_TRAVERSAL,
    NONE,
    DracoTraversalMethod,
)
from loaders.js_number import js_pow
from loaders.vrml_geometry import product
from std.collections import Dict
from std.memory import bitcast
from std.pathlib import Path


@fieldwise_init
struct DracoEncoderMethod(Equatable, ImplicitlyCopyable, Writable):
    """How Draco codes the connectivity, as a type rather than a bare int.

    three.js's `DRACOExporter.MESH_SEQUENTIAL_ENCODING` and
    `MESH_EDGEBREAKER_ENCODING`. `export_draco` refuses one that is not
    valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the sequential and the Edgebreaker method.

        Returns:
            True for the two methods three.js names.
        """
        return self == DRACO_MESH_SEQUENTIAL_ENCODING or (
            self == DRACO_MESH_EDGEBREAKER_ENCODING
        )


# The triangles or the points in order.
comptime DRACO_MESH_SEQUENTIAL_ENCODING = DracoEncoderMethod(0)
# Edgebreaker for a mesh, a KD-tree for a point cloud: three.js's default.
comptime DRACO_MESH_EDGEBREAKER_ENCODING = DracoEncoderMethod(1)


@fieldwise_init
struct DracoObjectKind(Equatable, ImplicitlyCopyable, Writable):
    """What the geometry is drawn as, as a type rather than a bare int.

    three.js's `DRACOExporter.parse` takes a `Mesh` or a `Points`.
    `export_draco` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for a mesh and for points.

        Returns:
            True for the two objects three.js exports.
        """
        return self == DRACO_EXPORT_MESH or self == DRACO_EXPORT_POINTS


# Triangles: three.js's `Mesh`.
comptime DRACO_EXPORT_MESH = DracoObjectKind(0)
# A point cloud: three.js's `Points`.
comptime DRACO_EXPORT_POINTS = DracoObjectKind(1)


struct DracoExportOptions(Copyable, Movable):
    """The options of three.js's `DRACOExporter.parse`, with its defaults."""

    var decode_speed: Int
    """How fast the file decodes, from 0 to 10."""
    var encode_speed: Int
    """How fast the file encodes, from 0 to 10."""
    var encoder_method: DracoEncoderMethod
    """Edgebreaker or sequential."""
    var quantization: List[Int]
    """The bits of `POSITION`, `NORMAL`, `COLOR`, `TEX_COORD` and
    `GENERIC`. A missing entry, or zero or less, stores the floats."""
    var export_uvs: Bool
    """Whether a mesh writes its `uv`."""
    var export_normals: Bool
    """Whether a mesh writes its `normal`."""
    var export_color: Bool
    """Whether the geometry writes its `color`."""

    def __init__(
        out self,
        *,
        decode_speed: Int = 5,
        encode_speed: Int = 5,
        encoder_method: DracoEncoderMethod = DRACO_MESH_EDGEBREAKER_ENCODING,
        var quantization: List[Int] = [16, 8, 8, 8, 8],
        export_uvs: Bool = True,
        export_normals: Bool = True,
        export_color: Bool = False,
    ):
        """Make options; each defaults to three.js's default.

        Args:
            decode_speed: How fast the file decodes, from 0 to 10.
            encode_speed: How fast the file encodes, from 0 to 10.
            encoder_method: Edgebreaker or sequential.
            quantization: The bits of each attribute type.
            export_uvs: Whether a mesh writes its `uv`.
            export_normals: Whether a mesh writes its `normal`.
            export_color: Whether the geometry writes its `color`.
        """
        self.decode_speed = decode_speed
        self.encode_speed = encode_speed
        self.encoder_method = encoder_method
        self.quantization = quantization^
        self.export_uvs = export_uvs
        self.export_normals = export_normals
        self.export_color = export_color

    def speed(self) -> Int:
        """Return Draco's speed: the larger of the two.

        Returns:
            The speed.
        """
        return max(self.encode_speed, self.decode_speed)

    def bits(self, attribute_type: DracoAttributeType) -> Int:
        """Return the quantization bits of an attribute type.

        Args:
            attribute_type: The type.

        Returns:
            The bits, or -1 when the options give none.
        """
        if attribute_type.value < len(self.quantization):
            return self.quantization[attribute_type.value]
        return -1


def _linear_to_srgb(c: Float64) -> Float64:
    """three.js's `LinearToSRGB`, with V8's `Math.pow`."""
    if c < 0.0031308:
        return product(c, 12.92)
    return product(1.055, js_pow(c, 0.41666)) - 0.055


def _srgb_colors(values: List[Float32], components: Int) -> List[Float32]:
    """three.js's `createVertexColorSRGBArray`: red, green and blue from
    linear to sRGB, and alpha kept."""
    var out = values.copy()
    # A color has a value for each vertex, and there is one.
    for i in range(len(values)):  # pragma: no branch
        if i % components < 3:
            out[i] = Float32(_linear_to_srgb(Float64(values[i])))
    return out^


struct _Geometry(Movable):
    """The geometry Draco's encoder is given: points, attributes, and
    triangles for a mesh."""

    var points: Int
    var faces: List[Int]
    var attributes: List[EncoderAttribute]

    def __init__(out self, points: Int):
        self.points = points
        self.faces = List[Int]()
        self.attributes = List[EncoderAttribute]()

    def add(
        mut self,
        geometry: BufferGeometry,
        name: String,
        attribute_type: DracoAttributeType,
        components: Int,
    ) raises:
        """Add a geometry attribute, as three.js's `AddFloatAttribute`."""
        ref view = geometry.attribute_view(name)
        draco_require(
            view.item_size == components,
            "a "
            + name
            + " attribute has "
            + String(view.item_size)
            + " components",
        )
        draco_require(
            view.count() == self.points,
            "a " + name + " attribute does not have one value for each vertex",
        )
        var values = view.packed()
        if attribute_type == DRACO_COLOR:
            values = _srgb_colors(values, components)
        self.attributes.append(
            EncoderAttribute(attribute_type, components, values^)
        )

    def deduplicate(mut self):
        """Draco's `DeduplicateAttributeValues` and
        `DeduplicatePointIds`: equal values, by their bits, and then
        points with equal values, merged in the order they first come."""
        # There is a position attribute: the loop runs.
        for i in range(len(self.attributes)):  # pragma: no branch
            _deduplicate_values(self.attributes[i])
        var keys = Dict[String, Int]()
        var point_of = List[Int](capacity=self.points)
        var firsts = List[Int]()
        # A geometry has a vertex: the loop runs.
        for p in range(self.points):  # pragma: no branch
            var key = String()
            # There is a position attribute: the loop runs.
            for a in self.attributes:  # pragma: no branch
                key += String(a.point_map[p]) + ","
            var found = keys.get(key, NONE)
            if found == NONE:
                keys[key] = len(firsts)
                point_of.append(len(firsts))
                firsts.append(p)
            else:
                point_of.append(found)
        if len(firsts) == self.points:
            return
        # There is a position attribute: the loop runs.
        for i in range(len(self.attributes)):  # pragma: no branch
            var map = List[Int](capacity=len(firsts))
            # A geometry has a vertex: the loop runs.
            for p in firsts:  # pragma: no branch
                map.append(self.attributes[i].point_map[p])
            self.attributes[i].point_map = map^
        for c in range(len(self.faces)):
            self.faces[c] = point_of[self.faces[c]]
        self.points = len(firsts)


def _deduplicate_values(mut attribute: EncoderAttribute):
    """Draco's `DeduplicateFormattedValues`: each value that equals an
    earlier one, bit for bit, is replaced by it."""
    var keys = Dict[String, Int]()
    var new_values = List[Float32]()
    var value_of = List[Int](capacity=attribute.count())
    var components = attribute.components
    # An attribute has a value for each vertex, and there is one.
    for v in range(attribute.count()):  # pragma: no branch
        var key = String()
        # An attribute has components: the loop runs.
        for c in range(components):  # pragma: no branch
            key += String(Int(bitcast[DType.uint32](attribute.at(v, c)))) + ","
        var found = keys.get(key, NONE)
        if found == NONE:
            found = len(new_values) // components
            keys[key] = found
            # An attribute has components: the loop runs.
            for c in range(components):  # pragma: no branch
                new_values.append(attribute.at(v, c))
        value_of.append(found)
    if len(new_values) == len(attribute.values):
        return
    # A geometry has a vertex: the loop runs.
    for p in range(len(attribute.point_map)):  # pragma: no branch
        attribute.point_map[p] = value_of[attribute.point_map[p]]
    attribute.values = new_values^


def _header(
    mut out: DracoWriter,
    geometry_type: DracoGeometryType,
    encoding: DracoEncoding,
):
    """Draco's `EncodeHeader`: the magic, the bitstream version, the
    geometry, the method and no flags."""
    out.append([UInt8(68), UInt8(82), UInt8(65), UInt8(67), UInt8(79)])
    out.u8(2)
    if geometry_type == DRACO_POINT_CLOUD:
        out.u8(3)
    else:
        out.u8(2)
    out.u8(geometry_type.value)
    out.u8(encoding.value)
    out.u16(0)


struct _Encoder(Movable):
    """The state of Draco's encoder while it writes one geometry."""

    var geometry: _Geometry
    var options: DracoExportOptions
    var out: DracoWriter
    var positions: Optional[Positions]

    def __init__(
        out self, var geometry: _Geometry, var options: DracoExportOptions
    ):
        self.geometry = geometry^
        self.options = options^
        self.out = DracoWriter()
        self.positions = None

    def coding(self, index: Int) -> DracoAttributeCoding:
        """Draco's `CreateSequentialEncoder`: floats with quantization
        bits are quantized, or folded for normals; the rest are raw."""
        ref attribute = self.geometry.attributes[index]
        if self.options.bits(attribute.attribute_type) <= 0:
            return DRACO_RAW
        if attribute.attribute_type == DRACO_NORMAL:
            return DRACO_NORMALS
        return DRACO_QUANTIZED

    def write_descriptions(mut self, ids: List[Int], codings: Bool):
        """Draco's `EncodeAttributesEncoderData`: each attribute's type,
        data type, components, normalization and unique id, then each
        one's coding when the encoder is sequential."""
        self.out.varint(len(ids))
        # An encoder has an attribute: the loop runs.
        for id in ids:  # pragma: no branch
            ref attribute = self.geometry.attributes[id]
            self.out.u8(attribute.attribute_type.value)
            self.out.u8(DRACO_FLOAT32.value)
            self.out.u8(attribute.components)
            self.out.u8(0)
            self.out.varint(id)
        if not codings:
            return
        # An encoder has an attribute: the loop runs.
        for id in ids:  # pragma: no branch
            self.out.u8(self.coding(id).value)

    def prediction(self, index: Int, mesh: Bool) -> DracoPrediction:
        """Draco's `SelectPredictionMethod`, and the fallback to the
        difference where the mesh prediction cannot run."""
        var speed = self.options.speed()
        if speed >= 10 or not mesh:
            return DRACO_DIFFERENCE
        ref attribute = self.geometry.attributes[index]
        var bits = self.options.bits(attribute.attribute_type)
        var position_bits = self.options.bits(DRACO_POSITION)
        # Draco also asks for two components, which a `uv` always has.
        if attribute.attribute_type == DRACO_TEX_COORD:
            if (
                position_bits > 0
                and position_bits <= 21
                and 2 * position_bits + bits < 64
                and speed < 4
            ):
                return DRACO_TEX_COORDS_PORTABLE
        if attribute.attribute_type == DRACO_NORMAL:
            if speed < 4 and position_bits > 0:
                return DRACO_GEOMETRIC_NORMAL
            return DRACO_DIFFERENCE
        if speed >= 8:
            return DRACO_DIFFERENCE
        if speed >= 2 or self.geometry.points < 40:
            return DRACO_PARALLELOGRAM
        return DRACO_CONSTRAINED_MULTI_PARALLELOGRAM

    def encode_values(
        mut self,
        ids: List[Int],
        points: List[Int],
        mesh: List[Optional[MeshData]],
    ) raises:
        """Draco's `SequentialAttributeEncodersController::EncodeAttributes`
        for one encoder: each attribute's values in the order of
        `points`, then each one's quantization or normal bits."""
        var level = 10 - self.options.speed()
        var settings = List[Optional[Quantization]]()
        # An encoder has an attribute: the loop runs.
        for i in range(len(ids)):  # pragma: no branch
            var id = ids[i]
            var coding = self.coding(id)
            ref attribute = self.geometry.attributes[id]
            settings.append(None)
            if coding == DRACO_RAW:
                # A geometry has a vertex: the loop runs.
                for p in points:  # pragma: no branch
                    var value = attribute.point_map[p]
                    for c in range(attribute.components):  # pragma: no branch
                        self.out.f32(attribute.at(value, c))
                continue
            var bits = self.options.bits(attribute.attribute_type)
            var values: List[Int]
            var components = attribute.components
            var normal_bits = 0
            if coding == DRACO_NORMALS:
                values = octahedral(attribute, bits, points)
                components = 2
                normal_bits = bits
            else:
                var q = quantization_of(attribute, bits)
                values = quantize(attribute, q, points)
                settings[i] = q^
            var method = self.prediction(id, Bool(mesh[i]))
            var data = mesh[i].copy()
            if method == DRACO_DIFFERENCE:
                data = None
            var positions: Optional[Positions] = None
            if (
                method == DRACO_TEX_COORDS_PORTABLE
                or method == DRACO_GEOMETRIC_NORMAL
            ):
                positions = self.positions.copy()
            encode_integers(
                self.out,
                values,
                components,
                method,
                normal_bits,
                data,
                positions,
                level,
            )
            if attribute.attribute_type == DRACO_POSITION:
                self.positions = _portable_positions(
                    attribute, values, points, self.geometry.points
                )
        # An encoder has an attribute: the loop runs.
        for i in range(len(ids)):  # pragma: no branch
            if Bool(settings[i]):
                settings[i].value().write(self.out)
            elif self.coding(ids[i]) == DRACO_NORMALS:
                self.out.u8(
                    self.options.bits(
                        self.geometry.attributes[ids[i]].attribute_type
                    )
                )


def _portable_positions(
    attribute: EncoderAttribute,
    values: List[Int],
    points: List[Int],
    count: Int,
) -> Positions:
    """Draco's portable position attribute of a parent encoder: each
    point maps to the last stored position of its value."""
    var stored = List[Int](length=attribute.count(), fill=0)
    # A geometry has a vertex: the loop runs.
    for i in range(len(points)):  # pragma: no branch
        stored[attribute.point_map[points[i]]] = i
    var map = List[Int](capacity=count)
    # A geometry has a vertex: the loop runs.
    for p in range(count):  # pragma: no branch
        map.append(stored[attribute.point_map[p]])
    return Positions(values.copy(), map^)


def write_sequential_index(mut out: DracoWriter, index: Int, width: Int):
    """Write one point index of a sequential mesh.

    Draco's `MeshSequentialEncoder::EncodeConnectivity`, the other half
    of `loaders.draco.read_sequential_index`.

    Args:
        out: Where to write it.
        index: The index.
        width: The bytes of the index, or 0 for a varint, as
            `sequential_index_width` gives it.
    """
    if width == 0:
        out.varint(index)
    else:
        out.unsigned(index, width)


def _check_bits(geometry: _Geometry, options: DracoExportOptions) raises:
    """Refuse quantization bits that Draco's encoder fails on."""
    # There is a position attribute: the loop runs.
    for attribute in geometry.attributes:  # pragma: no branch
        var bits = options.bits(attribute.attribute_type)
        draco_require(bits <= 30, "quantization bits are above 30")
        draco_require(
            bits != 1 or attribute.attribute_type != DRACO_NORMAL,
            "normals need two quantization bits or more",
        )


def _encode_mesh(
    var geometry: _Geometry, options: DracoExportOptions
) raises -> List[UInt8]:
    """Draco's `MeshEdgebreakerEncoder` and `MeshSequentialEncoder`."""
    var encoder = _Encoder(geometry^, options.copy())
    var ids = List[Int]()
    # There is a position attribute: the loop runs.
    for i in range(len(encoder.geometry.attributes)):  # pragma: no branch
        ids.append(i)
    if options.encoder_method == DRACO_MESH_SEQUENTIAL_ENCODING:
        _header(encoder.out, DRACO_TRIANGULAR_MESH, DRACO_SEQUENTIAL)
        var faces = len(encoder.geometry.faces) // 3
        var points = encoder.geometry.points
        encoder.out.varint(faces)
        encoder.out.varint(points)
        encoder.out.u8(1)
        var width = sequential_index_width(points)
        for index in encoder.geometry.faces:
            write_sequential_index(encoder.out, index, width)
        encoder.out.u8(1)
        encoder.write_descriptions(ids, True)
        var order = List[Int](capacity=points)
        # A geometry has a vertex: the loop runs.
        for p in range(points):  # pragma: no branch
            order.append(p)
        var none = List[Optional[MeshData]]()
        # An encoder has an attribute: the loop runs.
        for _ in ids:  # pragma: no branch
            none.append(None)
        encoder.encode_values(ids, order, none)
        return encoder.out.bytes.copy()
    _header(encoder.out, DRACO_TRIANGULAR_MESH, DRACO_COMPRESSED)
    var speed = options.speed()
    var valence = speed < 5 and len(encoder.geometry.faces) // 3 >= 1000
    if valence:
        encoder.out.u8(DRACO_VALENCE_TRAVERSAL.value)
    else:
        encoder.out.u8(DRACO_STANDARD_TRAVERSAL.value)
    var single = speed >= 6
    ref position = encoder.geometry.attributes[0]
    var corner_vertices = List[Int](capacity=len(encoder.geometry.faces))
    for point in encoder.geometry.faces:
        if single:
            corner_vertices.append(point)
        else:
            corner_vertices.append(position.point_map[point])
    var seams = List[List[Int]]()
    if not single:
        for i in range(1, len(ids)):
            seams.append(encoder.geometry.attributes[i].point_map.copy())
    var data = encode_edgebreaker(
        encoder.out,
        encoder.geometry.faces,
        corner_vertices,
        seams,
        valence,
    )
    _edgebreaker_attributes(encoder, data, single)
    return encoder.out.bytes.copy()


def _edgebreaker_attributes(
    mut encoder: _Encoder, data: EdgebreakerData, single: Bool
) raises:
    """Draco's `MeshEdgebreakerEncoderImpl::GenerateAttributesEncoder` and
    `EncodeAttributesEncoderIdentifier`, then the attributes: one encoder
    for them all when they share the table, one each otherwise."""
    var faces = encoder.geometry.faces.copy()
    var count = len(encoder.geometry.attributes)
    var groups = List[List[Int]]()
    if single:
        var all = List[Int]()
        # There is a position attribute: the loop runs.
        for i in range(count):  # pragma: no branch
            all.append(i)
        groups.append(all^)
    else:
        # There is a position attribute: the loop runs.
        for i in range(count):  # pragma: no branch
            groups.append([i])
    encoder.out.u8(len(groups))
    var tables = List[MeshData]()
    # There is an encoder: the loop runs.
    for g in range(len(groups)):  # pragma: no branch
        var id = groups[g][0]
        var method = DRACO_DEPTH_FIRST
        if id == 0 and encoder.options.speed() == 0:
            method = DRACO_PREDICTION_DEGREE
        var corner = False
        var table = data.base.table.copy()
        if id > 0 and not data.seams[id - 1].no_interior_seams:
            corner = True
            table = data.seams[id - 1].table.copy()
        var order = traverse(table, faces, data.order, method)
        tables.append(MeshData(table^, order^))
        encoder.out.u8(id - 1)
        encoder.out.u8(Int(corner))
        encoder.out.u8(method.value)
    # There is an encoder: the loop runs.
    for g in range(len(groups)):  # pragma: no branch
        encoder.write_descriptions(groups[g], True)
    # There is an encoder: the loop runs.
    for g in range(len(groups)):  # pragma: no branch
        var mesh = List[Optional[MeshData]]()
        # An encoder has an attribute: the loop runs.
        for _ in groups[g]:  # pragma: no branch
            mesh.append(tables[g].copy())
        encoder.encode_values(groups[g], tables[g].order.points, mesh)


def _encode_points(
    var geometry: _Geometry, options: DracoExportOptions
) raises -> List[UInt8]:
    """Draco's `PointCloudKdTreeEncoder` and
    `PointCloudSequentialEncoder`."""
    var encoder = _Encoder(geometry^, options.copy())
    var ids = List[Int]()
    # There is a position attribute: the loop runs.
    for i in range(len(encoder.geometry.attributes)):  # pragma: no branch
        ids.append(i)
    var points = encoder.geometry.points
    if options.encoder_method == DRACO_MESH_SEQUENTIAL_ENCODING:
        _header(encoder.out, DRACO_POINT_CLOUD, DRACO_SEQUENTIAL)
        encoder.out.u32(points)
        encoder.out.u8(1)
        encoder.write_descriptions(ids, True)
        var order = List[Int](capacity=points)
        # A geometry has a vertex: the loop runs.
        for p in range(points):  # pragma: no branch
            order.append(p)
        var none = List[Optional[MeshData]]()
        # An encoder has an attribute: the loop runs.
        for _ in ids:  # pragma: no branch
            none.append(None)
        encoder.encode_values(ids, order, none)
        return encoder.out.bytes.copy()
    # There is a position attribute: the loop runs.
    for attribute in encoder.geometry.attributes:  # pragma: no branch
        draco_require(
            options.bits(attribute.attribute_type) > 0,
            "a KD-tree needs every attribute quantized",
        )
    _header(encoder.out, DRACO_POINT_CLOUD, DRACO_COMPRESSED)
    encoder.out.u32(points)
    encoder.out.u8(1)
    encoder.write_descriptions(ids, False)
    var settings = List[Quantization]()
    var dimension = 0
    # There is a position attribute: the loop runs.
    for attribute in encoder.geometry.attributes:  # pragma: no branch
        settings.append(
            quantization_of(attribute, options.bits(attribute.attribute_type))
        )
        dimension += attribute.components
    var order = List[Int](capacity=points)
    # A geometry has a vertex: the loop runs.
    for p in range(points):  # pragma: no branch
        order.append(p)
    var coordinates = List[Int](length=points * dimension, fill=0)
    var offset = 0
    # There is a position attribute: the loop runs.
    for i in range(len(settings)):  # pragma: no branch
        ref attribute = encoder.geometry.attributes[i]
        var values = quantize(attribute, settings[i], order)
        var components = attribute.components
        # A geometry has a vertex: the loop runs.
        for p in range(points):  # pragma: no branch
            for c in range(components):  # pragma: no branch
                coordinates[p * dimension + offset + c] = (
                    values[p * components + c] & MASK32
                )
        offset += components
    encode_kd_tree(
        encoder.out, coordinates^, dimension, min(10 - options.speed(), 6)
    )
    # There is a position attribute: the loop runs.
    for q in settings:  # pragma: no branch
        q.write(encoder.out)
    return encoder.out.bytes.copy()


def export_draco(
    geometry: BufferGeometry,
    kind: DracoObjectKind = DRACO_EXPORT_MESH,
    options: DracoExportOptions = DracoExportOptions(),
) raises -> List[UInt8]:
    """Return a geometry as the bytes of a Draco file.

    three.js's `DRACOExporter.parse`: the attributes that the options
    pick, merged and encoded as Draco 1.5.6 encodes them.

    Args:
        geometry: The geometry.
        kind: `DRACO_EXPORT_MESH` for triangles, `DRACO_EXPORT_POINTS`
            for a point cloud.
        options: The options.

    Returns:
        The file.

    Raises:
        Error: If the kind, method or a speed is not known, the geometry
            has no vertices or an attribute that Draco cannot take, or
            Draco's encoder fails.
    """
    draco_require(kind.is_valid(), "an object kind is not known")
    draco_require(
        options.encoder_method.is_valid(), "an encoder method is not known"
    )
    draco_require(
        options.encode_speed >= 0
        and options.encode_speed <= 10
        and options.decode_speed >= 0
        and options.decode_speed <= 10,
        "a speed is not from 0 to 10",
    )
    draco_require(
        geometry.has_attribute(POSITION), "a geometry has no positions"
    )
    var points = geometry.attribute_view(POSITION).count()
    draco_require(points > 0, "a geometry has no vertices")
    var input = _Geometry(points)
    input.add(geometry, POSITION, DRACO_POSITION, 3)
    if kind == DRACO_EXPORT_POINTS:
        if options.export_color and geometry.has_attribute(COLOR):
            input.add(geometry, COLOR, DRACO_COLOR, _color_size(geometry))
        _check_bits(input, options)
        input.deduplicate()
        return _encode_points(input^, options)
    if geometry.is_indexed():
        # An indexed geometry has an index: the loop runs.
        for index in geometry.index:  # pragma: no branch
            draco_require(index < points, "a triangle names a missing vertex")
        input.faces = geometry.index.copy()
    else:
        for i in range(points - points % 3):
            input.faces.append(i)
    if options.export_normals and geometry.has_attribute(NORMAL):
        input.add(geometry, NORMAL, DRACO_NORMAL, 3)
    if options.export_uvs and geometry.has_attribute(UV):
        input.add(geometry, UV, DRACO_TEX_COORD, 2)
    if options.export_color and geometry.has_attribute(COLOR):
        input.add(geometry, COLOR, DRACO_COLOR, _color_size(geometry))
    _check_bits(input, options)
    input.deduplicate()
    return _encode_mesh(input^, options)


def _color_size(geometry: BufferGeometry) raises -> Int:
    """The item size of a color: three or four, or the error of `add`."""
    var size = geometry.attribute_view(COLOR).item_size
    if size == 4:
        return 4
    return 3


def write_draco(
    path: String,
    geometry: BufferGeometry,
    kind: DracoObjectKind = DRACO_EXPORT_MESH,
    options: DracoExportOptions = DracoExportOptions(),
) raises:
    """Write a geometry to a Draco file.

    Args:
        path: The file.
        geometry: The geometry.
        kind: `DRACO_EXPORT_MESH` or `DRACO_EXPORT_POINTS`.
        options: The options.

    Raises:
        Error: If the file cannot be written, or anything `export_draco`
            raises.
    """
    Path(path).write_bytes(export_draco(geometry, kind, options))
