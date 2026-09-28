# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A computed ripple field plays across a turning sphere.

    mojo run -I . examples/ripples.mojo [path.png]

The page is GPU computation. `GPUComputationRenderer` steps one float
image with a fragment shader. Each frame the image becomes the sphere's
map. The phase advances by one twelfth, so the rings return to their
start after the last frame.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.computation import GPUComputationRenderer
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/computation.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime SIZE = 96

comptime RIPPLE = """
void main() {
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    vec4 p = texture2D( field, uv );
    vec2 centered = uv - vec2( 0.5, 0.5 );
    float dist = length( centered );
    float wave = 0.5 + 0.5 * sin( dist * 28.0 - p.w * 6.283185 );
    gl_FragColor = vec4(
        wave, 0.22 + 0.5 * uv.y, 0.92 - 0.55 * wave, p.w + 1.0 / 12.0
    );
}
"""


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    mut assets: Assets,
    mut scene: Scene,
    mut computation: GPUComputationRenderer,
    field: Int,
    paint: Int,
    ball: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Step the field, wear it on the sphere, and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the sphere.
        assets: The geometry, the material and the textures.
        scene: The persistent scene, edited in place.
        computation: The ripple field.
        field: Which variable holds the image.
        paint: Which material wears the image.
        ball: The sphere's node.
        step: How much further the sphere turns.

    Returns:
        The rendered frame.

    Raises:
        Error: If the field, the scene or the render is invalid.
    """
    computation.compute()
    assets.materials.materials[paint].map = assets.textures.add(
        computation.current_texture(field)
    )
    scene.node(ball).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var computation = GPUComputationRenderer(SIZE, SIZE)
    var field = computation.add_variable(
        "field", RIPPLE, computation.create_texture()
    )
    computation.set_variable_dependencies(field, [field])
    computation.init()
    computation.compute()

    var assets = Assets()
    var ball_shape = assets.geometries.add(sphere(Length(0.85, METER), 28, 18))
    var paint = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=BASIC,
            map=assets.textures.add(computation.current_texture(field)),
        )
    )

    var scene = Scene()
    var ball = scene.add(Object3D())
    scene.add_mesh(Mesh(ball_shape, paint, ball))

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.15, 0.35, 2.55), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                computation,
                field,
                paint.value,
                ball,
                step,
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
