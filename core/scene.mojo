# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The flat array of nodes that makes up a scene graph.

three.js walks a tree of objects to update world matrices. Here the nodes live
in one array and each records its parent's index, because Mojo will not let a
struct hold a `List` of itself — see `core.object3d`.

The array is kept in an order where a parent always precedes its children.
`add` enforces it by refusing a parent that does not already exist, which is
not a restriction in practice: you cannot attach something to an object you
have not created. The payoff is that updating every world matrix is a single
forward pass, with each node's parent guaranteed to be finished before the
node is reached. No recursion, no visited set, no cycles possible.

**Stale transforms are refused, not served.** World matrices are cached by
`update` and read back by `world_matrix`. Any edit invalidates them, and
reading one before recomputing raises rather than handing back a matrix from
before the edit. The alternative — recompute automatically on read — hides
how much work a render costs and recomputes the whole scene for one lookup.
The alternative it replaces, serving the stale value, is worse than both: it
produces a plausible wrong image and no error at all.

**A known limitation.** Storing parents before children restricts reparenting.
Moving an older node underneath a newer one is a perfectly valid acyclic
operation and this rejects it, because the array order would no longer match
the dependency order. Nothing needs it yet. When something does, the fix is to
separate a stable node id from the position a node occupies in traversal
order, rather than to relax the check.

**Meshes and lights are scene content.** three.js's `scene.add` takes either,
and a renderer is handed the scene and a camera and nothing else. For a while
meshes traveled in a separate list beside the scene while lights lived
inside it, which was two answers to one question. `add_mesh` is the
counterpart of `add_light`, and `Renderer.render(scene, assets, camera)` reads
both from here.

**Fog is scene content as well.** three.js's `scene.fog` is a field on the
scene, read by the renderer, and so is `fog` here: `no_fog()` to begin
with, and `linear_fog` or `exp2_fog` to set. See `core.fog`.

**Nodes can be edited in place.** `node(id)` hands back a mutable reference
and marks the scene stale, which is what `mesh.rotation.y += 0.01` needs: a
persistent scene, one field changed, one `update`, one render. Before it
existed every example rebuilt its entire scene each frame, because copying a
node out with `get` and putting it back with `set` was more ceremony than
starting over.

The two arrays are named with a leading underscore. Mojo does not enforce
private fields, so that is a convention and not a guarantee — `validate` exists
to catch the case where something reached past it anyway, and `update` runs it
first, because a mutable reference to a node is also a way past it.
"""

from core.background import Background, no_background
from core.fog import Fog, no_fog
from core.object3d import NO_PARENT, NodeId, Object3D, facing
from lights.light import Light
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.cube_texture_store import NO_CUBE_TEXTURE, CubeTextureId
from units.si import Length, METER
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.line import Line
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skinned_mesh import SkinnedMesh
from objects.sprite import Sprite


struct Scene(Movable):
    """A scene graph held as a parent-before-child array of nodes."""

    var _nodes: List[Object3D]
    var _world: List[Matrix4]
    # What lights the scene. Public because it is read-only content rather
    # than a derived cache: a light is scene content in three.js too, where
    # `scene.add` takes one. Kept here rather than on the renderer so a scene
    # can have more than one, and so a light can be carried by a node -- see
    # `lights.light`.
    var lights: List[Light]
    # What the scene draws, each naming a node here and a geometry and
    # material in an `Assets`. Public for the reason `lights` is, and
    # assignable, so a caller comparing two draw lists against one scene can
    # swap them without rebuilding it.
    var meshes: List[Mesh]
    # The other things the scene draws, each naming a node here as a mesh
    # does: one geometry at many transforms, many geometries at many
    # transforms, and one of several geometries by distance. Public and
    # assignable for the reason `meshes` is. See `objects.instanced_mesh`
    # and `objects.lod`.
    var instanced_meshes: List[InstancedMesh]
    var batched_meshes: List[BatchedMesh]
    var lods: List[Lod]
    # Meshes carried by bones rather than by their node alone. Their own
    # list because a skinned mesh owns a skeleton and so is moved in
    # rather than copied, exactly as an instanced mesh is. See
    # `objects.skinned_mesh`.
    var skinned_meshes: List[SkinnedMesh]
    # The paths and sticks the scene draws one pixel wide, each naming a
    # node here as a mesh does. Their own list because they are prepared
    # by their own pass and rasterized by their own rule: a line has no
    # surface, so almost nothing a triangle carries applies to it. Public
    # and assignable for the reason `meshes` is. See `objects.line`.
    var lines: List[Line]
    # The vertices the scene draws as squares of pixels, each naming a
    # node here as a mesh does. Their own list for the reason the lines
    # have one: a point is its own primitive, with its own pass and its
    # own rule. See `objects.points`.
    var points: List[Points]
    # The camera-facing squares, each naming a node here. Their own list
    # because a sprite names no geometry: it is drawn as two triangles
    # the renderer builds for it. See `objects.sprite`.
    var sprites: List[Sprite]
    # What veils the scene with distance, three.js's `scene.fog`. Public
    # and assignable, as the lights are: set it to the value `linear_fog`
    # or `exp2_fog` returns, and the renderer reads it every frame.
    var fog: Fog
    # What shows where nothing is drawn, three.js's `scene.background`.
    # Public and assignable, as the fog is: set it to the value
    # `color_background`, `texture_background` or `cube_background`
    # returns, and the renderer reads it every frame. See `core.background`.
    var background: Background
    # The cube texture a material reflects when its `env_map` is
    # `SCENE_ENVIRONMENT`, three.js's `scene.environment`, or
    # `NO_CUBE_TEXTURE` for none. Public and assignable for the same reason.
    var environment: CubeTextureId
    # False only when every world matrix reflects every node as it stands.
    var _stale: Bool

    def __init__(out self):
        """Create an empty scene."""
        self._nodes = List[Object3D]()
        self._world = List[Matrix4]()
        self.lights = List[Light]()
        self.meshes = List[Mesh]()
        self.instanced_meshes = List[InstancedMesh]()
        self.batched_meshes = List[BatchedMesh]()
        self.lods = List[Lod]()
        self.skinned_meshes = List[SkinnedMesh]()
        self.lines = List[Line]()
        self.points = List[Points]()
        self.sprites = List[Sprite]()
        self.fog = no_fog()
        self.background = no_background()
        self.environment = NO_CUBE_TEXTURE
        # An empty scene has nothing to recompute, so it starts current.
        self._stale = False

    def count(self) -> Int:
        """Return how many nodes the scene holds."""
        return len(self._nodes)

    def add_mesh(mut self, mesh: Mesh) raises:
        """Add something to draw.

        Does not make the scene stale: a mesh holds no transform of its own,
        only the id of a node that does, exactly as a light does.

        Args:
            mesh: The mesh to draw. Its node must already be in the scene;
                its geometry and material are checked when rendered, because
                the scene has no view of the `Assets` they live in.

        Raises:
            Error: If the mesh names a node the scene does not have.
        """
        if mesh.node.value >= len(self._nodes):
            raise Error("A mesh must name a node that is in the scene")
        self.meshes.append(mesh)

    def add_instanced_mesh(mut self, var mesh: InstancedMesh) raises:
        """Add one geometry to draw at many transforms, three.js's
        `scene.add(instancedMesh)`.

        Args:
            mesh: The instanced mesh, consumed. Its node must already be
                in the scene; its geometry and material are checked when
                rendered.

        Raises:
            Error: If it names a node the scene does not have.
        """
        if mesh.node.value >= len(self._nodes):
            raise Error(
                "An instanced mesh must name a node that is in the scene"
            )
        self.instanced_meshes.append(mesh^)

    def add_batched_mesh(mut self, var mesh: BatchedMesh) raises:
        """Add many geometries to draw at many transforms under one
        material, three.js's `scene.add(batchedMesh)`.

        Args:
            mesh: The batched mesh, consumed. Its node must already be in
                the scene; its geometries and material are checked when
                rendered.

        Raises:
            Error: If it names a node the scene does not have.
        """
        if mesh.node.value >= len(self._nodes):
            raise Error("A batched mesh must name a node that is in the scene")
        self.batched_meshes.append(mesh^)

    def add_lod(mut self, var lod: Lod) raises:
        """Add a level-of-detail object, three.js's `scene.add(lod)`.

        Args:
            lod: The LOD, consumed. Its node must already be in the scene;
                its levels' geometries and materials are checked when the
                level is rendered.

        Raises:
            Error: If it names a node the scene does not have.
        """
        if lod.node.value >= len(self._nodes):
            raise Error("An LOD must name a node that is in the scene")
        self.lods.append(lod^)

    def add_skinned_mesh(mut self, var mesh: SkinnedMesh) raises:
        """Add a mesh carried by bones, three.js's
        `scene.add(skinnedMesh)`.

        Args:
            mesh: The skinned mesh, consumed. Its node and every one of
                its bones must already be in the scene; its geometry, its
                material and its skin attributes are checked when it is
                rendered.

        Raises:
            Error: If it names a node the scene does not have, or one of
                its bones does.
        """
        if mesh.node.value >= len(self._nodes):
            raise Error("A skinned mesh must name a node that is in the scene")
        for index in range(mesh.bone_count()):  # pragma: no branch
            var bone = mesh.skeleton.node(index)
            if bone.value < 0 or bone.value >= len(self._nodes):
                raise Error("A bone must name a node that is in the scene")
        self.skinned_meshes.append(mesh^)

    def add_line(mut self, line: Line) raises:
        """Add a path or a list of sticks to draw, the three.js
        `scene.add(line)`.

        Does not make the scene stale, for the reason `add_mesh` does not:
        a line holds no transform of its own, only the id of a node that
        does.

        Args:
            line: The line to draw. Its node must already be in the scene.
                Its geometry and material are checked when it is rendered,
                because the scene has no view of the `Assets` they live in.

        Raises:
            Error: If the line names a node the scene does not have.
        """
        if line.node.value >= len(self._nodes):
            raise Error("A line must name a node that is in the scene")
        self.lines.append(line)

    def add_points(mut self, points: Points) raises:
        """Add vertices to draw as squares of pixels, the three.js
        `scene.add(points)`.

        Does not make the scene stale, for the reason `add_mesh` does not.

        Args:
            points: The points to draw. Their node must already be in the
                scene. Their geometry and material are checked when they
                are rendered, because the scene has no view of the
                `Assets` they live in.

        Raises:
            Error: If the points name a node the scene does not have.
        """
        if points.node.value >= len(self._nodes):
            raise Error("Points must name a node that is in the scene")
        self.points.append(points)

    def add_sprite(mut self, sprite: Sprite) raises:
        """Add a camera-facing square to draw, the three.js
        `scene.add(sprite)`.

        Does not make the scene stale, for the reason `add_mesh` does not.

        Args:
            sprite: The sprite to draw. Its node must already be in the
                scene. Its material is checked when it is rendered.

        Raises:
            Error: If the sprite names a node the scene does not have.
        """
        if sprite.node.value >= len(self._nodes):
            raise Error("A sprite must name a node that is in the scene")
        self.sprites.append(sprite)

    def node(
        mut self, index: NodeId
    ) raises -> ref[origin_of(self._nodes[0])] Object3D:
        """Return the node at `index`, for editing in place.

        The three.js way to move something -- change a field on the object
        and render again -- and what `get` followed by `set` was standing in
        for. A mutable reference means the scene cannot see what is done
        through it, so it is marked stale on the way out and the next
        `update` recomputes everything. A caller that only wants to look
        should use `get`, which costs nothing later.

        Args:
            index: Which node to edit.

        Returns:
            A reference to it, valid as long as the scene is not otherwise
            touched.

        Raises:
            Error: If the index is out of range.
        """
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")
        self._stale = True
        return self._nodes[index.value]

    def add_light(mut self, light: Light):
        """Add a light to the scene.

        Unlike `add`, this does not make the scene stale: a light holds no
        transform of its own, only the id of a node that does, so adding one
        cannot invalidate a world matrix.

        Args:
            light: The light to add. Build one with `ambient_light` or
                `directional_light`.
        """
        self.lights.append(light)

    def is_stale(self) -> Bool:
        """Return True if a node has changed since the last `update`."""
        return self._stale

    def add(mut self, var node: Object3D) raises -> NodeId:
        """Add `node` and return the index it was given.

        Args:
            node: The node to add; its `parent` must already be in the scene.

        Returns:
            The new node's index, usable as a parent for later nodes.

        Raises:
            Error: If the parent index is not an existing earlier node.
        """
        if node.parent != NO_PARENT:
            if node.parent.value < 0 or node.parent.value >= len(self._nodes):
                raise Error("A node's parent must already be in the scene")
        self._nodes.append(node^)
        self._world.append(Matrix4())
        self._stale = True
        return NodeId(len(self._nodes) - 1)

    def attach(mut self, var node: Object3D, parent: NodeId) raises -> NodeId:
        """Add `node` as a child of `parent` and return its index.

        Args:
            node: The node to add.
            parent: Index of an existing node to attach it to.

        Returns:
            The new node's index.

        Raises:
            Error: If `parent` is not an existing earlier node.
        """
        node.parent = parent
        return self.add(node^)

    def get(self, index: NodeId) raises -> Object3D:
        """Return a copy of the node at `index`.

        A copy rather than a reference, so editing it does not silently change
        the scene behind `update`'s back. Put it back with `set`.

        Args:
            index: Which node to read.

        Returns:
            A copy of that node.

        Raises:
            Error: If the index is out of range.
        """
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")
        return Object3D(copy=self._nodes[index.value])

    def set(mut self, index: NodeId, var node: Object3D) raises:
        """Replace the node at `index`, keeping its place in the order.

        Args:
            index: Which node to replace.
            node: Its replacement.

        Raises:
            Error: If the index is out of range, or the replacement's parent
                is not earlier in the array, which would break the ordering
                the single-pass update depends on.
        """
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")
        # Both halves matter. `>= index` keeps the parent-before-child order
        # the single-pass update depends on; `< 0` catches a parent that is
        # neither NO_PARENT nor a real node, which `add` already refuses.
        # Without it a parent of -2 reached `self._world[parent]` in `update`.
        if node.parent != NO_PARENT:
            if node.parent.value < 0 or node.parent.value >= index.value:
                raise Error("A node's parent must be an earlier existing node")
        self._nodes[index.value] = node^
        self._stale = True

    def look_at(
        mut self, index: NodeId, target: Vector3, *, camera: Bool = False
    ) raises:
        """Turn a node to face a point given in *world* space.

        `Object3D.look_at` works in the node's parent frame, which is only
        the world for a root node. This does what three.js's `lookAt` does:
        builds the facing in world space -- where the node is, what it should
        face, and which way is up, all in world terms -- and then undoes the
        parent's rotation to get the node's own. It is why a camera parented
        to a moving pivot can still be told to watch the origin.

        The first version of this took the *target* into the parent's frame
        and built the basis there. That carries the target across correctly
        and the up direction not at all: it stays the parent's +y, so a
        parent rolled about z rolled the child's view with it, and a parent
        that swapped the axes round could make an ordinary view look like
        one straight along up and refuse it.

        The parent's world transform must be a rotation and a positive
        uniform scale. three.js normalizes the parent's axes and carries on,
        which aims the child wrong whenever the parent's scale is not
        uniform: the child's own axes are stretched unequally on the way
        back into the world, and only a direction along one of the parent's
        axes survives that. This refuses such a parent instead.

        Args:
            index: Which node to turn.
            target: The point to face, in world space.
            camera: True to face it the way a camera does; see
                `Object3D.look_at`.

        Raises:
            Error: If the index is out of range; the scene is stale, since
                the node's and its parent's world matrices have to be
                current; the parent's world transform is not a rotation and
                a positive uniform scale -- a nonuniform scale, a shear, a
                mirror or a flattened axis leaves no frame the facing
                survives the trip into; or the target leaves the orientation
                undefined.
        """
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")
        var eye = self.world_position(index)
        var desired = facing(eye, target, Vector3(0, 1, 0), camera)
        var parent = self._nodes[index.value].parent
        if parent != NO_PARENT:
            var frame = self.world_matrix(parent)
            # The facing was built in the world, and only a rotation and a
            # uniform scale carry it into the parent's frame unchanged. A
            # parent scaled (2, 1, 1) bends every direction that is not
            # along one of its axes: a child at its origin told to face
            # (1, 1, 0) would face (2, 1, 0) instead, eighteen degrees off.
            # Normalizing the axes and carrying on, as three.js does, gives
            # exactly that wrong answer.
            if not frame.is_scaled_rotation():
                raise Error(
                    "A parent must be a rotation and a uniform scale for the"
                    " facing to be defined: no nonuniform scale, shear or"
                    " mirror"
                )
            var undo = Quaternion.from_matrix(frame.extract_rotation())
            desired.premultiply(undo.conjugate())
        self.node(index).set_quaternion(desired)

    def update(mut self) raises:
        """Recompute every node's world matrix.

        One forward pass is enough: a parent always sits earlier in the array,
        so its world matrix is already final by the time a child is reached.

        Validates first. Every other mutation checks the parent links as it
        goes, but a reference from `node` can set one to anything, and the
        pass below indexes by it.

        Raises:
            Error: If a node's parent link no longer points at an earlier
                node, or a node's local matrix cannot be built.
        """
        self.validate()
        for index in range(len(self._nodes)):
            var local = self._nodes[index].local_matrix()
            var parent = self._nodes[index].parent
            if parent == NO_PARENT:
                self._world[index] = local^
            else:
                var combined = Matrix4(copy=self._world[parent.value])
                combined.multiply(local)
                self._world[index] = combined^
        self._stale = False

    def update_lods(mut self, eye: Vector3) raises:
        """Choose every LOD's level for a camera at `eye`, and remember the
        choices: three.js's `LOD.update(camera)`, for the whole scene.

        The renderer measures the same distance and reads the memory, so a
        frame drawn after this shows what this chose, hysteresis included.
        A scene never given this shows the stateless choice.

        Args:
            eye: The camera's position in world space.

        Raises:
            Error: If the scene is stale, or an LOD names a node that is
                not there.
        """
        for index in range(len(self.lods)):
            var distance = Length(
                (eye - self.world_position(self.lods[index].node)).length(),
                METER,
            )
            _ = self.lods[index].update(distance)

    def validate(self) raises:
        """Check the invariants the single-pass update relies on.

        Nothing in normal use can break these — every mutation goes through a
        method that checks — so this is for tests and for the day something
        reaches past the underscore on `_nodes`.

        Raises:
            Error: If the two arrays have drifted apart, or any node's parent
                is not an earlier valid node.
        """
        if len(self._nodes) != len(self._world):
            raise Error("Scene node and world arrays have different lengths")
        for index in range(len(self._nodes)):
            var parent = self._nodes[index].parent
            if parent == NO_PARENT:
                continue
            if parent.value < 0 or parent.value >= index:
                raise Error("A node's parent must be an earlier existing node")

    def world_matrix(self, index: NodeId) raises -> Matrix4:
        """Return the world transform computed for `index` by `update`.

        Args:
            index: Which node to read.

        Returns:
            That node's world matrix.

        Raises:
            Error: If the index is out of range, or the scene has changed
                since `update` was last called — see the module docstring.
        """
        if index.value < 0 or index.value >= len(self._world):
            raise Error("Scene node index out of range")
        if self._stale:
            raise Error(
                "The scene has changed since update(); call scene.update()"
                " before reading a world matrix"
            )
        return Matrix4(copy=self._world[index.value])

    def world_position(self, index: NodeId) raises -> Vector3:
        """Return where `index` sits in world space.

        Args:
            index: Which node to read.

        Returns:
            The node's origin transformed into world space.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        return self.world_matrix(index).transform_point(Vector3(0, 0, 0))
