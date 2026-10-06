#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Generate or check independent three.js r186 volume-light fixtures.

This portable scalar Float64 reference uses only the Python standard library.
It imports no native implementation and does not claim to execute WebGPU/TSL.
The fetched upstream Git blob IDs identify the equations transcribed here.
Native tests use Float32 tolerances against these independent constants.

Run with --write to replace assets/volume_lighting/r186.json, or --check to
verify it. The default is --check. Native output is 1 - transmittance. Actual
r186 outgoing-ray recurrence is also recorded, but is outside issue #616's
accepted scope and is deliberately not asserted as the native final color.
"""

import argparse
from copy import deepcopy
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "assets/volume_lighting/r186.json"
SOURCE_BLOBS = {
    "src/nodes/functions/BSDF/LTC.js": "6030b42b22794eb87711bfd5d1e65f974abf1eba",
    "src/nodes/functions/VolumetricLightingModel.js": "d37d3a6c2362170e043b8624958afbe16ae87137",
    "src/nodes/lighting/RectAreaLightNode.js": "d0b31a4575fe98021cd529f776c617dafaeac91d",
    "src/nodes/display/ViewportDepthNode.js": "7e96a52c22bbc0bc356a241b38c2e409da0740fc",
    "src/nodes/lighting/LightUtils.js": "f0498b00e6284876d4a264eaca1fe7ced97739d0",
    "src/nodes/lighting/SpotLightNode.js": "783cdc430a91b265ef6fae1f6e2057b023368f5c",
}


def add(a, b):
    return [x + y for x, y in zip(a, b)]


def sub(a, b):
    return [x - y for x, y in zip(a, b)]


def scale(a, value):
    return [x * value for x in a]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0]]


def length(a):
    return math.sqrt(dot(a, a))


def normalize(a):
    size = length(a)
    if size == 0:
        raise ValueError("A reference fixture must not normalize a zero vector")
    return scale(a, 1 / size)


def to_view(vector, up, back):
    return [dot(vector, cross(up, back)), dot(vector, up), dot(vector, back)]


def edge_form_factor(first, second):
    x = dot(first, second)
    y = abs(x)
    a = (0.0145206 * y + 0.4965155) * y + 0.8543985
    b = (y + 4.1616724) * y + 3.4175940
    v = a / b
    theta_sintheta = v if x > 0 else 0.5 / math.sqrt(max(1 - x * x, 1e-7)) - v
    return scale(cross(first, second), theta_sintheta)


def volume_factor(position, corners):
    normal = cross(sub(corners[1], corners[0]), sub(corners[3], corners[0]))
    if dot(normal, sub(position, corners[0])) < 0:
        return 0.0
    sphere = [normalize(sub(corner, position)) for corner in corners]
    total = [0.0, 0.0, 0.0]
    for index in range(4):
        total = add(total, edge_form_factor(sphere[index], sphere[(index + 1) % 4]))
    absolute = [abs(x) for x in total]
    magnitude = length(absolute)
    return max((magnitude * magnitude + absolute[2]) / (magnitude + 1), 0.0)


def rectangle_direct(light, position, camera):
    # Use absolute view positions as r186 does. Native code cancels the
    # common camera translation before rotation; no native helper is used.
    center = to_view(sub(light["position"], camera["eye"]), camera["up"], camera["back"])
    width = to_view(light["half_width"], camera["up"], camera["back"])
    height = to_view(light["half_height"], camera["up"], camera["back"])
    corners = [sub(add(center, width), height), sub(sub(center, width), height),
               add(sub(center, width), height), add(add(center, width), height)]
    view_position = to_view(sub(position, camera["eye"]), camera["up"], camera["back"])
    factor = volume_factor(view_position, corners)
    return factor, [(x * factor) ** 1.5 for x in light["radiance"]]


def distance_attenuation(distance, decay, cutoff):
    result = 1 / max(distance ** decay, 0.01)
    if cutoff > 0:
        result *= max(0, min(1, 1 - (distance / cutoff) ** 4)) ** 2
    return result


def direct(light, position, camera):
    kind = light["kind"]
    if kind == "rectangle":
        factor, result = rectangle_direct(light, position, camera)
        return {"kind": kind, "form_factor": factor, "rgb": result}
    if kind == "directional":
        # r186 direct() ignores lights without a distance property.
        return {"kind": kind, "rgb": [0.0, 0.0, 0.0]}
    toward = sub(light["position"], position)
    distance = length(toward)
    attenuation = distance_attenuation(distance, light["decay"], light["cutoff"])
    if kind == "spot":
        cosine = dot(normalize(toward), light["toward_light_axis"])
        fraction = max(0, min(1, (cosine - light["cone_cos"]) /
                                 (light["penumbra_cos"] - light["cone_cos"])))
        attenuation *= fraction * fraction * (3 - 2 * fraction)
    return {"kind": kind, "rgb": scale(light["radiance"], attenuation)}


def evaluate(scene):
    camera = scene["camera"]
    eye, fragment = camera["eye"], scene["fragment"]
    front_to_back = length(sub(eye, fragment)) > scene["model_radius"] * 2
    start, end = (eye, fragment) if front_to_back else (fragment, eye)
    ray = sub(end, start)
    step_size = length(ray) / scene["steps"]
    direction = normalize(ray)
    transmittance = [1.0, 1.0, 1.0]
    outgoing = [0.0, 0.0, 0.0]
    samples = []
    for index in range(scene["steps"]):
        position = add(start, scale(direction, (index + scene["offset"]) * step_size))
        distance = dot(sub(eye, position), camera["back"])
        depth = scene["scene_depth_m"]
        # linearDepth(viewZToPerspectiveDepth(z)) simplifies to this
        # monotonic camera-axis distance comparison for perspective cameras.
        accepted = depth is None or depth >= distance
        terms = [direct(light, position, camera) for light in scene["lights"]]
        summed = [sum(term["rgb"][channel] for term in terms) for channel in range(3)]
        density = scale(summed, scene["scattering_scale"] if accepted else 0.0)
        falloff = [math.exp(-value * 0.01 * step_size) for value in density]
        step_light = scale(density, 0.01)
        if front_to_back:
            outgoing = [old + lit * through * step_size
                        for old, lit, through in zip(outgoing, step_light, transmittance)]
        else:
            outgoing = [old * fall + lit * step_size
                        for old, fall, lit in zip(outgoing, falloff, step_light)]
        transmittance = [through * fall for through, fall in zip(transmittance, falloff)]
        samples.append({
            "index": index, "position": position, "camera_axis_depth_m": distance,
            "linear_depth": (distance - camera["near"]) / (camera["far"] - camera["near"]),
            "depth_gate": accepted, "direct_terms": terms, "ungated_light": summed,
            "scattering_density": density, "transmittance_after": transmittance,
            "r186_outgoing_after_out_of_scope": outgoing,
        })
    return {"front_to_back": front_to_back, "step_size_m": step_size, "samples": samples,
            "native_transmittance": transmittance,
            "native_accepted_output": [1 - max(0, min(1, value)) for value in transmittance],
            "r186_outgoing_out_of_scope": outgoing}


def camera(eye, back=None):
    return {"eye": eye, "up": [0, 1, 0], "back": back or [0, 0, 1],
            "near": 0.1, "far": 100.0, "projection": "perspective"}


def area(position=None, radiance=None):
    return {"kind": "rectangle", "position": position or [0, 0, 2.5],
            "half_width": [1, 0, 0], "half_height": [0, 1, 0],
            "radiance": radiance or [4, 1, 0.25]}


def mixed_lights():
    return [
        {"kind": "point", "position": [0.25, 0.5, 1], "radiance": [2, 3, 4],
         "decay": 2, "cutoff": 0},
        {"kind": "spot", "position": [0, 0, 3], "radiance": [5, 2, 1],
         "toward_light_axis": [0, 0, 1], "decay": 2, "cutoff": 8,
         "cone_cos": math.cos(math.pi / 3), "penumbra_cos": math.cos(math.pi / 4)},
        area(), area([0.5, -0.2, 2], [0.25, 0.5, 2]),
        {"kind": "directional", "radiance": [100, 100, 100]},
    ]


def scene(name, inside=False, mixed=False, depth=None, blocker="none"):
    return {"name": name, "camera": camera([0, 0, 0.5] if inside else [0, 0, 4]),
            "camera_relation": "inside" if inside else "outside",
            "fragment": [0, 0, -1], "model_radius": math.sqrt(3), "steps": 4,
            "offset": 0.0 if inside else 0.25, "scattering_scale": 0.75,
            "scene_depth_m": depth, "blocker_relation": blocker,
            "volume_bounds": {"min": [-1, -1, -1], "max": [1, 1, 1]},
            "lights": mixed_lights() if mixed else [area()]}


def build_fixture():
    scenes = []
    for mixed in (False, True):
        for label, depth in (("none", None), ("before", 2.0), ("inside", 4.0), ("behind", 6.0)):
            scenes.append(scene("outside_" + ("mixed_" if mixed else "rectangle_") + label,
                                mixed=mixed, depth=depth, blocker=label))
    for label, depth in (("none", None), ("before_samples", 0.2), ("inside", 0.5),
                         ("equality", 0.75), ("behind", 2.5)):
        scenes.append(scene("inside_mixed_" + label, inside=True, mixed=True,
                            depth=depth, blocker=label))
    back = scene("outside_rectangle_back_side")
    back["lights"] = [area([0, 0, -2])]
    scenes.append(back)
    rotated = scene("outside_rotated_camera_mixed", mixed=True)
    rotated["camera"] = camera([4, 0, 0], [1, 0, 0])
    rotated["fragment"] = [-1, 0, 0]
    scenes.append(rotated)
    # Exact inputs shared with tests/test_volume_scene_depth.mojo. Their
    # point radiance is constant, so admitted-step counts also give an
    # elementary Beer-law oracle independent of rectangle arithmetic.
    point = {"kind": "point", "position": [0, 5, 0], "radiance": [10, 10, 10],
             "decay": 0, "cutoff": 0}
    for label, depth in (("before", 1.5), ("inside", 3.5), ("behind", 6.0)):
        item = scene("depth_constant_outside_" + label, depth=depth, blocker=label)
        item.update(steps=5, offset=0.0, scattering_scale=1.0, lights=[point])
        scenes.append(item)
    item = scene("depth_constant_inside", inside=True, depth=0.5, blocker="inside")
    item.update(steps=5, offset=0.0, scattering_scale=1.0, lights=[point])
    scenes.append(item)
    item = scene("depth_constant_oblique", depth=1.7, blocker="inside")
    item.update(camera=camera([3, 0, 4]), fragment=[0, 0, 0], model_radius=1.0,
                steps=5, offset=0.0, scattering_scale=1.0, lights=[point])
    scenes.append(item)
    direct_cases = []
    for name, position, back in (("axis_front", [0, 0, 0], [0, 0, 1]),
                                 ("off_axis", [0.3, -0.4, -0.2], [0, 0, 1]),
                                 ("yaw_90", [0, 0, 0], [1, 0, 0]),
                                 ("back_side", [0, 0, 2], [0, 0, 1]),
                                 ("on_emitter_plane", [0, 0, 1], [0, 0, 1])):
        light, view = area([0, 0, 1], [4, 1, 0]), camera([0, 0, 4], back)
        factor, color = rectangle_direct(light, position, view)
        direct_cases.append({"name": name, "position": position, "camera": view,
                             "light": light, "form_factor": factor, "direct_light": color})
    return {
        "schema_version": 1, "upstream": "three.js r186", "issue": 616,
        "generation": "Independent Python Float64 scalar equations, not a WebGPU capture",
        "sources": [{"path": path, "git_blob_sha": sha,
                     "url": "https://github.com/mrdoob/three.js/blob/r186/" + path}
                    for path, sha in SOURCE_BLOBS.items()],
        "scope": {
            "accepted": "r186 rectangle direct light and scattering-depth gate; native 1-transmittance output retained",
            "out_of_scope": "r186 outgoingRayLight recurrence and scatteringEmissiveNode port",
            "depth": "Opaque positive camera-axis distance; equality accepted; original ray samples unchanged",
            "before_blocker": "Outside-camera samples before the volume and blocker can contribute, as in r186",
            "normalization": "All reference normalizations are nonzero; native normalize(0) stays zero, while GPU normalize(0) is undefined",
            "rounding": "Native Float32 may differ in final bits; sqrt(x)*x replaces power 1.5 and common view translation cancels before rotation",
            "shadows": "These independent mixed scenes have no shadows, IES maps, or projectors; existing native regressions cover them",
        },
        "direct_cases": direct_cases,
        "scenes": [dict(deepcopy(item), expected=evaluate(item)) for item in scenes],
    }


def compare(expected, actual, path="root"):
    if isinstance(expected, dict):
        if not isinstance(actual, dict) or set(expected) != set(actual):
            raise AssertionError(path + ": object keys differ")
        for key in expected:
            compare(expected[key], actual[key], path + "." + key)
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            raise AssertionError(path + ": list sizes differ")
        for index, (want, got) in enumerate(zip(expected, actual)):
            compare(want, got, path + "[" + str(index) + "]")
    elif isinstance(expected, float):
        if not isinstance(actual, (int, float)) or not math.isclose(expected, actual, rel_tol=2e-14, abs_tol=2e-14):
            raise AssertionError(f"{path}: {actual!r} != {expected!r}")
    elif expected != actual or type(expected) is not type(actual):
        raise AssertionError(f"{path}: {actual!r} != {expected!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="replace the checked-in JSON fixture")
    mode.add_argument("--check", action="store_true", help="check the fixture (default)")
    args = parser.parse_args()
    expected = build_fixture()
    if args.write:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(json.dumps(expected, indent=2, allow_nan=False) + "\n")
        verb = "wrote"
    else:
        compare(expected, json.loads(FIXTURE.read_text()))
        verb = "checked"
    print(f"{verb} {len(expected['direct_cases'])} direct cases and "
          f"{len(expected['scenes'])} ray scenes: {FIXTURE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
