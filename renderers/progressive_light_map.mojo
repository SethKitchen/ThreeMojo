# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A light map that gathers light frame by frame, three.js's
`examples/jsm/misc/ProgressiveLightMap.js`.

`add_objects_to_light_map` packs each mesh's texture square into one map
with `math.potpack`, three pixels of padding around each, and writes the
place into the geometry's `uv1`. Each mesh's material then reads the map
as its `light_map`, and the mesh casts and receives shadows.

`update` draws the meshes into the map in the space of their `uv1`, with
a white `PHONG` material, and mixes what it draws into what the map held:
`mix(old, lit, 1 / blend_window)`. Call it once a frame, and move the
lights a little each time: the shadows soften into an average.

The map is two float textures, drawn in turn, as three.js ping-pongs two
render targets. The meshes read the second, three.js's
`progressiveLightMap2`, so their light map changes every second update.

**The blur.** Before the meshes are drawn, each pixel of the map takes the
average of its eight neighbors in the old map, three.js's blurring plane.
The meshes then draw over their own pixels. What is left is the padding:
it takes the color of the edges beside it, so a filtered read at an edge
does not bleed in black.

**What differs from three.js.** three.js moves the meshes into a scene of
their own, with the lights handed to it, and draws that. Here the meshes
are drawn from their own scene: every light of the scene lights them, and
every caster of the scene shadows them. Neither side of a triangle is
culled in texture space.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.buffer_geometry import UV, UV1
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    Material,
    MaterialId,
    PHONG,
)
from materials.nodes import (
    NodeGraph,
    NodeProgramId,
    OUTPUT_NODE,
)
from math.potpack import PackedBox, potpack
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.reflector import view_renderer
from render.framebuffer import Color, FloatColor
from render.target import FLOAT_TARGET, RenderTarget
from render.texture import IGNORED, UV_CHANNEL_1, Texture, float_texture
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import isfinite, max, min
from units.si import Length, METER


# three.js's `averagingWindow` and `blendWindow` default: a hundred frames.
comptime DEFAULT_BLEND_WINDOW = Float32(100)


def _map_texture(
    resolution: Int, var pixels: List[Float32], second: Bool
) raises -> Texture:
    """Return a map's float texture, as a light map reads it: its alpha
    means nothing. The second map reads the second coordinates, three.js's
    `progressiveLightMap2.texture.channel = 1`.
    """
    var texture = float_texture(resolution, resolution, pixels^, alpha=IGNORED)
    if second:
        texture.channel = UV_CHANNEL_1
    return texture^


def _blend_program() raises -> NodeGraph:
    """Return the `PHONG` material's graph that mixes what it lights into
    the old map: three.js's `uvMat` shader patch.

    The old map is read where the fragment is on the map, which is its
    `uv1`: three.js's `texture2D(previousShadowMap, vLightMapUv)`.
    """
    var graph = NodeGraph()
    var previous = graph.texture_uniform("previousShadowMap")
    var window = graph.uniform("averagingWindow", DEFAULT_BLEND_WINDOW)
    var old = graph.swizzle(
        graph.texture(previous, graph.screen_uv()), "rgb"
    )
    graph.set_output(
        OUTPUT_NODE,
        graph.mix(old, graph.lit(), graph.div(graph.float(1), window)),
    )
    return graph^


struct ProgressiveLightMap(Movable):
    """Gathers the light on a set of meshes into one texture, frame by
    frame: three.js's `ProgressiveLightMap`. See the module docstring."""

    # The map's width and height in pixels, three.js's `res`.
    var resolution: Int
    # The two textures the map is drawn into in turn, in `assets.textures`:
    # three.js's `progressiveLightMap1` and `progressiveLightMap2`. The
    # meshes read the second.
    var maps: List[TextureId]
    # Whether the next update draws into the first, three.js's
    # `buffer1Active`.
    var buffer1_active: Bool
    # The meshes drawn into the map, by their place in `scene.meshes`:
    # three.js's `lightMapContainers`.
    var meshes: List[Int]
    # The white `PHONG` material the meshes are drawn with, three.js's
    # `uvMat`, and its program.
    var uv_material: MaterialId
    var program: NodeProgramId
    # The node of the plane that shows the first map, three.js's
    # `labelMesh`, or `None` before `show_debug_light_map` adds it.
    var label: Optional[NodeId]

    def __init__(
        out self, mut assets: Assets, resolution: Int = 1024
    ) raises:
        """Make the two maps, black, and the material the meshes are drawn
        with: three.js's `new ProgressiveLightMap(renderer, res)`.

        Args:
            assets: The stores the maps and the material are added to.
            resolution: The map's width and height in pixels.

        Raises:
            Error: If the resolution is not positive.
        """
        if resolution <= 0:
            raise Error("A light map's resolution must be positive")
        self.resolution = resolution
        self.maps = List[TextureId]()
        for index in range(2):
            self.maps.append(
                assets.textures.add(
                    _map_texture(
                        resolution,
                        List[Float32](
                            length=resolution * resolution * 4, fill=0
                        ),
                        index == 1,
                    )
                )
            )
        self.buffer1_active = False
        self.meshes = List[Int]()
        self.program = assets.programs.add(_blend_program().compile())
        self.uv_material = assets.materials.add(
            Material(Color(255, 255, 255), kind=PHONG, nodes=self.program)
        )
        self.label = None

    def add_objects_to_light_map(
        mut self, mut scene: Scene, mut assets: Assets, meshes: List[Int]
    ) raises:
        """Lay the meshes out on the map and give each the map as its light
        map: three.js's `addObjectsToLightMap`.

        Each mesh gets a square one unit wide and three pixels of padding
        around it, packed with `potpack`. Its `uv`, moved into its square
        and scaled to the map, becomes its `uv1`. Its material reads the
        second map as its `light_map`, dithered, and the mesh casts and
        receives shadows. Its node draws after the rest, in the order
        given, three.js's `renderOrder = 1000 + ob`.

        Args:
            scene: The scene the meshes are in.
            assets: The stores: each mesh's geometry and material change.
            meshes: The meshes, by their place in `scene.meshes`.

        Raises:
            Error: If a mesh is not in the scene, its geometry has no `uv`,
                or its material is neither basic nor lit, or a wireframe:
                it has no light map to read.
        """
        var padding = 3 / Float64(self.resolution)
        var boxes = List[PackedBox]()
        for index in range(len(meshes)):
            var at = meshes[index]
            if at < 0 or at >= len(scene.meshes):
                raise Error("A light map's mesh is not in the scene")
            ref mesh = scene.meshes[at]
            if not assets.geometries.get(mesh.geometry).has_attribute(UV):
                raise Error("A mesh drawn into a light map needs a uv")
            ref material = assets.materials.materials[mesh.material.value]
            if not material.kind.has_indirect() or material.wireframe:
                raise Error(
                    "A light map's mesh needs a basic or lit material that"
                    " is not a wireframe, to read the light map"
                )
            material.light_map = self.maps[1]
            material.dithering = True
            mesh.cast_shadow = True
            mesh.receive_shadow = True
            var node = scene.get(mesh.node)
            node.render_order = 1000 + index
            scene.set(mesh.node, node^)
            boxes.append(
                PackedBox(1 + padding * 2, 1 + padding * 2, 0, 0, index)
            )
            self.meshes.append(at)
        var packing = potpack(boxes)
        for box in boxes:
            ref geometry = assets.geometries.geometries[
                scene.meshes[meshes[box.index]].geometry.value
            ]
            var uv1 = geometry.clone_attribute(UV)
            for vertex in range(uv1.count()):
                uv1.set_component(
                    vertex,
                    0,
                    Float32(
                        (Float64(uv1.component(vertex, 0)) + box.x + padding)
                        / packing.w
                    ),
                )
                uv1.set_component(
                    vertex,
                    1,
                    Float32(
                        (Float64(uv1.component(vertex, 1)) + box.y + padding)
                        / packing.h
                    ),
                )
            geometry.set_attribute(UV1, uv1^)

    def update[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
        blend_window: Float32 = DEFAULT_BLEND_WINDOW,
        blur_edges: Bool = True,
    ) raises:
        """Draw the meshes' light into the map once, mixed into what it
        held: three.js's `update`. Nothing happens before a mesh is added.

        Args:
            renderer: The renderer the scene is drawn with; see
                `objects.reflector.view_renderer`.
            scene: The scene. Each mesh is drawn with the white material
                and given its own back afterward, even if the draw raises.
            assets: The stores. The map drawn into is replaced.
            camera: The camera the highlights are seen from.
            blend_window: How many updates the average spans: each mixes
                in one part in this many, three.js's `blendWindow`.
            blur_edges: Whether the padding takes the color of the edges
                beside it; see the module docstring.

        Raises:
            Error: If the blend window is not a positive finite number, or
                the draw raises.
        """
        if not isfinite(blend_window) or blend_window <= 0:
            raise Error("A light map's blend window must be positive")
        if len(self.meshes) == 0:
            return
        var active = 0 if self.buffer1_active else 1
        var inactive = 1 - active
        self.buffer1_active = not self.buffer1_active
        ref program = assets.programs.get(self.program)
        program.set_uniform("averagingWindow", blend_window)
        program.set_texture("previousShadowMap", self.maps[inactive])
        var target = RenderTarget(
            self.resolution, self.resolution, Color(0, 0, 0), FLOAT_TARGET
        )
        if blur_edges:
            _blur(target, assets.textures.get(self.maps[inactive]))
        var view = view_renderer(renderer, self.resolution, self.resolution)
        view.uv_space_meshes = self.meshes.copy()
        view.auto_clear = False
        var materials = List[MaterialId]()
        var groups = List[List[MaterialId]]()
        for at in self.meshes:
            materials.append(scene.meshes[at].material)
            groups.append(scene.meshes[at].materials.copy())
            scene.meshes[at].material = self.uv_material
            scene.meshes[at].materials = List[MaterialId]()
        try:
            view.render_into(target, scene, assets, camera)
        finally:
            for index in range(len(self.meshes)):
                ref mesh = scene.meshes[self.meshes[index]]
                mesh.material = materials[index]
                mesh.materials = groups[index].copy()
        assets.textures.textures[self.maps[active].value] = _map_texture(
            self.resolution, target.attachment(0).pixels.copy(), active == 1
        )

    def show_debug_light_map(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        visible: Bool,
        position: Optional[Vector3] = None,
    ) raises:
        """Show or hide a plane that shows the first map, three.js's
        `showDebugLightmap`. The first call adds it: a hundred units wide,
        250 up, beside the first mesh.

        Args:
            scene: The scene. The plane's node is added to it once.
            assets: The stores the plane's geometry and material go in.
            visible: Whether the plane is shown.
            position: Where the plane is put, or `None` to leave it.

        Raises:
            Error: If no mesh has been added yet: three.js warns and does
                nothing.
        """
        if len(self.meshes) == 0:
            raise Error("Show the light map after adding the meshes")
        # Spelled as a Bool, as the coverage probes take one.
        if not Bool(self.label):
            var shows = Material(
                Color(255, 255, 255),
                map=self.maps[0],
                side=DOUBLE_SIDE,
                kind=BASIC,
            )
            var node = Object3D()
            node.set_position(0, 250, 0)
            node.parent = scene.get(scene.meshes[self.meshes[0]].node).parent
            var at = scene.add(node^)
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(
                        plane(Length(100, METER), Length(100, METER))
                    ),
                    assets.materials.add(shows),
                    at,
                )
            )
            self.label = at
        var at = self.label.value()
        var label = scene.get(at)
        if Bool(position):
            var place = position.value()
            label.set_position(place.x, place.y, place.z)
        label.visible = visible
        scene.set(at, label^)
        scene.update()


def _blur(mut target: RenderTarget, old: Texture):
    """Fill the target with the average of each pixel's eight neighbors in
    the old map, clamped at the edges, and an alpha of one: three.js's
    blurring plane, whose texel offsets land on the neighbors' centers.
    """
    var size = target.width
    for y in range(size):
        for x in range(size):
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    if dx == 0 and dy == 0:
                        continue
                    var at = (
                        min(max(y + dy, 0), size - 1) * size
                        + min(max(x + dx, 0), size - 1)
                    ) * 4
                    r += old.data[at]
                    g += old.data[at + 1]
                    b += old.data[at + 2]
            target.colors[y * size + x] = FloatColor(r / 8, g / 8, b / 8, 1)
