# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The meadow drawn by the GPU rasterizer.

`Meadow.update` culls the grass clusters and grows the drawn ones on the
CPU. `Renderer.render` then draws the frame on the CPU too. `MeadowDevice`
draws that same prepared frame on a GPU instead: the same clusters,
crowns, ground and mountains, with the same sun cascades, sky, fog and
tone curve. The culling and the growing stay on the CPU.

This module needs MAX, as `render/gpu.mojo` does. The kernel is the
shared rasterizer, so the picture is the CPU's within the parity
tolerance. An antialiased frame is the one difference. The device draws
`SUPERSAMPLE` times the size each way and averages the encoded bytes,
because `GpuRenderer` gives back a resolved image. The CPU averages the
linear light before the tone curve. See `render.antialias`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.fog import FogView
from core.scene import Scene
from lights.lighting import Lighting
from render.antialias import SUPERSAMPLE, downsample
from render.framebuffer import Framebuffer
from render.gpu import GpuRenderer
from render.rasterizer import SHADE_TEXTURE
from renderers.renderer import (
    Renderer,
    camera_back,
    camera_position,
    camera_up,
    toward_camera,
)


def device_size(renderer: Renderer) -> Tuple[Int, Int]:
    """Return the size of the device target a renderer's frames need.

    Args:
        renderer: The meadow's renderer.

    Returns:
        The width and the height in pixels: the renderer's own, times
        `SUPERSAMPLE` each way when it antialiases.
    """
    if renderer.antialias:
        return (renderer.width * SUPERSAMPLE, renderer.height * SUPERSAMPLE)
    return (renderer.width, renderer.height)


struct MeadowDevice(Movable):
    """A GPU target that draws a meadow's frames.

    It keeps its device context and buffers between frames, as
    `GpuRenderer` does, so a frame costs an upload, a launch and a read
    back. Make one for a renderer, call `upload` once the meadow is
    built, and call `draw` after each `Meadow.update`.
    """

    var device: GpuRenderer
    # Whether `upload` has sent the textures.
    var uploaded: Bool

    def __init__(out self, renderer: Renderer) raises:
        """Open a device target for a renderer's frames.

        Args:
            renderer: The meadow's renderer. Its size and its antialias
                setting give the target's size.

        Raises:
            Error: If no GPU is present, or the size is not valid.
        """
        var size = device_size(renderer)
        self.device = GpuRenderer(size[0], size[1])
        self.uploaded = False

    def upload(mut self, assets: Assets) raises:
        """Send every texture the meadow samples to the device.

        Call it once after the meadow is built, and again only when a
        texture changes. A frame replaces cluster geometry, and that
        needs no upload here.

        Args:
            assets: The stores the meadow was built into.

        Raises:
            Error: If a texture cannot be sent.
        """
        self.device.set_textures(
            assets.textures,
            assets.cube_textures,
            assets.data_3d_textures,
            assets.data_array_textures,
        )
        self.uploaded = True

    def draw(
        mut self,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        """Draw one frame of the meadow on the device.

        Args:
            renderer: The renderer this device was made for.
            scene: The meadow's scene, after `Meadow.update`.
            assets: The stores.
            camera: The camera of the frame.

        Returns:
            The frame, at the renderer's size.

        Raises:
            Error: If `upload` has not been called, the renderer is not
                the size this device was made for, or the device refuses
                the frame.
        """
        if not self.uploaded:
            raise Error("Call upload() before the first meadow frame")
        var size = device_size(renderer)
        if size[0] != self.device.width or size[1] != self.device.height:
            raise Error("A meadow device draws one renderer size")
        if renderer.antialias:
            var big = renderer.supersampled()
            return downsample(
                self._frame(big, scene, assets, camera), SUPERSAMPLE
            )
        return self._frame(renderer, scene, assets, camera)

    def _frame(
        mut self,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        # What `Renderer.render` hands the host rasterizer, handed to the
        # kernel: the prepared frame, the lights with their shadow maps,
        # the fog, the backdrop and the tone curve.
        var frame = renderer.prepare_frame(scene, assets, camera)
        var lighting = Lighting(
            scene,
            camera.visible_layers(),
            camera_position(scene, camera),
            toward_camera(scene, camera),
            camera_up(scene, camera),
            back=camera_back(scene, camera),
            shadows=renderer.shadow_maps(scene, assets),
            spot_maps=renderer.spot_light_maps(scene, assets),
        )
        var fog = FogView(scene.fog)
        fog.validate()
        self.device.draw(
            frame.whole_corners(),
            renderer.clear_color(scene),
            SHADE_TEXTURE,
            lighting,
            fog,
            renderer.tone_mapping,
            renderer.tone_mapping_exposure,
            lines=frame.segments,
            draws=frame.draws,
            points=frame.points,
            backdrop=renderer.backdrop(scene, assets, camera),
            line_width=renderer.render_scale,
            depth_mode=renderer.depth_mode_for(camera),
            programs=frame.programs,
            custom_tone_mapping=renderer.custom_tone_mapping,
            output_color_space=renderer.output_color_space,
        )
        return self.device.read_back()
