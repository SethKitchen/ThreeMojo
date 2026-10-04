# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure repeated ground-truth captures with a synthetic foliage mask.

Build with --Werror -I . and run with: SIZE CAPTURES FLOAT MUTATE.
Use /usr/bin/time -v for the process's peak resident memory. Pixel and mip
allocation counts come from replacement of live owned buffers. A replacement
is allocated while the previous buffer is still live, so its address differs.
Copy bytes exclude sampler tables, objects, scene copies and render targets.
The retained-byte count includes the source and its white coverage texture.
"""

from core.object3d import Object3D
from extensions.carla.actor import ActorId
from extensions.carla.sensor import UNLABELED
from geometries.box import box
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.texture import Texture, float_texture
from std.sys import argv
from std.time import perf_counter_ns
from tests.test_carla_render_scene import _renderer, _world
from units.si import METER, Length


def main() raises:
    var args = argv()
    if len(args) != 5:
        raise Error(
            "usage: carla_sensor_cache_bench SIZE CAPTURES FLOAT MUTATE"
        )
    var size = Int(args[1])
    var captures = Int(args[2])
    var floats = Bool(Int(args[3]))
    var mutate = Bool(Int(args[4]))
    if size < 1 or captures < 1:
        raise Error("Size and capture count must be positive")
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    var texture: Texture
    if floats:
        var data = List[Float32](length=4 * size * size, fill=0.25)
        for y in range(size):
            for x in range(size):
                data[4 * (y * size + x) + 3] = Float32(((x // 8 + y // 8) % 2))
        texture = float_texture(size, size, data^, mipmapped=True)
    else:
        var pixels = List[UInt8](length=4 * size * size, fill=64)
        for y in range(size):
            for x in range(size):
                pixels[4 * (y * size + x) + 3] = UInt8(
                    ((x // 8 + y // 8) % 2) * 255
                )
        texture = Texture(size, size, pixels^)
    var map = view.assets.textures.add(texture^)
    var material = view.assets.materials.add(
        Material(Color(20, 80, 30), map=map, alpha_test=0.5)
    )
    var node = Object3D()
    node.set_position(12, 2, 1.75)
    view.scene.add_mesh(
        Mesh(
            view.assets.geometries.add(
                box(Length(1, METER), Length(10, METER), Length(10, METER))
            ),
            material,
            view.scene.add(node^),
        )
    )
    view.scene.update()
    _ = view.render_depth(world, camera)
    var override = view._sensor_material(material, UNLABELED)
    var white = view.assets.materials.get(override).map
    var previous = Int(view.assets.textures.get(white).pixels.unsafe_ptr())
    if floats:
        previous = Int(view.assets.textures.get(white).data.unsafe_ptr())
    var bytes = len(view.assets.textures.get(white).pixels) + 4 * len(
        view.assets.textures.get(white).data
    )
    var replacements = 0
    var checksum = UInt64(0)
    var start = perf_counter_ns()
    for capture in range(captures):
        if mutate:
            if floats:
                view.assets.textures.textures[map.value].data[3] = Float32(
                    capture % 2
                )
            else:
                view.assets.textures.textures[map.value].pixels[3] = UInt8(
                    (capture % 2) * 255
                )
        var image = view.render_depth(world, camera)
        var current = Int(view.assets.textures.get(white).pixels.unsafe_ptr())
        if floats:
            current = Int(view.assets.textures.get(white).data.unsafe_ptr())
        replacements += Int(current != previous)
        previous = current
        for pixel in image.pixels:
            checksum += UInt64(pixel)
    var elapsed = perf_counter_ns() - start
    print("size", size, "captures", captures, "float", floats, "mutate", mutate)
    print(
        "capture_ns",
        elapsed,
        "payload_replacements",
        replacements,
        "pixel_mip_copy_bytes",
        replacements * bytes,
        "retained_pixel_mip_bytes",
        2 * bytes,
        "checksum",
        checksum,
    )
