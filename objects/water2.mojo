# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flowing water surface, from three.js
`examples/jsm/objects/Water2.js`.

This water holds a `Reflector` and a `Refractor` on its own node. Each
update renders both of their targets, and the water's shader mixes the
two by a Fresnel term. Two normal maps, moved along a flow, bend the
coordinates it reads them at. A flow map, when there is one, gives the
flow's direction at each point. Else one direction holds everywhere.

The flow is three.js's: two offsets that run half a cycle apart and wrap
at a cycle of 0.15, blended so that no reset shows. three.js reads the
time from a `Clock`. Here `update` takes the time since the last frame.

The shader is three.js's `WaterShader` in the GLSL subset. The subset has
no `#ifdef`, so the fragment shader is written for the flow map or for the
flow direction; see `water2_fragment`.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.scene import Scene
from materials.glsl import compile_shader_material
from materials.material import shader_material
from materials.nodes import NodeProgramId
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from objects.mesh import Mesh
from objects.reflector import (
    DEFAULT_TEXTURE_SIZE,
    NO_CLIP_BIAS,
    Reflector,
    Refractor,
    follow_camera,
    projective_matrix,
)
from render.framebuffer import Color
from render.texture import REPEAT
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from std.math import isfinite
from units.si import Duration, Frequency, Length, PER_SECOND, SECOND

# How long a phase of the flow runs, in offsets: three.js's `cycle`.
comptime FLOW_CYCLE = Float64(0.15)
# three.js's `color` default, `0xFFFFFF`.
comptime DEFAULT_WATER2_COLOR = Color(0xFF, 0xFF, 0xFF)
# three.js's `flowDirection` default.
comptime DEFAULT_FLOW_DIRECTION = Vector2(1, 0)
# three.js's `flowSpeed` default: offsets per second.
comptime DEFAULT_FLOW_SPEED = Frequency(0.03, PER_SECOND)
# three.js's `reflectivity` default.
comptime DEFAULT_REFLECTIVITY = Float32(0.02)

comptime WATER2_VERTEX = """
uniform mat4 textureMatrix;

varying vec4 vCoord;
varying vec2 vUv;
varying vec3 vToEye;

void main() {
    vUv = uv;
    vec4 worldPosition = modelMatrix * vec4( position, 1.0 );
    vCoord = textureMatrix * worldPosition;
    vToEye = cameraPosition - worldPosition.xyz;
    vec4 mvPosition =  viewMatrix * worldPosition;
    gl_Position = projectionMatrix * mvPosition;
}
"""

# What the fragment shader holds before and after the flow, which is the
# one part `USE_FLOWMAP` changes.
comptime _FRAGMENT_HEAD = """
uniform sampler2D tReflectionMap;
uniform sampler2D tRefractionMap;
uniform sampler2D tNormalMap0;
uniform sampler2D tNormalMap1;
"""

comptime _FRAGMENT_BODY = """
uniform vec3 color;
uniform float reflectivity;
uniform vec4 config;

varying vec4 vCoord;
varying vec2 vUv;
varying vec3 vToEye;

void main() {
    float flowMapOffset0 = config.x;
    float flowMapOffset1 = config.y;
    float halfCycle = config.z;
    float scale = config.w;

    vec3 toEye = normalize( vToEye );

    vec2 flow;
"""

comptime _FRAGMENT_TAIL = """
    flow.x *= - 1.0;

    vec4 normalColor0 = texture2D( tNormalMap0, ( vUv * scale ) + flow * flowMapOffset0 );
    vec4 normalColor1 = texture2D( tNormalMap1, ( vUv * scale ) + flow * flowMapOffset1 );

    float flowLerp = abs( halfCycle - flowMapOffset0 ) / halfCycle;
    vec4 normalColor = mix( normalColor0, normalColor1, flowLerp );

    vec3 normal = normalize( vec3( normalColor.r * 2.0 - 1.0, normalColor.b,  normalColor.g * 2.0 - 1.0 ) );

    float theta = max( dot( toEye, normal ), 0.0 );
    float reflectance = reflectivity + ( 1.0 - reflectivity ) * pow( ( 1.0 - theta ), 5.0 );

    vec3 coord = vCoord.xyz / vCoord.w;
    vec2 uv = coord.xy + coord.z * normal.xz * 0.05;

    vec4 reflectColor = texture2D( tReflectionMap, vec2( 1.0 - uv.x, uv.y ) );
    vec4 refractColor = texture2D( tRefractionMap, uv );

    gl_FragColor = vec4( color, 1.0 ) * mix( refractColor, reflectColor, reflectance );
}
"""


def water2_fragment(flow_map: Bool) -> String:
    """Return three.js's `WaterShader` fragment shader with `USE_FLOWMAP`
    defined or not.

    Args:
        flow_map: True to read the flow from `tFlowMap`, False to read it
            from `flowDirection`.

    Returns:
        The GLSL.
    """
    if flow_map:
        return (
            String(_FRAGMENT_HEAD)
            + "uniform sampler2D tFlowMap;\n"
            + _FRAGMENT_BODY
            + "    flow = texture2D( tFlowMap, vUv ).rg * 2.0 - 1.0;\n"
            + _FRAGMENT_TAIL
        )
    return (
        String(_FRAGMENT_HEAD)
        + "uniform vec2 flowDirection;\n"
        + _FRAGMENT_BODY
        + "    flow = flowDirection;\n"
        + _FRAGMENT_TAIL
    )


def _repeat(mut assets: Assets, map: TextureId) raises:
    """Set a texture's wrap to `REPEAT` on both axes. The id is checked."""
    assets.textures.textures[map.value].wrap_s = REPEAT
    assets.textures.textures[map.value].wrap_t = REPEAT


struct Water2(Movable):
    """A flowing water with a reflection and a refraction, three.js's
    `Water` from `Water2.js`.

    Put `mesh` in the scene, and call `update` before each frame. The
    material is transparent and takes the scene's fog, as three.js's does.
    """

    # The geometry, the shader material and the node.
    var mesh: Mesh
    # The compiled shader, in `assets.programs`.
    var program: NodeProgramId
    # The two objects whose targets the shader mixes, on the water's node.
    # Their own meshes are not in the scene.
    var reflector: Reflector
    var refractor: Refractor
    # How fast the flow moves, in offsets per second.
    var flow_speed: Frequency
    # three.js's `config`: the two flow offsets, half a cycle, and the
    # scale of the normal maps. The offsets add up in doubles, as
    # JavaScript adds them.
    var offset0: Float64
    var offset1: Float64
    var scale: Float32
    # three.js's `textureMatrix`: the bias, the camera's projection and
    # view, and the water's world matrix.
    var texture_matrix: Matrix4

    def __init__(
        out self,
        mut assets: Assets,
        geometry: GeometryId,
        node: NodeId,
        normal_map0: TextureId,
        normal_map1: TextureId,
        color: Color = DEFAULT_WATER2_COLOR,
        texture_width: Int = DEFAULT_TEXTURE_SIZE,
        texture_height: Int = DEFAULT_TEXTURE_SIZE,
        clip_bias: Length = NO_CLIP_BIAS,
        flow_direction: Vector2 = DEFAULT_FLOW_DIRECTION,
        flow_speed: Frequency = DEFAULT_FLOW_SPEED,
        reflectivity: Float32 = DEFAULT_REFLECTIVITY,
        scale: Float32 = 1.0,
        flow_map: TextureId = NO_TEXTURE,
    ) raises:
        """Create a flowing water and add its textures, programs and
        materials to the stores.

        Args:
            assets: The stores. The reflector's and the refractor's
                textures, programs and materials are added, and the
                water's program and material.
            geometry: The water's shape. Its +z faces up, out of the water.
            node: The scene node the water is drawn at.
            normal_map0: The first normal map. Its wrap is set to `REPEAT`,
                as three.js sets it.
            normal_map1: The second normal map. Its wrap is set to `REPEAT`.
            color: The tint of the mix, as authored in sRGB.
            texture_width: The width of both render targets in pixels.
            texture_height: The height of both render targets in pixels.
            clip_bias: How far past the surface both clipping planes lie.
            flow_direction: Which way the flow runs, when there is no flow
                map.
            flow_speed: How fast the flow runs.
            reflectivity: The reflectance seen straight down.
            scale: How many times the normal maps repeat across the
                coordinates.
            flow_map: A texture whose red and green give the flow at each
                point, or `NO_TEXTURE` to use `flow_direction`.

        Raises:
            Error: If a normal map or the flow map is not in the stores, a
                number is not finite, or the reflector or the refractor
                refuses its arguments.
        """
        if not _finite_flow(flow_direction, flow_speed, reflectivity, scale):
            raise Error("A water's flow, reflectivity and scale must be finite")
        _ = assets.textures.get(normal_map0)
        _ = assets.textures.get(normal_map1)
        var flows = flow_map != NO_TEXTURE
        if flows:
            _ = assets.textures.get(flow_map)
        self.reflector = Reflector(
            assets,
            geometry,
            node,
            texture_width=texture_width,
            texture_height=texture_height,
            clip_bias=clip_bias,
        )
        self.refractor = Refractor(
            assets,
            geometry,
            node,
            texture_width=texture_width,
            texture_height=texture_height,
            clip_bias=clip_bias,
        )
        _repeat(assets, normal_map0)
        _repeat(assets, normal_map1)
        var program = compile_shader_material(
            WATER2_VERTEX, water2_fragment(flows)
        )
        if flows:
            program.set_texture("tFlowMap", flow_map)
        else:
            program.set_uniform("flowDirection", flow_direction)
        program.set_texture("tReflectionMap", self.reflector.texture)
        program.set_texture("tRefractionMap", self.refractor.texture)
        program.set_texture("tNormalMap0", normal_map0)
        program.set_texture("tNormalMap1", normal_map1)
        program.set_uniform("color", color)
        program.set_uniform("reflectivity", reflectivity)
        program.set_uniform("textureMatrix", Matrix4())
        self.flow_speed = flow_speed
        self.offset0 = 0
        self.offset1 = FLOW_CYCLE * 0.5
        self.scale = scale
        program.set_uniform(
            "config",
            Vector4(0, Float32(self.offset1), Float32(self.offset1), scale),
        )
        self.program = assets.programs.add(program^)
        var material = shader_material(self.program, transparent=True)
        material.fog = True
        self.mesh = Mesh(geometry, assets.materials.add(material), node)
        self.texture_matrix = Matrix4()

    def config(self) -> Vector4:
        """Return three.js's `config` uniform: the two offsets, half a
        cycle, and the scale.

        Returns:
            The uniform's value.
        """
        return Vector4(
            Float32(self.offset0),
            Float32(self.offset1),
            Float32(FLOW_CYCLE * 0.5),
            self.scale,
        )

    def flow(mut self, delta: Duration) raises:
        """Move the flow on by `delta`, three.js's `updateFlow`.

        Both offsets stay within a cycle and half a cycle apart, so the
        blend of the two normal maps never jumps.

        Args:
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative or not finite.
        """
        var seconds = Float64(delta.to(SECOND))
        if not (isfinite(seconds) and seconds >= 0):
            raise Error("A frame's time must be finite and not negative")
        var half = FLOW_CYCLE * 0.5
        self.offset0 += Float64(self.flow_speed.to(PER_SECOND)) * seconds
        self.offset1 = self.offset0 + half
        if self.offset0 >= FLOW_CYCLE:
            self.offset0 = 0
            self.offset1 = half
        elif self.offset1 >= FLOW_CYCLE:
            self.offset1 = self.offset1 - FLOW_CYCLE

    def update[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        mut scene: Scene,
        mut assets: Assets,
        camera: C,
        delta: Duration,
    ) raises:
        """Move the flow and render both targets, three.js's
        `onBeforeRender`.

        Call it before each frame, after `Scene.update`. The reflector and
        the refractor each skip their render when the camera is behind the
        water, as in three.js.

        Args:
            renderer: The renderer the scene is drawn with.
            scene: The scene, updated. The water's node is hidden while the
                targets are drawn.
            assets: The stores. The two textures are replaced, and the
                program's `textureMatrix` and `config` are set.
            camera: The camera the frame is drawn through.
            delta: The time since the last frame, three.js's
                `clock.getDelta()`.

        Raises:
            Error: If the time is refused, the water's node is not in the
                scene, the scene is stale, or a render raises.
        """
        var surface = scene.world_matrix(self.mesh.node)
        var seen = follow_camera(camera, camera.view_matrix_in(scene))
        var matrix = projective_matrix(seen)
        self.flow(delta)
        ref program = assets.programs.get(self.program)
        program.set_uniform("textureMatrix", matrix)
        program.set_uniform("config", self.config())
        matrix.multiply(surface)
        self.texture_matrix = matrix
        _ = self.reflector.update(renderer, scene, assets, camera)
        _ = self.refractor.update(renderer, scene, assets, camera)


def _finite_flow(
    direction: Vector2, speed: Frequency, reflectivity: Float32, scale: Float32
) -> Bool:
    """Return True if every number of a water's flow is finite."""
    return (
        isfinite(direction.x)
        and isfinite(direction.y)
        and isfinite(speed.to(PER_SECOND))
        and isfinite(reflectivity)
        and isfinite(scale)
    )
