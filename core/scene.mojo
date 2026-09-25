# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The flat array of nodes that makes up a scene graph.

three.js walks a tree of objects to update world matrices. Here the nodes live
in one array and each records its parent's index, because Mojo will not let a
struct hold a `List` of itself — see `core.object3d`.

**A node's id is its place in the array, and it never changes.** Every
mesh, light, bone and animation track names its node by id, so an id that
moved would move them all. Nothing is ever taken out of the array.

**The order of the tree is kept beside the array.** A node can be moved
under any other node, an older one or a newer one, as three.js's `add`
and `attach` move it. `_sequence` lists every node in the order it became
a child, which is the order three.js's `children` array keeps, and
`update` walks the tree from the roots in that order: a parent first, then
each child's subtree in turn, three.js's `traverse`. That walk is one
forward pass with each parent finished before its children, as before,
and it finds a loop that a reference from `node` has made: a node on a
loop is never reached from a root.

**A removed node stays in the array, out of the scene.** `remove`,
`remove_from_parent` and `clear` take a node off its parent, as three.js
does, and mark it removed. It keeps its id, its children and its world
matrix, but it is not shown: the renderer does not draw what it carries,
the raycaster does not hit it, the lights on it do not shine, the
animation mixer does not move it, the exporters do not write it, and
`traverse` and `find` do not reach it. Adding it back with `add` or
`attach` undoes all of that. `clone` makes a removed copy, as three.js's
`clone` makes one with no parent, for the caller to add. A scene that
removes a node every frame grows by one node every frame. Build a new
scene when that matters.

**Stale transforms are refused, not served.** World matrices are cached by
`update` and read back by `world_matrix`. Any edit invalidates them, and
reading one before recomputing raises rather than handing back a matrix from
before the edit. The alternative — recompute automatically on read — hides
how much work a render costs and recomputes the whole scene for one lookup.
The alternative it replaces, serving the stale value, is worse than both: it
produces a plausible wrong image and no error at all. `attach` is the one
exception: it needs world matrices at once, as three.js's does, and works
them out from the parents rather than asking for an `update`.

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
from core.layers import Layers
from core.object3d import (
    GYROSCOPE_TYPE,
    NO_PARENT,
    NodeId,
    Object3D,
    facing,
    scale_of,
)
from lights.light import Light
from materials.material import MaterialId
from math.matrix4 import Matrix4, compose
from math.quaternion import Quaternion
from math.euler import XYZ, Euler
from math.vector3 import Vector3
from render.cube_texture import check_rotation
from render.cube_texture_store import NO_CUBE_TEXTURE, CubeTextureId
from std.math import isfinite
from units.si import RADIAN, Angle, Length, METER
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.line import Line
from objects.line_segments2 import LineSegments2
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skinned_mesh import SkinnedMesh
from objects.sprite import Sprite

# No turn at all: the angle an environment rotation starts at.
comptime ZERO_ANGLE = Angle(0.0, RADIAN)


struct _Links(Movable):
    """Every node's children, in order, and the roots, in order: the
    `children` arrays three.js keeps, worked out from the parent links."""

    # Node `k`'s children are `kids[first[k]]` up to `kids[first[k + 1]]`.
    var first: List[Int]
    var kids: List[Int]
    # The nodes with no parent, removed ones included.
    var roots: List[Int]

    def __init__(
        out self,
        var first: List[Int],
        var kids: List[Int],
        var roots: List[Int],
    ):
        """Keep the three lists."""
        self.first = first^
        self.kids = kids^
        self.roots = roots^


struct Scene(Movable):
    """A scene graph held as a flat array of nodes, each naming its parent."""

    var _nodes: List[Object3D]
    var _world: List[Matrix4]
    # Whether each node is shown: visible, in the scene, and every ancestor
    # visible. Derived by `update`, as the world matrices are.
    var _shown: List[Bool]
    # True for a node `remove` took off its parent. Its children stay under
    # it, and are out of the scene with it.
    var _removed: List[Bool]
    # Every node, in the order it became a child: three.js's `children`
    # order, and the order of the roots. `add` of a node already here moves
    # it to the end, as three.js's `add` pushes it.
    var _sequence: List[Int]
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
    # The lines drawn wider than a pixel, each naming a node here. Their
    # own list because they are drawn as triangles the renderer builds
    # for them, where a `Line` is drawn by the line pass. See
    # `objects.line_segments2`.
    var wide_lines: List[LineSegments2]
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
    # How blurred a cube or panorama background is, from zero to one,
    # three.js's `backgroundBlurriness`: above zero the background is read
    # from its PMREM at this roughness. What it is multiplied by,
    # `backgroundIntensity`, and how it is turned, `backgroundRotation`.
    # Checked by `validate_environment`.
    var background_blurriness: Float32
    var background_intensity: Float32
    var background_rotation: Euler
    # What a standard or physical surface that reflects the scene's
    # environment multiplies it by, three.js's `environmentIntensity`, in
    # place of its own `env_map_intensity`, and how it is turned,
    # `environmentRotation`, in place of its own `env_map_rotation`.
    var environment_intensity: Float32
    var environment_rotation: Euler
    # The material every object is drawn with in place of its own,
    # three.js's `scene.overrideMaterial`, or `None` for each object's
    # own. An object whose material turns `allow_override` off keeps its
    # own. Shadow maps are not drawn with it, as in three.js.
    var override_material: Optional[MaterialId]
    # False only when every world matrix reflects every node as it stands.
    var _stale: Bool

    def __init__(out self):
        """Create an empty scene."""
        self._nodes = List[Object3D]()
        self._world = List[Matrix4]()
        self._shown = List[Bool]()
        self._removed = List[Bool]()
        self._sequence = List[Int]()
        self.lights = List[Light]()
        self.meshes = List[Mesh]()
        self.instanced_meshes = List[InstancedMesh]()
        self.batched_meshes = List[BatchedMesh]()
        self.lods = List[Lod]()
        self.skinned_meshes = List[SkinnedMesh]()
        self.lines = List[Line]()
        self.points = List[Points]()
        self.sprites = List[Sprite]()
        self.wide_lines = List[LineSegments2]()
        self.fog = no_fog()
        self.background = no_background()
        self.environment = NO_CUBE_TEXTURE
        self.background_blurriness = 0
        self.background_intensity = 1
        self.background_rotation = Euler(
            ZERO_ANGLE, ZERO_ANGLE, ZERO_ANGLE, XYZ
        )
        self.environment_intensity = 1
        self.environment_rotation = Euler(
            ZERO_ANGLE, ZERO_ANGLE, ZERO_ANGLE, XYZ
        )
        self.override_material = None
        # An empty scene has nothing to recompute, so it starts current.
        self._stale = False

    def validate_environment(self) raises:
        """Refuse a background or environment setting the renderer could
        not use. The fields are open, so the renderer asks this every
        frame, as it asks `Background.validate`.

        Raises:
            Error: If `background_blurriness` is outside zero to one or not
                finite, either intensity is negative or not finite, or
                either rotation is refused by `check_rotation`.
        """
        var blur = self.background_blurriness
        if not isfinite(blur) or blur < 0 or blur > 1:
            raise Error("A background blurriness must be between zero and one")
        var shown = self.background_intensity
        if not isfinite(shown) or shown < 0:
            raise Error("A background intensity cannot be negative")
        var lit = self.environment_intensity
        if not isfinite(lit) or lit < 0:
            raise Error("An environment intensity cannot be negative")
        check_rotation(self.background_rotation, "A background rotation")
        check_rotation(self.environment_rotation, "An environment rotation")

    def count(self) -> Int:
        """Return how many nodes the scene holds, removed ones included.

        Every id below this names a node, so this is the bound for a loop
        over ids. Ask `in_scene` which of them are in the scene.
        """
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

        Each level's node becomes a child of the LOD's node, as three.js's
        `addLevel` makes it one, and keeps its own transform. The level
        `shown` names is shown and the others are hidden, which is what a
        scene shows until `update_lods`.

        Args:
            lod: The LOD, consumed. Its node and its levels' nodes must
                already be in the scene.

        Raises:
            Error: If it names a node the scene does not have, or a level
                cannot go under the LOD's node: the LOD's node is under it.
        """
        if lod.node.value >= len(self._nodes):
            raise Error("An LOD must name a node that is in the scene")
        var above = self._chain(lod.node)
        for level in lod.levels:
            if level.object.value >= len(self._nodes):
                raise Error(
                    "An LOD level must name a node that is in the scene"
                )
            if level.object.value in above:
                raise Error(
                    "A node cannot go under itself or its own descendant"
                )
        for level in lod.levels:
            self.add(level.object, parent=lod.node)
        self.lods.append(lod^)
        self._show_level(len(self.lods) - 1)

    def add_lod_level(
        mut self,
        index: Int,
        object: NodeId,
        distance: Length = Length(0.0, METER),
        hysteresis: Float32 = 0,
    ) raises:
        """Add a level to an LOD in the scene, three.js's `lod.addLevel`:
        the node becomes a child of the LOD's node, and the level shown
        stays shown.

        Args:
            index: Which LOD, as its position in `lods`.
            object: The node to show from `distance` on.
            distance: How far the camera must be for this level to show.
            hysteresis: The level's hysteresis; see `Lod.add_level`.

        Raises:
            Error: If no LOD has that index, the node is not in the scene
                or cannot go under the LOD's node, or for anything
                `Lod.add_level` raises for.
        """
        if index < 0 or index >= len(self.lods):
            raise Error("No LOD has that index")
        self._check(object)
        var holder = self.lods[index].node
        if object.value in self._chain(holder):
            raise Error("A node cannot go under itself or its own descendant")
        self.lods[index].add_level(object, distance, hysteresis)
        self.add(object, parent=holder)
        self._show_level(index)

    def remove_lod_level(mut self, index: Int, distance: Length) raises -> Bool:
        """Remove the first level of an LOD at a distance, and take its
        node off the LOD's node, three.js's `lod.removeLevel`.

        Args:
            index: Which LOD, as its position in `lods`.
            distance: The level's distance, exactly.

        Returns:
            True if a level was removed.

        Raises:
            Error: If no LOD has that index.
        """
        if index < 0 or index >= len(self.lods):
            raise Error("No LOD has that index")
        var removed = self.lods[index].remove_level(distance)
        if not removed:
            return False
        var holder = self.lods[index].node
        self.remove(removed.value(), parent=holder)
        self._show_level(index)
        return True

    def _show_level(mut self, index: Int):
        """Show the level an LOD has chosen and hide the others, as
        three.js's `LOD.update` sets each level object's `visible`."""
        ref lod = self.lods[index]
        for level in range(len(lod.levels)):
            ref node = self._nodes[lod.levels[level].object.value]
            var shown = level == lod.shown
            # Only a change leaves the scene to be updated again.
            if node.visible != shown:
                node.visible = shown
                self._stale = True

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

    def add_wide_line(mut self, line: LineSegments2) raises:
        """Add a line wider than a pixel to draw, the three.js
        `scene.add(line2)`.

        Does not make the scene stale, for the reason `add_mesh` does not.

        Args:
            line: The `LineSegments2` or `Line2` to draw. Its node must
                already be in the scene. Its geometry and material are
                checked when it is rendered.

        Raises:
            Error: If the line names a node the scene does not have.
        """
        if line.node.value >= len(self._nodes):
            raise Error("A wide line must name a node that is in the scene")
        self.wide_lines.append(line)

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
            The new node's index, usable as a parent for later nodes. It is
            one more than the last, and never changes.

        Raises:
            Error: If the parent index names no node, or the node's
                `object_type` is none of the three there are.
        """
        self._check_parent(node.parent)
        _check_type(node)
        var id = len(self._nodes)
        self._nodes.append(node^)
        self._world.append(Matrix4())
        self._removed.append(False)
        self._sequence.append(id)
        self._stale = True
        return NodeId(id)

    def attach(mut self, var node: Object3D, parent: NodeId) raises -> NodeId:
        """Add `node` as a child of `parent` and return its index.

        Args:
            node: The node to add.
            parent: Index of an existing node to attach it to.

        Returns:
            The new node's index.

        Raises:
            Error: If `parent` names no node, or the node's `object_type`
                is none of the three there are.
        """
        node.parent = parent
        return self.add(node^)

    def add(mut self, child: NodeId, *, parent: NodeId = NO_PARENT) raises:
        """Move a node that is already here under `parent`, three.js's
        `parent.add(child)`.

        The node keeps its own position, rotation and scale, which now
        count from its new parent, so it moves in the world with the
        change, as there. It becomes the parent's last child. A removed
        node comes back into the scene, with everything under it.

        Args:
            child: The node to move.
            parent: Its new parent, older or newer than it, or `NO_PARENT`
                for the scene itself, three.js's `scene.add(child)`.

        Raises:
            Error: If either names no node, or `parent` is the child or
                under it. three.js adds a node under its own descendant
                and makes a loop that nothing can draw; this refuses.
        """
        self._check(child)
        self._check_parent(parent)
        if child.value in self._chain(parent):
            raise Error("A node cannot go under itself or its own descendant")
        self._nodes[child.value].parent = parent
        self._removed[child.value] = False
        for at in range(len(self._sequence)):  # pragma: no branch
            if self._sequence[at] == child.value:
                _ = self._sequence.pop(at)
                break
        self._sequence.append(child.value)
        self._stale = True

    def attach(mut self, child: NodeId, *, parent: NodeId = NO_PARENT) raises:
        """Move a node under `parent` and keep where it is in the world,
        three.js's `parent.attach(child)`.

        The node's transform is premultiplied by the inverse of the new
        parent's world transform and the old parent's world transform, as
        there. Those are worked out from the parents at once, so the scene
        need not be current. As in three.js, a node under a nonuniform
        scale can come out sheared, and a shear is not kept: see
        `Object3D.apply_matrix4`.

        Args:
            child: The node to move.
            parent: Its new parent, or `NO_PARENT` for the scene itself,
                three.js's `scene.attach(child)`.

        Raises:
            Error: If either names no node, `parent` is the child or under
                it, a parent link names no node or loops, or the result
                flattens an axis, which a flattened new parent does. The
                scene is left as it was.
        """
        self._check(child)
        self._check_parent(parent)
        if child.value in self._chain(parent):
            raise Error("A node cannot go under itself or its own descendant")
        var carry = self._world_now(parent)
        carry.invert()
        carry.multiply(self._world_now(self._nodes[child.value].parent))
        var moved = self._nodes[child.value]
        moved.apply_matrix4(carry)
        self._nodes[child.value] = moved^
        self.add(child, parent=parent)

    def detach(mut self, child: NodeId) raises:
        """Move a node to the top of the scene and keep where it is in the
        world: `attach` with no parent, three.js's `scene.attach(child)`.

        Args:
            child: The node to move.

        Raises:
            Error: For anything `attach` raises for.
        """
        self.attach(child, parent=NO_PARENT)

    def remove(mut self, child: NodeId, *, parent: NodeId = NO_PARENT) raises:
        """Take a node off `parent`, three.js's `parent.remove(child)`.

        Nothing happens when the node is not one of the parent's children,
        as there: `remove(node)` alone takes off a node at the top of the
        scene and leaves a deeper one where it is. See the module
        docstring for what a removed node is.

        Args:
            child: The node to take off.
            parent: The parent it is on, or `NO_PARENT` for the scene
                itself.

        Raises:
            Error: If either names no node.
        """
        self._check(child)
        self._check_parent(parent)
        if self._nodes[child.value].parent != parent:
            return
        if self._removed[child.value]:
            return
        self._take_out(child.value)

    def remove_from_parent(mut self, child: NodeId) raises:
        """Take a node off whatever parent it has, three.js's
        `removeFromParent`.

        Args:
            child: The node to take off. Nothing happens when it is
                removed already.

        Raises:
            Error: If it names no node.
        """
        self._check(child)
        if not self._removed[child.value]:
            self._take_out(child.value)

    def clear(mut self, parent: NodeId = NO_PARENT) raises:
        """Take off every child of `parent`, three.js's `clear`.

        Args:
            parent: The node to empty, or `NO_PARENT` to take every node
                off the top of the scene, three.js's `scene.clear()`.

        Raises:
            Error: If it names no node.
        """
        for child in self.children(parent):
            self._take_out(child.value)

    def _take_out(mut self, child: Int):
        """Take a node off its parent and out of the scene."""
        self._nodes[child].parent = NO_PARENT
        self._removed[child] = True
        self._stale = True

    def in_scene(self, index: NodeId) raises -> Bool:
        """Return True if neither a node nor any node above it is removed.

        Needs no `update`: it walks the parents as they are now.

        Args:
            index: The node, or `NO_PARENT` for the scene itself, which
                is always in it.

        Returns:
            Whether the node is in the scene.

        Raises:
            Error: If it names no node, or a parent link names no node or
                loops.
        """
        self._check_start(index)
        for node in self._chain(index):
            if self._removed[node]:
                return False
        return True

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
        self._check(index)
        return Object3D(copy=self._nodes[index.value])

    def set(mut self, index: NodeId, var node: Object3D) raises:
        """Replace the node at `index`, keeping its id.

        A new parent makes the node that parent's last child, as `add`
        does. A removed node stays removed; `add` brings it back.

        Args:
            index: Which node to replace.
            node: Its replacement.

        Raises:
            Error: If the index is out of range, the replacement's parent
                names no node or is the node itself or under it, or its
                `object_type` is none of the three there are.
        """
        self._check(index)
        self._check_parent(node.parent)
        _check_type(node)
        var parent = node.parent
        var moved = parent != self._nodes[index.value].parent
        if index.value in self._chain(parent):
            raise Error("A node cannot go under itself or its own descendant")
        var removed = self._removed[index.value]
        self._nodes[index.value] = node^
        if moved:
            self.add(index, parent=parent)
            self._removed[index.value] = removed
        self._stale = True

    def look_at(
        mut self, index: NodeId, target: Vector3, *, camera: Bool = False
    ) raises:
        """Turn a node to face a point given in *world* space.

        `Object3D.look_at` works in the node's parent frame, which is only
        the world for a root node. This does what three.js's `lookAt` does:
        builds the facing in world space -- where the node is, what it should
        face, and the node's `up`, all in world terms, as three.js reads
        `up` -- and then undoes the parent's rotation to get the node's own. It is why a camera parented
        to a moving pivot can still be told to watch the origin.

        The first version of this took the *target* into the parent's frame
        and built the basis there. That carries the target across correctly
        and the up direction not at all: it stays the parent's +y, so a
        parent rolled about z rolled the child's view with it, and a parent
        that swapped the axes round could make an ordinary view look like
        one straight along up.

        The parent's world transform must be a rotation and a positive
        uniform scale. three.js normalizes the parent's axes and carries on,
        which aims the child wrong whenever the parent's scale is not
        uniform: the child's own axes are stretched unequally on the way
        back into the world, and only a direction along one of the parent's
        axes survives that. This refuses such a parent instead.

        Args:
            index: Which node to turn.
            target: The point to face, in world space.
            camera: True to face it the way a camera or a light does; see
                `Object3D.look_at`.

        Raises:
            Error: If the index is out of range; the scene is stale, since
                the node's and its parent's world matrices have to be
                current; the parent's world transform is not a rotation and
                a positive uniform scale -- a nonuniform scale, a shear, a
                mirror or a flattened axis leaves no frame the facing
                survives the trip into; the node's `up` is zero or not
                finite. A target at the node or straight
                along up is not refused: `facing` settles both, as three.js
                does.
        """
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")
        var eye = self.world_position(index)
        var desired = facing(eye, target, self._nodes[index.value].up, camera)
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

        One pass down the tree from the roots, in `traverse` order, with
        removed nodes as roots of their own: a parent's world matrix is
        final by the time any child is reached, whatever the ids.

        Validates first. Every other mutation checks the parent links as it
        goes, but a reference from `node` can set one to anything, and the
        pass below indexes by it.

        Raises:
            Error: If a node's parent link names no node or loops back to
                it, a node's `object_type` is none of the three there
                are, or a node's local matrix cannot be built.
        """
        self._check_nodes()
        var order = self._order()
        self._shown = List[Bool](length=len(self._nodes), fill=True)
        for index in order:
            ref node = self._nodes[index]
            if node.matrix_auto_update:
                node.matrix = node.local_matrix()
            var parent = node.parent
            var shown = node.visible and not self._removed[index]
            if parent == NO_PARENT:
                self._world[index] = Matrix4(copy=node.matrix)
            elif node.object_type == GYROSCOPE_TYPE:
                self._world[index] = _gyroscope_world(
                    self._world[parent.value], node.matrix
                )
            else:
                var combined = Matrix4(copy=self._world[parent.value])
                combined.multiply(node.matrix)
                self._world[index] = combined^
                shown = shown and self._shown[parent.value]
            self._shown[index] = shown
        self._stale = False

    def is_shown(self, index: NodeId) raises -> Bool:
        """Return True if a node and every node above it are visible.

        Args:
            index: Which node to ask about.

        Returns:
            Whether the renderer draws what the node carries.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        self._check_current(index)
        return self._shown[index.value]

    def shows(self, index: NodeId, visible: Layers) raises -> Bool:
        """Return True if a node is shown and shares a layer with a camera.

        The question the renderer asks of every object before it draws it.
        three.js asks `visible` and `layers.test` in `projectObject`.

        Args:
            index: The object's node.
            visible: The camera's layers.

        Returns:
            Whether the camera draws what the node carries.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        if not self.is_shown(index):
            return False
        return self._nodes[index.value].layers.test(visible)

    def render_order(self, index: NodeId) raises -> Int:
        """Return a node's render order, without copying the node.

        Args:
            index: The node.

        Returns:
            Its `render_order`.

        Raises:
            Error: If the index is out of range.
        """
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")
        return self._nodes[index.value].render_order

    def light_shown(self, light: Light) raises -> Bool:
        """Return True if a light shines: on no node, or on a shown one.

        Args:
            light: The light.

        Returns:
            Whether the light's node, if it has one, is shown.

        Raises:
            Error: If the light names a node that is not there, or the
                scene is stale.
        """
        if light.node == NO_PARENT:
            return True
        return self.is_shown(light.node)

    def find(
        self, name: String, root: NodeId = NO_PARENT
    ) raises -> Optional[NodeId]:
        """Return the first node with a name, three.js's `getObjectByName`.

        Args:
            name: The name.
            root: Where to look: this node and everything under it, or
                `NO_PARENT` for the whole scene.

        Returns:
            The first node so named in `traverse` order, or None.

        Raises:
            Error: For anything `traverse` raises for.
        """
        for node in self.traverse(root):
            if self._nodes[node.value].name == name:
                return node
        return None

    def objects_by_name(
        self, name: String, root: NodeId = NO_PARENT
    ) raises -> List[NodeId]:
        """Return every node with a name, three.js's
        `getObjectsByProperty('name', name)`.

        three.js looks up any property by its name as a string. A Mojo
        struct has no such lookup, so the name has this call of its own;
        `objects_by_property` takes a function that reads any other.

        Args:
            name: The name.
            root: Where to look: this node and everything under it, or
                `NO_PARENT` for the whole scene.

        Returns:
            The nodes so named, in `traverse` order.

        Raises:
            Error: For anything `traverse` raises for.
        """
        var found = List[NodeId]()
        for node in self.traverse(root):
            if self._nodes[node.value].name == name:
                found.append(node)
        return found^

    def object_by_property[
        T: Equatable & ImplicitlyCopyable & Deinitable,
        //,
        property: def(Object3D) thin -> T,
    ](self, value: T, root: NodeId = NO_PARENT) raises -> Optional[NodeId]:
        """Return the first node whose property has a value, three.js's
        `getObjectByProperty`.

        three.js names the property by a string. A Mojo struct has no
        lookup by name, so the property is a function that reads it:
        `object_by_property[render_order_of](3)` with a
        `def render_order_of(node: Object3D) -> Int`.

        Parameters:
            T: The type of the property.
            property: Reads the property from a node.

        Args:
            value: The value to look for, compared with `==`.
            root: Where to look: this node and everything under it, or
                `NO_PARENT` for the whole scene.

        Returns:
            The first such node in `traverse` order, or None.

        Raises:
            Error: For anything `traverse` raises for.
        """
        for node in self.traverse(root):
            if property(self._nodes[node.value]) == value:
                return node
        return None

    def objects_by_property[
        T: Equatable & ImplicitlyCopyable & Deinitable,
        //,
        property: def(Object3D) thin -> T,
    ](self, value: T, root: NodeId = NO_PARENT) raises -> List[NodeId]:
        """Return every node whose property has a value, three.js's
        `getObjectsByProperty`.

        The property is a function that reads it; see
        `object_by_property`.

        Parameters:
            T: The type of the property.
            property: Reads the property from a node.

        Args:
            value: The value to look for, compared with `==`.
            root: Where to look: this node and everything under it, or
                `NO_PARENT` for the whole scene.

        Returns:
            The nodes, in `traverse` order.

        Raises:
            Error: For anything `traverse` raises for.
        """
        var found = List[NodeId]()
        for node in self.traverse(root):
            if property(self._nodes[node.value]) == value:
                found.append(node)
        return found^

    def object_by_id(
        self, id: NodeId, root: NodeId = NO_PARENT
    ) raises -> Optional[NodeId]:
        """Return a node if it is `root` or under it, three.js's
        `getObjectById`.

        Args:
            id: The node to look for.
            root: Where to look: this node and everything under it, or
                `NO_PARENT` for the whole scene.

        Returns:
            `id`, or None when it is not there: a removed node is not in
            the scene.

        Raises:
            Error: For anything `traverse` raises for.
        """
        for node in self.traverse(root):
            if node == id:
                return node
        return None

    def children(self, index: NodeId) raises -> List[NodeId]:
        """Return a node's direct children, three.js's `children`.

        Args:
            index: The parent, or `NO_PARENT` for the nodes at the top of
                the scene, removed ones left out.

        Returns:
            The nodes whose parent it is, in the order they became its
            children.

        Raises:
            Error: If the index names no node.
        """
        self._check_start(index)
        var found = List[NodeId]()
        for node in self._sequence:
            if self._nodes[node].parent != index:
                continue
            if index == NO_PARENT and self._removed[node]:
                continue
            found.append(NodeId(node))
        return found^

    def traverse(self, root: NodeId = NO_PARENT) raises -> List[NodeId]:
        """Return a node and every node under it, three.js's `traverse`.

        A node comes first, then each child's subtree in turn, in the
        order `children` gives. three.js calls a function on each; here
        the list is the answer, for a loop to call it.

        Args:
            root: Where to start, or `NO_PARENT` for every node in the
                scene. A removed node can be a root: its subtree is walked
                as three.js walks an object with no parent.

        Returns:
            The nodes, each before its descendants.

        Raises:
            Error: If `root` names no node, or a parent link names no node
                or loops.
        """
        return self._walk(root, False)

    def traverse_visible(self, root: NodeId = NO_PARENT) raises -> List[NodeId]:
        """Return the visible nodes from a node down, three.js's
        `traverseVisible`.

        A node that is not `visible` is left out with everything under it,
        the root included.

        Args:
            root: Where to start, or `NO_PARENT` for every node in the
                scene.

        Returns:
            The nodes, each before its descendants.

        Raises:
            Error: For anything `traverse` raises for.
        """
        return self._walk(root, True)

    def traverse_ancestors(self, index: NodeId) raises -> List[NodeId]:
        """Return the nodes above a node, three.js's `traverseAncestors`.

        three.js ends with the scene, which is an object there. Here the
        scene is not a node, so the list ends with the node at the top.

        Args:
            index: The node.

        Returns:
            Its parent, then its parent's parent, and on up.

        Raises:
            Error: If it names no node, or a parent link names no node or
                loops.
        """
        self._check(index)
        var found = List[NodeId]()
        for node in self._chain(self._nodes[index.value].parent):
            found.append(NodeId(node))
        return found^

    def descendants(self, index: NodeId) raises -> List[NodeId]:
        """Return a node and every node under it: `traverse` from a node.

        Args:
            index: Where to start.

        Returns:
            The node, then its descendants, as `traverse` orders them.

        Raises:
            Error: If the index names no node, or for anything `traverse`
                raises for.
        """
        self._check(index)
        return self.traverse(index)

    def update_lods(mut self, eye: Vector3) raises:
        """Choose the level of every LOD whose `auto_update` is set for a
        camera at `eye`, show it and hide the others, then update the
        scene: what three.js's renderer does with `LOD.update(camera)` as
        it draws.

        This renderer does not change the scene it draws, so call this
        before a frame, as `update` is called.

        Args:
            eye: The camera's position in world space.

        Raises:
            Error: If the scene is stale, or an LOD names a node that is
                not there.
        """
        # Every distance is measured before any level changes: showing a
        # level leaves the scene stale, and a stale scene has no world
        # positions to measure the next LOD by.
        var distances = List[Length]()
        for index in range(len(self.lods)):
            distances.append(self._lod_distance(index, eye))
        for index in range(len(self.lods)):
            if self.lods[index].auto_update:
                self._choose_level(index, distances[index])
        self.update()

    def update_lod(mut self, index: Int, eye: Vector3) raises:
        """Choose one LOD's level for a camera at `eye`, show it and hide
        the others, then update the scene: three.js's `LOD.update(camera)`,
        whatever the LOD's `auto_update`.

        Args:
            index: Which LOD, as its position in `lods`.
            eye: The camera's position in world space.

        Raises:
            Error: If no LOD has that index, the scene is stale, or the
                LOD names a node that is not there.
        """
        if index < 0 or index >= len(self.lods):
            raise Error("No LOD has that index")
        self._choose_level(index, self._lod_distance(index, eye))
        self.update()

    def _lod_distance(self, index: Int, eye: Vector3) raises -> Length:
        """How far a camera at `eye` is from one LOD's node."""
        return Length(
            (eye - self.world_position(self.lods[index].node)).length(), METER
        )

    def _choose_level(mut self, index: Int, distance: Length) raises:
        """Choose and show one LOD's level. three.js changes nothing for an
        LOD of one level or none, and neither does this."""
        if self.lods[index].count() < 2:
            return
        _ = self.lods[index].update(distance)
        self._show_level(index)

    def validate(self) raises:
        """Check the invariants the update relies on.

        Nothing in normal use can break these — every mutation goes through a
        method that checks — so this is for tests and for the day something
        reaches past the underscore on `_nodes`, or a reference from `node`
        sets a parent link.

        Raises:
            Error: If the arrays have drifted apart, a node's `object_type`
                is none of the three there are, or a parent link names no
                node or loops back to its node.
        """
        self._check_nodes()
        _ = self._order()

    def _check_nodes(self) raises:
        """Refuse arrays that have drifted apart, or a node of no type."""
        var count = len(self._nodes)
        if (
            len(self._world) != count
            or len(self._removed) != count
            or len(self._sequence) != count
        ):
            raise Error("Scene node and world arrays have different lengths")
        for node in self._nodes:
            _check_type(node)

    def _check(self, index: NodeId) raises:
        """Refuse an index that names no node."""
        if index.value < 0 or index.value >= len(self._nodes):
            raise Error("Scene node index out of range")

    def _check_start(self, index: NodeId) raises:
        """Refuse a node to start from that is neither a node nor
        `NO_PARENT`, the scene itself."""
        if index != NO_PARENT:
            self._check(index)

    def _check_parent(self, parent: NodeId) raises:
        """Refuse a parent that is neither a node nor `NO_PARENT`."""
        if parent != NO_PARENT:
            if parent.value < 0 or parent.value >= len(self._nodes):
                raise Error("A node's parent must already be in the scene")

    def _chain(self, index: NodeId) raises -> List[Int]:
        """Return a node and every node above it, nearest first, or nothing
        for `NO_PARENT`.

        Raises:
            Error: If a link names no node, or the links loop: a chain
                longer than the scene has nodes has come round again.
        """
        var chain = List[Int]()
        var current = index
        while current != NO_PARENT:
            if current.value < 0 or current.value >= len(self._nodes):
                raise Error("A node's parent must be a node in the scene")
            if len(chain) == len(self._nodes):
                raise Error("A node's parents must not loop back to it")
            chain.append(current.value)
            current = self._nodes[current.value].parent
        return chain^

    def _links(self) raises -> _Links:
        """Return every node's children and the roots, in `_sequence`
        order.

        Raises:
            Error: If a parent link names no node.
        """
        var count = len(self._nodes)
        var first = List[Int](length=count + 1, fill=0)
        for node in self._nodes:
            self._check_parent(node.parent)
            if node.parent != NO_PARENT:
                first[node.parent.value + 1] += 1
        for index in range(count):
            first[index + 1] += first[index]
        var fill = first.copy()
        var kids = List[Int](length=first[count], fill=0)
        var roots = List[Int]()
        for index in self._sequence:
            var parent = self._nodes[index].parent
            if parent == NO_PARENT:
                roots.append(index)
            else:
                kids[fill[parent.value]] = index
                fill[parent.value] += 1
        return _Links(first^, kids^, roots^)

    def _walk(self, root: NodeId, visible_only: Bool) raises -> List[NodeId]:
        """Walk the tree from `root`, or from every root in the scene, a
        parent before its children and the children in order.

        Raises:
            Error: If `root` names no node, or a parent link names no node
                or loops.
        """
        self._check_start(root)
        var links = self._links()
        var starts = List[Int]()
        if root == NO_PARENT:
            for node in links.roots:
                if not self._removed[node]:
                    starts.append(node)
        else:
            # A start on a loop is reached again from itself; `_chain`
            # finds that before the walk goes round for ever.
            _ = self._chain(root)
            starts.append(root.value)
        var found = List[NodeId]()
        for node in self._preorder(links, starts, visible_only):
            found.append(NodeId(node))
        return found^

    def _preorder(
        self, links: _Links, starts: List[Int], visible_only: Bool
    ) -> List[Int]:
        """Return the nodes under `starts`, each start's subtree in turn,
        a parent before its children. A node reached from a start on no
        loop is on no loop, so this ends."""
        var found = List[Int]()
        var stack = List[Int]()
        for at in range(len(starts) - 1, -1, -1):
            stack.append(starts[at])
        while len(stack) > 0:
            var node = stack.pop()
            if visible_only and not self._nodes[node].visible:
                continue
            found.append(node)
            var first = links.first[node]
            for at in range(links.first[node + 1] - 1, first - 1, -1):
                stack.append(links.kids[at])
        return found^

    def _order(self) raises -> List[Int]:
        """Return every node, removed ones too, each after its parent.

        Raises:
            Error: If a parent link names no node or loops back to its
                node, which leaves the node unreached from any root.
        """
        var links = self._links()
        var order = self._preorder(links, links.roots, False)
        if len(order) != len(self._nodes):
            raise Error("A node's parents must not loop back to it")
        return order^

    def _world_now(self, index: NodeId) raises -> Matrix4:
        """Return a node's world transform from the parents as they are
        now, or the identity for `NO_PARENT`: three.js's
        `updateWorldMatrix(true, false)`.
        A gyroscope is a plain node here, as three.js's `Gyroscope` does not
        change `updateWorldMatrix`.

        Raises:
            Error: If a parent link names no node or loops.
        """
        var world = Matrix4()
        for index in self._chain(index):
            ref node = self._nodes[index]
            if node.matrix_auto_update:
                world.premultiply(node.local_matrix())
            else:
                world.premultiply(node.matrix)
        return world^

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
        self._check_current(index)
        return Matrix4(copy=self._world[index.value])

    def _check_current(self, index: NodeId) raises:
        """Refuse an index out of range, or a question asked of a stale
        scene."""
        if index.value < 0 or index.value >= len(self._world):
            raise Error("Scene node index out of range")
        if self._stale:
            raise Error(
                "The scene has changed since update(); call scene.update()"
                " before reading a world matrix"
            )

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

    def local_to_world(self, index: NodeId, point: Vector3) raises -> Vector3:
        """Carry a point from a node's own frame into the world, three.js's
        `localToWorld`.

        Args:
            index: The node.
            point: The point, in the node's frame.

        Returns:
            The point, in the world.

        Raises:
            Error: If the index is out of range, or the scene is stale.
                three.js updates the node's world matrix first; here the
                caller calls `update`, as for `world_matrix`.
        """
        return self.world_matrix(index).transform_point(point)

    def world_to_local(self, index: NodeId, point: Vector3) raises -> Vector3:
        """Carry a point from the world into a node's own frame, three.js's
        `worldToLocal`.

        Args:
            index: The node.
            point: The point, in the world.

        Returns:
            The point, in the node's frame. A node whose world transform
            flattens an axis has no inverse, and every point comes back as
            the origin, as three.js's zero inverse gives.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        var undo = self.world_matrix(index)
        undo.invert()
        return undo.transform_point(point)

    def world_quaternion(self, index: NodeId) raises -> Quaternion:
        """Return a node's rotation in the world, three.js's
        `getWorldQuaternion`.

        Args:
            index: The node.

        Returns:
            The rotation `Matrix4.decompose` reads from its world matrix.

        Raises:
            Error: If the index is out of range, the scene is stale, or the
                world matrix flattens an axis, which leaves no rotation.
                three.js returns numbers that are not numbers there.
        """
        var parts = Object3D()
        parts.set_from_matrix(self.world_matrix(index))
        return parts.quaternion

    def world_scale(self, index: NodeId) raises -> Vector3:
        """Return a node's scale in the world, three.js's `getWorldScale`.

        Args:
            index: The node.

        Returns:
            The lengths of the world matrix's axes, the x one negative when
            it mirrors, as `Matrix4.decompose` reads them.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        return scale_of(self.world_matrix(index))

    def world_direction(
        self, index: NodeId, *, camera: Bool = False
    ) raises -> Vector3:
        """Return the way a node faces in the world, three.js's
        `getWorldDirection`.

        An object faces along its +z axis. A camera faces along -z, as
        three.js's `Camera.getWorldDirection` negates it. A light is an
        object here, as there: its direction is +z, although `look_at`
        turns its -z to the target, as three.js's `lookAt` turns a light's.

        Args:
            index: The node.
            camera: True for a camera's direction.

        Returns:
            The world z axis, unit length, negated for a camera. A zero
            axis stays zero.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        var world = self.world_matrix(index)
        var direction = Vector3(
            world.elements[8], world.elements[9], world.elements[10]
        )
        direction.normalize()
        if camera:
            direction = -direction
        return direction

    def clone(
        mut self, source: NodeId, recursive: Bool = True
    ) raises -> NodeId:
        """Copy a node, and what is under it, as new removed nodes,
        three.js's `clone`.

        Every copy is a new node with a new id. The copy of `source` has no
        parent and is removed, as three.js's clone has no parent: add it
        with `add` or `attach`. Its children are copies of the children of
        `source`, in their order, and so on down. What each copied node
        carries is copied onto its copy: meshes, instanced and batched
        meshes, LODs, skinned meshes, lines, points, sprites, wide lines
        and lights. A light whose target is copied aims at the copy, and
        one whose target is not keeps it. A skinned mesh keeps its
        skeleton, as three.js's clone shares it.

        Args:
            source: The node to copy.
            recursive: False to copy the node alone, without its children.

        Returns:
            The copy of `source`.

        Raises:
            Error: If the index is out of range, or for anything `traverse`
                raises for.
        """
        self._check(source)
        var nodes = List[NodeId]()
        if recursive:
            nodes = self.traverse(source)
        else:
            nodes.append(source)
        var copies = List[Int](length=len(self._nodes), fill=-1)
        # `nodes` holds `source` at least, so this runs.
        for old in nodes:  # pragma: no branch
            var node = Object3D(copy=self._nodes[old.value])
            if old == source:
                node.parent = NO_PARENT
            else:
                node.parent = NodeId(copies[node.parent.value])
            copies[old.value] = self.add(node^).value
        self._removed[copies[source.value]] = True
        self._carry(copies)
        return NodeId(copies[source.value])

    def copy(
        mut self, target: NodeId, source: NodeId, recursive: Bool = True
    ) raises:
        """Make one node like another, three.js's `target.copy(source)`.

        The target takes the source's name, transform, layers, visibility,
        render order, matrix settings and user data. It keeps its own
        parent, its place, its `object_type`, as three.js keeps an object's
        class, and what it carries. With `recursive`, a `clone` of each of
        the source's children is added under it, after its own children.

        Args:
            target: The node to change.
            source: The node to copy.
            recursive: False to copy the node alone.

        Raises:
            Error: If either index is out of range, or for anything
                `clone` raises for.
        """
        self._check(target)
        self._check(source)
        var kids = List[NodeId]()
        if recursive:
            kids = self.children(source)
        var node = Object3D(copy=self._nodes[source.value])
        node.parent = self._nodes[target.value].parent
        node.object_type = self._nodes[target.value].object_type
        self._nodes[target.value] = node^
        self._stale = True
        for child in kids:
            self.add(self.clone(child), parent=target)

    def _carry(mut self, copies: List[Int]):
        """Copy what the copied nodes carry onto their copies."""
        for index in range(len(self.meshes)):
            var copy = _copy_of(copies, self.meshes[index].node)
            if copy >= 0:
                var mesh = self.meshes[index]
                mesh.node = NodeId(copy)
                self.meshes.append(mesh)
        for index in range(len(self.instanced_meshes)):
            var copy = _copy_of(copies, self.instanced_meshes[index].node)
            if copy >= 0:
                var mesh = self.instanced_meshes[index].copy()
                mesh.node = NodeId(copy)
                self.instanced_meshes.append(mesh^)
        for index in range(len(self.batched_meshes)):
            var copy = _copy_of(copies, self.batched_meshes[index].node)
            if copy >= 0:
                var mesh = self.batched_meshes[index].copy()
                mesh.node = NodeId(copy)
                self.batched_meshes.append(mesh^)
        for index in range(len(self.lods)):
            var copy = _copy_of(copies, self.lods[index].node)
            if copy >= 0:
                var lod = self.lods[index].copy()
                lod.node = NodeId(copy)
                # A level copied with the LOD is the copy's level; one
                # that was not stays the original's, as three.js's `copy`
                # would clone it.
                for level in range(len(lod.levels)):
                    var moved = _copy_of(copies, lod.levels[level].object)
                    if moved >= 0:
                        lod.levels[level].object = NodeId(moved)
                self.lods.append(lod^)
        for index in range(len(self.skinned_meshes)):
            var copy = _copy_of(copies, self.skinned_meshes[index].node)
            if copy >= 0:
                var mesh = self.skinned_meshes[index].copy()
                mesh.node = NodeId(copy)
                self.skinned_meshes.append(mesh^)
        for index in range(len(self.lines)):
            var copy = _copy_of(copies, self.lines[index].node)
            if copy >= 0:
                var line = self.lines[index]
                line.node = NodeId(copy)
                self.lines.append(line)
        for index in range(len(self.points)):
            var copy = _copy_of(copies, self.points[index].node)
            if copy >= 0:
                var cloud = self.points[index]
                cloud.node = NodeId(copy)
                self.points.append(cloud)
        for index in range(len(self.sprites)):
            var copy = _copy_of(copies, self.sprites[index].node)
            if copy >= 0:
                var sprite = self.sprites[index]
                sprite.node = NodeId(copy)
                self.sprites.append(sprite)
        for index in range(len(self.wide_lines)):
            var copy = _copy_of(copies, self.wide_lines[index].node)
            if copy >= 0:
                var line = self.wide_lines[index]
                line.node = NodeId(copy)
                self.wide_lines.append(line)
        for index in range(len(self.lights)):
            var copy = _copy_of(copies, self.lights[index].node)
            if copy >= 0:
                var light = self.lights[index]
                light.node = NodeId(copy)
                var target = _copy_of(copies, light.target)
                if target >= 0:
                    light.target = NodeId(target)
                self.lights.append(light)


def _copy_of(copies: List[Int], node: NodeId) -> Int:
    """Return the copy `clone` made of a node, or -1 for none, for a node
    it did not copy and for `NO_PARENT`."""
    if node.value < 0 or node.value >= len(copies):
        return -1
    return copies[node.value]


def _check_type(node: Object3D) raises:
    """Refuse a node whose `object_type` is none of the three there are."""
    if not node.object_type.is_valid():
        raise Error("A node must be an Object3D, a Group or a Gyroscope")


def _gyroscope_world(parent: Matrix4, local: Matrix4) raises -> Matrix4:
    """Return a gyroscope's world transform, three.js's
    `Gyroscope.updateMatrixWorld`: the position and the scale the parents
    carry it to, and its own turn, not theirs.

    Args:
        parent: The parent's world transform.
        local: The gyroscope's transform relative to the parent.

    Returns:
        The world transform.

    Raises:
        Error: Never for a transform that decomposes.
    """
    var world = Matrix4(copy=parent)
    world.multiply(local)
    var at = Vector3(0, 0, 0)
    var turn = Quaternion.identity()
    var size = Vector3(1, 1, 1)
    world.decompose(at, turn, size)
    var own_at = Vector3(0, 0, 0)
    var own_turn = Quaternion.identity()
    var own_size = Vector3(1, 1, 1)
    local.decompose(own_at, own_turn, own_size)
    return compose(at, own_turn, size)
