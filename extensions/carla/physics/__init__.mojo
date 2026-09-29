# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's physics: rigid bodies, contacts, wheeled vehicles and walkers.

CARLA leaves its actors' physics to the game engine it runs in. This
package is a rigid-body engine of its own, with CARLA's vehicle and
walker records and controllers on top: `VehiclePhysicsControl`, `WheelPhysicsControl`,
`VehicleControl`, `VehicleAckermannControl` with CARLA's Ackermann
controller, and `WalkerControl`. Everything is in CARLA's left-handed
frame: plus x forward, plus y right, plus z up, in meters.
"""
