# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI on the full renderer: two orbiting cubes, turned with a mouse.

These are the functions of `window.capi_core`, with the same names and the
same meaning, so a host cannot tell the two apart. Here a call does real
work. `tm_event` becomes an `InputEvent` for `OrbitControls`, `tm_step`
turns the scene graph, and `tm_frame` runs `Renderer.render`. The scene is
the one in `examples/cubes.mojo`.

Nothing may raise across a C boundary. Each call that can raise is caught
here, and the call then does nothing: an event the controls refuse is
dropped, and a frame that cannot be drawn is the last one that could.

This module builds for the host only. The renderer uses lists, strings,
errors and threads, and Mojo 1.1 has no WebAssembly backend for them. Never
import this module and `window.capi_core` into one program.

A host that is not a Mojo program must call `tm_init` once, before any
other function. The renderer's thread pool needs the runtime that
`tm_init` starts, and without it `tm_create` crashes.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    InputKind,
    Key,
    NO_BUTTON,
    NO_KEY,
    PointerButton,
)
from controls.orbit_controls import OrbitControls
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.memory import Layout
from std.runtime import initialize_runtime
from units.si import Angle, DEGREE, Duration, Length, METER, MILLISECOND
from window.capi_abi import (
    ABI_VERSION,
    KEY_DOWN,
    KEY_SPACE,
    KEY_UP,
    MAX_SIDE,
    WHEEL,
)

comptime DEGREES_PER_SECOND = Float32(150)
"""How fast the cubes turn: one orbit in 2.4 seconds, as `cubes.mojo` runs."""
comptime ORBIT_RADIUS = Float32(1.6)
"""The small cube's distance from the pivot, in meters."""


struct SceneApp(Movable):
    """The state that a host's handle points at."""

    var width: Int
    """The frame's width, in pixels."""
    var height: Int
    """The frame's height, in pixels."""
    var renderer: Renderer
    """The CPU renderer."""
    var camera: PerspectiveCamera
    """The camera that `controls` turns."""
    var assets: Assets
    """The geometry and the materials of both cubes."""
    var scene: Scene
    """The scene graph, edited in place each step."""
    var controls: OrbitControls
    """The mouse and keyboard controls of `camera`."""
    var pivot: NodeId
    """The node that the small cube orbits."""
    var center: NodeId
    """The large cube's node."""
    var moon: NodeId
    """The small cube's node, a child of `pivot`."""
    var paused: Bool
    """Whether `tm_step` ignores time."""
    var frame: Framebuffer
    """The last frame drawn."""

    def __init__(out self, width: Int, height: Int) raises:
        """Build the scene and draw its first frame.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.

        Raises:
            Error: If a side is not positive.
        """
        self.width = width
        self.height = height
        self.camera = PerspectiveCamera(
            Angle(45.0, DEGREE),
            Float32(width) / Float32(height),
            Length(0.1, METER),
            Length(100.0, METER),
        )
        self.camera.place(Vector3(0, 1.2, 4.5), Vector3(0, 0, 0))
        self.renderer = Renderer(width, height, workers=available_workers())
        self.assets = Assets()
        var large = self.assets.geometries.add(cube(Length(1.1, METER)))
        var small = self.assets.geometries.add(cube(Length(0.44, METER)))
        var orange = self.assets.materials.add(Material(Color(255, 140, 40)))
        var blue = self.assets.materials.add(Material(Color(90, 190, 255)))
        self.scene = Scene()
        self.pivot = self.scene.add(Object3D())
        var large_node = Object3D()
        large_node.set_euler(
            Angle(20.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
        )
        self.center = self.scene.add(large_node^)
        var moon_node = Object3D()
        moon_node.set_position(ORBIT_RADIUS, 0, 0)
        self.moon = self.scene.attach(moon_node^, self.pivot)
        var lamp = Object3D()
        lamp.set_position(0.4, 0.8, 0.5)
        var lamp_node = self.scene.add(lamp^)
        self.scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
        self.scene.add_light(
            directional_light(Color(255, 255, 255), lamp_node, 2.36)
        )
        self.scene.add_mesh(Mesh(large, orange, self.center))
        self.scene.add_mesh(Mesh(small, blue, self.moon))
        self.controls = OrbitControls(Vector3(0, 0, 0))
        self.paused = False
        self.scene.update()
        self.frame = self.renderer.render(self.scene, self.assets, self.camera)


def _app(
    handle: OpaquePointer[MutUntrackedOrigin],
) -> Pointer[SceneApp, MutUntrackedOrigin]:
    """View a host's handle as the app it points at.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        A pointer to the app.
    """
    return handle.unsafe_bitcast[SceneApp]()


@export("tm_abi_version")
def tm_abi_version() abi("C") -> Int32:
    """Return the version of the C ABI, so that a host can check it.

    Returns:
        `ABI_VERSION`.
    """
    return Int32(ABI_VERSION)


@export("tm_init")
def tm_init() abi("C") -> None:
    """Start the Mojo runtime.

    A host that is not a Mojo program must call this once, before any other
    function.
    """
    initialize_runtime()


@export("tm_create")
def tm_create(
    width: Int32, height: Int32
) abi("C") -> OptionalPointer[SceneApp, MutUntrackedOrigin]:
    """Make an app with a frame of a size.

    Args:
        width: The frame's width, in pixels, from 1 to `MAX_SIDE`.
        height: The frame's height, in pixels, from 1 to `MAX_SIDE`.

    Returns:
        The app's handle, or NULL if a side is out of range.
    """
    var w = Int(width)
    var h = Int(height)
    if w > MAX_SIDE or h > MAX_SIDE:
        return None
    try:
        var app = SceneApp(w, h)
        var slot = alloc(Layout[SceneApp](count=1)).unsafe_leak()
        slot.unsafe_write(app^)
        return slot
    except:
        return None


@export("tm_destroy")
def tm_destroy(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> None:
    """Free an app. The handle must not be used again.

    Args:
        handle: A handle from `tm_create`.
    """
    var app = _app(handle)
    _ = app.unsafe_take_pointee()
    app.unsafe_free()


@export("tm_event")
def tm_event(
    handle: OpaquePointer[MutUntrackedOrigin],
    kind: Int32,
    x: Int32,
    y: Int32,
    detail: Int32,
) abi("C") -> None:
    """Tell an app about one input event.

    The space bar pauses the app, and pauses it no more when pressed again.
    Any other event goes to the orbit controls: a drag with the first
    button turns the camera, the second pans it, and the wheel dollies. An
    event that the controls refuse, such as one of an unknown kind, is
    dropped.

    Args:
        handle: A handle from `tm_create`.
        kind: The kind, as `controls.input.InputKind` numbers it.
        x: The pointer's column, in pixels.
        y: The pointer's row, in pixels.
        detail: The key code of a key event, the button of a pointer event,
            as `controls.input.PointerButton` numbers it, or -1, or the
            notches of a wheel event, positive toward the user.
    """
    var app = _app(handle)
    var event_kind = Int(kind)
    if event_kind == KEY_DOWN and Int(detail) == KEY_SPACE:
        app[].paused = not app[].paused
        return
    var key = NO_KEY
    var button = NO_BUTTON
    var notches = 0
    if event_kind == KEY_DOWN or event_kind == KEY_UP:
        key = Key(Int(detail))
    elif event_kind == WHEEL:
        notches = Int(detail)
    else:
        button = PointerButton(Int(detail))
    var event = InputEvent(
        InputKind(event_kind),
        key=key,
        button=button,
        x=Int(x),
        y=Int(y),
        wheel=notches,
    )
    try:
        app[].controls.handle(event, app[].camera, app[].height)
    except:
        pass


@export("tm_step")
def tm_step(
    handle: OpaquePointer[MutUntrackedOrigin], microseconds: Int32
) abi("C") -> None:
    """Move an app on by a time delta.

    The cubes turn, and the controls apply what the events asked of the
    camera. Time that is negative, or that comes while the app is paused,
    is ignored.

    Args:
        handle: A handle from `tm_create`.
        microseconds: The time since the last step, in microseconds.
    """
    var app = _app(handle)
    if app[].paused or microseconds < 0:
        return
    var seconds = Float32(Int(microseconds)) / 1000000.0
    var degrees = seconds * DEGREES_PER_SECOND
    try:
        app[].scene.node(app[].pivot).rotate_y(Angle(degrees, DEGREE))
        app[].scene.node(app[].center).rotate_y(Angle(degrees / 2, DEGREE))
        app[].scene.node(app[].moon).rotate_z(Angle(degrees * 2, DEGREE))
        app[].scene.update()
    except:
        return
    _ = app[].controls.update(
        app[].camera,
        Duration(Float32(Int(microseconds)) / 1000.0, MILLISECOND),
    )


@export("tm_frame")
def tm_frame(
    handle: OpaquePointer[MutUntrackedOrigin],
) abi("C") -> Pointer[UInt8, MutUntrackedOrigin]:
    """Draw an app's scene and return the frame.

    A scene that cannot be drawn leaves the last frame that could be.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The frame: RGBA, eight bits a channel, row by row from the top,
        `tm_width * tm_height * 4` bytes. It stays valid until the next
        call on this app.
    """
    var app = _app(handle)
    try:
        app[].frame = app[].renderer.render(
            app[].scene, app[].assets, app[].camera
        )
    except:
        pass
    return Pointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(app[].frame.pixels.unsafe_ptr())
    )


@export("tm_width")
def tm_width(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Return an app's frame width.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The width, in pixels.
    """
    return Int32(_app(handle)[].width)


@export("tm_height")
def tm_height(handle: OpaquePointer[MutUntrackedOrigin]) abi("C") -> Int32:
    """Return an app's frame height.

    Args:
        handle: A handle from `tm_create`.

    Returns:
        The height, in pixels.
    """
    return Int32(_app(handle)[].height)
