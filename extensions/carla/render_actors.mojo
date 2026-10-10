# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Procedural vehicles and walkers for a CARLA world's actors.

`ActorVisuals.sync` gives each vehicle and walker of a `World` a model in
a scene and moves it to the actor's transform. A model is built from
ThreeMojo's geometries, sized from the actor's bounding box:

- **A vehicle** is a lofted body: a run of rounded cross sections, a
  superellipse seen from above and from the side, with an arch over each
  axle. A narrower loft on top is the cabin, its glass framed by painted
  pillars and a painted roof. The shape follows a `BodyStyle`: a sedan, a
  hatchback, an SUV or a van, chosen from the blueprint's id and the
  box's height. It has four wheels with rims, a grille, two headlamps and
  two tail lamps. The body wears car paint: a metallic base under a clear
  coat, in the color of the actor's `color` attribute.
- **A walker** is capsules for the legs, the arms and the body, a sphere
  for the head, and shoes. The colors of the clothes, the skin and the hair
  come from the actor's id. The legs and the arms swing with the walker's
  speed and simulation time.

The lamps follow the vehicle's `VehicleLightState`: the headlamps glow
for the position lamps and the low and high beams, and the tail lamps
glow for the position lamps and brighter for the brake. A vehicle with
its beams on also casts a spot light down the road.

`tag_meshes` gives each model's meshes its actor's semantic tag.

The sizes, colors and intensities are this port's own choices.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    POSITION,
    UV,
)
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from extensions.carla.assets import AssetRegistry, ModelPlacement
from extensions.carla.model_cache import ModelCache
from extensions.carla.actor import Actor, ActorId, VEHICLE_ACTOR, WALKER_ACTOR
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.render_textures import hash2
from extensions.carla.sensor import SemanticTag
from extensions.carla.vehicle import (
    LIGHT_BRAKE,
    LIGHT_HIGH_BEAM,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    VehicleLightState,
)
from extensions.carla.world import World
from geometries.box import box
from geometries.capsule import capsule
from geometries.cylinder import cylinder
from geometries.rounded_box import rounded_box
from geometries.sphere import sphere
from geometries.utils import merge_geometries
from lights.light import spot_light
from materials.material import (
    Material,
    MaterialId,
    physical_material,
    standard_material,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.cube_texture_store import SCENE_ENVIRONMENT
from objects.mesh import Mesh
from render.framebuffer import Color
from std.collections import Set
from std.math import cos, pow, sin, sqrt
from units.si import DEGREE, METER, Angle, Length

# How brightly a lamp glows for each light.
comptime POSITION_GLOW = Float32(0.6)
comptime LOW_BEAM_GLOW = Float32(5)
comptime HIGH_BEAM_GLOW = Float32(8)
comptime TAIL_GLOW = Float32(1.2)
comptime BRAKE_GLOW = Float32(4.5)
# How bright a vehicle's beam is on the road.
comptime LOW_BEAM_LIGHT = Float32(60)
comptime HIGH_BEAM_LIGHT = Float32(110)
# The color a vehicle has with no color attribute.
comptime DEFAULT_PAINT = Color(160, 162, 166)
# A wheel's radius.
comptime WHEEL_RADIUS = Float32(0.34)


def headlight_glow(state: VehicleLightState) -> Float32:
    """Return how brightly the headlamps glow.

    Args:
        state: The vehicle's lights.

    Returns:
        `HIGH_BEAM_GLOW` with the high beam on, else `LOW_BEAM_GLOW` with
        the low beam, else `POSITION_GLOW` with the position lamps, else
        zero.
    """
    if state.has(LIGHT_HIGH_BEAM):
        return HIGH_BEAM_GLOW
    if state.has(LIGHT_LOW_BEAM):
        return LOW_BEAM_GLOW
    if state.has(LIGHT_POSITION):
        return POSITION_GLOW
    return 0


def tail_light_glow(state: VehicleLightState) -> Float32:
    """Return how brightly the tail lamps glow.

    Args:
        state: The vehicle's lights.

    Returns:
        `BRAKE_GLOW` with the brake lamps on, else `TAIL_GLOW` with the
        position lamps or a beam on, else zero.
    """
    if state.has(LIGHT_BRAKE):
        return BRAKE_GLOW
    if (
        state.has(LIGHT_POSITION)
        or state.has(LIGHT_LOW_BEAM)
        or state.has(LIGHT_HIGH_BEAM)
    ):
        return TAIL_GLOW
    return 0


def beam_intensity(state: VehicleLightState) -> Float32:
    """Return how bright the light a vehicle casts down the road is.

    Args:
        state: The vehicle's lights.

    Returns:
        `HIGH_BEAM_LIGHT` with the high beam, `LOW_BEAM_LIGHT` with the
        low beam, else zero.
    """
    if state.has(LIGHT_HIGH_BEAM):
        return HIGH_BEAM_LIGHT
    if state.has(LIGHT_LOW_BEAM):
        return LOW_BEAM_LIGHT
    return 0


def vehicle_color(actor: Actor) raises -> Color:
    """Return the color a vehicle is painted.

    Args:
        actor: The vehicle.

    Returns:
        Its `color` attribute, or `DEFAULT_PAINT` without one.

    Raises:
        Error: If the attribute is not a color.
    """
    var attribute = actor.attribute("color")
    if not Bool(attribute):
        return DEFAULT_PAINT
    return attribute.value().as_color()


def car_paint(color: Color) raises -> Material:
    """Return car paint: a metallic base under a clear coat.

    Args:
        color: The paint's color, in sRGB.

    Returns:
        A physical material of roughness 0.32 and metalness 0.15 under a
        full clear coat of roughness 0.04, reflecting the scene.

    Raises:
        Error: Never; the material's checks are passed on.
    """
    return physical_material(
        color,
        roughness=0.32,
        metalness=0.15,
        clearcoat=1.0,
        clearcoat_roughness=0.04,
        env_map=SCENE_ENVIRONMENT,
    )


@fieldwise_init
struct BodyStyle(Equatable, ImplicitlyCopyable, Writable):
    """The shape of a vehicle's body."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the four styles.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3

    def write_to(self, mut writer: Some[Writer]):
        """Write the style's number.

        Args:
            writer: The destination.
        """
        writer.write("BodyStyle(", self.value, ")")


# A long trunk behind a sloping rear window.
comptime SEDAN = BodyStyle(0)
# A short tail behind a steep rear window.
comptime HATCHBACK = BodyStyle(1)
# A tall body with a long roof.
comptime SUV = BodyStyle(2)
# A tall box whose roof runs nearly end to end.
comptime VAN = BodyStyle(3)


def body_style_of(type_id: String, height: Float32) -> BodyStyle:
    """Return the body style of a vehicle blueprint.

    Args:
        type_id: The blueprint's id, such as `vehicle.mini.cooper`.
        height: The height of the vehicle's box, in meters.

    Returns:
        `VAN` for a box taller than 1.9 m; else `HATCHBACK` for a small
        car (a Mini, a Golf, a Prius, a Micra, a C3, a Fiat or a Seat);
        else `SUV` for a Patrol, a Jeep, a Wrangler or a Cybertruck; else
        `SEDAN`.
    """
    if height > 1.9:
        return VAN
    var hatchbacks: List[String] = [
        "mini",
        "golf",
        "prius",
        "micra",
        "c3",
        "fiat",
        "seat",
    ]
    # The list is a constant and not empty.
    for name in hatchbacks:  # pragma: no branch
        if name in type_id:
            return HATCHBACK
    var suvs: List[String] = ["patrol", "jeep", "wrangler", "cybertruck"]
    # The list is a constant and not empty.
    for name in suvs:  # pragma: no branch
        if name in type_id:
            return SUV
    return SEDAN


@fieldwise_init
struct BodyProfile(ImplicitlyCopyable):
    """Where a body style's lines fall, as shares of the box.

    The stations run from the rear bumper at zero to the front bumper at
    one. The heights are shares of the box's height.
    """

    # The underside's height.
    var clearance: Float32
    # The belt line's height at the rear and at the front.
    var belt_rear: Float32
    var belt_front: Float32
    # Where the glass cabin starts, where its roof starts and ends, and
    # where the windshield meets the hood.
    var cabin_start: Float32
    var roof_start: Float32
    var roof_end: Float32
    var cabin_end: Float32


def body_profile(style: BodyStyle) raises -> BodyProfile:
    """Return where a body style's lines fall.

    Args:
        style: The style.

    Returns:
        The profile.

    Raises:
        Error: If the style is not one of the four.
    """
    if not style.is_valid():
        raise Error("A body style must be one of the four")
    if style == HATCHBACK:
        return BodyProfile(0.2, 0.6, 0.55, 0.05, 0.14, 0.56, 0.77)
    if style == SUV:
        return BodyProfile(0.24, 0.6, 0.57, 0.05, 0.1, 0.62, 0.8)
    if style == VAN:
        return BodyProfile(0.14, 0.46, 0.44, 0.02, 0.05, 0.8, 0.93)
    return BodyProfile(0.2, 0.63, 0.56, 0.19, 0.37, 0.59, 0.79)


def superellipse(t: Float32, exponent: Float32) -> Float32:
    """Return the half-width of a superellipse at a place across it.

    Args:
        t: The place, from -1 to 1.
        exponent: The curve's exponent; 2 is an ellipse, and a larger one
            is squarer.

    Returns:
        `(1 - |t|^exponent)^(1 / exponent)`, zero at the ends.
    """
    return pow(max(1 - pow(abs(t), exponent), 0), 1 / exponent)


def _ease(t: Float32) -> Float32:
    """Return a cosine ease from zero to one."""
    var x = min(max(t, 0), 1)
    return (1 - cos(x * Float32(3.141592653589793))) / 2


def loft(
    stations: List[Float32],
    half_width: List[Float32],
    bottom: List[Float32],
    top: List[Float32],
    taper: Float32,
    ring: Int,
) raises -> BufferGeometry:
    """Return a closed surface through rounded cross sections.

    Each station is a cross section across z, a superellipse of exponent
    4 from `bottom` to `top` and `half_width` either side, narrowed toward
    the top by `taper`. The surface joins the sections in order, with
    shared corners, so its normals are smooth.

    Args:
        stations: Each section's x, in meters, in order.
        half_width: Each section's half-width.
        bottom: Each section's lowest y.
        top: Each section's highest y.
        taper: The share of the width lost at the top.
        ring: Corners around each section; at least 4.

    Returns:
        The surface, indexed, with normals and texture coordinates: u
        along the stations, v around the ring.

    Raises:
        Error: If there are fewer than two stations, the lists differ in
            length, or the ring has fewer than 4 corners.
    """
    var count = len(stations)
    if (
        count < 2
        or len(half_width) != count
        or len(bottom) != count
        or len(top) != count
    ):
        raise Error("A loft needs two or more stations of four lists alike")
    if ring < 4:
        raise Error("A loft's ring needs at least four corners")
    var positions = List[Float32]()
    var uvs = List[Float32]()
    # The count is checked to be two or more.
    for i in range(count):  # pragma: no branch
        var middle = (bottom[i] + top[i]) / 2
        var half = (top[i] - bottom[i]) / 2
        # The ring is checked to be four or more.
        for j in range(ring):  # pragma: no branch
            var angle = Float32(j) / Float32(ring) * Float32(6.283185307179586)
            var c = cos(angle)
            var s = sin(angle)
            var across = _signed_root(c)
            var up = _signed_root(s)
            var y = middle + half * up
            var rise = (up + 1) / 2
            var z = half_width[i] * across * (1 - taper * rise)
            positions.extend([stations[i], y, z])
            uvs.extend(
                [Float32(i) / Float32(count - 1), Float32(j) / Float32(ring)]
            )
    var index = List[Int]()
    # The count is checked to be two or more.
    for i in range(count - 1):  # pragma: no branch
        # The ring is checked to be four or more.
        for j in range(ring):  # pragma: no branch
            var a = i * ring + j
            var b = i * ring + (j + 1) % ring
            var c = (i + 1) * ring + (j + 1) % ring
            var d = (i + 1) * ring + j
            index.extend([a, d, c, a, c, b])
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(UV, BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    geometry.compute_vertex_normals()
    return geometry^


def _signed_root(x: Float32) -> Float32:
    """Return the sign of x times the square root of its size: a
    superellipse of exponent 4 from a circle."""
    var root = sqrt(abs(x))
    return root if x >= 0 else -root


# How many sections a body has along its length, and corners around each.
comptime BODY_STATIONS = 72
comptime BODY_RING = 28


def body_geometry(
    length: Float32, width: Float32, height: Float32, style: BodyStyle
) raises -> BufferGeometry:
    """Return a vehicle's lower body, below the belt line.

    Seen from above, the body is a superellipse of exponent 8. Seen from
    the side, it rises from its clearance to the belt line and rounds off
    at each bumper, with an arch over each axle.

    Args:
        length: The body's length; x runs forward from its middle.
        width: Its width, across z.
        height: The box's height; y runs up from the ground.
        style: The body style.

    Returns:
        The body, standing on the ground.

    Raises:
        Error: If the style is not one of the four.
    """
    var p = body_profile(style)
    var axle = length / 2 - wheel_inset(length)
    var arch = WHEEL_RADIUS + Float32(0.07)
    var stations = List[Float32]()
    var half = List[Float32]()
    var bottom = List[Float32]()
    var top = List[Float32]()
    # A constant count, more than zero.
    for i in range(BODY_STATIONS):  # pragma: no branch
        var s = Float32(i) / Float32(BODY_STATIONS - 1)
        var x = (s - Float32(0.5)) * length
        var t = s * 2 - 1
        var low = p.clearance * height
        # Two sides.
        for side in [Float32(-1), Float32(1)]:  # pragma: no branch
            var dx = x - side * axle
            if abs(dx) < arch:
                low = max(low, WHEEL_RADIUS + sqrt(arch * arch - dx * dx))
        var belt = height * (p.belt_rear + (p.belt_front - p.belt_rear) * s)
        var bumper = height * p.clearance * Float32(1.1)
        var rounded = superellipse(t, 3.5)
        stations.append(x)
        half.append(width / 2 * superellipse(t, 8))
        bottom.append(bumper + (min(low, belt - 0.1) - bumper) * rounded)
        top.append(bumper + (belt - bumper) * rounded)
    return loft(stations, half, bottom, top, 0.06, BODY_RING)


def cabin_geometry(
    length: Float32, width: Float32, height: Float32, style: BodyStyle
) raises -> BufferGeometry:
    """Return a vehicle's cabin: its glass, its pillars and its roof.

    The cabin rises from the belt line at `cabin_start` to the roof at
    `roof_start`, runs flat to `roof_end` and falls to the belt line at
    `cabin_end`. The corners around its top, a pillar at its middle and
    its roof wear the paint, in group 0; the rest is glass, in group 1.

    Args:
        length: The body's length.
        width: The body's width.
        height: The box's height; the roof stands at it.
        style: The body style.

    Returns:
        The cabin, with two groups.

    Raises:
        Error: If the style is not one of the four.
    """
    var p = body_profile(style)
    var count = 40
    var stations = List[Float32]()
    var half = List[Float32]()
    var bottom = List[Float32]()
    var top = List[Float32]()
    # A constant count, more than zero.
    for i in range(count):  # pragma: no branch
        var f = Float32(i) / Float32(count - 1)
        var s = p.cabin_start + (p.cabin_end - p.cabin_start) * f
        var belt = height * (p.belt_rear + (p.belt_front - p.belt_rear) * s)
        var rise = _ease((s - p.cabin_start) / (p.roof_start - p.cabin_start))
        var fall = _ease((p.cabin_end - s) / (p.cabin_end - p.roof_end))
        var roof = height - Float32(0.02)
        stations.append((s - Float32(0.5)) * length)
        half.append(width * Float32(0.44) * superellipse(f * 2 - 1, 10))
        bottom.append(belt - Float32(0.06))
        top.append(
            belt - Float32(0.06) + (roof - belt + 0.06) * min(rise, fall)
        )
    var cabin = loft(stations, half, bottom, top, 0.22, BODY_RING)
    # Sort the triangles into paint and glass.
    var paint = List[Int]()
    var glass = List[Int]()
    var pillar = (Float32(0.5) - p.cabin_start) / (p.cabin_end - p.cabin_start)
    # A constant count, more than zero.
    for i in range(count - 1):  # pragma: no branch
        var f = (Float32(i) + 0.5) / Float32(count - 1)
        var s = p.cabin_start + (p.cabin_end - p.cabin_start) * f
        var on_roof = s > p.roof_start + 0.01 and s < p.roof_end - 0.01
        var on_pillar = abs(f - pillar) < Float32(0.025)
        # A constant count, more than zero.
        for j in range(BODY_RING):  # pragma: no branch
            var angle = (
                (Float32(j) + 0.5)
                / Float32(BODY_RING)
                * Float32(6.283185307179586)
            )
            var up = sin(angle)
            var painted = up > 0.93 and on_roof
            painted = painted or (up > 0.72 and up <= 0.93)
            painted = painted or (on_pillar and up > -0.2)
            var slot = (i * BODY_RING + j) * 6
            # Two triangles of three corners.
            for k in range(6):  # pragma: no branch
                if painted:
                    paint.append(cabin.index[slot + k])
                else:
                    glass.append(cabin.index[slot + k])
    var painted_count = len(paint)
    var total = painted_count + len(glass)
    paint.extend(glass^)
    cabin.set_index(paint^)
    cabin.add_group(0, painted_count, MaterialIndex(0))
    cabin.add_group(painted_count, total - painted_count, MaterialIndex(1))
    return cabin^


def wheel_inset(length: Float32) -> Float32:
    """Return how far each axle stands in from its bumper.

    Args:
        length: The body's length.

    Returns:
        A sixth of the length plus 0.1 m.
    """
    return length / 6 + Float32(0.1)


@fieldwise_init
struct VehicleModel(ImplicitlyCopyable):
    """The geometry of one vehicle size and style."""

    var extent: Vector2
    var height: Float32
    var style: BodyStyle
    var body: GeometryId
    # Paint in group 0, glass in group 1.
    var cabin: GeometryId
    var tires: GeometryId
    var rims: GeometryId
    var grille: GeometryId
    var heads: GeometryId
    var tails: GeometryId


def vehicle_model(
    mut assets: Assets, extent: BoundingBox, style: BodyStyle
) raises -> VehicleModel:
    """Build the geometry of a vehicle whose box has an extent.

    Args:
        assets: The stores; the geometry is added.
        extent: The box; its half-extents are read.
        style: The body style.

    Returns:
        The model's geometry ids.

    Raises:
        Error: If the box has no size, or the style is not one of the
            four.
    """
    var length = extent.extent.x * 2
    var width = extent.extent.y * 2
    var height = extent.extent.z * 2
    if not (length > 1 and width > 0.5 and height > 0.8):
        raise Error("A vehicle model needs a box at least 1 x 0.5 x 0.8 m")
    var p = body_profile(style)
    var body_width = width * Float32(0.92)
    var body = body_geometry(length, body_width, height, style)
    var cabin = cabin_geometry(length, body_width, height, style)
    var tires = List[BufferGeometry]()
    var rims = List[BufferGeometry]()
    var axle = length / 2 - wheel_inset(length)
    # Four wheels.
    for corner in range(4):  # pragma: no branch
        var x = axle if corner < 2 else -axle
        var side = Float32(1) if corner % 2 == 0 else Float32(-1)
        var z = (body_width / 2 - Float32(0.13)) * side
        var tire = cylinder(
            Length(WHEEL_RADIUS, METER),
            Length(WHEEL_RADIUS, METER),
            Length(0.24, METER),
            28,
        )
        tire.rotate_x(Angle(90, DEGREE))
        tire.translate(
            Length(x, METER), Length(WHEEL_RADIUS, METER), Length(z, METER)
        )
        tires.append(tire^)
        var rim = cylinder(
            Length(0.21, METER), Length(0.21, METER), Length(0.02, METER), 20
        )
        rim.rotate_x(Angle(90, DEGREE))
        rim.translate(
            Length(x, METER),
            Length(WHEEL_RADIUS, METER),
            Length(z + side * Float32(0.115), METER),
        )
        rims.append(rim^)
    # The lamps and the grille sit on the rounded nose and tail.
    var nose = length / 2 * Float32(0.955)
    var belt_front = height * p.belt_front
    var belt_rear = height * p.belt_rear
    var grille = rounded_box(
        Length(0.1, METER),
        Length(0.16, METER),
        Length(body_width * 0.38, METER),
        1,
        Length(0.03, METER),
    )
    grille.translate(
        Length(nose - 0.02, METER),
        Length(belt_front * 0.62, METER),
        Length(0, METER),
    )
    var heads = List[BufferGeometry]()
    var tails = List[BufferGeometry]()
    # Two sides.
    for side in [Float32(1), Float32(-1)]:  # pragma: no branch
        var head = rounded_box(
            Length(0.12, METER),
            Length(0.1, METER),
            Length(0.34, METER),
            2,
            Length(0.04, METER),
        )
        head.translate(
            Length(nose - 0.06, METER),
            Length(belt_front * 0.8, METER),
            Length(side * (body_width / 2 - 0.3), METER),
        )
        heads.append(head^)
        var tail = rounded_box(
            Length(0.12, METER),
            Length(0.12, METER),
            Length(0.36, METER),
            2,
            Length(0.04, METER),
        )
        tail.translate(
            Length(-nose + 0.06, METER),
            Length(belt_rear * 0.84, METER),
            Length(side * (body_width / 2 - 0.28), METER),
        )
        tails.append(tail^)
    return VehicleModel(
        Vector2(length, width),
        height,
        style,
        assets.geometries.add(body^),
        assets.geometries.add(cabin^),
        assets.geometries.add(merge_all(tires)),
        assets.geometries.add(merge_all(rims)),
        assets.geometries.add(grille^),
        assets.geometries.add(merge_all(heads)),
        assets.geometries.add(merge_all(tails)),
    )


def merge_all(parts: List[BufferGeometry]) raises -> BufferGeometry:
    """Return parts merged into one geometry, without groups.

    Args:
        parts: The parts, at least one, alike in their attributes.

    Returns:
        The merged geometry.

    Raises:
        Error: If the parts cannot be merged.
    """
    return merge_geometries(parts)


@fieldwise_init
struct VehicleVisual(Copyable, Movable):
    """One vehicle's model in a scene."""

    var actor: ActorId
    var node: NodeId
    var paint: MaterialId
    var heads: MaterialId
    var tails: MaterialId
    # The beam's spot light, as its index in `Scene.lights`.
    var beam: Int
    # The model's meshes: the first's index in `Scene.meshes`, and how
    # many follow it.
    var first_mesh: Int
    var mesh_count: Int
    # What the model was built from. Only a new actor with the same key
    # can take the model over.
    var key: String


@fieldwise_init
struct WalkerVisual(Copyable, Movable):
    """One walker's model in a scene."""

    var actor: ActorId
    var node: NodeId
    # The hips' and shoulders' nodes: left leg, right leg, left arm, right
    # arm.
    var limbs: List[NodeId]
    # The model's meshes: the first's index in `Scene.meshes`, and how
    # many follow it.
    var first_mesh: Int
    var mesh_count: Int
    # What the model was built from. Only a new actor with the same key
    # can take the model over.
    var key: String
    # A procedural walker's own shirt, trousers and skin; empty for a
    # cached model.
    var clothes: List[MaterialId]


def clothing(id: ActorId) -> Tuple[Color, Color, Color]:
    """Return a walker's shirt, trousers and skin colors.

    Args:
        id: The walker.

    Returns:
        Three colors picked from small palettes by the id.
    """
    var shirts: List[Color] = [
        Color(180, 40, 40),
        Color(40, 80, 160),
        Color(230, 230, 225),
        Color(60, 130, 70),
        Color(230, 170, 40),
        Color(40, 40, 44),
    ]
    var trousers: List[Color] = [
        Color(40, 50, 80),
        Color(30, 30, 32),
        Color(120, 100, 80),
        Color(90, 90, 96),
    ]
    var skins: List[Color] = [
        Color(236, 196, 164),
        Color(198, 150, 110),
        Color(141, 94, 62),
        Color(90, 60, 40),
    ]
    var a = Int(hash2(id.value, 1, 91) * 6)
    var b = Int(hash2(id.value, 2, 91) * 4)
    var c = Int(hash2(id.value, 3, 91) * 4)
    return (shirts[a], trousers[b], skins[c])


def stride(speed: Float32) -> Angle:
    """Return the target swing amplitude at a speed, without a gait phase.

    Args:
        speed: The walker's speed in meters per second.

    Returns:
        Twelve degrees per meter per second, up to 30 degrees.
    """
    return Angle(min(max(speed, 0) * 12, 30), DEGREE)


struct ActorVisuals(Movable):
    """The models of a world's vehicles and walkers in a scene."""

    var vehicles: List[VehicleVisual]
    var walkers: List[WalkerVisual]
    var models: List[VehicleModel]
    var cached_models: ModelCache
    var glass: MaterialId
    var rubber: MaterialId
    var chrome: MaterialId
    var grille: MaterialId
    var hair: MaterialId
    var ready: Bool

    def __init__(out self):
        """Start with no models."""
        self.vehicles = List[VehicleVisual]()
        self.walkers = List[WalkerVisual]()
        self.models = List[VehicleModel]()
        self.cached_models = ModelCache()
        self.glass = MaterialId(0)
        self.rubber = MaterialId(0)
        self.chrome = MaterialId(0)
        self.grille = MaterialId(0)
        self.hair = MaterialId(0)
        self.ready = False

    def _shared(mut self, mut assets: Assets) raises:
        """Add the materials every model shares, once."""
        if self.ready:
            return
        self.glass = assets.materials.add(
            physical_material(
                Color(38, 46, 54),
                roughness=0.05,
                metalness=0.2,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        self.rubber = assets.materials.add(
            standard_material(
                Color(24, 24, 26), roughness=0.9, env_map=SCENE_ENVIRONMENT
            )
        )
        self.chrome = assets.materials.add(
            standard_material(
                Color(200, 200, 204),
                roughness=0.25,
                metalness=1,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        self.grille = assets.materials.add(
            standard_material(
                Color(20, 20, 22), roughness=0.6, env_map=SCENE_ENVIRONMENT
            )
        )
        self.hair = assets.materials.add(
            standard_material(
                Color(40, 28, 20), roughness=0.8, env_map=SCENE_ENVIRONMENT
            )
        )
        self.ready = True

    def _model(
        mut self, mut assets: Assets, extent: BoundingBox, style: BodyStyle
    ) raises -> VehicleModel:
        """Return the model of a box's size and a style, building it the
        first time."""
        for model in self.models:
            if (
                model.extent
                == Vector2(extent.extent.x * 2, extent.extent.y * 2)
                and model.height == extent.extent.z * 2
                and model.style == style
            ):
                return model
        var model = vehicle_model(assets, extent, style)
        self.models.append(model)
        return model

    def _model_key(
        self, world: World, id: ActorId, registry: AssetRegistry
    ) raises -> String:
        """Return what a vehicle's or walker's model is built from."""
        var box = world.get_bounding_box(id)
        var type_id = world.actor(id).type_id
        var cached = String("")
        if Bool(registry.cached_entry(registry.model_key(type_id))):
            cached = registry.model_key(type_id)
        return (
            type_id
            + "|"
            + cached
            + "|"
            + String(box.extent.x)
            + ","
            + String(box.extent.y)
            + ","
            + String(box.extent.z)
        )

    def _reuse_vehicle(
        mut self,
        world: World,
        id: ActorId,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises -> Bool:
        """Give a new vehicle the first hidden model of its key.

        The model's own paint takes the new actor's color. Its lamps and
        beam follow the new actor's light state on this sync.
        """
        var key = self._model_key(world, id, registry)
        for k in range(len(self.vehicles)):
            if self.vehicles[k].key != key or world.is_alive(
                self.vehicles[k].actor
            ):
                continue
            assets.materials.materials[
                self.vehicles[k].paint.value
            ] = car_paint(vehicle_color(world.actor(id)))
            self.vehicles[k].actor = id
            return True
        return False

    def _reuse_walker(
        mut self,
        world: World,
        id: ActorId,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises -> Bool:
        """Give a new walker the first hidden model of its key.

        A procedural model's clothes take the new actor's colors.
        """
        var key = self._model_key(world, id, registry)
        for k in range(len(self.walkers)):
            if self.walkers[k].key != key or world.is_alive(
                self.walkers[k].actor
            ):
                continue
            if len(self.walkers[k].clothes) == 3:
                var colors = clothing(id)
                var looks = _clothes(colors)
                for c in range(3):  # pragma: no branch
                    assets.materials.materials[
                        self.walkers[k].clothes[c].value
                    ] = looks[c].copy()
            self.walkers[k].actor = id
            return True
        return False

    def _add_vehicle(
        mut self,
        world: World,
        id: ActorId,
        mut scene: Scene,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises:
        """Build a vehicle's model into the scene: the cached model of its
        blueprint, or the procedural one."""
        var box = world.get_bounding_box(id)
        var type_id = world.actor(id).type_id
        var paint_material = car_paint(vehicle_color(world.actor(id)))
        var first = len(scene.meshes)
        var scanned = registry.cached_entry(registry.model_key(type_id))
        var placement = Optional[ModelPlacement]()
        if Bool(scanned):
            # Load before actor-owned allocations. A failed model and retry
            # must not leave an unused holder or three override materials.
            placement = self.cached_models.place(
                registry,
                scanned.value(),
                scene,
                assets,
                NO_PARENT,
                Vector3(box.extent.x * 2, box.extent.z * 2, box.extent.y * 2),
            )
        var node = scene.add(Object3D())
        var paint = assets.materials.add(paint_material)
        var heads = assets.materials.add(
            standard_material(
                Color(230, 230, 220),
                roughness=0.1,
                emissive=Color(255, 244, 220),
                emissive_intensity=0,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        var tails = assets.materials.add(
            standard_material(
                Color(120, 10, 10),
                roughness=0.2,
                emissive=Color(255, 20, 10),
                emissive_intensity=0,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        var front = box.extent.x
        if Bool(placement):
            var placed = placement.value().copy()
            scene.add(placed.pivot, parent=node)
            first = placed.first_mesh
            # CARLA paints a car from its blueprint's color and lights its
            # lamps from its light state: the model wears the procedural
            # car's paint and lamps.
            # `place_model` refuses a model with no mesh.
            for m in range(
                first, first + placed.mesh_count
            ):  # pragma: no branch
                var own = scene.meshes[m].material
                if own in placed.paint:
                    scene.meshes[m].material = paint
                elif own in placed.heads:
                    scene.meshes[m].material = heads
                elif own in placed.tails:
                    scene.meshes[m].material = tails
        else:
            var model = self._model(
                assets, box, body_style_of(type_id, box.extent.z * 2)
            )
            scene.add_mesh(
                Mesh(
                    model.cabin,
                    [paint, self.glass],
                    node,
                    cast_shadow=True,
                    receive_shadow=True,
                )
            )
            var parts: List[Tuple[GeometryId, MaterialId]] = [
                (model.body, paint),
                (model.tires, self.rubber),
                (model.rims, self.chrome),
                (model.grille, self.grille),
                (model.heads, heads),
                (model.tails, tails),
            ]
            # The list is a constant and not empty.
            for part in parts:  # pragma: no branch
                scene.add_mesh(
                    Mesh(
                        part[0],
                        part[1],
                        node,
                        cast_shadow=True,
                        receive_shadow=True,
                    )
                )
            front = model.extent.x / 2
        var count = len(scene.meshes) - first
        var bulb = Object3D()
        bulb.set_position(front + 0.2, 0.62, 0)
        var aim = Object3D()
        aim.set_position(front + 18, -0.8, 0)
        var bulb_node = scene.attach(bulb^, node)
        var aim_node = scene.attach(aim^, node)
        var beam = spot_light(
            Color(255, 246, 228),
            bulb_node,
            0,
            45,
            Angle(32, DEGREE),
            0.5,
            2,
            aim_node,
        )
        var index = len(scene.lights)
        scene.add_light(beam)
        self.vehicles.append(
            VehicleVisual(
                id,
                node,
                paint,
                heads,
                tails,
                index,
                first,
                count,
                self._model_key(world, id, registry),
            )
        )

    def _add_walker(
        mut self,
        world: World,
        id: ActorId,
        mut scene: Scene,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises:
        """Build a walker's model into the scene: the cached model of its
        blueprint, still, or the procedural one, whose limbs swing."""
        var scanned = registry.cached_entry(
            registry.model_key(world.actor(id).type_id)
        )
        if Bool(scanned):
            var box = world.get_bounding_box(id)
            var holder = scene.add(Object3D())
            scene.update()
            var placed = registry.place_model(
                scanned.value(),
                scene,
                assets,
                holder,
                Vector3(box.extent.x * 2, box.extent.z * 2, box.extent.y * 2),
            )
            self.walkers.append(
                WalkerVisual(
                    id,
                    holder,
                    List[NodeId](),
                    placed.first_mesh,
                    placed.mesh_count,
                    self._model_key(world, id, registry),
                    List[MaterialId](),
                )
            )
            return
        var looks = _clothes(clothing(id))
        var shirt = assets.materials.add(looks[0].copy())
        var trousers = assets.materials.add(looks[1].copy())
        var skin = assets.materials.add(looks[2].copy())
        var first = len(scene.meshes)
        var node = scene.add(Object3D())
        var torso = capsule(Length(0.17, METER), Length(0.36, METER), 4, 10)
        torso.scale(Float32(0.62), 1, 1)
        torso.translate(Length(0, METER), Length(1.2, METER), Length(0, METER))
        scene.add_mesh(
            Mesh(
                assets.geometries.add(torso^),
                shirt,
                node,
                cast_shadow=True,
                receive_shadow=True,
            )
        )
        var head = sphere(Length(0.105, METER), 14, 10)
        head.translate(Length(0, METER), Length(1.63, METER), Length(0, METER))
        scene.add_mesh(
            Mesh(
                assets.geometries.add(head^),
                skin,
                node,
                cast_shadow=True,
                receive_shadow=True,
            )
        )
        var hair = sphere(
            Length(0.11, METER),
            14,
            6,
            Angle(0, DEGREE),
            Angle(360, DEGREE),
            Angle(0, DEGREE),
            Angle(80, DEGREE),
        )
        hair.translate(
            Length(-0.01, METER), Length(1.65, METER), Length(0, METER)
        )
        scene.add_mesh(
            Mesh(
                assets.geometries.add(hair^), self.hair, node, cast_shadow=True
            )
        )
        var limbs = List[NodeId]()
        var specs: List[Tuple[Float32, Float32, Float32, Float32]] = [
            (Float32(0.92), Float32(-0.09), Float32(0.07), Float32(0.72)),
            (Float32(0.92), Float32(0.09), Float32(0.07), Float32(0.72)),
            (Float32(1.44), Float32(-0.21), Float32(0.045), Float32(0.52)),
            (Float32(1.44), Float32(0.21), Float32(0.045), Float32(0.52)),
        ]
        # Four limbs.
        for k in range(4):  # pragma: no branch
            var spec = specs[k]
            var joint = Object3D()
            joint.set_position(0, spec[0], spec[1])
            var joint_node = scene.attach(joint^, node)
            var limb = capsule(
                Length(spec[2], METER), Length(spec[3], METER), 3, 8
            )
            limb.translate(
                Length(0, METER),
                Length(-spec[3] / 2 - spec[2], METER),
                Length(0, METER),
            )
            var look = trousers if k < 2 else shirt
            if k < 2:
                var shoe = rounded_box(
                    Length(0.26, METER),
                    Length(0.08, METER),
                    Length(0.11, METER),
                    1,
                    Length(0.03, METER),
                )
                shoe.translate(
                    Length(0.05, METER),
                    Length(-spec[0] + 0.04, METER),
                    Length(0, METER),
                )
                scene.add_mesh(
                    Mesh(
                        assets.geometries.add(shoe^),
                        self.hair,
                        joint_node,
                        cast_shadow=True,
                    )
                )
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(limb^),
                    look,
                    joint_node,
                    cast_shadow=True,
                    receive_shadow=True,
                )
            )
            limbs.append(joint_node)
        self.walkers.append(
            WalkerVisual(
                id,
                node,
                limbs^,
                first,
                len(scene.meshes) - first,
                self._model_key(world, id, registry),
                [shirt, trousers, skin],
            )
        )

    def sync(
        mut self,
        world: World,
        mut scene: Scene,
        mut assets: Assets,
        registry: AssetRegistry = AssetRegistry(),
    ) raises:
        """Give each live vehicle and walker a model, and pose every model
        as its actor is now.

        A blueprint whose key the registry's cache holds, by its id or by
        its family's wildcard, gets the cached model; every other one gets
        the procedural model. A model whose actor is gone is hidden, and
        its beam put out. A new actor takes over the first hidden model
        built from the same blueprint, box and cached model, so a cycle
        of spawns and destroys does not grow the scene or the stores.

        Args:
            world: The world.
            scene: The scene; models are added and moved.
            assets: The stores; geometry and materials are added, and the
                lamp materials change.
            registry: The photoscanned assets; none by default.

        Raises:
            Error: If the world refuses an actor, or a cached model cannot
                be read.
        """
        self._shared(assets)
        # Rebuild these indexes from the public lists in one pass. Repeated
        # syncs must not search all existing models for every live actor.
        var vehicles = Set[Int]()
        var walkers = Set[Int]()
        for v in self.vehicles:
            vehicles.add(v.actor.value)
        for w in self.walkers:
            walkers.add(w.actor.value)
        # A world always has its spectator.
        for id in world.get_actors():  # pragma: no branch
            var kind = world.actor(id).kind
            if kind == VEHICLE_ACTOR and id.value not in vehicles:
                if not self._reuse_vehicle(world, id, assets, registry):
                    self._add_vehicle(world, id, scene, assets, registry)
            if kind == WALKER_ACTOR and id.value not in walkers:
                if not self._reuse_walker(world, id, assets, registry):
                    self._add_walker(world, id, scene, assets, registry)
        for v in self.vehicles:
            var alive = world.is_alive(v.actor)
            scene.node(v.node).visible = alive
            if not alive:
                scene.lights[v.beam].intensity = 0
                continue
            self._pose(world, v.actor, v.node, scene)
            var state = world.get_light_state(v.actor)
            _glow(assets, v.heads, headlight_glow(state))
            _glow(assets, v.tails, tail_light_glow(state))
            scene.lights[v.beam].intensity = beam_intensity(state)
        for w in self.walkers:
            var alive = world.is_alive(w.actor)
            scene.node(w.node).visible = alive
            if not alive:
                continue
            self._pose(world, w.actor, w.node, scene)
            var swing = world.get_walker_gait(w.actor).swing()
            # A procedural walker has four limbs, and a cached model none.
            for k in range(len(w.limbs)):
                var sign = Float32(1) if k == 0 or k == 3 else Float32(-1)
                scene.node(w.limbs[k]).set_rotation_from_axis_angle(
                    Vector3(0, 0, 1), Angle(swing.to(DEGREE) * sign, DEGREE)
                )
        scene.update()

    def tag_meshes(self, world: World, mut tags: List[SemanticTag]) raises:
        """Tag each model's meshes with its actor's first semantic tag.

        A model whose actor is gone keeps the tags it has.

        Args:
            world: The world; each actor's tags are read.
            tags: One tag per mesh of the scene, changed in place.

        Raises:
            Error: If a model's meshes lie past the end of `tags`.
        """
        var ranges = List[Tuple[ActorId, Int, Int]]()
        for v in self.vehicles:
            ranges.append((v.actor, v.first_mesh, v.mesh_count))
        for w in self.walkers:
            ranges.append((w.actor, w.first_mesh, w.mesh_count))
        for r in ranges:
            if r[1] + r[2] > len(tags):
                raise Error("The tags do not cover every model's meshes")
            if not world.is_alive(r[0]):
                continue
            var tag = world.actor(r[0]).semantic_tags[0]
            # A model has meshes.
            for i in range(r[1], r[1] + r[2]):  # pragma: no branch
                tags[i] = tag

    def _pose(
        self, world: World, id: ActorId, node: NodeId, mut scene: Scene
    ) raises:
        """Stand a model where its actor is, feet on the box's floor."""
        var transform = world.get_transform(id)
        var box = world.get_bounding_box(id)
        var floor = box.location.z - box.extent.z
        var matrix = transform.three_matrix()
        var up = transform.rotation.up_vector()
        var at = transform.location + up * floor
        ref target = scene.node(node)
        target.set_rotation_from_matrix(matrix)
        target.set_position(at.x, at.z, at.y)


def _clothes(colors: Tuple[Color, Color, Color]) raises -> List[Material]:
    """Return a procedural walker's shirt, trousers and skin."""
    return [
        standard_material(colors[0], roughness=0.85, env_map=SCENE_ENVIRONMENT),
        standard_material(colors[1], roughness=0.85, env_map=SCENE_ENVIRONMENT),
        standard_material(colors[2], roughness=0.6, env_map=SCENE_ENVIRONMENT),
    ]


def _glow(mut assets: Assets, id: MaterialId, intensity: Float32) raises:
    """Set a lamp material's glow."""
    var lamp = assets.materials.get(id)
    lamp.emissive_intensity = intensity
    assets.materials.materials[id.value] = lamp
