# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draco meshes and point clouds, from three.js
`examples/jsm/loaders/DRACOLoader.js`.

three.js decodes a `.drc` file with Draco's own decoder, compiled to
WebAssembly. This module and the four beside it port that decoder, from
Draco 1.5.6, the decoder that three.js 0.180 ships, and then build the geometry as `DRACOLoader` builds it.

- `decode_draco` turns a file into a `DracoGeometry`: the points, the
  triangles, and each attribute as Draco stores it.
- `parse_draco` turns a file into a `BufferGeometry`, as
  `DRACOLoader.parse` does, and `read_draco` reads a file first.
- `draco_buffer_geometry` builds a geometry from a `DracoGeometry`, for a
  caller such as glTF's `KHR_draco_mesh_compression`.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**What is read.** The two bitstreams that Draco 1.5 writes: 2.2 for a
mesh and 2.3 for a point cloud. A mesh is sequential or Edgebreaker, with
the standard or the valence traversal. A point cloud is sequential or a
KD-tree. An attribute is raw, integer, quantized or an octahedral normal,
with every prediction Draco writes.

**The geometry.** As `DRACOLoader` builds it: the first `POSITION`,
`NORMAL`, `COLOR` and `TEX_COORD` attributes become `position`, `normal`,
`color` and `uv`, each read as `Float32`. An integer attribute is cast,
and divided by the largest value of its type if it is normalized. The
colors of a `.drc` file are taken as sRGB and made linear. A mesh has an
index of three points for each triangle.

**Where this port differs.** Draco reads bitstreams back to 1.0; this
reads 2.2 and 2.3 only, which is all that Draco has written since 2017.
Draco adds a triangle of a sequential mesh whatever its points; this
refuses a point that the mesh does not have, which would leave three.js
an index past the end of its attributes. three.js reads a color of one or
two components past the end of each item; this refuses it. Draco decodes
the deprecated texture coordinate prediction and a geometric normal
prediction with the wrap transform; this refuses both.

**What is refused.** A file that does not start with `DRACO`; another
bitstream version; an encoding, attribute decoder, prediction, transform
or traversal that is not known; and every check that Draco's decoder
makes, with the reason as the message.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from loaders.draco_attributes import (
    DRACO_BOOL,
    DRACO_COLOR,
    DRACO_CONSTRAINED_MULTI_PARALLELOGRAM,
    DRACO_DIFFERENCE,
    DRACO_FLOAT32,
    DRACO_GEOMETRIC_NORMAL,
    DRACO_INT16,
    DRACO_INT32,
    DRACO_INT8,
    DRACO_NORMAL,
    DRACO_OCTAHEDRON,
    DRACO_OCTAHEDRON_CANONICALIZED,
    DRACO_POSITION,
    DRACO_PREDICTION_NONE,
    DRACO_TEX_COORD,
    DRACO_TEX_COORDS_DEPRECATED,
    DRACO_TEX_COORDS_PORTABLE,
    DRACO_UINT16,
    DRACO_UINT32,
    DRACO_UINT8,
    DRACO_WRAP,
    DracoAttribute,
    DracoAttributeType,
    DracoDataType,
    DracoMeshData,
    DracoPortable,
    DracoPrediction,
    DracoTransform,
    PredictionScheme,
    PredictionTransform,
    dequantize,
    octahedron_to_normals,
    product32,
)
from loaders.draco_buffer import (
    DracoBuffer,
    decode_symbols,
    draco_require,
    draco_version,
    symbol_to_signed,
    to_int32,
)
from loaders.draco_kd_tree import decode_kd_tree
from loaders.draco_mesh import (
    DRACO_DEPTH_FIRST,
    DRACO_PREDICTION_DEGREE,
    NONE,
    DracoCornerTable,
    DracoEncodingData,
    DracoTraversal,
    DracoTraversalMethod,
    EdgebreakerConnectivity,
    decode_edgebreaker,
    traverse_depth_first,
    traverse_prediction_degree,
)
from loaders.js_number import js_pow
from loaders.vrml_geometry import product
from std.pathlib import Path


@fieldwise_init
struct DracoGeometryType(Equatable, ImplicitlyCopyable, Writable):
    """What a Draco file holds, as a type rather than a bare int.

    `decode_draco` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for a point cloud and for a mesh.

        Returns:
            True for the two geometries there are.
        """
        return self == DRACO_POINT_CLOUD or self == DRACO_TRIANGULAR_MESH


comptime DRACO_POINT_CLOUD = DracoGeometryType(0)
comptime DRACO_TRIANGULAR_MESH = DracoGeometryType(1)


@fieldwise_init
struct DracoEncoding(Equatable, ImplicitlyCopyable, Writable):
    """How the geometry of a Draco file is coded, as a type rather than a
    bare int.

    `decode_draco` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the sequential and the compressed encodings.

        Returns:
            True for the two encodings of each geometry.
        """
        return self == DRACO_SEQUENTIAL or self == DRACO_COMPRESSED


# Points or triangles in order.
comptime DRACO_SEQUENTIAL = DracoEncoding(0)
# A KD-tree for a point cloud, Edgebreaker for a mesh.
comptime DRACO_COMPRESSED = DracoEncoding(1)


@fieldwise_init
struct DracoAttributeCoding(Equatable, ImplicitlyCopyable, Writable):
    """How the values of an attribute are stored in order, as a type rather
    than a bare int.

    `decode_draco` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the four codings there are.

        Returns:
            True from `DRACO_RAW` to `DRACO_NORMALS`.
        """
        return self.value >= DRACO_RAW.value and (
            self.value <= DRACO_NORMALS.value
        )


# The bytes of each value.
comptime DRACO_RAW = DracoAttributeCoding(0)
# Integers, predicted.
comptime DRACO_INTEGER = DracoAttributeCoding(1)
# Floats, quantized to integers and predicted.
comptime DRACO_QUANTIZED = DracoAttributeCoding(2)
# Unit normals, folded onto an octahedron and predicted.
comptime DRACO_NORMALS = DracoAttributeCoding(3)


@fieldwise_init
struct DracoElement(Equatable, ImplicitlyCopyable, Writable):
    """Whether an Edgebreaker attribute has a value for each vertex or for
    each corner, as a type rather than a bare int.

    Draco reads any value but zero as a corner attribute, and so does
    `decode_draco`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the two elements there are.

        Returns:
            True for `DRACO_VERTEX` and `DRACO_CORNER`.
        """
        return self == DRACO_VERTEX or self == DRACO_CORNER


comptime DRACO_VERTEX = DracoElement(0)
comptime DRACO_CORNER = DracoElement(1)


struct DracoGeometry(Copyable, Movable):
    """What a Draco file holds, as Draco's decoder holds it."""

    var geometry_type: DracoGeometryType
    """A point cloud or a mesh."""
    var points: Int
    """The points."""
    var faces: List[Int]
    """Three points for each triangle; empty for a point cloud."""
    var attributes: List[DracoAttribute]
    """The attributes, in the order the file declares them."""

    def __init__(out self, geometry_type: DracoGeometryType):
        """Make an empty geometry.

        Args:
            geometry_type: A point cloud or a mesh.
        """
        self.geometry_type = geometry_type
        self.points = 0
        self.faces = List[Int]()
        self.attributes = List[DracoAttribute]()

    def named_attribute(self, attribute_type: DracoAttributeType) -> Int:
        """Return the first attribute of a type.

        Draco's `GetAttributeId`, which `DRACOLoader` calls for a `.drc`
        file.

        Args:
            attribute_type: What the attribute is for.

        Returns:
            Its index, or -1 if there is none.
        """
        for i in range(len(self.attributes)):
            if self.attributes[i].attribute_type == attribute_type:
                return i
        return NONE

    def unique_attribute(self, unique_id: Int) -> Int:
        """Return the attribute with a unique id.

        Draco's `GetAttributeByUniqueId`, which glTF's
        `KHR_draco_mesh_compression` calls.

        Args:
            unique_id: The id.

        Returns:
            Its index, or -1 if there is none.
        """
        for i in range(len(self.attributes)):
            if self.attributes[i].unique_id == unique_id:
                return i
        return NONE

    def float32_values(self, index: Int) raises -> List[Float32]:
        """Return the values of an attribute for every point, as `Float32`.

        Draco's `GetAttributeDataArrayForAllPoints` for `DT_FLOAT32`.

        Args:
            index: The attribute.

        Returns:
            `components` values for each point, point after point.

        Raises:
            Error: If a point uses a value the attribute does not have.
        """
        var attribute = self.attributes[index].copy()
        var out = List[Float32](capacity=self.points * attribute.components)
        for point in range(self.points):
            var value = attribute.mapped(point)
            draco_require(
                value >= 0 and value < attribute.count,
                "a point has no attribute value",
            )
            for c in range(attribute.components):  # pragma: no branch
                out.append(attribute.float32_at(value, c))
        return out^

    def integer_values(
        self, index: Int, out_type: DracoDataType
    ) raises -> List[Int]:
        """Return the values of an attribute for every point, as integers.

        Draco's `GetAttributeDataArrayForAllPoints` for an integer type,
        which glTF's `KHR_draco_mesh_compression` asks for when an
        accessor is not a float.

        Args:
            index: The attribute.
            out_type: The integer type to read the values as.

        Returns:
            `components` values for each point, point after point.

        Raises:
            Error: If a point uses a value the attribute does not have, the
                attribute is a float, or a value does not fit `out_type`.
        """
        var attribute = self.attributes[index].copy()
        var out = List[Int](capacity=self.points * attribute.components)
        for point in range(self.points):
            var value = attribute.mapped(point)
            draco_require(
                value >= 0 and value < attribute.count,
                "a point has no attribute value",
            )
            for c in range(attribute.components):  # pragma: no branch
                out.append(attribute.integer_at(value, c, out_type))
        return out^


struct _AttributesDecoder(Movable):
    """One attributes decoder: its attributes, their codings and, for an
    Edgebreaker mesh, the order of their values."""

    var ids: List[Int]
    var codings: List[DracoAttributeCoding]
    var data: Int
    var element: DracoElement
    var method: DracoTraversalMethod

    def __init__(out self):
        self.ids = List[Int]()
        self.codings = List[DracoAttributeCoding]()
        self.data = NONE
        self.element = DRACO_VERTEX
        self.method = DRACO_DEPTH_FIRST


struct _Decoder(Movable):
    """The state of Draco's decoder while it reads one file."""

    var buffer: DracoBuffer
    var geometry: DracoGeometry
    var encoding: DracoEncoding
    var connectivity: Optional[EdgebreakerConnectivity]
    var decoders: List[_AttributesDecoder]
    var portables: Dict[Int, DracoPortable]
    var position_data: Int
    var position_encoding: DracoEncodingData
    var encodings: List[DracoEncodingData]

    def __init__(
        out self,
        var buffer: DracoBuffer,
        geometry_type: DracoGeometryType,
        encoding: DracoEncoding,
    ):
        self.buffer = buffer^
        self.geometry = DracoGeometry(geometry_type)
        self.encoding = encoding
        self.connectivity = None
        self.decoders = List[_AttributesDecoder]()
        self.portables = Dict[Int, DracoPortable]()
        self.position_data = NONE
        self.position_encoding = DracoEncodingData(0)
        self.encodings = List[DracoEncodingData]()

    def take(deinit self) -> DracoGeometry:
        """Give up the decoded geometry."""
        return self.geometry^

    def edgebreaker(self) -> Bool:
        """Return True for an Edgebreaker mesh."""
        return Bool(self.connectivity)

    def read_sequential_mesh(mut self) raises:
        """Draco's `MeshSequentialDecoder::DecodeConnectivity`."""
        var faces = self.buffer.varint32()
        var points = self.buffer.varint32()
        draco_require(faces <= 0xFFFFFFFF // 3, "there are too many faces")
        draco_require(
            faces <= self.buffer.remaining() // 3, "there are too many faces"
        )
        draco_require(points <= faces * 3, "there are too many points")
        var method = self.buffer.u8()
        var indices = List[Int](capacity=faces * 3)
        if method == 0:
            var symbols = decode_symbols(self.buffer, faces * 3, 1)
            var last = 0
            for encoded in symbols:
                var diff = encoded >> 1
                if encoded & 1 != 0:
                    diff = -diff
                last = to_int32(diff + last)
                draco_require(last >= 0, "an index is negative")
                indices.append(last)
        else:
            var width = sequential_index_width(points)
            for _ in range(faces * 3):
                indices.append(read_sequential_index(self.buffer, width))
        for index in indices:
            draco_require(index < points, "a triangle names a missing point")
        self.geometry.faces = indices^
        self.geometry.points = points

    def read_edgebreaker(mut self) raises:
        """Draco's `MeshEdgebreakerDecoder`, up to the attributes."""
        var kind = DracoTraversal(self.buffer.u8())
        var connectivity = decode_edgebreaker(self.buffer, kind)
        self.geometry.faces = connectivity.faces.copy()
        self.geometry.points = connectivity.points
        self.position_encoding = DracoEncodingData(
            connectivity.table.vertices()
        )
        for data in connectivity.attributes:
            self.encodings.append(
                DracoEncodingData(
                    max(data.table.vertices(), connectivity.table.vertices())
                )
            )
        self.connectivity = connectivity^

    def create_decoder(mut self, index: Int) raises:
        """Draco's `CreateAttributesDecoder`."""
        var decoder = _AttributesDecoder()
        if self.edgebreaker():
            var data = self.buffer.i8()
            var element = DracoElement(min(self.buffer.u8(), 1))
            var method = DracoTraversalMethod(self.buffer.u8())
            draco_require(method.is_valid(), "a traversal method is not known")
            if data >= 0:
                ref attributes = self.connectivity.value().attributes
                draco_require(
                    data < len(attributes), "attribute data does not exist"
                )
                draco_require(
                    attributes[data].decoder == NONE,
                    "attribute data is read twice",
                )
                attributes[data].decoder = index
                if element == DRACO_VERTEX:
                    attributes[data].used = False
            else:
                draco_require(
                    self.position_data == NONE, "position data is read twice"
                )
                self.position_data = index
            draco_require(
                element == DRACO_VERTEX
                or (method == DRACO_DEPTH_FIRST and data >= 0),
                "a corner attribute needs its data and a depth first order",
            )
            decoder.data = data
            decoder.element = element
            decoder.method = method
        self.decoders.append(decoder^)

    def read_decoder_data(mut self, index: Int) raises:
        """Draco's `DecodeAttributesDecoderData`."""
        var count = self.buffer.varint32()
        draco_require(count > 0, "an attributes decoder has no attributes")
        draco_require(
            count <= 5 * self.buffer.remaining(),
            "an attributes decoder has too many attributes",
        )
        for _ in range(count):  # pragma: no branch
            var attribute_type = DracoAttributeType(self.buffer.u8())
            var data_type = DracoDataType(self.buffer.u8())
            var components = self.buffer.u8()
            var normalized = self.buffer.u8() > 0
            draco_require(
                attribute_type.is_valid(), "an attribute type is not known"
            )
            draco_require(data_type.is_valid(), "a data type is not known")
            draco_require(components > 0, "an attribute has no components")
            var unique_id = self.buffer.varint32()
            self.decoders[index].ids.append(len(self.geometry.attributes))
            self.geometry.attributes.append(
                DracoAttribute(
                    attribute_type, data_type, components, normalized, unique_id
                )
            )
        if self.geometry.geometry_type == DRACO_POINT_CLOUD and (
            self.encoding == DRACO_COMPRESSED
        ):
            return
        for id in self.decoders[index].ids.copy():  # pragma: no branch
            var coding = DracoAttributeCoding(self.buffer.u8())
            draco_require(coding.is_valid(), "an attribute coding is not known")
            ref attribute = self.geometry.attributes[id]
            draco_require(
                coding == DRACO_RAW
                or coding == DRACO_INTEGER
                or attribute.data_type == DRACO_FLOAT32,
                "a quantized attribute is not float",
            )
            draco_require(
                coding != DRACO_NORMALS or attribute.components == 3,
                "a normal attribute does not have three components",
            )
            self.decoders[index].codings.append(coding)

    def sequence(mut self, index: Int) raises -> List[Int]:
        """Draco's `GenerateSequence` and
        `UpdatePointToAttributeIndexMapping`."""
        if not self.edgebreaker():
            var points = List[Int](capacity=self.geometry.points)
            for p in range(self.geometry.points):
                points.append(p)
            return points^
        var data = self.decoders[index].data
        var method = self.decoders[index].method
        var table = self._table(data)
        var faces = self.geometry.faces.copy()
        var points: List[Int]
        var values: List[Int]
        if data < 0:
            points = _traverse(table, faces, self.position_encoding, method)
            values = self.position_encoding.vertex_values.copy()
        else:
            points = _traverse(table, faces, self.encodings[data], method)
            values = self.encodings[data].vertex_values.copy()
        var point_map = List[Int](length=self.geometry.points, fill=NONE)
        for corner in range(len(faces)):
            var vertex = table.vertex(corner)
            draco_require(vertex != NONE, "a corner has no vertex")
            var entry = values[vertex]
            draco_require(
                faces[corner] < self.geometry.points
                and entry < self.geometry.points,
                "a point maps past the end",
            )
            point_map[faces[corner]] = entry
        for id in self.decoders[index].ids:  # pragma: no branch
            self.geometry.attributes[id].point_map = point_map.copy()
        return points^

    def _table(self, data: Int) -> DracoCornerTable:
        """The table an attributes decoder traverses and predicts on."""
        ref connectivity = self.connectivity.value()
        if data >= 0 and connectivity.attributes[data].used:
            return connectivity.attributes[data].table.copy()
        return connectivity.table.copy()

    def mesh_data(self, index: Int) -> DracoMeshData:
        """Draco's `MeshPredictionSchemeData` for an attributes decoder."""
        var data = self.decoders[index].data
        var table = self._table(data)
        if data < 0:
            return DracoMeshData(
                table^,
                self.position_encoding.value_corners.copy(),
                self.position_encoding.vertex_values.copy(),
            )
        return DracoMeshData(
            table^,
            self.encodings[data].value_corners.copy(),
            self.encodings[data].vertex_values.copy(),
        )

    def decode_attributes(mut self, index: Int) raises:
        """Draco's `SequentialAttributeDecodersController::DecodeAttributes`."""
        var points = self.sequence(index)
        var ids = self.decoders[index].ids.copy()
        var codings = self.decoders[index].codings.copy()
        for i in range(len(ids)):  # pragma: no branch
            self.geometry.attributes[ids[i]].reset(len(points))
            if codings[i] == DRACO_RAW:
                self._read_raw(ids[i])
            else:
                self._read_integers(index, ids[i], codings[i], points)
        var quantization = List[Tuple[List[Float32], Float32, Int]]()
        var normal_bits = List[Int]()
        for i in range(len(ids)):  # pragma: no branch
            ref attribute = self.geometry.attributes[ids[i]]
            if codings[i] == DRACO_QUANTIZED:
                var minimums = List[Float32]()
                for _ in range(attribute.components):  # pragma: no branch
                    minimums.append(self.buffer.f32())
                var spread = self.buffer.f32()
                var bits = self.buffer.u8()
                draco_require(
                    bits >= 1 and bits <= 30,
                    "quantization bits are not from 1 to 30",
                )
                quantization.append((minimums^, spread, bits))
            elif codings[i] == DRACO_NORMALS:
                normal_bits.append(self.buffer.u8())
        var q = 0
        var n = 0
        for i in range(len(ids)):  # pragma: no branch
            var id = ids[i]
            var portable = List[Int]()
            if codings[i] != DRACO_RAW:
                portable = self.portables[id].values.copy()
            if codings[i] == DRACO_INTEGER:
                _store_integers(self.geometry.attributes[id], portable)
            elif codings[i] == DRACO_QUANTIZED:
                ref settings = quantization[q]
                dequantize(
                    self.geometry.attributes[id],
                    portable,
                    settings[0],
                    settings[1],
                    settings[2],
                )
                q += 1
            elif codings[i] == DRACO_NORMALS:
                octahedron_to_normals(
                    self.geometry.attributes[id], portable, normal_bits[n]
                )
                n += 1

    def _read_raw(mut self, id: Int) raises:
        """Draco's `SequentialAttributeDecoder::DecodeValues`."""
        ref attribute = self.geometry.attributes[id]
        var size = len(attribute.bytes)
        attribute.bytes = self.buffer.bytes(size)

    def _read_integers(
        mut self,
        index: Int,
        id: Int,
        coding: DracoAttributeCoding,
        points: List[Int],
    ) raises:
        """Draco's `SequentialIntegerAttributeDecoder::DecodeValues`.

        Draco 1.5.6 reads a prediction it does not know as a difference.
        It refuses an attribute with no values when it asks for the
        integers, after the prediction; the refusal is first here."""
        draco_require(len(points) > 0, "an integer attribute has no values")
        var method = DracoPrediction(self.buffer.i8())
        var components = self.geometry.attributes[id].components
        if coding == DRACO_NORMALS:
            components = 2
        var scheme: Optional[PredictionScheme] = None
        if method != DRACO_PREDICTION_NONE:
            var transform = DracoTransform(self.buffer.i8())
            draco_require(
                transform.is_valid(), "a prediction transform is not known"
            )
            scheme = self._scheme(method, transform, coding, components)
        var positions: Optional[DracoPortable] = None
        var position_map = List[Int]()
        if Bool(scheme) and scheme.value().needs_positions():
            var parent = self.geometry.named_attribute(DRACO_POSITION)
            draco_require(parent != NONE, "a prediction needs positions")
            draco_require(
                parent in self.portables, "the positions are not decoded yet"
            )
            draco_require(
                self.geometry.attributes[parent].components == 3,
                "a prediction needs three position components",
            )
            positions = self.portables[parent].copy()
            position_map = self.geometry.attributes[parent].point_map.copy()
        var count = len(points) * components
        var values: List[Int]
        if self.buffer.u8() > 0:
            values = decode_symbols(self.buffer, count, components)
        else:
            var size = self.buffer.u8()
            draco_require(size <= 4, "an integer is wider than four bytes")
            self.buffer.need(size * count)
            values = List[Int](capacity=count)
            # There are values here. The loop always runs.
            for _ in range(count):  # pragma: no branch
                values.append(self.buffer.read_unsigned(size))
        var positive = False
        if Bool(scheme):
            positive = scheme.value().transform.positive()
        if not positive:
            # There are values here. The loop always runs.
            for k in range(count):  # pragma: no branch
                values[k] = symbol_to_signed(values[k])
        if Bool(scheme):
            var edges = 0
            if self.edgebreaker():
                edges = self.connectivity.value().table.corners()
            scheme.value().read(self.buffer, edges)
            var mesh: Optional[DracoMeshData] = None
            if scheme.value().method != DRACO_DIFFERENCE:
                mesh = self.mesh_data(index)
            scheme.value().compute(
                values, components, points, mesh, positions, position_map
            )
        self.portables[id] = DracoPortable(values^, components)

    def _scheme(
        self,
        method: DracoPrediction,
        transform: DracoTransform,
        coding: DracoAttributeCoding,
        components: Int,
    ) raises -> Optional[PredictionScheme]:
        """Draco's `CreateIntPredictionScheme` and
        `CreatePredictionSchemeForDecoder`: which prediction runs, or none
        when the transform does not suit the attribute."""
        if coding == DRACO_NORMALS:
            if transform != DRACO_OCTAHEDRON and (
                transform != DRACO_OCTAHEDRON_CANONICALIZED
            ):
                return None
        elif transform != DRACO_WRAP:
            return None
        var effective = DRACO_DIFFERENCE
        if self.edgebreaker() and method.is_valid() and method.value > 0:
            if transform == DRACO_WRAP:
                draco_require(
                    method != DRACO_TEX_COORDS_DEPRECATED,
                    "the old texture coordinate prediction is not supported",
                )
                draco_require(
                    method != DRACO_GEOMETRIC_NORMAL,
                    "a normal prediction needs an octahedron transform",
                )
                effective = method
            elif method == DRACO_GEOMETRIC_NORMAL:
                effective = method
        return PredictionScheme(
            effective, PredictionTransform(transform, components)
        )

    def decode_kd_tree_attributes(mut self, index: Int) raises:
        """Draco's `KdTreeAttributesDecoder` for bitstream 2.3."""
        var level = self.buffer.u8()
        var points = self.geometry.points
        var ids = self.decoders[index].ids.copy()
        var dimension = 0
        var signed = 0
        for id in ids:  # pragma: no branch
            ref attribute = self.geometry.attributes[id]
            attribute.reset(points)
            var t = attribute.data_type
            draco_require(
                t.is_integral()
                and t.size() <= 4
                and t != DRACO_BOOL
                or t == DRACO_FLOAT32,
                "a KD-tree attribute is not a 32-bit number",
            )
            if t == DRACO_INT8 or t == DRACO_INT16 or t == DRACO_INT32:
                signed += attribute.components
            dimension += attribute.components
        var values = decode_kd_tree(self.buffer, level, dimension, points)
        var offset = 0
        var quantized = List[List[Int]]()
        for id in ids:  # pragma: no branch
            ref attribute = self.geometry.attributes[id]
            var components = attribute.components
            var own = List[Int](capacity=points * components)
            for p in range(points):
                for c in range(components):  # pragma: no branch
                    own.append(values[p * dimension + offset + c])
            if attribute.data_type == DRACO_FLOAT32:
                quantized.append(own^)
            else:
                for k in range(len(own)):
                    attribute.set_bits(k, own[k])
            offset += components
        var settings = List[Tuple[List[Float32], Float32, Int]]()
        for id in ids:  # pragma: no branch
            ref attribute = self.geometry.attributes[id]
            if attribute.data_type != DRACO_FLOAT32:
                continue
            var minimums = List[Float32]()
            for _ in range(attribute.components):  # pragma: no branch
                minimums.append(self.buffer.f32())
            var spread = self.buffer.f32()
            var bits = self.buffer.u8()
            draco_require(
                bits >= 1 and bits <= 30,
                "quantization bits are not from 1 to 30",
            )
            settings.append((minimums^, spread, bits))
        var minimums = List[Int]()
        for _ in range(signed):
            minimums.append(self.buffer.signed_varint32())
        var q = 0
        var s = 0
        for id in ids:  # pragma: no branch
            ref attribute = self.geometry.attributes[id]
            var t = attribute.data_type
            if t == DRACO_FLOAT32:
                ref setting = settings[q]
                dequantize(
                    attribute, quantized[q], setting[0], setting[1], setting[2]
                )
                q += 1
            elif t == DRACO_INT8 or t == DRACO_INT16 or t == DRACO_INT32:
                var components = attribute.components
                for k in range(attribute.count * components):
                    var bits = attribute.bits_at(k)
                    draco_require(
                        bits <= 0x7FFFFFFF, "a KD-tree value is too large"
                    )
                    attribute.set_bits(
                        k, to_int32(bits + minimums[s + k % components])
                    )
                s += components


def sequential_index_width(points: Int) -> Int:
    """Return how a sequential mesh stores each point index, by its points.

    Draco's `MeshSequentialDecoder::DecodeConnectivity` for bitstream 2.2.

    Args:
        points: The points of the mesh.

    Returns:
        One or two bytes below 256 and 65536 points, 0 for a varint below
        2^21 points, and four bytes from there.
    """
    if points < 256:
        return 1
    if points < 1 << 16:
        return 2
    if points < 1 << 21:
        return 0
    return 4


def read_sequential_index(mut buffer: DracoBuffer, width: Int) raises -> Int:
    """Read one point index of a sequential mesh.

    Args:
        buffer: The cursor.
        width: The bytes of the index, or 0 for a varint, as
            `sequential_index_width` gives it.

    Returns:
        The index.

    Raises:
        Error: If the file ends.
    """
    if width == 0:
        return buffer.varint32()
    return buffer.read_unsigned(width)


def _traverse(
    table: DracoCornerTable,
    faces: List[Int],
    mut data: DracoEncodingData,
    method: DracoTraversalMethod,
) raises -> List[Int]:
    """Run the traversal an attributes decoder names."""
    if method == DRACO_PREDICTION_DEGREE:
        return traverse_prediction_degree(table, faces, data)
    return traverse_depth_first(table, faces, data)


def _store_integers(mut attribute: DracoAttribute, portable: List[Int]) raises:
    """Draco's `SequentialIntegerAttributeDecoder::StoreValues`: each
    value cast to the attribute's integer type."""
    var t = attribute.data_type
    draco_require(
        t == DRACO_INT8
        or t == DRACO_UINT8
        or t == DRACO_INT16
        or t == DRACO_UINT16
        or t == DRACO_INT32
        or t == DRACO_UINT32,
        "an integer attribute is not an integer type of 32 bits or fewer",
    )
    # An integer attribute has values. The loop always runs.
    for k in range(len(portable)):  # pragma: no branch
        attribute.set_bits(k, portable[k])


def _skip_metadata(mut buffer: DracoBuffer) raises:
    """Draco's `MetadataDecoder::DecodeGeometryMetadata`, which reads the
    metadata three.js does not use."""
    var count = buffer.varint32()
    for _ in range(count):
        _ = buffer.varint32()
        _skip_metadata_tree(buffer)
    _skip_metadata_tree(buffer)


def _skip_metadata_tree(mut buffer: DracoBuffer) raises:
    """Draco's `MetadataDecoder::DecodeMetadata`: entries, then nested
    metadata, each named once under its parent."""
    var stack = List[Tuple[Int, Int]]()
    var names = List[List[String]]()
    stack.append((NONE, 0))
    while len(stack) > 0:
        var item = stack.pop()
        var parent = item[0]
        if parent != NONE:
            draco_require(item[1] <= 1000, "metadata is nested too deep")
            var name = _metadata_name(buffer)
            draco_require(
                name not in names[parent], "a metadata name is repeated"
            )
            names[parent].append(name)
        var node = len(names)
        names.append(List[String]())
        var entries = buffer.varint32()
        for _ in range(entries):
            _ = _metadata_name(buffer)
            var size = buffer.varint32()
            draco_require(size > 0, "a metadata entry is empty")
            buffer.advance(size)
        var children = buffer.varint32()
        draco_require(
            children <= buffer.remaining(), "there is too much metadata"
        )
        var level = item[1]
        if parent != NONE:
            level += 1
        for _ in range(children):
            stack.append((node, level))


def _metadata_name(mut buffer: DracoBuffer) raises -> String:
    """A name of metadata: a length byte, then the bytes."""
    var bytes = buffer.bytes(buffer.u8())
    return String(unsafe_from_utf8=bytes)


def decode_draco(bytes: List[UInt8]) raises -> DracoGeometry:
    """Decode a Draco file as Draco's decoder does.

    Args:
        bytes: The file.

    Returns:
        The points, the triangles and the attributes.

    Raises:
        Error: If the file is not a Draco file of bitstream 2.2 or 2.3, or
            its data is not valid.
    """
    var buffer = DracoBuffer(bytes.copy())
    var magic = buffer.bytes(min(5, len(bytes)))
    draco_require(
        String(unsafe_from_utf8=magic) == "DRACO", "the file is not Draco"
    )
    var major = buffer.u8()
    var minor = buffer.u8()
    var geometry_type = DracoGeometryType(buffer.u8())
    var encoding = DracoEncoding(buffer.u8())
    var flags = buffer.u16()
    draco_require(geometry_type.is_valid(), "a geometry type is not known")
    var expected = draco_version(2, 2)
    if geometry_type == DRACO_POINT_CLOUD:
        expected = draco_version(2, 3)
    draco_require(
        draco_version(major, minor) == expected,
        "bitstream "
        + String(major)
        + "."
        + String(minor)
        + " is not supported",
    )
    draco_require(encoding.is_valid(), "an encoding is not known")
    buffer.version = expected
    if flags & 0x8000 != 0:
        _skip_metadata(buffer)
    var decoder = _Decoder(buffer^, geometry_type, encoding)
    if geometry_type == DRACO_POINT_CLOUD:
        var points = decoder.buffer.i32()
        draco_require(points >= 0, "the point count is negative")
        decoder.geometry.points = points
    elif encoding == DRACO_SEQUENTIAL:
        decoder.read_sequential_mesh()
    else:
        decoder.read_edgebreaker()
    var count = decoder.buffer.u8()
    for i in range(count):
        decoder.create_decoder(i)
    for i in range(count):
        decoder.read_decoder_data(i)
    for i in range(count):
        if geometry_type == DRACO_POINT_CLOUD and encoding == DRACO_COMPRESSED:
            decoder.decode_kd_tree_attributes(i)
        else:
            decoder.decode_attributes(i)
    return decoder^.take()


def _srgb_to_linear(c: Float64) -> Float64:
    """three.js's `SRGBToLinear`, with V8's `Math.pow`."""
    if c < 0.04045:
        return c * 0.0773993808
    return js_pow(product(c, 0.9478672986) + 0.0521327014, 2.4)


def draco_buffer_geometry(
    geometry: DracoGeometry,
    names: List[String],
    attributes: List[Int],
    srgb_colors: Bool,
) raises -> BufferGeometry:
    """Build a `BufferGeometry` from decoded Draco data, as `DRACOLoader`
    builds it.

    Args:
        geometry: The decoded file.
        names: The name of each attribute to build.
        attributes: The attribute of `geometry` for each name, or -1 to
            leave the name out.
        srgb_colors: True to convert the `color` attribute from sRGB to
            linear, as `DRACOLoader.parse` does for a `.drc` file.

    Returns:
        The geometry, with an index for a mesh.

    Raises:
        Error: If a point has no value, or a color to convert has fewer
            than three components.
    """
    var out = BufferGeometry()
    for i in range(len(names)):
        var index = attributes[i]
        if index == NONE:
            continue
        var values = geometry.float32_values(index)
        var components = geometry.attributes[index].components
        if names[i] == COLOR and srgb_colors:
            draco_require(
                components >= 3, "a color has fewer than three components"
            )
            for p in range(geometry.points):
                for c in range(3):  # pragma: no branch
                    var at = p * components + c
                    values[at] = Float32(_srgb_to_linear(Float64(values[at])))
        out.set_attribute(names[i], BufferAttribute(values^, components))
    if geometry.geometry_type == DRACO_TRIANGULAR_MESH:
        out.set_index(geometry.faces.copy())
    return out^


def parse_draco(bytes: List[UInt8]) raises -> BufferGeometry:
    """Decode a `.drc` file into a geometry, as `DRACOLoader.parse` does.

    Args:
        bytes: The file.

    Returns:
        The geometry: `position`, `normal`, `color` and `uv` from the
        first attribute of each type, with the colors made linear, and an
        index for a mesh.

    Raises:
        Error: If the file cannot be decoded.
    """
    var geometry = decode_draco(bytes)
    var names: List[String] = [
        String(POSITION),
        String(NORMAL),
        String(COLOR),
        String(UV),
    ]
    var ids: List[Int] = [
        geometry.named_attribute(DRACO_POSITION),
        geometry.named_attribute(DRACO_NORMAL),
        geometry.named_attribute(DRACO_COLOR),
        geometry.named_attribute(DRACO_TEX_COORD),
    ]
    return draco_buffer_geometry(geometry, names, ids, True)


def read_draco(path: String) raises -> BufferGeometry:
    """Read a `.drc` file and decode it, as `DRACOLoader.load` does.

    Args:
        path: The file.

    Returns:
        The geometry, as `parse_draco` builds it.

    Raises:
        Error: If the file cannot be read or decoded.
    """
    return parse_draco(Path(path).read_bytes())
