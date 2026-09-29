# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's constants, CARLA's `trafficmanager/Constants.h`.

Each constant keeps CARLA's name, its namespace as a prefix-free comment
block, and CARLA's `float` value. A length, a speed, a time or an angle
carries its unit type. A plain factor, a percentage or a count is a
number.

CARLA computes some values in `float` at compile time, such as
`HIGHWAY_SPEED = 60.0f / 3.6f`. The values here are computed the same
way, in `Float32`.

The networking constants (the port and the time out of CARLA's remote
traffic manager) are not ported: the remote client is out of scope.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/Constants.h`.
"""

from units.si import (
    Acceleration,
    Angle,
    Area,
    DEGREE,
    Duration,
    Length,
    Velocity,
)

comptime _KMH = Float32(3.6)

# --- VehicleRemoval ---------------------------------------------------------

# A registered vehicle slower than this counts as idle.
comptime STOPPED_VELOCITY_THRESHOLD = Velocity(0.8)
# An idle vehicle is stuck after this long, when its light is not red.
comptime BLOCKED_TIME_THRESHOLD = Duration(90.0)
# An idle vehicle at a red light is stuck after this long.
comptime RED_TL_BLOCKED_TIME_THRESHOLD = Duration(180.0)
# The least time between two removals of stuck vehicles.
comptime DELTA_TIME_BETWEEN_DESTRUCTIONS = Duration(10.0)

# --- HybridMode -------------------------------------------------------------

# The step of a vehicle moved without physics.
comptime HYBRID_MODE_DT = Duration(0.05)
# CARLA's double `HYBRID_MODE_DT`, which the elapsed-time tests use.
comptime HYBRID_MODE_DT_SECONDS = Float64(0.05)
comptime INV_HYBRID_DT = Float64(1.0) / HYBRID_MODE_DT_SECONDS
comptime PHYSICS_RADIUS = Length(50.0)

# --- SpeedThreshold ---------------------------------------------------------

comptime HIGHWAY_SPEED = Velocity(Float32(60.0) / _KMH)
comptime AFTER_JUNCTION_MIN_SPEED = Velocity(Float32(5.0) / _KMH)
# In percent.
comptime INITIAL_PERCENTAGE_SPEED_DIFFERENCE = Float32(0.0)

# --- PathBufferUpdate -------------------------------------------------------

comptime MAX_START_DISTANCE = Length(20.0)
comptime MINIMUM_HORIZON_LENGTH = Length(15.0)
# The horizon is the speed times this, at least `MINIMUM_HORIZON_LENGTH`.
comptime HORIZON_RATE = Duration(2.0)
comptime HIGH_SPEED_HORIZON_RATE = Duration(4.0)

# --- WaypointSelection ------------------------------------------------------

comptime TARGET_WAYPOINT_TIME_HORIZON = Duration(0.5)
comptime MIN_TARGET_WAYPOINT_DISTANCE = Length(3.0)
comptime JUNCTION_LOOK_AHEAD = Length(5.0)
comptime SAFE_DISTANCE_AFTER_JUNCTION = Length(4.0)
comptime MIN_JUNCTION_LENGTH = Length(8.0)
comptime MIN_SAFE_INTERVAL_LENGTH = Length(
    Float32(0.5) * SAFE_DISTANCE_AFTER_JUNCTION.value
)
comptime LARGE_VEHICLES_JUNCTION_OFFSET = Length(1.5)
# A fraction of the junction's length.
comptime LARGE_VEHICLES_JUNCTION_POINT = Float32(0.3)
comptime LARGE_VEHICLES_JUNCTION_MAX_RADIUS = Length(20.0)
# The share of the inboard swing a large vehicle keeps.
comptime LARGE_VEHICLES_JUNCTION_INBOARD_SCALE = Float32(0.25)
comptime LARGE_VEHICLES_JUNCTION_REF_LENGTH = Length(6.0)
# Meters of offset per meter of length past the reference length.
comptime LARGE_VEHICLES_JUNCTION_OFFSET_GAIN = Float32(0.25)
comptime LARGE_VEHICLES_JUNCTION_CLEARANCE = Length(1.0)
comptime LARGE_VEHICLES_JUNCTION_SIDE_MARGIN = Length(2.0)

# --- LaneChange -------------------------------------------------------------

comptime MINIMUM_LANE_CHANGE_DISTANCE = Length(20.0)
comptime MAXIMUM_LANE_OBSTACLE_DISTANCE = Length(50.0)
# A dot product of two unit headings.
comptime MAXIMUM_LANE_OBSTACLE_CURVATURE = Float32(0.6)
comptime INTER_LANE_CHANGE_DISTANCE = Length(10.0)
comptime MIN_WPT_DISTANCE = Length(5.0)
comptime MAX_WPT_DISTANCE = Length(20.0)
comptime MIN_LANE_CHANGE_SPEED = Velocity(5.0)
# In percent.
comptime FIFTYPERC = Float32(50.0)

# --- Collision --------------------------------------------------------------

comptime BOUNDARY_EXTENSION_MINIMUM = Length(2.5)
# CARLA declares it and does not use it.
comptime BOUNDARY_EXTENSION_RATE = Float32(4.35)
comptime COS_10_DEGREES = Float32(0.9848)
comptime OVERLAP_THRESHOLD = Length(0.1)
comptime LOCKING_DISTANCE_PADDING = Length(4.0)
comptime COLLISION_RADIUS_STOP = Length(8.0)
comptime COLLISION_RADIUS_MIN = Length(20.0)
# The collision radius grows by the speed times this.
comptime COLLISION_RADIUS_RATE = Duration(2.65)
comptime MAX_LOCKING_EXTENSION = Length(10.0)
comptime WALKER_TIME_EXTENSION = Duration(1.5)
comptime SQUARE_ROOT_OF_TWO = Float32(1.414)
comptime VERTICAL_OVERLAP_THRESHOLD = Length(4.0)
# Two `FLT_EPSILON`: the least length a vector needs to be made a unit one.
comptime EPSILON = Float32(2.0) * Float32(1.1920928955078125e-07)
comptime MIN_REFERENCE_DISTANCE = Length(0.5)
comptime MIN_VELOCITY_COLL_RADIUS = Velocity(2.0)
# CARLA squares this times the speed in m/s and adds it, in meters.
comptime VEL_EXT_FACTOR = Float32(0.36)

# --- FrameMemory ------------------------------------------------------------

comptime INITIAL_SIZE = 50
comptime GROWTH_STEP_SIZE = 50

# --- Map --------------------------------------------------------------------

# `std::numeric_limits<float>::max()`.
comptime INFINITE_DISTANCE = Length(Float32(3.4028234663852886e38))
comptime MAX_GEODESIC_GRID_LENGTH = Length(20.0)
comptime MAP_RESOLUTION = Length(5.0)
comptime INV_MAP_RESOLUTION = Float32(1.0) / MAP_RESOLUTION.value
# CARLA's double `MAP_RESOLUTION / 2 + MAP_RESOLUTION^2`, which it divides
# a squared distance by.
comptime MAX_WPT_DISTANCE_SQUARED = Float64(5.0) / 2.0 + Float64(5.0) * 5.0
comptime MAX_WPT_RADIANS = Angle(0.087)
comptime DELTA = Length(25.0)
comptime Z_DELTA = Length(500.0)
comptime STRAIGHT_DEG = Angle(19.0, DEGREE)
comptime MIN_LANE_WIDTH = Length(1.0)

# --- TrafficLight -----------------------------------------------------------

comptime MINIMUM_STOP_TIME = Duration(2.0)
# A dot product: 90 degrees.
comptime EXIT_JUNCTION_THRESHOLD = Float32(0.0)

# --- MotionPlan -------------------------------------------------------------

comptime RELATIVE_APPROACH_SPEED = Velocity(Float32(12.0) / _KMH)
comptime MIN_FOLLOW_LEAD_DISTANCE = Length(2.0)
comptime CRITICAL_BRAKING_MARGIN = Length(0.2)
comptime EPSILON_RELATIVE_SPEED = Velocity(0.001)
comptime MAX_JUNCTION_BLOCK_DISTANCE = Length(
    Float32(1.0) * SAFE_DISTANCE_AFTER_JUNCTION.value
)
comptime TWO_KM = Length(2000.0)
comptime ATTEMPTS_TO_TELEPORT = 5
comptime LANDMARK_DETECTION_TIME = Duration(3.5)
comptime TL_TARGET_VELOCITY = Velocity(Float32(15.0) / _KMH)
comptime STOP_TARGET_VELOCITY = Velocity(Float32(10.0) / _KMH)
comptime YIELD_TARGET_VELOCITY = Velocity(Float32(10.0) / _KMH)
# A tire's friction coefficient.
comptime FRICTION = Float32(0.6)
comptime GRAVITY = Acceleration(9.81)
comptime PI = Float32(3.1415927)
# A share of the speed.
comptime PERC_MAX_SLOWDOWN = Float32(0.08)
# The follow distance grows by the speed times this.
comptime FOLLOW_LEAD_FACTOR = Duration(2.0)

# --- VehicleLight -----------------------------------------------------------

comptime SUN_ALTITUDE_DEGREES_BEFORE_DAWN = Angle(15.0, DEGREE)
comptime SUN_ALTITUDE_DEGREES_AFTER_SUNSET = Angle(165.0, DEGREE)
comptime SUN_ALTITUDE_DEGREES_JUST_AFTER_DAWN = Angle(35.0, DEGREE)
comptime SUN_ALTITUDE_DEGREES_JUST_BEFORE_SUNSET = Angle(145.0, DEGREE)
# In percent.
comptime HEAVY_PRECIPITATION_THRESHOLD = Float32(80.0)
comptime FOG_DENSITY_THRESHOLD = Float32(20.0)
# CARLA compares a squared distance with it.
comptime MAX_DISTANCE_LIGHT_CHECK = Area(225.0)

# --- PID --------------------------------------------------------------------

comptime MAX_THROTTLE = Float32(0.85)
comptime MAX_BRAKE = Float32(0.7)
comptime MAX_STEERING = Float32(0.8)
comptime MAX_STEERING_DIFF = Float32(0.15)
comptime DT = Duration(0.05)
comptime INV_DT = Float32(1.0) / DT.value

# --- TrackTraffic -----------------------------------------------------------

comptime BUFFER_STEP_THROUGH = 5
comptime INV_BUFFER_STEP_THROUGH = Float32(1.0) / Float32(BUFFER_STEP_THROUGH)
