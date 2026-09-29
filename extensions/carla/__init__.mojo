# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The engine-independent half of the CARLA driving simulator.

CARLA is the Computer Vision Center's open driving simulator (MIT, CVC at
the Universitat Autonoma de Barcelona). This package ports what does not
need CARLA's simulator plugin and its game engine: the left-handed frame and its transforms, the
OpenDRIVE plan-view geometries, lane and lane-marking meshes, the sensor
encodings, the camera intrinsics and the ray-cast LiDAR. The original
lives at https://github.com/carla-simulator/carla.
"""
