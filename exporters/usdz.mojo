# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene written as a USDZ file for AR Quick Look: three.js's
`USDZExporter`.

A USDZ file is a ZIP archive that is not compressed, with each file's
data at a multiple of 64 bytes. It holds `model.usda`, one
`geometries/Geometry_<id>.usda` for each geometry, and one
`textures/Texture_<id>_true.png` for each texture. `usdz_files` gives
those files, and `export_usdz` gives the archive.

**The scene.** `model.usda` has a `Root` with a `Scenes` scope and a
`Scene` under it, which holds the AR anchoring properties. Each node in
the scene is written under it, in `Scene.children` order:

- A node that carries one mesh of a `STANDARD` or `PHYSICAL` material
  is an `Xform` that references its geometry file and binds its
  material. A mesh of any other material is not written, and nor is
  anything under its node, as in three.js.
- A node that carries one camera of `cameras` is a `Camera`.
- Every other node is an `Xform`. Lights, lines and points are not
  written, as in three.js.
- A node that carries more than one mesh or camera is an `Xform`, with
  one child for each, named `Object` or `Camera`. three.js has no such
  node: one object is one mesh.

A name keeps only `A-Z`, `a-z`, `0-9` and `_`. It gets a `_` in front
of a digit, is `Object` or `Camera` when it is empty, and gets `_` and
the node's id after it when an earlier node has it. A hidden node and
all under it are left out, unless `only_visible` is off.

**The materials.** Each material is a `UsdPreviewSurface`, with the
inputs that three.js writes: the color or the `map`, the emissive color
or the `emissive_map`, the `normal_map`, the `ao_map`, the roughness,
the metalness and the opacity, or their maps. A `PHYSICAL` material also
writes its clear coat and its index of refraction. Each map is a
`UsdPrimvarReader_float2`, a `UsdTransform2d` of the texture's repeat,
offset and rotation, and a `UsdUVTexture`.

**The numbers.** A vertex value is written with seven significant
digits, as three.js writes it. Every other number, which three.js holds
as a double and this port holds as a `Float32`, is written as the
shortest text that reads back to the `Float32`, so `0.1` is written as
`0.1`. A color is held here as sRGB bytes. It is written as the linear
doubles that three.js's `setHex` of the same bytes holds. The sums of a texture transform are worked out in doubles from
those texts, as three.js works them out. So the text is three.js's text
for any scene whose numbers are short decimals. A matrix is this port's
`Float32` matrix. A turn that a `Float32` cannot hold exactly, such as
thirty degrees, is written a few units apart in the last digits.

**Where this port differs.** three.js draws each texture on a canvas
and scales it to `maxTextureSize`. This port writes the texture's own
pixels as a PNG from `render.png`, at its own size. A texture file is
named for the texture's id, as three.js names it for its source's id.
Each file of the archive starts at a multiple of 64 bytes, as USDZ
asks. three.js pads each file by a count that is right only for the
first file. A geometry that is not whole triangles is refused. three.js
throws a `RangeError` for it.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.gltf import gltf_pixels
from loaders.js_number import (
    js_float32_text,
    js_number_text,
    js_to_fixed,
    js_to_precision,
    srgb_to_linear,
)
from loaders.object_loader import ObjectCameras
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from materials.material import (
    NO_TEXTURE,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
)
from math.matrix4 import Matrix4
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.srgb import SRGB
from render.texture import CLAMP, MIRROR, REPEAT, Texture, Wrap
from render.texture_store import TextureId
from std.math import cos, pi, sin, tan
from units.si import DEGREE, METER

# The significant digits of a vertex value: three.js's `PRECISION`.
comptime _PRECISION = 7
# three.js's `PerspectiveCamera.filmGauge` and `focus`, in millimeters
# and meters, which this port's camera does not hold.
comptime FILM_GAUGE = 35.0
comptime FOCUS = 10.0


struct UsdzOptions(Copyable, Movable):
    """The options of three.js's `USDZExporter.parseAsync`."""

    # `ar.anchoring.type`: `plane`, `image`, `face` or `none`.
    var anchoring_type: String
    # `ar.planeAnchoring.alignment`: `horizontal`, `vertical` or `any`.
    var plane_alignment: String
    # Write the two anchoring properties on the scene.
    var include_anchoring_properties: Bool
    # Leave out a hidden node and all under it.
    var only_visible: Bool
    # Write texture transforms the way AR Quick Look reads them.
    var quick_look_compatible: Bool

    def __init__(out self):
        """Take three.js's defaults."""
        self.anchoring_type = "plane"
        self.plane_alignment = "horizontal"
        self.include_anchoring_properties = True
        self.only_visible = True
        self.quick_look_compatible = False


@fieldwise_init
struct _Property(Copyable, Movable):
    """A property line and the metadata lines under it."""

    var text: String
    var metadata: List[String]


struct _UsdNode(Copyable, Movable):
    """three.js's `USDNode`: a `def` with metadata, properties and
    children, written as text."""

    var name: String
    var type: String
    var metadata_keys: List[String]
    # A metadata value. When the entry's `metadata_lines` are not empty,
    # they are written in braces instead.
    var metadata_values: List[String]
    var metadata_lines: List[List[String]]
    var properties: List[_Property]
    # Each child's text at indent zero. A struct cannot hold a list of
    # itself, and a child's text at a deeper indent is its text with tabs
    # in front of each line that is not empty.
    var children: List[String]

    def __init__(out self, name: String, type: String = ""):
        """Start a node with nothing in it."""
        self.name = name
        self.type = type
        self.metadata_keys = List[String]()
        self.metadata_values = List[String]()
        self.metadata_lines = List[List[String]]()
        self.properties = List[_Property]()
        self.children = List[String]()

    def add_metadata(mut self, key: String, value: String):
        """Add a metadata entry of one value."""
        self.metadata_keys.append(key)
        self.metadata_values.append(value)
        self.metadata_lines.append(List[String]())

    def add_metadata_lines(mut self, key: String, var lines: List[String]):
        """Add a metadata entry of lines in braces."""
        self.metadata_keys.append(key)
        self.metadata_values.append("")
        self.metadata_lines.append(lines^)

    def add_property(
        mut self, text: String, var metadata: List[String] = List[String]()
    ):
        """Add a property, with metadata lines or none."""
        self.properties.append(_Property(text, metadata^))

    def add_child(mut self, child: _UsdNode):
        """Add a node under this one."""
        self.children.append(child.text())

    def text(self, indent: Int = 0) -> String:
        """Return the node as three.js's `toString` writes it."""
        var pad = "\t" * indent
        var meta = String()
        if len(self.metadata_keys) > 0:
            var lines = List[String]()
            # There is metadata here. The loop always runs.
            for i in range(len(self.metadata_keys)):  # pragma: no branch
                var entry: String
                if len(self.metadata_lines[i]) > 0:
                    entry = self.metadata_keys[i] + " = {"
                    # There are lines here. The loop always runs.
                    for line in self.metadata_lines[i]:  # pragma: no branch
                        entry += "\n" + pad + "\t\t" + line
                    entry += "\n" + pad + "\t}"
                else:
                    entry = (
                        self.metadata_keys[i] + " = " + self.metadata_values[i]
                    )
                lines.append(pad + "\t" + entry)
            meta = " (\n" + "\n".join(lines) + "\n" + pad + ")"
        var body = List[String]()
        for p in self.properties:
            var line = pad + "\t" + p.text
            if len(p.metadata) > 0:
                var inner = List[String]()
                # There is metadata here. The loop always runs.
                for m in p.metadata:  # pragma: no branch
                    inner.append(pad + "\t\t" + m)
                line += " (\n" + "\n".join(inner) + "\n" + pad + "\t)"
            body.append(line)
        if len(self.children) > 0 and len(self.properties) > 0:
            body.append("")
        for i in range(len(self.children)):
            body.append(_indented(self.children[i], "\t" * (indent + 1)))
            if i < len(self.children) - 1:
                body.append("")
        var kind = self.type + " " if self.type.byte_length() > 0 else ""
        return (
            pad
            + "def "
            + kind
            + '"'
            + self.name
            + '"'
            + meta
            + "\n"
            + pad
            + "{\n"
            + "\n".join(body)
            + "\n"
            + pad
            + "}"
        )


def _indented(text: String, pad: String) -> String:
    """Return text with `pad` in front of each line that is not empty."""
    var lines = List[String]()
    # A text has one line or more. The loop always runs.
    for line in text.split("\n"):  # pragma: no branch
        if line.byte_length() > 0:
            lines.append(pad + String(line))
        else:
            lines.append(String())
    return "\n".join(lines)


def usda_header() -> String:
    """Return the layer header that three.js writes at the top of each
    `.usda` file.

    Returns:
        The header, with its last new line.
    """
    return (
        "#usda 1.0\n(\n\tcustomLayerData = {\n\t\tstring creator ="
        ' "Three.js USDZExporter"\n\t}\n\tdefaultPrim = "Root"\n\t'
        'metersPerUnit = 1\n\tupAxis = "Y"\n)\n'
    )


def usd_name(name: String, fallback: String) -> String:
    """Return a name as three.js's `getName` cleans it, before a clash.

    Args:
        name: The node's name.
        fallback: `Object` or `Camera`, for a name with nothing left.

    Returns:
        The name with only `A-Z`, `a-z`, `0-9` and `_`, and a `_` in
        front of a digit.
    """
    var out = String()
    for b in name.as_bytes():
        var keep = (
            (b >= 65 and b <= 90)
            or (b >= 97 and b <= 122)
            or (b >= 48 and b <= 57)
            or b == 95
        )
        if keep:
            out += chr(Int(b))
    if out.byte_length() == 0:
        return fallback
    # Every byte kept is `0` or above, so a digit is one up to `9`.
    if out.as_bytes()[0] <= 57:
        return "_" + out
    return out


def _js(value: Float32) raises -> Float64:
    """Return the double that the shortest text of a `Float32` spells:
    the number three.js holds when the scene said that text."""
    return Float64(js_float32_text(value))


def _f(value: Float32) raises -> String:
    """Return a `Float32` as three.js writes the double it holds."""
    return js_float32_text(value)


def _matrix(m: Matrix4) raises -> String:
    """Return three.js's `buildMatrix`: four rows of the column-major
    elements."""
    var rows = List[String]()
    # Four rows. The loop always runs.
    for r in range(4):  # pragma: no branch
        var items = List[String]()
        # Four columns. The loop always runs.
        for c in range(4):  # pragma: no branch
            items.append(_f(m.elements[r * 4 + c]))
        rows.append("(" + ", ".join(items) + ")")
    return "( " + ", ".join(rows) + " )"


def _channels(c: Color) raises -> List[String]:
    """Return the three linear channels that three.js's `setHex` of a
    color holds, as three.js writes them."""
    return [
        js_number_text(srgb_to_linear(c.r)),
        js_number_text(srgb_to_linear(c.g)),
        js_number_text(srgb_to_linear(c.b)),
    ]


def _color(c: Color) raises -> String:
    """Return three.js's `buildColor`."""
    return "(" + ", ".join(_channels(c)) + ")"


def _color4(r: String, g: String, b: String) -> String:
    """Return three.js's `buildColor4`."""
    return "(" + r + ", " + g + ", " + b + ", 1.0)"


def _vector3s(attribute: BufferAttribute) raises -> String:
    """Return three.js's `buildVector3Array` of an attribute."""
    var items = List[String]()
    for i in range(attribute.count()):
        var parts = List[String]()
        # Three values. The loop always runs.
        for k in range(3):  # pragma: no branch
            parts.append(
                js_to_precision(Float64(attribute.component(i, k)), _PRECISION)
            )
        items.append("(" + ", ".join(parts) + ")")
    return ", ".join(items)


def _vector2s(attribute: BufferAttribute) raises -> String:
    """Return three.js's `buildVector2Array`: `y` flipped, after it is cut
    to seven digits."""
    var items = List[String]()
    for i in range(attribute.count()):
        var x = js_to_precision(Float64(attribute.component(i, 0)), _PRECISION)
        var y = js_to_precision(Float64(attribute.component(i, 1)), _PRECISION)
        items.append("(" + x + ", " + js_number_text(1 - Float64(y)) + ")")
    return ", ".join(items)


def usda_geometry(geometry: BufferGeometry) raises -> String:
    """Return a geometry's `.usda` file, as three.js writes it: the header
    and its `buildMeshObject`.

    Args:
        geometry: The geometry. It needs `position`.

    Returns:
        The file's text.

    Raises:
        Error: If the geometry has no `position`, or its triangles are not
            whole.
    """
    if not geometry.has_attribute(String(POSITION)):
        raise Error("USDZ: a geometry needs a position attribute")
    var position = geometry.clone_attribute(String(POSITION))
    var count = position.count()
    var indexed = len(geometry.index) > 0
    var corners = len(geometry.index) if indexed else count
    if corners % 3 != 0:
        raise Error(
            "USDZ: a geometry must be whole triangles, not "
            + String(corners)
            + " corners"
        )
    var mesh = _UsdNode("Geometry", "Mesh")
    var threes = List[String]()
    var indices = List[String]()
    for i in range(corners):
        if i % 3 == 0:
            threes.append("3")
        indices.append(String(geometry.index[i] if indexed else i))
    mesh.add_property("int[] faceVertexCounts = [" + ", ".join(threes) + "]")
    mesh.add_property(
        "int[] faceVertexIndices = [" + ", ".join(indices) + "]"
    )
    var normals: String
    if geometry.has_attribute(String(NORMAL)):
        normals = _vector3s(geometry.clone_attribute(String(NORMAL)))
    else:
        var zeros = List[String]()
        for _ in range(count):
            zeros.append("(0, 0, 0)")
        normals = ", ".join(zeros)
    var vertex: List[String] = ['interpolation = "vertex"']
    mesh.add_property("normal3f[] normals = [" + normals + "]", vertex.copy())
    mesh.add_property("point3f[] points = [" + _vector3s(position) + "]")
    # Four sets of coordinates. The loop always runs.
    for i in range(4):  # pragma: no branch
        var suffix = String(i) if i > 0 else ""
        if geometry.has_attribute("uv" + suffix):
            mesh.add_property(
                "texCoord2f[] primvars:st"
                + suffix
                + " = ["
                + _vector2s(geometry.clone_attribute("uv" + suffix))
                + "]",
                vertex.copy(),
            )
    if geometry.has_attribute(String(COLOR)):
        mesh.add_property(
            "color3f[] primvars:displayColor = ["
            + _vector3s(geometry.clone_attribute(String(COLOR)))
            + "]",
            vertex.copy(),
        )
    mesh.add_property('uniform token subdivisionScheme = "none"')
    var node = _UsdNode("Geometry")
    node.add_child(mesh)
    return usda_header() + "\n" + node.text()


def _wrap_name(wrap: Wrap) raises -> String:
    """Return three.js's `WRAPPINGS` of a wrap."""
    if wrap == REPEAT:
        return "repeat"
    if wrap == CLAMP:
        return "clamp"
    if wrap == MIRROR:
        return "mirror"
    raise Error("USDZ: a texture's wrap is none of the three")


def _has(values: List[Int], value: Int) -> Bool:
    """Return True if a list holds a value."""
    for v in values:
        if v == value:
            return True
    return False


struct _Exporter(Movable):
    """What three.js's `parseAsync` keeps as it goes: the names used, the
    geometry files, the materials and the textures."""

    var names: List[String]
    var geometry_ids: List[Int]
    var geometry_files: List[String]
    var materials: List[Int]
    var textures: List[Int]
    var options: UsdzOptions

    def __init__(out self, var options: UsdzOptions):
        """Start with nothing written."""
        self.names = List[String]()
        self.geometry_ids = List[Int]()
        self.geometry_files = List[String]()
        self.materials = List[Int]()
        self.textures = List[Int]()
        self.options = options^

    def name(mut self, node: NodeId, name: String, fallback: String) -> String:
        """Return three.js's `getName`, and keep it as used."""
        var out = usd_name(name, fallback)
        for used in self.names:
            if used == out:
                out = out + "_" + String(node.value)
                break
        self.names.append(out)
        return out

    def xform(
        mut self, node: NodeId, name: String, matrix: Matrix4
    ) raises -> _UsdNode:
        """Return three.js's `buildXform`."""
        var out = _UsdNode(self.name(node, name, "Object"), "Xform")
        out.add_property("matrix4d xformOp:transform = " + _matrix(matrix))
        out.add_property(
            'uniform token[] xformOpOrder = ["xformOp:transform"]'
        )
        return out^

    def mesh(
        mut self,
        node: NodeId,
        name: String,
        matrix: Matrix4,
        which: Int,
        scene: Scene,
        assets: Assets,
    ) raises -> Optional[_UsdNode]:
        """Return three.js's `buildMesh` for a mesh, or nothing for a mesh
        whose material is neither `STANDARD` nor `PHYSICAL`."""
        ref mesh = scene.meshes[which]
        ref material = assets.materials.get(mesh.material)
        if material.kind != STANDARD and material.kind != PHYSICAL:
            return None
        var id = mesh.geometry.value
        if not _has(self.geometry_ids, id):
            self.geometry_ids.append(id)
            self.geometry_files.append(
                usda_geometry(assets.geometries.get(mesh.geometry))
            )
        if not _has(self.materials, mesh.material.value):
            self.materials.append(mesh.material.value)
        var out = self.xform(node, name, matrix)
        out.add_metadata(
            "prepend references",
            "@./geometries/Geometry_" + String(id) + ".usda@</Geometry>",
        )
        out.add_metadata("prepend apiSchemas", '["MaterialBindingAPI"]')
        out.add_property(
            "rel material:binding = </Materials/Material_"
            + String(mesh.material.value)
            + ">"
        )
        return out^

    def _camera(
        mut self,
        node: NodeId,
        name: String,
        matrix: Matrix4,
        projection: String,
        near: Float32,
        far: Float32,
    ) raises -> _UsdNode:
        """Return the transform, projection and clipping of a camera."""
        var out = _UsdNode(self.name(node, name, "Camera"), "Camera")
        out.add_property("matrix4d xformOp:transform = " + _matrix(matrix))
        out.add_property(
            'uniform token[] xformOpOrder = ["xformOp:transform"]'
        )
        out.add_property('token projection = "' + projection + '"')
        out.add_property(
            "float2 clippingRange = ("
            + js_to_precision(_js(near), _PRECISION)
            + ", "
            + js_to_precision(_js(far), _PRECISION)
            + ")"
        )
        return out^

    def perspective(
        mut self,
        node: NodeId,
        name: String,
        matrix: Matrix4,
        camera: PerspectiveCamera,
    ) raises -> _UsdNode:
        """Return three.js's `buildCamera` for a perspective camera."""
        var out = self._camera(
            node,
            name,
            matrix,
            "perspective",
            Float32(camera.near.to(METER)),
            Float32(camera.far.to(METER)),
        )
        var aspect = _js(camera.aspect)
        var height = FILM_GAUGE / max(aspect, 1.0)
        out.add_property(
            "float horizontalAperture = "
            + js_to_precision(FILM_GAUGE * min(aspect, 1.0), _PRECISION)
        )
        out.add_property(
            "float verticalAperture = " + js_to_precision(height, _PRECISION)
        )
        var fov = _js(Float32(camera.fov.to(DEGREE)))
        var focal = 0.5 * height / tan(pi / 180 * 0.5 * fov)
        out.add_property(
            "float focalLength = " + js_to_precision(focal, _PRECISION)
        )
        out.add_property(
            "float focusDistance = " + js_to_precision(FOCUS, _PRECISION)
        )
        return out^

    def orthographic(
        mut self,
        node: NodeId,
        name: String,
        matrix: Matrix4,
        camera: OrthographicCamera,
    ) raises -> _UsdNode:
        """Return three.js's `buildCamera` for an orthographic camera."""
        var out = self._camera(
            node,
            name,
            matrix,
            "orthographic",
            Float32(camera.near.to(METER)),
            Float32(camera.far.to(METER)),
        )
        var wide = (
            abs(_js(Float32(camera.left.to(METER))))
            + abs(_js(Float32(camera.right.to(METER))))
        ) * 10
        var tall = (
            abs(_js(Float32(camera.top.to(METER))))
            + abs(_js(Float32(camera.bottom.to(METER))))
        ) * 10
        out.add_property(
            "float horizontalAperture = " + js_to_precision(wide, _PRECISION)
        )
        out.add_property(
            "float verticalAperture = " + js_to_precision(tall, _PRECISION)
        )
        return out^

    def texture_nodes(
        mut self,
        mut parent: _UsdNode,
        material: Material,
        material_id: Int,
        id: TextureId,
        map_type: String,
        color: String,
        assets: Assets,
    ) raises:
        """Add three.js's `buildTextureNodes`: a primvar reader, a 2D
        transform and a texture, with a scale when `color` is not empty.
        """
        ref texture = assets.textures.get(id)
        if not texture.channel.is_valid():
            raise Error("USDZ: a texture's channel is not valid")
        var wrap_s = _wrap_name(texture.wrap_s)
        var wrap_t = _wrap_name(texture.wrap_t)
        if not _has(self.textures, id.value):
            self.textures.append(id.value)
        var uv = "st"
        if texture.channel.value > 0:
            uv += String(texture.channel.value)
        var path = "</Materials/Material_" + String(material_id) + "/"
        var rx = _js(texture.repeat.x)
        var ry = _js(texture.repeat.y)
        var ox = _js(texture.offset.x)
        var oy = _js(texture.offset.y)
        var rotation = _js(Float32(texture.rotation.value))
        var sx = sin(rotation)
        var cy = cos(rotation)
        oy = 1 - oy - ry
        if self.options.quick_look_compatible:
            ox = ox / rx
            oy = oy / ry
            ox += sx / rx
            oy += cy - 1
        else:
            ox += sx * rx
            oy += (1 - cy) * ry
        var reader = _UsdNode("PrimvarReader_" + map_type, "Shader")
        reader.add_property(
            'uniform token info:id = "UsdPrimvarReader_float2"'
        )
        reader.add_property("float2 inputs:fallback = (0.0, 0.0)")
        reader.add_property('token inputs:varname = "' + uv + '"')
        reader.add_property("float2 outputs:result")
        var transform = _UsdNode("Transform2d_" + map_type, "Shader")
        transform.add_property('uniform token info:id = "UsdTransform2d"')
        transform.add_property(
            "token inputs:in.connect = "
            + path
            + "PrimvarReader_"
            + map_type
            + ".outputs:result>"
        )
        transform.add_property(
            "float inputs:rotation = "
            + js_to_fixed(rotation * (180 / pi), _PRECISION)
        )
        transform.add_property(
            "float2 inputs:scale = ("
            + js_number_text(rx)
            + ", "
            + js_number_text(ry)
            + ")"
        )
        transform.add_property(
            "float2 inputs:translation = ("
            + js_number_text(ox)
            + ", "
            + js_number_text(oy)
            + ")"
        )
        transform.add_property("float2 outputs:result")
        var node = _UsdNode(
            "Texture_" + String(id.value) + "_" + map_type, "Shader"
        )
        node.add_property('uniform token info:id = "UsdUVTexture"')
        node.add_property(
            "asset inputs:file = @textures/Texture_"
            + String(id.value)
            + "_true.png@"
        )
        node.add_property(
            "float2 inputs:st.connect = "
            + path
            + "Transform2d_"
            + map_type
            + ".outputs:result>"
        )
        if color.byte_length() > 0:
            node.add_property("float4 inputs:scale = " + color)
        var space = "sRGB" if texture.color_space == SRGB else "raw"
        node.add_property('token inputs:sourceColorSpace = "' + space + '"')
        node.add_property('token inputs:wrapS = "' + wrap_s + '"')
        node.add_property('token inputs:wrapT = "' + wrap_t + '"')
        node.add_property("float outputs:r")
        node.add_property("float outputs:g")
        node.add_property("float outputs:b")
        node.add_property("float3 outputs:rgb")
        if material.transparent or material.alpha_test > 0:
            node.add_property("float outputs:a")
        parent.add_child(reader)
        parent.add_child(transform)
        parent.add_child(node)

    def scalar(
        mut self,
        mut out: _UsdNode,
        mut surface: _UsdNode,
        material: Material,
        id: Int,
        map: TextureId,
        value: Float32,
        input: String,
        channel: String,
        assets: Assets,
    ) raises:
        """Add a one-number input: its map, scaled by the number, or the
        number."""
        if map == NO_TEXTURE:
            surface.add_property("float inputs:" + input + " = " + _f(value))
            return
        surface.add_property(
            "float inputs:"
            + input
            + ".connect = </Materials/Material_"
            + String(id)
            + "/Texture_"
            + String(map.value)
            + "_"
            + input
            + ".outputs:"
            + channel
            + ">"
        )
        var v = _f(value)
        self.texture_nodes(
            out, material, id, map, input, _color4(v, v, v), assets
        )

    def material(mut self, id: Int, assets: Assets) raises -> _UsdNode:
        """Return three.js's `buildMaterial`."""
        var material = assets.materials.get(MaterialId(id))
        var name = "Material_" + String(id)
        var out = _UsdNode(name, "Material")
        var path = "</Materials/" + name + "/Texture_"
        var surface = _UsdNode("PreviewSurface", "Shader")
        surface.add_property('uniform token info:id = "UsdPreviewSurface"')
        if material.map != NO_TEXTURE:
            var texture = (
                path + String(material.map.value) + "_diffuse.outputs:"
            )
            surface.add_property(
                "color3f inputs:diffuseColor.connect = " + texture + "rgb>"
            )
            if material.transparent:
                surface.add_property(
                    "float inputs:opacity.connect = " + texture + "a>"
                )
            elif material.alpha_test > 0:
                surface.add_property(
                    "float inputs:opacity.connect = " + texture + "a>"
                )
                surface.add_property(
                    "float inputs:opacityThreshold = "
                    + _f(material.alpha_test)
                )
            var c = _channels(material.color)
            self.texture_nodes(
                out,
                material,
                id,
                material.map,
                "diffuse",
                _color4(c[0], c[1], c[2]),
                assets,
            )
        else:
            surface.add_property(
                "color3f inputs:diffuseColor = " + _color(material.color)
            )
        if material.emissive_map != NO_TEXTURE:
            surface.add_property(
                "color3f inputs:emissiveColor.connect = "
                + path
                + String(material.emissive_map.value)
                + "_emissive.outputs:rgb>"
            )
            var k = _js(material.emissive_intensity)
            var e = material.emissive
            self.texture_nodes(
                out,
                material,
                id,
                material.emissive_map,
                "emissive",
                _color4(
                    js_number_text(srgb_to_linear(e.r) * k),
                    js_number_text(srgb_to_linear(e.g) * k),
                    js_number_text(srgb_to_linear(e.b) * k),
                ),
                assets,
            )
        elif material.emissive.hex() > 0:
            surface.add_property(
                "color3f inputs:emissiveColor = " + _color(material.emissive)
            )
        if material.normal_map != NO_TEXTURE:
            surface.add_property(
                "normal3f inputs:normal.connect = "
                + path
                + String(material.normal_map.value)
                + "_normal.outputs:rgb>"
            )
            self.texture_nodes(
                out, material, id, material.normal_map, "normal", "", assets
            )
        if material.ao_map != NO_TEXTURE:
            surface.add_property(
                "float inputs:occlusion.connect = "
                + path
                + String(material.ao_map.value)
                + "_occlusion.outputs:r>"
            )
            var a = _f(material.ao_map_intensity)
            self.texture_nodes(
                out,
                material,
                id,
                material.ao_map,
                "occlusion",
                _color4(a, a, a),
                assets,
            )
        self.scalar(
            out,
            surface,
            material,
            id,
            material.roughness_map,
            material.roughness,
            "roughness",
            "g",
            assets,
        )
        self.scalar(
            out,
            surface,
            material,
            id,
            material.metalness_map,
            material.metalness,
            "metallic",
            "b",
            assets,
        )
        if material.alpha_map != NO_TEXTURE:
            surface.add_property(
                "float inputs:opacity.connect = "
                + path
                + String(material.alpha_map.value)
                + "_opacity.outputs:r>"
            )
            surface.add_property("float inputs:opacityThreshold = 0.0001")
            self.texture_nodes(
                out, material, id, material.alpha_map, "opacity", "", assets
            )
        else:
            surface.add_property(
                "float inputs:opacity = " + _f(material.opacity)
            )
        if material.kind == PHYSICAL:
            self.scalar(
                out,
                surface,
                material,
                id,
                material.clearcoat_map,
                material.clearcoat,
                "clearcoat",
                "r",
                assets,
            )
            self.scalar(
                out,
                surface,
                material,
                id,
                material.clearcoat_roughness_map,
                material.clearcoat_roughness,
                "clearcoatRoughness",
                "g",
                assets,
            )
            surface.add_property("float inputs:ior = " + _f(material.ior))
        surface.add_property("int inputs:useSpecularWorkflow = 0")
        surface.add_property("token outputs:surface")
        out.add_child(surface)
        out.add_property(
            "token outputs:surface.connect = </Materials/"
            + name
            + "/PreviewSurface.outputs:surface>"
        )
        return out^


def _matrix_of(node: Object3D) raises -> Matrix4:
    """Return a node's own matrix, three.js's `object.matrix`."""
    if node.matrix_auto_update:
        return node.local_matrix()
    return node.matrix


struct UsdzFiles(Movable):
    """The files of a USDZ archive, in the order three.js writes them."""

    var names: List[String]
    var data: List[List[UInt8]]

    def __init__(out self):
        """Start with no files."""
        self.names = List[String]()
        self.data = List[List[UInt8]]()

    def add(mut self, name: String, var data: List[UInt8]):
        """Add a file.

        Args:
            name: Its path in the archive.
            data: Its bytes.
        """
        self.names.append(name)
        self.data.append(data^)

    def text(self, name: String) raises -> String:
        """Return a `.usda` file's text.

        Args:
            name: The file's path, such as `model.usda`.

        Returns:
            The text.

        Raises:
            Error: If there is no such file.
        """
        # There is always `model.usda`. The loop always runs.
        for i in range(len(self.names)):  # pragma: no branch
            if self.names[i] == name:
                return String(unsafe_from_utf8=self.data[i])
        raise Error("USDZ: no file named " + name)


def _build(
    mut exporter: _Exporter,
    mut parent: _UsdNode,
    index: NodeId,
    scene: Scene,
    assets: Assets,
    cameras: ObjectCameras,
    meshes: List[List[Int]],
) raises:
    """Add the nodes under `index` to `parent`: three.js's
    `buildHierarchy`."""
    for child in scene.children(index):
        var node = scene.get(child)
        if not node.visible and exporter.options.only_visible:
            continue
        var matrix = _matrix_of(node)
        ref carried = meshes[child.value]
        var perspective = List[Int]()
        for i in range(len(cameras.perspective)):
            if cameras.perspective[i].node == child:
                perspective.append(i)
        var orthographic = List[Int]()
        for i in range(len(cameras.orthographic)):
            if cameras.orthographic[i].node == child:
                orthographic.append(i)
        var things = len(carried) + len(perspective) + len(orthographic)
        var out: Optional[_UsdNode]
        if things == 1 and len(carried) == 1:
            out = exporter.mesh(
                child, node.name, matrix, carried[0], scene, assets
            )
        elif things == 1 and len(perspective) == 1:
            out = exporter.perspective(
                child, node.name, matrix, cameras.perspective[perspective[0]]
            )
        elif things == 1:
            out = exporter.orthographic(
                child,
                node.name,
                matrix,
                cameras.orthographic[orthographic[0]],
            )
        else:
            var group = exporter.xform(child, node.name, matrix)
            var still = Matrix4()
            for m in carried:
                var item = exporter.mesh(child, "", still, m, scene, assets)
                if item is not None:
                    group.add_child(item.value())
            for i in perspective:
                group.add_child(
                    exporter.perspective(
                        child, "", still, cameras.perspective[i]
                    )
                )
            for i in orthographic:
                group.add_child(
                    exporter.orthographic(
                        child, "", still, cameras.orthographic[i]
                    )
                )
            out = group^
        if out is not None:
            var built = out.take()
            _build(exporter, built, child, scene, assets, cameras, meshes)
            parent.add_child(built)


def usdz_files(
    scene: Scene,
    assets: Assets,
    cameras: ObjectCameras = ObjectCameras(),
    options: UsdzOptions = UsdzOptions(),
) raises -> UsdzFiles:
    """Return the files of a scene's USDZ archive: `model.usda`, the
    geometry files and the textures.

    Args:
        scene: The scene. Its nodes are written by their own transforms.
        assets: Where its geometries, materials and textures are.
        cameras: The cameras that ride nodes of the scene.
        options: The options of three.js's `parseAsync`.

    Returns:
        The files, in the order three.js writes them.

    Raises:
        Error: If a mesh names a node, a geometry, a material or a
            texture that is not there, a geometry has no position or is
            not whole triangles, or a texture is blank, holds floats, or
            has a wrap or a channel that is not valid.
    """
    var count = scene.count()
    var meshes = List[List[Int]](length=count, fill=List[Int]())
    for which in range(len(scene.meshes)):
        var node = scene.meshes[which].node
        if node.value < 0 or node.value >= count:
            raise Error("USDZ: a mesh names a node that is not in the scene")
        meshes[node.value].append(which)
    var exporter = _Exporter(options.copy())
    var top = _UsdNode("Scene", "Xform")
    top.add_metadata_lines(
        "customData",
        [
            "bool preliminary_collidesWithEnvironment = 0",
            'string sceneName = "Scene"',
        ],
    )
    top.add_metadata("sceneName", '"Scene"')
    if options.include_anchoring_properties:
        top.add_property(
            'token preliminary:anchoring:type = "'
            + options.anchoring_type
            + '"'
        )
        top.add_property(
            'token preliminary:planeAnchoring:alignment = "'
            + options.plane_alignment
            + '"'
        )
    _build(exporter, top, NO_PARENT, scene, assets, cameras, meshes)
    var scenes = _UsdNode("Scenes", "Scope")
    scenes.add_metadata("kind", '"sceneLibrary"')
    scenes.add_child(top)
    var root = _UsdNode("Root", "Xform")
    root.add_child(scenes)
    var materials = _UsdNode("Materials")
    for id in exporter.materials.copy():
        materials.add_child(exporter.material(id, assets))
    var files = UsdzFiles()
    var model = usda_header() + "\n" + root.text() + "\n\n" + materials.text()
    files.add("model.usda", List[UInt8](model.as_bytes()))
    for i in range(len(exporter.geometry_ids)):
        files.add(
            "geometries/Geometry_"
            + String(exporter.geometry_ids[i])
            + ".usda",
            List[UInt8](exporter.geometry_files[i].as_bytes()),
        )
    for id in exporter.textures:
        ref texture = assets.textures.get(TextureId(id))
        var pixels = gltf_pixels(texture)
        files.add(
            "textures/Texture_" + String(id) + "_true.png",
            encode_png(Framebuffer(texture.width, texture.height, pixels^)),
        )
    return files^


def export_usdz(
    scene: Scene,
    assets: Assets,
    cameras: ObjectCameras = ObjectCameras(),
    options: UsdzOptions = UsdzOptions(),
) raises -> List[UInt8]:
    """Return a scene as a USDZ archive, as three.js's `USDZExporter`
    writes it.

    Args:
        scene: The scene. Its nodes are written by their own transforms.
        assets: Where its geometries, materials and textures are.
        cameras: The cameras that ride nodes of the scene.
        options: The options of three.js's `parseAsync`.

    Returns:
        The archive: the files of `usdz_files`, stored, each at a
        multiple of 64 bytes.

    Raises:
        Error: Everything `usdz_files` raises.
    """
    var files = usdz_files(scene, assets, cameras, options)
    var entries = List[ZipEntry]()
    # There is always `model.usda`. The loop always runs.
    for i in range(len(files.names)):  # pragma: no branch
        entries.append(
            ZipEntry(files.names[i], ZIP_STORED, files.data[i].copy())
        )
    return zip_archive(entries, 64)
