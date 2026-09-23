# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node that only holds other nodes, ported from three.js
`src/objects/Group.js`.

three.js's `Group` is an `Object3D` with `type` set to `'Group'` and
nothing else. So is this one: `group()` returns an `Object3D` whose
`object_type` is `GROUP_TYPE`. It moves, turns and hides its children as
any node does. The type matters only in scene JSON, where it is written as
`"Group"` and read back as a group.
"""

from core.object3d import GROUP_TYPE, Object3D


def group() -> Object3D:
    """Return a new group, three.js's `new Group()`.

    Returns:
        An untransformed node with no parent and the `GROUP_TYPE` type.
    """
    var node = Object3D()
    node.object_type = GROUP_TYPE
    return node^
