# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's V2X sensors: cooperative awareness messages, the radio channel,
and custom messages.

The sources are CARLA's simulator plugin, `Carla/Sensor/V2XSensor.cpp`,
`CustomV2XSensor.cpp`, `V2X/CaService.cpp` and `V2X/PathLossModel.cpp`,
and `LibCarla/source/carla/sensor/data/LibITS.h`, `V2XData.h` and
`rpc/CustomV2XBytes.h`.

**The channel, `PathLossModel`.** A receiver hears a sender that is
closer than `filter_distance`. The heights of both antennas count from
the lower of the two. A line from the receiver to the sender finds what
is between them: nothing is line of sight (LOS), a vehicle is a vehicle
in the way (NLOSv), and anything else is a building in the way (NLOSb).
The loss is then:

- WINNER+ (ETSI TR 103 257-1): 36.85 + 30 log10 d + 18.9 log10 f for
  NLOSb; 32.4 + 20 log10 d + 20 log10 f on a highway and 38.77 + 16.7
  log10 d + 18.2 log10 f elsewhere, for LOS and NLOSv, with f in GHz.
- Geometric: the full two-ray ground reflection for LOS, the log-distance
  loss from the free-space loss at `d_ref` for NLOSb, and the free-space
  loss for NLOSv.
- For NLOSv, both add the largest knife-edge loss of the vehicles in the
  way. A vehicle's edge is 2 cm above its roof.
- Both add a normal shadow fading: ETSI's deviation for the path state
  and the scenario, or `custom_fading_stddev`.

The received power is the sender's power plus `combined_antenna_gain`
minus the loss. A message is received when that is at least
`receiver_sensitivity`. A distance under `d_ref` counts as `d_ref`.

**Cooperative awareness, `CaService`.** A vehicle sends a CAM when
`gen_cam_min` has passed since the last one and its heading changed by
more than 4 degrees, it moved more than 4 m, or its speed changed by
more than 0.5 m/s; or when `gen_cam` has passed. With `fixed_rate` it
sends each tick after `gen_cam_min`. A roadside unit, a sensor without a
vehicle parent, sends every 0.5 s. The message holds the station, its
reference position from the map's projection with GNSS noise, and for a
vehicle its heading, speed, size, accelerations and yaw rate, with
CARLA's noise and ETSI's units. A low-frequency container with the
vehicle's role and exterior lights follows every 0.5 s.

**Differences from CARLA.**

- The generation time counts from `generation_delta0`, milliseconds
  since 2004 that the caller gives. CARLA reads the wall clock.
- The line from receiver to sender passes through the two sensors'
  parents, so that a vehicle does not block its own antenna.
- The multi-hit line is a ray cast again past each hit.
- The senders are heard in the order of their actor ids. CARLA keeps
  them in a map ordered by address.
- A CAM's vehicle length and width are CARLA's: the box in centimeters,
  times ten.
"""

from extensions.carla.actor import (
    ActorId,
    NO_ACTOR,
    VEHICLE_ACTOR,
)
from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.geo import GeoProjection
from extensions.carla.imu import (
    Accelerometer,
    compass,
)
from extensions.carla.physics.body import BodyId
from extensions.carla.sensor import (
    BICYCLE,
    BUILDING,
    BUS,
    CAR,
    FENCE,
    MOTORCYCLE,
    PEDESTRIAN,
    POLE,
    SemanticTag,
    TRAFFIC_LIGHT,
    TRAFFIC_SIGN,
    TRAIN,
    TRUCK,
    UNLABELED,
    WALL,
)
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
    attribute_string,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.transform import CarlaTransform
from extensions.carla.vehicle import (
    LIGHT_FOG,
    LIGHT_HIGH_BEAM,
    LIGHT_LEFT_BLINKER,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    LIGHT_REVERSE,
    LIGHT_RIGHT_BLINKER,
)
from extensions.carla.world import World
from math.vector3 import Vector3
from std.math import (
    acos,
    cos,
    log10,
    pi,
    sin,
    sqrt,
)
from units.si import (
    RADIAN,
    Acceleration,
    Duration,
    Length,
    METER,
)

comptime SPEED_OF_LIGHT = 299792458.0
# The relative permittivity of the ground, for the two-ray model.
comptime _EPSILON_R = 1.02
comptime _FLOAT_MAX = Float32(3.4028234663852886e38)
# How far past a hit the multi-hit line starts again, in meters.
comptime _PAST_HIT = Float32(1e-3)
comptime _MAX_HITS = 64
# The height of a vehicle's knife edge above its roof, in meters.
comptime _ROOF_EDGE = 0.02
# CARLA's `Math::ToDegrees<float>` factor.
comptime _TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)


# --- kinds -------------------------------------------------------------------


@fieldwise_init
struct PathState(Equatable, ImplicitlyCopyable, Writable):
    """What lies between a sender and a receiver, `EPathState`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for LOS, NLOSb or NLOSv.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime LOS = PathState(0)
comptime NLOS_BUILDING = PathState(1)
comptime NLOS_VEHICLE = PathState(2)


@fieldwise_init
struct PathLossKind(Equatable, ImplicitlyCopyable, Writable):
    """Which loss model a sensor uses, `EPathLossModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for WINNER+ or geometric.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1


comptime WINNER = PathLossKind(0)
comptime GEOMETRIC = PathLossKind(1)


@fieldwise_init
struct Scenario(Equatable, ImplicitlyCopyable, Writable):
    """Where the radio works, `EScenario`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for highway, rural or urban.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime HIGHWAY = Scenario(0)
comptime RURAL = Scenario(1)
comptime URBAN = Scenario(2)


# --- the channel -----------------------------------------------------------------


struct PropagationParams(ImplicitlyCopyable):
    """A radio's settings, `SetPropagationParams`, with CARLA's defaults."""

    # In dBm.
    var transmit_power: Float32
    var receiver_sensitivity: Float32
    var frequency_ghz: Float32
    # In dBi.
    var combined_antenna_gain: Float32
    var path_loss_exponent: Float32
    var reference_distance: Length
    var filter_distance: Length
    var use_etsi_fading: Bool
    # In dB.
    var custom_fading_stddev: Float32
    var scenario: Scenario
    var model: PathLossKind

    def __init__(out self):
        """Create CARLA's defaults: 21.5 dBm, -99 dBm, 5.9 GHz, 10 dBi,
        2.7, 1 m, 500 m, ETSI fading, urban, geometric."""
        self.transmit_power = 21.5
        self.receiver_sensitivity = -99.0
        self.frequency_ghz = 5.9
        self.combined_antenna_gain = 10.0
        self.path_loss_exponent = 2.7
        self.reference_distance = Length(1.0, METER)
        self.filter_distance = Length(500.0, METER)
        self.use_etsi_fading = True
        self.custom_fading_stddev = 0
        self.scenario = URBAN
        self.model = GEOMETRIC

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> PropagationParams:
        """Read the settings from an actor's attributes, `SetV2X`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The settings. "urban" and "rural" pick those scenarios, and any
            other text the highway. "winner" and "geometric" pick a model;
            other text keeps the geometric model.

        Raises:
            Error: Never for these inputs; the number reader's error is
                passed on.
        """
        var p = PropagationParams()
        p.transmit_power = attribute_float(attributes, "transmit_power", 21.5)
        p.receiver_sensitivity = attribute_float(
            attributes, "receiver_sensitivity", -99.0
        )
        p.frequency_ghz = attribute_float(attributes, "frequency_ghz", 5.9)
        p.combined_antenna_gain = attribute_float(
            attributes, "combined_antenna_gain", 10.0
        )
        p.path_loss_exponent = attribute_float(
            attributes, "path_loss_exponent", 2.7
        )
        p.reference_distance = Length(
            attribute_float(attributes, "d_ref", 1.0), METER
        )
        p.filter_distance = Length(
            attribute_float(attributes, "filter_distance", 500.0), METER
        )
        p.use_etsi_fading = attribute_bool(attributes, "use_etsi_fading", True)
        p.custom_fading_stddev = attribute_float(
            attributes, "custom_fading_stddev", 0
        )
        var scenario = attribute_string(attributes, "scenario", "urban")
        if scenario == "urban":
            p.scenario = URBAN
        elif scenario == "rural":
            p.scenario = RURAL
        else:
            p.scenario = HIGHWAY
        var model = attribute_string(attributes, "path_loss_model", "geometric")
        if model == "winner":
            p.model = WINNER
        return p


@fieldwise_init
struct ReceivedPower(ImplicitlyCopyable):
    """A sender a receiver hears, and how strongly."""

    var sender: ActorId
    # In dBm.
    var power: Float32


def _state_index(state: PathState) raises -> Int:
    if not state.is_valid():
        raise Error("A path state must be LOS, NLOSb or NLOSv")
    return state.value


struct PathLossModel(ImplicitlyCopyable):
    """The radio channel of one V2X sensor, `PathLossModel`."""

    var params: PropagationParams
    # In Hz and meters.
    var frequency: Float64
    var wavelength: Float64
    # The free-space loss at the reference distance, in dB.
    var fspl_d0: Float32

    def __init__(out self, params: PropagationParams) raises:
        """Set the parameters, `SetParams`, and the loss at `d_ref`.

        Args:
            params: The settings.

        Raises:
            Error: If the scenario or the model is not valid, or the
                frequency or the reference distance is not positive.
        """
        if not (params.scenario.is_valid() and params.model.is_valid()):
            raise Error("A V2X scenario and loss model must be valid")
        if not (
            params.frequency_ghz > 0 and params.reference_distance.value > 0
        ):
            raise Error(
                "A V2X frequency and reference distance must be positive"
            )
        self.params = params
        self.frequency = Float64(params.frequency_ghz) * 1e9
        self.wavelength = SPEED_OF_LIGHT / self.frequency
        self.fspl_d0 = Float32(
            20.0 * log10(Float64(params.reference_distance.value))
            + 20.0 * log10(self.frequency)
            + 20.0 * log10(4.0 * pi / SPEED_OF_LIGHT)
        )

    def winner(self, state: PathState, distance: Float64) raises -> Float32:
        """Return the WINNER+ loss, `CalculatePathLoss_WINNER`.

        Args:
            state: The path state.
            distance: The distance, in meters.

        Returns:
            The loss, in dB.

        Raises:
            Error: If the state is not valid.
        """
        var f = Float64(self.params.frequency_ghz)
        if _state_index(state) == 1:
            return Float32(
                Float64(Float32(36.85))
                + Float64(Float32(30.0)) * log10(distance)
                + Float64(Float32(18.9)) * log10(f)
            )
        if self.params.scenario == HIGHWAY:
            return Float32(
                Float64(Float32(32.4))
                + Float64(Float32(20.0)) * log10(distance)
                + Float64(Float32(20.0)) * log10(f)
            )
        return Float32(
            Float64(Float32(38.77))
            + Float64(Float32(16.7)) * log10(distance)
            + Float64(Float32(18.2)) * log10(f)
        )

    def two_ray(self, distance: Float64, tx: Float64, rx: Float64) -> Float64:
        """Return the full two-ray ground reflection loss,
        `CalculateTwoRayPathLoss`.

        Args:
            distance: The line-of-sight distance, in meters.
            tx: The sender's antenna height, in meters.
            rx: The receiver's antenna height, in meters.

        Returns:
            The loss, in dB.
        """
        var ground = sqrt(distance * distance - (tx - rx) * (tx - rx))
        var reflected = sqrt(distance * distance + 4.0 * tx * rx)
        var sin_theta = (tx + rx) / reflected
        var cos_theta = ground / reflected
        var root = sqrt(_EPSILON_R - cos_theta * cos_theta)
        var gamma = (sin_theta - root) / (sin_theta + root)
        var phi = 2.0 * pi / self.wavelength * (distance - reflected)
        return 20 * log10(
            4.0
            * pi
            * ground
            / self.wavelength
            * 1.0
            / sqrt(
                (1 + gamma * cos(phi)) * (1 + gamma * cos(phi))
                + gamma * gamma * sin(phi) * sin(phi)
            )
        )

    def two_ray_simple(
        self, distance: Float64, tx: Float64, rx: Float64
    ) -> Float32:
        """Return the far-field two-ray loss, `CalculateTwoRayPathLossSimple`.

        Args:
            distance: The distance, in meters.
            tx: The sender's antenna height, in meters.
            rx: The receiver's antenna height, in meters.

        Returns:
            40 log10 d - 10 log10 (tx^2 rx^2), in dB.
        """
        return Float32(40 * log10(distance) - 10 * log10(tx * tx * rx * rx))

    def vehicle_loss(self, d1: Float64, d2: Float64, h: Float64) -> Float64:
        """Return one knife edge's loss, `CalcVehicleLoss`.

        Args:
            d1: From the sender to the edge, on the ground, in meters.
            d2: From the edge to the receiver, in meters.
            h: The edge's height above the reference, in meters.

        Returns:
            6.9 + 20 log10(sqrt((v - 0.1)^2 + 1) + v - 0.1) for a
            Fresnel-Kirchhoff parameter v of at least -0.78, else zero.
        """
        var v = h * sqrt(2.0 * (d1 + d2) / (self.wavelength * d1 * d2))
        if v >= -0.78:
            var t = (v - 0.1) * (v - 0.1)
            return 6.9 + 20.0 * log10(sqrt(t + 1.0) + v - 0.1)
        return 0.0

    def nlos_vehicle_loss(
        self, source: Vector3, destination: Vector3, obstacles: List[Vector3]
    ) -> Float64:
        """Return the largest knife-edge loss, `CalculateNLOSvLoss`.

        Args:
            source: The receiver, in meters.
            destination: The sender, in meters.
            obstacles: Each vehicle's edge: x and y in meters, z the height
                above the reference.

        Returns:
            The largest loss, in dB, and at least zero.
        """
        var best = 0.0
        for o in obstacles:
            var d1 = sqrt(
                Float64(o.x - source.x) ** 2 + Float64(o.y - source.y) ** 2
            )
            var d2 = sqrt(
                Float64(destination.x - o.x) ** 2
                + Float64(destination.y - o.y) ** 2
            )
            var loss = self.vehicle_loss(d1, d2, Float64(o.z))
            if loss >= best:
                best = loss
        return best

    def fading_stddev(self, state: PathState) raises -> Float32:
        """Return the shadow fading's deviation, ETSI TR 103 257-1 Table 6.

        Args:
            state: The path state.

        Returns:
            In dB: LOS 3.3, 4.25 and 5.2; NLOSb 6.8; NLOSv 3.8, 4.55 and
            5.3, for a highway, rural and urban scenario. Or
            `custom_fading_stddev` without ETSI fading.

        Raises:
            Error: If the state is not valid.
        """
        var i = _state_index(state)
        if not self.params.use_etsi_fading:
            return self.params.custom_fading_stddev
        if i == 1:
            return 6.8
        var s = self.params.scenario
        if i == 0:
            return Float32(3.3) if s == HIGHWAY else (
                Float32(4.25) if s == RURAL else Float32(5.2)
            )
        return Float32(3.8) if s == HIGHWAY else (
            Float32(4.55) if s == RURAL else Float32(5.3)
        )

    def loss(
        self,
        state: PathState,
        source: Vector3,
        destination: Vector3,
        distance: Float64,
        tx: Float64,
        rx: Float64,
        obstacles: List[Vector3],
        mut rng: SensorRandom,
    ) raises -> Float32:
        """Return the loss of one link, `ComputeLoss`.

        Args:
            state: The path state.
            source: The receiver, in meters.
            destination: The sender, in meters.
            distance: The distance, in meters, at least `d_ref`.
            tx: The receiver's antenna height over the reference, in meters.
            rx: The sender's, in meters.
            obstacles: The vehicle edges in the way.
            rng: The sensor's engine, for the fading.

        Returns:
            The path loss plus the shadow fading, in dB.

        Raises:
            Error: If the state is not valid.
        """
        var path: Float32
        if self.params.model == WINNER:
            path = self.winner(state, distance)
            if state == NLOS_VEHICLE:
                path = Float32(
                    Float64(path)
                    + self.nlos_vehicle_loss(source, destination, obstacles)
                )
        elif state == LOS:
            path = Float32(self.two_ray(distance, tx, rx))
        elif state == NLOS_BUILDING:
            path = Float32(
                Float64(self.fspl_d0)
                + 10.0
                * Float64(self.params.path_loss_exponent)
                * log10(
                    distance / Float64(self.params.reference_distance.value)
                )
            )
        else:
            var free = 20.0 * log10(distance) + 20.0 * log10(
                4.0 * pi / self.wavelength
            )
            path = Float32(
                free + self.nlos_vehicle_loss(source, destination, obstacles)
            )
        return path + rng.normal(0, self.fading_stddev(state))

    def received_power(
        self, sender_power: Float32, loss: Float32
    ) -> Optional[Float32]:
        """Return what a receiver gets, `CalculateReceivedPower`.

        Args:
            sender_power: The sender's transmit power, in dBm.
            loss: The link's loss, in dB.

        Returns:
            The power plus the antenna gain minus the loss, or None below
            the receiver's sensitivity.
        """
        var power = sender_power + self.params.combined_antenna_gain - loss
        if power >= self.params.receiver_sensitivity:
            return power
        return None


def _actor_of(world: World, body: BodyId) -> Int:
    # The spectator is always in the list.
    for i in range(len(world.actors)):  # pragma: no branch
        if world.actors[i].is_alive() and world.actors[i].body == body:
            return i
    return -1


def _parent_body(world: World, sensor: ActorId) raises -> BodyId:
    var parent = world.actor(sensor).parent
    if parent == NO_ACTOR:
        return BodyId(-1)
    return world.actor(parent).body


def path_state(
    world: World,
    receiver: ActorId,
    sender: ActorId,
    reference_z: Float32,
) raises -> Tuple[PathState, List[Vector3]]:
    """Find what lies between two sensors,
    `EstimatePathStateAndVehicleObstacles`.

    Args:
        world: The world.
        receiver: The receiving sensor.
        sender: The sending sensor.
        reference_z: The lower antenna's z, in meters.

    Returns:
        The state, and each vehicle's knife edge up to the first building.

    Raises:
        Error: If a sensor is not alive.
    """
    var a = world.get_location(receiver)
    var b = world.get_location(sender)
    var skip = [_parent_body(world, receiver), _parent_body(world, sender)]
    var toward = b - a
    var remaining = toward.length()
    var obstacles = List[Vector3]()
    if not (remaining > 0):
        return (LOS, obstacles^)
    var unit = toward / remaining
    var origin = a
    var last = BodyId(-1)
    # The hit limit is a positive constant.
    for _ in range(_MAX_HITS):  # pragma: no branch
        var found = world.physics.world.raycast(
            origin, unit, Length(remaining, METER), last
        )
        if not Bool(found):
            break
        var h = found.value()
        remaining -= h.distance + _PAST_HIT
        origin = h.point + unit * _PAST_HIT
        last = h.body
        if h.body in skip:
            continue
        var i = _actor_of(world, h.body)
        if i >= 0 and world.actors[i].kind == VEHICLE_ACTOR:
            ref v = world.actors[i]
            var at = world.get_location(v.id)
            obstacles.append(
                Vector3(
                    at.x,
                    at.y,
                    Float32(
                        Float64(at.z - reference_z)
                        + Float64(v.bounding_box.extent.z) * 2.0
                        + _ROOF_EDGE
                    ),
                )
            )
            continue
        return (NLOS_BUILDING, obstacles^)
    if len(obstacles) > 0:
        return (NLOS_VEHICLE, obstacles^)
    return (LOS, obstacles^)


def simulate_channel(
    world: World,
    model: PathLossModel,
    receiver: ActorId,
    senders: List[ActorId],
    powers: List[Float32],
    mut rng: SensorRandom,
) raises -> List[ReceivedPower]:
    """Work out which senders a receiver hears, `PathLossModel::Simulate`.

    Args:
        world: The world.
        model: The receiver's channel.
        receiver: The receiving sensor.
        senders: The sending sensors, other than the receiver.
        powers: Each sender's transmit power, in dBm.
        rng: The receiver's engine, for the fading.

    Returns:
        The senders heard, with the power of each.

    Raises:
        Error: If the lists differ in length, or the receiver is not alive.
    """
    if len(senders) != len(powers):
        raise Error("A V2X channel needs one power a sender")
    var here = world.get_location(receiver)
    var out = List[ReceivedPower]()
    for k in range(len(senders)):
        if not world.is_alive(senders[k]):
            continue
        var there = world.get_location(senders[k])
        var reference = min(here.z, there.z)
        var tx = Float64(here.z - reference)
        var rx = Float64(there.z - reference)
        var distance = Float64((there - here).length())
        if not (distance < Float64(model.params.filter_distance.value)):
            continue
        distance = max(distance, Float64(model.params.reference_distance.value))
        var found = path_state(world, receiver, senders[k], reference)
        var loss = model.loss(
            found[0], here, there, distance, tx, rx, found[1], rng
        )
        var power = model.received_power(powers[k], loss)
        if Bool(power):
            out.append(ReceivedPower(senders[k], power.value()))
    return out^


# --- cooperative awareness messages ------------------------------------------------


@fieldwise_init
struct StationType(Equatable, ImplicitlyCopyable, Writable):
    """An ITS station's type, ETSI's `StationType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for 0 to 11 or 15, a roadside unit.

        Returns:
            Whether ETSI names the value.
        """
        return (self.value >= 0 and self.value <= 11) or self.value == 15


comptime STATION_UNKNOWN = StationType(0)
comptime STATION_PEDESTRIAN = StationType(1)
comptime STATION_CYCLIST = StationType(2)
comptime STATION_MOPED = StationType(3)
comptime STATION_MOTORCYCLE = StationType(4)
comptime STATION_PASSENGER_CAR = StationType(5)
comptime STATION_BUS = StationType(6)
comptime STATION_LIGHT_TRUCK = StationType(7)
comptime STATION_HEAVY_TRUCK = StationType(8)
comptime STATION_TRAILER = StationType(9)
comptime STATION_SPECIAL_VEHICLES = StationType(10)
comptime STATION_TRAM = StationType(11)
comptime STATION_ROAD_SIDE_UNIT = StationType(15)


@fieldwise_init
struct MessageId(Equatable, ImplicitlyCopyable, Writable):
    """An ITS message's id, ETSI's `messageID`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for custom, DENM, CAM and the others to EV-RSR.

        Returns:
            Whether the value is from 0 to 7.
        """
        return self.value >= 0 and self.value <= 7


comptime MESSAGE_CUSTOM = MessageId(0)
comptime MESSAGE_CAM = MessageId(2)


@fieldwise_init
struct VehicleRole(Equatable, ImplicitlyCopyable, Writable):
    """A vehicle's role, ETSI's `VehicleRole`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the default role to the third reserved one.

        Returns:
            Whether the value is from 0 to 15.
        """
        return self.value >= 0 and self.value <= 15


comptime ROLE_DEFAULT = VehicleRole(0)
comptime ROLE_PUBLIC_TRANSPORT = VehicleRole(1)
comptime ROLE_EMERGENCY = VehicleRole(6)


@fieldwise_init
struct ContainerKind(Equatable, ImplicitlyCopyable, Writable):
    """Which container a CAM holds, `HighFrequencyContainer_PR` and
    `LowFrequencyContainer_PR`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for none, the vehicle's or the roadside unit's.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime CONTAINER_NOTHING = ContainerKind(0)
# The basic vehicle container, high or low frequency.
comptime CONTAINER_VEHICLE = ContainerKind(1)
# The roadside unit's high-frequency container.
comptime CONTAINER_RSU = ContainerKind(2)

# ETSI's "unavailable" values and the confidences CARLA writes.
comptime SEMI_AXIS_UNAVAILABLE = 4095
comptime HEADING_UNAVAILABLE = 3601
comptime ALTITUDE_CONFIDENCE_UNAVAILABLE = 15
comptime HEADING_CONFIDENCE_ONE_DEGREE = 10
comptime SPEED_UNAVAILABLE = 16383
comptime SPEED_CONFIDENCE = 3
comptime VEHICLE_LENGTH_CONFIDENCE_UNAVAILABLE = 4
comptime ACCELERATION_UNAVAILABLE = 161
comptime ACCELERATION_CONFIDENCE_UNAVAILABLE = 102
comptime CURVATURE_UNAVAILABLE = 30001
comptime CURVATURE_CONFIDENCE_UNAVAILABLE = 7
comptime CURVATURE_YAW_RATE_USED = 0
comptime YAW_RATE_UNAVAILABLE = 32767
comptime YAW_RATE_CONFIDENCE_UNAVAILABLE = 8
comptime DRIVE_FORWARD = 0
comptime DRIVE_BACKWARD = 1
# A roadside unit's protected zones, as CARLA fills them.
comptime RSU_ZONE_COUNT = 16
comptime RSU_ZONE_LATITUDE = 50
comptime RSU_ZONE_LONGITUDE = 50


@fieldwise_init
struct ItsPduHeader(Equatable, ImplicitlyCopyable, Writable):
    """An ITS message's header, `ItsPduHeader`."""

    var protocol_version: Int
    var message_id: MessageId
    var station_id: Int


@fieldwise_init
struct ReferencePosition(Equatable, ImplicitlyCopyable, Writable):
    """Where a station is, `ReferencePosition`, in ETSI units."""

    # In tenths of a microdegree.
    var latitude: Int
    var longitude: Int
    var semi_major_confidence: Int
    var semi_minor_confidence: Int
    var semi_major_orientation: Int
    # In centimeters.
    var altitude: Int
    var altitude_confidence: Int


@fieldwise_init
struct HighFrequencyContainer(Equatable, ImplicitlyCopyable, Writable):
    """A CAM's high-frequency container, in ETSI units."""

    var present: ContainerKind
    # In tenths of a degree from north.
    var heading: Int
    var heading_confidence: Int
    # In cm/s.
    var speed: Int
    var speed_confidence: Int
    var drive_direction: Int
    # CARLA's units: the box in centimeters, times ten.
    var vehicle_length: Int
    var vehicle_length_confidence: Int
    var vehicle_width: Int
    # In tenths of a m/s^2.
    var longitudinal_acceleration: Int
    var acceleration_confidence: Int
    var curvature: Int
    var curvature_confidence: Int
    var curvature_calculation_mode: Int
    # In hundredths of a degree a second.
    var yaw_rate: Int
    var yaw_rate_confidence: Int
    var lateral_acceleration_available: Bool
    var lateral_acceleration: Int
    var vertical_acceleration_available: Bool
    var vertical_acceleration: Int
    # A roadside unit's protected zones.
    var protected_zone_count: Int

    @staticmethod
    def nothing() -> HighFrequencyContainer:
        """Return an empty container.

        Returns:
            A container that holds nothing, all zero.
        """
        return HighFrequencyContainer(
            CONTAINER_NOTHING,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            False,
            0,
            False,
            0,
            0,
        )


@fieldwise_init
struct LowFrequencyContainer(Equatable, ImplicitlyCopyable, Writable):
    """A CAM's low-frequency container."""

    var present: ContainerKind
    var vehicle_role: VehicleRole
    # ETSI's bits, the most significant first: low beam, high beam, left
    # turn, right turn, daytime, reverse, fog and parking lights.
    var exterior_lights: UInt8
    var path_points: Int


@fieldwise_init
struct CAM(Equatable, ImplicitlyCopyable, Writable):
    """A cooperative awareness message, ETSI's `CAM`."""

    var header: ItsPduHeader
    # Milliseconds modulo 65536.
    var generation_delta_time: Int
    var station_type: StationType
    var reference_position: ReferencePosition
    var high_frequency: HighFrequencyContainer
    var low_frequency: LowFrequencyContainer


def speed_value(speed: Float32) -> Int:
    """Return a speed in ETSI units, `BuildSpeedValue`.

    Args:
        speed: In m/s.

    Returns:
        16382 at 163.82 m/s or more, the speed in cm/s rounded from zero
        up, and 16383, unavailable, below zero.
    """
    if speed >= 163.82:
        return 16382
    if speed >= 0:
        return Int(round_half_away(Float64(speed) * 100.0))
    return SPEED_UNAVAILABLE


def round_half_away(x: Float64) -> Float64:
    """Round as C's `round` does.

    Args:
        x: The number.

    Returns:
        The nearest integer, halves away from zero.
    """
    if x < 0:
        return -Float64(Int(-x + 0.5))
    return Float64(Int(x + 0.5))


def station_type_of(tag: SemanticTag, special_type: String) -> StationType:
    """Return a vehicle's station type, `GetStationType`.

    Args:
        tag: The vehicle's semantic tag.
        special_type: Its `special_type` attribute.

    Returns:
        An emergency vehicle is a special vehicle. Otherwise a car is a
        passenger car, a truck a light truck, and so on; a building, wall,
        fence, pole, light or sign is a roadside unit; any other tag is
        unknown.
    """
    if special_type == "emergency":
        return STATION_SPECIAL_VEHICLES
    if tag == PEDESTRIAN:
        return STATION_PEDESTRIAN
    if tag == BICYCLE:
        return STATION_CYCLIST
    if tag == MOTORCYCLE:
        return STATION_MOTORCYCLE
    if tag == CAR:
        return STATION_PASSENGER_CAR
    if tag == BUS:
        return STATION_BUS
    if tag == TRUCK:
        return STATION_LIGHT_TRUCK
    if tag == TRAIN:
        return STATION_TRAM
    if (
        tag == BUILDING
        or tag == WALL
        or tag == FENCE
        or tag == POLE
        or tag == TRAFFIC_LIGHT
        or tag == TRAFFIC_SIGN
    ):
        return STATION_ROAD_SIDE_UNIT
    return STATION_UNKNOWN


def vehicle_role_of(station: StationType) -> VehicleRole:
    """Return the role a station type gives, `GetVehicleRole`.

    Args:
        station: The station type.

    Returns:
        Public transport for a bus or a tram, emergency for a special
        vehicle, and the default role otherwise.
    """
    if station == STATION_BUS or station == STATION_TRAM:
        return ROLE_PUBLIC_TRANSPORT
    if station == STATION_SPECIAL_VEHICLES:
        return ROLE_EMERGENCY
    return ROLE_DEFAULT


struct CamNoise(ImplicitlyCopyable):
    """The noise of the data a CAM carries, `SetGNSSDeviation` and the
    others."""

    # In degrees.
    var latitude_stddev: Float32
    var longitude_stddev: Float32
    var latitude_bias: Float32
    var longitude_bias: Float32
    # In meters.
    var altitude_stddev: Float32
    var altitude_bias: Float32
    # In degrees.
    var heading_stddev: Float32
    var heading_bias: Float32
    # In m/s.
    var velocity_stddev: Float32
    # In rad/s.
    var yaw_rate_stddev: Float32
    var yaw_rate_bias: Float32
    # In m/s^2.
    var acceleration_stddev: Vector3

    def __init__(out self):
        """Create no noise."""
        self.latitude_stddev = 0
        self.longitude_stddev = 0
        self.latitude_bias = 0
        self.longitude_bias = 0
        self.altitude_stddev = 0
        self.altitude_bias = 0
        self.heading_stddev = 0
        self.heading_bias = 0
        self.velocity_stddev = 0
        self.yaw_rate_stddev = 0
        self.yaw_rate_bias = 0
        self.acceleration_stddev = Vector3(0, 0, 0)

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> CamNoise:
        """Read the noise from an actor's attributes, `SetV2X`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The noise.

        Raises:
            Error: Never for these inputs; the number reader's error is
                passed on.
        """
        var n = CamNoise()
        n.latitude_stddev = attribute_float(attributes, "noise_lat_stddev", 0)
        n.longitude_stddev = attribute_float(attributes, "noise_lon_stddev", 0)
        n.altitude_stddev = attribute_float(attributes, "noise_alt_stddev", 0)
        n.heading_stddev = attribute_float(attributes, "noise_head_stddev", 0)
        n.latitude_bias = attribute_float(attributes, "noise_lat_bias", 0)
        n.longitude_bias = attribute_float(attributes, "noise_lon_bias", 0)
        n.altitude_bias = attribute_float(attributes, "noise_alt_bias", 0)
        n.heading_bias = attribute_float(attributes, "noise_head_bias", 0)
        n.velocity_stddev = attribute_float(attributes, "noise_vel_stddev_x", 0)
        n.yaw_rate_stddev = attribute_float(
            attributes, "noise_yawrate_stddev", 0
        )
        n.yaw_rate_bias = attribute_float(attributes, "noise_yawrate_bias", 0)
        n.acceleration_stddev = Vector3(
            attribute_float(attributes, "noise_accel_stddev_x", 0),
            attribute_float(attributes, "noise_accel_stddev_y", 0),
            attribute_float(attributes, "noise_accel_stddev_z", 0),
        )
        return n


# CARLA's CAM accelerometer adds a fixed gravity, not the world's.
comptime _CAM_GRAVITY = Acceleration(9.81)
comptime _LOW_FREQUENCY_INTERVAL = 0.5
comptime _RSU_INTERVAL = 0.5
comptime _LOW_DYNAMICS_LIMIT = 3


struct CaService(Copyable, Movable):
    """The CAM generator of one V2X sensor, `CaService`."""

    var owner: ActorId
    var vehicle: Bool
    var station_id: Int
    var station_type: StationType
    var gen_cam_min: Float32
    var gen_cam_max: Float32
    var gen_cam: Float32
    var fixed_rate: Bool
    var noise: CamNoise
    var generation_delta0: Int
    var last_cam_timestamp: Float32
    var last_low_cam_timestamp: Float32
    var elapsed: Float64
    var low_dynamics_counter: Int
    var vehicle_speed: Float32
    var vehicle_position: Vector3
    var vehicle_heading: Vector3
    var last_cam_speed: Float32
    var last_cam_position: Vector3
    var last_cam_heading: Vector3
    var accelerometer: Accelerometer

    def __init__(
        out self,
        world: World,
        owner: ActorId,
        gen_cam_min: Float32,
        gen_cam_max: Float32,
        fixed_rate: Bool,
        noise: CamNoise,
        generation_delta0: Int,
    ) raises:
        """Set the parameters and the owner, `SetParams` and `SetActor`.

        Args:
            world: The world.
            owner: The sensor's parent, or the sensor itself without one.
            gen_cam_min: The shortest gap between CAMs, in seconds.
            gen_cam_max: The longest, in seconds.
            fixed_rate: Whether to send each tick after `gen_cam_min`.
            noise: The noise of the data sent.
            generation_delta0: Milliseconds from 2004 to the start.

        Raises:
            Error: If the owner is not alive.
        """
        var record = world.actor(owner)
        self.owner = owner
        self.vehicle = record.kind == VEHICLE_ACTOR
        self.station_id = owner.value
        self.gen_cam_min = gen_cam_min
        self.gen_cam_max = gen_cam_max
        self.gen_cam = gen_cam_max
        self.fixed_rate = fixed_rate
        self.noise = noise
        self.generation_delta0 = generation_delta0
        self.elapsed = world.elapsed_seconds
        self.low_dynamics_counter = 0
        self.vehicle_speed = 0
        self.vehicle_position = Vector3(0, 0, 0)
        self.vehicle_heading = Vector3(0, 0, 0)
        self.last_cam_speed = 0
        self.last_cam_position = Vector3(0, 0, 0)
        self.last_cam_heading = Vector3(0, 0, 0)
        self.accelerometer = Accelerometer()
        var now = Float32(world.elapsed_seconds)
        if self.vehicle:
            self.last_cam_timestamp = now - gen_cam_max
            self.last_low_cam_timestamp = now - Float32(_LOW_FREQUENCY_INTERVAL)
            var special = String()
            # A vehicle's blueprint gives it attributes.
            for a in record.attributes:  # pragma: no branch
                if a.id == "special_type":
                    special = a.value
            var tag = UNLABELED
            if len(record.semantic_tags) > 0:
                tag = record.semantic_tags[0]
            self.station_type = station_type_of(tag, special)
        else:
            self.last_cam_timestamp = -Float32(_RSU_INTERVAL)
            self.last_low_cam_timestamp = 0
            self.station_type = STATION_ROAD_SIDE_UNIT

    def _forward_speed(self, world: World) raises -> Float32:
        var t = world.get_transform(self.owner)
        return world.get_velocity(self.owner).dot(t.rotation.forward_vector())

    def trigger(
        mut self,
        world: World,
        projection: GeoProjection,
        tick: Duration,
        mut rng: SensorRandom,
    ) raises -> Optional[CAM]:
        """Decide whether to send a CAM this tick, and make it, `Trigger`.

        Args:
            world: The world, before its physics steps.
            projection: The map's projection.
            tick: The time since the last tick.
            rng: The sensor's engine.

        Returns:
            The new CAM, or None.

        Raises:
            Error: If the owner is not alive.
        """
        self.elapsed = world.elapsed_seconds
        if self.station_type == STATION_ROAD_SIDE_UNIT:
            if self.elapsed - Float64(self.last_cam_timestamp) >= _RSU_INTERVAL:
                var cam = self._message(world, projection, tick, rng)
                self.last_cam_timestamp = Float32(self.elapsed)
                return cam
            return None
        var elapsed = Float32(self.elapsed - Float64(self.last_cam_timestamp))
        if not (elapsed >= self.gen_cam_min):
            return None
        if self.fixed_rate:
            return self._generate(world, projection, tick, rng)
        if (
            self._heading_changed(world)
            or self._moved(world)
            or self._speed_changed(world)
        ):
            var cam = self._generate(world, projection, tick, rng)
            self.gen_cam = min(elapsed, self.gen_cam_max)
            self.low_dynamics_counter = 0
            return cam
        if elapsed >= self.gen_cam:
            var cam = self._generate(world, projection, tick, rng)
            self.low_dynamics_counter += 1
            if self.low_dynamics_counter >= _LOW_DYNAMICS_LIMIT:
                self.gen_cam = self.gen_cam_max
            return cam
        return None

    def _heading_changed(mut self, world: World) raises -> Bool:
        self.vehicle_heading = world.get_transform(
            self.owner
        ).rotation.forward_vector()
        var a = self.last_cam_heading
        var b = self.vehicle_heading
        var angle = acos(
            Float64(a.dot(b)) / (Float64(a.length()) * Float64(b.length()))
        )
        return angle * 180.0 / pi > 4.0

    def _moved(mut self, world: World) raises -> Bool:
        self.vehicle_position = world.get_location(self.owner)
        return (self.vehicle_position - self.last_cam_position).length() > 4.0

    def _speed_changed(mut self, world: World) raises -> Bool:
        self.vehicle_speed = self._forward_speed(world)
        return abs(self.vehicle_speed - self.last_cam_speed) > 0.5

    def _generate(
        mut self,
        world: World,
        projection: GeoProjection,
        tick: Duration,
        mut rng: SensorRandom,
    ) raises -> CAM:
        var cam = self._message(world, projection, tick, rng)
        self.last_cam_position = self.vehicle_position
        self.last_cam_speed = self.vehicle_speed
        self.last_cam_heading = self.vehicle_heading
        self.last_cam_timestamp = Float32(self.elapsed)
        return cam

    def _message(
        mut self,
        world: World,
        projection: GeoProjection,
        tick: Duration,
        mut rng: SensorRandom,
    ) raises -> CAM:
        """`CreateCooperativeAwarenessMessage`."""
        var header = ItsPduHeader(2, MESSAGE_CAM, self.station_id)
        var delta = (
            self.generation_delta0 + Int(world.elapsed_seconds * 1000)
        ) % 65536
        var t = world.get_transform(self.owner)
        var geo = projection.transform_to_geo_location(t.location)
        var n = self.noise
        var lat_error = rng.normal(0, n.latitude_stddev)
        var lon_error = rng.normal(0, n.longitude_stddev)
        var alt_error = rng.normal(0, n.altitude_stddev)
        var latitude = (
            geo.latitude_degrees + Float64(n.latitude_bias) + Float64(lat_error)
        )
        var longitude = (
            geo.longitude_degrees
            + Float64(n.longitude_bias)
            + Float64(lon_error)
        )
        var altitude = (
            geo.altitude_meters + Float64(n.altitude_bias) + Float64(alt_error)
        )
        var position = ReferencePosition(
            Int(round_half_away(latitude * 1e6)) * 10,
            Int(round_half_away(longitude * 1e6)) * 10,
            SEMI_AXIS_UNAVAILABLE,
            SEMI_AXIS_UNAVAILABLE,
            HEADING_UNAVAILABLE,
            Int(round_half_away(altitude * 100.0)),
            ALTITUDE_CONFIDENCE_UNAVAILABLE,
        )
        var high = HighFrequencyContainer.nothing()
        var low = LowFrequencyContainer(CONTAINER_NOTHING, ROLE_DEFAULT, 0, 0)
        if self.station_type == STATION_ROAD_SIDE_UNIT:
            high.present = CONTAINER_RSU
            high.protected_zone_count = RSU_ZONE_COUNT
        elif (
            self.station_type != STATION_PEDESTRIAN
            and self.station_type != STATION_UNKNOWN
        ):
            high = self._vehicle_container(world, t, tick, rng)
            if (
                self.elapsed - Float64(self.last_low_cam_timestamp)
                >= _LOW_FREQUENCY_INTERVAL
            ):
                low = self._low_frequency(world)
                self.last_low_cam_timestamp = Float32(self.elapsed)
        return CAM(header, delta, self.station_type, position, high, low)

    def _vehicle_container(
        mut self,
        world: World,
        t: CarlaTransform,
        tick: Duration,
        mut rng: SensorRandom,
    ) raises -> HighFrequencyContainer:
        """`AddBasicVehicleContainerHighFrequency`."""
        var n = self.noise
        var heading_degrees = (
            compass(t.rotation.forward_vector()).to(RADIAN) * _TO_DEGREES
        )
        var heading = Float32(
            Float64(heading_degrees)
            + Float64(n.heading_bias)
            + Float64(rng.normal(0, n.heading_stddev))
        )
        var forward = self._forward_speed(world)
        var speed = max(forward + rng.normal(0, n.velocity_stddev), 0)
        var box = world.get_bounding_box(self.owner)
        var accel = self.accelerometer.step(
            t.location, tick, _CAM_GRAVITY, t.rotation
        )
        accel = Vector3(
            accel.x + rng.normal(0, n.acceleration_stddev.x),
            accel.y + rng.normal(0, n.acceleration_stddev.y),
            accel.z + rng.normal(0, n.acceleration_stddev.z),
        )
        # The owner's rotation in its root's relative transform is its
        # world rotation, so the local turn is undone: the world's z.
        var spin = world.physics.angular_velocity(
            world.actor(self.owner).body
        ).z
        var yaw_rate = spin + n.yaw_rate_bias + rng.normal(0, n.yaw_rate_stddev)
        var yaw = Int(round_half_away(Float64(yaw_rate * _TO_DEGREES) * 100.0))
        if yaw < -32766 or yaw > 32766:
            yaw = YAW_RATE_UNAVAILABLE
        return HighFrequencyContainer(
            CONTAINER_VEHICLE,
            Int(round_half_away(Float64(heading) * 10.0)),
            HEADING_CONFIDENCE_ONE_DEGREE,
            speed_value(speed),
            SPEED_CONFIDENCE,
            DRIVE_FORWARD if forward >= 0 else DRIVE_BACKWARD,
            Int(round_half_away(Float64(box.extent.x) * 200.0 * 10.0)),
            VEHICLE_LENGTH_CONFIDENCE_UNAVAILABLE,
            Int(round_half_away(Float64(box.extent.y) * 200.0 * 10.0)),
            _acceleration(accel.x),
            ACCELERATION_CONFIDENCE_UNAVAILABLE,
            CURVATURE_UNAVAILABLE,
            CURVATURE_CONFIDENCE_UNAVAILABLE,
            CURVATURE_YAW_RATE_USED,
            yaw,
            YAW_RATE_CONFIDENCE_UNAVAILABLE,
            True,
            _acceleration(accel.y),
            True,
            _acceleration(accel.z),
            0,
        )

    def _low_frequency(self, world: World) raises -> LowFrequencyContainer:
        """`AddLowFrequencyContainer`."""
        var lights = world.get_light_state(self.owner)
        var bits = UInt8(0)
        var flags = [
            LIGHT_LOW_BEAM,
            LIGHT_HIGH_BEAM,
            LIGHT_LEFT_BLINKER,
            LIGHT_RIGHT_BLINKER,
            LIGHT_REVERSE,
            LIGHT_FOG,
            LIGHT_POSITION,
        ]
        # ETSI's bit of each light: 0, 1, 2, 3, 5, 6 and 7.
        var etsi = [0, 1, 2, 3, 5, 6, 7]
        # The list is a constant and not empty.
        for i in range(len(flags)):  # pragma: no branch
            if lights.has(flags[i]):
                bits |= UInt8(1) << UInt8(7 - etsi[i])
        return LowFrequencyContainer(
            CONTAINER_VEHICLE, vehicle_role_of(self.station_type), bits, 0
        )


def _acceleration(value: Float32) -> Int:
    var tenths = Float64(value) * 10.0
    if tenths >= -160.0 and tenths <= 161.0:
        return Int(round_half_away(tenths))
    return ACCELERATION_UNAVAILABLE


# --- custom messages -----------------------------------------------------------------


comptime CUSTOM_V2X_MAX_BYTES = 100


@fieldwise_init
struct CustomV2XMessage(Copyable, Equatable, Movable, Writable):
    """A custom message, `CustomV2XM`: a header and up to 100 bytes."""

    var header: ItsPduHeader
    var data: List[UInt8]


@fieldwise_init
struct ReceivedCam(ImplicitlyCopyable):
    """A CAM a receiver heard, `CAMData`."""

    # In dBm.
    var power: Float32
    var message: CAM


@fieldwise_init
struct ReceivedCustom(Copyable, Movable):
    """A custom message a receiver heard, `CustomV2XData`."""

    # In dBm.
    var power: Float32
    var message: CustomV2XMessage


def custom_message(
    station_id: Int, data: List[UInt8]
) raises -> CustomV2XMessage:
    """Make a custom message, `ACustomV2XSensor::Send`.

    Args:
        station_id: The sender's parent's actor id.
        data: The payload.

    Returns:
        The message, with protocol 2 and message id custom.

    Raises:
        Error: If the payload has more than 100 bytes.
    """
    if len(data) > CUSTOM_V2X_MAX_BYTES:
        raise Error("A custom V2X message holds 100 bytes at most")
    return CustomV2XMessage(
        ItsPduHeader(2, MESSAGE_CUSTOM, station_id), data.copy()
    )
