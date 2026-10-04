# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Measure public image-loading APIs in a fresh process.

Build this unchanged source against each source tree. The timer covers
read_gltf or AssetRegistry.preload only. The checksum reads every byte
of every output image and mip level after the timer stops. Registry
manifest parsing is setup; glTF JSON and geometry loading are timed.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.assets import AssetRegistry
from loaders.gltf import read_gltf
from render.texture import Texture
from std.memory import bitcast
from std.runtime import parallelism_level
from std.sys import argv
from std.time import perf_counter_ns


comptime _FNV_OFFSET = UInt64(14695981039346656037)
comptime _FNV_PRIME = UInt64(1099511628211)


def _byte(mut value: UInt64, byte: UInt8):
    value = (value ^ UInt64(byte)) * _FNV_PRIME


def _word(mut value: UInt64, word: UInt64):
    for shift in range(0, 64, 8):
        _byte(value, UInt8((word >> UInt64(shift)) & 255))


def _summarize(
    textures: List[Texture],
) -> Tuple[Int, Int, Int, UInt64, UInt64, UInt64]:
    var base_bytes = 0
    var payload_bytes = 0
    var levels = 0
    var all_hash = _FNV_OFFSET
    var base_hash = _FNV_OFFSET
    var shape_hash = _FNV_OFFSET
    _word(shape_hash, UInt64(len(textures)))
    for index in range(len(textures)):
        ref texture = textures[index]
        var base = texture.width * texture.height * Texture.CHANNELS
        base_bytes += base
        payload_bytes += len(texture.pixels) + 4 * len(texture.data)
        levels += texture.levels
        _word(shape_hash, UInt64(texture.width))
        _word(shape_hash, UInt64(texture.height))
        _word(shape_hash, UInt64(texture.levels))
        _word(shape_hash, UInt64(len(texture.pixels)))
        _word(shape_hash, UInt64(len(texture.data)))
        for offset in texture.offsets:
            _word(shape_hash, UInt64(offset))
        # pixels includes the full mip chain, not just its first level.
        for index in range(len(texture.pixels)):
            _byte(all_hash, texture.pixels[index])
            if index < base:
                _byte(base_hash, texture.pixels[index])
        for index in range(len(texture.data)):
            var bits = bitcast[DType.uint32](texture.data[index])
            for shift in range(0, 32, 8):
                var byte = UInt8((bits >> UInt32(shift)) & 255)
                _byte(all_hash, byte)
                if index < base:
                    _byte(base_hash, byte)
    return (
        base_bytes,
        payload_bytes,
        levels,
        all_hash,
        base_hash,
        shape_hash,
    )


def _report(
    api: String,
    workers: Int,
    runtime_workers: Int,
    elapsed: Int64,
    textures: List[Texture],
):
    var sums = _summarize(textures)
    print(
        "result api",
        api,
        "workers",
        workers,
        "runtime_parallelism",
        runtime_workers,
        "load_ns",
        elapsed,
        "textures",
        len(textures),
        "base_bytes",
        sums[0],
        "payload_bytes",
        sums[1],
        "mip_levels",
        sums[2],
        "all_fnv64",
        sums[3],
        "base_fnv64",
        sums[4],
        "shape_fnv64",
        sums[5],
    )


def main() raises:
    var args = argv()
    if len(args) != 4:
        raise Error("Usage: image_decode FIXTURE gltf|registry WORKERS")
    var folder = args[1]
    var api = args[2]
    var workers = atol(args[3])
    if workers <= 0:
        raise Error("WORKERS must be positive")
    # Record the runtime's declared capacity, not a guessed CPU count.
    # No decode warm-up runs in this fresh process.
    var runtime_workers = parallelism_level()
    if api == "gltf":
        var scene = Scene()
        var assets = Assets()
        var start = perf_counter_ns()
        var model = read_gltf(folder + "/scene.gltf", scene, assets, workers)
        var elapsed = Int64(perf_counter_ns() - start)
        _report(
            api, workers, runtime_workers, elapsed, assets.textures.textures
        )
        # Keep the loaded model alive through the timer and checksum.
        if len(model.nodes) != 1:
            raise Error("Fixture must load its one scene node")
    elif api == "registry":
        var registry = AssetRegistry.open(folder + "/manifest.json", folder)
        var start = perf_counter_ns()
        registry.preload(workers)
        var elapsed = Int64(perf_counter_ns() - start)
        _report(api, workers, runtime_workers, elapsed, registry.decoded)
    else:
        raise Error("API must be gltf or registry")
