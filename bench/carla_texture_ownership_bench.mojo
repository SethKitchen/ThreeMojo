# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure the same Town construction on main and the COW candidate.

Timing excludes input decode and validation. Payload accounting uses live
addresses and covers the decoded registry, texture store and Town-held map.
All texels, mip offsets and sampling state contribute to the checksum.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.assets import AssetRegistry
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.town import Town, TownSettings
from render.texture import Texture
from std.memory import Pointer, bitcast
from std.sys import argv
from std.testing import assert_equal
from std.time import perf_counter_ns
from units.si import Length


struct Payloads(Movable):
    """Count texture allocations and hash their values without changing them.

    Allocation addresses are compared while the source owners are live.
    """

    var bytes: List[Pointer[UInt8, UntrackedOrigin[mut=False]]]
    var floats: List[Pointer[Float32, UntrackedOrigin[mut=False]]]
    var logical: Int
    var unique: Int
    var hash: UInt64

    def __init__(out self):
        """Start with no allocations and the FNV-1a initial state."""
        self.bytes = List[Pointer[UInt8, UntrackedOrigin[mut=False]]]()
        self.floats = List[Pointer[Float32, UntrackedOrigin[mut=False]]]()
        self.logical = 0
        self.unique = 0
        self.hash = 1469598103934665603

    def _mix(mut self, word: UInt64):
        """Append one exact word to the validation hash."""
        self.hash = (self.hash ^ word) * UInt64(1099511628211)

    def _real(mut self, value: Float32):
        """Hash a floating-point value by its exact bit pattern."""
        self._mix(UInt64(bitcast[DType.uint32](value)))

    def include(mut self, texture: Texture):
        """Account for one live texture and its complete sampling state.

        Args:
            texture: A source that stays alive until accounting finishes.
        """
        self.logical += len(texture.pixels) + 4 * len(texture.data)
        if len(texture.pixels) > 0:
            var address = texture.pixels.unsafe_ptr().unsafe_origin_cast[
                UntrackedOrigin[mut=False]
            ]()
            if address not in self.bytes:
                self.bytes.append(address)
                self.unique += len(texture.pixels)
        if len(texture.data) > 0:
            var address = texture.data.unsafe_ptr().unsafe_origin_cast[
                UntrackedOrigin[mut=False]
            ]()
            if address not in self.floats:
                self.floats.append(address)
                self.unique += 4 * len(texture.data)
        self._mix(UInt64(texture.width))
        self._mix(UInt64(texture.height))
        self._mix(UInt64(texture.levels))
        self._mix(UInt64(texture.wrap_s.value))
        self._mix(UInt64(texture.wrap_t.value))
        self._mix(UInt64(texture.mag_filter.value))
        self._mix(UInt64(texture.min_filter.value))
        self._mix(UInt64(texture.color_space.value))
        self._mix(UInt64(texture.alpha.value))
        self._mix(UInt64(texture.texel_type.value))
        self._mix(UInt64(texture.channel.value))
        self._mix(UInt64(texture.anisotropy))
        self._mix(UInt64(1 if texture.flip_y else 0))
        self._real(texture.offset.x)
        self._real(texture.offset.y)
        self._real(texture.repeat.x)
        self._real(texture.repeat.y)
        self._real(texture.center.x)
        self._real(texture.center.y)
        self._real(texture.rotation.value)
        for offset in texture.offsets:
            self._mix(UInt64(offset))
        for index in range(len(texture.ramp)):
            self._real(texture.ramp[index])
        for index in range(len(texture.pixels)):
            self._mix(UInt64(texture.pixels[index]))
        for index in range(len(texture.data)):
            self._real(texture.data[index])


def main() raises:
    """Run one construction sample from the generated fixture.

    Raises:
        Error: If the arguments, inputs or resulting scene are invalid.
    """
    var args = argv()
    if len(args) != 4:
        raise Error("Usage: town_payload_bench FIXTURE LABEL SAMPLE")
    var registry = AssetRegistry.open(args[1] + "/manifest.json", args[1])
    registry.preload(1)
    assert_equal(len(registry.decoded), 2)
    var map = load_opendrive_file(args[1] + "/town.xodr")
    var settings = TownSettings()
    settings.texture_size = 64
    settings.resolution = Length(2)
    settings.buildings = False
    settings.trees = False
    settings.lamps = False
    var scene = Scene()
    var assets = Assets()
    var start = perf_counter_ns()
    var town = Town(map, scene, assets, settings^, registry)
    var elapsed = perf_counter_ns() - start
    var payload = Payloads()
    for index in range(len(registry.decoded)):
        payload.include(registry.decoded[index])
    for index in range(assets.textures.count()):
        payload.include(assets.textures.textures[index])
    payload.include(town.asphalt_roughness)
    var geometry_bytes = 0
    var geometry_hash = UInt64(1469598103934665603)
    for index in range(assets.geometries.count()):
        ref geometry = assets.geometries.geometries[index]
        geometry_bytes += len(geometry.index) * 8
        for vertex in geometry.index:
            geometry_hash = (geometry_hash ^ UInt64(vertex)) * UInt64(
                1099511628211
            )
        for attribute in geometry.values:
            geometry_bytes += len(attribute.data) * 4
            for value in attribute.data:
                geometry_hash = (
                    geometry_hash ^ UInt64(bitcast[DType.uint32](value))
                ) * UInt64(1099511628211)
    assert_equal(len(town.tags), len(scene.meshes))
    print(
        "kind",
        "town",
        "label",
        args[2],
        "sample",
        args[3],
        "construction_ns",
        elapsed,
        "logical_payload_bytes",
        payload.logical,
        "unique_payload_bytes",
        payload.unique,
        "payload_hash",
        payload.hash,
        "unique_byte_allocations",
        len(payload.bytes),
        "unique_float_allocations",
        len(payload.floats),
        "cache_textures",
        len(registry.decoded),
        "store_textures",
        assets.textures.count(),
        "materials",
        assets.materials.count(),
        "meshes",
        len(scene.meshes),
        "geometry_bytes",
        geometry_bytes,
        "geometry_hash",
        geometry_hash,
        "tags",
        len(town.tags),
    )
