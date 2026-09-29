# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One CARLA sensor rig on an OpenDRIVE road.

    mojo run -I . examples/carla.mojo [path.png]

The road is a line, a spiral and an arc, with two lanes each way, built
with CARLA's `MapBuilder`. Its surface and paint come from CARLA's
`MeshFactory`. Cars sit in lanes at CARLA's waypoint transforms. One
camera sees the scene three ways, side by side: the RGB render with one
LiDAR sweep on top, the CityScapes semantic image, and the logarithmic
depth image. The page is CARLA.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.carla.capture import depth_frame, semantic_frame
from extensions.carla.geometry import RoadGeometry, arc, line, spiral
from extensions.carla.lidar import LidarDescription, scan_lidar
from extensions.carla.map import Map, Waypoint
from extensions.carla.map_builder import MapBuilder
from extensions.carla.mesh_factory import (
    LaneMarkMesh,
    MeshFactory,
    to_three_frame,
)
from extensions.carla.road_info import (
    JuncId,
    LANE_DRIVING,
    LANE_NONE,
    LaneId,
    RoadId,
    SectionId,
)
from extensions.carla.sensor import (
    BUILDING,
    CAR,
    CameraIntrinsics,
    ROAD,
    ROAD_LINE,
    SKY,
    SemanticTag,
    TERRAIN,
    logarithmic_gray,
    normalized_depth,
)
from extensions.carla.transform import (
    CarlaRotation,
    CarlaTransform,
    carla_to_three,
)
from geometries.box import box
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.png import encode
from renderers.renderer import Renderer, available_workers
from std.math import atan, tan
from std.pathlib import Path
from std.sys import argv
from units.si import (
    DEGREE,
    InverseLength,
    Length,
    METER,
    PER_METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
)

comptime DEFAULT_OUTPUT = "out/carla.png"
comptime WIDTH = 400
comptime HEIGHT = 240
comptime FOV = Float32(90)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _next_start(record: RoadGeometry) -> Tuple[Float32, Float32, Float32]:
    var end = record.pos_from_dist(_m(Float32(record.length)))
    return (Float32(end.x), Float32(end.y), Float32(end.tangent))


def build_map() raises -> Map:
    """Return one road: a line, a spiral and an arc, two lanes each way.

    Returns:
        The map, with the road's lanes and marks.

    Raises:
        Error: If a record is not valid, which it is.
    """
    var first = line(_m(0), _m(0), _m(0), Angle(0, RADIAN), _m(40))
    var a = _next_start(first)
    var second = spiral(
        _m(40),
        _m(a[0]),
        _m(a[1]),
        Angle(a[2], RADIAN),
        _m(30),
        InverseLength(0.0, PER_METER),
        InverseLength(0.02, PER_METER),
    )
    var b = _next_start(second)
    var builder = MapBuilder()
    var road = builder.add_road(
        RoadId(1), "demo", 130.0, JuncId(-1), RoadId(0), RoadId(0), True
    )
    builder.add_road_geometry_line(road, 0.0, 0.0, 0.0, 0.0, 40.0)
    builder.add_road_geometry_spiral(
        road, 40.0, Float64(a[0]), Float64(a[1]), Float64(a[2]), 30.0, 0.0, 0.02
    )
    builder.add_road_geometry_arc(
        road, 70.0, Float64(b[0]), Float64(b[1]), Float64(b[2]), 60.0, 0.02
    )
    _ = builder.add_road_section(road, SectionId(0), 0.0)
    for id in [-2, -1, 0, 1, 2]:
        var kind = LANE_NONE if id == 0 else LANE_DRIVING
        _ = builder.add_road_section_lane(
            road, 0, LaneId(id), kind, False, LaneId(0), LaneId(0)
        )
        var lane = builder.lane(RoadId(1), LaneId(id), 0.0)
        builder.create_lane_width(lane, 0.0, 0.0 if id == 0 else 3.5, 0, 0, 0)
        # The center line is solid and 0.3 m wide; the lanes between are
        # broken and the outer edges solid, 0.15 m wide.
        var mark = "broken" if abs(id) == 1 else "solid"
        var width = 0.3 if id == 0 else 0.15
        builder.create_road_mark(
            lane,
            0,
            0.0,
            mark,
            "",
            "white",
            "",
            width,
            "",
            0.0,
            "",
            0.0,
            True,
        )
    builder.create_section_offset(road, 0.0, 0, 0, 0, 0)
    builder.add_road_elevation_profile(road, 0.0, 0, 0, 0, 0)
    return builder.build()


def _lane_transform(map: Map, s: Float64, lane: Int) raises -> CarlaTransform:
    return map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(lane), s)
    )


def place(mut node: Object3D, transform: CarlaTransform, lift: Float32):
    """Put a three.js node where CARLA puts an actor.

    Args:
        node: The node to move.
        transform: The actor's transform, in CARLA's frame.
        lift: How far above the transform the node's center sits.
    """
    var at = carla_to_three(transform.location + Vector3(0, 0, lift))
    node.set_position(at.x, at.y, at.z)
    node.set_rotation_from_matrix(transform.three_matrix())


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var map = build_map()
    ref road = map.road(RoadId(1))
    var factory = MeshFactory()
    factory.road_param.resolution = _m(2)
    var assets = Assets()
    var scene = Scene()
    var tags = List[SemanticTag]()

    var asphalt = assets.materials.add(Material(Color(70, 72, 78)))
    var paint = assets.materials.add(Material(Color(235, 235, 225)))
    var grass = assets.materials.add(Material(Color(96, 128, 72)))
    var concrete = assets.materials.add(Material(Color(176, 168, 158)))
    var body = assets.materials.add(Material(Color(180, 30, 36)))
    var other_body = assets.materials.add(Material(Color(40, 90, 170)))

    var ground = plane(_m(400), _m(400))
    var ground_id = assets.geometries.add(ground^)
    var ground_node = Object3D()
    ground_node.rotate_x(Angle(-90, DEGREE))
    ground_node.set_position(60, -0.02, 30)
    scene.add_mesh(Mesh(ground_id, grass, scene.add(ground_node^)))
    tags.append(TERRAIN)

    for lane in range(len(road.sections[0].lanes)):
        if road.sections[0].lanes[lane].id.value == 0:
            continue
        var surface = assets.geometries.add(
            to_three_frame(factory.generate_whole_lane(road, 0, lane))
        )
        scene.add_mesh(Mesh(surface, asphalt, scene.add(Object3D())))
        tags.append(ROAD)
    var marks = List[LaneMarkMesh]()
    var colors = List[String]()
    factory.generate_lane_mark_for_road(road, marks, colors)
    for i in range(len(marks)):
        var mark = assets.geometries.add(to_three_frame(marks[i].geometry))
        scene.add_mesh(Mesh(mark, paint, scene.add(Object3D())))
        tags.append(ROAD_LINE)

    var car = assets.geometries.add(box(_m(4.5), _m(1.5), _m(1.8)))
    var cars: List[Tuple[Float64, Int, Int]] = [
        (30.0, -1, 0),
        (52.0, -2, 1),
        (70.0, 1, 1),
        (95.0, -1, 0),
        (44.0, 2, 0),
    ]
    for c in cars:
        var node = Object3D()
        place(node, _lane_transform(map, c[0], c[1]), 0.75)
        var paint_id = body if c[2] == 0 else other_body
        scene.add_mesh(Mesh(car, paint_id, scene.add(node^)))
        tags.append(CAR)

    var block = assets.geometries.add(box(_m(12), _m(14), _m(10)))
    for s in [Float32(20), Float32(58), Float32(96), Float32(122)]:
        for side in [Float32(-1), Float32(1)]:
            var edge = road.directed_point(Float64(s))
            edge.apply_lateral_offset(_m(side * 16))
            var node = Object3D()
            place(node, edge.to_carla(), 7)
            scene.add_mesh(Mesh(block, concrete, scene.add(node^)))
            tags.append(BUILDING)

    # The ego car drives lane -1. Its camera sits on the roof.
    var ego = _lane_transform(map, 16.0, -1)
    var camera_pose = CarlaTransform(
        _m(ego.location.x),
        _m(ego.location.y),
        _m(2.2),
        CarlaRotation(
            Angle(0, DEGREE), Angle(ego.rotation.yaw, DEGREE), Angle(0, DEGREE)
        ),
    )
    var eye = Object3D()
    var pose = camera_pose.camera_matrix()
    eye.set_position(pose.elements[12], pose.elements[13], pose.elements[14])
    eye.set_rotation_from_matrix(pose)
    var eye_node = scene.add(eye^)
    var lamp = Object3D()
    lamp.set_position(-30, 60, -40)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.55))
    scene.add_light(directional_light(Color(255, 250, 240), lamp_node, 2.2))
    scene.update()

    # CARLA's fov is horizontal. A three.js camera's fov is vertical.
    var half = Float32(FOV) * 0.5 * Float32(0.017453292519943295)
    var vertical = 2.0 * atan(tan(half) * Float32(HEIGHT) / Float32(WIDTH))
    var camera = PerspectiveCamera(
        Angle(vertical, RADIAN),
        Float32(WIDTH) / Float32(HEIGHT),
        _m(0.1),
        _m(1000),
    )
    camera.attach(eye_node)
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(70, 130, 180))
    var rgb = renderer.render(scene, assets, camera)

    var k = CameraIntrinsics(WIDTH, HEIGHT, Angle(FOV, DEGREE))
    var semantic = semantic_frame(scene, assets, tags, SKY, camera_pose, k)
    var depth = depth_frame(scene, assets, camera_pose, k)

    var lidar = LidarDescription()
    lidar.range = _m(60)
    lidar.points_per_second = 90000
    lidar.upper_fov = Angle(2, DEGREE)
    lidar.lower_fov = Angle(-24, DEGREE)
    var sensor = CarlaTransform(
        _m(ego.location.x), _m(ego.location.y), _m(2.4), ego.rotation
    )
    var sweep = scan_lidar(
        scene, assets, sensor, lidar, Duration(0.1, SECOND), Angle(0, DEGREE), 1
    )

    var out = Framebuffer(WIDTH * 3, HEIGHT, Color(0, 0, 0))
    for y in range(HEIGHT):
        for x in range(WIDTH):
            out.set_pixel(x, y, rgb.get_pixel(x, y))
            out.set_pixel(WIDTH + x, y, semantic.get_pixel(x, y))
            var gray = logarithmic_gray(normalized_depth(depth.get_pixel(x, y)))
            var level = UInt8(Int(gray * 255.0 + 0.5))
            out.set_pixel(2 * WIDTH + x, y, Color(level, level, level))
    for p in sweep.points:
        var world = sensor.transform_point(p.point)
        var pixel = k.project(camera_pose, world)
        var px = Int(pixel.x)
        var py = Int(pixel.y)
        if pixel.z > 0.0 and px >= 0 and px < WIDTH and py >= 0 and py < HEIGHT:
            # Yellow near, cyan at 40 m and beyond.
            var t = min(pixel.z / 40.0, Float32(1.0))
            out.set_pixel(
                px,
                py,
                Color(
                    UInt8(Int(255.0 * (1.0 - t))),
                    UInt8(Int(210.0 + 30.0 * t)),
                    UInt8(Int(255.0 * t)),
                ),
            )

    Path(destination).write_bytes(encode(out))
    print("Wrote", destination, "-", len(sweep.points), "LiDAR points")
