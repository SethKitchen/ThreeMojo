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

The rotation is a quaternion, as three.js's `Object3D.quaternion` is. Euler
angles are one way to *set* it -- `set_euler`, the order being three.js's --
and `rotate_x`, `rotate_y`, `rotate_z` and `rotate_on_axis` turn it further
by one multiply each, about the node's *own* axes, which is three.js's
`rotateY` and friends. That is not `rotation.y += 0.01` there, except while
the other two angles are zero: an Euler component is not a local axis in
general. From `XYZ` angles of (0, 0, 90) a turn of 90 about the local y
sends +x to -z, while raising the Euler y to 90 sends it to +y. `look_at`
orients a node towards a point in its parent's frame; `Scene.look_at` does
it in world space.
"""

from math.euler import XYZ, Euler, EulerOrder
from math.matrix4 import Matrix4, scaling, translation
from math.quaternion import Quaternion
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


def facing(
    eye: Vector3, target: Vector3, up: Vector3, camera: Bool
) raises -> Quaternion:
    """Return the rotation that turns something at `eye` to face `target`.

    The basis three.js's `Matrix4.lookAt` builds, as a quaternion: z along
    the line of sight, x perpendicular to it and to `up`, y completing the
    frame. All three vectors have to be given in one frame, and the answer
    is a rotation in that frame -- which is why `Scene.look_at` calls this
    with world-space values and only then takes the result into the parent's
    frame, rather than taking the target across first and building the
    basis there with the wrong up.

    Args:
        eye: Where the thing is.
        target: The point it should face.
        up: Which way is up; need not be perpendicular to the line of sight.
        camera: True to face the target down -z, as a camera does; else +z.

    Returns:
        The rotation.

    Raises:
        Error: If the target is at the eye, or the line of sight runs along
            `up`, either of which leaves the roll undefined.
    """
    var z = target - eye
    if z.length() == 0:
        raise Error("A node cannot look at its own position")
    z.normalize()
    if camera:
        z = -z
    var x = up
    x.cross(z)
    if x.length() == 0:
        raise Error("Looking straight along up leaves the roll undefined")
    x.normalize()
    var y = z
    y.cross(x)
    var basis = Matrix4()
    basis.set(
        x.x,
        y.x,
        z.x,
        0,
        x.y,
        y.y,
        z.y,
        0,
        x.z,
        y.z,
        z.z,
        0,
        0,
        0,
        0,
        1,
    )
    return Quaternion.from_matrix(basis)


struct Object3D(ImplicitlyCopyable):
    """A transform in the scene graph, positioned relative to its parent."""

    var position: Vector3
    var scale: Vector3
    # The rotation, as three.js holds it. A matrix would compose but not
    # interpolate; Euler angles would interpolate but lock up. See
    # `math.quaternion`.
    var quaternion: Quaternion
    var parent: NodeId

    def __init__(out self):
        """Create an untransformed node with no parent."""
        self.position = Vector3(0, 0, 0)
        self.scale = Vector3(1, 1, 1)
        self.quaternion = Quaternion.identity()
        self.parent = NO_PARENT

    def __init__(out self, *, copy: Self):
        """Copy another node, parent link included."""
        self.position = copy.position
        self.scale = copy.scale
        self.quaternion = copy.quaternion
        self.parent = copy.parent

    def set_position(mut self, x: Float32, y: Float32, z: Float32):
        """Move this node, relative to its parent."""
        self.position = Vector3(x, y, z)

    def set_scale(mut self, x: Float32, y: Float32, z: Float32):
        """Scale this node, relative to its parent."""
        self.scale = Vector3(x, y, z)

    def set_euler(
        mut self, x: Angle, y: Angle, z: Angle, order: EulerOrder = XYZ
    ):
        """Set the rotation from three angles, composed in `order`.

        The default is three.js's default, `XYZ`, and means what it means
        there: turn about x, then about the turned y, then about the
        twice-turned z, which as a matrix is Rx * Ry * Rz. This used to
        compose Rz * Ry * Rx, three.js's `ZYX`, so the same three numbers
        gave a different orientation from the same code in three.js whenever
        two of them were non-zero. `ZYX` is still available by name.

        Args:
            x: Rotation about the x axis.
            y: Rotation about the y axis.
            z: Rotation about the z axis.
            order: Which axis comes first, second and third.
        """
        self.quaternion = Euler(x, y, z, order).to_quaternion()

    def set_rotation(mut self, euler: Euler):
        """Set the rotation from an `Euler`, three.js's `rotation.set`."""
        self.quaternion = euler.to_quaternion()

    def set_quaternion(mut self, quaternion: Quaternion):
        """Set the rotation directly, three.js's `quaternion.copy`."""
        self.quaternion = quaternion

    def rotate_on_axis(mut self, axis: Vector3, angle: Angle):
        """Turn this node about one of its *own* axes.

        Local, as three.js's `rotateOnAxis` is: the axis is in the node's
        current frame, so turning about (0, 1, 0) after a tilt turns about
        the tilted up. A post-multiply, for the same reason `Matrix4.multiply`
        applies the right-hand matrix first.

        Args:
            axis: The axis, unit length, in the node's own frame.
            angle: How far to turn.
        """
        self.quaternion.multiply(Quaternion.from_axis_angle(axis, angle))

    def rotate_on_world_axis(mut self, axis: Vector3, angle: Angle):
        """Turn this node about an axis of its *parent's* frame.

        three.js's `rotateOnWorldAxis`, and like it named for the common
        case: a root node's parent frame is the world.

        Args:
            axis: The axis, unit length, in the parent's frame.
            angle: How far to turn.
        """
        self.quaternion.premultiply(Quaternion.from_axis_angle(axis, angle))

    def rotate_x(mut self, angle: Angle):
        """Turn about the node's own x axis: three.js's `rotateX`."""
        self.rotate_on_axis(Vector3(1, 0, 0), angle)

    def rotate_y(mut self, angle: Angle):
        """Turn about the node's own y axis: three.js's `rotateY`."""
        self.rotate_on_axis(Vector3(0, 1, 0), angle)

    def rotate_z(mut self, angle: Angle):
        """Turn about the node's own z axis: three.js's `rotateZ`."""
        self.rotate_on_axis(Vector3(0, 0, 1), angle)

    def look_at(mut self, target: Vector3, *, camera: Bool = False) raises:
        """Turn this node to face `target`, given in the parent's frame.

        three.js's `Object3D.lookAt` with one difference worth knowing: it
        works in world space, walking the parents to get there, and this one
        works entirely in the frame the node's position is in -- the target,
        and the up direction, which is that frame's +y. For a root node the
        two are the same; for a child, `Scene.look_at` does the walk, up
        direction included.

        Which way "facing" is depends on what the node is, exactly as there.
        An object points its +z axis at the target. A camera points its -z
        axis at the target, because a camera looks down -z; three.js decides
        by `isCamera`, and here you say so.

        Args:
            target: The point to face, in the parent's frame.
            camera: True to face the target the way a camera does.

        Raises:
            Error: If the target is at the node's own position, or straight
                along the parent's y from it, either of which leaves the
                orientation undefined. three.js nudges the axis by a small
                amount instead; refusing is consistent with
                `math.projection.look_at`.
        """
        self.quaternion = facing(
            self.position, target, Vector3(0, 1, 0), camera
        )

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
        matrix.multiply(self.quaternion.to_matrix())
        matrix.multiply(scaling(self.scale.x, self.scale.y, self.scale.z))
        return matrix^
