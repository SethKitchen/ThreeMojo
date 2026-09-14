# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node in the scene graph, ported from three.js `src/core/Object3D.js`.

three.js gives every object a `children` array and a `parent` pointer, so the
graph is a tree of objects holding each other. Mojo cannot express that: a
struct may not contain a `List` of itself, which the compiler rejects with
"field 'children' has non-'Deinitable' type". So the tree is stored the other
way round — each node records only its parent's index, and `core.scene` owns
the flat array they all live in.

That is a real deviation from three.js, and on balance a good one. Traversal
becomes a single forward pass instead of recursion, the nodes sit contiguously
in memory, and the invariant that a parent is always added before its children
is checkable rather than assumed.

A node's local transform composes as translation * rotation * scale, matching
three.js: a point is scaled first, then rotated, then moved.
"""

from math.matrix4 import Matrix4, rotation_x, rotation_y, rotation_z, scaling
from math.matrix4 import translation
from math.vector3 import Vector3
from units.si import Angle


@fieldwise_init
struct NodeId(Equatable, ImplicitlyCopyable, Writable):
    """Which node in a `Scene`, as a type rather than a bare integer.

    A scene index, a geometry id, a material id and a texture id are all small
    integers, and `Mesh` takes three of them in a row. As plain `Int`s any two
    could be transposed and the result would compile and render nonsense.
    Wrapped, the compiler refuses; `tests/compile_fail/` has the proof.

    The wrapper costs nothing at runtime — it is one integer in a struct — and
    `value` is there for the few places that genuinely need the number: array
    indexing inside `Scene`, and packing for the device.
    """

    var value: Int


# A node with no parent. Roots carry this instead of an index.
comptime NO_PARENT = NodeId(-1)


struct Object3D(ImplicitlyCopyable):
    """A transform in the scene graph, positioned relative to its parent."""

    var position: Vector3
    var scale: Vector3
    # Held as a matrix rather than Euler angles or a quaternion: three.js has
    # both, and porting either properly is its own step.
    var rotation: Matrix4
    var parent: NodeId

    def __init__(out self):
        """Create an untransformed node with no parent."""
        self.position = Vector3(0, 0, 0)
        self.scale = Vector3(1, 1, 1)
        self.rotation = Matrix4()
        self.parent = NO_PARENT

    def __init__(out self, *, copy: Self):
        """Copy another node, parent link included."""
        self.position = copy.position
        self.scale = copy.scale
        self.rotation = Matrix4(copy=copy.rotation)
        self.parent = copy.parent

    def set_position(mut self, x: Float32, y: Float32, z: Float32):
        """Move this node, relative to its parent."""
        self.position = Vector3(x, y, z)

    def set_scale(mut self, x: Float32, y: Float32, z: Float32):
        """Scale this node, relative to its parent."""
        self.scale = Vector3(x, y, z)

    def set_euler(mut self, x: Angle, y: Angle, z: Angle) raises:
        """Set the rotation from three angles, applied x, then y, then z.

        Args:
            x: Rotation about the x axis, applied first.
            y: Rotation about the y axis.
            z: Rotation about the z axis, applied last.

        Raises:
            Error: Never; present to match the matrix helpers.
        """
        var combined = rotation_z(z)
        combined.multiply(rotation_y(y))
        combined.multiply(rotation_x(x))
        self.rotation = combined^

    def local_matrix(self) raises -> Matrix4:
        """Return this node's transform relative to its parent.

        Returns:
            The product translation * rotation * scale, so a point is scaled
            first, then rotated, then moved.

        Raises:
            Error: Never; present to match the matrix helpers.
        """
        var matrix = translation(
            self.position.x, self.position.y, self.position.z
        )
        matrix.multiply(self.rotation)
        matrix.multiply(scaling(self.scale.x, self.scale.y, self.scale.z))
        return matrix^
