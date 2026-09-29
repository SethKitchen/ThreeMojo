# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gaussian splats in glTF meshes, `KHR_gaussian_splatting`, from three.js
`examples/jsm/loaders/GLTFGaussianSplatLoaderExtension.js`.

A glTF primitive with the extension is a point cloud whose points are
splats. Its attributes are the splat's fields:

- `POSITION`: the center.
- `KHR_gaussian_splatting:SCALE`: the scale, three numbers.
- `KHR_gaussian_splatting:ROTATION`: the rotation's x, y, z and w.
- `KHR_gaussian_splatting:OPACITY`: the opacity, 0 to 1.
- `KHR_gaussian_splatting:SH_DEGREE_0_COEF_0`: the zeroth band, read as a
  color by `write_color_bytes_from_sh0`.
- `KHR_gaussian_splatting:SH_DEGREE_d_COEF_c`: the higher bands, three
  numbers each, for `c` from 0 to `2 d`. A band is read when all its
  coefficients are there, and becomes the band's bytes,
  `value * 128 + 128`, clamped.

The extension object must have `kernel` `ellipse` and a `colorSpace`.
`projection` and `sortingMethod` are kept as the file gives them;
three.js warns when they are not `perspective` and `cameraDistance`.

**What is read.** `read_gltf_gaussian_splats` reads each mesh of a
`.gltf` or a `.glb` whose primitives have the extension, three.js's
`loadMesh` in the plugin, and returns one `GltfGaussianSplatMesh` for
each: the mesh's index, its `extras` as user data, and one
`GltfGaussianSplatPrimitive` for each primitive, which three.js makes a
`GaussianSplat`, in a `Group` when there are several. A mesh with no
splat primitive is left to `loaders.gltf.read_gltf`, as three.js leaves
it to `GLTFLoader`.

**Names.** Each primitive is named after its mesh, or `mesh_N`, made
unique as three.js's `createUniqueName` makes a name: sanitized, then
`_1`, `_2` and on for a name used before. Every primitive of every mesh
takes a name, in mesh order, after node names have been reserved. three.js
can name meshes in the order the nodes reach them.

**Accessors.** An accessor of floats, or of integers that are normalized
or not, is read, with its buffer view's byte stride. Sparse values overlay
the base buffer or an implicit zero array.

A mesh that mixes splat and other primitives, a splat primitive that is
not `POINTS`, a kernel that is not `ellipse`, a missing `colorSpace`, a
missing field, fields of different counts, a band that is incomplete, not
three numbers or not as many as the positions, or a band above a missing
one is refused, with three.js's reasons.
"""

from loaders.gltf_layout import AccessorLayout, check_buffer_range

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    clamped_byte,
    create_gaussian_splat_geometry,
    packed_band,
    sh_band_words,
    write_color_bytes_from_sh0,
    write_covariance,
)
from core.user_data import UserData, user_data_of
from loaders.fbx import sanitize_node_name
from loaders.gltf import decode_base64, split_glb, _apply_matrix
from core.scene import Scene
from core.object3d import NodeId, Object3D, NO_PARENT
from math.quaternion import Quaternion
from objects.gaussian_splat import GaussianSplat
from loaders.json import OBJECT, JsonDocument, parse_json
from loaders.splat import le_u32
from std.memory import bitcast
from std.math import max, nan
from std.pathlib import Path

comptime KHR_GAUSSIAN_SPLATTING = "KHR_gaussian_splatting"
# glTF's `POINTS` primitive mode.
comptime GLTF_POINTS = 0
# glTF's default mode, `TRIANGLES`.
comptime GLTF_TRIANGLES = 4
# Bound allocation for implicit zero accessors as well as stored attributes.
comptime MAX_GLTF_SPLATS = 10000000
# `glTF`, the binary container's magic, little-endian.
comptime _GLB_MAGIC = 0x46546C67


struct GltfGaussianSplatPrimitive(Copyable, Movable):
    """One splat primitive: what three.js makes a `GaussianSplat`."""

    # Its unique name.
    var name: String
    # Its index among its mesh's primitives.
    var primitive: Int
    var geometry: GaussianSplatGeometry
    # The extension object's fields, three.js's
    # `userData.gltfExtensions.KHR_gaussian_splatting`. `projection` and
    # `sorting_method` are empty when the file leaves them out.
    var kernel: String
    var color_space: String
    var projection: String
    var sorting_method: String

    def __init__(out self, name: String, primitive: Int):
        """Start a primitive with no splats.

        Args:
            name: Its name.
            primitive: Its index in its mesh.
        """
        self.name = name
        self.primitive = primitive
        self.geometry = GaussianSplatGeometry()
        self.kernel = ""
        self.color_space = ""
        self.projection = ""
        self.sorting_method = ""


struct GltfGaussianSplatMesh(Copyable, Movable):
    """One glTF mesh of splat primitives."""

    # The mesh's index in the file.
    var mesh: Int
    # The mesh's `extras`, three.js's `userData`, empty when they are not
    # an object.
    var extras: UserData
    var primitives: List[GltfGaussianSplatPrimitive]

    def __init__(out self, mesh: Int):
        """Start a mesh with no primitives.

        Args:
            mesh: The mesh's index.
        """
        self.mesh = mesh
        self.extras = UserData()
        self.primitives = List[GltfGaussianSplatPrimitive]()

    def is_group(self) -> Bool:
        """Return whether three.js makes the mesh a `Group`: when it has
        more than one primitive."""
        return len(self.primitives) > 1


struct _Accessor(Movable):
    """An accessor's numbers, element after element, as three.js's
    attribute `getX` and the rest read them."""

    var values: List[Float64]
    var count: Int
    var size: Int

    def __init__(out self, var values: List[Float64], count: Int, size: Int):
        """Hold the numbers.

        Args:
            values: `count * size` numbers.
            count: How many elements.
            size: How many numbers an element has.
        """
        self.values = values^
        self.count = count
        self.size = size


struct _Names(Movable):
    """The names used so far, three.js's `nodeNamesUsed`."""

    var names: List[String]
    var uses: List[Int]

    def __init__(out self):
        """Start with none used."""
        self.names = List[String]()
        self.uses = List[Int]()

    def unique(mut self, original: String) -> String:
        """Return a name made unique, three.js's `createUniqueName`.

        Args:
            original: The name wanted.

        Returns:
            The sanitized name, or it with `_N` after it when it was used
            before.
        """
        var name = sanitize_node_name(original)
        for at in range(len(self.names)):
            if self.names[at] == name:
                self.uses[at] += 1
                return name + "_" + String(self.uses[at])
        self.names.append(name)
        self.uses.append(0)
        return name


def _component_bytes(component: Int) raises -> Int:
    """Return how many bytes a glTF component type takes.

    Args:
        component: The `componentType`.

    Returns:
        1, 2 or 4.

    Raises:
        Error: If the type is not one of glTF's six.
    """
    if component == 5120 or component == 5121:
        return 1
    if component == 5122 or component == 5123:
        return 2
    if component == 5125 or component == 5126:
        return 4
    raise Error("glTF: unknown component type " + String(component))


def _element_size(kind: String) raises -> Int:
    """Return how many numbers an accessor type holds.

    Args:
        kind: The `type`.

    Returns:
        1 to 4.

    Raises:
        Error: If the type is not a scalar or a vector.
    """
    var kinds: List[String] = ["SCALAR", "VEC2", "VEC3", "VEC4"]
    for at in range(4):  # pragma: no branch
        if kinds[at] == kind:
            return at + 1
    raise Error("glTF: a splat attribute cannot be " + kind)


def _component(
    bytes: List[UInt8], at: Int, component: Int, normalized: Bool
) raises -> Float64:
    """Return one number, as three.js's attribute reads it.

    Args:
        bytes: The buffer.
        at: Where the number starts.
        component: The `componentType`, one of glTF's six.
        normalized: Whether an integer stands for 0 to 1, or -1 to 1.

    Returns:
        The number.

    Raises:
        Error: If the component type is not one of glTF's six.
    """
    if component == 5126:
        return Float64(bitcast[DType.float32](UInt32(le_u32(bytes, at))))
    var width = _component_bytes(component)
    var bits = width * 8
    var value = 0
    for byte in range(width):  # pragma: no branch
        value |= Int(bytes[at + byte]) << (byte * 8)
    var signed = component == 5120 or component == 5122
    var largest = (1 << bits) - 1
    if signed:
        largest = (1 << (bits - 1)) - 1
        if value > largest:
            value -= 1 << bits
    if not normalized:
        return Float64(value)
    return max(Float64(value) / Float64(largest), -1)


def _read_accessor(
    document: JsonDocument, buffers: List[List[UInt8]], index: Int
) raises -> _Accessor:
    """Return an accessor's numbers.

    Args:
        document: The glTF JSON.
        buffers: Every buffer's bytes.
        index: The accessor.

    Returns:
        Its numbers.

    Raises:
        Error: If the accessor has invalid sparse data, counts, offsets or
            strides, exceeds `MAX_GLTF_SPLATS`, names a missing buffer,
            or reaches past its buffer view or its buffer.
    """
    var accessor = document.at(
        document.get(document.root(), "accessors"), index
    )
    var component = document.integer(document.get(accessor, "componentType"))
    var width = _component_bytes(component)
    var kind = document.string(document.get(accessor, "type"))
    var size = _element_size(kind)
    var layout = AccessorLayout(kind, width)
    var count = document.integer(document.get(accessor, "count"))
    if count < 0 or count > MAX_GLTF_SPLATS:
        raise Error("glTF: a splat accessor has an invalid count")
    var offset = _offset(document, accessor)
    layout.check(count, offset)
    var normalized = False
    if document.has(accessor, "normalized"):
        normalized = document.boolean(document.get(accessor, "normalized"))
    if not document.has(accessor, "bufferView"):
        if offset != 0:
            raise Error(
                "glTF: a splat accessor without a view cannot have a byteOffset"
            )
        var values = List[Float64](length=count * size, fill=0)
        _apply_sparse_splat(
            document,
            buffers,
            accessor,
            count,
            size,
            component,
            normalized,
            values,
        )
        return _Accessor(values^, count, size)
    var view = document.at(
        document.get(document.root(), "bufferViews"),
        document.integer(document.get(accessor, "bufferView")),
    )
    var buffer_index = document.integer(document.get(view, "buffer"))
    if buffer_index < 0 or buffer_index >= len(buffers):
        raise Error("glTF: a splat buffer view names a missing buffer")
    ref buffer = buffers[buffer_index]
    var view_offset = _offset(document, view)
    var length = document.integer(document.get(view, "byteLength"))
    check_buffer_range(len(buffer), view_offset, length)
    var stride = size * width
    var explicit_stride = document.has(view, "byteStride")
    if explicit_stride:
        stride = document.integer(document.get(view, "byteStride"))
    var span = layout.span(
        count, offset, view_offset, length, stride, explicit_stride
    )
    var start = span[0]
    stride = span[1]
    # Validate the metadata before allocating or reading the output.
    var values = List[Float64](capacity=count * size)
    for element in range(count):
        for lane in range(size):  # pragma: no branch
            values.append(
                _component(
                    buffer,
                    start + element * stride + lane * width,
                    component,
                    normalized,
                )
            )
    _apply_sparse_splat(
        document, buffers, accessor, count, size, component, normalized, values
    )
    return _Accessor(values^, count, size)


def _sparse_span(
    document: JsonDocument,
    buffers: List[List[UInt8]],
    part: Int,
    size: Int,
    alignment: Int,
) raises -> Tuple[Int, Int]:
    """Check a packed sparse index or value range before it is read."""
    var view = document.at(
        document.get(document.root(), "bufferViews"),
        document.integer(document.get(part, "bufferView")),
    )
    var buffer = document.integer(document.get(view, "buffer"))
    if buffer < 0 or buffer >= len(buffers):
        raise Error("glTF: a sparse splat accessor names a missing buffer")
    var base = _offset(document, view)
    var length = document.integer(document.get(view, "byteLength"))
    check_buffer_range(len(buffers[buffer]), base, length)
    var offset = _offset(document, part)
    check_buffer_range(length, offset, size)
    if document.has(view, "byteStride") or (base + offset) % alignment != 0:
        raise Error("glTF: a sparse splat accessor must be packed and aligned")
    return (buffer, base + offset)


def _apply_sparse_splat(
    document: JsonDocument,
    buffers: List[List[UInt8]],
    accessor: Int,
    count: Int,
    width: Int,
    component: Int,
    normalized: Bool,
    mut values: List[Float64],
) raises:
    """Overlay sparse values without a Float32 precision round trip."""
    if not document.has(accessor, "sparse"):
        return
    var sparse = document.get(accessor, "sparse")
    if (
        document.kind(sparse) != OBJECT
        or not document.has(sparse, "count")
        or not document.has(sparse, "indices")
        or not document.has(sparse, "values")
    ):
        raise Error(
            "glTF: a sparse splat accessor needs count, indices and values"
        )
    var changed = document.integer(document.get(sparse, "count"))
    if changed < 1 or changed > count:
        raise Error("glTF: a sparse splat accessor has an invalid count")
    var indices = document.get(sparse, "indices")
    var data = document.get(sparse, "values")
    var index_type = document.integer(document.get(indices, "componentType"))
    if index_type != 5121 and index_type != 5123 and index_type != 5125:
        raise Error("glTF: sparse indices must be unsigned integers")
    var index_size = _component_bytes(index_type)
    var component_size = _component_bytes(component)
    var found = _sparse_span(
        document, buffers, indices, changed * index_size, index_size
    )
    var what = _sparse_span(
        document,
        buffers,
        data,
        changed * width * component_size,
        component_size,
    )
    var last = -1
    for slot in range(changed):  # pragma: no branch
        var element = Int(
            _component(
                buffers[found[0]],
                found[1] + slot * index_size,
                index_type,
                False,
            )
        )
        if element <= last or element >= count:
            raise Error(
                "glTF: sparse indices must rise and stay inside the accessor"
            )
        last = element
        for lane in range(width):  # pragma: no branch
            values[element * width + lane] = _component(
                buffers[what[0]],
                what[1] + (slot * width + lane) * component_size,
                component,
                normalized,
            )


def _offset(document: JsonDocument, node: Int) raises -> Int:
    """Return an object's `byteOffset`, zero when it has none.

    Args:
        document: The glTF JSON.
        node: The accessor or the buffer view.

    Returns:
        The offset.

    Raises:
        Error: If the offset is not an integer.
    """
    if document.has(node, "byteOffset"):
        return document.integer(document.get(node, "byteOffset"))
    return 0


def _buffers(
    document: JsonDocument, binary: List[UInt8], directory: String
) raises -> List[List[UInt8]]:
    """Return every buffer's bytes.

    Args:
        document: The glTF JSON.
        binary: The `.glb` container's binary chunk, for a buffer with no
            `uri`.
        directory: Where a relative `uri` is read from.

    Returns:
        One list of bytes a buffer.

    Raises:
        Error: If a `data:` URI is not base64, a file cannot be read, a
            buffer is shorter than its declared length, or a later
            buffer has no URI.
    """
    var out = List[List[UInt8]]()
    if not document.has(document.root(), "buffers"):
        return out^
    var list = document.get(document.root(), "buffers")
    for index in range(document.length(list)):
        var buffer = document.at(list, index)
        var length = document.integer(document.get(buffer, "byteLength"))
        if length < 0:
            raise Error("glTF: a splat buffer needs a nonnegative byteLength")
        var data: List[UInt8]
        if not document.has(buffer, "uri"):
            if index != 0:
                raise Error("glTF: only the first splat buffer can have no URI")
            data = binary.copy()
        else:
            var uri = document.string(document.get(buffer, "uri"))
            if uri.startswith("data:"):
                var comma = uri.find(",")
                if comma < 0 or not uri[byte=:comma].endswith(";base64"):
                    raise Error("glTF: a data URI that is not base64")
                data = decode_base64(String(uri[byte = comma + 1 :]))
            else:
                data = Path(directory + uri).read_bytes()
        if length > len(data):
            raise Error("glTF: a splat buffer is shorter than its byteLength")
        # GLB padding is not part of the declared buffer. Views must not
        # read it, even though the container supplies those extra bytes.
        if length < len(data):
            var trimmed = List[UInt8](data[:length])
            data = trimmed^
        out.append(data^)
    return out^


def _attribute(
    document: JsonDocument,
    buffers: List[List[UInt8]],
    attributes: Int,
    semantic: String,
) raises -> _Accessor:
    """Return a required splat attribute, three.js's
    `getGaussianSplatAttribute`.

    Args:
        document: The glTF JSON.
        buffers: Every buffer's bytes.
        attributes: The primitive's `attributes` object.
        semantic: The attribute's name.

    Returns:
        Its numbers.

    Raises:
        Error: If the primitive has no such attribute, or its accessor is
            refused.
    """
    if not document.has(attributes, semantic):
        raise Error("glTF: KHR_gaussian_splatting requires " + semantic)
    return _read_accessor(
        document, buffers, document.integer(document.get(attributes, semantic))
    )


def _is_splat(document: JsonDocument, primitive: Int) raises -> Bool:
    """Return whether a primitive has the extension, three.js's
    `isGaussianSplatPrimitive`.

    Args:
        document: The glTF JSON.
        primitive: The primitive.

    Returns:
        Whether its `extensions` has `KHR_gaussian_splatting`.

    Raises:
        Error: If `extensions` is not an object.
    """
    if not document.has(primitive, "extensions"):
        return False
    return document.has(
        document.get(primitive, "extensions"), KHR_GAUSSIAN_SPLATTING
    )


def load_gltf_gaussian_splats(
    json: String, binary: List[UInt8], directory: String
) raises -> List[GltfGaussianSplatMesh]:
    """Read the splat meshes of a glTF document.

    Args:
        json: The glTF JSON.
        binary: The `.glb` container's binary chunk, or empty.
        directory: Where relative URIs are read from, with its last slash.

    Returns:
        One entry per mesh with splat primitives, in mesh order.

    Raises:
        Error: If the JSON is refused, a buffer cannot be read, or a splat
            mesh is refused; see the module docstring.
    """
    var document = parse_json(json)
    var buffers = _buffers(document, binary, directory)
    var out = List[GltfGaussianSplatMesh]()
    var names = _Names()
    if document.has(document.root(), "nodes"):
        var nodes = document.get(document.root(), "nodes")
        for index in range(document.length(nodes)):
            var node = document.at(nodes, index)
            if document.has(node, "name"):
                var name = document.string(document.get(node, "name"))
                if name != "":
                    _ = names.unique(name)
    if not document.has(document.root(), "meshes"):
        return out^
    var meshes = document.get(document.root(), "meshes")
    for index in range(document.length(meshes)):
        var mesh = document.at(meshes, index)
        var primitives = document.get(mesh, "primitives")
        var base = "mesh_" + String(index)
        if document.has(mesh, "name"):
            base = document.string(document.get(mesh, "name"))
        var splats = 0
        for at in range(document.length(primitives)):
            if _is_splat(document, document.at(primitives, at)):
                splats += 1
        if splats == 0:
            for _ in range(document.length(primitives)):
                _ = names.unique(base)
            continue
        if splats != document.length(primitives):
            raise Error(
                "glTF: mixed gaussian and non-gaussian mesh primitives are"
                " not supported"
            )
        var found = GltfGaussianSplatMesh(index)
        if document.has(mesh, "extras"):
            var extras = document.get(mesh, "extras")
            if document.kind(extras) == OBJECT:
                found.extras = user_data_of(document, extras)
        for at in range(document.length(primitives)):  # pragma: no branch
            var splat = GltfGaussianSplatPrimitive(names.unique(base), at)
            _read_primitive(
                document, buffers, document.at(primitives, at), splat
            )
            found.primitives.append(splat^)
        out.append(found^)
    return out^


def _string_or_empty(
    document: JsonDocument, node: Int, key: String
) raises -> String:
    """Return a string field, or empty when there is none.

    Args:
        document: The glTF JSON.
        node: The object.
        key: The field.

    Returns:
        The string.

    Raises:
        Error: If the field is not a string.
    """
    if document.has(node, key):
        return document.string(document.get(node, key))
    return ""


def _read_primitive(
    document: JsonDocument,
    buffers: List[List[UInt8]],
    primitive: Int,
    mut splat: GltfGaussianSplatPrimitive,
) raises:
    """Read one splat primitive, three.js's `createGaussianSplat`.

    Args:
        document: The glTF JSON.
        buffers: Every buffer's bytes.
        primitive: The primitive.
        splat: Where its splats and its extension's fields go.

    Raises:
        Error: If the primitive is refused; see the module docstring.
    """
    var mode = GLTF_TRIANGLES
    if document.has(primitive, "mode"):
        mode = document.integer(document.get(primitive, "mode"))
    if mode != GLTF_POINTS:
        raise Error("glTF: gaussian splat primitives must use POINTS mode")
    var extension = document.get(
        document.get(primitive, "extensions"), KHR_GAUSSIAN_SPLATTING
    )
    splat.kernel = _string_or_empty(document, extension, "kernel")
    if splat.kernel != "ellipse":
        raise Error("glTF: unsupported KHR_gaussian_splatting kernel")
    if not document.has(extension, "colorSpace"):
        raise Error("glTF: KHR_gaussian_splatting colorSpace is required")
    splat.color_space = document.string(document.get(extension, "colorSpace"))
    splat.projection = _string_or_empty(document, extension, "projection")
    splat.sorting_method = _string_or_empty(
        document, extension, "sortingMethod"
    )
    var attributes = document.get(primitive, "attributes")
    var prefix = String(KHR_GAUSSIAN_SPLATTING) + ":"
    var position = _attribute(document, buffers, attributes, "POSITION")
    var scale = _attribute(document, buffers, attributes, prefix + "SCALE")
    var rotation = _attribute(
        document, buffers, attributes, prefix + "ROTATION"
    )
    var opacity = _attribute(document, buffers, attributes, prefix + "OPACITY")
    var sh0 = _attribute(
        document, buffers, attributes, prefix + "SH_DEGREE_0_COEF_0"
    )
    var count = position.count
    var same = (
        scale.count == count
        and rotation.count == count
        and opacity.count == count
        and sh0.count == count
    )
    if not same:
        raise Error(
            "glTF: KHR_gaussian_splatting attribute counts must match POSITION"
        )
    var centers = List[Float32](capacity=count * 3)
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](length=count * 4, fill=0)
    for index in range(count):
        for lane in range(3):  # pragma: no branch
            centers.append(Float32(_get(position, index, lane)))
        write_covariance(
            covariances,
            index * 6,
            _get(scale, index, 0),
            _get(scale, index, 1),
            _get(scale, index, 2),
            _get(rotation, index, 0),
            _get(rotation, index, 1),
            _get(rotation, index, 2),
            _get(rotation, index, 3),
        )
        write_color_bytes_from_sh0(
            colors,
            index * 4,
            _get(sh0, index, 0),
            _get(sh0, index, 1),
            _get(sh0, index, 2),
            _get(opacity, index, 0),
        )
    var bands = _bands(document, buffers, attributes, count)
    splat.geometry = create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


def _get(accessor: _Accessor, element: Int, lane: Int) -> Float64:
    """Return one number of an accessor, as three.js's `getX` and the rest
    read an attribute: `element * size + lane` of its numbers, whatever the
    element's size.

    Args:
        accessor: The accessor.
        element: Which element.
        lane: Which number of it.

    Returns:
        The number, the next element's when the lane is past this one's
        size, and not a number past the last, as a typed array reads
        `undefined` there.
    """
    var at = element * accessor.size + lane
    if at >= len(accessor.values):
        return nan[DType.float64]()
    return accessor.values[at]


def _bands(
    document: JsonDocument,
    buffers: List[List[UInt8]],
    attributes: Int,
    count: Int,
) raises -> List[List[UInt8]]:
    """Return the higher bands' bytes, three.js's
    `createGLTFSphericalHarmonicsAttributes`.

    Args:
        document: The glTF JSON.
        buffers: Every buffer's bytes.
        attributes: The primitive's `attributes` object.
        count: How many splats.

    Returns:
        Three lists of bytes, empty for a band that is not there.

    Raises:
        Error: If a band's attribute is not three numbers or not `count`
            of them, a band is incomplete, or a band is above a missing one.
    """
    var out = List[List[UInt8]]()
    var stop = False
    # How many bands were read: a band of no splats is read and empty.
    var bands_read = 0
    for degree in range(1, 4):  # pragma: no branch
        if stop:
            out.append(List[UInt8]())
            continue
        var found = List[_Accessor]()
        var missing = 0
        for coefficient in range(2 * degree + 1):  # pragma: no branch
            var semantic = (
                String(KHR_GAUSSIAN_SPLATTING)
                + ":SH_DEGREE_"
                + String(degree)
                + "_COEF_"
                + String(coefficient)
            )
            if not document.has(attributes, semantic):
                missing += 1
                continue
            var accessor = _read_accessor(
                document,
                buffers,
                document.integer(document.get(attributes, semantic)),
            )
            if accessor.count != count or accessor.size != 3:
                raise Error("glTF: invalid " + semantic + " attribute")
            found.append(accessor^)
        if missing == 2 * degree + 1:
            stop = True
            out.append(List[UInt8]())
            continue
        if missing > 0:
            raise Error(
                "glTF: incomplete KHR_gaussian_splatting SH degree "
                + String(degree)
                + " coefficients"
            )
        out.append(_band_bytes(found, count, degree))
        bands_read = degree
    _check_contiguous(document, attributes, bands_read)
    return out^


def _band_bytes(
    found: List[_Accessor], count: Int, degree: Int
) raises -> List[UInt8]:
    """Return one band's bytes from its coefficients' attributes.

    Args:
        found: The band's attributes, one a coefficient.
        count: How many splats.
        degree: The band.

    Returns:
        The band's bytes.

    Raises:
        Error: Never, for a degree of 1 through 3.
    """
    var band = packed_band(count, degree)
    var words = sh_band_words(degree) * 4
    for index in range(count):
        for coefficient in range(len(found)):  # pragma: no branch
            for lane in range(3):  # pragma: no branch
                band[index * words + coefficient * 3 + lane] = clamped_byte(
                    found[coefficient].values[index * 3 + lane] * 128 + 128
                )
    return band^


def _check_contiguous(
    document: JsonDocument, attributes: Int, bands_read: Int
) raises:
    """Refuse a band's attribute when the band was not read, three.js's
    last check.

    Args:
        document: The glTF JSON.
        attributes: The primitive's `attributes` object.
        bands_read: How many bands were read, 0 through 3.

    Raises:
        Error: If an attribute names band 1, 2 or 3 and that band was not
            read.
    """
    var prefix = String(KHR_GAUSSIAN_SPLATTING) + ":SH_DEGREE_"
    for at in range(document.length(attributes)):  # pragma: no branch
        var semantic = document.key(attributes, at)
        if not semantic.startswith(prefix):
            continue
        var rest = String(semantic[byte = prefix.byte_length() :])
        for degree in range(1, 4):  # pragma: no branch
            if (
                rest.startswith(String(degree) + "_COEF_")
                and degree > bands_read
            ):
                raise Error(
                    "glTF: KHR_gaussian_splatting spherical harmonics"
                    " attributes must be contiguous"
                )


def read_gltf_gaussian_splats(
    path: String,
) raises -> List[GltfGaussianSplatMesh]:
    """Read the splat meshes of a `.gltf` or a `.glb` file.

    Args:
        path: The file.

    Returns:
        Its splat meshes; see `load_gltf_gaussian_splats`.

    Raises:
        Error: If the file cannot be read, the container is refused, or
            anything `load_gltf_gaussian_splats` raises.
    """
    var bytes = Path(path).read_bytes()
    var directory = String(path[byte = : path.rfind("/") + 1])
    if len(bytes) >= 4 and le_u32(bytes, 0) == _GLB_MAGIC:
        var parts = split_glb(bytes)
        return load_gltf_gaussian_splats(parts[0], parts[1], directory)
    return load_gltf_gaussian_splats(
        String(unsafe_from_utf8=bytes), List[UInt8](), directory
    )


def _node_numbers(
    document: JsonDocument, node: Int, field: String, count: Int
) raises -> List[Float32]:
    """Read a node transform field without silently accepting a short array."""
    var out = List[Float32]()
    if not document.has(node, field):
        return out^
    var values = document.get(node, field)
    if document.length(values) != count:
        raise Error("glTF: a node transform has the wrong length")
    for index in range(count):  # pragma: no branch
        out.append(Float32(document.number(document.at(values, index))))
    return out^


def load_gltf_gaussian_splat_scene(
    json: String, binary: List[UInt8], directory: String, mut scene: Scene
) raises -> List[NodeId]:
    """Place the default glTF scene's Gaussian splats on its node hierarchy.

    Args:
        json: The glTF JSON.
        binary: The GLB binary chunk, or empty.
        directory: The base directory for relative buffer URIs.
        scene: The destination scene. Its splats enter the normal render list.

    Returns:
        Scene node IDs by glTF node index. Unreached nodes are NO_PARENT.

    Raises:
        Error: If a splat, transform, scene, or node hierarchy is malformed.
    """
    var document = parse_json(json)
    var meshes = load_gltf_gaussian_splats(json, binary, directory)
    var count = 0
    if document.has(document.root(), "nodes"):
        count = document.length(document.get(document.root(), "nodes"))
    var ids = List[NodeId](length=count, fill=NO_PARENT)
    if not document.has(document.root(), "scenes"):
        return ids^
    var chosen = 0
    if document.has(document.root(), "scene"):
        chosen = document.integer(document.get(document.root(), "scene"))
    var selected = document.at(document.get(document.root(), "scenes"), chosen)
    if not document.has(selected, "nodes"):
        return ids^
    var roots = document.get(selected, "nodes")
    var pending = List[Tuple[Int, Int]]()
    for slot in range(document.length(roots) - 1, -1, -1):
        pending.append((document.integer(document.at(roots, slot)), -1))
    var order = List[Int]()
    var parents = List[Int](length=count, fill=-1)
    var reached = List[Bool](length=count, fill=False)
    # Validate the entire selected hierarchy before adding any scene nodes.
    while len(pending) > 0:
        var entry = pending.pop()
        var index = entry[0]
        if index < 0 or index >= count:
            raise Error("glTF: a splat node index is not there")
        if reached[index]:
            raise Error("glTF: a splat node is reached twice")
        reached[index] = True
        parents[index] = entry[1]
        order.append(index)
        var node = document.at(document.get(document.root(), "nodes"), index)
        if document.has(node, "children"):
            var children = document.get(node, "children")
            for slot in range(document.length(children) - 1, -1, -1):
                pending.append(
                    (document.integer(document.at(children, slot)), index)
                )
    var names = _Names()
    var node_names = List[String]()
    for index in range(count):
        var node = document.at(document.get(document.root(), "nodes"), index)
        var name = _string_or_empty(document, node, "name")
        node_names.append(names.unique(name) if name != "" else String())
    var mesh_map = List[Int]()
    if document.has(document.root(), "meshes"):
        mesh_map = List[Int](
            length=document.length(document.get(document.root(), "meshes")),
            fill=-1,
        )
    for index in range(len(meshes)):
        mesh_map[meshes[index].mesh] = index
    for at in range(len(order)):
        var index = order[at]
        var node = document.at(document.get(document.root(), "nodes"), index)
        var placed = Object3D()
        placed.name = node_names[index]
        if document.has(node, "extras"):
            var extras = document.get(node, "extras")
            if document.kind(extras) == OBJECT:
                placed.user_data = user_data_of(document, extras)
        var matrix = _node_numbers(document, node, "matrix", 16)
        if len(matrix) > 0:
            _apply_matrix(placed, matrix)
        else:
            var position = _node_numbers(document, node, "translation", 3)
            var rotation = _node_numbers(document, node, "rotation", 4)
            var scale = _node_numbers(document, node, "scale", 3)
            if len(position) > 0:
                placed.set_position(position[0], position[1], position[2])
            if len(rotation) > 0:
                placed.set_quaternion(
                    Quaternion(
                        rotation[0], rotation[1], rotation[2], rotation[3]
                    )
                )
            if len(scale) > 0:
                placed.set_scale(scale[0], scale[1], scale[2])
        var id: NodeId
        if parents[index] < 0:
            id = scene.add(placed^)
        else:
            id = scene.attach(placed^, ids[parents[index]])
        ids[index] = id
        if not document.has(node, "mesh"):
            continue
        var mesh = document.integer(document.get(node, "mesh"))
        if mesh < 0 or mesh >= len(mesh_map):
            raise Error("glTF: a splat node names a missing mesh")
        if mesh_map[mesh] < 0:
            continue
        ref primitives = meshes[mesh_map[mesh]].primitives
        for primitive in range(len(primitives)):  # pragma: no branch
            var attached = id
            if len(primitives) > 1:
                var child = Object3D()
                child.name = primitives[primitive].name
                attached = scene.attach(child^, id)
            scene.add_gaussian_splat(
                GaussianSplat(primitives[primitive].geometry.copy(), attached)
            )
    scene.update()
    return ids^


def read_gltf_gaussian_splat_scene(
    path: String, mut scene: Scene
) raises -> List[NodeId]:
    """Read and place a glTF or GLB scene's Gaussian splats.

    Args:
        path: The document path.
        scene: The destination scene.

    Returns:
        Scene node IDs by glTF node index.

    Raises:
        Error: If the file or its splat scene is refused.
    """
    var file = Path(path)
    var bytes = file.read_bytes()
    var directory = String(path[byte = : path.rfind("/") + 1])
    if len(bytes) >= 4 and le_u32(bytes, 0) == _GLB_MAGIC:
        var parts = split_glb(bytes)
        return load_gltf_gaussian_splat_scene(
            parts[0], parts[1], directory, scene
        )
    return load_gltf_gaussian_splat_scene(
        String(unsafe_from_utf8=bytes), List[UInt8](), directory, scene
    )
