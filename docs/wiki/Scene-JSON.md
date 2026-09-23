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
| `geometries`, `materials`, `textures`, `images` | The libraries. Each entry has a `uuid`. Each thing is written one time, also when two meshes use it. |
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
| `AmbientLight`, `DirectionalLight`, `PointLight`, `HemisphereLight`, `SpotLight`, `RectAreaLight`, `LightProbe` | A `Light` of that kind, on the layers of the object. A `LightProbe` reads its 27 `sh` numbers. |
| `PerspectiveCamera`, `OrthographicCamera` | A camera that rides the node, in `ObjectModel.cameras`. |

A `Scene` root is not a node. Its `fog` becomes the fog of the scene. A number in `background` becomes a color background. A string in `background` names a texture background.

A light's `target` names an object by its uuid. When no object has that uuid, the target is the origin. This is the default target of three.js. A light's `shadow` gives `bias`, `normalBias`, `radius`, `mapSize` and the planes of its camera. A directional light's shadow camera must be square about its axis, because `LightShadow` holds one `extent`.

The writer makes the same objects. A node that carries one thing becomes that thing. A node that carries more than one thing becomes an `Object3D`, with one child object for each thing at the identity. A light or a camera on other layers than its node is also a child object. A light with no node, as an ambient light usually is, is a child of the scene. The reader then gives that light a node of its own.

A camera is not a scene node in this port. Put the cameras in an `ObjectCameras`, and attach each one to a node first. The writer refuses a camera that rides no node.

## Geometry

The writer writes each geometry as a `BufferGeometry`. Each attribute is a `Float32Array`. The index is a `Uint16Array` up to 65535 vertices, and a `Uint32Array` above that, as three.js chooses. The groups and the morph targets are written too.

The reader reads a `BufferGeometry` with `Float32Array` attributes, an index, groups and morph targets. It also builds three parametric types from their parameters:

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

The writer writes the fields that the three.js class has. For example, only a `MeshPhongMaterial` has `specular` and `shininess`. The reader uses the three.js defaults for a field that is not there. For example, a `MeshPhongMaterial` without `specular` gets `0x111111`. Colors are 24-bit sRGB numbers, as `Color.getHex` gives them.

three.js's `blending` is a number. `NormalBlending`, the default, follows `transparent`. `NoBlending` is `OPAQUE`. `AdditiveBlending`, `SubtractiveBlending` and `MultiplyBlending` are `ADDITIVE`, `SUBTRACTIVE` and `MULTIPLY`.

## Textures

The writer writes each texture with its wrap, its filters, its transform, its color space and an image. The image is a PNG `data:` URL of the full-size level. A texture here runs up from its bottom row, as a three.js texture with `flipY` does. Thus `flipY` is true.

The reader decodes a PNG, a JPEG or a TGA image from a `data:` URL or from a file beside the document. When `flipY` is false, the reader turns the image upside down. `colorSpace` `srgb` is `SRGB`. `srgb-linear` and the empty `NoColorSpace` are `LINEAR`. The minification filter tells whether the texture has a mip chain. The magnification filter gives `NEAREST` or `BILINEAR`.

three.js has no alpha mode, so the reader finds it from the use of the texture. A `map` or a background gets `COVERAGE`. A data map gets `IGNORED`: an alpha, emissive, gradient, matcap, roughness, metalness, normal or bump map. When a texture has the two uses, the reader builds it two times.

## Differences from three.js

- A camera is kept beside the scene, in `ObjectCameras`, because a camera is not a node here.
- A node that carries two things becomes an `Object3D` with child objects. In three.js, each object is one thing.
- A light's `layers` are its own here. The writer writes a light on other layers than its node as a child object.
- The uuids are not random. The same scene gives the same text.

## Not ported

The writer does not write these things, and the reader refuses them:

- Lines, points, sprites, LODs, batched meshes and skinned meshes.
- `CustomBlending`.
- A mesh with more than one material, and an interleaved attribute or one that is not a `Float32Array`.
- A texture with two different wraps, a mapping that is not `UVMapping`, or a `channel` that is not zero.
- A perspective camera with `zoom`, `filmOffset` or `view`, and an orthographic camera with `view`.

The writer does not write these things, and the reader ignores them:

- Cube textures: a cube background, the scene's `environment` and a material's `envMap`.
- `animations`, `shapes`, `skeletons`, `up` and `userData`.
- `lightMap`, `aoMap`, `displacementMap`, `specularMap`, `flatShading`, the depth and stencil settings, and the keys of `MeshPhysicalMaterial` after the clear coat.
- A camera's `focus` and `filmGauge`, and a texture's `format`, `type` and `premultiplyAlpha`.

The writer also does not write a mesh's morph influences, a material's clipping planes, or the dash, point and sprite settings.

## Errors

The writer raises for:

- A mesh, a light, a target or a camera that names a node that is not in the scene.
- A blank texture, or a light or a texture that its own `validate` refuses.
- Custom blending, or a material that blends but is not transparent.
- A perspective camera with a view shift.

The reader raises for a document that is not JSON, for each refusal in [Not ported](#not-ported), and for:

- A uuid that is named two times, or that names nothing.
- An object, geometry, material or fog type that has no counterpart here.
- A shadow map that is not square, or a shadow camera that is not square about its axis.
- Each value that the builders refuse, for example a negative intensity.

## Example

`tests/test_object_json.mojo` writes a scene with each kind of thing and reads it back. It also reads a document in the shape of three.js's own `scene.toJSON()` output.
