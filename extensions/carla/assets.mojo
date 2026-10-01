# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Photoscanned assets for a CARLA town: the manifest and the registry.

`assets/carla/manifest.json` names each asset the town can wear: a PBR
texture set, an HDRI sky or a glTF model. Each entry has an id, a kind, a
license (CC0 or CC BY 4.0), an author, a source page, a note on where it
came from, and its files, each with a role, a URL, a SHA-256 sum and a
path in the cache. `assets/carla/tools/carla_assets.py` downloads the files into
`.cache/carla-assets/` and checks each sum before it keeps a file.

**Bindings.** The manifest's `bindings` table maps a key to an entry id,
or to null for the procedural asset. A key is a CARLA blueprint id, such
as `vehicle.tesla.model3`, a family's wildcard, such as `vehicle.*`, or a
surface key: `surface.road`, `ground.grass`, `sky.clear`, `tree`. The table is data, so an export of CARLA's own CC BY models can
replace a stand-in one key at a time, and no code changes.

**The fallback.** `AssetRegistry.cached_entry` gives an entry only when
the key is bound and every file the entry reads is in the cache. For any
other key the caller keeps its procedural asset, so a build, a test or a
CI run never needs a download.

**What each kind becomes.**

- A texture set becomes a `TextureSet`: its albedo in sRGB, and its
  normal, roughness and ambient occlusion maps in linear light, each
  repeating every `tile_meters`. A missing map is a flat one. A
  displacement map becomes the bump map when the set has no normal map,
  since the town's meshes are too coarse to be displaced.
- An HDRI becomes a float equirectangular texture, from a Radiance `.hdr`
  file. `render_sky` turns it into the sky.
- A model is read by `loaders.gltf.read_gltf` and hung under a pivot. The
  pivot turns the model's forward axis to plus x, scales it evenly to fit
  a box, and stands it on the pivot's origin, centered. Its materials
  reflect the scene's environment.

The kinds, the roles and the licenses are types, and the manifest reader
refuses a value outside them.
"""

from core.assets import Assets
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from extensions.carla.mesh_factory import (
    CROSSWALK_SURFACE,
    CURB_SURFACE,
    ROAD_SURFACE,
    SIDEWALK_SURFACE,
    SurfaceKind,
    WALL_SURFACE,
    WHITE_MARK_SURFACE,
    YELLOW_MARK_SURFACE,
)
from extensions.carla.render_textures import SurfaceMaps
from loaders.gltf import decode_image, read_gltf
from loaders.json import (
    ARRAY,
    JsonDocument,
    NO_NODE,
    NUMBER,
    OBJECT,
    STRING,
    parse_json,
)
from materials.material import Material, MaterialId
from objects.lod import Lod
from math.bounds import Box3
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.cube_texture_store import NO_CUBE_TEXTURE, SCENE_ENVIRONMENT
from render.rgbe import decode as decode_rgbe
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    IGNORED,
    REPEAT,
    Texture,
    float_texture_from,
    texture_from,
)
from render.tasks import TaskGroup
from render.texture_store import NO_TEXTURE
from std.pathlib import Path
from units.si import DEGREE, METER, Angle, Length


@fieldwise_init
struct AssetKind(Equatable, ImplicitlyCopyable, Writable):
    """What a manifest entry is: a texture set, an HDRI, a model or a
    town."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the four kinds.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3

    def write_to(self, mut writer: Some[Writer]):
        """Write the kind's number.

        Args:
            writer: The destination.
        """
        writer.write("AssetKind(", self.value, ")")


comptime TEXTURE_SET_ASSET = AssetKind(0)
comptime HDRI_ASSET = AssetKind(1)
comptime MODEL_ASSET = AssetKind(2)
# A whole CARLA town, placed as it is: see `AssetRegistry.place_town`.
comptime TOWN_ASSET = AssetKind(3)


@fieldwise_init
struct AssetRole(Equatable, ImplicitlyCopyable, Writable):
    """What one file of an entry holds."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the eight roles.

        Returns:
            Whether the value is from 0 to 7.
        """
        return self.value >= 0 and self.value <= 7

    def write_to(self, mut writer: Some[Writer]):
        """Write the role's number.

        Args:
            writer: The destination.
        """
        writer.write("AssetRole(", self.value, ")")


# A texture set's maps.
comptime ALBEDO_ROLE = AssetRole(0)
comptime NORMAL_ROLE = AssetRole(1)
comptime ROUGHNESS_ROLE = AssetRole(2)
comptime AO_ROLE = AssetRole(3)
comptime DISPLACEMENT_ROLE = AssetRole(4)
# An HDRI's panorama.
comptime HDRI_ROLE = AssetRole(5)
# A model's glTF file, and a file it reads: a buffer or a texture.
comptime MODEL_ROLE = AssetRole(6)
comptime SUPPORT_ROLE = AssetRole(7)


@fieldwise_init
struct AssetLicense(Equatable, ImplicitlyCopyable, Writable):
    """The license an entry is under: CC0 1.0 or CC BY 4.0."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for CC0 or CC BY.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1

    def needs_credit(self) -> Bool:
        """Return True when the license asks for attribution.

        Returns:
            Whether this is CC BY 4.0.
        """
        return self.value == 1

    def write_to(self, mut writer: Some[Writer]):
        """Write the license's number.

        Args:
            writer: The destination.
        """
        writer.write("AssetLicense(", self.value, ")")


comptime CC0_LICENSE = AssetLicense(0)
comptime CC_BY_LICENSE = AssetLicense(1)


def asset_kind_of(name: String) raises -> AssetKind:
    """Return the kind a manifest names.

    Args:
        name: `texture_set`, `hdri`, `model` or `town`.

    Returns:
        The kind.

    Raises:
        Error: If the name is none of the four.
    """
    if name == "texture_set":
        return TEXTURE_SET_ASSET
    if name == "hdri":
        return HDRI_ASSET
    if name == "model":
        return MODEL_ASSET
    if name == "town":
        return TOWN_ASSET
    raise Error(
        "An asset kind is texture_set, hdri, model or town, not " + name
    )


def asset_role_of(name: String) raises -> AssetRole:
    """Return the role a manifest names.

    Args:
        name: `albedo`, `normal`, `roughness`, `ao`, `displacement`,
            `hdri`, `model` or `support`.

    Returns:
        The role.

    Raises:
        Error: If the name is none of the eight.
    """
    var names: List[String] = [
        "albedo",
        "normal",
        "roughness",
        "ao",
        "displacement",
        "hdri",
        "model",
        "support",
    ]
    for index in range(len(names)):
        if names[index] == name:
            return AssetRole(index)
    raise Error("An asset file's role is not one the registry reads: " + name)


def asset_license_of(name: String) raises -> AssetLicense:
    """Return the license a manifest names, by its SPDX id.

    Args:
        name: `CC0-1.0` or `CC-BY-4.0`.

    Returns:
        The license.

    Raises:
        Error: If the id is neither.
    """
    if name == "CC0-1.0":
        return CC0_LICENSE
    if name == "CC-BY-4.0":
        return CC_BY_LICENSE
    raise Error("An asset's license is CC0-1.0 or CC-BY-4.0, not " + name)


def forward_yaw(axis: String) raises -> Angle:
    """Return the turn about plus y that brings a model's forward axis to
    plus x.

    Args:
        axis: `+x`, `-x`, `+z` or `-z`. glTF's convention is `+z`.

    Returns:
        0, 180, 90 or -90 degrees.

    Raises:
        Error: If the axis is none of the four.
    """
    if axis == "+x":
        return Angle(0, DEGREE)
    if axis == "-x":
        return Angle(180, DEGREE)
    if axis == "+z":
        return Angle(90, DEGREE)
    if axis == "-z":
        return Angle(-90, DEGREE)
    raise Error("A model's forward axis is +x, -x, +z or -z, not " + axis)


@fieldwise_init
struct AssetFile(Copyable, Movable):
    """One file the registry reads: its role and its path in the cache."""

    var role: AssetRole
    # Relative to the cache.
    var path: String
    # The expected SHA-256, or empty when the manifest has not pinned it.
    var sha256: String


struct AssetEntry(Copyable, Movable, Writable):
    """One asset of the manifest."""

    var id: String
    var kind: AssetKind
    var license: AssetLicense
    var title: String
    var author: String
    var source: String
    var provenance: String
    # How far one tile of a texture set reaches; zero for other kinds.
    var tile: Length
    # The turn that brings a model's forward axis to plus x.
    var yaw: Angle
    # The files the registry reads: an archive's members, not the
    # archive.
    var files: List[AssetFile]

    def __init__(out self, id: String, kind: AssetKind, license: AssetLicense):
        """Start an entry with no files.

        Args:
            id: The entry's id.
            kind: What it is.
            license: Its license.
        """
        self.id = id
        self.kind = kind
        self.license = license
        self.title = id
        self.author = String()
        self.source = String()
        self.provenance = String()
        self.tile = Length(0, METER)
        self.yaw = Angle(0, DEGREE)
        self.files = List[AssetFile]()

    def file(self, role: AssetRole) -> Optional[String]:
        """Return the path of the entry's file in a role.

        Args:
            role: The role.

        Returns:
            The first such file's path, or None.
        """
        for f in self.files:
            if f.role == role:
                return f.path
        return None

    def write_to(self, mut writer: Some[Writer]):
        """Write the id and the kind.

        Args:
            writer: The destination.
        """
        writer.write("AssetEntry(", self.id, ", ", self.kind, ")")


def _text(document: JsonDocument, node: Int, key: String) raises -> String:
    """Return a required string member."""
    var at = document.get(node, key)
    if at == NO_NODE or document.kind(at) != STRING:
        raise Error("A manifest entry needs the string " + key)
    return document.string(at)


def _optional_text(
    document: JsonDocument, node: Int, key: String, fallback: String
) raises -> String:
    """Return a string member, or the fallback when it is absent."""
    var at = document.get(node, key)
    if at == NO_NODE:
        return fallback
    if document.kind(at) != STRING:
        raise Error("A manifest entry's " + key + " must be a string")
    return document.string(at)


def _file(
    document: JsonDocument, node: Int, kind: AssetKind
) raises -> AssetFile:
    """Read one file, and check its role fits the entry's kind."""
    var role = asset_role_of(_text(document, node, "role"))
    var fits = (
        role.value
        <= DISPLACEMENT_ROLE.value if kind
        == TEXTURE_SET_ASSET else (
            role
            == HDRI_ROLE if kind
            == HDRI_ASSET else role.value
            >= MODEL_ROLE.value
        )
    )
    if not fits:
        raise Error("A manifest file's role does not fit its entry's kind")
    var path = _text(document, node, "path")
    if path.byte_length() == 0 or path.startswith("/") or ".." in path:
        raise Error("A manifest path must stay inside the cache: " + path)
    var sum = String()
    var at = document.get(node, "sha256")
    if at != NO_NODE and document.kind(at) == STRING:
        sum = document.string(at)
    return AssetFile(role, path, sum)


def _entry(document: JsonDocument, node: Int) raises -> AssetEntry:
    """Read one entry."""
    if document.kind(node) != OBJECT:
        raise Error("A manifest entry must be an object")
    var id = _text(document, node, "id")
    var entry = AssetEntry(
        id,
        asset_kind_of(_text(document, node, "kind")),
        asset_license_of(_text(document, node, "license")),
    )
    entry.title = _optional_text(document, node, "title", id)
    entry.author = _text(document, node, "author")
    entry.source = _text(document, node, "source")
    entry.provenance = _text(document, node, "provenance")
    var files = document.get(node, "files")
    if files == NO_NODE or document.kind(files) != ARRAY:
        raise Error("A manifest entry needs a list of files")
    for index in range(document.length(files)):
        var item = document.at(files, index)
        var role = _text(document, item, "role")
        if role == "archive":
            var members = document.get(item, "extract")
            if members == NO_NODE or document.kind(members) != ARRAY:
                raise Error("A manifest archive must list what it extracts")
            for m in range(document.length(members)):
                entry.files.append(
                    _file(document, document.at(members, m), entry.kind)
                )
        else:
            entry.files.append(_file(document, item, entry.kind))
    if entry.kind == TEXTURE_SET_ASSET:
        var tile = document.get(node, "tile_meters")
        if tile == NO_NODE or document.kind(tile) != NUMBER:
            raise Error("A texture set needs its tile_meters")
        var meters = Float32(document.number(tile))
        if not (meters > 0):
            raise Error("A texture set's tile_meters must be positive")
        entry.tile = Length(meters, METER)
        if not Bool(entry.file(ALBEDO_ROLE)):
            raise Error("A texture set needs an albedo map")
    elif entry.kind == MODEL_ASSET:
        entry.yaw = forward_yaw(_text(document, node, "forward"))
        if not Bool(entry.file(MODEL_ROLE)):
            raise Error("A model entry needs its model file")
    elif entry.kind == TOWN_ASSET:
        if not Bool(entry.file(MODEL_ROLE)):
            raise Error("A town entry needs its model file")
    elif not Bool(entry.file(HDRI_ROLE)):
        raise Error("An HDRI entry needs its panorama")
    return entry^


struct AssetManifest(Copyable, Movable):
    """The manifest's entries and its binding table."""

    var entries: List[AssetEntry]
    # The table: each key, and the entry id it names or empty for null.
    var keys: List[String]
    var values: List[String]

    def __init__(out self):
        """Start with no entries and no bindings."""
        self.entries = List[AssetEntry]()
        self.keys = List[String]()
        self.values = List[String]()

    def find(self, id: String) -> Optional[Int]:
        """Return an entry's index.

        Args:
            id: The entry's id.

        Returns:
            Its index in `entries`, or None.
        """
        for index in range(len(self.entries)):
            if self.entries[index].id == id:
                return index
        return None

    def binding(self, key: String) -> Optional[String]:
        """Return the entry a key is bound to.

        Args:
            key: A blueprint id or a surface key.

        Returns:
            The entry's id, or None when the key is absent or bound to
            null.
        """
        for index in range(len(self.keys)):
            if self.keys[index] == key:
                if self.values[index].byte_length() == 0:
                    return None
                return self.values[index]
        return None

    def is_bound(self, key: String) -> Bool:
        """Return True when the table has a key, even one bound to null.

        Args:
            key: The key.

        Returns:
            Whether the key is in the table.
        """
        for k in self.keys:
            if k == key:
                return True
        return False

    def credits(self) -> List[String]:
        """Return one attribution line for each CC BY entry.

        Returns:
            `"<title>" by <author>, <source>, CC BY 4.0`, in the
            manifest's order.
        """
        var lines = List[String]()
        for e in self.entries:
            if e.license.needs_credit():
                lines.append(
                    '"'
                    + e.title
                    + '" by '
                    + e.author
                    + ", "
                    + e.source
                    + ", CC BY 4.0"
                )
        return lines^


def parse_manifest(text: String) raises -> AssetManifest:
    """Read a manifest's JSON.

    Args:
        text: The JSON.

    Returns:
        The manifest.

    Raises:
        Error: If the JSON is malformed, the format is not 1, an entry
            breaks a rule (an unknown kind, role or license, a path out of
            the cache, a texture set with no albedo or no positive tile, a
            model with no model file or forward axis, a town with no model
            file, an HDRI with no panorama), two entries share an id, or a binding names an
            entry that is not there or is of the wrong kind.
    """
    var document = parse_json(text)
    var root = document.root()
    if document.kind(root) != OBJECT:
        raise Error("A manifest must be a JSON object")
    var format = document.get(root, "format")
    if (
        format == NO_NODE
        or document.kind(format) != NUMBER
        or document.number(format) != 1
    ):
        raise Error("A manifest must have format 1")
    var manifest = AssetManifest()
    var entries = document.get(root, "entries")
    if entries == NO_NODE or document.kind(entries) != ARRAY:
        raise Error("A manifest needs a list of entries")
    for index in range(document.length(entries)):
        var entry = _entry(document, document.at(entries, index))
        if Bool(manifest.find(entry.id)):
            raise Error("Two manifest entries share the id " + entry.id)
        manifest.entries.append(entry^)
    var bindings = document.get(root, "bindings")
    if bindings == NO_NODE:
        return manifest^
    if document.kind(bindings) != OBJECT:
        raise Error("A manifest's bindings must be an object")
    for index in range(document.length(bindings)):
        var key = document.key(bindings, index)
        var value = document.at(bindings, index)
        var id = String()
        if not document.is_null(value):
            id = document.string(value)
            var found = manifest.find(id)
            if not Bool(found):
                raise Error("The binding " + key + " names no entry: " + id)
            if manifest.entries[found.value()].kind != binding_kind(key):
                raise Error("The binding " + key + " names the wrong kind")
        manifest.keys.append(key)
        manifest.values.append(id)
    return manifest^


def binding_kind(key: String) -> AssetKind:
    """Return the kind of entry a binding key takes.

    Args:
        key: The key.

    Returns:
        A texture set for `surface.`, `ground.` and `facade.` keys, an
        HDRI for `sky.` keys, a town for `town.` keys, and a model for
        any other key: a blueprint id, a wildcard, or `tree`.
    """
    if (
        key.startswith("surface.")
        or key.startswith("ground.")
        or key.startswith("facade.")
    ):
        return TEXTURE_SET_ASSET
    if key.startswith("sky."):
        return HDRI_ASSET
    if key.startswith("town."):
        return TOWN_ASSET
    return MODEL_ASSET


def surface_key(kind: SurfaceKind) raises -> String:
    """Return the binding key of a road surface kind.

    Args:
        kind: The surface.

    Returns:
        `surface.` and the kind's name: `road`, `sidewalk`, `curb`,
        `wall`, `crosswalk`, `white_mark` or `yellow_mark`.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("A surface kind must be one of the seven")
    var names: List[String] = [
        "road",
        "sidewalk",
        "curb",
        "wall",
        "crosswalk",
        "white_mark",
        "yellow_mark",
    ]
    return "surface." + names[kind.value]


def wildcard_key(type_id: String) -> String:
    """Return a blueprint's family wildcard.

    Args:
        type_id: A blueprint id, such as `vehicle.tesla.model3`.

    Returns:
        The id's first part and `.*`, such as `vehicle.*`; the id and
        `.*` when it has no dot.
    """
    var dot = type_id.find(".")
    if dot < 0:
        return type_id + ".*"
    return String(type_id[byte=:dot]) + ".*"


# The key of a glTF material's `extras` that says what the material is on a
# CARLA vehicle.
comptime MATERIAL_TAG = "carla"
# The `extras` key of a town mesh's node that names its kind.
comptime TOWN_KIND = "carla_kind"
# The `extras` key of a town's scene that lists its lamp heads, three
# numbers each.
comptime TOWN_LAMPS = "carla_lamps"


@fieldwise_init
struct ModelPlacement(Copyable, Movable):
    """Where a placed model went."""

    # The pivot the model hangs from.
    var pivot: NodeId
    # The model's meshes: the first's index in `Scene.meshes`, and how
    # many follow it.
    var first_mesh: Int
    var mesh_count: Int
    # The even scale that fitted it.
    var scale: Float32
    # The materials the model's glTF tags with `"extras": {"carla": ...}`:
    # a vehicle's body `"paint"`, which takes the blueprint's color, and
    # its `"heads"` and `"tails"` lamps, which follow its light state.
    var paint: List[MaterialId]
    var heads: List[MaterialId]
    var tails: List[MaterialId]


@fieldwise_init
struct TownPlacement(Copyable, Movable):
    """Where a placed town went."""

    # The town's meshes: the first's index in `Scene.meshes`, and how many
    # follow it.
    var first_mesh: Int
    var mesh_count: Int
    # Each mesh's kind, from its node's `carla_kind`: `building`, `road`,
    # `vegetation` and the others `build_towns.py` writes.
    var kinds: List[String]
    # Each mesh's level of detail, from its node's `carla_lod`: 0 near,
    # 1 far.
    var lods: List[Int]
    # The town's tiles, one LOD each: the first's index in `Scene.lods`,
    # and how many follow it.
    var first_lod: Int
    var lod_count: Int
    # Each street lamp's head, in the scene's frame, from the scene's
    # `carla_lamps`.
    var lamps: List[Vector3]
    # The materials its glTF tags `"extras": {"carla": "lamp"}`: the lamps'
    # glass, which glows when the street lights are on.
    var lamp_materials: List[MaterialId]


def town_tile(name: String) -> Tuple[String, Int]:
    """Return a town mesh's tile and level of detail, from its node's name.

    `build_towns.py` names each node `<kind>_<x>_<z>_lod<level>`, where x
    and z number its tile. A kind can hold underscores, so the name is
    read from its end.

    Args:
        name: The node's name.

    Returns:
        The tile, as `<x>_<z>`, and the level. A name of another form is
        the tile `""` at level 0.
    """
    var parts = name.split("_")
    if len(parts) < 4 or not String(parts[len(parts) - 1]).startswith("lod"):
        return (String(""), 0)
    var value: Int
    try:
        value = atol(String(parts[len(parts) - 1]).removeprefix("lod"))
    except:
        return (String(""), 0)
    return (
        String(parts[len(parts) - 3]) + "_" + String(parts[len(parts) - 2]),
        value,
    )


struct TextureSet(Movable):
    """A texture set read from the cache, ready for a material."""

    # The albedo, roughness and normal maps; `emissive` is black.
    var maps: SurfaceMaps
    # The ambient occlusion map; white when the set has none.
    var ao: Texture
    # The bump map, from the displacement, when the set has no normal map.
    var bump: Texture
    var has_normal: Bool
    var has_roughness: Bool
    var has_ao: Bool
    var has_bump: Bool
    var tile: Length

    def __init__(
        out self,
        var maps: SurfaceMaps,
        var ao: Texture,
        var bump: Texture,
        tile: Length,
    ):
        """Hold the maps, each marked as read.

        Args:
            maps: The albedo, roughness, normal and emissive maps.
            ao: The occlusion map.
            bump: The bump map.
            tile: How far one tile reaches.
        """
        self.maps = maps^
        self.ao = ao^
        self.bump = bump^
        self.has_normal = True
        self.has_roughness = True
        self.has_ao = True
        self.has_bump = False
        self.tile = tile

    def per_meter(self) -> Vector2:
        """Return the repeat of a mesh whose texture coordinates are
        meters.

        Returns:
            One over `tile` on both axes.
        """
        var scale = 1 / self.tile.to(METER)
        return Vector2(scale, scale)

    def dress(
        self, mut assets: Assets, var material: Material, repeat: Vector2
    ) raises -> Material:
        """Return a material wearing this set's maps.

        The albedo is the color map, the roughness map scales the
        material's roughness, and the occlusion map darkens the ambient
        light.

        Args:
            assets: The stores; the maps are added.
            material: The material to dress.
            repeat: How many times each map repeats across the texture
                coordinates: `per_meter` for a mesh measured in meters.

        Returns:
            The material with its maps set.

        Raises:
            Error: Never; the store's add is passed on.
        """
        var color = Texture(copy=self.maps.color)
        color.repeat = repeat
        material.map = assets.textures.add(color^)
        if self.has_roughness:
            var rough = Texture(copy=self.maps.roughness)
            rough.repeat = repeat
            material.roughness_map = assets.textures.add(rough^)
        if self.has_normal:
            var normal = Texture(copy=self.maps.normal)
            normal.repeat = repeat
            material.normal_map = assets.textures.add(normal^)
        if self.has_ao:
            var ao = Texture(copy=self.ao)
            ao.repeat = repeat
            material.ao_map = assets.textures.add(ao^)
        if self.has_bump:
            var bump = Texture(copy=self.bump)
            bump.repeat = repeat
            material.bump_map = assets.textures.add(bump^)
        return material^


def _flat(value: UInt8, space: ColorSpace) raises -> Texture:
    """Return a one-texel repeating texture of one gray."""
    var pixels: List[UInt8] = [value, value, value, 255]
    return Texture(1, 1, pixels^, REPEAT, BILINEAR, space, False, IGNORED)


async def _read_one(
    paths: MutPointer[String, MutAnyOrigin],
    spaces: MutPointer[ColorSpace, MutAnyOrigin],
    textures: MutPointer[Texture, MutAnyOrigin],
    errors: MutPointer[String, MutAnyOrigin],
    index: Int,
):
    """Decode one cached image as `AssetRegistry._decode` does, as a task
    of `AssetRegistry.preload`; an error is carried back as its text."""
    try:
        var image = decode_image(Path(paths[unsafe_offset=index]).read_bytes())
        textures[unsafe_offset=index] = texture_from(
            image, REPEAT, BILINEAR, spaces[unsafe_offset=index], True, IGNORED
        )
    except e:
        errors[unsafe_offset=index] = String(e)


def _texture_key(path: String, space: ColorSpace) -> String:
    """Return the key a decoded image is kept under: one path can be read
    in both color spaces."""
    return path + ("|srgb" if space == SRGB else "|linear")


struct AssetRegistry(Movable):
    """A manifest read against a cache folder."""

    var manifest: AssetManifest
    # The cache folder, ending in a slash.
    var cache: String
    # The images `preload` decoded, by `_texture_key`.
    var decoded_keys: List[String]
    var decoded: List[Texture]
    # How many images a model's or a town's glTF decodes at once: the
    # count `preload` was last given.
    var workers: Int

    def __init__(out self):
        """Start with no manifest: every key falls back."""
        self.manifest = AssetManifest()
        self.cache = String()
        self.decoded_keys = List[String]()
        self.decoded = List[Texture]()
        self.workers = 1

    def __init__(out self, var manifest: AssetManifest, cache: String):
        """Read a manifest against a cache folder.

        Args:
            manifest: The manifest.
            cache: The folder the fetch tool fills, such as
                `.cache/carla-assets`.
        """
        self.manifest = manifest^
        self.cache = cache if cache.endswith("/") else cache + "/"
        self.decoded_keys = List[String]()
        self.decoded = List[Texture]()
        self.workers = 1

    @staticmethod
    def open(manifest_path: String, cache: String) raises -> AssetRegistry:
        """Read the manifest file and hold the cache folder.

        Args:
            manifest_path: The manifest, such as
                `assets/carla/manifest.json`.
            cache: The cache folder.

        Returns:
            The registry.

        Raises:
            Error: If the file cannot be read, or `parse_manifest` refuses
                it.
        """
        return AssetRegistry(
            parse_manifest(Path(manifest_path).read_text()), cache
        )

    def path(self, file: String) -> String:
        """Return a cached file's path.

        Args:
            file: The path the manifest gives.

        Returns:
            The cache folder and the path.
        """
        return self.cache + file

    def is_cached(self, entry: AssetEntry) raises -> Bool:
        """Return True when every file an entry reads is in the cache.

        Args:
            entry: The entry.

        Returns:
            Whether each of its files exists.

        Raises:
            Error: If the file system cannot be asked.
        """
        for f in entry.files:
            if not Path(self.path(f.path)).is_file():
                return False
        return True

    def cached_entry(self, key: String) raises -> Optional[Int]:
        """Return the entry a key is bound to, if the cache holds it.

        Args:
            key: A surface key or a blueprint id.

        Returns:
            The entry's index, or None when the key is not bound, is bound
            to null, or its files are not all in the cache.

        Raises:
            Error: If the file system cannot be asked.
        """
        var id = self.manifest.binding(key)
        if not Bool(id):
            return None
        # `parse_manifest` checks every binding names an entry.
        var index = self.manifest.find(id.value()).value()
        if not self.is_cached(self.manifest.entries[index]):
            return None
        return index

    def model_key(self, type_id: String) -> String:
        """Return the key a blueprint's model is looked up by.

        Args:
            type_id: The blueprint id.

        Returns:
            The id itself when the table has it, even bound to null, and
            else its family's wildcard.
        """
        if self.manifest.is_bound(type_id):
            return type_id
        return wildcard_key(type_id)

    def _texture(self, path: String, space: ColorSpace) raises -> Texture:
        """Read a cached image as a repeating, mipmapped texture: the one
        `preload` decoded, or decoded now."""
        var key = _texture_key(self.path(path), space)
        for index in range(len(self.decoded_keys)):
            if self.decoded_keys[index] == key:
                return Texture(copy=self.decoded[index])
        var image = decode_image(Path(self.path(path)).read_bytes())
        return texture_from(image, REPEAT, BILINEAR, space, True, IGNORED)

    def preload(mut self, workers: Int = 1) raises:
        """Decode every map of every bound, cached texture set, each once,
        `workers` at a time.

        A 2048-texel photoscan takes a few tenths of a second to decode,
        and a town reads twenty of them, some twice: a curb and a wall can
        wear one set. After this, `texture_set` copies them.

        The registry keeps `workers`, and `place_model` and `place_town`
        decode their glTF's images as many at a time.

        Args:
            workers: How many images to decode at once; one decodes them in
                turn.

        Raises:
            Error: If an image cannot be read or decoded.
        """
        self.workers = workers
        var paths = List[String]()
        var spaces = List[ColorSpace]()
        for index in range(len(self.manifest.keys)):
            var id = self.manifest.values[index]
            if id.byte_length() == 0:
                continue
            ref entry = self.manifest.entries[self.manifest.find(id).value()]
            if entry.kind != TEXTURE_SET_ASSET or not self.is_cached(entry):
                continue
            var normal = Bool(entry.file(NORMAL_ROLE))
            for f in entry.files:
                # The maps `texture_set` reads, in the spaces it reads them.
                if f.role == DISPLACEMENT_ROLE and normal:
                    continue
                var space = SRGB if f.role == ALBEDO_ROLE else LINEAR
                var path = self.path(f.path)
                var key = _texture_key(path, space)
                if key in self.decoded_keys:
                    continue
                var fresh = True
                for k in range(len(paths)):
                    if _texture_key(paths[k], spaces[k]) == key:
                        fresh = False
                if fresh:
                    paths.append(path)
                    spaces.append(space)
        var count = len(paths)
        var textures = List[Texture]()
        for _ in range(count):
            textures.append(_flat(0, LINEAR))
        var errors = List[String](length=count, fill=String(""))
        if workers <= 1 or count <= 1:
            for index in range(count):
                var image = decode_image(Path(paths[index]).read_bytes())
                textures[index] = texture_from(
                    image, REPEAT, BILINEAR, spaces[index], True, IGNORED
                )
        else:
            # Every pointer is to a local that outlives `wait`.
            var group = TaskGroup()
            for index in range(count):  # pragma: no branch
                group.create_task(
                    _read_one(
                        paths.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                        spaces.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                        textures.unsafe_ptr().unsafe_origin_cast[
                            MutAnyOrigin
                        ](),
                        errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                        index,
                    )
                )
            group.wait()
            for index in range(count):
                if errors[index].byte_length() > 0:
                    raise Error(paths[index] + ": " + errors[index])
        for index in range(count):
            self.decoded_keys.append(_texture_key(paths[index], spaces[index]))
            self.decoded.append(Texture(copy=textures[index]))

    def texture_set(self, index: Int) raises -> TextureSet:
        """Read a cached texture set.

        Args:
            index: The entry's index, from `cached_entry`.

        Returns:
            The set. A map the entry lacks is flat: a roughness of one,
            an occlusion of one, and no normal map.

        Raises:
            Error: If the entry is not a texture set, or an image cannot
                be read or decoded.
        """
        ref entry = self.manifest.entries[index]
        if entry.kind != TEXTURE_SET_ASSET:
            raise Error("The entry " + entry.id + " is not a texture set")
        var color = self._texture(entry.file(ALBEDO_ROLE).value(), SRGB)
        var rough = entry.file(ROUGHNESS_ROLE)
        var normal = entry.file(NORMAL_ROLE)
        var ao = entry.file(AO_ROLE)
        var bump = entry.file(DISPLACEMENT_ROLE)
        var maps = SurfaceMaps(
            color^,
            self._texture(rough.value(), LINEAR) if Bool(rough) else _flat(
                255, LINEAR
            ),
            self._texture(normal.value(), LINEAR) if Bool(normal) else _flat(
                128, LINEAR
            ),
            _flat(0, SRGB),
        )
        var set = TextureSet(
            maps^,
            self._texture(ao.value(), LINEAR) if Bool(ao) else _flat(
                255, LINEAR
            ),
            self._texture(bump.value(), LINEAR) if Bool(bump)
            and not Bool(normal) else _flat(0, LINEAR),
            entry.tile,
        )
        set.has_roughness = Bool(rough)
        set.has_normal = Bool(normal)
        set.has_ao = Bool(ao)
        set.has_bump = Bool(bump) and not Bool(normal)
        return set^

    def hdri(self, index: Int) raises -> Texture:
        """Read a cached HDRI as a float equirectangular texture.

        Args:
            index: The entry's index, from `cached_entry`.

        Returns:
            The panorama, linear, repeating across its width.

        Raises:
            Error: If the entry is not an HDRI, or its file is not a
                Radiance `.hdr` image.
        """
        ref entry = self.manifest.entries[index]
        if entry.kind != HDRI_ASSET:
            raise Error("The entry " + entry.id + " is not an HDRI")
        var image = decode_rgbe(
            Path(self.path(entry.file(HDRI_ROLE).value())).read_bytes()
        )
        return float_texture_from(image, REPEAT, BILINEAR, False, IGNORED)

    def place_model(
        self,
        index: Int,
        mut scene: Scene,
        mut assets: Assets,
        parent: NodeId,
        fit: Vector3,
    ) raises -> ModelPlacement:
        """Read a cached model and hang it from a new pivot.

        The pivot turns the model's forward axis to plus x, scales it
        evenly by the largest factor that keeps it inside `fit`, and moves
        it so that its box is centered on the pivot's origin in x and z
        and stands on it in y. Every mesh casts and receives shadows, and
        each material that reflects no cube reflects the scene's
        environment.

        Args:
            index: The entry's index, from `cached_entry`.
            scene: The scene; the model's nodes and meshes are added.
            assets: The stores; its geometry, materials and textures are
                added.
            parent: The node the pivot hangs from.
            fit: The box to fit, in meters: length along plus x, height
                along plus y, width along plus z.

        Returns:
            The pivot, the model's meshes and its scale.

        Raises:
            Error: If the entry is not a model, `read_gltf` refuses the
                file, the model adds skinned or instanced meshes, or it
                has no mesh.
        """
        ref entry = self.manifest.entries[index]
        if entry.kind != MODEL_ASSET:
            raise Error("The entry " + entry.id + " is not a model")
        var model = read_gltf(
            self.path(entry.file(MODEL_ROLE).value()),
            scene,
            assets,
            self.workers,
        )
        if model.skinned_mesh_count > 0 or model.instanced_mesh_count > 0:
            raise Error("A town model must hold only plain meshes")
        if model.mesh_count == 0:
            raise Error("The model " + entry.id + " has no mesh")
        scene.update()
        var bounds = Box3.empty()
        for m in range(model.first_mesh, model.first_mesh + model.mesh_count):
            var box = assets.geometries.get(
                scene.meshes[m].geometry
            ).bounding_box()
            box.apply_matrix4(scene.world_matrix(scene.meshes[m].node))
            bounds.union(box)
            scene.meshes[m].cast_shadow = True
            scene.meshes[m].receive_shadow = True
        for id in model.materials:
            var material = assets.materials.get(id)
            if material.env_map == NO_CUBE_TEXTURE:
                material.env_map = SCENE_ENVIRONMENT
                assets.materials.materials[id.value] = material
        var turned = Object3D()
        turned.rotate_y(entry.yaw)
        bounds.apply_matrix4(turned.local_matrix())
        var size = bounds.size()
        var scale = min(
            fit.x / max(size.x, Float32(1e-6)),
            min(
                fit.y / max(size.y, Float32(1e-6)),
                fit.z / max(size.z, Float32(1e-6)),
            ),
        )
        var center = bounds.center()
        var pivot = Object3D()
        pivot.rotate_y(entry.yaw)
        pivot.set_scale(scale, scale, scale)
        pivot.set_position(
            -center.x * scale, -bounds.min.y * scale, -center.z * scale
        )
        var node = scene.attach(pivot^, parent)
        for n in model.nodes:
            if n != NO_PARENT and scene.get(n).parent == NO_PARENT:
                scene.add(n, parent=node)
        scene.update()
        var paint = List[MaterialId]()
        var heads = List[MaterialId]()
        var tails = List[MaterialId]()
        for m in range(len(model.materials)):
            ref extras = model.material_extras[m]
            if extras.has(MATERIAL_TAG) and extras.kind(MATERIAL_TAG) == STRING:
                var tag = extras.string(MATERIAL_TAG)
                if tag == "paint":
                    paint.append(model.materials[m])
                elif tag == "heads":
                    heads.append(model.materials[m])
                elif tag == "tails":
                    tails.append(model.materials[m])
        return ModelPlacement(
            node,
            model.first_mesh,
            model.mesh_count,
            scale,
            paint^,
            heads^,
            tails^,
        )

    def place_town(
        self,
        index: Int,
        mut scene: Scene,
        mut assets: Assets,
        parent: NodeId,
        near: Length,
    ) raises -> TownPlacement:
        """Read a cached town and hang it, as it is, from a node.

        A town package is in the scene's frame already, so it takes no
        turn and no scale. Each of its tiles becomes an LOD: the tile's
        near meshes show when the camera is nearer than `near` to the
        middle of the tile's ground, and its far meshes show otherwise. Call
        `Scene.update_lods` with the camera's position before a frame.
        Every mesh casts and receives shadows, and each material that
        reflects no cube reflects the scene's environment.

        Args:
            index: The entry's index, from `cached_entry`.
            scene: The scene; the town's nodes, meshes and LODs are added.
            assets: The stores; its geometry, materials and textures are
                added.
            parent: The node the town hangs from.
            near: How far from a tile's center its near meshes show.

        Returns:
            The town's meshes, each one's kind and level, its LODs, its
            lamp heads, and its lamps' glass.

        Raises:
            Error: If the entry is not a town, `read_gltf` refuses the
                file, the town adds skinned or instanced meshes, it has no
                mesh, or its scene's `carla_lamps` is not a list of
                numbers three at a time.
        """
        ref entry = self.manifest.entries[index]
        if entry.kind != TOWN_ASSET:
            raise Error("The entry " + entry.id + " is not a town")
        var model = read_gltf(
            self.path(entry.file(MODEL_ROLE).value()),
            scene,
            assets,
            self.workers,
        )
        if model.skinned_mesh_count > 0 or model.instanced_mesh_count > 0:
            raise Error("A town must hold only plain meshes")
        if model.mesh_count == 0:
            raise Error("The town " + entry.id + " has no mesh")
        scene.update()
        for id in model.materials:
            var material = assets.materials.get(id)
            if material.env_map == NO_CUBE_TEXTURE:
                material.env_map = SCENE_ENVIRONMENT
                assets.materials.materials[id.value] = material
        # Each tile's key, box and meshes, in the order first met.
        var tiles = List[String]()
        var boxes = List[Box3]()
        var kinds = List[String]()
        var lods = List[Int]()
        var tile_of = List[Int]()
        for m in range(model.first_mesh, model.first_mesh + model.mesh_count):
            scene.meshes[m].cast_shadow = True
            scene.meshes[m].receive_shadow = True
            var node = scene.get(scene.meshes[m].node).copy()
            var kind = String("prop")
            if (
                node.user_data.has(TOWN_KIND)
                and node.user_data.kind(TOWN_KIND) == STRING
            ):
                kind = node.user_data.string(TOWN_KIND)
            kinds.append(kind)
            var tile = town_tile(node.name)
            lods.append(max(0, min(tile[1], 1)))
            var box = assets.geometries.get(
                scene.meshes[m].geometry
            ).bounding_box()
            box.apply_matrix4(scene.world_matrix(scene.meshes[m].node))
            var at = -1
            for k in range(len(tiles)):
                if tiles[k] == tile[0]:
                    at = k
            if at < 0:
                at = len(tiles)
                tiles.append(tile[0])
                boxes.append(Box3.empty())
            boxes[at].union(box)
            tile_of.append(at)
        var first_lod = len(scene.lods)
        var groups = List[NodeId]()
        for k in range(len(tiles)):
            # The tile's middle, at its ground: a tower's tile is measured
            # from the street, not from halfway up the tower.
            var center = boxes[k].center()
            center.y = boxes[k].min.y
            var holder = Object3D()
            holder.set_position(center.x, center.y, center.z)
            var tile_node = scene.attach(holder^, parent)
            var lod = Lod(tile_node)
            for level in range(2):
                var group = Object3D()
                group.set_position(-center.x, -center.y, -center.z)
                var group_node = scene.add(group^)
                groups.append(group_node)
                lod.add_level(
                    group_node, near if level == 1 else Length(0.0, METER)
                )
            scene.add_lod(lod^)
        for k in range(model.mesh_count):
            var node = scene.meshes[model.first_mesh + k].node
            scene.add(node, parent=groups[2 * tile_of[k] + lods[k]])
        scene.update()
        var lamps = List[Vector3]()
        if model.scene_extras.has(TOWN_LAMPS):
            var document = parse_json(model.scene_extras.json(TOWN_LAMPS))
            var root = document.root()
            if document.kind(root) != ARRAY or document.length(root) % 3 != 0:
                raise Error("A town's lamps must be three numbers each")
            var into = scene.world_matrix(parent)
            for k in range(document.length(root) // 3):
                var xyz = List[Float32]()
                for axis in range(3):
                    var at = document.at(root, 3 * k + axis)
                    if document.kind(at) != NUMBER:
                        raise Error("A town's lamps must be three numbers each")
                    xyz.append(Float32(document.number(at)))
                var head = Vector3(xyz[0], xyz[1], xyz[2])
                head.apply_matrix4(into)
                lamps.append(head)
        var glass = List[MaterialId]()
        for m in range(len(model.materials)):
            ref extras = model.material_extras[m]
            if (
                extras.has(MATERIAL_TAG)
                and extras.kind(MATERIAL_TAG) == STRING
                and extras.string(MATERIAL_TAG) == "lamp"
            ):
                glass.append(model.materials[m])
        return TownPlacement(
            model.first_mesh,
            model.mesh_count,
            kinds^,
            lods^,
            first_lod,
            len(tiles),
            lamps^,
            glass^,
        )


def repeat_model(
    placement: ModelPlacement, mut scene: Scene, parent: NodeId
) raises -> ModelPlacement:
    """Hang a second copy of a placed model from another node.

    The copy shares the first's geometry and materials, so a street of
    trees reads its model once.

    Args:
        placement: The placed model, from `AssetRegistry.place_model`.
        scene: The scene, updated; the copy's nodes and meshes are added.
        parent: The node the copy hangs from, as the first hangs from its
            own.

    Returns:
        The copy's pivot and meshes, at the first's scale.

    Raises:
        Error: If a node of the first is not in the scene, or the scene
            has changed since its last update.
    """
    var pivot_local = scene.get(placement.pivot).local_matrix()
    var into_pivot = scene.world_matrix(placement.pivot)
    into_pivot.invert()
    # Each mesh's place under the pivot, read while the scene is still
    # up to date: attaching a node makes its world matrices stale.
    var relatives = List[Matrix4]()
    for m in range(
        placement.first_mesh, placement.first_mesh + placement.mesh_count
    ):
        relatives.append(into_pivot * scene.world_matrix(scene.meshes[m].node))
    var pivot = Object3D()
    pivot.set_from_matrix(pivot_local)
    var node = scene.attach(pivot^, parent)
    var first = len(scene.meshes)
    for k in range(placement.mesh_count):
        var m = placement.first_mesh + k
        var holder = Object3D()
        holder.set_from_matrix(relatives[k])
        var mesh = scene.meshes[m].copy()
        mesh.node = scene.attach(holder^, node)
        scene.add_mesh(mesh^)
    scene.update()
    return ModelPlacement(
        node,
        first,
        placement.mesh_count,
        placement.scale,
        placement.paint.copy(),
        placement.heads.copy(),
        placement.tails.copy(),
    )
