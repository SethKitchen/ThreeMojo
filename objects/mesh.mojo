# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Something drawable, from three.js `src/objects/Mesh.js`.

In three.js a `Mesh` *is* an `Object3D` holding a reference to a
`BufferGeometry` — it inherits its transform and shares its vertex data. Mojo
gives us neither inheritance nor shared references, so a mesh names both: the
scene node it is drawn at, in `core.scene`, and the geometry it draws, in
`core.geometry_store`.

That split is worth keeping even where inheritance was available. A scene node
is a position; a mesh is a thing to draw. Not every node has geometry — the
pivot a cube orbits is a node and nothing else — and one geometry can be drawn
at many nodes without being copied.

That last sentence used to be false. A mesh took its geometry by value and
moved it in, so two meshes meant two copies of the vertex array and sharing was
impossible however the comment read. Naming it by id is what made the claim
true.

A mesh is three ids and one flag — where it is, what shape it is, what it is
made of, and whether the renderer may skip it when its bounds are out of
view — which is as small as identity gets. The ids are three *different*
types rather than three integers, because adjacent same-typed parameters are
transposable and these three used to be exactly that; see `core.object3d`.

The flag is three.js's `Object3D.frustumCulled`, and it lives here rather
than on the node because here is what is drawn: a node is a transform, and
a transform has no bounds to be out of view. It is on by default, as in
three.js, and is turned off to prove the culling changes nothing, which is
what the renderer's tests use it for.

It used to say here that nothing moved a vertex after the geometry was
built, so a bound always described what it bounded. Morph targets are the
thing that moves one. A mesh whose weights are not all zero is left in
whatever its bound says, because the bound describes the face the mesh is
no longer wearing; see `Renderer.prepare`.

## Morph target influences

`morph_influences` is three.js's `morphTargetInfluences`: how much of each
of the geometry's morph targets this mesh wears. The geometry holds the
targets and the mesh holds the numbers, which is what lets two meshes share
one head and pull different faces.

They are a `MorphInfluences`, a list with no cap, as three.js on WebGL2
has none. A weight never set reads as zero, and the weight of a target the
geometry does not have is never read.

`morph_target_dictionary` is three.js's `morphTargetDictionary`: each
target's name and its index. `update_morph_targets` fills both from a
geometry, as three.js's `updateMorphTargets` does when a mesh is made. A
mesh here names its geometry by id and cannot read it, so the call is
made by whoever holds both; a loader makes it.

## Several materials

A mesh can wear a list of materials, three.js's `Mesh.material` as an
array. Each group of its geometry then draws with the material its
`material_index` names, and a group whose index is past the end of the
list draws nothing, as in three.js. A mesh with a list and a geometry
without groups draws nothing either: three.js reads the groups and finds
none. A mesh with one material ignores the groups and draws every
triangle, as three.js does.

`material` holds the first entry of the list, so code that reads one
material reads a sensible one. `materials` is empty for a mesh with one
material. See `is_multi_material` and `group_material`.

Color used to live here, with a note saying a `Material` would be ceremony
until there was a second property to put in it. Textures were that second
property, and `side` a third; see `materials.material`.
"""

from core.buffer_geometry import BufferGeometry, MaterialIndex
from core.geometry_store import GeometryId
from core.morph import MorphInfluences
from core.object3d import NodeId
from materials.material import MaterialId


struct Mesh(ImplicitlyCopyable):
    """A geometry drawn with a given material at a given scene node."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    # Whether `Renderer.prepare` may leave this mesh out when its bounding
    # sphere, carried to world space, lies outside the camera's frustum.
    var frustum_culled: Bool
    # How much of each of the geometry's morph targets this mesh wears:
    # three.js's `morphTargetInfluences`. See the module docstring.
    var morph_influences: MorphInfluences
    # Each target's name and index: three.js's `morphTargetDictionary`.
    # Empty until `update_morph_targets`.
    var morph_target_dictionary: Dict[String, Int]
    # Whether this mesh is drawn into the shadow maps of the lights that
    # cast, and whether the lights' shadows fall on it: three.js's
    # `castShadow` and `receiveShadow`, both off by default as there.
    # See `lights.shadow`.
    var cast_shadow: Bool
    var receive_shadow: Bool
    # The materials the geometry's groups wear, three.js's `material`
    # array, or empty for a mesh with one material. See the module
    # docstring.
    var materials: List[MaterialId]
    # The materials a light's shadow map draws this mesh with in place of
    # its own, three.js's `customDepthMaterial` for a directional or a
    # spot light and `customDistanceMaterial` for a point light, or `None`
    # for the renderer's own. The mesh's own material still says whether
    # it is visible and which faces are drawn; see
    # `Renderer.shadow_maps`.
    var custom_depth_material: Optional[MaterialId]
    var custom_distance_material: Optional[MaterialId]

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
        cast_shadow: Bool = False,
        receive_shadow: Bool = False,
    ) raises:
        """Bind a stored geometry and material to a scene node.

        Whether the ids exist is not checkable here — a mesh holds none of the
        three stores — so only the obviously impossible is refused. The
        renderer has them all and raises if any id is out of range.

        Args:
            geometry: Id of the geometry to draw, from `GeometryStore.add`.
            material: Id of the material to draw it with.
            node: Index of the scene node giving its world transform.
            frustum_culled: Whether the renderer may skip this mesh when
                its bounds are out of view. On unless said otherwise, as
                three.js's `frustumCulled` is.
            cast_shadow: Whether this mesh is drawn into the shadow maps,
                three.js's `castShadow`. Off unless said otherwise.
            receive_shadow: Whether the shadows fall on this mesh,
                three.js's `receiveShadow`. Off unless said otherwise.

        Raises:
            Error: If any id is negative.
        """
        if node.value < 0:
            raise Error("A mesh must name a scene node")
        if geometry.value < 0:
            raise Error("A mesh must name a geometry")
        if material.value < 0:
            raise Error("A mesh must name a material")
        self.geometry = geometry
        self.material = material
        self.node = node
        self.frustum_culled = frustum_culled
        self.morph_influences = MorphInfluences()
        self.morph_target_dictionary = Dict[String, Int]()
        self.cast_shadow = cast_shadow
        self.receive_shadow = receive_shadow
        self.materials = List[MaterialId]()
        self.custom_depth_material = None
        self.custom_distance_material = None

    def __init__(
        out self,
        geometry: GeometryId,
        materials: List[MaterialId],
        node: NodeId,
        *,
        frustum_culled: Bool = True,
        cast_shadow: Bool = False,
        receive_shadow: Bool = False,
    ) raises:
        """Bind a stored geometry and a list of materials to a scene node,
        three.js's `new Mesh(geometry, [a, b, ...])`.

        Each group of the geometry draws with the material its
        `material_index` names. A list of one entry is still a list: the
        groups are read, as three.js reads them for an array of one.

        Args:
            geometry: Id of the geometry to draw, from `GeometryStore.add`.
            materials: The materials the groups wear, by position.
            node: Index of the scene node giving its world transform.
            frustum_culled: Whether the renderer may skip this mesh when
                its bounds are out of view.
            cast_shadow: Whether this mesh is drawn into the shadow maps.
            receive_shadow: Whether the shadows fall on this mesh.

        Raises:
            Error: If the list is empty, or any id is negative.
        """
        if len(materials) == 0:
            raise Error("A mesh with a material list needs one material")
        for index in range(len(materials)):  # pragma: no branch
            if materials[index].value < 0:
                raise Error("A mesh must name a material")
        self = Mesh(
            geometry,
            materials[0],
            node,
            frustum_culled=frustum_culled,
            cast_shadow=cast_shadow,
            receive_shadow=receive_shadow,
        )
        self.materials = materials.copy()

    def __init__(out self, *, copy: Self):
        """Copy a mesh, its material list included.

        Written out because a list is not copied implicitly, and a mesh
        is: a scene adds one by value.

        Args:
            copy: The mesh to copy.
        """
        self.geometry = copy.geometry
        self.material = copy.material
        self.node = copy.node
        self.frustum_culled = copy.frustum_culled
        self.morph_influences = copy.morph_influences
        self.morph_target_dictionary = copy.morph_target_dictionary.copy()
        self.cast_shadow = copy.cast_shadow
        self.receive_shadow = copy.receive_shadow
        self.materials = copy.materials.copy()
        self.custom_depth_material = copy.custom_depth_material
        self.custom_distance_material = copy.custom_distance_material

    def is_multi_material(self) -> Bool:
        """Return True if the mesh wears a list of materials, three.js's
        `Array.isArray(mesh.material)`.
        """
        return len(self.materials) > 0

    def group_material(
        self, index: MaterialIndex
    ) raises -> Optional[MaterialId]:
        """Return the material a group wears, three.js's
        `material[group.materialIndex]`.

        Args:
            index: The group's material index.

        Returns:
            The material, or none when the index is past the end of the
            list: three.js reads `undefined` and draws nothing.

        Raises:
            Error: If the mesh has one material and no list, or the index
                is not valid.
        """
        if not self.is_multi_material():
            raise Error("A mesh with one material has no material list")
        if not index.is_valid():
            raise Error("A group's material index cannot be negative")
        if index.value >= len(self.materials):
            return None
        return self.materials[index.value]

    def set_morph_influence(mut self, target: Int, weight: Float32) raises:
        """Set how much of one morph target this mesh wears.

        Args:
            target: Which of the geometry's targets, from zero.
            weight: How much of it. One wears the target outright, zero
                leaves the base shape, and the numbers between mix. Values
                outside that range are allowed, as three.js allows them:
                they overshoot, which is how a smile becomes a grin.

        Raises:
            Error: If the target is negative, or the weight is not a
                number.
        """
        self.morph_influences.set(target, weight)

    def set_morph_influence(mut self, name: String, weight: Float32) raises:
        """Set how much of one named morph target this mesh wears, three.js's
        `morphTargetInfluences[morphTargetDictionary[name]]`.

        Args:
            name: The target's name, from `morph_target_dictionary`.
            weight: How much of it.

        Raises:
            Error: If no target has that name, or the weight is not a
                number.
        """
        self.morph_influences.set(
            morph_target_index(self.morph_target_dictionary, name), weight
        )

    def morph_influence(self, target: Int) raises -> Float32:
        """Return how much of one morph target this mesh wears.

        Args:
            target: Which of the geometry's targets, from zero.

        Returns:
            Its weight, zero for a target never set.

        Raises:
            Error: If the target is negative.
        """
        return self.morph_influences.get(target)

    def update_morph_targets(mut self, geometry: BufferGeometry) raises:
        """Size the weights and name the targets from the geometry the mesh
        draws, three.js's `updateMorphTargets`.

        Every weight is set to zero, one per target, and the dictionary
        maps each target's name to its index. A geometry with no targets
        leaves both as they are, as three.js does.

        Args:
            geometry: The geometry this mesh names.

        Raises:
            Error: Never for a geometry that was built through its own
                methods.
        """
        fill_morph_targets(
            self.morph_influences, self.morph_target_dictionary, geometry
        )

    def is_morphed(self) -> Bool:
        """Return True if any morph target is worn at all.

        The renderer asks before it culls: a mesh wearing a target is not
        where its geometry's bound says it is.
        """
        return self.morph_influences.is_worn()


def morph_target_index(
    dictionary: Dict[String, Int], name: String
) raises -> Int:
    """Return the index a morph target's name maps to.

    Args:
        dictionary: A mesh's `morph_target_dictionary`.
        name: The target's name.

    Returns:
        Its index.

    Raises:
        Error: If no target has that name.
    """
    var found = dictionary.get(name)
    if not found:
        raise Error("No morph target has the name " + name)
    return found.value()


def fill_morph_targets(
    mut influences: MorphInfluences,
    mut dictionary: Dict[String, Int],
    geometry: BufferGeometry,
) raises:
    """Fill a mesh's weights and dictionary from its geometry, three.js's
    `updateMorphTargets`; see `Mesh.update_morph_targets`.

    Args:
        influences: The weights, replaced by one zero per target.
        dictionary: The names, replaced by each target's name and index.
        geometry: The geometry the mesh draws.

    Raises:
        Error: Never for a geometry built through its own methods.
    """
    var count = geometry.morph_count()
    if count == 0:
        return
    influences = MorphInfluences(count=count)
    dictionary = Dict[String, Int]()
    for target in range(count):  # pragma: no branch
        dictionary[geometry.morph_target_name(target)] = target
