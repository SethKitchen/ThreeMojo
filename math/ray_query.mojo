# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""A ray and its distance range, independent of scene traversal."""

from math.ray import Ray
from units.si import Length


trait RayQuery:
    """The geometric part of a raycaster used by individual objects."""

    def query_ray(self) -> Ray:
        """Return the world-space ray."""
        ...

    def query_near(self) -> Length:
        """Return the nearest accepted distance."""
        ...

    def query_far(self) -> Length:
        """Return the furthest accepted distance."""
        ...
