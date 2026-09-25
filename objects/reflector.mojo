# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mirror and a pane of glass, from three.js
`examples/jsm/objects/Reflector.js` and `Refractor.js`.

Both are a mesh that shows the scene as a second camera sees it. Each
frame, before the main render, the object renders the scene again into a
render target of its own, from a *virtual camera*, and cuts away what lies
on the wrong side of its surface. Its shader then reads that target
projectively: `textureMatrix` takes a world position to where the virtual
camera saw it, so each pixel of the surface shows what lies along its own
line of sight.

- `Reflector` mirrors the camera through the surface's plane. The virtual
  camera stands behind the mirror and looks out through it.
- `Refractor` keeps the camera where it is. It cuts away what is in front
  of the surface, so the target holds what lies behind the glass.

**The update is a call, not a hook.** three.js renders the target in the
mesh's `onBeforeRender`. A hook here observes a frame and cannot change it
(see `renderers.renderer.RenderHooks`), so the caller calls `update` before
each frame instead. `update` takes the scene mutably, because it hides the
object's node while it renders the target, as three.js sets `visible`
false.

**The cut is a clipping plane.** three.js replaces the third row of the
virtual camera's projection with the surface's plane, Lengyel's oblique
near plane. This port's clipper cuts at the camera's near distance and not
at the projection's near plane, so the same row would leave the depth of
the cut geometry below zero. The virtual render instead adds the surface's
plane to the renderer's clipping planes. The pixels of the target are the
same, and the depth keeps its full range. `clip_bias` moves the plane that
many meters past the surface; three.js adds its bias to the oblique row.

**The texture matrix acts on world positions.** three.js multiplies it by
the mesh's world matrix and applies it to the local position. The GLSL
subset refuses a varying that reads `position`, so the uniform stops at
world space and the vertex shader multiplies it by the world position.
`texture_matrix` keeps three.js's value, with the world matrix.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NodeId
from core.scene import Scene
from materials.glsl import compile_shader_material
from materials.material import MaterialId, shader_material
from materials.nodes import NodeProgramId
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.projection import look_at, viewport
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.target import (
    HALF_FLOAT_TARGET,
    RenderTarget,
    TargetType,
    check_samples,
)
from render.texture import Texture
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import isfinite
from units.si import Length, METER

# three.js's `textureWidth` and `textureHeight` default, in pixels.
comptime DEFAULT_TEXTURE_SIZE = 512
# The samples each pixel of the target takes, three.js's `multisample`
# option of `Reflector` and `Refractor`: four by default, zero for none.
comptime DEFAULT_MULTISAMPLE = 4
# three.js's `clipBias` default: the plane lies on the surface.
comptime NO_CLIP_BIAS = Length(0.0, METER)
# three.js's `color` default for both objects, `0x7F7F7F`.
comptime DEFAULT_MIRROR_COLOR = Color(0x7F, 0x7F, 0x7F)
# The near and far distances of three.js's `new PerspectiveCamera()`, what
# the virtual camera holds before the first update.
comptime _DEFAULT_NEAR = Float32(0.1)
comptime _DEFAULT_FAR = Float32(2000)

# `Reflector.ReflectorShader`. The vertex shader multiplies the texture
# matrix by the world position; see the module docstring. The fragment
# shader reads `texture2DProj` as the division it is, and the overlay of a
# `vec3` has its own name, because the subset has no overloads.
comptime REFLECTOR_VERTEX = """
uniform mat4 textureMatrix;
varying vec4 vUv;

void main() {
    vUv = textureMatrix * ( modelMatrix * vec4( position, 1.0 ) );
    gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
}
"""

comptime REFLECTOR_FRAGMENT = """
uniform vec3 color;
uniform sampler2D tDiffuse;
varying vec4 vUv;

float blendOverlay( float base, float blend ) {
    return( base < 0.5 ? ( 2.0 * base * blend ) : ( 1.0 - 2.0 * ( 1.0 - base ) * ( 1.0 - blend ) ) );
}

vec3 blendOverlay3( vec3 base, vec3 blend ) {
    return vec3( blendOverlay( base.r, blend.r ), blendOverlay( base.g, blend.g ), blendOverlay( base.b, blend.b ) );
}

void main() {
    vec4 base = texture2D( tDiffuse, vUv.xy / vUv.w );
    gl_FragColor = vec4( blendOverlay3( base.rgb, color ), 1.0 );
}
"""

# `Refractor.RefractorShader`: the same two shaders.
comptime REFRACTOR_VERTEX = REFLECTOR_VERTEX
comptime REFRACTOR_FRAGMENT = REFLECTOR_FRAGMENT


struct VirtualCamera(Camera, ImplicitlyCopyable):
    """A camera given by its two matrices: what a reflector, a refractor
    and a water render their target through.

    three.js keeps a `PerspectiveCamera` and writes its `matrixWorld` and
    `projectionMatrix` by hand. A camera here is a trait, so the matrices
    are the camera.
    """

    # The world-to-camera matrix.
    var view: Matrix4
    # The camera-to-clip matrix, copied from the camera the view follows.
    var projection: Matrix4
    # The near and far clipping distances, in meters.
    var near: Float32
    var far: Float32
    # The layers it draws, the main camera's.
    var layers: Layers

    def __init__(
        out self,
        view: Matrix4,
        projection: Matrix4,
        near: Float32,
        far: Float32,
        layers: Layers,
    ):
        """Create a camera from its matrices.

        Args:
            view: The world-to-camera matrix.
            projection: The camera-to-clip matrix.
            near: The near clipping distance, in meters.
            far: The far clipping distance, in meters.
            layers: The layers the camera draws.
        """
        self.view = view
        self.projection = projection
        self.near = near
        self.far = far
        self.layers = layers

    def view_matrix(self) raises -> Matrix4:
        """Return the world-to-camera matrix.

        Returns:
            The view matrix.
        """
        return self.view

    def view_matrix_in(self, scene: Scene) raises -> Matrix4:
        """Return the world-to-camera matrix, which no scene changes.

        Args:
            scene: The scene, not read.

        Returns:
            The view matrix.
        """
        return self.view

    def projection_matrix(self) raises -> Matrix4:
        """Return the camera-to-clip matrix.

        Returns:
            The projection matrix.
        """
        return self.projection

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the transform from camera space to pixels.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Returns:
            The product viewport * projection.

        Raises:
            Error: If either dimension is not positive.
        """
        var combined = viewport(width, height)
        combined.multiply(self.projection)
        return combined^

    def near_distance(self) -> Float32:
        """Return the near clipping distance, in meters."""
        return self.near

    def far_distance(self) -> Float32:
        """Return the far clipping distance, in meters."""
        return self.far

    def visible_layers(self) -> Layers:
        """Return which layers the camera draws."""
        return self.layers


def default_virtual_camera() -> VirtualCamera:
    """Return the virtual camera an object holds before its first update:
    identity matrices, and three.js's default near and far distances.

    Returns:
        The camera.
    """
    return VirtualCamera(
        Matrix4(), Matrix4(), _DEFAULT_NEAR, _DEFAULT_FAR, Layers()
    )


def follow_camera[C: Camera](camera: C, view: Matrix4) raises -> VirtualCamera:
    """Return a virtual camera that looks through `view` with `camera`'s
    projection, distances and layers.

    Args:
        camera: The camera to copy the projection of.
        view: The world-to-camera matrix of the virtual camera.

    Returns:
        The virtual camera.

    Raises:
        Error: If the camera's projection raises.
    """
    return VirtualCamera(
        view,
        camera.projection_matrix(),
        camera.near_distance(),
        camera.far_distance(),
        camera.visible_layers(),
    )


def camera_world[C: Camera](camera: C, scene: Scene) raises -> Matrix4:
    """Return a camera's world matrix, three.js's `camera.matrixWorld`.

    Args:
        camera: The camera.
        scene: The scene, updated, whose node the camera can ride.

    Returns:
        The inverse of the camera's view matrix.

    Raises:
        Error: If the camera's view raises.
    """
    var world = camera.view_matrix_in(scene)
    world.invert()
    return world^


def texture_bias() -> Matrix4:
    """Return the matrix that maps clip space onto texture space, from
    minus one to one onto zero to one, three.js's first factor of
    `textureMatrix`.

    Returns:
        The bias matrix.
    """
    var bias = Matrix4()
    bias.set(
        0.5,
        0.0,
        0.0,
        0.5,
        0.0,
        0.5,
        0.0,
        0.5,
        0.0,
        0.0,
        0.5,
        0.5,
        0.0,
        0.0,
        0.0,
        1.0,
    )
    return bias^


def projective_matrix(camera: VirtualCamera) -> Matrix4:
    """Return the texture matrix of a world position: the bias, times the
    camera's projection, times its view.

    Args:
        camera: The camera the target was rendered through.

    Returns:
        The matrix, before any model matrix.
    """
    var matrix = texture_bias()
    matrix.multiply(camera.projection)
    matrix.multiply(camera.view)
    return matrix^


@fieldwise_init
struct MirrorView(ImplicitlyCopyable):
    """Where a mirror's virtual camera stands, from three.js's
    `Reflector.onBeforeRender`."""

    # Whether the camera is behind the mirror: three.js's `isFacingAway`.
    var facing_away: Bool
    # The mirror's world normal, its turned +z.
    var normal: Vector3
    # The mirror's world position.
    var point: Vector3
    # The virtual camera's world-to-camera matrix.
    var view: Matrix4


def mirror_view(surface: Matrix4, eye_world: Matrix4) raises -> MirrorView:
    """Return the camera mirrored through a surface's plane.

    three.js reflects the camera's position and the point one meter ahead
    of it through the plane, and reflects its up. The virtual camera looks
    from the first at the second.

    Args:
        surface: The mirror's world matrix. Its +z is the normal.
        eye_world: The camera's world matrix.

    Returns:
        The mirrored view.

    Raises:
        Error: If either matrix has no extent along an axis, and so no
            rotation.
    """
    var point = Vector3.from_matrix_position(surface)
    var eye = Vector3.from_matrix_position(eye_world)
    var normal = surface.extract_rotation().transform_direction(
        Vector3(0, 0, 1)
    )
    var toward = point - eye
    var facing_away = toward.dot(normal) > 0
    toward.reflect(normal)
    toward.negate()
    toward.add(point)
    var turn = eye_world.extract_rotation()
    var ahead = turn.transform_direction(Vector3(0, 0, -1)) + eye
    var target = point - ahead
    target.reflect(normal)
    target.negate()
    target.add(point)
    var up = turn.transform_direction(Vector3(0, 1, 0))
    up.reflect(normal)
    return MirrorView(facing_away, normal, point, look_at(toward, target, up))


def view_renderer(
    renderer: Renderer, width: Int, height: Int
) raises -> Renderer:
    """Return a renderer of a target's size that draws as `renderer` does.

    three.js renders a target with the renderer the scene is drawn with,
    and the target's own viewport. A renderer here draws one size, so the
    object draws with a copy: the background, the shading, the workers,
    the clipping planes, the shadow filter, the depth mode, the time and
    the area light tables. It has no tone mapping, as three.js tone maps
    no render target.

    Args:
        renderer: The renderer the scene is drawn with.
        width: The target's width in pixels.
        height: The target's height in pixels.

    Returns:
        The renderer.

    Raises:
        Error: If a size is not positive.
    """
    var view = Renderer(width, height, renderer.workers)
    view.background = renderer.background
    view.shading = renderer.shading
    view.clipping_planes = renderer.clipping_planes.copy()
    view.local_clipping_enabled = renderer.local_clipping_enabled
    view.shadow_map_type = renderer.shadow_map_type
    view.depth_mode = renderer.depth_mode
    view.time = renderer.time
    view.set_ltc_tables(renderer.ltc_tables())
    return view^


def _show(mut scene: Scene, node: NodeId, visible: Bool) raises:
    """Set a node's `visible` and update the scene."""
    var held = scene.get(node)
    held.visible = visible
    scene.set(node, held^)
    scene.update()


def render_view(
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    hidden: NodeId,
    camera: VirtualCamera,
    cut: Plane,
    width: Int,
    height: Int,
    type: TargetType,
    samples: Int = 0,
) raises -> Texture:
    """Render the scene through a virtual camera, with a node hidden and a
    plane cut, and return the target as a texture.

    Args:
        renderer: The renderer the scene is drawn with; see
            `view_renderer`.
        scene: The scene, updated. The node is hidden while the target is
            drawn and shown as it was afterward, even if the render raises.
        assets: The stores the scene names.
        hidden: The node of the object that renders the view.
        camera: The virtual camera.
        cut: The plane that cuts away what lies behind it, in world space.
        width: The target's width in pixels.
        height: The target's height in pixels.
        type: What the target stores.
        samples: How many samples each pixel of the target takes, three.js's
            `samples`. Zero, the default, takes one.

    Returns:
        The target's color as a float texture, clamped, bilinear, without
        a chain.

    Raises:
        Error: If the node is not in the scene, or the render raises.
    """
    var view = view_renderer(renderer, width, height)
    view.clipping_planes.append(cut)
    var target = RenderTarget(
        width, height, renderer.background, type, samples=samples
    )
    var was = scene.get(hidden).visible
    _show(scene, hidden, False)
    try:
        view.render_into(target, scene, assets, camera)
    finally:
        _show(scene, hidden, was)
    return target.attachment_texture(0)


def blank_texture(width: Int, height: Int, type: TargetType) raises -> Texture:
    """Return what a render target holds before anything is drawn: black.

    Args:
        width: The target's width in pixels.
        height: The target's height in pixels.
        type: What the target stores.

    Returns:
        The texture.

    Raises:
        Error: If a size is not positive.
    """
    return RenderTarget(width, height, Color(0, 0, 0), type).attachment_texture(
        0
    )


def replace_texture(
    mut assets: Assets, id: TextureId, var texture: Texture
) raises:
    """Put a new texture in place of the one an id names, so every program
    that reads the id reads the new one.

    Args:
        assets: The stores.
        id: The texture to replace.
        texture: The new texture, moved in.

    Raises:
        Error: If no texture has that id.
    """
    _ = assets.textures.get(id)
    assets.textures.textures[id.value] = texture^


def check_texture_size(width: Int, height: Int) raises:
    """Refuse a render target size that holds no pixel.

    Args:
        width: The width in pixels.
        height: The height in pixels.

    Raises:
        Error: If either is not positive.
    """
    if width <= 0 or height <= 0:
        raise Error("A render target size must be positive")


def check_clip_bias(bias: Length) raises:
    """Refuse a clip bias that is not a finite length.

    Args:
        bias: How far past the surface the clipping plane lies.

    Raises:
        Error: If it is not finite.
    """
    if not isfinite(bias.to(METER)):
        raise Error("A clip bias must be finite")


struct Reflector(Movable):
    """A flat mirror, three.js's `Reflector`.

    Put `mesh` in the scene, and call `update` before each frame.
    """

    # The geometry, the shader material and the node. Add it to the scene
    # with `Scene.add_mesh`.
    var mesh: Mesh
    # The compiled shader, in `assets.programs`: three.js's
    # `material.uniforms`.
    var program: NodeProgramId
    # The render target's texture, in `assets.textures`: three.js's
    # `getRenderTarget().texture`. Replaced at each update.
    var texture: TextureId
    var texture_width: Int
    var texture_height: Int
    # The samples each pixel of the target takes, three.js's `multisample`.
    var multisample: Int
    # How far past the mirror the clipping plane lies.
    var clip_bias: Length
    # Render the target at the next update even when the camera is behind
    # the mirror, three.js's `forceUpdate`. The update clears it.
    var force_update: Bool
    # The camera the last update rendered through, three.js's `camera`.
    var camera: VirtualCamera
    # three.js's `textureMatrix`: the bias, the virtual camera's projection
    # and view, and the mirror's world matrix.
    var texture_matrix: Matrix4

    def __init__(
        out self,
        mut assets: Assets,
        geometry: GeometryId,
        node: NodeId,
        color: Color = DEFAULT_MIRROR_COLOR,
        texture_width: Int = DEFAULT_TEXTURE_SIZE,
        texture_height: Int = DEFAULT_TEXTURE_SIZE,
        clip_bias: Length = NO_CLIP_BIAS,
        multisample: Int = DEFAULT_MULTISAMPLE,
        vertex_shader: String = REFLECTOR_VERTEX,
        fragment_shader: String = REFLECTOR_FRAGMENT,
    ) raises:
        """Create a mirror and add its texture, program and material to the
        stores.

        Args:
            assets: The stores. The texture, the program and the material
                are added to them.
            geometry: The mirror's shape. Its +z faces the viewer, as a
                `plane` does.
            node: The scene node the mirror is drawn at.
            color: The tint the reflection is overlaid with, as authored in
                sRGB.
            texture_width: The render target's width in pixels.
            texture_height: The render target's height in pixels.
            clip_bias: How far past the mirror the clipping plane lies.
            multisample: How many samples each pixel of the target takes,
                three.js's `multisample`: four by default, zero for none.
            vertex_shader: The GLSL vertex shader, three.js's `shader`.
            fragment_shader: The GLSL fragment shader. The shaders read the
                uniforms `color`, `tDiffuse` and `textureMatrix`.

        Raises:
            Error: If a size is not positive, the bias is not finite, or a
                shader does not compile or lacks one of the uniforms.
        """
        check_texture_size(texture_width, texture_height)
        check_clip_bias(clip_bias)
        check_samples(multisample)
        self.texture = assets.textures.add(
            blank_texture(texture_width, texture_height, HALF_FLOAT_TARGET)
        )
        var program = compile_shader_material(vertex_shader, fragment_shader)
        program.set_uniform("color", color)
        program.set_texture("tDiffuse", self.texture)
        program.set_uniform("textureMatrix", Matrix4())
        self.program = assets.programs.add(program^)
        var material = assets.materials.add(shader_material(self.program))
        self.mesh = Mesh(geometry, material, node)
        self.texture_width = texture_width
        self.texture_height = texture_height
        self.clip_bias = clip_bias
        self.multisample = multisample
        self.force_update = False
        self.camera = default_virtual_camera()
        self.texture_matrix = Matrix4()

    def update[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
    ) raises -> Bool:
        """Render what the mirror shows to `camera` into its texture, three.js's
        `onBeforeRender`.

        Call it before each frame, after `Scene.update`. A camera behind the
        mirror renders nothing, unless `force_update` is set.

        Args:
            renderer: The renderer the scene is drawn with.
            scene: The scene, updated. The mirror's node is hidden while the
                target is drawn.
            assets: The stores. The texture is replaced.
            camera: The camera the frame is drawn through.

        Returns:
            True if the target was rendered.

        Raises:
            Error: If the mirror's node is not in the scene, the scene is
                stale, a matrix has no rotation, or the render raises.
        """
        var surface = scene.world_matrix(self.mesh.node)
        var mirror = mirror_view(surface, camera_world(camera, scene))
        if mirror.facing_away and not self.force_update:
            return False
        self.camera = follow_camera(camera, mirror.view)
        var matrix = projective_matrix(self.camera)
        assets.programs.get(self.program).set_uniform("textureMatrix", matrix)
        matrix.multiply(surface)
        self.texture_matrix = matrix
        var cut = Plane(
            mirror.normal,
            -mirror.normal.dot(mirror.point) + self.clip_bias.to(METER),
        )
        var seen = render_view(
            renderer,
            scene,
            assets,
            self.mesh.node,
            self.camera,
            cut,
            self.texture_width,
            self.texture_height,
            HALF_FLOAT_TARGET,
            self.multisample,
        )
        replace_texture(assets, self.texture, seen^)
        self.force_update = False
        return True


def refractor_plane(surface: Matrix4) raises -> Plane:
    """Return the plane a refractor keeps what lies behind, three.js's
    `updateRefractorPlane`: through the surface, facing its -z.

    Args:
        surface: The refractor's world matrix.

    Returns:
        The plane, facing away from the viewer.

    Raises:
        Error: If the matrix has no extent along an axis.
    """
    var position = Vector3(0, 0, 0)
    var quaternion = Quaternion.identity()
    var scale = Vector3(1, 1, 1)
    surface.decompose(position, quaternion, scale)
    var normal = Vector3(0, 0, 1)
    normal.apply_quaternion(quaternion)
    normal.normalize()
    normal.negate()
    return Plane.from_normal_and_point(normal, position)


def sees_front(surface: Matrix4, eye_world: Matrix4) raises -> Bool:
    """Return True if the camera is in front of a surface, three.js's
    `Refractor` `visible`.

    Args:
        surface: The surface's world matrix. Its +z is the front.
        eye_world: The camera's world matrix.

    Returns:
        Whether the camera sees the surface's front.

    Raises:
        Error: If the surface's matrix has no extent along an axis.
    """
    var toward = Vector3.from_matrix_position(
        surface
    ) - Vector3.from_matrix_position(eye_world)
    var normal = surface.extract_rotation().transform_direction(
        Vector3(0, 0, 1)
    )
    return toward.dot(normal) < 0


struct Refractor(Movable):
    """A pane that shows what lies behind it, three.js's `Refractor`.

    Put `mesh` in the scene, and call `update` before each frame. The
    material is transparent, so refractors are drawn after the opaque
    scene, furthest first, as in three.js.
    """

    # The geometry, the shader material and the node.
    var mesh: Mesh
    # The compiled shader, in `assets.programs`.
    var program: NodeProgramId
    # The render target's texture, in `assets.textures`. Replaced at each
    # update.
    var texture: TextureId
    var texture_width: Int
    var texture_height: Int
    # The samples each pixel of the target takes, three.js's `multisample`.
    var multisample: Int
    # How far past the surface the clipping plane lies.
    var clip_bias: Length
    # The camera the last update rendered through.
    var camera: VirtualCamera
    # three.js's `textureMatrix`, with the refractor's world matrix.
    var texture_matrix: Matrix4

    def __init__(
        out self,
        mut assets: Assets,
        geometry: GeometryId,
        node: NodeId,
        color: Color = DEFAULT_MIRROR_COLOR,
        texture_width: Int = DEFAULT_TEXTURE_SIZE,
        texture_height: Int = DEFAULT_TEXTURE_SIZE,
        clip_bias: Length = NO_CLIP_BIAS,
        multisample: Int = DEFAULT_MULTISAMPLE,
        vertex_shader: String = REFRACTOR_VERTEX,
        fragment_shader: String = REFRACTOR_FRAGMENT,
    ) raises:
        """Create a refractor and add its texture, program and material to
        the stores.

        Args:
            assets: The stores. The texture, the program and the material
                are added to them.
            geometry: The pane's shape. Its +z faces the viewer.
            node: The scene node the pane is drawn at.
            color: The tint the view is overlaid with, as authored in sRGB.
            texture_width: The render target's width in pixels.
            texture_height: The render target's height in pixels.
            clip_bias: How far past the surface the clipping plane lies.
            multisample: How many samples each pixel of the target takes,
                three.js's `multisample`: four by default, zero for none.
            vertex_shader: The GLSL vertex shader, three.js's `shader`.
            fragment_shader: The GLSL fragment shader. The shaders read the
                uniforms `color`, `tDiffuse` and `textureMatrix`.

        Raises:
            Error: If a size is not positive, the bias is not finite, or a
                shader does not compile or lacks one of the uniforms.
        """
        check_texture_size(texture_width, texture_height)
        check_clip_bias(clip_bias)
        check_samples(multisample)
        self.texture = assets.textures.add(
            blank_texture(texture_width, texture_height, HALF_FLOAT_TARGET)
        )
        var program = compile_shader_material(vertex_shader, fragment_shader)
        program.set_uniform("color", color)
        program.set_texture("tDiffuse", self.texture)
        program.set_uniform("textureMatrix", Matrix4())
        self.program = assets.programs.add(program^)
        var material = assets.materials.add(
            shader_material(self.program, transparent=True)
        )
        self.mesh = Mesh(geometry, material, node)
        self.texture_width = texture_width
        self.texture_height = texture_height
        self.clip_bias = clip_bias
        self.multisample = multisample
        self.camera = default_virtual_camera()
        self.texture_matrix = Matrix4()

    def update[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
    ) raises -> Bool:
        """Render what lies behind the pane into its texture, three.js's
        `onBeforeRender`.

        Call it before each frame, after `Scene.update`. A camera behind
        the pane renders nothing.

        Args:
            renderer: The renderer the scene is drawn with.
            scene: The scene, updated. The pane's node is hidden while the
                target is drawn.
            assets: The stores. The texture is replaced.
            camera: The camera the frame is drawn through.

        Returns:
            True if the target was rendered.

        Raises:
            Error: If the pane's node is not in the scene, the scene is
                stale, a matrix has no rotation, or the render raises.
        """
        var surface = scene.world_matrix(self.mesh.node)
        if not sees_front(surface, camera_world(camera, scene)):
            return False
        var plane = refractor_plane(surface)
        self.camera = follow_camera(camera, camera.view_matrix_in(scene))
        var matrix = projective_matrix(self.camera)
        assets.programs.get(self.program).set_uniform("textureMatrix", matrix)
        matrix.multiply(surface)
        self.texture_matrix = matrix
        var cut = Plane(plane.normal, plane.constant + self.clip_bias.to(METER))
        var seen = render_view(
            renderer,
            scene,
            assets,
            self.mesh.node,
            self.camera,
            cut,
            self.texture_width,
            self.texture_height,
            HALF_FLOAT_TARGET,
            self.multisample,
        )
        replace_texture(assets, self.texture, seen^)
        return True
