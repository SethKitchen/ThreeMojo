# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An ocean surface, from three.js `examples/jsm/objects/Water.js`.

The water is a mirror whose surface a normal map ripples. Each update
renders the scene mirrored through the water's plane into a byte render
target, as `objects.reflector.Reflector` does. The shader reads four
moving copies of the normal map, bends the reflection by the normal, and
mixes it with a scatter color by a Fresnel term. A sun adds a highlight.

The shader is three.js's `MirrorShader` in the GLSL subset:

- `sunLight` wrote its two results through `inout` parameters. The subset
  has none, so it is two functions that return them.
- `getShadowMask()` is one. The shader material is unlit and receives no
  shadow.
- The texture matrix acts on world positions, as three.js's does for this
  object alone.

Move the waves on with `set_time`, three.js's `uniforms.time.value`.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.scene import Scene
from materials.glsl import compile_shader_material
from materials.material import FRONT_SIDE, Side, shader_material
from materials.nodes import NodeProgramId
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.reflector import (
    DEFAULT_MIRROR_COLOR,
    DEFAULT_TEXTURE_SIZE,
    NO_CLIP_BIAS,
    VirtualCamera,
    blank_texture,
    camera_world,
    check_clip_bias,
    check_texture_size,
    default_virtual_camera,
    follow_camera,
    mirror_view,
    projective_matrix,
    render_view,
    replace_texture,
)
from render.framebuffer import Color
from render.target import UNSIGNED_BYTE_TARGET
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import isfinite
from units.si import Duration, Length, METER, SECOND

# three.js's `sunDirection` default.
comptime DEFAULT_SUN_DIRECTION = Vector3(0.70707, 0.70707, 0.0)
# three.js's `sunColor` default, `0xffffff`.
comptime DEFAULT_SUN_COLOR = Color(0xFF, 0xFF, 0xFF)
# three.js's `distortionScale` default.
comptime DEFAULT_DISTORTION_SCALE = Float32(20.0)

comptime WATER_VERTEX = """
uniform mat4 textureMatrix;
uniform float time;

varying vec4 mirrorCoord;
varying vec4 worldPosition;

void main() {
    mirrorCoord = modelMatrix * vec4( position, 1.0 );
    worldPosition = mirrorCoord.xyzw;
    mirrorCoord = textureMatrix * mirrorCoord;
    vec4 mvPosition =  modelViewMatrix * vec4( position, 1.0 );
    gl_Position = projectionMatrix * mvPosition;
}
"""

comptime WATER_FRAGMENT = """
uniform sampler2D mirrorSampler;
uniform float alpha;
uniform float time;
uniform float size;
uniform float distortionScale;
uniform sampler2D normalSampler;
uniform vec3 sunColor;
uniform vec3 sunDirection;
uniform vec3 eye;
uniform vec3 waterColor;

varying vec4 mirrorCoord;
varying vec4 worldPosition;

vec4 getNoise( vec2 uv ) {
    vec2 uv0 = ( uv / 103.0 ) + vec2(time / 17.0, time / 29.0);
    vec2 uv1 = uv / 107.0-vec2( time / -19.0, time / 31.0 );
    vec2 uv2 = uv / vec2( 8907.0, 9803.0 ) + vec2( time / 101.0, time / 97.0 );
    vec2 uv3 = uv / vec2( 1091.0, 1027.0 ) - vec2( time / 109.0, time / -113.0 );
    vec4 noise = texture2D( normalSampler, uv0 ) +
        texture2D( normalSampler, uv1 ) +
        texture2D( normalSampler, uv2 ) +
        texture2D( normalSampler, uv3 );
    return noise * 0.5 - 1.0;
}

vec3 sunSpecular( vec3 surfaceNormal, vec3 eyeDirection, float shiny, float spec ) {
    vec3 reflection = normalize( reflect( -sunDirection, surfaceNormal ) );
    float direction = max( 0.0, dot( eyeDirection, reflection ) );
    return pow( direction, shiny ) * sunColor * spec;
}

vec3 sunDiffuse( vec3 surfaceNormal, float diffuse ) {
    return max( dot( sunDirection, surfaceNormal ), 0.0 ) * sunColor * diffuse;
}

void main() {
    vec4 noise = getNoise( worldPosition.xz * size );
    vec3 surfaceNormal = normalize( noise.xzy * vec3( 1.5, 1.0, 1.5 ) );

    vec3 diffuseLight = vec3(0.0);
    vec3 specularLight = vec3(0.0);

    vec3 worldToEye = eye-worldPosition.xyz;
    vec3 eyeDirection = normalize( worldToEye );
    specularLight += sunSpecular( surfaceNormal, eyeDirection, 100.0, 2.0 );
    diffuseLight += sunDiffuse( surfaceNormal, 0.5 );

    float distance = length(worldToEye);

    vec2 distortion = surfaceNormal.xz * ( 0.001 + 1.0 / distance ) * distortionScale;
    vec3 reflectionSample = vec3( texture2D( mirrorSampler, mirrorCoord.xy / mirrorCoord.w + distortion ) );

    float theta = max( dot( eyeDirection, surfaceNormal ), 0.0 );
    float rf0 = 0.3;
    float reflectance = rf0 + ( 1.0 - rf0 ) * pow( ( 1.0 - theta ), 5.0 );
    vec3 scatter = max( 0.0, dot( surfaceNormal, eyeDirection ) ) * waterColor;
    vec3 albedo = mix( ( sunColor * diffuseLight * 0.3 + scatter ), ( vec3( 0.1 ) + reflectionSample * 0.9 + reflectionSample * specularLight ), reflectance);
    vec3 outgoingLight = albedo;
    gl_FragColor = vec4( outgoingLight, alpha );
}
"""


struct Water(Movable):
    """A rippled mirror, three.js's `Water` from `Water.js`.

    Put `mesh` in the scene, and call `update` before each frame.
    """

    # The geometry, the shader material and the node.
    var mesh: Mesh
    # The compiled shader, in `assets.programs`: three.js's
    # `material.uniforms`.
    var program: NodeProgramId
    # The render target's texture, in `assets.textures`. Replaced at each
    # update.
    var texture: TextureId
    var texture_width: Int
    var texture_height: Int
    # How far past the surface the clipping plane lies.
    var clip_bias: Length
    # The camera the last update rendered through.
    var camera: VirtualCamera
    # three.js's `textureMatrix`: the bias, the mirror camera's projection
    # and its view. It acts on world positions.
    var texture_matrix: Matrix4

    def __init__(
        out self,
        mut assets: Assets,
        geometry: GeometryId,
        node: NodeId,
        normals: TextureId,
        texture_width: Int = DEFAULT_TEXTURE_SIZE,
        texture_height: Int = DEFAULT_TEXTURE_SIZE,
        clip_bias: Length = NO_CLIP_BIAS,
        alpha: Float32 = 1.0,
        time: Duration = Duration(0.0, SECOND),
        sun_direction: Vector3 = DEFAULT_SUN_DIRECTION,
        sun_color: Color = DEFAULT_SUN_COLOR,
        water_color: Color = DEFAULT_MIRROR_COLOR,
        eye: Vector3 = Vector3(0, 0, 0),
        distortion_scale: Float32 = DEFAULT_DISTORTION_SCALE,
        side: Side = FRONT_SIDE,
        fog: Bool = False,
    ) raises:
        """Create a water surface and add its texture, program and material
        to the stores.

        Args:
            assets: The stores. The texture, the program and the material
                are added to them.
            geometry: The water's shape. Its +z faces up, out of the water.
            node: The scene node the water is drawn at.
            normals: The normal map the waves are read from, three.js's
                `waterNormals`. Set its wrap to `REPEAT`, as three.js's
                example does.
            texture_width: The render target's width in pixels.
            texture_height: The render target's height in pixels.
            clip_bias: How far past the surface the clipping plane lies.
            alpha: The surface's opacity.
            time: Where the waves start, three.js's `time`.
            sun_direction: Which way the sunlight comes from.
            sun_color: The sunlight's color, as authored in sRGB.
            water_color: The color the water scatters, as authored in sRGB.
            eye: Where the highlight is seen from until the first update.
            distortion_scale: How far the waves bend the reflection.
            side: `FRONT_SIDE`, `BACK_SIDE` or `DOUBLE_SIDE`.
            fog: Whether the scene's fog reaches the water.

        Raises:
            Error: If a size is not positive, the bias, the alpha, the time
                or the distortion is not finite, the side is none of the
                three, or `normals` is not a texture id.
        """
        check_texture_size(texture_width, texture_height)
        check_clip_bias(clip_bias)
        if not side.is_valid():
            raise Error("A water's side must be one of the three")
        if not (
            isfinite(alpha)
            and isfinite(time.to(SECOND))
            and isfinite(distortion_scale)
        ):
            raise Error("A water's alpha, time and distortion must be finite")
        self.texture = assets.textures.add(
            blank_texture(texture_width, texture_height, UNSIGNED_BYTE_TARGET)
        )
        var program = compile_shader_material(WATER_VERTEX, WATER_FRAGMENT)
        program.set_texture("mirrorSampler", self.texture)
        program.set_texture("normalSampler", normals)
        program.set_uniform("textureMatrix", Matrix4())
        program.set_uniform("alpha", alpha)
        program.set_uniform("time", time.to(SECOND))
        program.set_uniform("size", Float32(1.0))
        program.set_uniform("distortionScale", distortion_scale)
        program.set_uniform("sunColor", sun_color)
        program.set_uniform("sunDirection", sun_direction)
        program.set_uniform("eye", eye)
        program.set_uniform("waterColor", water_color)
        self.program = assets.programs.add(program^)
        var material = shader_material(self.program, side=side)
        material.fog = fog
        self.mesh = Mesh(geometry, assets.materials.add(material), node)
        self.texture_width = texture_width
        self.texture_height = texture_height
        self.clip_bias = clip_bias
        self.camera = default_virtual_camera()
        self.texture_matrix = Matrix4()

    def set_time(self, mut assets: Assets, time: Duration) raises:
        """Move the waves to a time, three.js's `uniforms.time.value`.

        Args:
            assets: The stores that hold the program.
            time: How long the waves have run.

        Raises:
            Error: If the time is not finite, or the program is gone.
        """
        var seconds = time.to(SECOND)
        if not isfinite(seconds):
            raise Error("A water's time must be finite")
        assets.programs.get(self.program).set_uniform("time", seconds)

    def update[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
    ) raises -> Bool:
        """Render the mirrored scene into the water's texture, three.js's
        `onBeforeRender`.

        Call it before each frame, after `Scene.update`. A camera below the
        water renders nothing.

        Args:
            renderer: The renderer the scene is drawn with.
            scene: The scene, updated. The water's node is hidden while the
                target is drawn.
            assets: The stores. The texture is replaced, and the program's
                `textureMatrix` and `eye` are set.
            camera: The camera the frame is drawn through.

        Returns:
            True if the target was rendered.

        Raises:
            Error: If the water's node is not in the scene, the scene is
                stale, a matrix has no rotation, or the render raises.
        """
        var surface = scene.world_matrix(self.mesh.node)
        var eye_world = camera_world(camera, scene)
        var mirror = mirror_view(surface, eye_world)
        if mirror.facing_away:
            return False
        self.camera = follow_camera(camera, mirror.view)
        self.texture_matrix = projective_matrix(self.camera)
        ref program = assets.programs.get(self.program)
        program.set_uniform("textureMatrix", self.texture_matrix)
        program.set_uniform("eye", Vector3.from_matrix_position(eye_world))
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
            UNSIGNED_BYTE_TARGET,
        )
        replace_texture(assets, self.texture, seen^)
        return True
