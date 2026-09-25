# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node in the scene graph, ported from three.js `src/core/Object3D.js`.

three.js gives every object a `children` array and a `parent` pointer, so the
graph is a tree of objects holding each other. Mojo cannot express that: a
struct may not contain a `List` of itself, which the compiler rejects with
"field 'children' has non-'Deinitable' type". So the tree is stored the other
way round -- each node records only its parent's index, and `core.scene` owns
the flat array they all live in, and the order of each node's children.

That is a real deviation from three.js, and on balance a good one. The nodes
sit contiguously in memory, a node's id is its place in the array and never
changes, and the graph can be checked for a loop, which three.js cannot do
for a child added under its own descendant.

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

The rest of three.js's own-frame edits are here too: `translate_x`,
`translate_y`, `translate_z` and `translate_on_axis` move the node along its
own axes, `apply_matrix4` and `apply_quaternion` transform it in its
parent's frame, and the four `set_rotation_from_*` set the rotation from an
axis and an angle, an `Euler`, a matrix or a quaternion. What needs the
world -- `localToWorld`, `getWorldPosition` and the rest -- needs the
parents too, and is on `Scene`.

A node carries nothing to draw. A mesh, a light or a line names a node, so
a node is an `Object3D` or a `Group` in three.js's terms, and `object_type`
says which. The two act the same; the type is kept so a scene written to
JSON reads back as it was. See `objects.group`.
"""

from core.layers import Layers
from core.user_data import UserData
from math.euler import XYZ, Euler, EulerOrder
from math.matrix4 import Matrix4, scaling, translation
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isfinite
from units.si import METER, Angle, Length


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


# Which way is up for a node that is not told otherwise, three.js's
# `Object3D.DEFAULT_UP`. three.js lets a program change it for every object
# made after; a Mojo module has no mutable global, so here it is fixed, and
# a node's own `up` is what changes.
comptime DEFAULT_UP = Vector3(0, 1, 0)

# A node with no parent. Roots carry this instead of an index. Where a
# `Scene` method takes a node to start from, this names the scene itself.
comptime NO_PARENT = NodeId(-1)


@fieldwise_init
struct ObjectType(Equatable, ImplicitlyCopyable, Writable):
    """What a node is when it carries nothing, three.js's `type` of an
    `Object3D` or a `Group`, or three.js's `Gyroscope`.

    An `Object3D` and a `Group` act the same. The type is kept so a scene
    written to JSON reads back as it was. A gyroscope keeps its own turn
    in the world, whatever its parents' turns: see `Scene.update`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three types there are."""
        return (
            self == OBJECT3D_TYPE
            or self == GROUP_TYPE
            or self == GYROSCOPE_TYPE
        )


comptime OBJECT3D_TYPE = ObjectType(0)
comptime GROUP_TYPE = ObjectType(1)
# three.js's `Gyroscope`: the node takes its parents' position and scale,
# and not their turn.
comptime GYROSCOPE_TYPE = ObjectType(2)


def scale_of(matrix: Matrix4) -> Vector3:
    """Return the scale a transform holds, as three.js's `Matrix4.decompose`
    finds it.

    Args:
        matrix: A translation times a rotation times a scale.

    Returns:
        The lengths of the first three columns. The x length is negative
        when the matrix mirrors, as in three.js.
    """
    ref e = matrix.elements
    var sx = Vector3(e[0], e[1], e[2]).length()
    var sy = Vector3(e[4], e[5], e[6]).length()
    var sz = Vector3(e[8], e[9], e[10]).length()
    if matrix.determinant() < 0:
        sx = -sx
    return Vector3(sx, sy, sz)


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
        Error: If `up` is zero or not finite: it names no direction, and
            three.js builds a basis that is not a rotation from it. A
            target at the eye leaves the rotation the identity, and a line
            of sight along `up` is nudged off it by a ten-thousandth,
            exactly as three.js's `Matrix4.lookAt` settles both; see
            `math.projection.look_at`.
    """
    var reach = up.length()
    if not isfinite(reach) or reach == 0:
        raise Error("An up direction must be finite and not zero")
    var z = target - eye
    if camera:
        z = -z
    # three.js substitutes +z for the basis's third column whichever way
    # round the eye and target went in, so both cases give the identity.
    if z.length() == 0:
        z = Vector3(0, 0, 1)
    z.normalize()
    var x = up
    x.cross(z)
    if x.length() == 0:
        if abs(up.z) == 1:
            z.x += 0.0001
        else:
            z.z += 0.0001
        z.normalize()
        x = up
        x.cross(z)
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
    # Which layers this node is on, three.js's `Object3D.layers`. A camera
    # draws a mesh only if its node shares a layer with the camera. Layer
    # zero alone by default, so a scene that never mentions layers renders
    # as it always did.
    var layers: Layers
    # False hides this node and everything under it, three.js's
    # `Object3D.visible`. A hidden node still has a world matrix.
    var visible: Bool
    # A name to find the node by, three.js's `Object3D.name`. Empty by
    # default; two nodes can share one.
    var name: String
    # Where the node's objects go in the draw order, three.js's
    # `renderOrder`. Lower draws first. Within one order, opaque draws go
    # nearest first and blended ones furthest first, as before.
    var render_order: Int
    # True, the default, to rebuild `matrix` from the position, rotation
    # and scale at every `Scene.update`. False keeps `matrix` as the
    # caller set it, three.js's `matrixAutoUpdate`.
    var matrix_auto_update: Bool
    # The transform relative to the parent, as the last update built it
    # or as the caller set it. three.js's `Object3D.matrix`.
    var matrix: Matrix4
    # `OBJECT3D_TYPE`, `GROUP_TYPE` for a node built by `group()`, or
    # `GYROSCOPE_TYPE` for one built by `gyroscope()`.
    var object_type: ObjectType
    # What the caller keeps on the node, three.js's `userData`. Written to
    # and read from scene JSON. See `core.user_data`.
    var user_data: UserData
    # Which way is up when the node turns to face something, three.js's
    # `Object3D.up`: `look_at` and `Scene.look_at` keep the node's y axis
    # as near it as they can. A direction in world space, as three.js reads
    # it, and `DEFAULT_UP` unless set. Written to and read from scene JSON.
    var up: Vector3

    def __init__(out self):
        """Create an untransformed node with no parent, on layer zero,
        visible, unnamed, at render order zero, with no user data, and with
        `DEFAULT_UP` for up."""
        self.position = Vector3(0, 0, 0)
        self.scale = Vector3(1, 1, 1)
        self.quaternion = Quaternion.identity()
        self.parent = NO_PARENT
        self.layers = Layers()
        self.visible = True
        self.name = String()
        self.render_order = 0
        self.matrix_auto_update = True
        self.matrix = Matrix4()
        self.object_type = OBJECT3D_TYPE
        self.user_data = UserData()
        self.up = DEFAULT_UP

    def __init__(out self, *, copy: Self):
        """Copy another node, every field included."""
        self.position = copy.position
        self.scale = copy.scale
        self.quaternion = copy.quaternion
        self.parent = copy.parent
        self.layers = copy.layers
        self.visible = copy.visible
        self.name = copy.name
        self.render_order = copy.render_order
        self.matrix_auto_update = copy.matrix_auto_update
        self.matrix = Matrix4(copy=copy.matrix)
        self.object_type = copy.object_type
        self.user_data = UserData(copy=copy.user_data)
        self.up = copy.up

    def set_position(mut self, x: Float32, y: Float32, z: Float32):
        """Move this node, relative to its parent."""
        self.position = Vector3(x, y, z)

    def set_scale(mut self, x: Float32, y: Float32, z: Float32):
        """Scale this node, relative to its parent."""
        self.scale = Vector3(x, y, z)

    def set_euler(
        mut self, x: Angle, y: Angle, z: Angle, order: EulerOrder = XYZ
    ) raises:
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

        Raises:
            Error: If `order` does not name three different axes. The
                rotation is left as it was.
        """
        self.quaternion = Euler(x, y, z, order).to_quaternion()

    def set_rotation(mut self, euler: Euler) raises:
        """Set the rotation from an `Euler`, three.js's `rotation.set`.

        Args:
            euler: The angles and their order.

        Raises:
            Error: If the order does not name three different axes. The
                rotation is left as it was.
        """
        self.quaternion = euler.to_quaternion()

    def set_quaternion(mut self, quaternion: Quaternion):
        """Set the rotation directly, three.js's `quaternion.copy`."""
        self.quaternion = quaternion

    def rotation(self, order: EulerOrder = XYZ) raises -> Euler:
        """Return the rotation as three angles, three.js's `Object3D.rotation`.

        Read out of the quaternion, which is the truth: `rotate_y` and
        `look_at` change the quaternion, and this decomposes whatever they
        left. `set_rotation` with the result gives the same rotation back.
        The numbers can differ from the ones that were set: past a right
        angle on the middle axis, and at gimbal lock, more than one triple
        makes the same rotation and this returns three.js's. Whole turns
        are gone, because a rotation does not remember them.

        The result is a snapshot, not three.js's live `rotation` object.
        Changing it changes nothing; `rotation.y += angle` in three.js is
        three steps here: read the angles, change one, and `set_rotation`.

        Args:
            order: Which axis the angles turn about first, second and third.

        Returns:
            The angles, in `order`.

        Raises:
            Error: If `order` does not name three different axes.
        """
        return Euler.from_quaternion(self.quaternion, order)

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

    def translate_on_axis(mut self, axis: Vector3, distance: Length):
        """Move this node along one of its *own* axes.

        three.js's `translateOnAxis`: the axis is turned by the node's
        rotation, scaled by the distance, and added to the position. The
        node's scale does not stretch the step.

        Args:
            axis: The axis, unit length, in the node's own frame.
            distance: How far to move.
        """
        self.position.add(self.quaternion.rotate(axis) * distance.to(METER))

    def translate_x(mut self, distance: Length):
        """Move along the node's own x axis: three.js's `translateX`."""
        self.translate_on_axis(Vector3(1, 0, 0), distance)

    def translate_y(mut self, distance: Length):
        """Move along the node's own y axis: three.js's `translateY`."""
        self.translate_on_axis(Vector3(0, 1, 0), distance)

    def translate_z(mut self, distance: Length):
        """Move along the node's own z axis: three.js's `translateZ`."""
        self.translate_on_axis(Vector3(0, 0, 1), distance)

    def apply_quaternion(mut self, quaternion: Quaternion):
        """Turn this node in its parent's frame, three.js's
        `applyQuaternion`.

        The rotation is premultiplied, as `rotate_on_world_axis` does. The
        position does not move.

        Args:
            quaternion: The turn, unit length.
        """
        self.quaternion.premultiply(quaternion)

    def set_rotation_from_axis_angle(mut self, axis: Vector3, angle: Angle):
        """Set the rotation to a turn about one axis, three.js's
        `setRotationFromAxisAngle`.

        Args:
            axis: The axis, unit length.
            angle: How far to turn.
        """
        self.quaternion = Quaternion.from_axis_angle(axis, angle)

    def set_rotation_from_euler(mut self, euler: Euler) raises:
        """Set the rotation from an `Euler`, three.js's
        `setRotationFromEuler`. The same as `set_rotation`.

        Args:
            euler: The angles and their order.

        Raises:
            Error: If the order does not name three different axes. The
                rotation is left as it was.
        """
        self.set_rotation(euler)

    def set_rotation_from_matrix(mut self, matrix: Matrix4):
        """Set the rotation from the upper 3x3 of a matrix, three.js's
        `setRotationFromMatrix`.

        As there, the 3x3 must be a pure rotation. A scale in it gives a
        wrong rotation rather than an error; see `Quaternion.from_matrix`.

        Args:
            matrix: A rotation matrix.
        """
        self.quaternion = Quaternion.from_matrix(matrix)

    def set_rotation_from_quaternion(mut self, quaternion: Quaternion):
        """Set the rotation directly, three.js's
        `setRotationFromQuaternion`. The same as `set_quaternion`.

        Args:
            quaternion: The rotation, unit length.
        """
        self.quaternion = quaternion

    def look_at(mut self, target: Vector3, *, camera: Bool = False) raises:
        """Turn this node to face `target`, given in the parent's frame.

        three.js's `Object3D.lookAt` with one difference worth knowing: it
        works in world space, walking the parents to get there, and this one
        works entirely in the frame the node's position is in -- the target,
        and the node's `up`. For a root node the two are the same; for a
        child, `Scene.look_at` does the walk.

        Which way "facing" is depends on what the node is, exactly as there.
        An object points its +z axis at the target. A camera and a light
        point their -z axis at it, because a camera looks down -z; three.js
        decides by `isCamera` and `isLight`, and here you say so. All three
        keep their y axis as near `up` as they can.

        Args:
            target: The point to face, in the parent's frame.
            camera: True to face the target the way a camera or a light
                does.

        Raises:
            Error: If `up` is zero or not finite; the node is left as it
                was. A target at the node's own position gives the
                identity, and a target straight along `up` is nudged off
                it by a ten-thousandth, as three.js does; see `facing`.
        """
        self.quaternion = facing(self.position, target, self.up, camera)

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

    def set_from_matrix(mut self, matrix: Matrix4) raises:
        """Set the position, rotation and scale from a transform, three.js's
        `matrix.decompose(position, quaternion, scale)`.

        The arithmetic is three.js's: the scale is the length of each of
        the first three columns, the x scale is negated when the matrix
        mirrors, and the rotation is read from the columns divided by
        their scales. `matrix` is left as it was.

        Args:
            matrix: A translation times a rotation times a scale.

        Raises:
            Error: If the matrix flattens an axis. three.js divides by the
                zero and leaves a rotation that is not a number; this
                refuses and leaves the node as it was.
        """
        var scale = scale_of(matrix)
        if scale.x * scale.y * scale.z == 0:
            raise Error("A transform that flattens an axis has no rotation")
        ref e = matrix.elements
        var rotation = Matrix4()
        for row in range(3):  # pragma: no branch
            rotation.elements[row] = e[row] / scale.x
            rotation.elements[4 + row] = e[4 + row] / scale.y
            rotation.elements[8 + row] = e[8 + row] / scale.z
        self.position = Vector3(e[12], e[13], e[14])
        self.quaternion = Quaternion.from_matrix(rotation)
        self.scale = scale

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Transform this node in its parent's frame, three.js's
        `applyMatrix4`.

        The node's matrix -- rebuilt from its parts first when
        `matrix_auto_update` is set -- is premultiplied by `matrix`, and
        the position, rotation and scale are read back out of the result.
        As in three.js, a transform that shears the node is not kept: the
        parts cannot hold a shear.

        Args:
            matrix: The transform, in the parent's frame.

        Raises:
            Error: If the result flattens an axis. The node is left as it
                was; see `set_from_matrix`.
        """
        var combined = self.local_matrix() if self.matrix_auto_update else (
            Matrix4(copy=self.matrix)
        )
        combined.premultiply(matrix)
        self.set_from_matrix(combined)
        self.matrix = combined^
