# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A summer grassland: grass, poppies, trees and bushes, boulders, sky and
sun.

`Meadow` puts the whole scene into a `Scene` and its stores, and
`update` prepares one frame. The frame runs in this order:

1. **Cull and pick the levels.** `GrassField.select` gives each cluster a
   fate. A GPU-driven renderer runs this as a compute pass over the
   cluster bounds.
2. **Grow the drawn clusters.** Each drawn cluster grows its blades again
   at its level, bends them by the wind at this time, and replaces its
   geometry. A culled or far cluster is hidden, and costs nothing more.
3. **Pick each tree's crown, and sway it.** Each tree wears the crown of
   the first `CrownLevel` whose reach holds it: every leaf near, and
   fewer, larger leaves further away. Each tree leans from its foot by
   `Wind.tree_sway`, a degree or so in a gust.
4. **Fit the sun.** `SunLight.update` fits its two shadow cascades to the
   view. The trees, the bushes and the boulders cast. The grass only
   receives. The dark roots of each blade stand in for its shadow on
   itself.

**The layout.** `MeadowParameters.crowns` lists the kinds of tree and
bush, and `plantings` says where each one stands and how large it is.
The default layout is open grassland: a lone tree near the camera,
trees and round bushes scattered at every distance, and a bush with
broad leaves a few meters away. A canyon crosses the land 330 meters
away. Its far wall shows above the near rim as a band of cliffs, and a
woodland grows on the higher plateau beyond it.

**The light.** The sun is a `SunLight`. The sky's light is a hemisphere
light, blue from above and green from below, which is the light that the
sky and the sunlit grass bounce back. The blades are lit from both
sides: `two_sided_program` turns a back face's normal to the front again,
so a blade with the sun behind it glows as a thin leaf does. The leaves
use `foliage_program`, which also takes their baked light. The sun's
direction is baked into each crown, so a planting is never turned.
`paint_sky` bakes Preetham's sky and its clouds into the background cube.
Fog of the sky's haze color veils the far woodland and the mountains.
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
    dress,
    grow_crown,
    round_tree,
    windswept_tree,
    young_tree,
)
from extensions.vegetation.field import (
    FieldParameters,
    FieldStats,
    GrassField,
    no_stats,
)
from extensions.vegetation.foliage import foliage_program
from extensions.vegetation.ground import Canyon, Ground, cliff_wall, ridge_ring
from extensions.vegetation.kinds import DRAWN
from extensions.vegetation.noise import hash01
from extensions.vegetation.rock import boulder
from extensions.vegetation.sky import SkyDome, SkyLook, paint_sky
from extensions.vegetation.wind import Wind
from lights.light import ambient_light, hemisphere_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from lights.sun_light import SunLight
from materials.material import DOUBLE_SIDE, Material, MaterialId
from materials.nodes import NORMAL_NODE, NodeGraph, NodeProgram
from math.frustum import Frustum
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, pow, sin
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
comptime EYE_HEIGHT = Float32(1.6)


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


def blend_frames(frames: List[Framebuffer]) raises -> Framebuffer:
    """Return the mean of frames of one size, channel by channel.

    Frames rendered at moments inside one frame's shutter blend into a
    frame with motion blur. A thin blade that moves a few pixels a frame
    then smears, as it does in a film, and does not jump.

    Args:
        frames: The frames, at least one, all of one size.

    Returns:
        The blended frame. Its depth is the first frame's.

    Raises:
        Error: If there is no frame, or the frames differ in size.
    """
    if len(frames) == 0:
        raise Error("Blending needs at least one frame")
    var width = frames[0].width
    var height = frames[0].height
    var blended = Framebuffer(width, height, Color(0, 0, 0, 0))
    blended.depth = frames[0].depth.copy()
    var total = List[Int](length=len(frames[0].pixels), fill=0)
    for f in range(len(frames)):  # pragma: no branch
        ref frame = frames[f]
        if frame.width != width or frame.height != height:
            raise Error("Blended frames must all be of one size")
        for index in range(len(frame.pixels)):  # pragma: no branch
            total[index] += Int(frame.pixels[index])
    var count = len(frames)
    for index in range(len(total)):  # pragma: no branch
        blended.pixels[index] = UInt8((total[index] + count // 2) // count)
    return blended^


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
    """Return a camera at head height in the grass, looking out over the
    grassland toward -z.

    Args:
        parameters: The meadow; its ground and mountains are read.
        width: Image width in pixels.
        height: Image height in pixels.
        walk: How far the camera has walked toward -z.

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
    var z = 30 - walk.to(METER)
    var ahead = z - 70
    camera.place(
        Vector3(0, ground.height_at(0, z) + EYE_HEIGHT, z),
        Vector3(-4, ground.height_at(-4, ahead) + 4.5, ahead),
    )
    return camera^


@fieldwise_init
struct Planting(ImplicitlyCopyable):
    """One tree or bush: which crown it wears, where it stands, and how
    large it is."""

    # The entry of `MeadowParameters.crowns` it wears.
    var crown: Int
    # Where it stands, in meters.
    var x: Float32
    var z: Float32
    # What its crown is scaled by.
    var size: Float32


def scatter_plantings(
    count: Int,
    first: Int,
    kinds: Int,
    near: Length,
    far: Length,
    smallest: Float32,
    largest: Float32,
    seed: Int,
) -> List[Planting]:
    """Return plantings scattered across the view toward -z.

    Each planting stands between `near` and `far` from the origin, toward
    -z, and as far to each side as the view reaches there. More of them
    stand toward `far`, where the view is wider. They cycle through
    `kinds` crowns from `first`.

    Args:
        count: How many plantings.
        first: The first crown they wear.
        kinds: How many crowns, from `first`, they cycle through.
        near: The nearest a planting stands.
        far: The furthest a planting stands.
        smallest: The smallest size.
        largest: The largest size.
        seed: Which places to pick.

    Returns:
        The plantings.
    """
    var plantings = List[Planting]()
    var low = near.to(METER)
    var high = far.to(METER)
    for index in range(count):
        var depth = low + (high - low) * pow(
            hash01(index, 0, seed), Float32(0.7)
        )
        var across = (hash01(index, 1, seed) - 0.5) * (2.2 * depth + 20)
        var size = smallest + (largest - smallest) * hash01(index, 2, seed)
        plantings.append(
            Planting(first + index % max(kinds, 1), across, -depth, size)
        )
    return plantings^


def grove_plantings(
    count: Int,
    first: Int,
    kinds: Int,
    x: Float32,
    z: Float32,
    spread: Length,
    smallest: Float32,
    largest: Float32,
    seed: Int,
) -> List[Planting]:
    """Return plantings that stand together in a grove.

    Each stands within `spread` of the grove's middle, more of them near
    it. They cycle through `kinds` crowns from `first`.

    Args:
        count: How many plantings.
        first: The first crown they wear.
        kinds: How many crowns, from `first`, they cycle through.
        x: The grove's middle along x, in meters.
        z: The grove's middle along z, in meters.
        spread: The grove's radius.
        smallest: The smallest size.
        largest: The largest size.
        seed: Which places to pick.

    Returns:
        The plantings.
    """
    var plantings = List[Planting]()
    var turn = Float32(2) * Float32(pi)
    for index in range(count):
        var away = spread.to(METER) * pow(hash01(index, 0, seed), Float32(0.6))
        var round = turn * hash01(index, 1, seed)
        var size = smallest + (largest - smallest) * hash01(index, 2, seed)
        plantings.append(
            Planting(
                first + index % max(kinds, 1),
                x + cos(round) * away,
                z + sin(round) * away,
                size,
            )
        )
    return plantings^


def default_crowns() -> List[CrownParameters]:
    """Return the eight crowns of the grassland.

    Returns:
        Two open trees, a windswept tree, two young trees, a round tree,
        a green bush and a gray-green bush, each of its own seed.
    """
    var crowns: List[CrownParameters] = [
        CrownParameters(),
        CrownParameters(),
        windswept_tree(),
        young_tree(),
        young_tree(),
        round_tree(),
        bush_parameters(),
        bush_parameters(),
    ]
    crowns[7].leaf = Vector3(0.060, 0.080, 0.045)
    crowns[7].leaf_light = Vector3(0.120, 0.140, 0.085)
    crowns[7].leaf_length = Length(0.07, METER)
    crowns[7].leaf_width = Length(0.04, METER)
    crowns[7].leaves_per_node = 6
    for index in range(len(crowns)):  # pragma: no branch
        crowns[index].seed = 11 + 7 * index
        crowns[index].limbs.seed = 3 + 5 * index
    # The two open trees whose crowns spread most like a lone tree's.
    crowns[0].limbs.seed = 10
    crowns[1].limbs.seed = 6
    return crowns^


def default_plantings() -> List[Planting]:
    """Return the layout of the grassland.

    Returns:
        A lone open tree and a bush near the camera; a second open tree
        and a windswept tree; three groves of mixed trees from 60 to 140
        meters; trees and round bushes scattered from 12 to 160 meters;
        and young and round trees from 435 to 700 meters, on the far side
        of the canyon.
    """
    var plantings: List[Planting] = [
        Planting(0, -12.0, -6.0, 1.0),
        Planting(1, 33.0, -36.0, 1.1),
        Planting(2, 21.0, -12.0, 0.9),
        Planting(6, -3.4, 25.8, 0.85),
    ]
    plantings.extend(
        grove_plantings(
            9, 1, 5, 44.0, -95.0, Length(22.0, METER), 0.8, 1.25, 31
        )
    )
    plantings.extend(
        grove_plantings(
            5, 3, 3, -26.0, -70.0, Length(12.0, METER), 0.75, 1.15, 32
        )
    )
    plantings.extend(
        grove_plantings(6, 2, 4, 6.0, -132.0, Length(18.0, METER), 0.8, 1.2, 33)
    )
    plantings.extend(
        scatter_plantings(
            14,
            1,
            5,
            Length(45.0, METER),
            Length(160.0, METER),
            0.7,
            1.2,
            21,
        )
    )
    plantings.extend(
        scatter_plantings(
            30,
            6,
            2,
            Length(12.0, METER),
            Length(120.0, METER),
            0.6,
            1.5,
            22,
        )
    )
    plantings.extend(
        scatter_plantings(
            45,
            3,
            3,
            Length(435.0, METER),
            Length(700.0, METER),
            0.9,
            1.4,
            23,
        )
    )
    return plantings^


struct MeadowParameters(Copyable, Movable):
    """What the meadow holds, and where the sun is."""

    # The grass, its ground, and the wind over it.
    var field: FieldParameters
    var ground: Ground
    var wind: Wind
    # The kinds of tree and bush, and where each stands.
    var crowns: List[CrownParameters]
    var plantings: List[Planting]
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
    # Which boulders to place.
    var seed: Int

    def __init__(out self) raises:
        """Create open grassland under a sun ahead of the camera and to its
        right, so the grass glows against it and the trees cast their
        shadows toward the camera.

        Raises:
            Error: Never; the defaults are in range.
        """
        self.field = FieldParameters()
        self.ground = Ground(
            canyon=Canyon(
                Length(300.0, METER),
                Length(420.0, METER),
                Length(80.0, METER),
                Length(38.0, METER),
            )
        )
        self.wind = Wind()
        self.crowns = default_crowns()
        self.plantings = default_plantings()
        self.crown_levels = default_crown_levels()
        self.rocks = 6
        self.sun_elevation = Angle(38.0, DEGREE)
        self.sun_azimuth = Angle(-30.0, DEGREE)
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
                is refused; there are not from 1 to 64 crowns, from 0 to
                100,000 plantings or from 0 to 1,000 boulders; a planting
                names no crown, stands further than 10 kilometers, or is
                not from 0.05 to 20 times its crown's size; the crowns
                have not from 1 to 8 levels or a level is refused; the sun
                is not from 1 to 90 degrees high; the ground is not from 10
                meters to 100 kilometers across; or the mountains are not
                from 10 meters to 100 kilometers away.
        """
        self.field.check()
        self.ground.check()
        self.wind.check()
        self.sky.check()
        require_count_between(
            len(self.crowns), 1, 64, "A meadow must have from 1 to 64 crowns"
        )
        for index in range(len(self.crowns)):  # pragma: no branch
            self.crowns[index].check()
        require_count_between(
            len(self.plantings),
            0,
            100000,
            "A meadow must have from 0 to 100,000 plantings",
        )
        for index in range(len(self.plantings)):
            ref planting = self.plantings[index]
            require_count_between(
                planting.crown,
                0,
                len(self.crowns) - 1,
                "A planting must wear one of the meadow's crowns",
            )
            require_between(
                planting.x,
                -1.0e4,
                1.0e4,
                "A planting must stand within 10 kilometers",
            )
            require_between(
                planting.z,
                -1.0e4,
                1.0e4,
                "A planting must stand within 10 kilometers",
            )
            require_between(
                planting.size,
                0.05,
                20,
                "A planting must be from 0.05 to 20 times its crown's size",
            )
        require_count_between(
            self.rocks, 0, 1000, "A meadow must have from 0 to 1,000 boulders"
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
    """One planted tree or bush: where it stands, which crown it wears,
    and its wood's mesh. Its leaves' mesh is the next one."""

    var place: Vector3
    var crown: Int
    var wood: Int


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
    # The crown levels, and the wood and the leaves of each crown at each
    # level: entry `crown * len(levels) + level`.
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
        var white = Color(255, 255, 255)
        var two_sided = assets.programs.add(two_sided_program())
        self.grass = assets.materials.add(
            Material(
                white, side=DOUBLE_SIDE, vertex_colors=True, nodes=two_sided
            )
        )
        var lit_leaves = assets.programs.add(foliage_program())
        var foliage = assets.materials.add(
            Material(
                white, side=DOUBLE_SIDE, vertex_colors=True, nodes=lit_leaves
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
            Length(parameters.mountain_radius.to(METER) * 0.34, METER),
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
        ref canyon = ground.canyon
        if canyon.depth.value + canyon.rise.value > 0:
            var wall = cliff_wall(
                ground, Length(1200.0, METER), 1600, 96, parameters.seed
            )
            wall.compute_vertex_normals()
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(wall^),
                    stone,
                    scene.add(Object3D()),
                    receive_shadow=True,
                )
            )

        var toward = sun_direction(
            parameters.sun_elevation, parameters.sun_azimuth
        )
        # Each crown at each level, with the sun baked into its leaves.
        self.woods = List[GeometryId]()
        self.leaves = List[GeometryId]()
        for crown in range(len(parameters.crowns)):  # pragma: no branch
            ref kind = parameters.crowns[crown]
            var grown = grow_crown(kind, toward)
            for level in range(len(self.levels)):  # pragma: no branch
                var dressed = dress(grown, kind, self.levels[level])
                self.woods.append(assets.geometries.add(dressed.wood.clone()))
                self.leaves.append(
                    assets.geometries.add(dressed.leaves.clone())
                )
        self.trees = List[_Tree]()
        var first_level = len(self.levels)
        for index in range(len(parameters.plantings)):
            ref planting = parameters.plantings[index]
            var place = Vector3(
                planting.x,
                ground.height_at(planting.x, planting.z) - 0.1,
                planting.z,
            )
            var stand = Object3D()
            stand.set_position(place.x, place.y, place.z)
            stand.set_scale(planting.size, planting.size, planting.size)
            var node = scene.add(stand^)
            var entry = planting.crown * first_level
            scene.add_mesh(
                Mesh(
                    self.woods[entry],
                    painted,
                    node,
                    cast_shadow=True,
                    receive_shadow=True,
                )
            )
            # The leaves receive so that `foliage_program` can replace the
            # shadow with their baked sunlight.
            scene.add_mesh(
                Mesh(
                    self.leaves[entry],
                    foliage,
                    node,
                    cast_shadow=True,
                    receive_shadow=True,
                )
            )
            self.trees.append(
                _Tree(place, planting.crown, len(scene.meshes) - 2)
            )

        var seed = parameters.seed * 6151
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

        self.dome = paint_sky(
            renderer, assets, toward, parameters.sky, parameters.sky_size
        )
        scene.background = cube_background(self.dome.cube)
        self.sun = SunLight(scene, Color(255, 241, 222), 4.4)
        self.sun.cast_shadow = True
        self.sun.shadow.map_size = 4096
        self.sun.shadow.bias = -0.0004
        self.sun.shadow.normal_bias = 0.04
        # The cascades cover the meadow and the near trees, not the
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
        scene.fog = exp2_fog(self.dome.haze(), InverseLength(0.0008, PER_METER))
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
            var entry = tree.crown * len(self.levels) + level
            scene.meshes[tree.wood].geometry = self.woods[entry]
            scene.meshes[tree.wood + 1].geometry = self.leaves[entry]
            # The tree leans from its foot. A lean of zero is no turn,
            # whatever the axis.
            var lean = self.wind.tree_sway(
                tree.place.x, tree.place.z, hash01(t, 0, 977), time
            )
            var angle = lean.length()
            var axis = Vector3(lean.y, 0, -lean.x) / max(angle, 1.0e-9)
            var stand = scene.meshes[tree.wood].node
            scene.node(stand).set_rotation_from_axis_angle(
                axis, Angle(angle, RADIAN)
            )
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
            Mesh(
                id,
                self.grass,
                self.cluster_node[index],
                cast_shadow=True,
                receive_shadow=True,
            )
        )
        self.cluster_mesh[index] = len(scene.meshes) - 1
        return True
