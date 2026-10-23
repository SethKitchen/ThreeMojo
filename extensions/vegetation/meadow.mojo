# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A summer meadow: grass, poppies, a treeline, boulders, sky and sun.

`Meadow` puts the whole scene into a `Scene` and its stores, and
`update` prepares one frame. The frame runs in this order:

1. **Cull and pick the levels.** `GrassField.select` gives each cluster a
   fate. A GPU-driven renderer runs this as a compute pass over the
   cluster bounds.
2. **Grow the drawn clusters.** Each drawn cluster grows its blades again
   at its level, bends them by the wind at this time, and replaces its
   geometry. A culled or far cluster is hidden, and costs nothing more.
3. **Pick each tree's crown.** Each tree wears the crown of the first
   `CrownLevel` whose reach holds it: every leaf near, and fewer, larger
   leaves and leaner wood further away.
4. **Fit the sun.** `SunLight.update` fits its two shadow cascades to the
   view. The trees and the boulders cast. The grass only receives, which
   halves the shadow work, and the dark roots of each blade stand in for
   the grass's shadow on itself.

**The light.** The sun is a `SunLight`. The sky's light is a hemisphere
light, blue from above and green from below, which is the light that the
sky and the sunlit grass bounce back. The blades and the leaves are lit
from both sides: `two_sided_program` turns a back face's normal to the
front again, so a blade with the sun behind it glows as a thin leaf does,
and does not go dark. `paint_sky` bakes Preetham's sky and its clouds
into the background cube. Fog of the sky's haze color veils the treeline
a little and the mountains a lot.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import cube_background
from core.fog import exp2_fog
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.crown import (
    CrownLevel,
    CrownParameters,
    bush_parameters,
    crown_level_for,
    default_crown_levels,
    leafy_tree,
)
from extensions.vegetation.field import (
    FieldParameters,
    FieldStats,
    GrassField,
    no_stats,
)
from extensions.vegetation.ground import Ground, ridge_ring
from extensions.vegetation.kinds import DRAWN
from extensions.vegetation.noise import hash01
from extensions.vegetation.rock import boulder
from extensions.vegetation.sky import SkyDome, SkyLook, paint_sky
from extensions.vegetation.wind import Wind
from lights.light import ambient_light, hemisphere_light
from lights.sun_light import SunLight
from materials.material import DOUBLE_SIDE, Material, MaterialId
from materials.nodes import NORMAL_NODE, NodeGraph, NodeProgram
from math.frustum import Frustum
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from lights.shadow import PCF_SOFT_SHADOW_MAP
from render.framebuffer import Color
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    Angle,
    Duration,
    InverseLength,
    Length,
)

# How far the mountains' far foot can be, and so how far a camera must
# see, as a multiple of the mountains' radius.
comptime FARTHEST = Float32(1.7)
# What the light is multiplied by before ACES filmic tone mapping.
comptime EXPOSURE = Float32(0.8)
# How high above the ground the camera's eye is.
comptime EYE_HEIGHT = Float32(1.05)


def two_sided_program() raises -> NodeProgram:
    """Return a node program that lights a back face as its front.

    The renderer lights a double-sided face seen from behind with its
    normal turned round. For a thin blade that is wrong: light that
    reaches one side shows through on the other. The program's normal
    offset is `2 * (front_facing - 1) * normal`. It is zero on a front
    face, and turns a back face's normal to the front again.

    Returns:
        The compiled program, with a `NORMAL_NODE` and no other output.

    Raises:
        Error: Never; the graph is fixed.
    """
    var graph = NodeGraph()
    var behind = graph.mul(
        graph.sub(graph.front_facing(), graph.float(1.0)), graph.float(2.0)
    )
    graph.set_output(NORMAL_NODE, graph.mul(graph.normal_world(), behind))
    return graph.compile()


def sun_direction(elevation: Angle, azimuth: Angle) -> Vector3:
    """Return the unit direction toward the sun.

    Args:
        elevation: How high the sun is above the horizon.
        azimuth: Which way the sun is, turned from +x toward +z.

    Returns:
        The direction.
    """
    var up = elevation.to(RADIAN)
    var round = azimuth.to(RADIAN)
    return Vector3(cos(up) * cos(round), sin(up), cos(up) * sin(round))


def meadow_renderer(width: Int, height: Int) raises -> Renderer:
    """Return a renderer for the meadow: every worker, ACES filmic tone
    mapping at `EXPOSURE`, soft shadows, and four samples a pixel.

    A blade is often narrower than a pixel. With one sample a pixel it
    falls between the samples on some frames and not on others, and the
    field shimmers. The frame's cost is mostly its triangles, so the extra
    samples cost little.

    Args:
        width: Image width in pixels.
        height: Image height in pixels.

    Returns:
        The renderer.

    Raises:
        Error: If the renderer cannot be created.
    """
    var renderer = Renderer(width, height, workers=available_workers())
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, EXPOSURE)
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    renderer.set_antialias(True)
    return renderer^


def meadow_camera(
    parameters: MeadowParameters, width: Int, height: Int, walk: Length
) raises -> PerspectiveCamera:
    """Return a camera at head height in the grass, looking up the slope
    to the treeline.

    Args:
        parameters: The meadow; its ground and mountains are read.
        width: Image width in pixels.
        height: Image height in pixels.
        walk: How far the camera has walked toward the trees.

    Returns:
        The placed camera. It sees as far as the mountains.

    Raises:
        Error: If the camera is not valid.
    """
    var camera = PerspectiveCamera(
        Angle(52.0, DEGREE),
        Float32(width) / Float32(height),
        Length(0.05, METER),
        Length(parameters.mountain_radius.to(METER) * FARTHEST, METER),
    )
    ref ground = parameters.ground
    var z = 22 - walk.to(METER)
    var ahead = z - 52
    camera.place(
        Vector3(2, ground.height_at(2, z) + EYE_HEIGHT, z),
        Vector3(-3, ground.height_at(-3, ahead) + 4, ahead),
    )
    return camera^


struct MeadowParameters(Copyable, Movable):
    """What the meadow holds, and where the sun is."""

    # The grass, its ground, and the wind over it.
    var field: FieldParameters
    var ground: Ground
    var wind: Wind
    # The trees: the crown of each kind, how many kinds, and how many
    # trees stand in the treeline.
    var crown: CrownParameters
    var tree_kinds: Int
    var trees: Int
    # The bushes under the treeline: their crown, and how many.
    var bush: CrownParameters
    var bushes: Int
    # Where a lone tree stands in the meadow, as x and z in meters.
    var solitary: List[Vector2]
    # How far behind the origin, toward -z, the treeline starts and ends,
    # and how wide it is.
    var treeline_near: Length
    var treeline_far: Length
    var treeline_width: Length
    # The levels of detail of every crown, nearest first.
    var crown_levels: List[CrownLevel]
    # How many boulders lie in the field.
    var rocks: Int
    # Where the sun is, and how the sky looks.
    var sun_elevation: Angle
    var sun_azimuth: Angle
    var sky: SkyLook
    # Texels on a side of each face of the sky's cube.
    var sky_size: Int
    # The ground drawn round the field, and its cells along a side.
    var ground_span: Length
    var ground_cells: Int
    # Where the ring of mountains starts.
    var mountain_radius: Length
    # Which trees and boulders to place.
    var seed: Int

    def __init__(out self) raises:
        """Create a meadow that rises to a treeline, with a high sun.

        Raises:
            Error: Never; the defaults are in range.
        """
        self.field = FieldParameters()
        self.ground = Ground(climb=0.035)
        self.wind = Wind()
        self.crown = CrownParameters()
        self.tree_kinds = 3
        self.trees = 56
        self.bush = bush_parameters()
        self.bushes = 110
        self.solitary = [Vector2(-10.0, -9.0), Vector2(27.0, -21.0)]
        self.treeline_near = Length(40.0, METER)
        self.treeline_far = Length(80.0, METER)
        self.treeline_width = Length(200.0, METER)
        self.crown_levels = default_crown_levels()
        self.rocks = 5
        self.sun_elevation = Angle(44.0, DEGREE)
        self.sun_azimuth = Angle(160.0, DEGREE)
        self.sky = SkyLook()
        self.sky_size = 512
        self.ground_span = Length(1400.0, METER)
        self.ground_cells = 160
        self.mountain_radius = Length(900.0, METER)
        self.seed = 5

    def check(self) raises:
        """Refuse a meadow that cannot be built.

        Raises:
            Error: If the field, the ground, the wind, a crown or the sky
                is refused; there are not from 1 to 16 tree kinds, from 0
                to 10,000 trees or bushes, from 0 to 1,000 lone trees or
                from 0 to 1,000 boulders; a lone tree is not within 10
                kilometers; the treeline does not lie from 0 to 10
                kilometers away with its far edge past its near edge; the
                crowns have not from 1 to 8 levels or a level is refused;
                the sun is not from 1 to 90 degrees high; the ground is not
                from 10 meters to 100 kilometers across; or the mountains
                are not from 10 meters to 100 kilometers away.
        """
        self.field.check()
        self.ground.check()
        self.wind.check()
        self.crown.check()
        self.bush.check()
        self.sky.check()
        require_count_between(
            self.tree_kinds, 1, 16, "A meadow must have from 1 to 16 tree kinds"
        )
        require_count_between(
            self.trees, 0, 10000, "A meadow must have from 0 to 10,000 trees"
        )
        require_count_between(
            self.bushes, 0, 10000, "A meadow must have from 0 to 10,000 bushes"
        )
        require_count_between(
            len(self.solitary),
            0,
            1000,
            "A meadow must have from 0 to 1,000 lone trees",
        )
        for index in range(len(self.solitary)):
            require_between(
                self.solitary[index].x,
                -1.0e4,
                1.0e4,
                "A lone tree must stand within 10 kilometers",
            )
            require_between(
                self.solitary[index].y,
                -1.0e4,
                1.0e4,
                "A lone tree must stand within 10 kilometers",
            )
        require_count_between(
            self.rocks, 0, 1000, "A meadow must have from 0 to 1,000 boulders"
        )
        require_between(
            self.treeline_near.to(METER),
            0,
            1.0e4,
            "A treeline must start from 0 to 10 kilometers away",
        )
        require_between(
            self.treeline_far.to(METER),
            self.treeline_near.to(METER) + 0.01,
            1.0e4,
            "A treeline must end past its start, within 10 kilometers",
        )
        require_between(
            self.treeline_width.to(METER),
            0,
            1.0e4,
            "A treeline must be from 0 to 10 kilometers wide",
        )
        require_count_between(
            len(self.crown_levels),
            1,
            8,
            "A crown must have from 1 to 8 levels",
        )
        for index in range(len(self.crown_levels)):  # pragma: no branch
            self.crown_levels[index].check()
        require_between(
            self.sun_elevation.to(DEGREE),
            1,
            90,
            "The sun must be from 1 to 90 degrees high",
        )
        require_between(
            self.sun_azimuth.to(RADIAN),
            -1.0e6,
            1.0e6,
            "The sun must be a finite way round",
        )
        require_between(
            self.ground_span.to(METER),
            10,
            1.0e5,
            "The ground must be from 10 meters to 100 kilometers across",
        )
        require_between(
            self.mountain_radius.to(METER),
            10,
            1.0e5,
            "The mountains must be from 10 meters to 100 kilometers away",
        )


@fieldwise_init
struct _Tree(ImplicitlyCopyable):
    """One tree of the treeline: where it stands, which kind it is, and
    its wood's mesh. Its leaves' mesh is the next one."""

    var place: Vector3
    var kind: Int
    var wood: Int


def _plant(
    mut scene: Scene,
    woods: List[GeometryId],
    leaves: List[GeometryId],
    levels: Int,
    wood: MaterialId,
    foliage: MaterialId,
    ground: Ground,
    x: Float32,
    z: Float32,
    kind: Int,
    turn: Float32,
    size: Float32,
) raises -> _Tree:
    """Stand one tree or bush of a kind on the ground, at full detail.

    Args:
        scene: The scene. The tree's node and two meshes are added.
        woods: The wood of each crown kind at each level.
        leaves: The leaves of each crown kind at each level.
        levels: How many levels each kind has.
        wood: The bark's material.
        foliage: The leaves' material.
        ground: The ground it stands on.
        x: Where it stands, in meters.
        z: Where it stands, in meters.
        kind: Which crown kind it wears.
        turn: How far it turns about +y, as a fraction of a turn.
        size: What it is scaled by.

    Returns:
        The tree, for `Meadow.update` to pick its crown.

    Raises:
        Error: If the scene refuses a mesh.
    """
    var place = Vector3(x, ground.height_at(x, z) - 0.2, z)
    var stand = Object3D()
    stand.set_position(place.x, place.y, place.z)
    stand.rotate_y(Angle(turn * 360, DEGREE))
    stand.set_scale(size, size, size)
    var node = scene.add(stand^)
    var first = kind * levels
    scene.add_mesh(
        Mesh(woods[first], wood, node, cast_shadow=True, receive_shadow=True)
    )
    # A crown does not take the sun's shadow on itself: thin cards
    # shadow each other into a noise. Its outward normals and its baked
    # occlusion give it its volume instead.
    scene.add_mesh(Mesh(leaves[first], foliage, node, cast_shadow=True))
    return _Tree(place, kind, len(scene.meshes) - 2)


struct Meadow(Movable):
    """The meadow in a scene, and what it changes on each frame."""

    var field: GrassField
    var wind: Wind
    # The material every grass cluster is drawn with.
    var grass: MaterialId
    # Each cluster's mesh in `scene.meshes`, its node and its geometry,
    # once the cluster has been drawn. None before.
    var cluster_mesh: List[Optional[Int]]
    var cluster_node: List[NodeId]
    var cluster_geometry: List[GeometryId]
    # The crown levels, and the wood and the leaves of each crown kind at
    # each level: entry `kind * len(levels) + level`.
    var levels: List[CrownLevel]
    var woods: List[GeometryId]
    var leaves: List[GeometryId]
    var trees: List[_Tree]
    var sun: SunLight
    var dome: SkyDome

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        renderer: Renderer,
        parameters: MeadowParameters,
    ) raises:
        """Build the meadow into a scene and its stores.

        Args:
            scene: The scene. The meadow's nodes, meshes, lights, fog and
                sky are added to it.
            assets: The stores. Its geometries, materials and programs
                are added to them.
            renderer: What the sky's cube is drawn with.
            parameters: What the meadow holds.

        Raises:
            Error: If `parameters.check` refuses a value, or a part
                cannot be built.
        """
        parameters.check()
        self.field = GrassField(parameters.field.copy(), parameters.ground)
        self.wind = parameters.wind
        self.levels = parameters.crown_levels.copy()
        var two_sided = assets.programs.add(two_sided_program())
        var white = Color(255, 255, 255)
        self.grass = assets.materials.add(
            Material(
                white, side=DOUBLE_SIDE, vertex_colors=True, nodes=two_sided
            )
        )
        var painted = assets.materials.add(Material(white, vertex_colors=True))
        var stone = assets.materials.add(
            Material(white, vertex_colors=True, flat_shading=True)
        )
        var far_stone = assets.materials.add(
            Material(white, side=DOUBLE_SIDE, vertex_colors=True)
        )
        self.cluster_mesh = List[Optional[Int]](
            length=len(self.field.clusters), fill=None
        )
        self.cluster_node = List[NodeId]()
        self.cluster_geometry = List[GeometryId]()
        for _ in range(len(self.field.clusters)):  # pragma: no branch
            self.cluster_node.append(scene.add(Object3D()))
            self.cluster_geometry.append(GeometryId(-1))

        ref ground = parameters.ground
        var land = ground.mesh(
            parameters.ground_span, parameters.ground_cells, 0, 0
        )
        land.compute_vertex_normals()
        scene.add_mesh(
            Mesh(
                assets.geometries.add(land^),
                painted,
                scene.add(Object3D()),
                receive_shadow=True,
            )
        )
        var ridge = ridge_ring(
            parameters.mountain_radius,
            Length(parameters.mountain_radius.to(METER) * 0.6, METER),
            Length(parameters.mountain_radius.to(METER) * 0.24, METER),
            480,
            parameters.seed,
        )
        ridge.compute_vertex_normals()
        var ridge_node = Object3D()
        ridge_node.set_position(0, ground.height_at(0, 0) - 20, 0)
        scene.add_mesh(
            Mesh(
                assets.geometries.add(ridge^), far_stone, scene.add(ridge_node^)
            )
        )

        # The crown kinds: the tree kinds, then the bush. Each is a crown
        # in full and a crown with fewer, larger leaves.
        self.woods = List[GeometryId]()
        self.leaves = List[GeometryId]()
        for kind in range(parameters.tree_kinds + 1):  # pragma: no branch
            var crown = parameters.bush.copy()
            if kind < parameters.tree_kinds:
                crown = parameters.crown.copy()
            crown.tree.seed = crown.tree.seed + kind * 17
            crown.seed = crown.seed + kind * 31
            for level in range(len(self.levels)):  # pragma: no branch
                var grown = leafy_tree(
                    crown, self.levels[level].detail, lean_wood=level > 0
                )
                self.woods.append(assets.geometries.add(grown.wood.clone()))
                self.leaves.append(assets.geometries.add(grown.leaves.clone()))
        self.trees = List[_Tree]()
        var seed = parameters.seed * 6151
        var near = parameters.treeline_near.to(METER)
        var deep = parameters.treeline_far.to(METER) - near
        var wide = parameters.treeline_width.to(METER)
        var plants = parameters.trees + parameters.bushes
        for t in range(plants):
            # Trees fill the band from its near edge to its far edge. The
            # bushes stand in two rows along the near edge, under the
            # first crowns.
            var bush = t >= parameters.trees
            var row = t
            var count = parameters.trees
            if bush:
                row = t - parameters.trees
                count = parameters.bushes
            var x = (
                (Float32(row) + hash01(t, 0, seed)) / Float32(count) - 0.5
            ) * wide
            var z = -(near + deep * hash01(t, 1, seed))
            var kind = t % parameters.tree_kinds
            var size = 0.8 + 0.45 * hash01(t, 3, seed)
            if bush:
                z = -(near - 4 + 9 * hash01(t, 1, seed))
                kind = parameters.tree_kinds
                size = 1.3 + 0.9 * hash01(t, 3, seed)
            self.trees.append(
                _plant(
                    scene,
                    self.woods,
                    self.leaves,
                    len(self.levels),
                    painted,
                    self.grass,
                    ground,
                    x,
                    z,
                    kind,
                    hash01(t, 2, seed),
                    size,
                )
            )
        for t in range(len(parameters.solitary)):
            ref spot = parameters.solitary[t]
            self.trees.append(
                _plant(
                    scene,
                    self.woods,
                    self.leaves,
                    len(self.levels),
                    painted,
                    self.grass,
                    ground,
                    spot.x,
                    spot.y,
                    t % parameters.tree_kinds,
                    hash01(t, 4, seed),
                    1.05 + 0.2 * hash01(t, 5, seed),
                )
            )

        var span = parameters.field.span.to(METER) * 0.4
        for r in range(parameters.rocks):
            var x = (hash01(r, 10, seed) - 0.5) * 2 * span
            var z = (hash01(r, 11, seed) - 0.5) * 2 * span
            var size = 0.35 + 1.1 * hash01(r, 12, seed) * hash01(r, 13, seed)
            var lie = Object3D()
            lie.set_position(x, ground.height_at(x, z) - size * 0.25, z)
            lie.rotate_y(Angle(hash01(r, 14, seed) * 360, DEGREE))
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(
                        boulder(Length(size, METER), 3, seed + r)
                    ),
                    stone,
                    scene.add(lie^),
                    cast_shadow=True,
                    receive_shadow=True,
                )
            )

        var toward = sun_direction(
            parameters.sun_elevation, parameters.sun_azimuth
        )
        self.dome = paint_sky(
            renderer, assets, toward, parameters.sky, parameters.sky_size
        )
        scene.background = cube_background(self.dome.cube)
        self.sun = SunLight(scene, Color(255, 241, 222), 4.4)
        self.sun.cast_shadow = True
        self.sun.shadow.map_size = 2048
        self.sun.shadow.bias = -0.0004
        self.sun.shadow.normal_bias = 0.04
        # The cascades cover the meadow and the treeline, not the
        # mountains: they would spread the same texels over 1.5 km.
        self.sun.shadow.far = Length(150.0, METER)
        scene.node(self.sun.node).set_position(
            toward.x * 100, toward.y * 100, toward.z * 100
        )
        var above = Object3D()
        above.set_position(0, 1, 0)
        scene.add_light(
            hemisphere_light(
                Color(165, 198, 245), Color(80, 96, 44), scene.add(above^), 1.1
            )
        )
        scene.add_light(ambient_light(Color(200, 215, 240), 0.08))
        scene.fog = exp2_fog(
            self.dome.haze(), InverseLength(0.00075, PER_METER)
        )
        scene.update()

    def update(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        camera: PerspectiveCamera,
        time: Duration,
    ) raises -> FieldStats:
        """Prepare one frame: cull and grow the grass, pick the crowns,
        and fit the sun.

        Args:
            scene: The scene the meadow is in, updated.
            assets: The stores. The drawn clusters' geometries change.
            camera: The camera of the frame, placed.
            time: The time of the frame, for the wind.

        Returns:
            What the frame draws of the field.

        Raises:
            Error: If the camera's view is refused, or a cluster cannot be
                built.
        """
        var view = camera.view_matrix()
        var clip = camera.projection_matrix()
        clip.multiply(view)
        var frustum = Frustum.from_camera(
            clip, view, camera.near_distance(), camera.far_distance()
        )
        var eye = camera.position
        var choices = self.field.select(eye, frustum)
        var stats = no_stats()
        for index in range(len(choices)):  # pragma: no branch
            var choice = choices[index]
            stats.tally(choice.fate)
            var shown = False
            if choice.fate == DRAWN:
                shown = self._grow(
                    scene, assets, index, choice.band, time, stats
                )
            scene.node(self.cluster_node[index]).visible = shown
        for t in range(len(self.trees)):
            ref tree = self.trees[t]
            var level = crown_level_for(
                self.levels, (tree.place - eye).length()
            )
            var entry = tree.kind * len(self.levels) + level
            scene.meshes[tree.wood].geometry = self.woods[entry]
            scene.meshes[tree.wood + 1].geometry = self.leaves[entry]
        scene.update()
        self.sun.update(scene, camera)
        return stats

    def _grow(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        index: Int,
        band: Int,
        time: Duration,
        mut stats: FieldStats,
    ) raises -> Bool:
        """Build one drawn cluster into its mesh, and count what it holds.

        Returns:
            Whether the cluster has a mesh to show. False, and counted as
            empty, if no blade of its level grows.
        """
        var grown = self.field.build(index, band, self.wind, time)
        if not grown:
            stats.empty += 1
            return False
        var geometry = grown.take()
        stats.blades += self.field.kept(index, band)
        stats.triangles += len(geometry.index) // 3
        if self.cluster_mesh[index]:
            assets.geometries.replace(self.cluster_geometry[index], geometry^)
            return True
        var id = assets.geometries.add(geometry^)
        self.cluster_geometry[index] = id
        scene.add_mesh(
            Mesh(id, self.grass, self.cluster_node[index], receive_shadow=True)
        )
        self.cluster_mesh[index] = len(scene.meshes) - 1
        return True
