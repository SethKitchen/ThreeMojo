# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Traffic lights and signs, placed from a map's signals.

`signal_props` reads each signal of a `Map` and decides what stands
there. It follows the choice a world makes: a signal whose type
`is_traffic_light` names is a traffic light, and `sign_kind_of` picks the
stop, yield and speed-limit signs. A prop stands at the signal's place,
with its face toward the traffic the signal is for:

- A signal of orientation "+" is for the traffic that runs along the
  road's s, so its face looks back along s. One of orientation "-" looks
  along s. One for both directions looks back along s.
- A traffic light has a head on its pole at the signal's height, and an
  arm at `ARM_HEIGHT` over the road, toward the reference line, with a
  second head at its end. The arm reaches the signal's lateral offset
  less 2 m, and never more than `MAX_REACH`.
- A sign has a pole and a face: an octagon for a stop sign, a triangle
  that points down for a yield sign, a disc for a speed limit.

`Props` builds the props into a scene. Each traffic light has three lamp
materials, red, yellow and green. `set_state` makes the lamp of the
light's state glow and turns the other two off, as a traffic light does;
`set_states` reads every state from a `World`.

The sizes and colors are this port's own choices.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.carla.actor import (
    GREEN,
    RED,
    TrafficLightState,
    YELLOW,
)
from extensions.carla.map import Map, Signal, is_traffic_light
from extensions.carla.road_info import ORIENTATION_NEGATIVE, SignalId
from extensions.carla.sensor import (
    POLE,
    SemanticTag,
    TRAFFIC_LIGHT,
    TRAFFIC_SIGN,
)
from extensions.carla.traffic_sign import (
    SPEED_LIMIT_SIGN,
    STOP_SIGN,
    sign_kind_of,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import World
from geometries.box import box
from geometries.cylinder import cylinder
from geometries.rounded_box import rounded_box
from geometries.utils import merge_geometries
from materials.material import MaterialId, standard_material
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture_store import SCENE_ENVIRONMENT
from render.framebuffer import Color
from std.math import atan2
from units.si import DEGREE, METER, RADIAN, Angle, Length

# How high a traffic light's arm runs, and how far it reaches at most.
comptime ARM_HEIGHT = Length(5.6, METER)
comptime MAX_REACH = Length(6.5, METER)
# How bright a lit lamp glows.
comptime LAMP_GLOW = Float32(9)
# How far apart a head's lamps sit, center to center.
comptime LAMP_PITCH = Float32(0.3)


@fieldwise_init
struct PropKind(Equatable, ImplicitlyCopyable, Writable):
    """What stands at a signal."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the four kinds.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3

    def write_to(self, mut writer: Some[Writer]):
        """Write the kind's number.

        Args:
            writer: The destination.
        """
        writer.write("PropKind(", self.value, ")")


comptime TRAFFIC_LIGHT_PROP = PropKind(0)
comptime STOP_PROP = PropKind(1)
comptime YIELD_PROP = PropKind(2)
comptime SPEED_LIMIT_PROP = PropKind(3)


def prop_kind_of(signal: Signal) -> Optional[PropKind]:
    """Return what stands at a signal, if anything.

    Args:
        signal: The signal.

    Returns:
        A traffic light for a traffic-light type; a stop, yield or
        speed-limit sign where `sign_kind_of` finds one; else None.
    """
    if is_traffic_light(signal.type):
        return TRAFFIC_LIGHT_PROP
    var kind = sign_kind_of(signal.type, signal.subtype, signal.name)
    if not Bool(kind):
        return None
    if kind.value() == STOP_SIGN:
        return STOP_PROP
    if kind.value() == SPEED_LIMIT_SIGN:
        return SPEED_LIMIT_PROP
    return YIELD_PROP


def signal_facing(signal: Signal) -> Vector3:
    """Return which way a signal's face looks, in CARLA's frame.

    Args:
        signal: The signal.

    Returns:
        The unit vector: along the signal's forward vector for orientation
        "-", and against it otherwise. It is level.
    """
    var forward = signal.transform.rotation.forward_vector()
    var level = Vector3(forward.x, forward.y, 0)
    level.normalize()
    if signal.orientation() == ORIENTATION_NEGATIVE:
        return level
    return -level


@fieldwise_init
struct SignalProp(Copyable, Movable, Writable):
    """A traffic light or sign, placed from a signal."""

    var kind: PropKind
    var signal_id: SignalId
    # The foot of the pole, on the road's surface, in CARLA's frame.
    var foot: Vector3
    # How high the head or the face stands above the foot.
    var height: Length
    # Which way the face looks, level and unit length.
    var facing: Vector3
    # The level unit direction toward the road's reference line.
    var inward: Vector3
    # How far a traffic light's arm reaches; zero for a sign.
    var reach: Length

    def write_to(self, mut writer: Some[Writer]):
        """Write the prop.

        Args:
            writer: The destination.
        """
        writer.write(
            "SignalProp(",
            self.kind.value,
            ", ",
            self.signal_id.value,
            ", reach=",
            self.reach.to(METER),
            ")",
        )


def signal_prop(map: Map, signal: Signal) raises -> Optional[SignalProp]:
    """Return the prop that stands at a signal, if any.

    Args:
        map: The map; the signal's road is read.
        signal: The signal.

    Returns:
        The prop, whose `inward` points level and square to the road,
        from the signal's side toward the road's reference line, and to
        the road's right for a signal on the line; None for a signal with
        no prop.

    Raises:
        Error: If the signal's road is not in the map.
    """
    var kind = prop_kind_of(signal)
    if not Bool(kind):
        return None
    var at = signal.transform.location
    var line = map.road(signal.road_id).directed_point(signal.s).to_carla()
    var right = line.rotation.right_vector()
    var inward = Vector3(right.x, right.y, 0)
    inward.normalize()
    var side = (at.x - line.location.x) * inward.x + (
        at.y - line.location.y
    ) * inward.y
    if side > 0:
        inward = -inward
    var reach = Float32(0)
    if kind.value() == TRAFFIC_LIGHT_PROP:
        reach = min(max(Float32(abs(signal.t)) - 2, 0), MAX_REACH.to(METER))
    return SignalProp(
        kind.value(),
        signal.signal_id,
        Vector3(at.x, at.y, at.z - Float32(signal.z_offset)),
        Length(Float32(signal.z_offset), METER),
        signal_facing(signal),
        inward,
        Length(reach, METER),
    )


def signal_props(map: Map) raises -> List[SignalProp]:
    """Return a prop for each signal that has one.

    Args:
        map: The map.

    Returns:
        The props, in the map's signal order.

    Raises:
        Error: If a signal's road is not in the map.
    """
    var out = List[SignalProp]()
    for signal in map.signals:
        var prop = signal_prop(map, signal)
        if Bool(prop):
            out.append(prop.value().copy())
    return out^


def lamp_intensity(
    state: TrafficLightState, lamp: TrafficLightState
) raises -> Float32:
    """Return how strongly one lamp of a traffic light glows.

    Args:
        state: The light's state.
        lamp: Which lamp: `RED`, `YELLOW` or `GREEN`.

    Returns:
        One when the lamp is the state's, zero otherwise. Off and unknown
        light no lamp.

    Raises:
        Error: If the lamp is not red, yellow or green.
    """
    if not (lamp == RED or lamp == YELLOW or lamp == GREEN):
        raise Error("A traffic light's lamp is red, yellow or green")
    return Float32(1) if state == lamp else Float32(0)


@fieldwise_init
struct LampSet(Copyable, Movable):
    """The three lamp materials of one traffic light."""

    var signal_id: SignalId
    var red: MaterialId
    var yellow: MaterialId
    var green: MaterialId


def _local(prop: SignalProp) -> Matrix4:
    """Return the three.js matrix that stands a prop at its foot, with its
    local x along its facing."""
    var yaw = Angle(atan2(prop.facing.y, prop.facing.x), RADIAN)
    return CarlaTransform(
        Length(prop.foot.x, METER),
        Length(prop.foot.y, METER),
        Length(prop.foot.z, METER),
        CarlaRotation(Angle(0, DEGREE), yaw, Angle(0, DEGREE)),
    ).three_matrix()


def _moved(
    var g: BufferGeometry, x: Float32, y: Float32, z: Float32, pose: Matrix4
) raises -> BufferGeometry:
    """Return a part moved to its place on a prop and then to the prop's."""
    g.translate(Length(x, METER), Length(y, METER), Length(z, METER))
    g.apply_matrix4(pose)
    return g.to_non_indexed()


def _disc(radius: Float32, sides: Int, turn: Angle) raises -> BufferGeometry:
    """Return a thin plate facing plus x: a disc, octagon or triangle."""
    var g = cylinder(
        Length(radius, METER),
        Length(radius, METER),
        Length(0.025, METER),
        sides,
        1,
        False,
        turn,
    )
    g.rotate_z(Angle(90, DEGREE))
    return g^


struct Props(Movable):
    """The traffic lights and signs of a map, in a scene."""

    var props: List[SignalProp]
    var lamps: List[LampSet]
    # The semantic tag of each mesh the props added, in order.
    var tags: List[SemanticTag]

    def __init__(
        out self, map: Map, mut scene: Scene, mut assets: Assets
    ) raises:
        """Build a map's props into a scene, every lamp off.

        Args:
            map: The map.
            scene: The scene; one node and the meshes are added.
            assets: The stores; the geometry and materials are added.

        Raises:
            Error: If a part cannot be made.
        """
        self.props = signal_props(map)
        self.lamps = List[LampSet]()
        self.tags = List[SemanticTag]()
        var metal = assets.materials.add(
            standard_material(
                Color(96, 100, 100),
                roughness=0.4,
                metalness=0.8,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        var housing = assets.materials.add(
            standard_material(
                Color(34, 36, 34), roughness=0.5, env_map=SCENE_ENVIRONMENT
            )
        )
        var red = assets.materials.add(
            standard_material(
                Color(190, 24, 24), roughness=0.35, env_map=SCENE_ENVIRONMENT
            )
        )
        var white = assets.materials.add(
            standard_material(
                Color(236, 236, 232), roughness=0.35, env_map=SCENE_ENVIRONMENT
            )
        )
        var node = scene.add(Object3D())
        var poles = List[BufferGeometry]()
        var boxes = List[BufferGeometry]()
        var reds = List[BufferGeometry]()
        var whites = List[BufferGeometry]()
        for prop in self.props:
            var pose = _local(prop)
            var h = prop.height.to(METER)
            if prop.kind == TRAFFIC_LIGHT_PROP:
                var top = ARM_HEIGHT.to(METER)
                poles.append(
                    _moved(
                        cylinder(
                            Length(0.09, METER),
                            Length(0.12, METER),
                            Length(top + 0.2, METER),
                            12,
                        ),
                        0,
                        (top + 0.2) / 2,
                        0,
                        pose,
                    )
                )
                # The arm runs along local z, toward the road.
                var side = Float32(1) if (
                    prop.facing.x * prop.inward.y
                    - prop.facing.y * prop.inward.x
                ) > 0 else Float32(-1)
                var reach = prop.reach.to(METER)
                var heads: List[Tuple[Float32, Float32]] = [
                    (h, Float32(0.2) * side)
                ]
                if reach > 0:
                    poles.append(
                        _moved(
                            box(
                                Length(0.12, METER),
                                Length(0.12, METER),
                                Length(reach, METER),
                            ),
                            0,
                            top,
                            side * reach / 2,
                            pose,
                        )
                    )
                    heads.append((top - Float32(0.55), side * reach))
                var set = LampSet(
                    prop.signal_id,
                    _lamp(assets, Color(70, 8, 6), Color(255, 36, 20)),
                    _lamp(assets, Color(70, 50, 6), Color(255, 170, 20)),
                    _lamp(assets, Color(6, 60, 30), Color(40, 255, 130)),
                )
                # A light has at least the head on its pole.
                for head in heads:  # pragma: no branch
                    var y = head[0]
                    var z = head[1]
                    boxes.append(
                        _moved(
                            rounded_box(
                                Length(0.3, METER),
                                Length(0.98, METER),
                                Length(0.36, METER),
                                2,
                                Length(0.04, METER),
                            ),
                            0,
                            y,
                            z,
                            pose,
                        )
                    )
                    # Three lamps.
                    for k in range(3):  # pragma: no branch
                        var ly = y + LAMP_PITCH * Float32(1 - k)
                        boxes.append(
                            _moved(
                                box(
                                    Length(0.16, METER),
                                    Length(0.025, METER),
                                    Length(0.26, METER),
                                ),
                                0.2,
                                ly + 0.13,
                                z,
                                pose,
                            )
                        )
                    var lamps: List[MaterialId] = [
                        set.red,
                        set.yellow,
                        set.green,
                    ]
                    # Three lamps.
                    for k in range(3):  # pragma: no branch
                        var ly = y + LAMP_PITCH * Float32(1 - k)
                        self.tags.append(TRAFFIC_LIGHT)
                        scene.add_mesh(
                            Mesh(
                                assets.geometries.add(
                                    _moved(
                                        _disc(0.105, 20, Angle(0, DEGREE)),
                                        0.155,
                                        ly,
                                        z,
                                        pose,
                                    )
                                ),
                                lamps[k],
                                node,
                            )
                        )
                self.lamps.append(set^)
            else:
                poles.append(
                    _moved(
                        cylinder(
                            Length(0.04, METER),
                            Length(0.04, METER),
                            Length(h + 0.3, METER),
                            8,
                        ),
                        -0.05,
                        (h + 0.3) / 2,
                        0,
                        pose,
                    )
                )
                var sides = 8 if prop.kind == STOP_PROP else (
                    3 if prop.kind == YIELD_PROP else 28
                )
                var turn = Angle(
                    22.5, DEGREE
                ) if prop.kind == STOP_PROP else Angle(0, DEGREE)
                var outer = Float32(
                    0.42
                ) if prop.kind == YIELD_PROP else Float32(0.38)
                var inner = Float32(
                    0.3
                ) if prop.kind == YIELD_PROP else Float32(0.34)
                var face = _disc(outer, sides, turn)
                var core = _disc(inner, sides, turn)
                if prop.kind == YIELD_PROP:
                    face.rotate_x(Angle(180, DEGREE))
                    core.rotate_x(Angle(180, DEGREE))
                if prop.kind == STOP_PROP:
                    whites.append(_moved(face^, 0, h, 0, pose))
                    reds.append(_moved(core^, 0.012, h, 0, pose))
                else:
                    reds.append(_moved(face^, 0, h, 0, pose))
                    whites.append(_moved(core^, 0.012, h, 0, pose))
        _add_merged(scene, assets, poles, metal, node, self.tags, POLE)
        _add_merged(
            scene, assets, boxes, housing, node, self.tags, TRAFFIC_LIGHT
        )
        _add_merged(scene, assets, reds, red, node, self.tags, TRAFFIC_SIGN)
        _add_merged(scene, assets, whites, white, node, self.tags, TRAFFIC_SIGN)
        scene.update()

    def set_state(
        self, mut assets: Assets, signal: SignalId, state: TrafficLightState
    ) raises:
        """Light the lamp of a traffic light's state.

        Args:
            assets: The stores; the light's three lamp materials change.
            signal: The light's signal.
            state: Its state.

        Raises:
            Error: If no traffic light stands at that signal.
        """
        for set in self.lamps:
            if set.signal_id == signal:
                var pairs: List[Tuple[MaterialId, TrafficLightState]] = [
                    (set.red, RED),
                    (set.yellow, YELLOW),
                    (set.green, GREEN),
                ]
                # Three lamps.
                for pair in pairs:  # pragma: no branch
                    var lamp = assets.materials.get(pair[0])
                    lamp.emissive_intensity = LAMP_GLOW * lamp_intensity(
                        state, pair[1]
                    )
                    assets.materials.materials[pair[0].value] = lamp
                return
        raise Error("No traffic light stands at signal " + signal.value)

    def set_states(self, mut assets: Assets, world: World) raises:
        """Light every traffic light as the world's light for its signal
        is.

        A light with no light in the world stays as it is.

        Args:
            assets: The stores; the lamp materials change.
            world: The world.

        Raises:
            Error: If the world refuses a light.
        """
        for set in self.lamps:
            var actor = world.get_traffic_light_from_opendrive(set.signal_id)
            if Bool(actor):
                self.set_state(
                    assets,
                    set.signal_id,
                    world.get_traffic_light_state_of(actor.value()),
                )


def _add_merged(
    mut scene: Scene,
    mut assets: Assets,
    parts: List[BufferGeometry],
    material: MaterialId,
    node: NodeId,
    mut tags: List[SemanticTag],
    tag: SemanticTag,
) raises:
    """Add the parts that wear one material as one mesh, if there are any,
    and remember its tag."""
    if len(parts) == 0:
        return
    tags.append(tag)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(merge_geometries(parts)),
            material,
            node,
            cast_shadow=True,
            receive_shadow=True,
        )
    )


def _lamp(mut assets: Assets, glass: Color, glow: Color) raises -> MaterialId:
    """Add one lamp's material, dark glass that glows, off to begin with."""
    return assets.materials.add(
        standard_material(
            glass,
            roughness=0.15,
            emissive=glow,
            emissive_intensity=0,
            env_map=SCENE_ENVIRONMENT,
        )
    )
