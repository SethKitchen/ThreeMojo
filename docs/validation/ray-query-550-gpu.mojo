# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Compile public and prepared ray queries for SM80 without a device run."""

from max.gpu.host.compile import _compile_code, get_gpu_target
from math.bounds import Box3, Sphere
from math.ray import Ray


def ray_queries(
    output: MutPointer[Float32, MutAnyOrigin],
    rays: MutPointer[Ray, MutAnyOrigin],
    boxes: MutPointer[Box3, MutAnyOrigin],
    spheres: MutPointer[Sphere, MutAnyOrigin],
):
    var ray = rays[unsafe_offset=0]
    var box = boxes[unsafe_offset=0]
    var sphere = spheres[unsafe_offset=0]
    output[unsafe_offset=0] = Float32(Int(ray.intersects_box(box)))
    output[unsafe_offset=1] = Float32(
        Int(ray._box_decision[True](box, ray._query_products())[0])
    )
    var point = ray.intersect_box(box)
    output[unsafe_offset=2] = Float32(Int(Bool(point)))
    if point:
        output[unsafe_offset=3] = point.value().x
        output[unsafe_offset=4] = point.value().y
        output[unsafe_offset=5] = point.value().z
    output[unsafe_offset=6] = Float32(Int(ray.intersects_sphere(sphere)))
    point = ray.intersect_sphere(sphere)
    output[unsafe_offset=7] = Float32(Int(Bool(point)))
    if point:
        output[unsafe_offset=8] = point.value().x
        output[unsafe_offset=9] = point.value().y
        output[unsafe_offset=10] = point.value().z


def main() raises:
    var code = _compile_code[
        ray_queries, emission_kind="asm", target=get_gpu_target["sm_80"]()
    ]()
    print(code.asm)
