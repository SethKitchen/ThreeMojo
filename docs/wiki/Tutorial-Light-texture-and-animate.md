# Tutorial: light, texture and animate a scene

In this tutorial you extend the first scene with a texture, a point light and motion. The result is an animated PNG of a checkerboard cube that turns under a warm bulb. It takes about fifteen minutes.

![A checkerboard cube turns under a warm bulb](out/lit_scene.png)

Complete [Render your first scene](Tutorial-Render-your-first-scene) first. The finished program is `examples/lit_scene.mojo` in the repository.

## 1. Change the imports

Replace the PNG encoder with the animated one, and import the texture and light helpers:

```mojo
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, point_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.texture import BILINEAR, REPEAT, checkerboard
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from units.si import Angle, DEGREE, Length, METER
```

## 2. Add a texture

A texture is an asset too. Make a checkerboard with a mip chain, and a white material that shows it:

```mojo
def main() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var board = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(245, 245, 250),
            Color(35, 70, 150),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var tiled = assets.materials.add(Material(Color(255, 255, 255), board))
```

The material color multiplies the texture. White shows the image as it is. The mip chain keeps the far side of the cube smooth.

## 3. Build the scene

```mojo
    var scene = Scene()
    var block = Object3D()
    block.set_euler(Angle(25.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    var node = scene.add(block^)
    scene.add_mesh(Mesh(box, tiled, node))
```

The tilt is set once. The animation turns the node about its own y axis, and the tilt stays.

## 4. Add a bulb

A point light sits at a position and falls off with distance:

```mojo
    var bulb = Object3D()
    bulb.set_position(0.8, 1.0, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 1.5))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.15))
```

The third argument is the intensity at one meter. The default decay is the inverse-square law.

## 5. Place the camera and the renderer

```mojo
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 4.0 / 3.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0.6, 3), Vector3(0, 0, 0))

    var renderer = Renderer(320, 240, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
```

`workers=available_workers()` draws each frame on every core.

## 6. Render the frames

Turn the node a little each frame, update the scene, and keep the image:

```mojo
    var frames = List[Framebuffer]()
    var step = Angle(Float32(360) / Float32(36), DEGREE)
    for _ in range(36):
        scene.node(node).rotate_y(step)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))

    Path("out/lit_scene.png").write_bytes(encode(frames, delay_ms=60))
    print("Wrote out/lit_scene.png -", len(frames), "frames")
```

`scene.node(node)` returns the node for editing and marks the scene stale. `rotate_y` is one quaternion multiply. Thirty-six steps of ten degrees make one full turn, so the loop is seamless.

## 7. Run it

```bash
mkdir -p out
.venv/bin/mojo run -I . examples/lit_scene.mojo
```

Open `out/lit_scene.png` in a browser or in VS Code. The cube turns. The bulb lights the face nearest to it most, and the far faces fade.

## What you learned

- A texture belongs to a material, and the material color multiplies it.
- A point light needs a node for its position. Its light falls off with distance.
- Edit a node in place with `scene.node(id)`. Then call `scene.update()`.
- An APNG holds many frames. The first frame is a plain PNG.

Next: read [Lights](Lights) and [Textures](Textures) for every option.
