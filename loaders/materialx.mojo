# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A MaterialX document's materials as node materials: three.js's
`MaterialXLoader`, `examples/jsm/loaders/MaterialXLoader.js` (r180).

A `surfacematerial` whose shader is a `standard_surface` becomes a
`PHYSICAL` material, as three.js maps it to a `MeshPhysicalNodeMaterial`.
A document with no surface material makes a `BASIC` material of each
`nodegraph`, its `out` output the color. Each node of a graph becomes the
node program's node that three.js's library maps it to.

**Where this differs from three.js.**

- A surface input that is a value sets the material's own number. One
  that a graph drives becomes a node output: the color, the opacity, the
  roughness, the metalness, the glow and the normal, the node outputs this
  port has. Any other input that a graph drives is refused.
- `position` and `normal` in object space read the world ones: a fragment
  here has no object space. For a mesh at the origin the two agree.
- `smoothstep`, `splitlr` and `splittb` take their inputs as the MaterialX
  specification names them; three.js passes them in another order.
- `emission_color` multiplies `emission`, as the specification says;
  three.js reads `emissionColor`, which no document names.
- `normalmap`, `heighttonormal`, `tangent`, `frame`, `unifiednoise2d`,
  `unifiednoise3d` and the matrix nodes are refused: the program has no
  tangents, no frame count and no matrices of those types.
"""

from core.assets import Assets
from loaders.model_nodes import texture_from_file
from loaders.xml import XmlDocument, parse_xml
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    PHYSICAL,
    Material,
    MaterialId,
)
from materials.nodes import (
    COLOR_NODE,
    EMISSIVE_NODE,
    METALNESS_NODE,
    NORMAL_NODE,
    OPACITY_NODE,
    ROUGHNESS_NODE,
    NodeGraph,
    NodeRef,
)
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, linear_to_srgb
from render.texture import COVERAGE, IGNORED, REPEAT, Texture
from render.texture_store import TextureId
from std.collections import Dict
from std.math import max, min
from std.pathlib import Path
from units.si import Angle, DEGREE


@fieldwise_init
struct MaterialXMaterials(Movable):
    """What a MaterialX document holds: each material's name and its id in
    the store, three.js's `{ materials }` keyed by name."""

    var names: List[String]
    var ids: List[MaterialId]


def _byte(value: Float32) -> UInt8:
    """Return a linear channel as the sRGB byte a material keeps."""
    var held = max(Float32(0), min(Float32(1), value))
    return UInt8(Int(linear_to_srgb(held) * 255 + 0.5))


def _prefix(width: Int) -> String:
    """Return the first `width` of `xyzw`."""
    if width == 1:
        return "x"
    if width == 2:
        return "xy"
    return "xyz"


def _width(type: String) -> Int:
    """Return how many floats a MaterialX type holds, or zero for one this
    port does not read."""
    if type == "float" or type == "integer" or type == "boolean":
        return 1
    if type == "vector2":
        return 2
    if type == "vector3" or type == "color3":
        return 3
    if type == "vector4" or type == "color4":
        return 4
    return 0


def mtlx_numbers(text: String) raises -> List[Float32]:
    """Return a MaterialX value's numbers, three.js's `getVector`: split at
    commas, bars and spaces. `true` and `false` are one and zero.

    Args:
        text: The value attribute.

    Returns:
        The numbers.

    Raises:
        Error: If a part is not a number.
    """
    var found = List[Float32]()
    var word = String("")
    var bytes = text.as_bytes()
    for index in range(len(bytes) + 1):
        var byte = 32 if index == len(bytes) else Int(bytes[index])
        if byte == 44 or byte == 124 or byte == 32 or byte == 9 or byte == 10:
            if word == "true":
                found.append(1)
            elif word == "false":
                found.append(0)
            elif word != "":
                found.append(Float32(atof(word)))
            word = ""
        else:
            word += chr(byte)
    return found^


struct _Reader(Movable):
    """One document's elements by path, three.js's `nodesXLib`, and the
    graph being built for one material, with each element's node once it
    is made."""

    var document: XmlDocument
    var paths: Dict[String, Int]
    var own_paths: List[String]
    var base: String
    var graph: NodeGraph
    var made: Dict[String, Int]
    # The images read so far, by path, and the textures to add to the
    # store, which the first free id and their order name.
    var texture_keys: Dict[String, Int]
    var pending: List[Texture]
    var first_texture: Int

    def __init__(
        out self, var document: XmlDocument, base: String, first_texture: Int
    ) raises:
        """Index every named element by its path, three.js's `nodePath`."""
        self.document = document^
        self.paths = Dict[String, Int]()
        self.own_paths = List[String](length=self.document.count(), fill="")
        self.base = base
        self.graph = NodeGraph()
        self.made = Dict[String, Int]()
        self.texture_keys = Dict[String, Int]()
        self.pending = List[Texture]()
        self.first_texture = first_texture
        self._index(self.document.root(), "")

    def _index(mut self, element: Int, parent: String) raises:
        """Give an element and its children their paths."""
        var name = self.document.attribute(element, "name")
        var path = parent
        if name != "":
            path = parent + "/" + name if parent != "" else name
            self.paths[path] = element
        self.own_paths[element] = path
        var children = self.document.children(element)
        for index in range(len(children)):
            self._index(children[index], path)

    def begin(mut self):
        """Start the graph of the next material."""
        self.graph = NodeGraph()
        self.made = Dict[String, Int]()

    def tag(self, element: Int) raises -> String:
        """Return an element's tag."""
        return self.document.name(element)

    def attr(self, element: Int, key: String) raises -> String:
        """Return an attribute, or an empty string."""
        return self.document.attribute(element, key)

    def has(self, element: Int, key: String) raises -> Bool:
        """Return whether an element has an attribute."""
        return self.document.has_attribute(element, key)

    def child_named(self, element: Int, name: String) raises -> Int:
        """Return the child whose `name` is `name`, or -1."""
        var children = self.document.children(element)
        for index in range(len(children)):
            if self.attr(children[index], "name") == name:
                return children[index]
        return -1

    def graph_path(self, element: Int) raises -> String:
        """Return the path of the `nodegraph` an element is in, or the
        document's for none, three.js's `getNodeGraph().nodePath`."""
        var at = element
        while at >= 0:
            if self.tag(at) == "nodegraph":
                return self.own_paths[at]
            at = self.document.parent(at)
        return ""

    def recursive_attr(self, element: Int, key: String) raises -> String:
        """Return an attribute of the element or of the nearest parent
        that has it."""
        var at = element
        while at >= 0:
            if self.has(at, key):
                return self.attr(at, key)
            at = self.document.parent(at)
        return ""

    def refers(self, element: Int) raises -> Bool:
        """Return True if an element names another, three.js's
        `hasReference`."""
        return (
            (self.attr(element, "nodegraph") != "" and self.attr(element, "output") != "")
            or self.attr(element, "nodename") != ""
            or self.attr(element, "interfacename") != ""
        )

    # --- nodes ------------------------------------------------------------

    def input(mut self, element: Int, name: String) raises -> NodeRef:
        """Return the node an element's input feeds, or `NodeRef(-1)` for an
        input it does not have, three.js's `getNodeByName`."""
        var child = self.child_named(element, name)
        if child < 0:
            return NodeRef(-1)
        return self.node(child, self.attr(child, "output"))

    def input_or(
        mut self, element: Int, name: String, default: Float32
    ) raises -> NodeRef:
        """Return an input's node, or a constant when it is absent."""
        var found = self.input(element, name)
        return found if found.value >= 0 else self.graph.float(default)

    def input_value(
        self, element: Int, name: String, default: Float32
    ) raises -> Float32:
        """Return an input's value, which must be a value and not a graph,
        or a default when it is absent."""
        var child = self.child_named(element, name)
        if child < 0:
            return default
        if not self.has(child, "value"):
            raise Error(
                "MaterialX: the input "
                + name
                + " of "
                + self.tag(element)
                + " must be a value"
            )
        return mtlx_numbers(self.attr(child, "value"))[0]

    def needed(mut self, element: Int, name: String) raises -> NodeRef:
        """Return an input's node, which the element must have."""
        var found = self.input(element, name)
        if found.value < 0:
            raise Error(
                "MaterialX: " + self.tag(element) + " needs its input " + name
            )
        return found

    def node(mut self, element: Int, port: String = "") raises -> NodeRef:
        """Return the node an element makes, three.js's `getNode(out)`,
        each once, cast to its type."""
        var key = String(element) + ":" + port
        if key in self.made:
            return NodeRef(self.made[key])
        var built = self.make(element, port)
        var type = self.attr(element, "type")
        var tag = self.tag(element)
        var split = tag.startswith("separate") and port.startswith("out")
        if _width(type) > 0 and not split:
            built = self.cast(built, _width(type))
        self.made[key] = built.value
        return built

    def cast(mut self, node: NodeRef, want: Int) raises -> NodeRef:
        """Return a node at a width: a `float` repeated into a vector, a
        vector cut to fewer components, or padded with zeros and a `w` of
        one, as TSL converts one."""
        var have = self.graph.type_of(node).value
        if have == want or have > 4:
            return node
        if have == 1:
            var parts = List[NodeRef]()
            for _ in range(want):
                parts.append(node)
            return self.graph.join(parts)
        if want < have:
            return self.graph.swizzle(node, _prefix(want))
        var parts: List[NodeRef] = [node]
        for index in range(have, want):
            parts.append(self.graph.float(Float32(1) if index == 3 else Float32(0)))
        return self.graph.join(parts)

    def constant(mut self, element: Int) raises -> NodeRef:
        """Return an input's value as a constant of its type."""
        var type = self.attr(element, "type")
        var values = mtlx_numbers(self.attr(element, "value"))
        var width = _width(type)
        if width == 0 or len(values) < width:
            raise Error(
                "MaterialX: a value of type " + type + " that is not read"
            )
        if width == 1:
            return self.graph.float(values[0])
        if width == 2:
            return self.graph.vec2(values[0], values[1])
        if width == 3:
            return self.graph.vec3(values[0], values[1], values[2])
        return self.graph.vec4(values[0], values[1], values[2], values[3])

    def make(mut self, element: Int, port: String) raises -> NodeRef:
        """Make an element's node, three.js's `getNode` before its cast."""
        var tag = self.tag(element)
        var name = self.attr(element, "name")
        var type = self.attr(element, "type")
        var valued = self.has(element, "value")
        if tag == "input" and valued and type != "filename":
            return self.constant(element)
        if self.refers(element):
            var wanted = port
            var target: String
            if self.attr(element, "nodegraph") != "" and self.attr(element, "output") != "":
                # Here `output` names the graph's output, which says its
                # own port.
                target = self.attr(element, "nodegraph") + "/" + self.attr(element, "output")
                wanted = ""
            else:
                var named = self.attr(element, "nodename")
                if named == "":
                    named = self.attr(element, "interfacename")
                var within = self.graph_path(element)
                target = within + "/" + named if within != "" else named
                if tag == "output" and wanted == "":
                    wanted = self.attr(element, "output")
            if target not in self.paths:
                raise Error("MaterialX: nothing is named " + target)
            return self.node(self.paths[target], wanted)
        if tag == "input" and name == "texcoord" and type == "vector2":
            return self.graph.uv()
        return self.library(element, tag, port)

    def texture(mut self, file: Int) raises -> TextureId:
        """Return the texture a `file` input names, read once: repeating,
        rows from the top, and decoded from sRGB when its color space says
        so, three.js's `getTexture`."""
        var uri = self.recursive_attr(file, "fileprefix") + self.attr(
            file, "value"
        )
        var srgb = self.attr(file, "colorspace") == "srgb_texture"
        var key = uri + ("|srgb" if srgb else "")
        if key not in self.texture_keys:
            var built = texture_from_file(
                self.base + uri,
                SRGB if srgb else LINEAR,
                REPEAT,
                COVERAGE if srgb else IGNORED,
            )
            built.flip_y = False
            self.texture_keys[key] = len(self.pending)
            self.pending.append(built^)
        return TextureId(self.first_texture + self.texture_keys[key])

    def image(mut self, element: Int, at: NodeRef) raises -> NodeRef:
        """Return an image read at a coordinate."""
        var file = self.child_named(element, "file")
        if file < 0:
            raise Error("MaterialX: an image needs its file")
        return self.graph.texture(self.texture(file), at)

    def library(mut self, element: Int, tag: String, port: String) raises -> NodeRef:
        """Return a node of three.js's library, `MtlXLibrary`."""
        # << Geometry >>
        if tag == "position":
            return self.graph.position_world()
        if tag == "normal":
            return self.graph.normal_world()
        if tag == "texcoord":
            return self.graph.uv()
        if tag == "geomcolor":
            return self.graph.vertex_color()
        if tag == "time":
            return self.graph.time()
        if tag == "constant":
            return self.needed(element, "value")
        if tag == "convert" or tag == "dot":
            return self.needed(element, "in")
        if tag == "image":
            var at = self.input(element, "texcoord")
            return self.image(element, at if at.value >= 0 else self.graph.uv())
        if tag == "tiledimage":
            var at = self.input(element, "texcoord")
            if at.value < 0:
                at = self.graph.uv()
            var tiled = self.graph.mul(
                at, self._vec2_or(element, "uvtiling", 1)
            )
            return self.image(
                element,
                self.graph.add(tiled, self._vec2_or(element, "uvoffset", 0)),
            )
        # << Math >>
        if tag == "add" or tag == "subtract" or tag == "multiply" or tag == "divide" or tag == "modulo" or tag == "power" or tag == "atan2" or tag == "min" or tag == "max" or tag == "dotproduct" or tag == "crossproduct" or tag == "distance" or tag == "safepower":
            var a = self.needed(element, "in1")
            var b = self.input_or(
                element,
                "in2",
                Float32(0) if tag == "add" or tag == "subtract" else Float32(1),
            )
            if tag == "add":
                return self.graph.add(a, b)
            if tag == "subtract":
                return self.graph.sub(a, b)
            if tag == "multiply":
                return self.graph.mul(a, b)
            if tag == "divide":
                return self.graph.div(a, b)
            if tag == "modulo":
                return self.graph.mod(a, b)
            if tag == "power":
                return self.graph.pow(a, b)
            if tag == "atan2":
                return self.graph.atan2(a, b)
            if tag == "min":
                return self.graph.min(a, b)
            if tag == "max":
                return self.graph.max(a, b)
            if tag == "dotproduct":
                return self.graph.dot(a, b)
            if tag == "crossproduct":
                return self.graph.cross(a, b)
            if tag == "distance":
                return self.graph.distance(a, b)
            # safepower: the sign kept, the power of the size.
            return self.graph.mul(
                self.graph.sign(a), self.graph.pow(self.graph.abs(a), b)
            )
        if tag == "absval" or tag == "sign" or tag == "floor" or tag == "ceil" or tag == "round" or tag == "sin" or tag == "cos" or tag == "tan" or tag == "asin" or tag == "acos" or tag == "sqrt" or tag == "ln" or tag == "exp" or tag == "normalize" or tag == "magnitude" or tag == "length":
            var x = self.input(element, "in")
            if x.value < 0:
                x = self.needed(element, "in1")
            if tag == "absval":
                return self.graph.abs(x)
            if tag == "sign":
                return self.graph.sign(x)
            if tag == "floor":
                return self.graph.floor(x)
            if tag == "ceil":
                return self.graph.ceil(x)
            if tag == "round":
                return self.graph.round(x)
            if tag == "sin":
                return self.graph.sin(x)
            if tag == "cos":
                return self.graph.cos(x)
            if tag == "tan":
                return self.graph.tan(x)
            if tag == "asin":
                return self.graph.asin(x)
            if tag == "acos":
                return self.graph.acos(x)
            if tag == "sqrt":
                return self.graph.sqrt(x)
            if tag == "ln":
                return self.graph.log(x)
            if tag == "exp":
                return self.graph.exp(x)
            if tag == "normalize":
                return self.graph.normalize(x)
            return self.graph.length(x)
        if tag == "clamp":
            return self.graph.clamp(
                self.needed(element, "in"),
                self.input_or(element, "low", 0),
                self.input_or(element, "high", 1),
            )
        if tag == "invert":
            return self.graph.sub(
                self.input_or(element, "amount", 1), self.needed(element, "in")
            )
        if tag == "reflect":
            return self.graph.reflect(
                self.needed(element, "in"), self.needed(element, "normal")
            )
        if tag == "refract":
            return self.graph.refract(
                self.needed(element, "in"),
                self.needed(element, "normal"),
                self.input_or(element, "ior", 1),
            )
        # << Adjustment >>
        if tag == "remap":
            return self.graph.remap(
                self.needed(element, "in"),
                self.input_or(element, "inlow", 0),
                self.input_or(element, "inhigh", 1),
                self.input_or(element, "outlow", 0),
                self.input_or(element, "outhigh", 1),
            )
        if tag == "smoothstep":
            return self.graph.smoothstep(
                self.input_or(element, "low", 0),
                self.input_or(element, "high", 1),
                self.needed(element, "in"),
            )
        if tag == "luminance":
            return self.luminance(element, self.needed(element, "in"))
        if tag == "saturate":
            var color = self.cast(self.needed(element, "in"), 3)
            var gray = self.luminance(element, color)
            return self.graph.mix(
                self.cast(gray, 3), color, self.input_or(element, "amount", 1)
            )
        if tag == "contrast":
            var pivot = self.input_or(element, "pivot", 0.5)
            return self.graph.add(
                self.graph.mul(
                    self.graph.sub(self.needed(element, "in"), pivot),
                    self.input_or(element, "amount", 1),
                ),
                pivot,
            )
        if tag == "rgbtohsv":
            return self.rgb_to_hsv(self.cast(self.needed(element, "in"), 3))
        if tag == "hsvtorgb":
            return self.hsv_to_rgb(self.cast(self.needed(element, "in"), 3))
        # << Mix and channels >>
        if tag == "mix":
            return self.graph.mix(
                self.input_or(element, "bg", 0),
                self.input_or(element, "fg", 0),
                self.input_or(element, "mix", 0),
            )
        if tag == "combine2" or tag == "combine3" or tag == "combine4":
            var parts = List[NodeRef]()
            var count = 2 if tag == "combine2" else (3 if tag == "combine3" else 4)
            for index in range(count):
                parts.append(
                    self.cast(self.input_or(element, "in" + String(index + 1), 0), 1)
                )
            return self.graph.join(parts)
        if tag == "separate2" or tag == "separate3" or tag == "separate4":
            var whole = self.needed(element, "in")
            var which = port if port != "" else "outx"
            var component = String(which[byte=3:4])
            if component == "r":
                component = "x"
            elif component == "g":
                component = "y"
            elif component == "b":
                component = "z"
            elif component == "a":
                component = "w"
            return self.graph.swizzle(whole, component)
        if tag == "extract":
            var index = Int(self.input_value(element, "index", 0))
            if index < 0 or index > 3:
                raise Error("MaterialX: extract reads a component zero to three")
            return self.graph.swizzle(
                self.needed(element, "in"),
                String(String("xyzw")[byte=index : index + 1]),
            )
        if tag == "ifgreater" or tag == "ifgreatereq" or tag == "ifequal":
            var a = self.input_or(element, "value1", 1)
            var b = self.input_or(element, "value2", 0)
            var test = self.graph.greater_than(a, b) if tag == "ifgreater" else (
                self.graph.greater_than_equal(a, b) if tag == "ifgreatereq" else self.graph.equal(a, b)
            )
            return self.graph.select(
                test, self.input_or(element, "in1", 0), self.input_or(element, "in2", 0)
            )
        # << Procedural >>
        if tag == "ramplr" or tag == "ramptb":
            var at = self._texcoord(element)
            var first = "valuel" if tag == "ramplr" else "valuet"
            var second = "valuer" if tag == "ramplr" else "valueb"
            var along = self.graph.swizzle(at, "x" if tag == "ramplr" else "y")
            return self.graph.mix(
                self.input_or(element, first, 0),
                self.input_or(element, second, 0),
                self.graph.clamp(along, self.graph.float(0), self.graph.float(1)),
            )
        if tag == "splitlr" or tag == "splittb":
            var at = self._texcoord(element)
            var first = "valuel" if tag == "splitlr" else "valuet"
            var second = "valuer" if tag == "splitlr" else "valueb"
            var along = self.graph.swizzle(at, "x" if tag == "splitlr" else "y")
            return self.graph.mix(
                self.input_or(element, first, 0),
                self.input_or(element, second, 0),
                self.graph.step(self.input_or(element, "center", 0.5), along),
            )
        if tag == "ramp4":
            var at = self._texcoord(element)
            var s = self.graph.clamp(self.graph.swizzle(at, "x"), self.graph.float(0), self.graph.float(1))
            var t = self.graph.clamp(self.graph.swizzle(at, "y"), self.graph.float(0), self.graph.float(1))
            var top = self.graph.mix(
                self.input_or(element, "valuetl", 0), self.input_or(element, "valuetr", 0), s
            )
            var bottom = self.graph.mix(
                self.input_or(element, "valuebl", 0), self.input_or(element, "valuebr", 0), s
            )
            return self.graph.mix(top, bottom, t)
        if tag == "noise2d" or tag == "noise3d":
            var at = self._point(element, "texcoord" if tag == "noise2d" else "position")
            var width = _width(self.attr(element, "type"))
            var noise = self.graph.perlin_noise(at) if width == 1 else self.graph.perlin_noise_vec3(at)
            return self.graph.add(
                self.graph.mul(noise, self.input_or(element, "amplitude", 1)),
                self.input_or(element, "pivot", 0),
            )
        if tag == "fractal3d":
            return self.graph.mul(
                self.graph.mx_fractal_noise_float(
                    self._point(element, "position"),
                    Int(self.input_value(element, "octaves", 3)),
                    self.input_value(element, "lacunarity", 2),
                    self.input_value(element, "diminish", 0.5),
                ),
                self.input_or(element, "amplitude", 1),
            )
        if tag == "cellnoise2d" or tag == "cellnoise3d":
            return self.graph.cell_noise_float(
                self._point(element, "texcoord" if tag == "cellnoise2d" else "position")
            )
        if tag == "worleynoise2d" or tag == "worleynoise3d":
            var width = _width(self.attr(element, "type"))
            return self.graph.worley_noise(
                self._point(element, "texcoord" if tag == "worleynoise2d" else "position"),
                self.input_or(element, "jitter", 1),
                width,
            )
        # << Supplemental >>
        if tag == "place2d":
            return self.place2d(element)
        if tag == "rotate2d":
            return self.rotate2d(
                self.needed(element, "in"), self.input_or(element, "amount", 0)
            )
        if tag == "rotate3d":
            return self.rotate3d(
                self.needed(element, "in"),
                self.input_or(element, "amount", 0),
                self.cast(self.input_or(element, "axis", 0), 3),
            )
        raise Error("MaterialX: the node " + tag + " is not read")

    def _texcoord(mut self, element: Int) raises -> NodeRef:
        """Return a node's `texcoord` input, or the surface's first set of
        coordinates."""
        var at = self.input(element, "texcoord")
        return at if at.value >= 0 else self.graph.uv()

    def _point(mut self, element: Int, name: String) raises -> NodeRef:
        """Return a noise's point: its input, or the coordinates for a
        `texcoord` and the position for a `position`."""
        var at = self.input(element, name)
        if at.value >= 0:
            return at
        return self.graph.uv() if name == "texcoord" else self.graph.position_world()

    def _vec2_or(mut self, element: Int, name: String, default: Float32) raises -> NodeRef:
        """Return a `vector2` input, or both components a default."""
        var found = self.input(element, name)
        return found if found.value >= 0 else self.graph.vec2(default, default)

    def luminance(mut self, element: Int, color: NodeRef) raises -> NodeRef:
        """Return a color's luminance by the node's coefficients, or
        three.js's Rec. 709 ones."""
        var weights = self.input(element, "lumacoeffs")
        if weights.value < 0:
            weights = self.graph.vec3(0.2126, 0.7152, 0.0722)
        return self.graph.dot(self.cast(color, 3), self.cast(weights, 3))

    def rgb_to_hsv(mut self, c: NodeRef) raises -> NodeRef:
        """Return MaterialX's `mx_rgbtohsv`: hue, saturation and value,
        each zero to one."""
        ref g = self.graph
        var r = g.swizzle(c, "x")
        var gr = g.swizzle(c, "y")
        var b = g.swizzle(c, "z")
        var top = g.max(r, g.max(gr, b))
        var bottom = g.min(r, g.min(gr, b))
        var delta = g.sub(top, bottom)
        var saturation = g.select(
            g.greater_than(top, g.float(0)), g.div(delta, top), g.float(0)
        )
        var safe = g.select(
            g.greater_than(delta, g.float(0)), delta, g.float(1)
        )
        # The hue's sixth by which channel is the largest.
        var from_red = g.div(g.sub(gr, b), safe)
        var from_green = g.add(g.float(2), g.div(g.sub(b, r), safe))
        var from_blue = g.add(g.float(4), g.div(g.sub(r, gr), safe))
        var sixth = g.select(
            g.greater_than_equal(r, top),
            from_red,
            g.select(g.greater_than_equal(gr, top), from_green, from_blue),
        )
        var hue = g.div(sixth, g.float(6))
        hue = g.select(g.less_than(hue, g.float(0)), g.add(hue, g.float(1)), hue)
        hue = g.select(g.greater_than(delta, g.float(0)), hue, g.float(0))
        return g.join([hue, saturation, top])

    def hsv_to_rgb(mut self, c: NodeRef) raises -> NodeRef:
        """Return MaterialX's `mx_hsvtorgb`, the inverse of `rgb_to_hsv`,
        as a continuous function of the hue."""
        ref g = self.graph
        var hue = g.swizzle(c, "x")
        var s = g.swizzle(c, "y")
        var v = g.swizzle(c, "z")
        var k = g.vec3(0, 2.0 / 3.0, 1.0 / 3.0)
        var p = g.abs(
            g.sub(
                g.mul(g.fract(g.add(g.join([hue, hue, hue]), k)), g.float(6)),
                g.float(3),
            )
        )
        var rgb = g.clamp(g.sub(p, g.float(1)), g.float(0), g.float(1))
        return g.mul(v, g.mix(g.vec3(1, 1, 1), rgb, s))

    def place2d(mut self, element: Int) raises -> NodeRef:
        """Return MaterialX's `place2d` in its default order, scale, rotate
        then translate, about the pivot."""
        var at = self._texcoord(element)
        var pivot = self._vec2_or(element, "pivot", 0)
        var moved = self.graph.div(
            self.graph.sub(at, pivot), self._vec2_or(element, "scale", 1)
        )
        moved = self.rotate2d(
            moved, self.graph.negate(self.input_or(element, "rotate", 0))
        )
        return self.graph.add(
            self.graph.sub(moved, self._vec2_or(element, "offset", 0)), pivot
        )

    def rotate2d(mut self, at: NodeRef, degrees: NodeRef) raises -> NodeRef:
        """Return MaterialX's `mx_rotate_vector2`: a point turned by an
        angle in degrees."""
        ref g = self.graph
        var turn = g.radians(degrees)
        var sine = g.sin(turn)
        var cosine = g.cos(turn)
        var x = g.swizzle(at, "x")
        var y = g.swizzle(at, "y")
        return g.join(
            [
                g.add(g.mul(cosine, x), g.mul(sine, y)),
                g.sub(g.mul(cosine, y), g.mul(sine, x)),
            ]
        )

    def rotate3d(
        mut self, at: NodeRef, degrees: NodeRef, axis: NodeRef
    ) raises -> NodeRef:
        """Return MaterialX's `mx_rotate_vector3`: a point turned about an
        axis by an angle in degrees, Rodrigues' formula."""
        ref g = self.graph
        var unit = g.normalize(axis)
        var turn = g.radians(degrees)
        var sine = g.sin(turn)
        var cosine = g.cos(turn)
        var along = g.mul(unit, g.mul(g.dot(unit, at), g.one_minus(cosine)))
        return g.add(
            g.add(g.mul(at, cosine), g.mul(g.cross(unit, at), sine)), along
        )


def _set_surface(mut reader: _Reader, shader: Int, mut material: Material) raises:
    """Give a physical material a `standard_surface`'s inputs, three.js's
    `setStandardSurfaceToGltfPBR`: a value as the material's own number,
    and a graph as a node output."""
    var inputs = reader.document.children(shader)
    var color = NodeRef(-1)
    var coat_color = NodeRef(-1)
    var emission = NodeRef(-1)
    var emission_color = NodeRef(-1)
    for index in range(len(inputs)):
        var entry = inputs[index]
        if reader.tag(entry) != "input":
            continue
        var name = reader.attr(entry, "name")
        var value = reader.has(entry, "value") and not reader.refers(entry)
        var numbers = List[Float32]()
        if value:
            numbers = mtlx_numbers(reader.attr(entry, "value"))
        var node = reader.node(entry, reader.attr(entry, "output"))
        if name == "base":
            color = node if color.value < 0 else reader.graph.mul(node, color)
        elif name == "base_color":
            color = node if color.value < 0 else reader.graph.mul(color, node)
        elif name == "opacity":
            reader.graph.set_output(
                OPACITY_NODE, reader.graph.swizzle(reader.cast(node, 3), "x")
            )
            material.transparent = True
        elif name == "specular_roughness":
            if value:
                material.roughness = numbers[0]
            else:
                reader.graph.set_output(ROUGHNESS_NODE, reader.cast(node, 1))
        elif name == "metalness":
            if value:
                material.metalness = numbers[0]
            else:
                reader.graph.set_output(METALNESS_NODE, reader.cast(node, 1))
        elif name == "coat_color":
            coat_color = node
        elif name == "emission":
            emission = node
        elif name == "emission_color":
            emission_color = node
        elif name == "normal":
            # A replacement normal, as three.js's `normalNode` is; the
            # output here is an offset from the surface's own.
            reader.graph.set_output(
                NORMAL_NODE,
                reader.graph.sub(reader.cast(node, 3), reader.graph.normal_world()),
            )
        elif not value:
            raise Error(
                "MaterialX: a graph that drives "
                + name
                + " is not ported: set it to a value"
            )
        elif name == "specular":
            material.specular_intensity = numbers[0]
        elif name == "specular_color":
            material.specular_color = Color(
                _byte(numbers[0]), _byte(numbers[1]), _byte(numbers[2])
            )
        elif name == "ior":
            material.ior = numbers[0]
        elif name == "specular_anisotropy":
            material.anisotropy = numbers[0]
        elif name == "specular_rotation":
            material.anisotropy_rotation = Angle(numbers[0] * 360, DEGREE)
        elif name == "transmission":
            material.transmission = numbers[0]
            if numbers[0] > 0:
                material.side = DOUBLE_SIDE
                material.transparent = True
        elif name == "thin_film_thickness":
            if numbers[0] > 0:
                material.iridescence = 1
        elif name == "thin_film_ior":
            material.iridescence_ior = max(Float32(1), min(Float32(2.333), numbers[0]))
        elif name == "sheen":
            material.sheen = numbers[0]
        elif name == "sheen_color":
            material.sheen_color = Color(
                _byte(numbers[0]), _byte(numbers[1]), _byte(numbers[2])
            )
        elif name == "sheen_roughness":
            material.sheen_roughness = numbers[0]
        elif name == "coat":
            material.clearcoat = numbers[0]
        elif name == "coat_roughness":
            material.clearcoat_roughness = numbers[0]
    # The color: the base times its color, times the coat's color, or
    # three.js's gray.
    if color.value < 0:
        color = reader.graph.vec3(0.8, 0.8, 0.8)
    if coat_color.value >= 0:
        color = reader.graph.mul(color, coat_color)
    reader.graph.set_output(COLOR_NODE, reader.cast(color, 3))
    if emission.value >= 0:
        var glow = emission
        if emission_color.value >= 0:
            glow = reader.graph.mul(glow, emission_color)
        reader.graph.set_output(EMISSIVE_NODE, reader.cast(glow, 3))


def read_materialx(
    text: String, mut assets: Assets, base: String = ""
) raises -> MaterialXMaterials:
    """Read a MaterialX document's materials into the store, three.js's
    `MaterialXLoader.parse`.

    Args:
        text: The `.mtlx` document.
        assets: Where the materials, their programs and their textures go.
        base: What each image's path is read after: the document's folder,
            with its slash.

    Returns:
        Each material's name and id.

    Raises:
        Error: If the document is not XML, names an element that is not
            there, uses a node this port does not read, or an image cannot
            be read.
    """
    var reader = _Reader(parse_xml(text), base, assets.textures.count())
    var names = List[String]()
    var programs = List[NodeGraph]()
    var shaded = List[Bool]()
    var materials = List[Material]()
    var root = reader.document.root()
    var children = reader.document.children(root)
    for index in range(len(children)):
        var entry = children[index]
        if reader.tag(entry) != "surfacematerial":
            continue
        reader.begin()
        var material = Material(Color(255, 255, 255), kind=PHYSICAL)
        var graphed = False
        var inputs = reader.document.children(entry)
        for at in range(len(inputs)):
            var shader_name = reader.attr(inputs[at], "nodename")
            if shader_name == "" or shader_name not in reader.paths:
                continue
            var shader = reader.paths[shader_name]
            var kind = reader.tag(shader)
            if kind == "standard_surface":
                _set_surface(reader, shader, material)
                graphed = True
            elif kind != "gltf_pbr":
                raise Error("MaterialX: the surface " + kind + " is not read")
        names.append(reader.attr(entry, "name"))
        programs.append(reader.graph.copy())
        shaded.append(graphed)
        materials.append(material^)
    if len(names) == 0:
        # No surface: each node graph's `out` is the color of an unlit
        # material, three.js's `toBasicMaterial`.
        for index in range(len(children)):
            var entry = children[index]
            if reader.tag(entry) != "nodegraph":
                continue
            var output = reader.child_named(entry, "out")
            if output < 0:
                continue
            reader.begin()
            reader.graph.set_output(COLOR_NODE, reader.cast(reader.node(output), 3))
            names.append(reader.attr(entry, "name"))
            programs.append(reader.graph.copy())
            shaded.append(True)
            materials.append(Material(Color(255, 255, 255), kind=BASIC))
    # Every image the graphs read, in the order they were given ids.
    for index in range(len(reader.pending)):
        _ = assets.textures.add(Texture(copy=reader.pending[index]))
    var ids = List[MaterialId]()
    for index in range(len(materials)):
        var material = materials[index].copy()
        # A glTF surface, which three.js leaves as it is, runs no program.
        if shaded[index]:
            material.nodes = assets.programs.add(programs[index].compile())
        ids.append(assets.materials.add(material))
    return MaterialXMaterials(names^, ids^)


def load_materialx(path: String, mut assets: Assets) raises -> MaterialXMaterials:
    """Read a `.mtlx` file's materials into the store, its images read from
    beside it: three.js's `MaterialXLoader.load`.

    Args:
        path: The file.
        assets: Where the materials, their programs and their textures go.

    Returns:
        Each material's name and id.

    Raises:
        Error: Everything `read_materialx` raises, and if the file cannot be
            read.
    """
    var folder = String("")
    var slash = path.rfind("/")
    if slash >= 0:
        folder = String(path[byte=0 : slash + 1])
    return read_materialx(Path(path).read_text(), assets, folder)
