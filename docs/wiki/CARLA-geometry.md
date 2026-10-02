# CARLA geometry

Eight modules in `extensions/carla/` port CARLA's engine-independent `geom/`, `image/` and `pointcloud/` code. They give CARLA's math helpers, bounding boxes, map projections, R-trees, meshes, mesh simplification, point cloud files and image conversions. The numbers match CARLA's for the same inputs.

The port follows the `LibCarla` source at commit `1360bb9`. See [CARLA](CARLA) for the roads, sensors and frames.

## Modules

| Module | CARLA source | What it gives |
|---|---|---|
| `math` | `geom/Math.cpp`, the vector headers, `Quaternion.h` | Distances to segments and arcs, 2D helpers, `Vector3DInt`, unit vectors, quaternion conversions. |
| `bounding_box` | `geom/BoundingBox.h` | `BoundingBox`: `contains`, the local and world vertices. |
| `geo` | `geom/GeoProjection*`, `GeoReferenceParser.cpp` | `GeoLocation`, four projections, the OpenDRIVE `geoReference` parser. |
| `rtree` | `geom/Rtree.h` | `PointCloudRtree` and `SegmentCloudRtree`: nearest k, with a filter, and box queries. |
| `mesh` | `geom/Mesh.cpp` | `CarlaMesh`: strips, fans, materials, OBJ, PLY, a `BufferGeometry`. |
| `simplification` | `geom/Simplification.cpp`, `third-party/simplify` | Quadric edge-collapse simplification. |
| `pointcloud` | `pointcloud/PointCloudIO.h` | The PLY file of a LiDAR measurement. |
| `image_convert` | `image/ColorConverter.h`, `ImageConverter.h` | Depth, logarithmic depth and CityScapes conversions, instance, normals and optical flow decoders. |

## What the port reuses

The modules use ThreeMojo's types where ThreeMojo has one. They add only what CARLA needs and ThreeMojo lacks.

- A CARLA `Vector3D` or `Location` is a `math.vector3.Vector3` in meters. A `Vector2D` is a `math.vector2.Vector2`.
- A CARLA `Quaternion` is a `math.quaternion.Quaternion`. The product, the conjugate and `RotatedVector` are its own.
- `Math::Clamp` and `Math::LinearLerp` are `math.utils.clamp` and `math.utils.lerp`.
- The forward, right and up vectors are `CarlaRotation.forward_vector`, `right_vector` and `up_vector`.
- `BoundingBox` is a thin layer over `math.obb.OBB`. `BoundingBox.to_obb` gives the oriented box.
- The R-tree boxes are `math.bounds.Box3`.
- `CarlaMesh.to_buffer_geometry` gives a `core.buffer_geometry.BufferGeometry`. `CarlaMesh.generate_ply` writes it with `exporters.ply.export_ply`.
- `image_convert` applies the pixel steps of `extensions.carla.sensor` to a `render.framebuffer.Framebuffer`.

## Measure a distance

`distance_segment_to_point` and `distance_arc_to_point` project a point on a lane segment in the x-y plane. Each returns two lengths: the distance along the segment and the distance to it.

```mojo
from extensions.carla.math import distance_segment_to_point
from math.vector3 import Vector3

var along_and_off = distance_segment_to_point(
    Vector3(1, 2, 0), Vector3(0, 0, 0), Vector3(4, 0, 0)
)
# along_and_off[0] is 1 meter, along_and_off[1] is 2 meters.
```

An arc has a length, a heading and a curvature. The heading is an `Angle` and the curvature is an `InverseLength`.

## Integer vector norms

`Vector3DInt.squared_length` returns an exact `UInt64`. The former return type was `Int64`, which could overflow for valid components. Each signed 32-bit component is squared in `Int64`. Each square converts to `UInt64` before addition. The largest sum is 13835058055282163712, for three components of -2147483648.

`Vector3DInt.length` returns a finite, nonnegative `Float64`. It converts the exact sum to `Float64`, then takes the square root. The relative error is below 2^-51. Zero gives an exact zero. The other integer vector operations keep their existing contracts.

## Normalize and compare rotations

`CarlaRotation.normalized` reduces each finite `Float32` angle into [-180, 180) degrees. Both endpoints become -180. Whole turns reduce to zero with the input sign. The remainder is stable at large angles: 1e10 degrees becomes -80 degrees. A negative angle near zero keeps its low bits.

`rotations_equal` uses the same reduction for each angle. Signed zeros compare equal. A nonfinite angle becomes NaN during normalization. A rotation with a nonfinite angle compares unequal, including to itself. This rule also applies to `transforms_equal` and bounding box equality.

## Read a geolocation

A map's projection turns a CARLA location into a latitude, a longitude and an altitude. The GNSS sensor and `Map::TransformToGeolocation` use this math.

```mojo
from extensions.carla.geo import parse_geo_reference
from loaders.xml import parse_xml
from math.vector3 import Vector3

var document = parse_xml(xodr_text)
var projection_and_reference = parse_geo_reference(document)
var projection = projection_and_reference[0].copy()
var geo = projection.transform_to_geo_location(Vector3(100, -200, 3))
```

`parse_geo_reference` reads `OpenDRIVE/header/geoReference` and the attributes of `OpenDRIVE/header/offset`. The PROJ string picks the projection:

| `+proj` | Projection | Parameters |
|---|---|---|
| `tmerc` | `TRANSVERSE_MERCATOR` | `lat_0`, `lon_0`, `k`, `x_0`, `y_0` |
| `utm` | `UNIVERSAL_TRANSVERSE_MERCATOR` | `zone`, `south`, and the header offset |
| `merc` | `WEB_MERCATOR` | none |
| `lcc` | `LAMBERT_CONFORMAL_CONIC` | `lat_0`, `lat_1`, `lat_2`, `lon_0`, `x_0`, `y_0` |

A supplied UTM `zone` is read once with `stod`, including decimal exponents and ignored text after the numeric prefix. The value must be finite, at least 1 and less than 61 before integer conversion. Fractional values still truncate toward zero: 1.5 selects zone 1, and 60.5 selects zone 60. A value below 1 or at least 61 raises an error. Large and nonfinite values cannot wrap into a valid zone.

The returned reference longitude uses the selected zone's central meridian, 6 times the zone minus 183 degrees. This fixes the former fractional reference: 31.5 now gives zone 31 and 3 degrees, rather than 6 degrees. Exponents now select the same numeric value for the zone and reference: `3.1e1` selects zone 31. With no zone, the existing default stays zone 31 with a zero reference.

Another value, or no `+proj`, gives the default transverse Mercator. The ellipsoid comes from `ellps` or `datum`, then `a`, `b`, `f` and `rf`. Without any of them it is WGS 84.

A latitude, a longitude and an altitude are `Float64` numbers. An `Angle` holds a `Float32`, which keeps a latitude to about a meter only. The field names say the units: `latitude_degrees`, `altitude_meters`.

The projections call the C library's `log`, `exp` and `pow`. Mojo's own functions are off by up to 1e-11, which is tens of micrometers on the Earth.

## Find the nearest segment

`SegmentCloudRtree` holds segments with two whole numbers each. The numbers are the caller's own, such as indices into a list of waypoints.

```mojo
from extensions.carla.rtree import SegmentCloudRtree
from math.vector3 import Vector3

var tree = SegmentCloudRtree()
tree.insert_element(Vector3(0, 0, 0), Vector3(10, 0, 0), 0, 1)
var nearest = tree.get_nearest_neighbours(Vector3(5, 2, 0), 1)
```

A filter is a struct with an `accepts` method, as `PointFilter` and `SegmentFilter` define. `get_intersections` returns the segments that meet a `Box3`.

The results come nearest first. Entries at the same distance come in the order of insertion. Boost leaves this order open, so CARLA code that reads only the first result gets the same answer.

## Build a mesh

`CarlaMesh` keeps CARLA's lists: vertices, normals, UVs, indices counted from one, and named materials. `add_triangle_strip` and `add_triangle_fan` turn the same way as CARLA's.

- `generate_obj` and `generate_obj_for_recast` write CARLA's text with its comments, its `usemtl` names and six digits after the point.
- `generate_ply` writes an ASCII PLY file through ThreeMojo's exporter.
- `to_buffer_geometry` gives a `BufferGeometry` in the three.js frame, with one group for each material.
- `concat_mesh` joins two meshes and stitches the seam, as CARLA's `ConcatMesh` does.

`Simplification(0.5).simplificate(mesh)` keeps about half of the triangles. It is Forstmann's quadric simplification, which CARLA keeps in its tree. Border edges do not collapse.

## Write a point cloud

`dump` writes detections as CARLA's ASCII PLY text, with four digits after the point. `save_to_disk` writes the file and changes the extension to `.ply`.

```mojo
from extensions.carla.pointcloud import LidarDetection, save_to_disk

var points = List[LidarDetection]()
for point in scan.points:
    points.append(LidarDetection.from_lidar_point(point))
_ = save_to_disk("out/scan.ply", points)
```

`SemanticLidarDetection` writes `CosAngle`, `ObjIdx` and `ObjTag`. Another detection type conforms to `PlyDetection`.

## Convert an image

`convert_in_place` applies a `ColorConverter` to every pixel: `RAW`, `DEPTH`, `LOGARITHMIC_DEPTH` or `CITY_SCAPES_PALETTE`. A gray level g becomes the byte of g times 255 plus 0.5, as Boost.GIL writes it.

- `encode_instance` and the two `decode_instance_` functions read the instance segmentation camera. Red is the tag, and green and blue hold the 16-bit `InstanceId`.
- `decode_normal` reads the normals camera. Each channel c is c / 255 * 2 - 1.
- `encode_flow_pixel` and `encode_flow_image` color an optical flow image with CARLA's color wheel.

## Kinds

Each kind is a type with `is_valid`, and the functions that read one refuse a value that is not valid.

| Type | Values |
|---|---|
| `ProjectionType` | `TRANSVERSE_MERCATOR`, `UNIVERSAL_TRANSVERSE_MERCATOR`, `WEB_MERCATOR`, `LAMBERT_CONFORMAL_CONIC` |
| `UtmZone` | 1 to 60 |
| `ColorConverter` | `RAW`, `DEPTH`, `LOGARITHMIC_DEPTH`, `CITY_SCAPES_PALETTE` |
| `InstanceId` | 0 to 65535 |

## Differences from CARLA

The port refuses input where CARLA reads out of bounds, divides by zero or wraps around. It also fixes some behavior that has no use.

- A bounding box half size must be finite and zero or more.
- A UTM zone must be from 1 to 60 after the checked fractional conversion above. CARLA takes any zone.
- `stod` does not read a hexadecimal float. It reads the zero before the `x`.
- `CarlaMesh.generate_ply` writes a PLY file. CARLA's `GeneratePLY` returns an empty string.
- `CarlaMesh.concat_mesh` refuses a link count larger than either mesh.
- `Simplification` refuses a negative rate, and a mesh with fewer than two indices.
- A red channel of 30 or more is not a semantic tag. The CityScapes conversion refuses it, and CARLA wraps it.
- An empty point cloud writes its header from the type.

`BoundingBox.contains` does not apply the box's own rotation. CARLA's `Contains` does not either, so the port keeps this.

Mojo fuses a multiply and an add into one step, which rounds once. The simplifier rounds each product on its own, as the C++ does, so the same edges collapse.

## Not ported

- `ImageIO` and `ImageView` read and write image files with Boost.GIL, libpng and libjpeg. ThreeMojo's own image loaders and writers do this.
- `Vector3D`'s `operator/(float, Vector3D)` divides the vector by the number, which reads as the opposite.
- `CubicPolynomial.h` is in `extensions/carla/polynomial.mojo`. `Rotation.h` and `Transform.h` are in `extensions/carla/transform.mojo`.
