# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sealed humanoid bakes: the geometry digest and its load-time check."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
)
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from core.user_data import UserData, user_data_of
from exporters.gltf import (
    GLB,
    GLTF_EMBEDDED,
    GltfExportOptions,
    write_gltf,
)
from extensions.humanoid.bake import (
    bake_geometry_digest,
    require_bake_geometry,
    require_sealed_bake,
    seal_bake_provenance,
    write_sealed_bake,
)
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    FIDELITY_KEY,
    GAME_RECIPE,
    UNSEALED_GEOMETRY,
    humanoid_provenance,
    is_geometry_digest,
    require_bake_provenance,
)
from extensions.humanoid.genome import FACE_SHAPE_1, Expression
from extensions.humanoid.rig.game import game_build_settings
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from loaders.gltf import read_gltf
from loaders.json import parse_json
from materials.material import BASIC, Material, MaterialId
from math.matrix4 import Matrix4
from objects.mesh import Mesh
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_scratch import TestScratch, temporary_path
from units.si import Length, METER

# A distinctive position, found again as bytes in the written file.
comptime MARK = Float32(0.123456)


def _record() raises -> UserData:
    return humanoid_provenance(
        HumanoidSpec(Length(1.8288, METER), MALE),
        game_build_settings(3000),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "synthetic-no-source-assets",
    )


def _floats(values: List[Float32], size: Int) raises -> BufferAttribute:
    return BufferAttribute(values.copy(), size)


def _skin() raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        _floats([0, 0, 0, 1, 0, 0, 0, 1, 0], 3),
    )
    geometry.set_attribute(
        String(SKIN_INDEX), _floats([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 4)
    )
    geometry.set_attribute(
        String(SKIN_WEIGHT),
        _floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4),
    )
    geometry.set_index([0, 1, 2])
    return geometry^


def _surface() raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        _floats([MARK, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], 3),
    )
    geometry.set_attribute(
        String(NORMAL), _floats([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(String(UV), _floats([0, 0, 1, 0, 1, 1, 0, 1], 2))
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


struct _Bake(Movable):
    """A small scene with a skinned mesh and a plain mesh."""

    var scene: Scene
    var assets: Assets
    var skin: GeometryId
    var surface: GeometryId

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        var material = self.assets.materials.add(
            Material(Color(200, 180, 160), kind=BASIC)
        )
        var root = Object3D()
        root.name = "bake"
        var holder = self.scene.add(root^)
        var bone = Object3D()
        bone.name = "hips"
        var hips = self.scene.add(bone^)
        var plain = Object3D()
        plain.name = "surface"
        var surface = self.scene.add(plain^)
        self.skin = self.assets.geometries.add(_skin())
        self.surface = self.assets.geometries.add(_surface())
        self.scene.add_skinned_mesh(
            SkinnedMesh(
                self.skin,
                material,
                holder,
                Skeleton([Bone(hips, Matrix4())]),
            )
        )
        self.scene.add_mesh(Mesh(self.surface, material, surface))


def _edited(
    mut assets: Assets,
    id: GeometryId,
    name: String,
    item: Int,
    lane: Int,
    value: Float32,
) raises:
    var geometry = assets.geometries.get(id).clone()
    var attribute = geometry.clone_attribute(name)
    attribute.set_component(item, lane, value)
    geometry.set_attribute(name, attribute^)
    assets.geometries.replace(id, geometry^)


def _reindexed(mut assets: Assets, id: GeometryId, var index: List[Int]) raises:
    var geometry = assets.geometries.get(id).clone()
    geometry.set_index(index^)
    assets.geometries.replace(id, geometry^)


# Model each kind of edit on one draw list or one buffer. Zero edits nothing.
comptime EDITS = 18


def _edit(mut bake: _Bake, edit: Int) raises:
    if edit == 1:
        _edited(bake.assets, bake.surface, String(POSITION), 0, 0, 0.5)
    elif edit == 2:
        _reindexed(bake.assets, bake.surface, [0, 2, 1, 0, 2, 3])
    elif edit == 3:
        _edited(bake.assets, bake.skin, String(SKIN_WEIGHT), 1, 0, 0.5)
    elif edit == 4:
        _edited(bake.assets, bake.skin, String(SKIN_INDEX), 2, 1, 1)
    elif edit == 5:
        _edited(bake.assets, bake.surface, String(NORMAL), 3, 2, -1)
    elif edit == 6:
        _edited(bake.assets, bake.surface, String(UV), 2, 1, 0.5)
    elif edit == 7:
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        geometry.add_group(0, 3, MaterialIndex(1))
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 8:
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        geometry.add_morph_target(geometry.clone_attribute(String(POSITION)))
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 9:
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        geometry.add_morph_target(
            geometry.clone_attribute(String(POSITION)),
            geometry.clone_attribute(String(NORMAL)),
        )
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 10:
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        geometry.add_morph_target(geometry.clone_attribute(String(POSITION)))
        geometry.set_morph_colors(
            [_floats([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 3)]
        )
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 11:
        var bone = bake.scene.skinned_meshes[0].skeleton.bones[0].node
        var named = bake.scene.get(bone)
        named.name = ""
        bake.scene.set(bone, named^)
    elif edit == 12:
        # Swap the order of two meshes.
        var first = bake.scene.meshes[0]
        bake.scene.add_mesh(first)
        bake.scene.meshes[0] = Mesh(
            bake.assets.geometries.add(BufferGeometry()),
            first.material,
            first.node,
        )
    elif edit == 13:
        # Reorder two vertices, keeping the same triangles.
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        for name in [String(POSITION), String(NORMAL), String(UV)]:
            var attribute = geometry.clone_attribute(name)
            for lane in range(attribute.item_size):
                var first = attribute.component(0, lane)
                attribute.set_component(0, lane, attribute.component(1, lane))
                attribute.set_component(1, lane, first)
            geometry.set_attribute(name, attribute^)
        geometry.set_index([1, 0, 2, 1, 2, 3])
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 14:
        # Reorder the attributes alone.
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        var normals = geometry.clone_attribute(String(NORMAL))
        geometry.delete_attribute(String(NORMAL))
        geometry.set_attribute(String(NORMAL), normals^)
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 15:
        var geometry = bake.assets.geometries.get(bake.surface).clone()
        geometry.set_attribute(
            String(COLOR), _floats([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 3)
        )
        bake.assets.geometries.replace(bake.surface, geometry^)
    elif edit == 16:
        # An empty geometry without an index or attributes.
        bake.scene.add_mesh(
            Mesh(
                bake.assets.geometries.add(BufferGeometry()),
                bake.scene.meshes[0].material,
                bake.scene.meshes[0].node,
            )
        )
    elif edit == 17:
        # An attribute that holds no items.
        var geometry = BufferGeometry()
        geometry.set_attribute("empty", _floats(List[Float32](), 3))
        bake.scene.add_mesh(
            Mesh(
                bake.assets.geometries.add(geometry^),
                bake.scene.meshes[0].material,
                bake.scene.meshes[0].node,
            )
        )


def test_digest_covers_each_buffer_and_its_order() raises:
    var digests = List[String]()
    for edit in range(EDITS):
        var bake = _Bake()
        _edit(bake, edit)
        var digest = bake_geometry_digest(bake.scene, bake.assets)
        assert_true(is_geometry_digest(digest))
        for earlier in digests:
            assert_true(digest != earlier, String("edit ") + String(edit))
        digests.append(digest)
    var again = _Bake()
    assert_equal(bake_geometry_digest(again.scene, again.assets), digests[0])


def _load(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> UserData:
    return read_gltf(path, scene, assets).scene_extras.copy()


def test_sealed_bake_round_trip_in_each_container() raises:
    var record = _record()
    var digests = List[String]()
    for container in [GLB, GLTF_EMBEDDED]:
        var bake = _Bake()
        var path = temporary_path("sealed-" + String(container.value) + ".glb")
        var options = GltfExportOptions()
        options.scene_user_data.set_string("label", "kept")
        options.scene_user_data.set_string(String(FIDELITY_KEY), "replaced")
        write_sealed_bake(
            path,
            bake.scene,
            bake.assets,
            record,
            container,
            options=options^,
        )
        var scene = Scene()
        var assets = Assets()
        var extras = _load(path, scene, assets)
        assert_equal(extras.string("label"), "kept")
        require_sealed_bake(extras, record, scene, assets)
        var document = parse_json(extras.json(String(FIDELITY_KEY)))
        var stored = user_data_of(document, document.root())
        assert_true(is_geometry_digest(stored.string("geometry_digest")))
        digests.append(stored.string("geometry_digest"))
        # The stale-recipe check still runs first on a sealed bake.
        var spec = HumanoidSpec(Length(1.8288, METER), MALE)
        spec.genome = spec.genome.with_gene(FACE_SHAPE_1, Expression(1))
        var stale = humanoid_provenance(
            spec,
            game_build_settings(3000),
            String(CANONICAL_RECIPE),
            String(GAME_RECIPE),
            "synthetic-no-source-assets",
        )
        with assert_raises(contains="spec fingerprint is stale"):
            require_sealed_bake(extras, stale, scene, assets)
    assert_equal(digests[0], digests[1])


def test_each_loaded_edit_is_refused() raises:
    var bake = _Bake()
    var path = temporary_path("edited.glb")
    write_sealed_bake(path, bake.scene, bake.assets, _record())
    # The loader reads the meshes in the order the bake wrote them.
    for edit in range(1, EDITS):
        var loaded = _Bake()
        loaded.scene = Scene()
        loaded.assets = Assets()
        var extras = _load(path, loaded.scene, loaded.assets)
        loaded.skin = loaded.scene.skinned_meshes[0].geometry
        loaded.surface = loaded.scene.meshes[0].geometry
        require_bake_geometry(extras, loaded.scene, loaded.assets)
        _edit(loaded, edit)
        with assert_raises(contains="does not match its digest"):
            require_bake_geometry(extras, loaded.scene, loaded.assets)
        with assert_raises(contains="does not match its digest"):
            require_sealed_bake(extras, _record(), loaded.scene, loaded.assets)


def test_an_edited_file_byte_is_refused() raises:
    var bake = _Bake()
    var path = temporary_path("byte.glb")
    write_sealed_bake(path, bake.scene, bake.assets, _record())
    var bytes = Path(path).read_bytes()
    var mark = bitcast[DType.uint32](MARK)
    var found = -1
    for at in range(len(bytes) - 3):
        var word = (
            UInt32(bytes[at])
            | (UInt32(bytes[at + 1]) << 8)
            | (UInt32(bytes[at + 2]) << 16)
            | (UInt32(bytes[at + 3]) << 24)
        )
        if word == mark:
            found = at
    assert_true(found >= 0)
    # Flip the lowest bit of one position's float32 bytes.
    bytes[found] = bytes[found] ^ 1
    Path(path).write_bytes(bytes)
    var scene = Scene()
    var assets = Assets()
    var extras = _load(path, scene, assets)
    require_bake_provenance(extras, _record())
    with assert_raises(contains="does not match its digest"):
        require_sealed_bake(extras, _record(), scene, assets)


def test_unsealed_and_missing_records_are_not_verified() raises:
    var bake = _Bake()
    var path = temporary_path("unsealed.glb")
    var options = GltfExportOptions()
    options.scene_user_data.set_json(String(FIDELITY_KEY), _record().to_json())
    write_gltf(path, bake.scene, bake.assets, GLB, options=options^)
    var scene = Scene()
    var assets = Assets()
    var extras = _load(path, scene, assets)
    # The recipe check alone does not claim verified geometry.
    require_bake_provenance(extras, _record())
    with assert_raises(contains="unsealed and unverified"):
        require_bake_geometry(extras, scene, assets)
    with assert_raises(contains="unsealed and unverified"):
        require_sealed_bake(extras, _record(), scene, assets)
    with assert_raises(contains="no fidelity provenance"):
        require_bake_geometry(UserData(), scene, assets)
    # A schema 2 bake has no geometry digest and is refused as stale.
    var old = _record()
    old.set_number("schema_version", 2)
    _ = old.remove("geometry_digest")
    _ = old.remove("geometry_digest_algorithm")
    var stored = UserData()
    stored.set_json(String(FIDELITY_KEY), old.to_json())
    with assert_raises(contains="schema is unsupported"):
        require_bake_geometry(stored, scene, assets)
    # An invalid record cannot be sealed.
    with assert_raises(contains="has no schema"):
        _ = seal_bake_provenance(bake.scene, bake.assets, UserData())
    var sealed = seal_bake_provenance(bake.scene, bake.assets, _record())
    assert_true(sealed.string("geometry_digest") != UNSEALED_GEOMETRY)
    assert_equal(
        sealed.string("geometry_digest"),
        bake_geometry_digest(scene, assets),
    )


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
