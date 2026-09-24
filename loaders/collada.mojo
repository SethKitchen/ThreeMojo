# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A Collada file's geometries, materials, node hierarchy, cameras and
lights, read from a `.dae` into a `Scene` and an `Assets`: three.js's
`ColladaLoader`.

**What a Collada file is.** An XML document of libraries -- geometries,
effects, materials, images, cameras, lights, nodes, visual scenes -- that
name one another by `#id`. A `<scene>` names the visual scene to show. A
visual scene is a tree of `<node>` elements, each with a list of
transform steps and the things it instances: a geometry with a material
bound to each of its symbols, a camera, a light, or another node.
`read_collada` reads all of that into the scene and the assets it is
handed, and returns a `ColladaModel` that says what went where.

**What maps to what.** A `<triangles>`, `<polylist>` or `<polygons>`
primitive becomes a `BufferGeometry` with `position`, and `normal`, `uv`
and `color` when its inputs name them, drawn as a `Mesh`. A `<lines>` or
`<linestrips>` primitive becomes a geometry drawn as a `Line` of
`SEGMENTS`. A `phong` or `blinn` effect becomes a `PHONG` material, a
`lambert` one a `LAMBERT` material and a `constant` one a `BASIC`
material, as three.js makes a `MeshPhongMaterial`, a `MeshLambertMaterial`
and a `MeshBasicMaterial`. A node becomes an `Object3D` at its transform
steps multiplied in order and decomposed; the visual scene becomes a root
node, turned a quarter turn about x for a `Z_UP` file and scaled by the
file's unit, as three.js turns and scales its `scene`.

**One geometry per primitive.** three.js builds one geometry per kind of
primitive, with a group per primitive and an array of materials. A mesh
here draws one material, so each primitive is its own geometry and its
own `Mesh`, as `loaders.obj` makes one object per `usemtl`.

**Skins.** An `<instance_controller>` of a `<skin>` controller draws the
skin's geometry as `SkinnedMesh`es, as three.js's `buildNode`,
`buildSkin` and `buildSkeleton` bind it. The bones are the `JOINT` nodes
under each `<skeleton>` root, in the order of the controller's joint
names, which match a joint's `sid`; a joint the controller does not name
follows, at the identity. Each joint's `INV_BIND_MATRIX` is its bone's
inverse bind, and the `bind_shape_matrix` is the bind matrix. A vertex
keeps its four largest weights, and the weights are normalized.
`loaders.collada_animation` reads the animations and the clips.

**Where skins differ from three.js.** three.js adds the skin to the
geometry itself, so every instance of the geometry is skinned; here only
the controller's instances are. A `<skeleton>` that names neither a node
nor a visual scene, a controller joint no bone has, and a joint index
outside the joints are refused, where three.js reads a hole. A bone inside
an `<instance_node>` copy is not a bone here. A joint source must be a
`Name_array`, which is the one three.js reads. A `<morph>` controller is
refused: three.js does not read one.

**Not ported.** Kinematics and physics, `<lookat>` and `<skew>` steps, `<trifans>`,
`<tristrips>` and polygons with holes, a second set of texture
coordinates, and the specular and ambient maps. `<polygons>` is read,
which three.js does not read.
"""

from animation.animation_clip import AnimationClip
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import (
    ambient_light,
    directional_light,
    point_light,
    spot_light,
)
from loaders.collada_animation import read_collada_animations
from loaders.model_nodes import (
    authored_color,
    decompose_onto,
    texture_from_file,
)
from loaders.xml import NO_ELEMENT, XmlDocument, parse_xml
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    FRONT_SIDE,
    LAMBERT,
    NO_TEXTURE,
    PHONG,
    Material,
    MaterialId,
    MaterialKind,
    Side,
)
from math.matrix4 import Matrix4, scaling, translation
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.line import SEGMENTS, Line
from objects.mesh import Mesh
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import (
    SKIN_INDEX,
    SKIN_WEIGHT,
    SkinnedMesh,
    normalized_skin_weights,
)
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, ColorSpace, srgb_to_linear
from render.texture import CLAMP, COVERAGE, IGNORED, REPEAT, Alpha, Wrap
from render.texture_store import TextureId
from std.math import cos, isfinite, sin, sqrt
from std.pathlib import Path
from units.si import DEGREE, METER, Angle, Length

# How deep `<instance_node>` can nest. A file that instances a node inside
# itself would otherwise place nodes until memory ran out.
comptime MAX_INSTANCE_DEPTH = 64

# three.js's `PerspectiveCamera` defaults, which a Collada camera takes
# for any number it leaves out: three.js hands `undefined` to the
# constructor, and JavaScript fills in the default.
comptime DEFAULT_FOV = Angle(50.0, DEGREE)
comptime DEFAULT_NEAR = Float64(0.1)
comptime DEFAULT_FAR = Float64(2000.0)
# three.js's `SpotLight` default cone, a third of a half turn.
comptime DEFAULT_SPOT = Angle(60.0, DEGREE)
# The material three.js draws a primitive with when its symbol is bound
# to nothing: a basic magenta that stands out.
comptime FALLBACK_COLOR = Color(255, 0, 255)
comptime _WHITE = Color(255, 255, 255)


@fieldwise_init
struct UpAxis(Equatable, ImplicitlyCopyable, Writable):
    """Which axis a Collada file calls up, as a type rather than a bare
    int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three axes there are."""
        return self == X_UP or self == Y_UP or self == Z_UP


# `<up_axis>X_UP</up_axis>`. three.js reads it and does not turn the scene.
comptime X_UP = UpAxis(0)
# `<up_axis>Y_UP</up_axis>`, the default: this renderer's own up.
comptime Y_UP = UpAxis(1)
# `<up_axis>Z_UP</up_axis>`: turned a quarter turn about x to stand up.
comptime Z_UP = UpAxis(2)


def up_axis_rotation(axis: UpAxis) raises -> Quaternion:
    """Return how three.js turns a Collada scene that has an up axis.

    A `Z_UP` scene is turned by minus a quarter turn about x, which
    stands z up as y. The vertices are not changed, as three.js does not
    change them. A `Y_UP` or an `X_UP` scene is not turned.

    Args:
        axis: The file's up axis.

    Returns:
        The rotation of the scene's root node.

    Raises:
        Error: If `axis` is none of `X_UP`, `Y_UP` and `Z_UP`.
    """
    if not axis.is_valid():
        raise Error("Collada: an up axis that is not X_UP, Y_UP or Z_UP")
    if axis == Z_UP:
        return Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(-90, DEGREE))
    return Quaternion.identity()


struct ColladaModel(Copyable, Movable):
    """What `read_collada` put into the scene and the assets."""

    # The visual scene's own node, which every root `<node>` hangs on.
    var root: NodeId
    # The file's `<up_axis>`, and its `<unit meter>` as a length.
    var up_axis: UpAxis
    var unit: Length
    # One entry per `<node>` placed, in the order placed: a node that an
    # `<instance_node>` places twice is here twice. Its name, or its `sid`
    # for a `JOINT`, as three.js names it.
    var nodes: List[NodeId]
    var node_names: List[String]
    # One entry per `<material>` of the file, in file order, with its
    # `id` and its `name`.
    var materials: List[MaterialId]
    var material_ids: List[String]
    var material_names: List[String]
    # One geometry per primitive built, in the order built.
    var geometries: List[GeometryId]
    # One texture per map a material read, in the order read.
    var textures: List[TextureId]
    # Each camera an `<instance_camera>` placed, riding its node.
    var perspective_cameras: List[PerspectiveCamera]
    var orthographic_cameras: List[OrthographicCamera]
    # Where the meshes, lines and lights this file added begin in the
    # scene's lists, and how many there are.
    var first_mesh: Int
    var mesh_count: Int
    var first_line: Int
    var line_count: Int
    var first_light: Int
    var light_count: Int
    # The same for the skinned meshes, in `scene.skinned_meshes`.
    var first_skinned_mesh: Int
    var skinned_mesh_count: Int
    # One clip per animation clip that makes a track, or `default`.
    var animations: List[AnimationClip]

    def __init__(out self):
        """Start empty."""
        self.root = NO_PARENT
        self.up_axis = Y_UP
        self.unit = Length(1.0, METER)
        self.nodes = List[NodeId]()
        self.node_names = List[String]()
        self.materials = List[MaterialId]()
        self.material_ids = List[String]()
        self.material_names = List[String]()
        self.geometries = List[GeometryId]()
        self.textures = List[TextureId]()
        self.perspective_cameras = List[PerspectiveCamera]()
        self.orthographic_cameras = List[OrthographicCamera]()
        self.first_mesh = 0
        self.mesh_count = 0
        self.first_line = 0
        self.line_count = 0
        self.first_light = 0
        self.light_count = 0
        self.first_skinned_mesh = 0
        self.skinned_mesh_count = 0
        self.animations = List[AnimationClip]()

    def material(self, id: String) raises -> MaterialId:
        """Return the material a `<material id>` became.

        Args:
            id: The material's `id`, without `#`.

        Returns:
            Its material.

        Raises:
            Error: If the file has no material of that id.
        """
        for index in range(len(self.material_ids)):
            if self.material_ids[index] == id:
                return self.materials[index]
        raise Error("Collada: no material with id " + id)


def read_collada(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> ColladaModel:
    """Read a `.dae` file into a scene and its assets.

    An image is read from the file's own directory.

    Args:
        path: The file.
        scene: The scene to add the nodes, meshes, lines and lights to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the file cannot be read, or everything `load_collada`
            raises.
    """
    var directory = String(path[byte = 0 : path.rfind("/") + 1])
    return load_collada(Path(path).read_text(), directory, scene, assets)


def load_collada(
    text: String, directory: String, mut scene: Scene, mut assets: Assets
) raises -> ColladaModel:
    """Read a Collada document into a scene and its assets.

    Args:
        text: The XML.
        directory: Where an image's relative path is read from, ending in
            a slash, or empty for the working directory.
        scene: The scene to add the nodes, meshes, lines and lights to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the text is not XML or its root is not `<COLLADA>`; the
            unit or the up axis is not one Collada has; the file has no
            `<scene>`, or it names no visual scene the file has; a
            reference is not `#id` or names nothing where three.js needs
            something; a number, a count or an index is malformed or out
            of range; an effect has no `profile_COMMON` technique; a
            camera or a light is refused by its builder; an image path is
            not relative or the image cannot be read; or `<instance_node>`
            nests deeper than `MAX_INSTANCE_DEPTH`; or a controller, a skin,
            its skeleton, an animation or a clip is malformed or names what
            is not there.
    """
    var document = parse_xml(text)
    if document.name(document.root()) != "COLLADA":
        raise Error("Collada: the root element is not <COLLADA>")
    var loader = _Loader(document^, directory)
    loader.read_asset()
    loader.read_materials(assets)
    loader.model.first_skinned_mesh = len(scene.skinned_meshes)
    loader.read_scene(scene, assets)
    loader.place_controllers(scene, assets)
    loader.model.skinned_mesh_count = (
        len(scene.skinned_meshes) - loader.model.first_skinned_mesh
    )
    loader.model.line_count = len(scene.lines) - loader.model.first_line
    loader.read_animations()
    return loader.model.copy()


def _reference(url: String) raises -> String:
    """Return the id a `#id` reference names.

    Args:
        url: The reference.

    Returns:
        The id, without `#`.

    Raises:
        Error: If the reference does not begin with `#`, which is the one
            form three.js's `parseId` reads.
    """
    if not url.startswith("#"):
        raise Error("Collada: a reference must be #id, not '" + url + "'")
    return String(url[byte=1:])


def _floats(text: String) raises -> List[Float64]:
    """Return the numbers a white-space separated list holds.

    Args:
        text: The list.

    Returns:
        The numbers.

    Raises:
        Error: If one is not a number, or is not finite once it is a
            `Float32`.
    """
    var out = List[Float64]()
    for piece in text.split():
        var field = String(piece)
        var value: Float64
        try:
            value = Float64(field)
        except:
            raise Error("Collada: not a number: " + field)
        if not isfinite(Float32(value)):
            raise Error("Collada: a number must be finite: " + field)
        out.append(value)
    return out^


def _ints(text: String) raises -> List[Int]:
    """Return the whole numbers a white-space separated list holds.

    Args:
        text: The list.

    Returns:
        The numbers.

    Raises:
        Error: If one is not a whole number.
    """
    var out = List[Int]()
    for piece in text.split():
        var field = String(piece)
        try:
            out.append(Int(field))
        except:
            raise Error("Collada: not a whole number: " + field)
    return out^


def _axis_rotation(axis: Vector3, angle: Angle) -> Matrix4:
    """Return three.js's `Matrix4.makeRotationAxis`: a turn about an axis
    used as given, which a `<rotate>` step names."""
    var c = cos(angle.value)
    var s = sin(angle.value)
    var t = 1 - c
    var x = axis.x
    var y = axis.y
    var z = axis.z
    var tx = t * x
    var ty = t * y
    var matrix = Matrix4()
    matrix.set(
        tx * x + c,
        tx * y - s * z,
        tx * z + s * y,
        0,
        tx * y + s * z,
        ty * y + c,
        ty * z - s * x,
        0,
        tx * z - s * y,
        ty * z + s * x,
        t * z * z + c,
        0,
        0,
        0,
        0,
        1,
    )
    return matrix^


@fieldwise_init
struct _Source(Copyable, Movable):
    """A `<source>`: its numbers and how many make one element."""

    var values: List[Float64]
    var stride: Int


@fieldwise_init
struct _Input(Copyable, Movable):
    """An `<input>` of a primitive: what it gives, from where, and which
    index of each corner it reads."""

    var name: String
    var source: String
    var offset: Int


@fieldwise_init
struct _Built(Copyable, Movable):
    """One primitive, built: its geometry, whether it is lines, and the
    material symbol it names, or empty."""

    var geometry: GeometryId
    var lines: Bool
    var symbol: String
    # three.js makes one object per kind of primitive in a geometry, and
    # counts them to decide whether a node is one object.
    var kind: String
    # The position each corner names, for a skin.
    var vertices: List[Int]


struct _Corners(Movable):
    """The attributes of a primitive, gathered corner by corner."""

    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var colors: List[Float32]
    var color_size: Int
    var vertices: List[Int]

    def __init__(out self):
        self.vertices = List[Int]()
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.colors = List[Float32]()
        self.color_size = 0


@fieldwise_init
struct _Controlled(Copyable, Movable):
    """An `<instance_controller>` and the scene node it rides, waiting for
    its bones to be placed."""

    var instance: Int
    var node: NodeId


struct _Skin(Movable):
    """A `<skin>`, read: its bind shape matrix, its joints' names and
    inverse binds, and each vertex's four bones and weights."""

    var bind: Matrix4
    var names: List[String]
    var inverses: List[Matrix4]
    var bones: List[Float32]
    var weights: List[Float32]

    def __init__(out self):
        self.bind = Matrix4()
        self.names = List[String]()
        self.inverses = List[Matrix4]()
        self.bones = List[Float32]()
        self.weights = List[Float32]()

    def apply(self, vertices: List[Int], mut geometry: BufferGeometry) raises:
        """Give a primitive its skin, one value per corner, read by the
        position each corner names.

        Raises:
            Error: If a corner names a position the skin has no weights
                for.
        """
        var bones = List[Float32]()
        var weights = List[Float32]()
        # A primitive is built with a corner at least.
        for vertex in vertices:  # pragma: no branch
            if vertex * 4 + 4 > len(self.bones):
                raise Error("Collada: a position has no skin weights")
            for lane in range(4):  # pragma: no branch
                bones.append(self.bones[vertex * 4 + lane])
                weights.append(self.weights[vertex * 4 + lane])
        geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
        geometry.set_attribute(
            String(SKIN_WEIGHT), BufferAttribute(weights^, 4)
        )


struct _ColladaRig(Movable):
    """The controllers, the nodes placed, and the controller instances
    waiting for their bones."""

    var controllers: Dict[String, Int]
    # The scene node each `<node>` element became, placed itself and not
    # as a copy.
    var placed: Dict[Int, NodeId]
    var waiting: List[_Controlled]
    # Each skinned primitive built, by controller and primitive.
    var skinned: Dict[String, GeometryId]

    def __init__(out self):
        self.controllers = Dict[String, Int]()
        self.placed = Dict[Int, NodeId]()
        self.waiting = List[_Controlled]()
        self.skinned = Dict[String, GeometryId]()


def _require(
    inputs: Dict[String, Tuple[String, Int]], semantic: String, what: String
) raises:
    """Raise unless a skin's inputs have one of a semantic.

    Raises:
        Error: If they have none.
    """
    if semantic not in inputs:
        raise Error("Collada: " + what + " needs " + semantic)


def _within(index: Int, count: Int) -> Bool:
    """Return True if an index is from zero to below a count."""
    return index >= 0 and index < count


def _sorted_place(amounts: List[Float64], amount: Float64) -> Int:
    """Return where a weight goes in weights sorted largest first: after
    every weight at least as large, as a stable sort puts it."""
    var at = len(amounts)
    for before in range(len(amounts) - 1, -1, -1):
        if amounts[before] >= amount:
            break
        at = before
    return at


def _row_major(values: List[Float64], start: Int) -> Matrix4:
    """Return the matrix sixteen numbers hold row by row, as Collada
    writes one, from `start`."""
    var out = Matrix4()
    for at in range(16):  # pragma: no branch
        out.elements[(at % 4) * 4 + at // 4] = Float32(values[start + at])
    return out^


struct _Loader(Movable):
    """The document, its libraries by id, and what has been built."""

    var document: XmlDocument
    var directory: String
    var model: ColladaModel
    # Every library entry by `id`. A later entry of one id replaces an
    # earlier one, as three.js's libraries do; a node keeps the first.
    var effects: Dict[String, Int]
    var images: Dict[String, Int]
    var cameras: Dict[String, Int]
    var lights: Dict[String, Int]
    var geometries: Dict[String, Int]
    var nodes: Dict[String, Int]
    var visual_scenes: Dict[String, Int]
    # Each geometry built so far, by id: where its primitives begin in
    # `built` and how many there are.
    var built_at: Dict[String, Int]
    var built_count: Dict[String, Int]
    var built: List[_Built]
    # Each material index's copy for lines, made once, by index.
    var line_materials: Dict[Int, MaterialId]
    # The three materials three.js makes when a file names none: a white
    # phong for a mesh, a white basic for a line, and a magenta basic for
    # a symbol bound to nothing. Made once each, when first needed.
    var defaults: Dict[String, MaterialId]
    # The controllers, the placed nodes and the skins waiting for them.
    var rig: _ColladaRig

    def __init__(out self, var document: XmlDocument, directory: String) raises:
        self.document = document^
        self.directory = directory
        self.model = ColladaModel()
        self.effects = Dict[String, Int]()
        self.images = Dict[String, Int]()
        self.cameras = Dict[String, Int]()
        self.lights = Dict[String, Int]()
        self.geometries = Dict[String, Int]()
        self.nodes = Dict[String, Int]()
        self.visual_scenes = Dict[String, Int]()
        self.built_at = Dict[String, Int]()
        self.built_count = Dict[String, Int]()
        self.built = List[_Built]()
        self.line_materials = Dict[Int, MaterialId]()
        self.defaults = Dict[String, MaterialId]()
        self.rig = _ColladaRig()
        # A parsed document has its root at least: the loop always runs.
        for index in range(self.document.count()):  # pragma: no branch
            ref element = self.document.elements[index]
            var id = self.document.attribute(index, "id")
            if id == "":
                continue
            if element.name == "effect":
                self.effects[id] = index
            elif element.name == "image":
                self.images[id] = index
            elif element.name == "camera":
                self.cameras[id] = index
            elif element.name == "light":
                self.lights[id] = index
            elif element.name == "geometry":
                self.geometries[id] = index
            elif element.name == "visual_scene":
                self.visual_scenes[id] = index
            elif element.name == "node" and id not in self.nodes:
                self.nodes[id] = index

    # --- small readers ------------------------------------------------------

    def numbers(
        self, element: Int, count: Int, what: String
    ) raises -> List[Float64]:
        """Return the numbers an element's text holds, refusing a list of
        another length.

        Args:
            element: The element.
            count: How many numbers it must hold.
            what: What it is, for the error.

        Returns:
            The numbers.

        Raises:
            Error: If the text is not `count` numbers.
        """
        var values = _floats(self.document.text(element))
        if len(values) != count:
            raise Error(
                "Collada: "
                + what
                + " needs "
                + String(count)
                + " numbers, not "
                + String(len(values))
            )
        return values^

    def number(
        self, parent: Int, name: String, default: Float64
    ) raises -> Float64:
        """Return the one number a child element holds, or a default.

        Args:
            parent: The element to look in.
            name: The child's name.
            default: What to return when there is no such child.

        Returns:
            The number.

        Raises:
            Error: If the child is there and does not hold one number.
        """
        var found = self.document.child(parent, name)
        if found == NO_ELEMENT:
            return default
        return self.numbers(found, 1, "<" + name + ">")[0]

    def color(self, element: Int, alpha: Bool) raises -> List[Float64]:
        """Return a `<color>`'s numbers: three, or four when `alpha`
        asks for the alpha too.

        Args:
            element: The `<color>`.
            alpha: Whether the fourth number is needed.

        Returns:
            The numbers.

        Raises:
            Error: If there are too few, or one is not a number.
        """
        var values = _floats(self.document.text(element))
        var need = 3
        if alpha:
            need = 4
        if len(values) < need:
            raise Error("Collada: a color needs " + String(need) + " numbers")
        return values^

    # --- asset ----------------------------------------------------------------

    def read_asset(mut self) raises:
        """Read the unit and the up axis from `<asset>`."""
        var asset = self.document.child(self.document.root(), "asset")
        if asset == NO_ELEMENT:
            return
        var unit = self.document.child(asset, "unit")
        if unit != NO_ELEMENT and self.document.has_attribute(unit, "meter"):
            var meter = _floats(self.document.attribute(unit, "meter"))
            if len(meter) != 1 or meter[0] <= 0:
                raise Error("Collada: <unit meter> must be one positive number")
            self.model.unit = Length(Float32(meter[0]), METER)
        var up = self.document.child(asset, "up_axis")
        if up == NO_ELEMENT:
            return
        var axis = String(self.document.text(up).strip())
        if axis == "Z_UP":
            self.model.up_axis = Z_UP
        elif axis == "X_UP":
            self.model.up_axis = X_UP
        elif axis != "Y_UP":
            raise Error("Collada: an up axis that is not known: " + axis)

    # --- materials --------------------------------------------------------------

    def read_materials(mut self, mut assets: Assets) raises:
        """Build every `<material>` of `<library_materials>`, in file
        order."""
        var library = self.document.child(
            self.document.root(), "library_materials"
        )
        if library == NO_ELEMENT:
            return
        for element in self.document.children_named(library, "material"):
            var built = self.build_material(element, assets)
            self.model.materials.append(assets.materials.add(built))
            self.model.material_ids.append(
                self.document.attribute(element, "id")
            )
            self.model.material_names.append(
                self.document.attribute(element, "name")
            )

    def build_material(
        mut self, element: Int, mut assets: Assets
    ) raises -> Material:
        """Build a material from the effect it instances, as three.js's
        `buildMaterial` builds it.

        Args:
            element: The `<material>`.
            assets: Where a texture it reads goes.

        Returns:
            The material.

        Raises:
            Error: If it instances no effect the file has, the effect has
                no `profile_COMMON` technique of a shading three.js
                reads, or a parameter is malformed.
        """
        var instance = self.document.child(element, "instance_effect")
        if instance == NO_ELEMENT:
            raise Error("Collada: a material instances no effect")
        var url = _reference(self.document.attribute(instance, "url"))
        if url not in self.effects:
            raise Error("Collada: a material instances no effect: " + url)
        var profile = self.document.child(self.effects[url], "profile_COMMON")
        if profile == NO_ELEMENT:
            raise Error("Collada: an effect has no profile_COMMON")
        var technique = self.document.child(profile, "technique")
        if technique == NO_ELEMENT:
            raise Error("Collada: an effect has no technique")
        var shading = NO_ELEMENT
        var kind = BASIC
        for child in self.document.children(technique):
            var name = self.document.name(child)
            if name == "phong" or name == "blinn":
                shading = child
                kind = PHONG
            elif name == "lambert":
                shading = child
                kind = LAMBERT
            elif name == "constant":
                shading = child
                kind = BASIC
        if shading == NO_ELEMENT:
            raise Error(
                "Collada: a technique has no constant, lambert, blinn or"
                " phong shading"
            )
        var color = _WHITE
        var map = NO_TEXTURE
        var specular = Color(0, 0, 0)
        var shininess = Float32(0)
        if kind == PHONG:
            specular = Color(17, 17, 17)
            shininess = 30
        var emissive = Color(0, 0, 0)
        var emissive_map = NO_TEXTURE
        var normal_map = NO_TEXTURE
        var lit = kind != BASIC
        # `transparent` and `transparency`, read after every other
        # parameter, as three.js reads them.
        var transparent = NO_ELEMENT
        var transparency = NO_ELEMENT
        for parameter in self.document.children(shading):
            var name = self.document.name(parameter)
            var tinted = self.document.child(parameter, "color")
            var texture = self.document.child(parameter, "texture")
            if name == "diffuse":
                if tinted != NO_ELEMENT:
                    color = self.srgb(tinted)
                if texture != NO_ELEMENT:
                    map = self.texture(profile, texture, SRGB, COVERAGE, assets)
            elif name == "specular" and kind == PHONG and tinted != NO_ELEMENT:
                specular = self.srgb(tinted)
            elif name == "bump" and lit and texture != NO_ELEMENT:
                normal_map = self.texture(
                    profile, texture, LINEAR, IGNORED, assets
                )
            elif name == "shininess" and kind == PHONG:
                var value = self.number(parameter, "float", 0)
                # three.js tests the number for truth: a zero keeps the
                # default.
                if value != 0:
                    shininess = Float32(value)
            elif name == "emission" and lit:
                if tinted != NO_ELEMENT:
                    emissive = self.srgb(tinted)
                if texture != NO_ELEMENT:
                    emissive_map = self.texture(
                        profile, texture, SRGB, IGNORED, assets
                    )
            elif name == "transparent":
                transparent = parameter
            elif name == "transparency":
                transparency = parameter
        var opacity = Float32(1)
        var blended = False
        if transparent != NO_ELEMENT or transparency != NO_ELEMENT:
            var result = self.opacity(transparent, transparency)
            opacity = result[0]
            blended = result[1]
        var side = FRONT_SIDE
        var extra_bump = NO_ELEMENT
        var extra = self.document.child(technique, "extra")
        if extra != NO_ELEMENT:
            for inner in self.document.children_named(extra, "technique"):
                for setting in self.document.children(inner):
                    var name = self.document.name(setting)
                    if name == "double_sided":
                        side = self.side(setting)
                    elif name == "bump":
                        extra_bump = self.document.child(setting, "texture")
        if extra_bump != NO_ELEMENT and lit:
            normal_map = self.texture(
                profile, extra_bump, LINEAR, IGNORED, assets
            )
        return Material(
            color,
            map=map,
            side=side,
            opacity=opacity,
            kind=kind,
            emissive=emissive,
            emissive_map=emissive_map,
            specular=specular,
            shininess=shininess,
            transparent=blended,
            normal_map=normal_map,
        )

    def srgb(self, element: Int) raises -> Color:
        """Return a `<color>` as authored, its alpha ignored, as
        three.js's `Color.fromArray` ignores it."""
        var values = self.color(element, False)
        return authored_color(values[0], values[1], values[2], "Collada")

    def side(self, element: Int) raises -> Side:
        """Return the side a `<double_sided>` asks for: both for one,
        the front for anything else, as three.js reads it."""
        var values = _floats(self.document.text(element))
        if len(values) == 1 and values[0] == 1:
            return DOUBLE_SIDE
        return FRONT_SIDE

    def opacity(
        self, transparent: Int, transparency: Int
    ) raises -> Tuple[Float32, Bool]:
        """Return the opacity and whether the surface blends, from a
        `<transparent>` and a `<transparency>`, either of which can be
        missing, as three.js's `buildMaterial` works them out.

        Args:
            transparent: The `<transparent>`, or `NO_ELEMENT`.
            transparency: The `<transparency>`, or `NO_ELEMENT`.

        Returns:
            The opacity, and True if the surface blends.

        Raises:
            Error: If the `opaque` mode is not one Collada has, a number
                is malformed, or the opacity is outside zero to one.
        """
        # A missing `<transparency>` is one; a missing `<transparent>` is
        # a white of alpha one in `A_ONE`.
        var factor = Float64(1)
        if transparency != NO_ELEMENT:
            factor = self.number(transparency, "float", 1)
        var mode = String("A_ONE")
        var rgba: List[Float64] = [1, 1, 1, 1]
        if transparent != NO_ELEMENT:
            mode = self.document.attribute(transparent, "opaque", "A_ONE")
            if self.document.child(transparent, "texture") != NO_ELEMENT:
                # A texture and no color: three.js makes the surface blend
                # and sets no alpha map.
                return (Float32(1), True)
            var tinted = self.document.child(transparent, "color")
            if tinted != NO_ELEMENT:
                rgba = self.color(tinted, True)
        var value: Float64
        if mode == "A_ONE":
            value = rgba[3] * factor
        elif mode == "RGB_ZERO":
            value = 1 - rgba[0] * factor
        elif mode == "A_ZERO":
            value = 1 - rgba[3] * factor
        elif mode == "RGB_ONE":
            value = rgba[0] * factor
        else:
            raise Error("Collada: an opaque mode that is not known: " + mode)
        if value < 0 or value > 1:
            raise Error(
                "Collada: an opacity outside zero to one: " + String(value)
            )
        return (Float32(value), value < 1)

    # --- textures ---------------------------------------------------------------

    def newparam(self, profile: Int, sid: String, kind: String) raises -> Int:
        """Return the `<kind>` inside the profile's `<newparam sid>`, or
        `NO_ELEMENT`."""
        for param in self.document.children_named(profile, "newparam"):
            if self.document.attribute(param, "sid") == sid:
                return self.document.child(param, kind)
        return NO_ELEMENT

    def texture(
        mut self,
        profile: Int,
        element: Int,
        space: ColorSpace,
        alpha: Alpha,
        mut assets: Assets,
    ) raises -> TextureId:
        """Return a `<texture>` as a texture, as three.js's `getTexture`
        resolves it: through a `sampler2D` and a `surface` to an image,
        or straight to an image when no sampler has its name.

        Args:
            profile: The effect's `profile_COMMON`.
            element: The `<texture>`.
            space: `SRGB` for a color map, `LINEAR` for a data map.
            alpha: `COVERAGE` for a color map, `IGNORED` for any other.
            assets: Where the texture goes.

        Returns:
            The texture, or `NO_TEXTURE` when no image has the id, which
            three.js warns about and leaves out.

        Raises:
            Error: If a sampler names no surface, the image has no
                `init_from` or names a path that is not relative, the
                image cannot be read, or a setting is malformed.
        """
        var name = self.document.attribute(element, "texture")
        var image_id = name
        var sampler = self.newparam(profile, name, "sampler2D")
        if sampler != NO_ELEMENT:
            var source = self.document.child(sampler, "source")
            var source_name = String()
            if source != NO_ELEMENT:
                source_name = String(self.document.text(source).strip())
            var surface = self.newparam(profile, source_name, "surface")
            if surface == NO_ELEMENT:
                raise Error("Collada: a sampler names no surface: " + name)
            var from_ = self.document.child(surface, "init_from")
            if from_ == NO_ELEMENT:
                raise Error("Collada: a surface has no init_from")
            image_id = String(self.document.text(from_).strip())
        if image_id not in self.images:
            return NO_TEXTURE
        var init = self.document.child(self.images[image_id], "init_from")
        if init == NO_ELEMENT:
            raise Error("Collada: an image has no init_from")
        var path = String(self.document.text_content(init).strip())
        if path.find(":") >= 0:
            raise Error("Collada: only a relative image path is read: " + path)
        var wrap = REPEAT
        var repeat = Vector2(1, 1)
        var offset = Vector2(0, 0)
        var settings = self.texture_settings(element)
        if len(settings) > 0:
            # three.js reads `wrapU` for `wrapS` and `wrapV` for `wrapT`,
            # and a missing one clamps. A texture here has one wrap for
            # both, so `wrapU` decides, as glTF's `wrapS` decides.
            wrap = CLAMP
            if settings.get("wrapU", 0) != 0:
                wrap = REPEAT
            repeat = Vector2(
                Float32(self.or_default(settings, "repeatU", 1)),
                Float32(self.or_default(settings, "repeatV", 1)),
            )
            offset = Vector2(
                Float32(settings.get("offsetU", 0)),
                Float32(settings.get("offsetV", 0)),
            )
        var built = texture_from_file(self.directory + path, space, wrap, alpha)
        built.repeat = repeat
        built.offset = offset
        var id = assets.textures.add(built^)
        self.model.textures.append(id)
        return id

    def or_default(
        self, settings: Dict[String, Float64], key: String, default: Float64
    ) raises -> Float64:
        """Return a setting, or a default when it is missing or zero, as
        three.js's `technique.repeatU || 1` reads it."""
        var value = settings.get(key, 0)
        if value == 0:
            return default
        return value

    def texture_settings(self, element: Int) raises -> Dict[String, Float64]:
        """Return the `wrapU`, `wrapV`, `repeatU`, `repeatV`, `offsetU` and
        `offsetV` a texture's `<extra><technique>` gives, as numbers.

        `TRUE` and `FALSE` are one and zero, as three.js reads them.

        Raises:
            Error: If a setting is not a number, `TRUE` or `FALSE`.
        """
        var settings = Dict[String, Float64]()
        for extra in self.document.children_named(element, "extra"):
            for technique in self.document.children_named(extra, "technique"):
                for setting in self.document.children(technique):
                    var name = self.document.name(setting)
                    if (
                        name != "wrapU"
                        and name != "wrapV"
                        and name != "repeatU"
                        and name != "repeatV"
                        and name != "offsetU"
                        and name != "offsetV"
                    ):
                        continue
                    var text = String(self.document.text(setting).strip())
                    var upper = text.upper()
                    if upper == "TRUE":
                        settings[name] = 1
                    elif upper == "FALSE":
                        settings[name] = 0
                    else:
                        settings[name] = self.numbers(setting, 1, name)[0]
        return settings^

    # --- the scene --------------------------------------------------------------

    def read_scene(mut self, mut scene: Scene, mut assets: Assets) raises:
        """Place the visual scene `<scene>` names, and everything in it."""
        var top = self.document.child(self.document.root(), "scene")
        if top == NO_ELEMENT:
            raise Error("Collada: the file has no <scene>")
        var instance = self.document.child(top, "instance_visual_scene")
        if instance == NO_ELEMENT:
            raise Error("Collada: <scene> instances no visual scene")
        var url = _reference(self.document.attribute(instance, "url"))
        if url not in self.visual_scenes:
            raise Error("Collada: <scene> names no visual scene: " + url)
        var visual = self.visual_scenes[url]
        self.model.first_mesh = len(scene.meshes)
        self.model.first_line = len(scene.lines)
        self.model.first_light = len(scene.lights)
        var root = Object3D()
        root.name = self.document.attribute(visual, "name")
        root.set_quaternion(up_axis_rotation(self.model.up_axis))
        var size = Float32(self.model.unit.to(METER))
        root.set_scale(size, size, size)
        self.model.root = scene.add(root^)
        var top_node = self.model.root
        for node in self.document.children_named(visual, "node"):
            self.place_node(node, top_node, scene, assets, 0)
        self.model.mesh_count = len(scene.meshes) - self.model.first_mesh
        self.model.line_count = len(scene.lines) - self.model.first_line
        self.model.light_count = len(scene.lights) - self.model.first_light

    def node_matrix(self, element: Int) raises -> Matrix4:
        """Return a node's transform: its steps multiplied in file order,
        as three.js's `parseNode` multiplies them."""
        var matrix = Matrix4()
        for step in self.document.children(element):
            var name = self.document.name(step)
            if name == "matrix":
                var v = self.numbers(step, 16, "<matrix>")
                var m = Matrix4()
                # Collada writes a matrix row by row, as `set` reads one.
                m.set(
                    Float32(v[0]),
                    Float32(v[1]),
                    Float32(v[2]),
                    Float32(v[3]),
                    Float32(v[4]),
                    Float32(v[5]),
                    Float32(v[6]),
                    Float32(v[7]),
                    Float32(v[8]),
                    Float32(v[9]),
                    Float32(v[10]),
                    Float32(v[11]),
                    Float32(v[12]),
                    Float32(v[13]),
                    Float32(v[14]),
                    Float32(v[15]),
                )
                matrix.multiply(m)
            elif name == "translate":
                var v = self.numbers(step, 3, "<translate>")
                matrix.multiply(
                    translation(Float32(v[0]), Float32(v[1]), Float32(v[2]))
                )
            elif name == "rotate":
                var v = self.numbers(step, 4, "<rotate>")
                matrix.multiply(
                    _axis_rotation(
                        Vector3(Float32(v[0]), Float32(v[1]), Float32(v[2])),
                        Angle(Float32(v[3]), DEGREE),
                    )
                )
            elif name == "scale":
                var v = self.numbers(step, 3, "<scale>")
                matrix.multiply(
                    scaling(Float32(v[0]), Float32(v[1]), Float32(v[2]))
                )
        return matrix^

    def object_count(mut self, element: Int, mut assets: Assets) raises -> Int:
        """Return how many objects three.js's `buildNode` makes for a
        node's instances: one per camera and light the file has, one per
        kind of primitive of each geometry, and one per controller and
        instanced node."""
        var count = 0
        for child in self.document.children(element):
            var name = self.document.name(child)
            if name == "instance_camera":
                if self.known(child, self.cameras):
                    count += 1
            elif name == "instance_light":
                if self.known(child, self.lights):
                    count += 1
            elif name == "instance_geometry":
                var id = _reference(self.document.attribute(child, "url"))
                self.build_geometry(id, assets)
                var kinds = List[String]()
                for slot in range(self.built_count[id]):
                    var kind = self.built[self.built_at[id] + slot].kind
                    if kind not in kinds:
                        kinds.append(kind)
                count += len(kinds)
            elif name == "instance_controller" or name == "instance_node":
                count += 1
        return count

    def known(self, element: Int, library: Dict[String, Int]) raises -> Bool:
        """Return True if an instance's `url` names an entry of a
        library."""
        return _reference(self.document.attribute(element, "url")) in library

    def place_node(
        mut self,
        element: Int,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
        depth: Int,
    ) raises:
        """Add a `<node>` under its parent, then what it holds."""
        var placed = Object3D()
        decompose_onto(placed, self.node_matrix(element), "Collada")
        var name = self.document.attribute(element, "name")
        if self.document.attribute(element, "type") == "JOINT":
            name = self.document.attribute(element, "sid")
        placed.name = name
        var id = scene.attach(placed^, parent)
        self.model.nodes.append(id)
        self.model.node_names.append(name)
        if depth == 0:
            # The node itself, not a copy an `<instance_node>` placed: the
            # one three.js animates and binds as a bone.
            self.rig.placed[element] = id
        self.place_contents(element, id, scene, assets, depth)

    def place_contents(
        mut self,
        element: Int,
        id: NodeId,
        mut scene: Scene,
        mut assets: Assets,
        depth: Int,
    ) raises:
        """Place a node's child nodes and instances at the scene node
        `id`.

        three.js makes a node with no child nodes and one object into that
        object, at the node's transform; a node with more becomes a group
        with its objects inside at their own transforms. The difference
        shows only for a directional or a spot light, which three.js
        places one unit up its node's y when it is one object of several.
        """
        if depth > MAX_INSTANCE_DEPTH:
            raise Error("Collada: <instance_node> nests too deep")
        var children = self.document.children_named(element, "node")
        var alone = (
            len(children) == 0 and self.object_count(element, assets) == 1
        )
        for child in children:
            self.place_node(child, id, scene, assets, depth)
        for instance in self.document.children(element):
            var name = self.document.name(instance)
            if name == "instance_camera":
                self.place_camera(instance, id)
            elif name == "instance_light":
                self.place_light(instance, id, alone, scene)
            elif name == "instance_geometry":
                self.place_geometry(instance, id, scene, assets)
            elif name == "instance_controller":
                # Placed once every bone is.
                self.rig.waiting.append(_Controlled(instance, id))
            elif name == "instance_node":
                var url = _reference(self.document.attribute(instance, "url"))
                if url not in self.nodes:
                    raise Error(
                        "Collada: <instance_node> names no node: " + url
                    )
                if alone:
                    # The copy is the node's one object, so it takes the
                    # node's name and transform, and its own are lost.
                    self.place_contents(
                        self.nodes[url], id, scene, assets, depth + 1
                    )
                else:
                    self.place_node(
                        self.nodes[url], id, scene, assets, depth + 1
                    )

    def place_camera(mut self, instance: Int, node: NodeId) raises:
        """Add the camera an `<instance_camera>` names, riding its node,
        as three.js's `buildCamera` builds it. A camera the file does not
        have is skipped, as three.js skips it."""
        var url = _reference(self.document.attribute(instance, "url"))
        if url not in self.cameras:
            return
        var technique = NO_ELEMENT
        var optics = self.document.child(self.cameras[url], "optics")
        if optics != NO_ELEMENT:
            technique = self.document.child(optics, "technique_common")
        var projection = NO_ELEMENT
        var orthographic = False
        if technique != NO_ELEMENT:
            for child in self.document.children(technique):
                var name = self.document.name(child)
                if name == "perspective" or name == "orthographic":
                    projection = child
                    orthographic = name == "orthographic"
        var near = DEFAULT_NEAR
        var far = DEFAULT_FAR
        var aspect = Float64(1)
        if projection != NO_ELEMENT:
            near = self.number(projection, "znear", DEFAULT_NEAR)
            far = self.number(projection, "zfar", DEFAULT_FAR)
        if orthographic:
            var ratio = self.document.child(projection, "aspect_ratio")
            var x = self.document.child(projection, "xmag")
            var y = self.document.child(projection, "ymag")
            if x == NO_ELEMENT and y == NO_ELEMENT:
                raise Error(
                    "Collada: an orthographic camera needs xmag or ymag"
                )
            if (x == NO_ELEMENT or y == NO_ELEMENT) and ratio == NO_ELEMENT:
                raise Error(
                    "Collada: an orthographic camera with one of xmag and"
                    " ymag needs aspect_ratio"
                )
            var xmag: Float64
            var ymag: Float64
            if x == NO_ELEMENT:
                ymag = self.number(projection, "ymag", 0)
                xmag = ymag * self.number(projection, "aspect_ratio", 1)
            elif y == NO_ELEMENT:
                xmag = self.number(projection, "xmag", 0)
                ymag = xmag / self.number(projection, "aspect_ratio", 1)
            else:
                xmag = self.number(projection, "xmag", 0)
                ymag = self.number(projection, "ymag", 0)
            var camera = OrthographicCamera(
                Length(Float32(-xmag / 2), METER),
                Length(Float32(xmag / 2), METER),
                Length(Float32(ymag / 2), METER),
                Length(Float32(-ymag / 2), METER),
                Length(Float32(near), METER),
                Length(Float32(far), METER),
            )
            camera.attach(node)
            self.model.orthographic_cameras.append(camera^)
            return
        var fov = DEFAULT_FOV
        if projection != NO_ELEMENT:
            aspect = self.number(projection, "aspect_ratio", 1)
            if self.document.child(projection, "yfov") != NO_ELEMENT:
                fov = Angle(Float32(self.number(projection, "yfov", 0)), DEGREE)
        var camera = PerspectiveCamera(
            fov,
            Float32(aspect),
            Length(Float32(near), METER),
            Length(Float32(far), METER),
        )
        camera.attach(node)
        self.model.perspective_cameras.append(camera)

    def place_light(
        mut self, instance: Int, node: NodeId, alone: Bool, mut scene: Scene
    ) raises:
        """Add the light an `<instance_light>` names, at its node, as
        three.js's `buildLight` builds it. A light the file does not have
        is skipped, as three.js skips it."""
        var url = _reference(self.document.attribute(instance, "url"))
        if url not in self.lights:
            return
        var technique = self.document.child(
            self.lights[url], "technique_common"
        )
        var kind = NO_ELEMENT
        if technique != NO_ELEMENT:
            for child in self.document.children(technique):
                var name = self.document.name(child)
                if (
                    name == "directional"
                    or name == "point"
                    or name == "spot"
                    or name == "ambient"
                ):
                    kind = child
        if kind == NO_ELEMENT:
            raise Error(
                "Collada: a light has no directional, point, spot or ambient"
                " technique"
            )
        var color = _WHITE
        var tinted = self.document.child(kind, "color")
        if tinted != NO_ELEMENT:
            color = self.srgb(tinted)
        var distance = Float32(0)
        var attenuation = self.number(kind, "quadratic_attenuation", 0)
        if attenuation != 0:
            distance = Float32(sqrt(1 / attenuation))
        var name = self.document.name(kind)
        if name == "ambient":
            scene.add_light(ambient_light(color))
            return
        if name == "point":
            scene.add_light(point_light(color, node, distance=distance))
            return
        # three.js's directional and spot lights stand one unit up their
        # own y, which the node's transform replaces when the light is the
        # node's one object and does not when it is one of several.
        var at = node
        if not alone:
            var raised = Object3D()
            raised.set_position(0, 1, 0)
            at = scene.attach(raised^, node)
        if name == "directional":
            scene.add_light(directional_light(color, at))
        else:
            scene.add_light(
                spot_light(color, at, distance=distance, angle=DEFAULT_SPOT)
            )

    def place_geometry(
        mut self,
        instance: Int,
        node: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add a mesh or a line per primitive of the geometry an
        `<instance_geometry>` names, each with the material its symbol is
        bound to."""
        var id = _reference(self.document.attribute(instance, "url"))
        self.build_geometry(id, assets)
        var bindings = Dict[String, String]()
        for bind in self.document.children_named(instance, "bind_material"):
            self.collect_bindings(bind, bindings)
        for slot in range(self.built_count[id]):
            var built = self.built[self.built_at[id] + slot].copy()
            var material = self.material_for(
                built.symbol, bindings, built.lines, assets
            )
            if built.lines:
                scene.add_line(
                    Line(built.geometry, material, node, mode=SEGMENTS)
                )
            else:
                scene.add_mesh(Mesh(built.geometry, material, node))

    def collect_bindings(
        self, element: Int, mut bindings: Dict[String, String]
    ) raises:
        """Gather every `<instance_material>` inside an element, at any
        depth, as three.js's `getElementsByTagName` gathers them."""
        for child in self.document.children(element):
            if self.document.name(child) == "instance_material":
                bindings[self.document.attribute(child, "symbol")] = _reference(
                    self.document.attribute(child, "target")
                )
            else:
                self.collect_bindings(child, bindings)

    def default_material(
        mut self, key: String, material: Material, mut assets: Assets
    ) -> MaterialId:
        """Return one of the materials three.js makes when a file names
        none, making it the first time."""
        if key not in self.defaults:
            self.defaults[key] = assets.materials.add(material)
        return self.defaults.get(key, MaterialId(0))

    def material_for(
        mut self,
        symbol: String,
        bindings: Dict[String, String],
        lines: Bool,
        mut assets: Assets,
    ) raises -> MaterialId:
        """Return the material a primitive draws with.

        Args:
            symbol: The primitive's `material` symbol, or empty.
            bindings: Each symbol's material id, from the instance.
            lines: Whether the primitive is lines.
            assets: Where a default or a line copy goes.

        Returns:
            The material.

        Raises:
            Error: If a symbol is bound to a material id the file does
                not have.
        """
        if symbol == "":
            if lines:
                return self.default_material(
                    "line", Material(_WHITE, kind=BASIC), assets
                )
            return self.default_material(
                "mesh",
                Material(
                    _WHITE, kind=PHONG, specular=Color(17, 17, 17), shininess=30
                ),
                assets,
            )
        if symbol not in bindings:
            return self.default_material(
                "fallback", Material(FALLBACK_COLOR, kind=BASIC), assets
            )
        var target = bindings[symbol]
        var index = -1
        for at in range(len(self.model.material_ids)):
            if self.model.material_ids[at] == target:
                index = at
        if index < 0:
            raise Error("Collada: a symbol is bound to no material: " + target)
        var found = self.model.materials[index]
        if not lines:
            return found
        var surface = assets.materials.get(found)
        if surface.kind == BASIC:
            return found
        # A lit material on a line is replaced by a basic one of its color,
        # opacity and blending, as three.js replaces it.
        if index not in self.line_materials:
            self.line_materials[index] = assets.materials.add(
                Material(
                    surface.color,
                    opacity=surface.opacity,
                    kind=BASIC,
                    transparent=surface.transparent,
                )
            )
        return self.line_materials[index]

    # --- geometry ---------------------------------------------------------------

    def build_geometry(mut self, id: String, mut assets: Assets) raises:
        """Build a geometry's primitives the first time it is instanced.

        Raises:
            Error: If the file has no geometry of the id, or it has no
                `<mesh>`, or a primitive is refused.
        """
        if id in self.built_at:
            return
        if id not in self.geometries:
            raise Error("Collada: <instance_geometry> names no geometry: " + id)
        var mesh = self.document.child(self.geometries[id], "mesh")
        if mesh == NO_ELEMENT:
            raise Error("Collada: a geometry has no <mesh>: " + id)
        var sources = Dict[String, _Source]()
        for source in self.document.children_named(mesh, "source"):
            var values = List[Float64]()
            var array = self.document.child(source, "float_array")
            if array != NO_ELEMENT:
                values = _floats(self.document.text(array))
            var stride = 1
            var common = self.document.child(source, "technique_common")
            if common != NO_ELEMENT:
                var accessor = self.document.child(common, "accessor")
                if accessor != NO_ELEMENT:
                    stride = _ints(
                        self.document.attribute(accessor, "stride", "1")
                    )[0]
            if stride < 1:
                raise Error("Collada: a source's stride must be positive")
            sources[self.document.attribute(source, "id")] = _Source(
                values^, stride
            )
        var vertices = List[_Input]()
        var shared = self.document.child(mesh, "vertices")
        if shared != NO_ELEMENT:
            for input in self.document.children_named(shared, "input"):
                vertices.append(
                    _Input(
                        self.document.attribute(input, "semantic"),
                        _reference(self.document.attribute(input, "source")),
                        0,
                    )
                )
        self.built_at[id] = len(self.built)
        for primitive in self.document.children(mesh):
            var kind = self.document.name(primitive)
            if (
                kind == "triangles"
                or kind == "polylist"
                or kind == "polygons"
                or kind == "lines"
                or kind == "linestrips"
            ):
                self.build_primitive(primitive, kind, sources, vertices, assets)
        self.built_count[id] = len(self.built) - self.built_at[id]

    def build_primitive(
        mut self,
        primitive: Int,
        kind: String,
        sources: Dict[String, _Source],
        vertices: List[_Input],
        mut assets: Assets,
    ) raises:
        """Build one primitive's geometry and record it.

        Args:
            primitive: The `<triangles>`, `<polylist>`, `<polygons>`,
                `<lines>` or `<linestrips>`.
            kind: Its name.
            sources: The mesh's sources by id.
            vertices: The inputs its `<vertices>` gives.
            assets: Where the geometry goes.

        Raises:
            Error: If it has no inputs, an input names no source, the
                indices do not fill whole corners and faces, an index is
                out of range, or it has corners and no positions.
        """
        var inputs = List[_Input]()
        var stride = 0
        for input in self.document.children_named(primitive, "input"):
            var semantic = self.document.attribute(input, "semantic")
            var offset = _ints(self.document.attribute(input, "offset", "x"))
            if len(offset) != 1 or offset[0] < 0:
                raise Error("Collada: an input needs one offset, not negative")
            var set = _ints(self.document.attribute(input, "set", "0"))
            if len(set) == 1 and set[0] > 0:
                semantic += String(set[0])
            inputs.append(
                _Input(
                    semantic,
                    _reference(self.document.attribute(input, "source")),
                    offset[0],
                )
            )
            stride = max(stride, offset[0] + 1)
        if stride == 0:
            raise Error("Collada: a primitive has no inputs")
        # Every `<p>`, one after another, and the corners of each run.
        var indices = List[Int]()
        var runs = List[Int]()
        for p in self.document.children_named(primitive, "p"):
            var values = _ints(self.document.text(p))
            if len(values) % stride != 0:
                raise Error("Collada: a <p> does not hold whole corners")
            runs.append(len(values) // stride)
            indices.extend(values^)
        if self.document.child(primitive, "ph") != NO_ELEMENT:
            raise Error("Collada: a polygon with holes is not read")
        var total = len(indices) // stride
        var order = List[Int]()
        var lines = kind == "lines" or kind == "linestrips"
        if kind == "triangles" or kind == "lines":
            var size = 3
            if lines:
                size = 2
            if total % size != 0:
                raise Error("Collada: <" + kind + "> does not hold whole faces")
            for corner in range(total):
                order.append(corner)
        elif kind == "linestrips":
            var start = 0
            for run in runs:
                for step in range(run - 1):
                    order.append(start + step)
                    order.append(start + step + 1)
                start += run
        else:
            var counts = runs.copy()
            if kind == "polylist":
                counts = List[Int]()
                var vcount = self.document.child(primitive, "vcount")
                if vcount != NO_ELEMENT:
                    counts = _ints(self.document.text(vcount))
                var sum = 0
                for count in counts:
                    sum += count
                if sum != total:
                    raise Error(
                        "Collada: a <polylist>'s vcount does not match its <p>"
                    )
            _polygon_order(counts, order)
        var corners = _Corners()
        for corner in order:
            var base = corner * stride
            # A primitive with no inputs was refused above: the loop always
            # runs.
            for input in inputs:  # pragma: no branch
                var index = indices[base + input.offset]
                if input.name == "VERTEX":
                    for shared in vertices:
                        self.gather(
                            shared.name, sources, shared.source, index, corners
                        )
                else:
                    self.gather(
                        input.name, sources, input.source, index, corners
                    )
        var count = len(order)
        if count == 0:
            return
        if len(corners.positions) != count * 3:
            raise Error(
                "Collada: a primitive's positions do not match its corners"
            )
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(corners.positions.copy(), 3)
        )
        _optional(geometry, NORMAL, corners.normals, 3, count)
        _optional(geometry, COLOR, corners.colors, corners.color_size, count)
        if not lines:
            _optional(geometry, UV, corners.uvs, 2, count)
        var id = assets.geometries.add(geometry^)
        self.model.geometries.append(id)
        self.built.append(
            _Built(
                id,
                lines,
                self.document.attribute(primitive, "material"),
                kind,
                corners.vertices.copy(),
            )
        )

    def gather(
        self,
        name: String,
        sources: Dict[String, _Source],
        source: String,
        index: Int,
        mut corners: _Corners,
    ) raises:
        """Append one corner's values of one input to where they go:
        `POSITION`, `NORMAL`, `COLOR` or `TEXCOORD`. Any other input is
        skipped, as three.js skips it.

        Raises:
            Error: If the source is not there, the index is outside it,
                or the source is too narrow for what it gives.
        """
        var width: Int
        if name == "POSITION" or name == "NORMAL":
            width = 3
        elif name == "TEXCOORD":
            width = 2
        elif name == "COLOR":
            width = 3
        else:
            return
        if source not in sources:
            raise Error("Collada: an input names no source: " + source)
        ref found = sources[source]
        if found.stride < width:
            raise Error("Collada: a source is too narrow for " + name)
        var start = index * found.stride
        if index < 0 or start + found.stride > len(found.values):
            raise Error(
                "Collada: an index outside its source: " + String(index)
            )
        if name == "POSITION":
            corners.vertices.append(index)
            for axis in range(3):  # pragma: no branch
                corners.positions.append(Float32(found.values[start + axis]))
        elif name == "NORMAL":
            for axis in range(3):  # pragma: no branch
                corners.normals.append(Float32(found.values[start + axis]))
        elif name == "TEXCOORD":
            corners.uvs.append(Float32(found.values[start]))
            corners.uvs.append(Float32(found.values[start + 1]))
        else:
            # A vertex color is sRGB, and a geometry's is linear; its
            # alpha is kept when the source has one.
            if found.stride > 4:
                raise Error("Collada: a color source has more than 4 values")
            corners.color_size = found.stride
            for channel in range(found.stride):  # pragma: no branch
                var value = Float32(found.values[start + channel])
                if channel < 3:
                    value = srgb_to_linear(value)
                corners.colors.append(value)

    # --- skins and animations ---------------------------------------------

    def place_controllers(
        mut self, mut scene: Scene, mut assets: Assets
    ) raises:
        """Place every `<instance_controller>`, now that every bone is in
        the scene, as three.js's `buildNode` places it.

        Raises:
            Error: If an instance names no controller, the controller is a
                `<morph>` or has no `<skin>`, the skin is malformed, or its
                skeleton cannot be built.
        """
        if len(self.rig.waiting) == 0:
            return
        for index in range(self.document.count()):  # pragma: no branch
            if self.document.name(index) == "controller":
                var id = self.document.attribute(index, "id")
                if id != "":
                    self.rig.controllers[id] = index
        # The list is not empty, or the function returned above.
        for waiting in self.rig.waiting.copy():  # pragma: no branch
            var url = _reference(
                self.document.attribute(waiting.instance, "url")
            )
            if url not in self.rig.controllers:
                raise Error(
                    "Collada: <instance_controller> names nothing: " + url
                )
            var controller = self.rig.controllers[url]
            var skin = self.document.child(controller, "skin")
            if skin == NO_ELEMENT:
                if self.document.child(controller, "morph") != NO_ELEMENT:
                    raise Error(
                        "Collada: a morph controller is not read, as three.js"
                        " does not read one"
                    )
                raise Error("Collada: a controller has no <skin>")
            var geometry = _reference(self.document.attribute(skin, "source"))
            self.build_geometry(geometry, assets)
            var data = self.read_skin(skin)
            var skeleton = self.skeleton_for(waiting.instance, data, assets)
            var bindings = Dict[String, String]()
            for bind in self.document.children_named(
                waiting.instance, "bind_material"
            ):
                self.collect_bindings(bind, bindings)
            for slot in range(self.built_count[geometry]):
                var built = self.built[self.built_at[geometry] + slot].copy()
                var material = self.material_for(
                    built.symbol, bindings, built.lines, assets
                )
                if built.lines:
                    # three.js draws a line of a skinned geometry unskinned.
                    scene.add_line(
                        Line(
                            built.geometry,
                            material,
                            waiting.node,
                            mode=SEGMENTS,
                        )
                    )
                    continue
                var key = url + "#" + String(slot)
                if key not in self.rig.skinned:
                    var shape = assets.geometries.get(built.geometry).clone()
                    data.apply(built.vertices, shape)
                    var made = assets.geometries.add(shape^)
                    self.model.geometries.append(made)
                    self.rig.skinned[key] = made
                scene.add_skinned_mesh(
                    SkinnedMesh(
                        self.rig.skinned[key],
                        material,
                        waiting.node,
                        skeleton.copy(),
                        data.bind,
                    )
                )

    def skin_source(self, sources: Dict[String, Int], id: String) raises -> Int:
        """Return a skin's `<source>` of an id.

        Raises:
            Error: If the skin has none.
        """
        if id not in sources:
            raise Error("Collada: a skin names no source: " + id)
        return sources[id]

    def skin_inputs(
        self, element: Int
    ) raises -> Dict[String, Tuple[String, Int]]:
        """Return the `<input>`s of a `<joints>` or a `<vertex_weights>`:
        each semantic's source and offset."""
        var inputs = Dict[String, Tuple[String, Int]]()
        for input in self.document.children_named(element, "input"):
            var offset = _ints(self.document.attribute(input, "offset", "0"))
            if len(offset) != 1:
                raise Error("Collada: an input needs one offset")
            inputs[self.document.attribute(input, "semantic")] = (
                _reference(self.document.attribute(input, "source")),
                offset[0],
            )
        return inputs^

    def read_skin(self, skin: Int) raises -> _Skin:
        """Read a `<skin>`: its bind shape matrix, its joints' names and
        inverse binds, and each vertex's four bones and weights, as
        three.js's `buildSkin` reads them.

        Raises:
            Error: If it has no `<joints>` or `<vertex_weights>`, an input
                is missing or names no source, the joint names are not a
                `Name_array`, a matrix or a weight is out of range, or an
                index names no joint.
        """
        var data = _Skin()
        var shape = self.document.child(skin, "bind_shape_matrix")
        if shape != NO_ELEMENT:
            data.bind = _row_major(
                self.numbers(shape, 16, "<bind_shape_matrix>"), 0
            )
        var sources = Dict[String, Int]()
        for source in self.document.children_named(skin, "source"):
            sources[self.document.attribute(source, "id")] = source
        var joints = self.document.child(skin, "joints")
        var weights = self.document.child(skin, "vertex_weights")
        if joints == NO_ELEMENT:
            raise Error("Collada: a skin needs <joints>")
        if weights == NO_ELEMENT:
            raise Error("Collada: a skin needs <vertex_weights>")
        var joint_inputs = self.skin_inputs(joints)
        var weight_inputs = self.skin_inputs(weights)
        _require(joint_inputs, "JOINT", "<joints>")
        _require(joint_inputs, "INV_BIND_MATRIX", "<joints>")
        _require(weight_inputs, "JOINT", "<vertex_weights>")
        _require(weight_inputs, "WEIGHT", "<vertex_weights>")
        var names = self.document.child(
            self.skin_source(sources, joint_inputs["JOINT"][0]), "Name_array"
        )
        if names == NO_ELEMENT:
            raise Error("Collada: a skin's joints must be a Name_array")
        for piece in self.document.text(names).split():
            data.names.append(String(piece))
        var inverses = self.source_of(
            self.skin_source(sources, joint_inputs["INV_BIND_MATRIX"][0])
        )
        for joint in range(len(data.names)):
            var start = joint * inverses.stride
            if start + 16 > len(inverses.values):
                raise Error("Collada: a joint has no inverse bind matrix")
            data.inverses.append(_row_major(inverses.values, start))
        var shares = self.source_of(
            self.skin_source(sources, weight_inputs["WEIGHT"][0])
        ).values.copy()
        var joint_at = weight_inputs["JOINT"][1]
        var weight_at = weight_inputs["WEIGHT"][1]
        var counts = List[Int]()
        var found = self.document.child(weights, "vcount")
        if found != NO_ELEMENT:
            counts = _ints(self.document.text(found))
        var pairs = List[Int]()
        found = self.document.child(weights, "v")
        if found != NO_ELEMENT:
            pairs = _ints(self.document.text(found))
        var stride = 0
        for count in counts:
            var bones = List[Int]()
            var amounts = List[Float64]()
            for _ in range(count):
                # three.js steps two numbers per influence, whatever the
                # inputs are.
                if stride + max(joint_at, weight_at) >= len(pairs):
                    raise Error("Collada: <v> is shorter than <vcount> needs")
                var bone = pairs[stride + joint_at]
                var share = pairs[stride + weight_at]
                if not _within(bone, len(data.names)):
                    raise Error(
                        "Collada: a joint index outside the joints: "
                        + String(bone)
                    )
                if not _within(share, len(shares)):
                    raise Error("Collada: a weight index outside the weights")
                # Largest first, equal weights keeping their order, as
                # three.js's stable sort keeps them.
                var at = _sorted_place(amounts, shares[share])
                bones.insert(at, bone)
                amounts.insert(at, shares[share])
                stride += 2
            var four = SIMD[DType.float32, 4](0)
            for lane in range(4):  # pragma: no branch
                var bone = 0
                if lane < len(amounts):
                    bone = bones[lane]
                    four[lane] = Float32(amounts[lane])
                data.bones.append(Float32(bone))
            var scaled = normalized_skin_weights(four)
            for lane in range(4):  # pragma: no branch
                data.weights.append(scaled[lane])
        return data^

    def source_of(self, element: Int) raises -> _Source:
        """Return a skin `<source>`'s numbers and stride, three when it
        names none, as three.js's `parseSource` reads them."""
        var values = List[Float64]()
        var array = self.document.child(element, "float_array")
        if array != NO_ELEMENT:
            values = _floats(self.document.text(array))
        var stride = 3
        var common = self.document.child(element, "technique_common")
        if common != NO_ELEMENT:
            var accessor = self.document.child(common, "accessor")
            if accessor != NO_ELEMENT:
                stride = _ints(
                    self.document.attribute(accessor, "stride", "3")
                )[0]
        if stride < 1:
            raise Error("Collada: a source's stride must be positive")
        return _Source(values^, stride)

    def is_bone(mut self, element: Int, mut assets: Assets) raises -> Bool:
        """Return True if three.js makes a node a `Bone`: a `JOINT` that
        is not one object alone."""
        if self.document.attribute(element, "type") != "JOINT":
            return False
        return not (
            len(self.document.children_named(element, "node")) == 0
            and self.object_count(element, assets) == 1
        )

    def collect_bones(
        mut self, element: Int, mut bones: List[Int], mut assets: Assets
    ) raises:
        """Gather the bones under a node, itself first, as three.js's
        `traverse` meets them."""
        if self.is_bone(element, assets):
            bones.append(element)
        for child in self.document.children_named(element, "node"):
            self.collect_bones(child, bones, assets)

    def skeleton_for(
        mut self, instance: Int, data: _Skin, mut assets: Assets
    ) raises -> Skeleton:
        """Build an instance's skeleton, as three.js's `buildSkeleton` and
        `buildBoneHierarchy` build it.

        Raises:
            Error: If a `<skeleton>` names neither a node nor a visual
                scene, a joint names no bone, a bone is not in the scene,
                or the skeleton has no bone.
        """
        var found = List[Int]()
        for root in self.document.children_named(instance, "skeleton"):
            var id = _reference(String(self.document.text(root).strip()))
            if id in self.nodes:
                self.collect_bones(self.nodes[id], found, assets)
            elif id in self.visual_scenes:
                for child in self.document.children_named(
                    self.visual_scenes[id], "node"
                ):
                    if self.document.attribute(child, "type") == "JOINT":
                        self.collect_bones(child, found, assets)
            else:
                raise Error("Collada: a <skeleton> names no node: " + id)
        var used = List[Bool](length=len(found), fill=False)
        var order = List[Int]()
        for name in data.names:
            var hit = -1
            for at in range(len(found)):
                if self.document.attribute(found[at], "sid") == name:
                    hit = at
                    break
            if hit < 0:
                raise Error("Collada: a joint names no bone: " + name)
            used[hit] = True
            order.append(hit)
        for at in range(len(found)):
            if not used[at]:
                order.append(at)
        var bones = List[Bone]()
        for at in order:
            var element = found[at]
            if element not in self.rig.placed:
                raise Error("Collada: a bone is not in the scene")
            # The inverse of the first joint of the bone's name, or the
            # identity for a bone the controller does not name.
            var inverse = Matrix4()
            var sid = self.document.attribute(element, "sid")
            for joint in range(len(data.names) - 1, -1, -1):
                if data.names[joint] == sid:
                    inverse = data.inverses[joint]
            bones.append(Bone(self.rig.placed[element], inverse))
        return Skeleton(bones^)

    def read_animations(mut self) raises:
        """Read the animations and the clips onto the placed nodes."""
        var matrices = Dict[Int, Matrix4]()
        for element in self.rig.placed.keys():
            matrices[element] = self.node_matrix(element)
        self.model.animations = read_collada_animations(
            self.document, self.nodes, self.rig.placed, matrices
        )


def _polygon_order(counts: List[Int], mut order: List[Int]):
    """Append the corners of each polygon's triangles, as three.js's
    `buildGeometryData` cuts them: a quad into (a, b, d) and (b, c, d),
    a larger polygon into a fan from its first corner, and a polygon of
    fewer than three corners into nothing.

    Args:
        counts: How many corners each polygon has, in order.
        order: Where the corners go, three per triangle.
    """
    var start = 0
    for count in counts:
        if count == 4:
            for step in [0, 1, 3, 1, 2, 3]:  # pragma: no branch
                order.append(start + step)
        elif count >= 3:
            for k in range(1, count - 1):  # pragma: no branch
                order.append(start)
                order.append(start + k)
                order.append(start + k + 1)
        start += count


def _optional(
    mut geometry: BufferGeometry,
    name: StaticString,
    values: List[Float32],
    size: Int,
    corners: Int,
) raises:
    """Set an attribute that a primitive can leave out, refusing one that
    covers some corners and not others.

    Args:
        geometry: The geometry.
        name: The attribute.
        values: Its values; empty when the primitive gives none.
        size: How many values make one corner's.
        corners: How many corners the primitive has.

    Raises:
        Error: If there are values and not one set per corner, which is
            what two inputs of one meaning give.
    """
    if len(values) == 0:
        return
    if len(values) != size * corners:
        raise Error(
            "Collada: a primitive's "
            + String(name)
            + " does not match its corners"
        )
    geometry.set_attribute(String(name), BufferAttribute(values.copy(), size))
