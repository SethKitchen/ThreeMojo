# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The density inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.density760_inputs import density760_inputs


def _copy(root: String) raises:
    """Copy the reviewed density inputs.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/core",
            root + "/extensions/anatomy",
            root + "/extensions/humanoid/skeleton/arm/bones",
            root + "/extensions/humanoid/skeleton/arm/hair",
            root + "/extensions/humanoid/skeleton/arm/ligaments",
            root + "/extensions/humanoid/skeleton/arm/lymph",
            root + "/extensions/humanoid/skeleton/arm/muscles",
            root + "/extensions/humanoid/skeleton/arm/nerves",
            root + "/extensions/humanoid/skeleton/arm/skin",
            root + "/extensions/humanoid/skeleton/arm/vessels",
            root + "/extensions/humanoid/skeleton/foot/bones",
            root + "/extensions/humanoid/skeleton/foot/hair",
            root + "/extensions/humanoid/skeleton/foot/ligaments",
            root + "/extensions/humanoid/skeleton/foot/lymph",
            root + "/extensions/humanoid/skeleton/foot/muscles",
            root + "/extensions/humanoid/skeleton/foot/nerves",
            root + "/extensions/humanoid/skeleton/foot/skin",
            root + "/extensions/humanoid/skeleton/foot/vessels",
            root + "/extensions/humanoid/skeleton/hand/bones",
            root + "/extensions/humanoid/skeleton/hand/hair",
            root + "/extensions/humanoid/skeleton/hand/ligaments",
            root + "/extensions/humanoid/skeleton/hand/lymph",
            root + "/extensions/humanoid/skeleton/hand/muscles",
            root + "/extensions/humanoid/skeleton/hand/nerves",
            root + "/extensions/humanoid/skeleton/hand/skin",
            root + "/extensions/humanoid/skeleton/hand/vessels",
            root + "/extensions/humanoid/skeleton/head/bones",
            root + "/extensions/humanoid/skeleton/head/hair",
            root + "/extensions/humanoid/skeleton/head/ligaments",
            root + "/extensions/humanoid/skeleton/head/lymph",
            root + "/extensions/humanoid/skeleton/head/muscles",
            root + "/extensions/humanoid/skeleton/head/nerves",
            root + "/extensions/humanoid/skeleton/head/skin",
            root + "/extensions/humanoid/skeleton/head/vessels",
            root + "/extensions/humanoid/skeleton/leg/femur",
            root + "/extensions/humanoid/skeleton/leg/fibula",
            root + "/extensions/humanoid/skeleton/leg/hair",
            root + "/extensions/humanoid/skeleton/leg/knee",
            root + "/extensions/humanoid/skeleton/leg/lymph",
            root + "/extensions/humanoid/skeleton/leg/muscles",
            root + "/extensions/humanoid/skeleton/leg/nerves",
            root + "/extensions/humanoid/skeleton/leg/patella",
            root + "/extensions/humanoid/skeleton/leg/skin",
            root + "/extensions/humanoid/skeleton/leg/tibia",
            root + "/extensions/humanoid/skeleton/leg/vessels",
            root + "/extensions/humanoid/skeleton/limb",
            root + "/extensions/humanoid/skeleton/pelvis/bones",
            root + "/extensions/humanoid/skeleton/pelvis/ligaments",
            root + "/extensions/humanoid/skeleton/pelvis/lymph",
            root + "/extensions/humanoid/skeleton/pelvis/muscles",
            root + "/extensions/humanoid/skeleton/pelvis/nerves",
            root + "/extensions/humanoid/skeleton/pelvis/skin",
            root + "/extensions/humanoid/skeleton/pelvis/vessels",
            root + "/extensions/humanoid/skeleton/torso/bones",
            root + "/extensions/humanoid/skeleton/torso/ligaments",
            root + "/extensions/humanoid/skeleton/torso/lymph",
            root + "/extensions/humanoid/skeleton/torso/muscles",
            root + "/extensions/humanoid/skeleton/torso/nerves",
            root + "/extensions/humanoid/skeleton/torso/skin",
            root + "/extensions/humanoid/skeleton/torso/vessels",
            root + "/geometries",
            root + "/lights",
            root + "/loaders",
            root + "/materials",
            root + "/math",
            root + "/objects",
            root + "/render",
            root + "/tests",
            root + "/tools/carla_lane_oracle",
            root + "/units",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("core/__init__.mojo")
    files.append("core/assets.mojo")
    files.append("core/background.mojo")
    files.append("core/binary.mojo")
    files.append("core/buffer_attribute.mojo")
    files.append("core/buffer_geometry.mojo")
    files.append("core/interleaved_buffer.mojo")
    files.append("core/layers.mojo")
    files.append("core/object3d.mojo")
    files.append("core/order.mojo")
    files.append("core/ordinal.mojo")
    files.append("core/scene.mojo")
    files.append("core/search.mojo")
    files.append("core/user_data.mojo")
    files.append("extensions/__init__.mojo")
    files.append("extensions/anatomy/__init__.mojo")
    files.append("extensions/anatomy/soft_tissue.mojo")
    files.append("extensions/humanoid/__init__.mojo")
    files.append("extensions/humanoid/assets.mojo")
    files.append("extensions/humanoid/athleticism.mojo")
    files.append("extensions/humanoid/genome.mojo")
    files.append("extensions/humanoid/sex.mojo")
    files.append("extensions/humanoid/side.mojo")
    files.append("extensions/humanoid/skeleton/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/assembly.mojo")
    files.append("extensions/humanoid/skeleton/arm/bones/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/bones/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/bones/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/contents.mojo")
    files.append("extensions/humanoid/skeleton/arm/frame.mojo")
    files.append("extensions/humanoid/skeleton/arm/hair/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/hair/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/hair/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/ligaments/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/ligaments/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/ligaments/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/arm/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/arm/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/arm/vessels/geometry.mojo")
    files.append("extensions/humanoid/skeleton/complexion.mojo")
    files.append("extensions/humanoid/skeleton/dermis.mojo")
    files.append("extensions/humanoid/skeleton/field.mojo")
    files.append("extensions/humanoid/skeleton/foot/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/assembly.mojo")
    files.append("extensions/humanoid/skeleton/foot/bones/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/bones/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/bones/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/chain.mojo")
    files.append("extensions/humanoid/skeleton/foot/contents.mojo")
    files.append("extensions/humanoid/skeleton/foot/hair/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/hair/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/hair/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/ligaments/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/ligaments/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/ligaments/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/foot/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/foot/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/foot/vessels/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hair_shafts.mojo")
    files.append("extensions/humanoid/skeleton/hand/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/assembly.mojo")
    files.append("extensions/humanoid/skeleton/hand/bones/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/bones/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/bones/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/contents.mojo")
    files.append("extensions/humanoid/skeleton/hand/hair/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/hair/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/hair/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/ligaments/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/ligaments/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/ligaments/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/hand/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/hand/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/hand/vessels/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/bones/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/bones/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/bones/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/contents.mojo")
    files.append("extensions/humanoid/skeleton/head/eyes.mojo")
    files.append("extensions/humanoid/skeleton/head/face_model.mojo")
    files.append("extensions/humanoid/skeleton/head/frame.mojo")
    files.append("extensions/humanoid/skeleton/head/hair/collider.mojo")
    files.append("extensions/humanoid/skeleton/head/hair/density.mojo")
    files.append("extensions/humanoid/skeleton/head/hair/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/hair/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/hair/styles.mojo")
    files.append("extensions/humanoid/skeleton/head/ligaments/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/ligaments/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/ligaments/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/head/skin/mouth.mojo")
    files.append("extensions/humanoid/skeleton/head/skin/scan.mojo")
    files.append("extensions/humanoid/skeleton/head/skin/tint.mojo")
    files.append("extensions/humanoid/skeleton/head/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/head/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/head/vessels/geometry.mojo")
    files.append("extensions/humanoid/skeleton/isosurface.mojo")
    files.append("extensions/humanoid/skeleton/layer_set.mojo")
    files.append("extensions/humanoid/skeleton/leg/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/assembly.mojo")
    files.append("extensions/humanoid/skeleton/leg/contents.mojo")
    files.append("extensions/humanoid/skeleton/leg/femur/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/femur/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/femur/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/fibula/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/fibula/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/fibula/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/hair/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/hair/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/hair/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/knee/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/knee/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/knee/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/patella/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/patella/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/patella/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/tibia/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/tibia/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/tibia/geometry.mojo")
    files.append("extensions/humanoid/skeleton/leg/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/leg/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/leg/vessels/geometry.mojo")
    files.append("extensions/humanoid/skeleton/limb/__init__.mojo")
    files.append("extensions/humanoid/skeleton/limb/skin.mojo")
    files.append("extensions/humanoid/skeleton/mesh_field.mojo")
    files.append("extensions/humanoid/skeleton/morph.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/assembly.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/bones/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/bones/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/bones/geometry.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/contents.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/ligaments/__init__.mojo")
    files.append(
        "extensions/humanoid/skeleton/pelvis/ligaments/dimensions.mojo"
    )
    files.append("extensions/humanoid/skeleton/pelvis/ligaments/geometry.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/lower_body.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/pelvis/vessels/geometry.mojo")
    files.append("extensions/humanoid/skeleton/place.mojo")
    files.append("extensions/humanoid/skeleton/sculpt.mojo")
    files.append("extensions/humanoid/skeleton/torso/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/assembly.mojo")
    files.append("extensions/humanoid/skeleton/torso/body.mojo")
    files.append("extensions/humanoid/skeleton/torso/bones/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/bones/geometry.mojo")
    files.append("extensions/humanoid/skeleton/torso/contents.mojo")
    files.append("extensions/humanoid/skeleton/torso/ligaments/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/ligaments/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/torso/ligaments/geometry.mojo")
    files.append("extensions/humanoid/skeleton/torso/lymph/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/lymph/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/torso/lymph/geometry.mojo")
    files.append("extensions/humanoid/skeleton/torso/muscles/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/muscles/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/torso/muscles/geometry.mojo")
    files.append("extensions/humanoid/skeleton/torso/nerves/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/nerves/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/torso/nerves/geometry.mojo")
    files.append("extensions/humanoid/skeleton/torso/skin/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/skin/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/torso/skin/geometry.mojo")
    files.append("extensions/humanoid/skeleton/torso/vessels/__init__.mojo")
    files.append("extensions/humanoid/skeleton/torso/vessels/dimensions.mojo")
    files.append("extensions/humanoid/skeleton/torso/vessels/geometry.mojo")
    files.append("extensions/humanoid/spec.mojo")
    files.append("geometries/__init__.mojo")
    files.append("geometries/utils.mojo")
    files.append("lights/__init__.mojo")
    files.append("lights/fresnel.mojo")
    files.append("lights/light.mojo")
    files.append("lights/light_slot.mojo")
    files.append("lights/physical_layers.mojo")
    files.append("loaders/__init__.mojo")
    files.append("loaders/js_text.mojo")
    files.append("loaders/json.mojo")
    files.append("loaders/utf8.mojo")
    files.append("materials/__init__.mojo")
    files.append("materials/compute_ids.mojo")
    files.append("materials/nodes.mojo")
    files.append("math/__init__.mojo")
    files.append("math/arc_tangent.mojo")
    files.append("math/bezier.mojo")
    files.append("math/bounds.mojo")
    files.append("math/box_extent.mojo")
    files.append("math/catmull.mojo")
    files.append("math/cross.mojo")
    files.append("math/euler.mojo")
    files.append("math/finite.mojo")
    files.append("math/matrix3.mojo")
    files.append("math/matrix_determinant.mojo")
    files.append("math/matrix_inverse.mojo")
    files.append("math/norm.mojo")
    files.append("math/polyline.mojo")
    files.append("math/quaternion.mojo")
    files.append("math/random.mojo")
    files.append("math/ray.mojo")
    files.append("math/ray_query.mojo")
    files.append("math/remainder.mojo")
    files.append("math/scaled_products.mojo")
    files.append("math/sine.mojo")
    files.append("math/smoothstep.mojo")
    files.append("math/spherical_harmonics3.mojo")
    files.append("math/triangle.mojo")
    files.append("math/triangle_normal.mojo")
    files.append("math/vector2.mojo")
    files.append("math/vector3.mojo")
    files.append("objects/__init__.mojo")
    files.append("objects/clipping_group.mojo")
    files.append("objects/instanced_mesh.mojo")
    files.append("objects/line.mojo")
    files.append("objects/lod.mojo")
    files.append("objects/mesh.mojo")
    files.append("objects/points.mojo")
    files.append("objects/skeleton.mojo")
    files.append("objects/skinned_mesh.mojo")
    files.append("objects/sprite.mojo")
    files.append("render/__init__.mojo")
    files.append("render/blend.mojo")
    files.append("render/checksum.mojo")
    files.append("render/color_math.mojo")
    files.append("render/cube_texture_store.mojo")
    files.append("render/float_image.mojo")
    files.append("render/inflate.mojo")
    files.append("render/packing.mojo")
    files.append("render/png.mojo")
    files.append("render/raster_state.mojo")
    files.append("render/srgb.mojo")
    files.append("render/texture_buffer.mojo")
    files.append("render/texture_store.mojo")
    files.append("render/volume_texture_store.mojo")
    files.append("tests/test_hair_density_bounds_controls.mojo")
    files.append("tests/test_reconciled_hair_density.mojo")
    files.append("tools/carla_lane_oracle/pr760_arithmetic_stage.py")
    files.append("units/__init__.mojo")
    files.append("units/measure.mojo")
    files.append("units/quantity.mojo")
    files.append("units/si.mojo")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_density_inputs_hold() raises:
    """The 311 density inputs keep their reviewed digests."""
    density760_inputs(".")
    density760_inputs("./")
    density760_inputs("core/..")


def test_a_changed_core_package_is_refused() raises:
    """A changed core package is refused."""
    var root = "/tmp/density760-core"
    _copy(root)
    var path = root + "/core/__init__.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="density760 input changed: core/__init__.mojo"):
        density760_inputs(root)


def test_a_changed_last_density_input_is_refused() raises:
    """A changed last density input is refused."""
    var root = "/tmp/density760-last"
    _copy(root)
    var path = root + "/units/si.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=("density760 input changed: " + "units/si.mojo")
    ):
        density760_inputs(root)


def main() raises:
    """Run the density-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
