# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The splat app that the C ABI's splat library keeps: a scan, a camera and
the orbit controls that turn it.

`window.capi_splat` exports it under the C names. This module holds the state
and the rules, and exports nothing. The scene is the three.js example
`webgpu_gaussian_splat`: one scan of Gaussian splats on a dark ground, seen
by a 50 degree camera that stands where `cameras.fit_sphere` puts it, and
turned with the orbit controls and damping. The camera also turns by itself
until the space bar stops it.

A host can draw a frame in two ways.

- `draw` draws on the CPU, with `draw_gaussian_splat`, as the examples do.
  It takes about 0.2 s a frame for 445,409 splats.
- `prepare` makes what a host's GPU needs and the host draws. The scan stays
  where it is in memory, and `part` says where. `prepare` sorts the splats
  back to front on the CPU when the view has turned far enough, which is a few
  milliseconds, and it writes the draw order and the view. The GPU projects
  every splat, shades it with its spherical harmonics, and blends the quads in
  that order. This is three.js's own split: its `updateSort` runs between
  frames and the shaders do the rest.

Both ways draw the same picture. The colors blend as they are stored, and the
screen shows them as they are, because the example sets its working color
space to sRGB.
"""

from cameras.fit_sphere import fit_sphere
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
from core.gaussian_splat_utils import GaussianSplatGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from loaders.spz import parse_spz
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.framebuffer import Color, Framebuffer
from render.splat_raster import draw_gaussian_splat
from render.working_space import resolve_srgb_working, srgb_working_target
from std.pathlib import Path
from units.si import DEGREE, METER, MILLISECOND, Angle, Duration, Length
from window.capi_abi import (
    KEY_DOWN,
    KEY_SPACE,
    KEY_UP,
    SPLAT_CENTERS,
    SPLAT_COLORS,
    SPLAT_COVARIANCES,
    SPLAT_INFO_COUNT,
    SPLAT_INFO_DEGREE,
    SPLAT_INFO_ORDER,
    SPLAT_INFO_SCAN,
    SPLAT_ORDER,
    SPLAT_SH1,
    SPLAT_SH2,
    SPLAT_SH3,
    SPLAT_VIEW,
    SPLAT_VIEW_FLOATS,
    SplatInfo,
    SplatPart,
    WHEEL,
)

comptime SCAN = "assets/tomatoes/tomatoes.v4.spz"
"""The scan, relative to the folder the program runs in."""
comptime BACKGROUND = Color(7, 8, 15)
"""The example's `scene.background`, `0x07080f`."""
comptime VIEW_FROM = Vector3(0, 0.35, 1)
"""The example's `cameraPosition` for the tomato scan: which side the camera
takes."""
comptime LONGEST_MICROSECONDS = 100000
"""The most time that one `advance` counts. A host that was stopped for a
while does not turn the camera a long way at once."""
comptime TURN_SPEED = Float32(4)
"""The automatic turn, in three.js's `autoRotateSpeed`: 15 s a turn."""
comptime NEAREST_SHARE = Float32(1.1)
"""The nearest the camera goes, as a share of the scan's radius."""
comptime FARTHEST_SHARE = Float32(8)
"""The farthest the camera goes, as a share of the scan's radius."""
comptime SMALLEST_RADIUS = Float32(0.01)
"""The least radius that the camera is fitted to, in meters, as the example."""

# Where the view's numbers are in the `SPLAT_VIEW` part. `window/threemojo.h`
# and the hosts' shaders read the same places.
comptime VIEW_MODEL_VIEW = 0
comptime VIEW_PROJECTION = 16
comptime VIEW_WIDTH = 32
comptime VIEW_HEIGHT = 33
comptime VIEW_EYE = 34
comptime VIEW_DEGREE = 37
comptime VIEW_COUNT = 38
comptime VIEW_BACKGROUND = 40


def _words(values: List[Float32]) -> Tuple[Int, Int]:
    """Return the address and the size in words of a list of floats.

    Args:
        values: The list. It is not empty: a scan has at least one splat, and
            the view always has `SPLAT_VIEW_FLOATS` floats.

    Returns:
        The address of the first float and the count.
    """
    return (Int(values.unsafe_ptr()), len(values))


def _band(values: List[UInt8]) -> Tuple[Int, Int]:
    """Return the address and the size in words of a list of bytes.

    Args:
        values: The list. Its length is a whole number of words.

    Returns:
        The address of the first byte and the length divided by four, or 0 and
        0 for an empty list.
    """
    if len(values) == 0:
        return (0, 0)
    return (Int(values.unsafe_ptr()), len(values) // 4)


def _order(values: List[UInt32]) -> Tuple[Int, Int]:
    """Return the address and the size in words of the draw order.

    Args:
        values: The order.

    Returns:
        The address of the first index and the count, or 0 and 0 for an empty
        order.
    """
    if len(values) == 0:
        return (0, 0)
    return (Int(values.unsafe_ptr()), len(values))


struct SplatApp(Movable):
    """The state that a host's handle points at."""

    var width: Int
    """The frame's width, in pixels."""
    var height: Int
    """The frame's height, in pixels."""
    var scene: Scene
    """The scene graph: one node, which places the scan."""
    var node: NodeId
    """The scan's node."""
    var splat: GaussianSplat
    """The scan. Its geometry is empty until `load`."""
    var loaded: Bool
    """Whether `splat` holds a scan."""
    var camera: PerspectiveCamera
    """The camera that `controls` turns."""
    var controls: OrbitControls
    """The mouse and keyboard controls of `camera`."""
    var frame: Framebuffer
    """The last frame that `draw` made."""
    var order: List[UInt32]
    """The draw order of the last `prepare`, furthest splat first."""
    var view: List[Float32]
    """The view of the last `prepare`: `SPLAT_VIEW_FLOATS` numbers."""
    var scan_generation: Int
    """How many scans have been loaded."""
    var order_generation: Int
    """How many times `prepare` has made the order."""

    def __init__(out self, width: Int, height: Int) raises:
        """Build an app with no scan and a black frame.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.

        Raises:
            Error: If a side is not positive.
        """
        self.width = width
        self.height = height
        self.frame = Framebuffer(width, height, Color(0, 0, 0))
        self.scene = Scene()
        self.node = self.scene.add(Object3D())
        self.scene.update()
        self.splat = GaussianSplat(GaussianSplatGeometry(), self.node)
        self.loaded = False
        self.camera = PerspectiveCamera(
            Angle(50.0, DEGREE),
            Float32(width) / Float32(height),
            Length(0.01, METER),
            Length(100.0, METER),
        )
        self.camera.place(Vector3(0, 0.35, 3.2), Vector3(0, 0, 0))
        self.controls = OrbitControls(Vector3(0, 0, 0))
        self.controls.enable_damping = True
        self.controls.auto_rotate = True
        self.controls.auto_rotate_speed = TURN_SPEED
        self.order = List[UInt32]()
        self.view = List[Float32](length=SPLAT_VIEW_FLOATS, fill=0)
        self.scan_generation = 0
        self.order_generation = 0

    def load(mut self, file: List[UInt8]) raises:
        """Replace the scan with an `.spz` file, and frame it.

        Args:
            file: The bytes of an `.spz` file.

        Raises:
            Error: If the file is not one that `parse_spz` reads, or it holds
                no splats. The app is not changed then.
        """
        self.load_geometry(parse_spz(file))

    def load_geometry(mut self, var geometry: GaussianSplatGeometry) raises:
        """Replace the scan with splats, and frame them as the example does.

        The camera stands on the side of the scan's bounding sphere that
        `VIEW_FROM` names, and the controls orbit the sphere's center between
        1.1 and 8 times its radius.

        Args:
            geometry: The splats.

        Raises:
            Error: If there are no splats. The app is not changed then.
        """
        if geometry.count() == 0:
            raise Error("The scan has no splats")
        var splat = GaussianSplat(geometry^, self.node)
        splat.compute_bounding_sphere()
        var sphere = splat.bounding_sphere.value()
        var radius = max(sphere.radius, SMALLEST_RADIUS)
        _ = fit_sphere(
            self.camera,
            sphere.center,
            Length(radius, METER),
            VIEW_FROM,
        )
        self.controls.target = sphere.center
        self.controls.min_distance = Length(radius * NEAREST_SHARE, METER)
        self.controls.max_distance = Length(radius * FARTHEST_SHARE, METER)
        _ = self.controls.update(self.camera, Duration(0.0, MILLISECOND))
        self.splat = splat^
        self.loaded = True
        self.order = List[UInt32]()
        self.scan_generation += 1

    def load_path(mut self, path: String) -> Bool:
        """Load the scan from a file, if the file can be read.

        Args:
            path: The `.spz` file.

        Returns:
            Whether the scan is loaded. The app is not changed when it is not.
        """
        try:
            self.load(Path(path).read_bytes())
        except:
            return False
        return True

    def resize(mut self, width: Int, height: Int) raises:
        """Change the size of the frame, and keep the scan and the view.

        Args:
            width: The new width, in pixels.
            height: The new height, in pixels.

        Raises:
            Error: If a side is not positive. The app is not changed then.
        """
        self.frame = Framebuffer(width, height, Color(0, 0, 0))
        self.width = width
        self.height = height
        self.camera.aspect = Float32(width) / Float32(height)

    def handle(mut self, kind: Int, x: Int, y: Int, detail: Int):
        """Take one input event.

        The space bar stops the camera's own turn, and starts it again when
        pressed again. Any other event goes to the orbit controls: a drag with
        the first button turns the camera, the second pans it, and the wheel
        dollies. An event that the controls refuse is dropped.

        Args:
            kind: The event kind, as `window.capi_abi` numbers it.
            x: The pointer's column, in pixels.
            y: The pointer's row, in pixels.
            detail: The key code of a key event, the button of a pointer
                event, or the notches of a wheel event, positive toward the
                user.
        """
        if kind == KEY_DOWN and detail == KEY_SPACE:
            self.controls.auto_rotate = not self.controls.auto_rotate
            return
        var key = NO_KEY
        var button = NO_BUTTON
        var notches = 0
        if kind == KEY_DOWN or kind == KEY_UP:
            key = Key(detail)
        elif kind == WHEEL:
            notches = detail
        else:
            button = PointerButton(detail)
        var event = InputEvent(
            InputKind(kind), key=key, button=button, x=x, y=y, wheel=notches
        )
        try:
            self.controls.handle(event, self.camera, self.height)
        except:
            pass

    def advance(mut self, microseconds: Int):
        """Move the camera on by a time delta.

        The controls apply what the events asked of the camera, with damping,
        and the camera turns by itself unless the space bar stopped it. Time
        that is negative is ignored. A single call counts at most 0.1 s.

        Args:
            microseconds: The time since the last call, in microseconds.
        """
        if microseconds < 0:
            return
        var counted = min(microseconds, LONGEST_MICROSECONDS)
        _ = self.controls.update(
            self.camera, Duration(Float32(counted) / 1000.0, MILLISECOND)
        )

    def draw(mut self) raises:
        """Draw the scan on the CPU into `frame`.

        Raises:
            Error: If the camera or the draw is refused. `frame` is not
                changed then.
        """
        var target = srgb_working_target(self.width, self.height, BACKGROUND)
        if self.loaded:
            draw_gaussian_splat(target, self.scene, self.splat, self.camera)
        self.frame = resolve_srgb_working(target)

    def prepare(mut self) raises -> Int:
        """Make the draw order and the view that a host's GPU draws from.

        The splats are sorted back to front when the view has turned far
        enough since the last sort, as three.js's `updateSort` does, and the
        order is then made again. The view is written every time, with the
        camera that `draw` uses.

        Returns:
            How many times the order has been made. It is 0 while no scan is
            loaded.

        Raises:
            Error: If the camera or the sort is refused. The order and the
                view of the last `prepare` stay.
        """
        if not self.loaded:
            return 0
        var world = self.scene.world_matrix(self.node)
        var view = self.camera.view_matrix_in(self.scene)
        var sorted = self.splat.update_sort(world, view, self.camera.near)
        if sorted:
            self._copy_order()
        var model_view = view * world
        var projection = self.camera.projection_matrix()
        var camera_world = view
        camera_world.invert()
        var local = world
        local.invert()
        var eye = local.transform_point(
            camera_world.transform_point(Vector3(0, 0, 0))
        )
        var at = 0
        while at < 16:
            self.view[VIEW_MODEL_VIEW + at] = model_view.elements[at]
            self.view[VIEW_PROJECTION + at] = projection.elements[at]
            at += 1
        self.view[VIEW_WIDTH] = Float32(self.width)
        self.view[VIEW_HEIGHT] = Float32(self.height)
        self.view[VIEW_EYE] = eye.x
        self.view[VIEW_EYE + 1] = eye.y
        self.view[VIEW_EYE + 2] = eye.z
        self.view[VIEW_DEGREE] = Float32(
            self.splat.splat_geometry.spherical_harmonics_degree()
        )
        self.view[VIEW_COUNT] = Float32(self.splat.count())
        self.view[VIEW_BACKGROUND] = Float32(BACKGROUND.r) / 255
        self.view[VIEW_BACKGROUND + 1] = Float32(BACKGROUND.g) / 255
        self.view[VIEW_BACKGROUND + 2] = Float32(BACKGROUND.b) / 255
        return self.order_generation

    def _copy_order(mut self):
        """Copy the splat object's order into `order` as 32-bit indices, and
        count it."""
        var count = self.splat.count()
        if len(self.order) != count:
            self.order = List[UInt32](length=count, fill=0)
        var at = 0
        while at < count:
            self.order[at] = UInt32(self.splat.order[at])
            at += 1
        self.order_generation += 1

    def info(self, which: SplatInfo) -> Int:
        """Return one number about the scan.

        Args:
            which: A `SPLAT_INFO_*` number from `window.capi_abi`.

        Returns:
            The number. It is 0 for the splat count and the degree while no
            scan is loaded. `which` must be valid.
        """
        if which == SPLAT_INFO_SCAN:
            return self.scan_generation
        if which == SPLAT_INFO_ORDER:
            return self.order_generation
        if not self.loaded:
            return 0
        if which == SPLAT_INFO_COUNT:
            return self.splat.count()
        return self.splat.splat_geometry.spherical_harmonics_degree()

    def part(self, which: SplatPart) -> Tuple[Int, Int]:
        """Return where one array of the scan is in memory.

        Args:
            which: A `SPLAT_*` part from `window.capi_abi`.

        Returns:
            The address of the first byte, and the size in 32-bit words. The
            address and the size are both 0 while no scan is loaded, for a
            band that the scan does not have, and for the order before the
            first `prepare`. `which` must be valid.
        """
        if not self.loaded:
            return (0, 0)
        ref geometry = self.splat.splat_geometry
        if which == SPLAT_CENTERS:
            return _words(geometry.centers)
        if which == SPLAT_COVARIANCES:
            return _words(geometry.covariances)
        if which == SPLAT_COLORS:
            return _band(geometry.colors)
        if which == SPLAT_SH1:
            return _band(geometry.sh1)
        if which == SPLAT_SH2:
            return _band(geometry.sh2)
        if which == SPLAT_SH3:
            return _band(geometry.sh3)
        if which == SPLAT_ORDER:
            return _order(self.order)
        return _words(self.view)
