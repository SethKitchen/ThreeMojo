# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""G-code toolpaths, from three.js `examples/jsm/loaders/GCodeLoader.js`.

A G-code file is text, one command a line. `gcode_layers` reads the moves
as three.js's `parse` reads them, and `gcode_scene` adds three.js's
objects to a scene.

**What is read.** A `;` and the rest of its line is a comment. A line is
cut at each space: the first word is the command, and each other word is
a letter and a number. These commands are read:

- `G0` and `G1` move to the `X`, `Y` and `Z` they give. A move that
  raises `E` extrudes; the others are travel.
- `G90` and `G91` set absolute and relative positions.
- `G92` sets the position without a move.

Other commands, and `G2` and `G3` arcs, are stepped over, as three.js
steps over them. A number is read as JavaScript's `parseFloat` reads it.
A word with no number gives NaN, as it does in three.js.

**Layers.** A move that extrudes at a new height starts a layer. Each
layer keeps its extruded segments and its travel segments apart.

**Where three.js's quirks are kept.** A command is compared with its
case raised but with any carriage return kept, so `G1\\r` is not a move.
Each move starts a new state, so `G91` holds for the next move only. A
comment needs a character after its `;`, so a lone `;` is kept in its
word.

**The objects.** `gcode_scene` adds a node named `gcode`, turned a
quarter turn back about x so that z is up. Under it go line segments
named `layer` and a number: one pair for each layer with `split_layer`,
or one pair for the whole file. The extruded lines are green and the
travel lines red, three.js's two `LineBasicMaterial`s.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.js_number import js_parse_float
from materials.material import BASIC, Material, MaterialId
from math.vector3 import Vector3
from objects.line import SEGMENTS, Line
from render.framebuffer import Color
from std.math import pi
from std.pathlib import Path
from units.si import RADIAN, Angle


struct GCodeLayer(Copyable, Movable):
    """One layer: its height, and its segments, two points each."""

    # The segments drawn while extruding, three.js's `vertex`.
    var vertex: List[Float64]
    # The travel segments, three.js's `pathVertex`.
    var path_vertex: List[Float64]
    # The height the layer started at.
    var z: Float64

    def __init__(out self, z: Float64):
        """Start a layer with no segments.

        Args:
            z: The height it starts at.
        """
        self.vertex = List[Float64]()
        self.path_vertex = List[Float64]()
        self.z = z


@fieldwise_init
struct _State(Copyable, Movable):
    """Where the tool is, three.js's `state`."""

    var x: Float64
    var y: Float64
    var z: Float64
    var e: Float64
    var f: Float64
    var relative: Bool


def _is_terminator(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return True if a JavaScript line terminator starts at a byte: `\\n`,
    `\\r`, U+2028 or U+2029, which a regular expression's `.` does not
    match.

    Args:
        bytes: The text.
        at: The byte.

    Returns:
        Whether a line terminator starts there.
    """
    var b = bytes[at]
    if b == 10 or b == 13:
        return True
    return (
        b == 0xE2
        and at + 2 < len(bytes)
        and bytes[at + 1] == 0x80
        and (bytes[at + 2] == 0xA8 or bytes[at + 2] == 0xA9)
    )


def _uncommented(text: String) -> String:
    """Return the text with three.js's `/;.+/g` removed: a `;` and the
    rest of its line, when at least one character follows it.

    Args:
        text: The file.

    Returns:
        The text with no comments.
    """
    var bytes = text.as_bytes()
    var kept = List[UInt8](capacity=len(bytes))
    var at = 0
    while at < len(bytes):
        var comment = (
            bytes[at] == 59
            and at + 1 < len(bytes)
            and not _is_terminator(bytes, at + 1)
        )
        if comment:
            while at < len(bytes) and not _is_terminator(bytes, at):
                at += 1
        else:
            kept.append(bytes[at])
            at += 1
    return String(unsafe_from_utf8=kept)


def _absolute(state: _State, current: Float64, given: Float64) -> Float64:
    """Return three.js's `absolute`: the given value, or the current one
    plus it when the positions are relative.

    Args:
        state: The state, for its `relative`.
        current: The current value.
        given: The value the command gives.

    Returns:
        The new value.
    """
    return current + given if state.relative else given


def gcode_layers(text: String) -> List[GCodeLayer]:
    """Read a G-code file's moves into layers, the loop of three.js's
    `GCodeLoader.parse`.

    Args:
        text: The file.

    Returns:
        The layers, in the order they started.
    """
    var state = _State(0, 0, 0, 0, 0, False)
    var layers = List[GCodeLayer]()
    for raw in _uncommented(text).split("\n"):  # pragma: no branch
        var tokens = String(raw).split(" ")
        var command = String(tokens[0]).upper()
        var has = List[Bool](length=5, fill=False)
        var given = List[Float64](length=5, fill=0)
        for t in range(1, len(tokens)):
            var token = String(tokens[t])
            if token.byte_length() == 0:
                continue
            # Only an ASCII letter lowers to one of the five keys.
            var key = Int(token.as_bytes()[0]) | 32
            var slot = -1
            for k in range(5):  # pragma: no branch
                if key == Int("xyzef".as_bytes()[k]):
                    slot = k
            if slot >= 0:
                has[slot] = True
                given[slot] = js_parse_float(String(token[byte=1:]))
        if command == "G0" or command == "G1":
            var now: List[Float64] = [
                state.x,
                state.y,
                state.z,
                state.e,
                state.f,
            ]
            for k in range(5):  # pragma: no branch
                if has[k]:
                    now[k] = _absolute(state, now[k], given[k])
            var line = _State(now[0], now[1], now[2], now[3], now[4], False)
            var raised = line.e if state.relative else line.e - state.e
            var extruding = raised > 0
            if extruding:
                var new = (
                    len(layers) == 0 or line.z != layers[len(layers) - 1].z
                )
                if new:
                    layers.append(GCodeLayer(line.z))
            if len(layers) == 0:
                layers.append(GCodeLayer(state.z))
            ref layer = layers[len(layers) - 1]
            var ends: List[Float64] = [
                state.x,
                state.y,
                state.z,
                line.x,
                line.y,
                line.z,
            ]
            for value in ends:  # pragma: no branch
                if extruding:
                    layer.vertex.append(value)
                else:
                    layer.path_vertex.append(value)
            state = line^
        elif command == "G90":
            state.relative = False
        elif command == "G91":
            state.relative = True
        elif command == "G92":
            if has[0]:
                state.x = given[0]
            if has[1]:
                state.y = given[1]
            if has[2]:
                state.z = given[2]
            if has[3]:
                state.e = given[3]
    return layers^


@fieldwise_init
struct GCodeObject(Copyable, Movable):
    """One `LineSegments` the loader added."""

    var node: NodeId
    var geometry: GeometryId
    # True for the extruded lines, False for the travel lines.
    var extruding: Bool


struct GCodeModel(Movable):
    """What `gcode_scene` added: the root node, the layers, the objects
    and the two materials."""

    # The node named `gcode`, three.js's returned `Group`.
    var root: NodeId
    var layers: List[GCodeLayer]
    var objects: List[GCodeObject]
    # three.js's `extruded` material, green.
    var extruded_material: MaterialId
    # three.js's `path` material, red.
    var path_material: MaterialId

    def __init__(
        out self,
        root: NodeId,
        var layers: List[GCodeLayer],
        extruded_material: MaterialId,
        path_material: MaterialId,
    ):
        """Hold the root, the layers and the materials, with no objects.

        Args:
            root: The node named `gcode`.
            layers: The layers.
            extruded_material: The material of the extruded lines.
            path_material: The material of the travel lines.
        """
        self.root = root
        self.layers = layers^
        self.objects = List[GCodeObject]()
        self.extruded_material = extruded_material
        self.path_material = path_material


def _add_object(
    mut model: GCodeModel,
    vertex: List[Float64],
    extruding: Bool,
    index: Int,
    mut scene: Scene,
    mut assets: Assets,
) raises:
    """Add one `LineSegments`, three.js's `addObject`.

    Args:
        model: What was added so far. The object is added to it.
        vertex: The segments, two points each.
        extruding: Whether the lines are the extruded ones.
        index: The number in its name.
        scene: The scene.
        assets: Where the geometry goes.

    Raises:
        Error: If the scene refuses the line.
    """
    var positions = List[Float32](capacity=len(vertex))
    for value in vertex:
        positions.append(Float32(value))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    var id = assets.geometries.add(geometry^)
    var node = Object3D()
    node.name = "layer" + String(index)
    var at = scene.attach(node, model.root)
    var material = model.extruded_material if extruding else model.path_material
    scene.add_line(Line(id, material, at, mode=SEGMENTS))
    model.objects.append(GCodeObject(at, id, extruding))


def gcode_scene(
    var layers: List[GCodeLayer],
    mut scene: Scene,
    mut assets: Assets,
    split_layer: Bool = False,
    parent: NodeId = NO_PARENT,
) raises -> GCodeModel:
    """Add the layers to a scene as three.js's `parse` builds its group.

    Args:
        layers: What `gcode_layers` gives.
        scene: The scene to add the nodes to.
        assets: Where the geometries and the materials go.
        split_layer: True for a pair of objects for each layer, three.js's
            `splitLayer`. False, the default, for one pair.
        parent: The node to put the root under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: If the scene refuses a node or a line.
    """
    var extruded = assets.materials.add(Material(Color(0, 255, 0), kind=BASIC))
    var path = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var group = Object3D()
    group.name = "gcode"
    group.set_rotation_from_axis_angle(
        Vector3(1, 0, 0), Angle(Float32(-pi / 2), RADIAN)
    )
    var root = scene.attach(group, parent)
    var model = GCodeModel(root, layers^, extruded, path)
    var count = len(model.layers)
    if split_layer:
        for i in range(count):
            var vertex = model.layers[i].vertex.copy()
            var path_vertex = model.layers[i].path_vertex.copy()
            _add_object(model, vertex, True, i, scene, assets)
            _add_object(model, path_vertex, False, i, scene, assets)
    else:
        var vertex = List[Float64]()
        var path_vertex = List[Float64]()
        for layer in model.layers:
            vertex.extend(layer.vertex.copy())
            path_vertex.extend(layer.path_vertex.copy())
        _add_object(model, vertex, True, count, scene, assets)
        _add_object(model, path_vertex, False, count, scene, assets)
    return model^


def parse_gcode(
    text: String,
    mut scene: Scene,
    mut assets: Assets,
    split_layer: Bool = False,
    parent: NodeId = NO_PARENT,
) raises -> GCodeModel:
    """Read a G-code file's text into a scene, three.js's
    `GCodeLoader.parse`.

    Args:
        text: The file.
        scene: The scene to add the nodes to.
        assets: Where the geometries and the materials go.
        split_layer: True for a pair of objects for each layer.
        parent: The node to put the root under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: If the scene refuses a node or a line.
    """
    return gcode_scene(gcode_layers(text), scene, assets, split_layer, parent)


def read_gcode(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    split_layer: Bool = False,
    parent: NodeId = NO_PARENT,
) raises -> GCodeModel:
    """Read a G-code file into a scene.

    Args:
        path: The file.
        scene: The scene to add the nodes to.
        assets: Where the geometries and the materials go.
        split_layer: True for a pair of objects for each layer.
        parent: The node to put the root under, or `NO_PARENT`.

    Returns:
        What `parse_gcode` gives.

    Raises:
        Error: If the file cannot be read, or the scene refuses a node or
            a line.
    """
    return parse_gcode(
        Path(path).read_text(), scene, assets, split_layer, parent
    )
