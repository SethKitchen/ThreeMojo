# Scene JSON

`exporters/object_json.mojo` writes a scene and its assets as three.js JSON. `loaders/object_loader.mojo` reads that JSON back into a scene and its assets. The format is version 4 of three.js's JSON Object format. three.js: `Object3D.toJSON` and `ObjectLoader`.

```mojo
var cameras = ObjectCameras()
cameras.perspective.append(camera)
write_object_json("out/scene.json", scene, assets, cameras)

var loaded = Scene()
var loaded_assets = Assets()
var model = load_object_json("out/scene.json", loaded, loaded_assets)
var camera_again = model.cameras.perspective[0]
```

| Function | Meaning |
|---|---|
| `object_to_json(scene, assets, cameras) -> String` | The JSON text of a scene, its assets and its cameras. |
| `write_object_json(path, scene, assets, cameras)` | Write that text to a file. |
| `read_object_json(text, scene, assets, directory) -> ObjectModel` | Read a JSON text into a scene and its assets. |
| `load_object_json(path, scene, assets) -> ObjectModel` | Read a JSON file. An image with a relative URL is read beside the file. |

The reader adds to the scene and the assets that you give it. The nodes that it adds come after the nodes that the scene has already.

## The document

A document has four parts. The writer writes them, and the reader reads them, as three.js does.

| Key | Meaning |
|---|---|
| `metadata` | `version` 4.6, `type` `Object`. The reader refuses another type or a major version that is not 4. |
| `geometries`, `materials`, `textures`, `images`, `skeletons` | The libraries. Each entry has a `uuid`. Each thing is written one time, also when two meshes use it. |
| `object` | The root object. The writer writes a `Scene`. Its children are the root nodes of the scene. |

three.js gives each thing a random uuid. The writer makes each uuid from the kind of the thing and its position. Thus the same scene always gives the same text. Node `k` has the uuid `object_uuid(2, k)`.

`ObjectModel` tells you what the reader made:

| Field | Meaning |
|---|---|
| `node(uuid) -> NodeId` | The node that the object with this uuid became. |
| `nodes`, `uuids` | Each node that the reader added, and the uuid of its object, in the order of the tree. |
| `cameras` | An `ObjectCameras`: the perspective and orthographic cameras of the document. |

## Objects

Each object becomes one scene node. The node gets the `name`, `visible`, `layers`, `renderOrder` and `matrix` of the object. The reader decomposes the matrix as three.js's `Matrix4.decompose` does. Without a matrix, the reader reads `position`, `rotation`, `quaternion` and `scale`. An object with `matrixAutoUpdate` false keeps its matrix as it is.

The type of the object tells what the node carries:

| Type | The node carries |
|---|---|
| `Object3D`, `Group`, `Bone` | Nothing. |
| `Mesh` | A `Mesh`, with `castShadow`, `receiveShadow` and `frustumCulled`. |
| `InstancedMesh` | An `InstancedMesh`, with its `count` and its `instanceMatrix`. |
| `BatchedMesh` | A `BatchedMesh`. See [Other objects](#other-objects). |
| `SkinnedMesh` | A `SkinnedMesh` on its skeleton. See [Other objects](#other-objects). |
| `Line`, `LineLoop`, `LineSegments` | A `Line` with the `LineMode` `STRIP`, `LOOP` or `SEGMENTS`. |
| `Points` | `Points`. |
| `Sprite` | A `Sprite`. |
| `LOD` | An `Lod`. See [Other objects](#other-objects). |
| `AmbientLight`, `DirectionalLight`, `PointLight`, `HemisphereLight`, `SpotLight`, `RectAreaLight`, `LightProbe` | A `Light` of that kind, on the layers of the object. A `LightProbe` reads its 27 `sh` numbers. |
| `PerspectiveCamera`, `OrthographicCamera` | A camera that rides the node, in `ObjectModel.cameras`. |

A `Scene` root is not a node. Its `fog` becomes the fog of the scene. A number in `background` becomes a color background. A string in `background` names a texture or a cube texture. A string in `environment` names the cube texture of the scene's `environment`. See [Cube textures](#cube-textures).

A `Mesh` and a `SkinnedMesh` carry their `morphTargetInfluences`, one number for each morph target of the geometry. The reader reads eight at most, because a mesh here holds eight.

A light's `target` names an object by its uuid. When no object has that uuid, the target is the origin. This is the default target of three.js. A light's `shadow` gives `bias`, `normalBias`, `radius`, `mapSize` and the planes of its camera. A directional light's shadow camera must be square about its axis, because `LightShadow` holds one `extent`.

The writer makes the same objects. A node that carries one thing becomes that thing. A node that carries more than one thing becomes an `Object3D`, with one child object for each thing at the identity. A light or a camera on other layers than its node is also a child object. A light with no node, as an ambient light usually is, is a child of the scene. The reader then gives that light a node of its own.

A camera is not a scene node in this port. Put the cameras in an `ObjectCameras`, and attach each one to a node first. The writer refuses a camera that rides no node.

A node that carries nothing and is a bone of a skeleton becomes a `Bone`.

## Other objects

An LOD, a skinned mesh and a batched mesh have more parts than a mesh. The writer writes them as three.js's `toJSON` writes them.

| Object | Keys |
|---|---|
| `LOD` | `levels`: one entry for each level, with the `object` uuid, the `distance` and the `hysteresis`. Each level is a child `Mesh` at the identity. |
| `SkinnedMesh` | `bindMode` (`attached` or `detached`), `bindMatrix` and `skeleton`. The `skeleton` names an entry of the `skeletons` library. |
| `BatchedMesh` | One joined `geometry`, `geometryInfo`, `instanceInfo`, `perObjectFrustumCulled` and three data textures. |

A skeleton entry has the uuids of its `bones` and their `boneInverses`. The bones are objects in the same document. The reader reads one inverse for each bone and ignores the rest, as three.js's `Skeleton.fromJSON` does. The reader binds each skinned mesh after it reads all the objects, because a bone can come after its mesh.

A skeleton entry can leave out `boneInverses`, or give an empty list. Then the reader calculates each inverse from the world matrix of its bone, as three.js's `Skeleton.calculateInverses` does. Thus the mesh is bound in the pose that the document gives.

A batched mesh joins its geometries into one `BufferGeometry`, as three.js's `BatchedMesh` holds them. Each `geometryInfo` entry gives the `vertexStart`, `vertexCount`, `indexStart` and `indexCount` of one geometry. Each `instanceInfo` entry gives the `geometryIndex` of one instance. The instance matrices are in `matricesTexture`, and the instance colors are in `colorsTexture`. Both are `DataTexture` entries with a `Float32Array` image. The colors are linear, as three.js keeps them.

The writer also writes the `indirectTexture` that three.js reads.

The reader splits the joined geometry back into its parts. It adds each part to the assets. It leaves out an instance that is not `active` or not `visible`, because three.js does not draw it.

## Geometry

The writer writes each geometry as a `BufferGeometry`. Each attribute is a `Float32Array`. The index is a `Uint16Array` up to 65535 vertices, and a `Uint32Array` above that, as three.js chooses. The groups and the morph targets are written too.

An instanced geometry is an `InstancedBufferGeometry` with its `instanceCount`, and each per-instance attribute has its `meshPerAttribute`. An interleaved attribute is written as its own floats, as three.js writes one attribute alone. See [Geometry](Geometry#interleaved-buffers).

The reader reads a `BufferGeometry` with `Float32Array` attributes, an index, groups and morph targets. An interleaved attribute reads the `interleavedBuffers` and `arrayBuffers` of the geometry, and attributes that name one buffer share it. An `InstancedBufferGeometry` keeps its `instanceCount` and the `meshPerAttribute` of each attribute. three.js's loader leaves both at their defaults. It also builds three parametric types from their parameters:

| Type | Built with | Condition |
|---|---|---|
| `BoxGeometry` | `box` | One segment on each side. |
| `PlaneGeometry` | `plane` | None. |
| `SphereGeometry` | `sphere` | The whole sphere: `phiStart`, `phiLength`, `thetaStart` and `thetaLength` at their defaults. |

## Materials

Each `MaterialKind` has the three.js class of the same kind:

| Kind | Type |
|---|---|
| `BASIC` | `MeshBasicMaterial` |
| `LAMBERT` | `MeshLambertMaterial` |
| `PHONG` | `MeshPhongMaterial` |
| `TOON` | `MeshToonMaterial` |
| `MATCAP` | `MeshMatcapMaterial` |
| `STANDARD` | `MeshStandardMaterial` |
| `PHYSICAL` | `MeshPhysicalMaterial` |
| `NORMALS` | `MeshNormalMaterial` |
| `DEPTH` | `MeshDepthMaterial` |
| `SHADOW` | `ShadowMaterial` |

A line, points and a sprite use a `BASIC` material. The writer writes that material as the three.js class of the object:

| Object | Type | Fields |
|---|---|---|
| `Line` | `LineBasicMaterial`, or `LineDashedMaterial` when the material has a gap | `linewidth`, and `dashSize`, `gapSize` and `scale` for dashes |
| `Points` | `PointsMaterial` | `map`, `alphaMap`, `size`, `sizeAttenuation` |
| `Sprite` | `SpriteMaterial` | `map`, `alphaMap`, `rotation`, `sizeAttenuation` |

When a mesh and a line use the same material, the writer writes one entry for each class.

The writer writes the fields that the three.js class has. For example, only a `MeshPhongMaterial` has `specular` and `shininess`. The reader uses the three.js defaults for a field that is not there. For example, a `MeshPhongMaterial` without `specular` gets `0x111111`. Colors are 24-bit sRGB numbers, as `Color.getHex` gives them.

These fields use three.js's keys and three.js's defaults:

| Fields | Keys |
|---|---|
| Baked light | `aoMap`, `aoMapIntensity`, `lightMap`, `lightMapIntensity` |
| Displacement | `displacementMap`, `displacementScale`, `displacementBias` |
| Other surface fields | `specularMap`, `flatShading`, and `depthPacking` on a `MeshDepthMaterial` |
| Volume | `transmission`, `transmissionMap`, `thickness`, `thicknessMap`, `attenuationColor`, `attenuationDistance`, `dispersion` |
| Specular and clear coat maps | `specularIntensityMap`, `specularColorMap`, `clearcoatMap`, `clearcoatRoughnessMap`, `clearcoatNormalMap`, `clearcoatNormalScale` |
| Sheen | `sheen`, `sheenColor`, `sheenColorMap`, `sheenRoughness`, `sheenRoughnessMap` |
| Thin film | `iridescence`, `iridescenceIOR`, `iridescenceThicknessRange` in nanometers, `iridescenceMap`, `iridescenceThicknessMap` |
| Stretch | `anisotropy`, `anisotropyRotation` in radians, `anisotropyMap` |
| Depth and stencil | `depthFunc`, `depthTest`, `depthWrite`, `colorWrite`, `stencilWrite`, `stencilWriteMask`, `stencilFunc`, `stencilRef`, `stencilFuncMask`, `stencilFail`, `stencilZFail`, `stencilZPass` |
| Polygon offset | `polygonOffset`, `polygonOffsetFactor`, `polygonOffsetUnits` |
| Environment | `envMap`, the uuid of a cube texture. See [Cube textures](#cube-textures). |
| Clipping | `clippingPlanes`, `clipIntersection`, `clipShadows` |
| Distance | `referencePosition`, `nearDistance` and `farDistance` on a `MeshDistanceMaterial` |
| Wide line | `dashOffset` |

Each clipping plane is an object with a `normal` of three numbers and a `constant`. This is the shape that `JSON.stringify` gives a three.js `Plane`. three.js's `Material.toJSON` does not write the clipping, distance and `dashOffset` keys, and its loader ignores them. This port writes them, so that a scene that it reads back renders the same.

The writer writes a map intensity, a displacement scale and a displacement bias only with their map, as `Material.toJSON` does. The reader reads them only with their map. The writer writes `normalScale` and `clearcoatNormalScale` only with their map too, but the reader always reads them. The writer does not write an infinite `attenuationDistance`, because that is the default. The stencil functions and operations use three.js's numbers: `stencilFunc` 519 is `ALWAYS_STENCIL_FUNC`, and `stencilFail` 7680 is `KEEP_STENCIL_OP`.

three.js's `blending` is a number. `NormalBlending`, the default, follows `transparent`. `NoBlending` is `OPAQUE`. `AdditiveBlending`, `SubtractiveBlending` and `MultiplyBlending` are `ADDITIVE`, `SUBTRACTIVE` and `MULTIPLY`.

## Textures

The writer writes each texture with its wrap, its filters, its transform, its color space, its `channel` and an image. The image is a PNG `data:` URL of the full-size level. A texture here runs up from its bottom row, as a three.js texture with `flipY` does. Thus `flipY` is true.

The reader decodes a PNG, a JPEG or a TGA image from a `data:` URL or from a file beside the document. When `flipY` is false, the reader turns the image upside down. `colorSpace` `srgb` is `SRGB`. `srgb-linear` and the empty `NoColorSpace` are `LINEAR`. The minification filter tells whether the texture has a mip chain. The magnification filter gives `NEAREST` or `BILINEAR`.

A `channel` of 1 reads the second set of texture coordinates, `uv1`.

three.js has no alpha mode, so the reader finds it from the use of the texture. A `map`, a background, a `sheenRoughnessMap` or a `specularIntensityMap` gets `COVERAGE`. All other maps get `IGNORED`. A sheen roughness map and a specular intensity map keep their alpha, because the renderer reads the number from the alpha. When a texture has the two uses, the reader builds it two times.

## Cube textures

A cube texture is a texture entry whose image has six URLs. This is how three.js's `Source.toJSON` writes a `CubeTexture`, and how its `ObjectLoader` finds one. The writer writes six PNG `data:` URLs, `CubeReflectionMapping` (301) and `flipY` false.

three.js keeps the six images of a cube in its own layout. The px image is the view along -x, and the nx image is the view along +x. Thus the writer swaps these two faces, and the reader reads the images `SEEN_FROM_OUTSIDE`. See [Textures](Textures). A `flipY` of true turns each image upside down.

A cube texture is one of these:

| Key | Meaning |
|---|---|
| `background` on the scene | A cube background. |
| `environment` on the scene | The scene's `environment`. |
| `envMap` on a material | The cube texture that the surface reflects. |

three.js reads the scene's `environment` only on a standard or physical material without an `envMap`. The reader does the same. A standard or physical material without an `envMap` gets `SCENE_ENVIRONMENT`. Every other class without an `envMap` reflects nothing. A basic, lambert or phong material that reflects the environment here gets the uuid of that cube in its `envMap`.

three.js's renderer prefilters the environment, and each cube that a standard or physical material reflects. Thus the reader builds the PMREM of each of these cubes with `pmrem_from_cube`. The writer does not write the PMREM, because three.js has no key for it. For the same reason, the writer refuses a cube that these surfaces reflect without its PMREM.

## Differences from three.js

- A camera is kept beside the scene, in `ObjectCameras`, because a camera is not a node here.
- A node that carries two things becomes an `Object3D` with child objects. In three.js, each object is one thing.
- A light's `layers` are its own here. The writer writes a light on other layers than its node as a child object.
- The uuids are not random. The same scene gives the same text.
- One material can be a mesh material and a line material here. The writer writes one entry for each three.js class that uses it.
- The writer writes `transparent` false on a `SpriteMaterial`. three.js leaves it out, and then its loader reads a transparent sprite.
- The writer writes a sprite's `center` when it is not the middle. three.js does not write it, and ignores it.
- An LOD level must be a child `Mesh` at the identity, because an `Lod` draws its levels at its own node.
- A skeleton can leave out `boneInverses`, or give an empty list. Then the reader calculates the inverses. three.js's `Skeleton.fromJSON` reads one entry for each bone and fails without them.
- The writer writes a material's clipping planes, a distance material's range and a `dashOffset`. three.js does not write them.
- The writer refuses a standard or physical material that reflects nothing in a scene with an environment. three.js would reflect the environment on it.
- A face of a cube texture is always clamped. The reader does not read the `wrap` of a cube texture.
- The joined geometry of a batched mesh stays in the assets after the reader splits it.

## Not ported

The writer does not write these things, and the reader refuses them:

- Wide lines (`LineSegments2`), which are a three.js addon that `ObjectLoader` does not read. The writer ignores them.
- `CustomBlending`, and a line width in world units.
- A batched mesh with geometries that do not have the same attributes and index, or that have morph targets.
- A mesh with more than one material, and an attribute or an interleaved buffer that is not a `Float32Array`.
- A texture with two different wraps, a mapping that is not `UVMapping`, or a `channel` that is not 0 or 1.
- A cube texture that does not have six images, or a mapping that is not `CubeReflectionMapping`. A cube texture with float faces.
- More than eight clipping planes on a material, or more than eight morph influences on a mesh.
- A depth function, a stencil function or a stencil operation that is not one of three.js's.
- A perspective camera with `zoom`, `filmOffset` or `view`, and an orthographic camera with `view`.

The writer does not write these things, and the reader ignores them:

- A background's `backgroundBlurriness`, `backgroundIntensity` and `backgroundRotation`, and the scene's `environmentIntensity` and `environmentRotation`.
- An `envMap` on a class that does not reflect, for example a `MeshToonMaterial` or a `LineBasicMaterial`.
- `animations`, `shapes`, `skeletons`, `up` and `userData`.
- The material keys that have no field here.
- An LOD's `autoUpdate`, and a batched mesh's sorting, reserved ranges and bounds.
- A camera's `focus` and `filmGauge`, and a texture's `format`, `type` and `premultiplyAlpha`.

## Errors

The writer raises for:

- A thing, a target, a bone or a camera that names a node that is not in the scene.
- A blank texture, or a light or a texture that its own `validate` refuses.
- Custom blending, or a material that blends but is not transparent.
- A material that its own checks refuse, for example a stencil operation that is not one of the eight.
- A line, points or sprite material that is not `BASIC`, or a line width in world units.
- A line mode or a bind mode that is not one of its values.
- A batched mesh with geometries that it cannot join.
- A perspective camera with a view shift.
- A cube texture with float faces, or with faces that do not have the same filter, color space and mip chain.
- A cube without its PMREM that the environment or a standard or physical material reflects.
- A standard or physical material that reflects nothing in a scene with an environment.

The reader raises for a document that is not JSON, for each refusal in [Not ported](#not-ported), and for:

- A uuid that is named two times, or that names nothing.
- An object, geometry, material or fog type that has no counterpart here.
- A shadow map that is not square, or a shadow camera that is not square about its axis.
- An LOD level that is not a child `Mesh` at the identity without children.
- A bone uuid that no object has.
- A skeleton with a `boneInverses` list that is not empty and has fewer entries than bones. three.js's `Skeleton.fromJSON` fails on it too.
- An `envMap` or an `environment` that names a texture that is not a cube.
- A `geometryInfo` or an instance that names data that is not there.
- Each value that the builders refuse, for example a negative intensity.

## Example

`tests/test_object_json.mojo` writes a scene with each kind of thing and reads it back. It also reads a document in the shape of three.js's own `scene.toJSON()` output.

`tests/test_object_json_objects.mojo` renders a scene with each newer material field and each other object. It writes the scene, reads it back and renders it again. The two images are the same.

`tests/test_object_json_environment.mojo` does the same for cube textures, environment maps, clipping planes, a distance range and morph influences.
