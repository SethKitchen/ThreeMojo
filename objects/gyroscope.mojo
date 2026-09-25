# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node that keeps its own turn in the world, ported from three.js
`examples/jsm/misc/Gyroscope.js`.

`gyroscope()` returns an `Object3D` whose `object_type` is
`GYROSCOPE_TYPE`. `Scene.update` carries it to the position and the scale
its parents give it, as any node, and gives it its own turn, not theirs.
Its children then ride that world transform. three.js's example hangs a
camera and a light on a gyroscope under a turning car, so they follow the
car and do not turn with it.

three.js's `Gyroscope` writes its `type` as `Object3D` in JSON, so it reads
back as a plain node. This does the same.
"""

from core.object3d import GYROSCOPE_TYPE, Object3D


def gyroscope() -> Object3D:
    """Return a new gyroscope, three.js's `new Gyroscope()`.

    Returns:
        An untransformed node with no parent and the `GYROSCOPE_TYPE` type.
    """
    var node = Object3D()
    node.object_type = GYROSCOPE_TYPE
    return node^
