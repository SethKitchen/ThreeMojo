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
takes a name, in mesh order. three.js also counts the names of the nodes,
and names the meshes in the order the nodes reach them.

**Accessors.** An accessor of floats, or of integers that are normalized
or not, is read, with its buffer view's byte stride. A sparse accessor is
refused.

A mesh that mixes splat and other primitives, a splat primitive that is
not `POINTS`, a kernel that is not `ellipse`, a missing `colorSpace`, a
missing field, fields of different counts, a band that is incomplete, not
three numbers or not as many as the positions, or a band above a missing
one is refused, with three.js's reasons.
"""

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
from loaders.gltf import decode_base64, split_glb
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
        Error: If the accessor is sparse, of an unknown type, or reaches
            past its buffer view or its buffer.
    """
    var accessor = document.at(
        document.get(document.root(), "accessors"), index
    )
    if document.has(accessor, "sparse"):
        raise Error("glTF: a sparse splat accessor is not read")
    var component = document.integer(document.get(accessor, "componentType"))
    var width = _component_bytes(component)
    var size = _element_size(document.string(document.get(accessor, "type")))
    var count = document.integer(document.get(accessor, "count"))
    var normalized = False
    if document.has(accessor, "normalized"):
        normalized = document.boolean(document.get(accessor, "normalized"))
    var values = List[Float64](length=count * size, fill=0)
    if not document.has(accessor, "bufferView"):
        return _Accessor(values^, count, size)
    var view = document.at(
        document.get(document.root(), "bufferViews"),
        document.integer(document.get(accessor, "bufferView")),
    )
    ref buffer = buffers[document.integer(document.get(view, "buffer"))]
    var start = _offset(document, view) + _offset(document, accessor)
    var stride = size * width
    if document.has(view, "byteStride"):
        stride = document.integer(document.get(view, "byteStride"))
    var length = document.integer(document.get(view, "byteLength"))
    var reach = (
        _offset(document, accessor) + stride * (count - 1) + size * width
    )
    var outside = _offset(document, view) + length > len(buffer)
    if count > 0:
        if reach > length or outside:
            raise Error("glTF: a splat accessor reaches past its data")
    for element in range(count):
        for lane in range(size):  # pragma: no branch
            values[element * size + lane] = _component(
                buffer,
                start + element * stride + lane * width,
                component,
                normalized,
            )
    return _Accessor(values^, count, size)


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
        Error: If a `data:` URI is not base64, or a file cannot be read.
    """
    var out = List[List[UInt8]]()
    if not document.has(document.root(), "buffers"):
        return out^
    var list = document.get(document.root(), "buffers")
    for index in range(document.length(list)):
        var buffer = document.at(list, index)
        if not document.has(buffer, "uri"):
            out.append(binary.copy())
            continue
        var uri = document.string(document.get(buffer, "uri"))
        if uri.startswith("data:"):
            var comma = uri.find(",")
            if comma < 0 or not uri[byte=:comma].endswith(";base64"):
                raise Error("glTF: a data URI that is not base64")
            out.append(decode_base64(String(uri[byte = comma + 1 :])))
        else:
            out.append(Path(directory + uri).read_bytes())
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
