# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ground mirror for the SSR pass: three.js's `ReflectorForSSRPass`,
`examples/jsm/objects/ReflectorForSSRPass.js`.

It is a `Reflector` with three.js's own shader for the SSR pass's ground.
Without a depth texture it overlays the mirrored scene with its color, as
a `Reflector` does. With one, `use_depth_texture`, it reads how high above
the ground each reflected point is, and fades the reflection over
`max_distance` and by a fresnel factor of the camera's height: three.js's
`DISTANCE_ATTENUATION` and `FRESNEL`. The material then blends.

Call `update` before each frame, as for a `Reflector`. Give the SSR pass
the layers the mirror is on as its `ground`: the pass lays no reflection of
its own on the mirror's pixels, as three.js hides the mirror from the
pass's normals.

**Where this differs from three.js.** The ground is the plane `y = 0` in
world space whatever the mirror's own plane is, and the fresnel factor
reads the camera's world position: three.js reads its local `position`,
which is the same for a camera at the scene's root. The clipping plane is
`y = -clip_bias`, three.js's `globalPlanes`. `distance_attenuation` and
`fresnel` are chosen when the mirror is made, as three.js's `defines`.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.scene import Scene
from materials.glsl import compile_shader_material
from materials.material import shader_material
from materials.nodes import NodeProgramId
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.reflector import (
    DEFAULT_MIRROR_COLOR,
    DEFAULT_TEXTURE_SIZE,
    NO_CLIP_BIAS,
    REFLECTOR_VERTEX,
    VirtualCamera,
    blank_texture,
    camera_world,
    check_clip_bias,
    check_texture_size,
    default_virtual_camera,
    follow_camera,
    mirror_view,
    projective_matrix,
    render_view_target,
    replace_texture,
)
from render.framebuffer import Color
from render.target import FLOAT_TARGET, HALF_FLOAT_TARGET
from render.texture import CLAMP
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from std.math import isfinite, sqrt
from units.si import Length, METER

# three.js's `maxDistance` and `opacity` defaults.
comptime DEFAULT_GROUND_DISTANCE = Length(180.0, METER)
comptime DEFAULT_GROUND_OPACITY = Float32(0.5)

# `ReflectorForSSRPass.ReflectorShader`'s fragment shader, with
# `perspectiveDepthToViewZ` written out, as the subset has no chunks, and
# the overlay of a `vec3` named apart, as it has no overloads.
comptime SSR_REFLECTOR_FRAGMENT = """
uniform vec3 color;
uniform sampler2D tDiffuse;
uniform sampler2D tDepth;
uniform float maxDistance;
uniform float opacity;
uniform float fresnelCoe;
uniform float virtualCameraNear;
uniform float virtualCameraFar;
uniform mat4 virtualCameraProjectionMatrix;
uniform mat4 virtualCameraProjectionMatrixInverse;
uniform mat4 virtualCameraMatrixWorld;
uniform vec2 resolution;
varying vec4 vUv;

float blendOverlay( float base, float blend ) {
    return( base < 0.5 ? ( 2.0 * base * blend ) : ( 1.0 - 2.0 * ( 1.0 - base ) * ( 1.0 - blend ) ) );
}

vec3 blendOverlay3( vec3 base, vec3 blend ) {
    return vec3( blendOverlay( base.r, blend.r ), blendOverlay( base.g, blend.g ), blendOverlay( base.b, blend.b ) );
}

float perspectiveDepthToViewZ( float depth, float near, float far ) {
    return ( near * far ) / ( ( far - near ) * depth - far );
}

vec3 getViewPosition( vec2 uv, float depth, float clipW ) {
    vec4 clipPosition = vec4( ( vec3( uv, depth ) - 0.5 ) * 2.0, 1.0 );
    clipPosition *= clipW;
    return ( virtualCameraProjectionMatrixInverse * clipPosition ).xyz;
}

void main() {
    vec4 base = texture2DProj( tDiffuse, vUv );
#ifdef useDepthTexture
    vec2 uv = ( gl_FragCoord.xy - 0.5 ) / resolution.xy;
    uv.x = 1.0 - uv.x;
    float depth = texture2DProj( tDepth, vUv ).r;
    float viewZ = perspectiveDepthToViewZ( depth, virtualCameraNear, virtualCameraFar );
    float clipW = virtualCameraProjectionMatrix[2][3] * viewZ + virtualCameraProjectionMatrix[3][3];
    vec3 viewPosition = getViewPosition( uv, depth, clipW );
    vec3 worldPosition = ( virtualCameraMatrixWorld * vec4( viewPosition, 1.0 ) ).xyz;
    if ( worldPosition.y > maxDistance ) discard;
    float op = opacity;
#ifdef DISTANCE_ATTENUATION
    float ratio = 1.0 - ( worldPosition.y / maxDistance );
    float attenuation = ratio * ratio;
    op = opacity * attenuation;
#endif
#ifdef FRESNEL
    op *= fresnelCoe;
#endif
    gl_FragColor = vec4( blendOverlay3( base.rgb, color ), op );
#else
    gl_FragColor = vec4( blendOverlay3( base.rgb, color ), 1.0 );
#endif
}
"""


def fresnel_coefficient(eye: Vector3) -> Float32:
    """Return three.js's `fresnelCoe`: the eye's direction from the origin
    dotted with its reflection in the ground, made zero to one. One seen
    from the side, zero from straight above.

    Args:
        eye: The camera's position.

    Returns:
        The factor.
    """
    if not (isfinite(eye.x) and isfinite(eye.y) and isfinite(eye.z)):
        var up = eye.y / sqrt(eye.dot(eye))
        return 1 - up * up
    var unit = eye
    unit.normalize()
    var up = unit.y
    return 1 - up * up


struct ReflectorForSSR(Movable):
    """A ground mirror for the SSR pass, three.js's `ReflectorForSSRPass`.

    Put `mesh` in the scene, give the SSR pass its layers as `ground`, and
    call `update` before each frame.
    """

    # The geometry, the shader material and the node.
    var mesh: Mesh
    # The compiled shader, in `assets.programs`: three.js's
    # `material.uniforms`.
    var program: NodeProgramId
    # The render target's color and, with `use_depth_texture`, its depth,
    # in `assets.textures`. Replaced at each update.
    var texture: TextureId
    var depth: TextureId
    var texture_width: Int
    var texture_height: Int
    var clip_bias: Length
    var use_depth_texture: Bool
    # three.js's `color`, `maxDistance` and `opacity`, set on the program
    # at each update.
    var color: Color
    var max_distance: Length
    var opacity: Float32
    # three.js's `resolution`: the frame's size in pixels.
    var resolution: Vector2
    # The camera the last update rendered through.
    var camera: VirtualCamera

    def __init__(
        out self,
        mut assets: Assets,
        geometry: GeometryId,
        node: NodeId,
        color: Color = DEFAULT_MIRROR_COLOR,
        texture_width: Int = DEFAULT_TEXTURE_SIZE,
        texture_height: Int = DEFAULT_TEXTURE_SIZE,
        clip_bias: Length = NO_CLIP_BIAS,
        use_depth_texture: Bool = False,
        distance_attenuation: Bool = True,
        fresnel: Bool = True,
        resolution: Vector2 = Vector2(512, 512),
    ) raises:
        """Create the mirror and add its textures, program and material to
        the stores.

        Args:
            assets: The stores.
            geometry: The mirror's shape, flat on the ground.
            node: The scene node the mirror is drawn at.
            color: The tint the reflection is overlaid with, in sRGB.
            texture_width: The render target's width in pixels.
            texture_height: The render target's height in pixels.
            clip_bias: How far below the ground the clipping plane lies.
            use_depth_texture: Whether the reflection fades with the
                reflected point's height and blends.
            distance_attenuation: Whether it fades over `max_distance`.
            fresnel: Whether it fades as the camera looks down.
            resolution: The frame's size in pixels, three.js's
                `resolution`.

        Raises:
            Error: If a size is not positive or the bias is not finite.
        """
        check_texture_size(texture_width, texture_height)
        check_clip_bias(clip_bias)
        self.texture = assets.textures.add(
            blank_texture(texture_width, texture_height, HALF_FLOAT_TARGET)
        )
        self.depth = NO_TEXTURE
        var defines = List[String]()
        if use_depth_texture:
            defines.append("useDepthTexture")
            self.depth = assets.textures.add(
                blank_texture(texture_width, texture_height, FLOAT_TARGET)
            )
        if distance_attenuation:
            defines.append("DISTANCE_ATTENUATION")
        if fresnel:
            defines.append("FRESNEL")
        var program = compile_shader_material(
            REFLECTOR_VERTEX, SSR_REFLECTOR_FRAGMENT, defines
        )
        program.set_texture("tDiffuse", self.texture)
        if use_depth_texture:
            program.set_texture("tDepth", self.depth)
        self.program = assets.programs.add(program^)
        var material = assets.materials.add(
            shader_material(self.program, transparent=use_depth_texture)
        )
        self.mesh = Mesh(geometry, material, node)
        self.texture_width = texture_width
        self.texture_height = texture_height
        self.clip_bias = clip_bias
        self.use_depth_texture = use_depth_texture
        self.color = color
        self.max_distance = DEFAULT_GROUND_DISTANCE
        self.opacity = DEFAULT_GROUND_OPACITY
        self.resolution = resolution
        self.camera = default_virtual_camera()

    def update[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
    ) raises -> Bool:
        """Render what the mirror shows to `camera` into its textures,
        three.js's `doRender`, which the SSR pass calls before its beauty
        render.

        Args:
            renderer: The renderer the scene is drawn with.
            scene: The scene, updated. The mirror's node is hidden while its
                target is drawn.
            assets: The stores. The textures are replaced.
            camera: The camera the frame is drawn through.

        Returns:
            True if the target was rendered; False with the camera below
            the mirror, as three.js skips it.

        Raises:
            Error: If the distance or the opacity is not finite, the node
                is not in the scene, or the render raises.
        """
        var reach = self.max_distance.to(METER)
        if not isfinite(reach) or not isfinite(self.opacity):
            raise Error("A ground mirror's distance and opacity are finite")
        ref program = assets.programs.get(self.program)
        program.set_uniform("color", self.color)
        program.set_uniform("maxDistance", reach)
        program.set_uniform("opacity", self.opacity)
        var eye_world = camera_world(camera, scene)
        program.set_uniform(
            "fresnelCoe",
            fresnel_coefficient(Vector3.from_matrix_position(eye_world)),
        )
        var surface = scene.world_matrix(self.mesh.node)
        var mirror = mirror_view(surface, eye_world)
        if mirror.facing_away:
            return False
        self.camera = follow_camera(camera, mirror.view)
        var world = self.camera.view
        world.invert()
        var inverse = self.camera.projection
        inverse.invert()
        program.set_uniform("virtualCameraNear", self.camera.near)
        program.set_uniform("virtualCameraFar", self.camera.far)
        program.set_uniform("virtualCameraMatrixWorld", world)
        program.set_uniform(
            "virtualCameraProjectionMatrix", self.camera.projection
        )
        program.set_uniform("virtualCameraProjectionMatrixInverse", inverse)
        program.set_uniform("resolution", self.resolution)
        program.set_uniform("textureMatrix", projective_matrix(self.camera))
        var drawn = render_view_target(
            renderer,
            scene,
            assets,
            self.mesh.node,
            self.camera,
            Plane(Vector3(0, 1, 0), self.clip_bias.to(METER)),
            self.texture_width,
            self.texture_height,
            HALF_FLOAT_TARGET,
        )
        replace_texture(assets, self.texture, drawn.attachment_texture(0))
        if self.use_depth_texture:
            replace_texture(
                assets, self.depth, drawn.depth_texture(CLAMP, FLOAT_TARGET)
            )
        return True
