# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a GPU draws after the village's triangles.

On the CPU, `VillageGame` follows the raster with five passes: the pond's
water, the weather's clouds and fog, the night's darkness and stars, the
smoothing of edges, and the rain. A host with a GPU can do the first four
and leave the rain and the heads-up display to the CPU. `GpuPost` makes
the numbers that those four need, and describes them to the host in the
arrays of `renderers.game_gpu`.

The order on the GPU is not the CPU's, and the frame is the same. The
weather and the night change only the pixels that show the sky, and the
water replaces whole pixels. So the host can draw the weather and the night
with the sky, before the triangles, and compose the water over the finished
triangles. The smoothing comes last, as it does on the CPU.

The numbers are those of the CPU passes: `Weather.cover_look`,
`Weather.cloud_grid`, `DayCycle.night_look` and `ComposeUpload`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from extensions.village.day import (
    DUSK_ORANGE,
    NIGHT_SKY,
    NIGHT_WATER,
    STARS,
    STAR_GRID,
    DayCycle,
    NightLook,
)
from extensions.village.village import Village
from extensions.village.weather import (
    CLOUD_STEP,
    CloudGrid,
    CoverLook,
    Weather,
)
from extensions.water.frame import _ComposePlan, _compose_plan
from extensions.water.upload import COMPOSE_WORDS, ComposeUpload, grid_samples
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from renderers.game_gpu import (
    FLOAT_COVER_BRIGHT,
    FLOAT_COVER_FOG,
    FLOAT_COVER_GLOOM,
    FLOAT_COVER_GRAY,
    FLOAT_COVER_MIST,
    FLOAT_COVER_VEIL,
    FLOAT_NIGHT_ACROSS,
    FLOAT_NIGHT_D00,
    FLOAT_NIGHT_DAY,
    FLOAT_NIGHT_DOWN,
    FLOAT_NIGHT_DUSK,
    FLOAT_NIGHT_GLOW,
    FLOAT_NIGHT_MOON,
    FLOAT_NIGHT_MOONLIT,
    FLOAT_NIGHT_SKY,
    FLOAT_NIGHT_STAR_GRID,
    FLOAT_NIGHT_STAR_RATE,
    FLOAT_NIGHT_STARS,
    FLOAT_WATER_CLIP,
    FLOAT_WATER_EYE,
    FLOAT_WATER_NIGHT,
    FLOAT_WATER_SHARE,
    GpuFrame,
    INT_COVER_COLUMNS,
    INT_COVER_ROWS,
    INT_COVER_STEP,
    INT_DEPTH,
    INT_NIGHT_ON,
    INT_PASSES,
    INT_SMOOTH_ON,
    INT_WATER_BED_MADE,
    INT_WATER_CAUSTIC_FLOATS,
    INT_WATER_GRID_HEIGHT,
    INT_WATER_GRID_WIDTH,
    INT_WATER_ON,
    INT_WATER_PEBBLE_FLOATS,
    INT_WATER_RIPPLE_FLOATS,
    INT_WATER_RIPPLE_MADE,
    INT_WATER_STEP,
    INT_WATER_SURFACE_FLOATS,
    INT_WATER_SURFACE_MADE,
    INT_WATER_WORDS,
    POINTER_COVER,
    POINTER_WATER_CAUSTIC,
    POINTER_WATER_PEBBLE,
    POINTER_WATER_RIPPLE,
    POINTER_WATER_SURFACE,
    POINTER_WATER_WORDS,
    address,
)


def _count(mut frame: GpuFrame, at: Int, value: Int):
    """Write a count into an integer of a frame."""
    frame.ints[at] = Int64(value)


def _put(mut frame: GpuFrame, at: Int, value: Vector3):
    """Write a vector into three floats of a frame."""
    frame.floats[at] = value.x
    frame.floats[at + 1] = value.y
    frame.floats[at + 2] = value.z


struct GpuPost(Movable):
    """The numbers that a GPU draws the weather, the night, the water and
    the smoothing of edges from, for one frame.
    """

    var on: Bool
    """True while a prepared frame leaves these passes to a GPU."""
    var smooth: Bool
    """Whether the GPU smooths the frame's edges."""
    var cover: CloudGrid
    """The clouds on a grid over the frame."""
    var cover_look: CoverLook
    """What the weather mixes a sky pixel with."""
    var night: NightLook
    """What the hour mixes a sky pixel with."""
    var water: Bool
    """Whether the GPU composes the pond's water into the frame."""
    var share: Float32
    """How much of its own light the water keeps."""
    var step: Int
    """The pixels between two shaded samples of the water."""
    var plan: Optional[_ComposePlan]
    """The camera as the water sees it, when `water` is set."""
    var upload: ComposeUpload
    """The water's tables, kept from frame to frame."""

    def __init__(out self):
        """Make a post that is not prepared: the CPU does every pass."""
        self.on = False
        self.smooth = False
        self.cover = CloudGrid(0, 0, List[Float32]())
        self.cover_look = CoverLook(
            Vector3(0, 0, 0), Vector3(0, 0, 0), 0, 0, 1, 0
        )
        var none = Vector3(0, 0, 0)
        self.night = NightLook(
            False, 1, 0, 0, none, none, none, Vector3(0, 1, 0), 0
        )
        self.water = False
        self.share = 1
        self.step = 0
        self.plan = None
        self.upload = ComposeUpload()

    def prepare(
        mut self,
        mut village: Village,
        weather: Weather,
        day: DayCycle,
        camera: PerspectiveCamera,
        scene: Scene,
        image: Framebuffer,
        smooth: Bool,
    ) raises:
        """Make the numbers of one frame, and take its four passes.

        Args:
            village: The village. The pond's water finds its surface here.
            weather: The weather.
            day: The hour of the day.
            camera: The camera that draws the frame.
            scene: The scene, with current world matrices.
            image: The frame's image: only its size is read.
            smooth: Whether the quality smooths the frame's edges.

        Raises:
            Error: If the camera's matrices are invalid, the camera is not
                above the pond's water, or the water's shade step is not
                from 2 to 64. A post that fails is not taken: `on` keeps
                its value.
        """
        var cover = weather.cloud_grid(camera, image.width, image.height)
        var night = day.night_look(camera, 1 - weather.look.clouds)
        var seen = village.pond_seen(camera)
        var plan = Optional[_ComposePlan](None)
        if seen:
            var made = _compose_plan(
                image,
                camera.projection_matrix(),
                camera.view_matrix_in(scene),
                village.level,
            )
            self.upload.refresh(
                village.water, made, village.bed, image.width, image.height
            )
            plan = made
        self.cover = cover^
        self.cover_look = weather.cover_look()
        self.night = night
        self.water = seen
        self.share = day.water_light()
        self.step = village.water.shade_step
        self.plan = plan
        self.smooth = smooth
        self.on = True

    def describe(self, mut frame: GpuFrame, width: Int, height: Int):
        """Write what a host needs of this frame into its arrays.

        Args:
            frame: The arrays. Each entry that the passes use is set.
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
        """
        _count(frame, INT_PASSES, 1)
        # The GPU does every pass that reads the depth.
        _count(frame, INT_DEPTH, 0)
        _count(frame, INT_COVER_COLUMNS, self.cover.columns)
        _count(frame, INT_COVER_ROWS, self.cover.rows)
        _count(frame, INT_COVER_STEP, CLOUD_STEP)
        frame.pointers[POINTER_COVER] = address(self.cover.cover.unsafe_ptr())
        _put(frame, FLOAT_COVER_GRAY, self.cover_look.gray)
        _put(frame, FLOAT_COVER_FOG, self.cover_look.fog)
        frame.floats[FLOAT_COVER_VEIL] = self.cover_look.veil
        frame.floats[FLOAT_COVER_MIST] = self.cover_look.mist
        frame.floats[FLOAT_COVER_BRIGHT] = self.cover_look.bright
        frame.floats[FLOAT_COVER_GLOOM] = self.cover_look.gloom
        _count(frame, INT_NIGHT_ON, 1 if self.night.on else 0)
        frame.floats[FLOAT_NIGHT_DAY] = self.night.day
        frame.floats[FLOAT_NIGHT_DUSK] = self.night.dusk
        frame.floats[FLOAT_NIGHT_STARS] = self.night.stars
        _put(frame, FLOAT_NIGHT_D00, self.night.d00)
        _put(frame, FLOAT_NIGHT_ACROSS, self.night.across)
        _put(frame, FLOAT_NIGHT_DOWN, self.night.down)
        _put(frame, FLOAT_NIGHT_GLOW, DUSK_ORANGE * 1.15)
        _put(frame, FLOAT_NIGHT_SKY, NIGHT_SKY)
        frame.floats[FLOAT_NIGHT_STAR_GRID] = STAR_GRID
        frame.floats[FLOAT_NIGHT_STAR_RATE] = STARS
        _put(frame, FLOAT_NIGHT_MOON, self.night.moon)
        frame.floats[FLOAT_NIGHT_MOONLIT] = self.night.moonlit
        _count(frame, INT_SMOOTH_ON, 1 if self.smooth else 0)
        _count(frame, INT_WATER_ON, 1 if self.water else 0)
        if not self.water:
            return
        ref plan = self.plan.value()
        _count(frame, INT_WATER_STEP, self.step)
        _count(frame, INT_WATER_GRID_WIDTH, grid_samples(width, self.step))
        _count(frame, INT_WATER_GRID_HEIGHT, grid_samples(height, self.step))
        _count(frame, INT_WATER_SURFACE_MADE, self.upload.surface_made)
        _count(frame, INT_WATER_RIPPLE_MADE, self.upload.ripple_made)
        _count(frame, INT_WATER_BED_MADE, self.upload.bed_made)
        _count(frame, INT_WATER_SURFACE_FLOATS, len(self.upload.surface))
        _count(frame, INT_WATER_RIPPLE_FLOATS, len(self.upload.ripple))
        _count(frame, INT_WATER_CAUSTIC_FLOATS, len(self.upload.caustic))
        _count(frame, INT_WATER_PEBBLE_FLOATS, len(self.upload.pebble))
        _count(frame, INT_WATER_WORDS, COMPOSE_WORDS)
        frame.pointers[POINTER_WATER_SURFACE] = address(
            self.upload.surface.unsafe_ptr()
        )
        frame.pointers[POINTER_WATER_RIPPLE] = address(
            self.upload.ripple.unsafe_ptr()
        )
        frame.pointers[POINTER_WATER_CAUSTIC] = address(
            self.upload.caustic.unsafe_ptr()
        )
        frame.pointers[POINTER_WATER_PEBBLE] = address(
            self.upload.pebble.unsafe_ptr()
        )
        frame.pointers[POINTER_WATER_WORDS] = address(
            self.upload.words.unsafe_ptr()
        )
        _put(frame, FLOAT_WATER_EYE, plan.eye)
        for k in range(16):  # pragma: no branch
            frame.floats[FLOAT_WATER_CLIP + k] = plan.clip.elements[k]
        frame.floats[FLOAT_WATER_SHARE] = self.share
        _put(frame, FLOAT_WATER_NIGHT, NIGHT_WATER)
