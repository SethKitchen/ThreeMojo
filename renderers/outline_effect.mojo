# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An ink outline around every mesh: three.js's `OutlineEffect` from
`examples/jsm/effects/`.

`OutlineEffect` draws the scene, and then draws each mesh again with an
outline material. The outline material draws only the back faces, with
each vertex pushed out along its normal, in one flat color. The pushed
back faces show as a rim around the mesh, and the mesh hides the rest of
them.

**The shader.** The outline material is three.js's own GLSL, compiled by
`materials.glsl.compile_shader_material`. Its vertex shader moves each
vertex in clip space by the thickness times the clip w, along the
direction of the normal on the screen. So the rim is the same width in
the image whatever the mesh's distance. This port's GLSL knows the
built-in matrices only as the steps to `gl_Position`, so the shader reads
the model-view-projection matrix and its inverse from two uniforms, one
pair for each mesh.

**One draw.** three.js draws the scene, and then the outlines over it
without a clear. This port adds the outline meshes to the scene's mesh
list and draws the scene once. The depth test gives the same result for
opaque surfaces. The outline materials and meshes are taken out again
before `render` returns.

**What is outlined.** Each mesh in `Scene.meshes` whose geometry has
normals and whose material's parameters are visible. three.js reads the
parameters from a material's `userData.outlineParameters`. This port
reads them from `OutlineEffect.set_parameters`. Instanced, batched and
skinned meshes, lines, points and sprites are not outlined. A mesh whose
world matrix cannot be inverted is not outlined either.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from materials.glsl import compile_shader_material
from materials.material import BACK_SIDE, MaterialId, shader_material
from materials.nodes import NodeProgram
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.collections import Dict
from std.math import isfinite

# three.js's `defaultThickness`, in clip units per unit of clip w.
comptime OUTLINE_THICKNESS = Float32(0.003)

# The outline's vertex shader: three.js's `calculateOutline`, with the
# model-view-projection matrix and its inverse as uniforms. The normal is
# read the other way, as three.js flips it on a back-side material.
comptime OUTLINE_VERTEX_SHADER = """
uniform mat4 outlineMatrix;
uniform mat4 outlineInverse;
uniform float outlineThickness;
void main() {
    vec4 pos = outlineMatrix * vec4(position, 1.0);
    vec4 pos2 = outlineMatrix * vec4(position - normal, 1.0);
    vec4 norm = normalize(pos - pos2);
    vec4 moved = pos + norm * outlineThickness * pos.w;
    vec4 back = outlineInverse * moved;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(back.xyz / back.w, 1.0);
}
"""

# The outline's fragment shader: three.js's, one flat color.
comptime OUTLINE_FRAGMENT_SHADER = """
uniform vec3 outlineColor;
uniform float outlineAlpha;
void main() {
    gl_FragColor = vec4(outlineColor, outlineAlpha);
}
"""


struct OutlineParameters(ImplicitlyCopyable):
    """How one material's meshes are outlined: three.js's
    `userData.outlineParameters`."""

    # `thickness`: how far the rim reaches, in clip units per unit of
    # clip w.
    var thickness: Float32
    # `color`: the rim's color, in sRGB.
    var color: Color
    # `alpha`: the rim's opacity. Below one the rim blends.
    var alpha: Float32
    # `visible`: whether the rim is drawn.
    var visible: Bool

    def __init__(
        out self,
        thickness: Float32 = OUTLINE_THICKNESS,
        color: Color = Color(0, 0, 0),
        alpha: Float32 = 1.0,
        visible: Bool = True,
    ):
        """Start with three.js's defaults: a thin, opaque black rim.

        Args:
            thickness: How far the rim reaches.
            color: The rim's color, in sRGB.
            alpha: The rim's opacity.
            visible: Whether the rim is drawn.
        """
        self.thickness = thickness
        self.color = color
        self.alpha = alpha
        self.visible = visible


def check_outline_parameters(parameters: OutlineParameters) raises:
    """Refuse outline parameters no material could draw.

    Args:
        parameters: The parameters.

    Raises:
        Error: If the thickness or the alpha is not finite, the thickness
            is negative, or the alpha is outside zero to one.
    """
    if not (isfinite(parameters.thickness) and isfinite(parameters.alpha)):
        raise Error("An outline's thickness and alpha must be finite")
    if parameters.thickness < 0:
        raise Error("An outline's thickness must not be negative")
    if parameters.alpha < 0 or parameters.alpha > 1:
        raise Error("An outline's alpha runs from zero to one")


struct OutlineEffect(Movable):
    """The scene with an ink outline around every mesh: three.js's
    `OutlineEffect`."""

    # `enabled`: whether `render` draws the outlines at all.
    var enabled: Bool
    # The parameters of a material that has none of its own:
    # `defaultThickness`, `defaultColor`, `defaultAlpha`.
    var defaults: OutlineParameters
    # Each material's own parameters, by its id.
    var _parameters: Dict[Int, OutlineParameters]
    # The outline shaders, compiled once.
    var _program: NodeProgram

    def __init__(
        out self,
        thickness: Float32 = OUTLINE_THICKNESS,
        color: Color = Color(0, 0, 0),
        alpha: Float32 = 1.0,
    ) raises:
        """Take three.js's constructor parameters: the defaults.

        Args:
            thickness: `defaultThickness`.
            color: `defaultColor`, in sRGB.
            alpha: `defaultAlpha`.

        Raises:
            Error: Everything `check_outline_parameters` raises.
        """
        self.enabled = True
        self.defaults = OutlineParameters(thickness, color, alpha)
        check_outline_parameters(self.defaults)
        self._parameters = Dict[Int, OutlineParameters]()
        self._program = compile_shader_material(
            OUTLINE_VERTEX_SHADER, OUTLINE_FRAGMENT_SHADER
        )

    def set_parameters(
        mut self, material: MaterialId, parameters: OutlineParameters
    ) raises:
        """Give a material's meshes their own outline: three.js's
        `material.userData.outlineParameters`.

        Args:
            material: The material.
            parameters: Its outline.

        Raises:
            Error: If the material id is negative, and everything
                `check_outline_parameters` raises.
        """
        if material.value < 0:
            raise Error("Outline parameters must name a material")
        check_outline_parameters(parameters)
        self._parameters[material.value] = parameters

    def parameters(self, material: MaterialId) -> OutlineParameters:
        """Return the outline a material's meshes get.

        Args:
            material: The material.

        Returns:
            Its own parameters, or the defaults.
        """
        return self._parameters.get(material.value, self.defaults)

    def _add_outlines[
        C: Camera
    ](self, mut scene: Scene, mut assets: Assets, camera: C) raises:
        """Add an outline mesh, its program and its material for each mesh
        that is outlined."""
        var projection_view = camera.projection_matrix()
        projection_view.multiply(camera.view_matrix_in(scene))
        var count = len(scene.meshes)
        for index in range(count):  # pragma: no branch
            var mesh = scene.meshes[index]
            var parameters = self.parameters(mesh.material)
            var material = assets.materials.get(mesh.material)
            ref geometry = assets.geometries.get(mesh.geometry)
            var shown = parameters.visible and geometry.has_attribute("normal")
            var matrix = projection_view.copy()
            matrix.multiply(scene.world_matrix(mesh.node))
            if not shown or matrix.determinant() == 0:
                continue
            var inverse = matrix.copy()
            inverse.invert()
            var program = self._program.copy()
            program.set_uniform("outlineMatrix", matrix)
            program.set_uniform("outlineInverse", inverse)
            program.set_uniform("outlineThickness", parameters.thickness)
            program.set_uniform("outlineColor", parameters.color)
            program.set_uniform("outlineAlpha", parameters.alpha)
            var outline = shader_material(
                assets.programs.add(program^),
                side=BACK_SIDE,
                transparent=parameters.alpha < 1 or material.transparent,
            )
            outline.fog = material.fog
            mesh.material = assets.materials.add(outline)
            mesh.cast_shadow = False
            mesh.receive_shadow = False
            scene.meshes.append(mesh)

    def render[
        C: Camera
    ](
        self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
    ) raises -> Framebuffer:
        """Draw the scene with its outlines: three.js's `render`.

        The outline meshes, their programs and their materials are added
        to the scene and the assets, the scene is drawn, and they are
        taken out again, whether the draw succeeds or raises.

        Args:
            renderer: What the scene is drawn with.
            scene: The scene. It must be current; see `Scene.update`.
            assets: The geometry, materials and textures it names.
            camera: The camera.

        Returns:
            The image.

        Raises:
            Error: If a mesh names a material or a geometry that is not in
                the assets, and everything `Scene.world_matrix` and
                `Renderer.render` raise.
        """
        if not self.enabled:
            return renderer.render(scene, assets, camera)
        var meshes = len(scene.meshes)
        var materials = assets.materials.count()
        var programs = assets.programs.count()
        try:
            self._add_outlines(scene, assets, camera)
            return renderer.render(scene, assets, camera)
        finally:
            while len(scene.meshes) > meshes:
                _ = scene.meshes.pop()
            while assets.materials.count() > materials:
                _ = assets.materials.materials.pop()
            while assets.programs.count() > programs:
                _ = assets.programs.programs.pop()
