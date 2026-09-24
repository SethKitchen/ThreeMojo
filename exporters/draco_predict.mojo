# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The attribute values of a Draco file as Draco's encoder writes them,
from Draco 1.5.6: the other half of `loaders.draco_attributes`.

- `attributes/attribute_quantization_transform.cc` and
  `core/quantization_utils`: `quantization_of` and `quantize`, which turn
  floats into integers of so many bits across the attribute's range.
- `attributes/attribute_octahedron_transform.cc` and
  `compression/attributes/normal_compression_utils.h`: `octahedral`,
  which folds unit normals onto an octahedron.
- `compression/attributes/prediction_schemes`: the encoders of the
  difference, parallelogram, constrained multi-parallelogram, texture
  coordinate and geometric normal predictions, with the wrap and the
  canonicalized octahedron transforms.
- `compression/attributes/sequential_integer_attribute_encoder.cc`:
  `encode_integers`, which writes the corrections and the prediction's
  data.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**Arithmetic.** The floats of quantization are `Float32` and those of
the octahedron are `Float64`, as in Draco. Each product is rounded
before a sum uses it. The integers are 32-bit where Draco's are, and a
division rounds toward zero.
"""

from exporters.draco_connectivity import EncodingData
from exporters.draco_writer import (
    DracoWriter,
    EntropyTracker,
    RAnsBitEncoder,
    binary_entropy,
    encode_symbols,
    entropy_data_bits,
    entropy_table_bits,
    signed_to_symbol,
)
from loaders.draco_attributes import (
    DRACO_CONSTRAINED_MULTI_PARALLELOGRAM,
    DRACO_DIFFERENCE,
    DRACO_GEOMETRIC_NORMAL,
    DRACO_OCTAHEDRON_CANONICALIZED,
    DRACO_PARALLELOGRAM,
    DRACO_TEX_COORDS_PORTABLE,
    DRACO_WRAP,
    DracoAttributeType,
    DracoPrediction,
    DracoTransform,
    Octahedron,
    product32,
)
from loaders.draco_buffer import draco_require, to_int32, truncated_divide
from loaders.draco_mesh import NONE, DracoCornerTable
from loaders.vrml_geometry import product
from std.math import ceil, floor, isinf, isnan

# The most parallelograms the constrained prediction mixes.
comptime _MAX_PARALLELOGRAMS = 4
# The largest `Int`, as C++'s `int64_t`.
comptime _INT64_MAX = 0x7FFFFFFFFFFFFFFF


struct EncoderAttribute(Copyable, Movable):
    """One attribute of the geometry that Draco's encoder is given.

    Draco's `PointAttribute` of `Float32` values: the distinct values,
    and the value of each point.
    """

    var attribute_type: DracoAttributeType
    """What the attribute is for."""
    var components: Int
    """The components of each value."""
    var values: List[Float32]
    """The values, `components` to each."""
    var point_map: List[Int]
    """The value of each point."""

    def __init__(
        out self,
        attribute_type: DracoAttributeType,
        components: Int,
        var values: List[Float32],
    ):
        """Keep values, one for each point.

        Args:
            attribute_type: What the attribute is for.
            components: The components of each value.
            values: The values, one for each point.
        """
        self.attribute_type = attribute_type
        self.components = components
        var count = len(values) // components
        self.values = values^
        self.point_map = List[Int](capacity=count)
        # An attribute has a value: the loop runs.
        for i in range(count):  # pragma: no branch
            self.point_map.append(i)

    def count(self) -> Int:
        """Return the values.

        Returns:
            The count of distinct values.
        """
        return len(self.values) // self.components

    def at(self, value: Int, component: Int) -> Float32:
        """Return one component of a value.

        Args:
            value: The value.
            component: The component.

        Returns:
            The component.
        """
        return self.values[value * self.components + component]


struct Quantization(Copyable, Movable):
    """The parameters of Draco's quantization of an attribute."""

    var bits: Int
    """The bits of each quantized component."""
    var minimums: List[Float32]
    """The smallest value of each component."""
    var range: Float32
    """The largest spread of any component; one when all are zero."""

    def __init__(
        out self, bits: Int, var minimums: List[Float32], range: Float32
    ):
        """Keep the parameters.

        Args:
            bits: The bits.
            minimums: The minimum of each component.
            range: The range.
        """
        self.bits = bits
        self.minimums = minimums^
        self.range = range

    def write(self, mut out: DracoWriter):
        """Write the parameters as Draco does: the minimums, the range and
        the bits.

        Args:
            out: Where to write them.
        """
        # A value has components: the loop runs.
        for m in self.minimums:  # pragma: no branch
            out.f32(m)
        out.f32(self.range)
        out.u8(self.bits)


def quantization_of(
    attribute: EncoderAttribute, bits: Int
) raises -> Quantization:
    """Return the quantization of an attribute's values.

    Draco's `AttributeQuantizationTransform::ComputeParameters`.

    Args:
        attribute: The attribute.
        bits: The bits of each quantized component, from 1 to 30.

    Returns:
        The minimum of each component and the largest spread.

    Raises:
        Error: If the bits are out of range, or a value is not finite, as
            Draco fails.
    """
    draco_require(bits >= 1 and bits <= 30, "quantization bits are not 1 to 30")
    var components = attribute.components
    var minimums = List[Float32](capacity=components)
    var maximums = List[Float32](capacity=components)
    # A value has components: the loop runs.
    for c in range(components):  # pragma: no branch
        minimums.append(attribute.at(0, c))
        maximums.append(attribute.at(0, c))
    for v in range(1, attribute.count()):
        # A value has components: the loop runs.
        for c in range(components):  # pragma: no branch
            var x = attribute.at(v, c)
            if minimums[c] > x:
                minimums[c] = x
            if maximums[c] < x:
                maximums[c] = x
    var widest = Float32(0)
    # A value has components: the loop runs.
    for c in range(components):  # pragma: no branch
        draco_require(
            _finite(minimums[c]) and _finite(maximums[c]),
            "a value to quantize is not finite",
        )
        var spread = maximums[c] - minimums[c]
        if spread > widest:
            widest = spread
    if widest == 0:
        widest = 1
    return Quantization(bits, minimums^, widest)


def wasm_i32(x: Float64) -> Int:
    """Return a float cast to a 32-bit integer as Draco's WebAssembly
    build casts it.

    LLVM lowers the cast for WebAssembly without its non-trapping
    conversions: it truncates a value inside the range of the type, and
    gives the smallest integer for any other value and for `NaN`.

    Args:
        x: The float.

    Returns:
        The integer.
    """
    if abs(x) < 2147483648.0:
        return Int(x)
    return -2147483648


def _finite(x: Float32) -> Bool:
    """True if a float is neither `NaN` nor infinite."""
    return not isnan(x) and not isinf(x)


def quantize(
    attribute: EncoderAttribute, q: Quantization, points: List[Int]
) -> List[Int]:
    """Return the quantized values of the points of a sequence.

    Draco's `GeneratePortableAttribute` with its `Quantizer`: each
    component less its minimum, times `(2^bits - 1) / range`, rounded
    down after adding a half, all in `Float32`.

    Args:
        attribute: The attribute.
        q: The quantization.
        points: The points, in the order their values are stored.

    Returns:
        The integers, `components` to each point.
    """
    var inverse = Float32((1 << q.bits) - 1) / q.range
    var out = List[Int](capacity=len(points) * attribute.components)
    # A sequence has a point: the loop runs.
    for p in points:  # pragma: no branch
        var value = attribute.point_map[p]
        # A value has components: the loop runs.
        for c in range(attribute.components):  # pragma: no branch
            var x = attribute.at(value, c) - q.minimums[c]
            var rounded = floor(product32(x, inverse) + Float32(0.5))
            out.append(wasm_i32(Float64(rounded)))
    return out^


def octahedral(
    attribute: EncoderAttribute, bits: Int, points: List[Int]
) raises -> List[Int]:
    """Return the normals of the points of a sequence, folded onto an
    octahedron.

    Draco's `AttributeOctahedronTransform::GeneratePortableAttribute`
    with `FloatVectorToQuantizedOctahedralCoords`. A vector whose
    components sum to 1e-6 or less in size folds as (1, 0, 0).

    Args:
        attribute: The normals, three components each.
        bits: The bits of each coordinate, from 2 to 30.
        points: The points, in the order their values are stored.

    Returns:
        Two coordinates for each point.

    Raises:
        Error: If the bits are out of range, as Draco fails.
    """
    var o = Octahedron(bits)
    var center = Float64(o.center)
    var out = List[Int](capacity=2 * len(points))
    # A sequence has a point: the loop runs.
    for p in points:  # pragma: no branch
        var value = attribute.point_map[p]
        var x = Float64(attribute.at(value, 0))
        var y = Float64(attribute.at(value, 1))
        var z = Float64(attribute.at(value, 2))
        var sum = abs(x) + abs(y) + abs(z)
        # Draco scales an infinite normal to `NaN`, and its integers then
        # overflow; three.js writes whatever that gives.
        draco_require(not isinf(sum), "a normal is infinite")
        var sx = 1.0
        var sy = 0.0
        var sz = 0.0
        if sum > 1e-6:
            var scale = 1.0 / sum
            sx = product(x, scale)
            sy = product(y, scale)
            sz = product(z, scale)
        var ix = wasm_i32(floor(product(sx, center) + 0.5))
        var iy = wasm_i32(floor(product(sy, center) + 0.5))
        var iz = o.center - abs(ix) - abs(iy)
        if iz < 0:
            # Only two positive components can round past the center, so
            # Draco's other case, `iy -= iz`, never runs; it is kept here
            # as an expression.
            iy = iy + iz if iy > 0 else iy - iz
            iz = 0
        if sz < 0:
            iz = -iz
        var coords = o.vector_to_coords(ix, iy, iz)
        out.append(coords[0])
        out.append(coords[1])
    return out^


struct Positions(Copyable, Movable):
    """The quantized positions that a prediction reads.

    Draco's portable position attribute of a parent encoder.
    """

    var values: List[Int]
    """Three integers for each stored position."""
    var point_map: List[Int]
    """The stored position of each point."""

    def __init__(out self, var values: List[Int], var point_map: List[Int]):
        """Keep the positions.

        Args:
            values: The quantized positions, in their stored order.
            point_map: The stored position of each point.
        """
        self.values = values^
        self.point_map = point_map^

    def at(self, point: Int) -> List[Int]:
        """Return the quantized position of a point.

        Args:
            point: The point.

        Returns:
            Its three integers.
        """
        var at = 3 * self.point_map[point]
        return [self.values[at], self.values[at + 1], self.values[at + 2]]


struct MeshData(Copyable, Movable):
    """What a mesh prediction needs from the connectivity.

    Draco's `MeshPredictionSchemeData`.
    """

    var table: DracoCornerTable
    """The table of the attribute: the mesh's or its own."""
    var order: EncodingData
    """The order in which the attribute's values are stored."""

    def __init__(
        out self, var table: DracoCornerTable, var order: EncodingData
    ):
        """Keep the table and the order.

        Args:
            table: The table.
            order: The order.
        """
        self.table = table^
        self.order = order^


struct _Transform(Copyable, Movable):
    """Draco's wrap and canonicalized octahedron encoding transforms."""

    var kind: DracoTransform
    var components: Int
    var min_value: Int
    var max_value: Int
    var max_dif: Int
    var max_correction: Int
    var min_correction: Int
    var octahedron: Octahedron

    def __init__(
        out self, kind: DracoTransform, components: Int, bits: Int
    ) raises:
        self.kind = kind
        self.components = components
        self.min_value = 0
        self.max_value = 0
        self.max_dif = 0
        self.max_correction = 0
        self.min_correction = 0
        self.octahedron = Octahedron(max(bits, 2))

    def init(mut self, values: List[Int]) raises:
        """Draco's `Init`: the range of the values, for the wrap. Draco
        goes on with a range of 2^31 or more, and then fails or writes a
        file its decoder refuses; this refuses it."""
        if self.kind != DRACO_WRAP:
            return
        var low = values[0]
        var high = low
        # A value to wrap has two components or more: the loop runs.
        for i in range(1, len(values)):  # pragma: no branch
            if values[i] < low:
                low = values[i]
            elif values[i] > high:
                high = values[i]
        draco_require(high - low < 0x7FFFFFFF, "a wrap range is too wide")
        self.min_value = low
        self.max_value = high
        self.max_dif = 1 + high - low
        self.max_correction = self.max_dif // 2
        self.min_correction = -self.max_correction
        if self.max_dif & 1 == 0:
            self.max_correction -= 1

    def correct(
        self, values: List[Int], offset: Int, predicted: List[Int]
    ) -> List[Int]:
        """Draco's `ComputeCorrection`: the value at `offset` less the
        prediction, wrapped or folded."""
        var out = List[Int](capacity=self.components)
        if self.kind == DRACO_WRAP:
            for c in range(self.components):  # pragma: no branch
                var p = min(max(predicted[c], self.min_value), self.max_value)
                var corr = to_int32(values[offset + c] - p)
                if corr < self.min_correction:
                    corr += self.max_dif
                elif corr > self.max_correction:
                    corr -= self.max_dif
                out.append(corr)
            return out^
        ref o = self.octahedron
        var s = values[offset] - o.center
        var t = values[offset + 1] - o.center
        var ps = predicted[0] - o.center
        var pt = predicted[1] - o.center
        if not o.in_diamond(ps, pt):
            (s, t) = o.invert_diamond(s, t)
            (ps, pt) = o.invert_diamond(ps, pt)
        var bottom_left = (ps == 0 and pt == 0) or (ps < 0 and pt <= 0)
        if not bottom_left:
            var count = _rotation_count(ps, pt)
            (s, t) = _rotate(s, t, count)
            (ps, pt) = _rotate(ps, pt, count)
        out.append(_positive(o, s - ps))
        out.append(_positive(o, t - pt))
        return out^

    def write(self, mut out: DracoWriter):
        """Draco's `EncodeTransformData`."""
        if self.kind == DRACO_WRAP:
            out.u32(self.min_value)
            out.u32(self.max_value)
            return
        out.u32(self.octahedron.max_quantized)
        out.u32(self.octahedron.center)


def _positive(o: Octahedron, x: Int) -> Int:
    """Draco's `MakePositive`."""
    if x < 0:
        return x + o.max_quantized
    return x


def _rotation_count(s: Int, t: Int) -> Int:
    """Draco's `GetRotationCount`, for a pair not in the bottom left."""
    if s == 0:
        return 3 if t > 0 else 1
    if s > 0:
        return 2 if t >= 0 else 1
    return 3


def _rotate(s: Int, t: Int, count: Int) -> Tuple[Int, Int]:
    """Draco's `RotatePoint`, by a quarter turn `count` times."""
    if count == 1:
        return (t, -s)
    if count == 2:
        return (-s, -t)
    return (-t, s)


def _parallelogram(
    p: Int,
    corner: Int,
    data: MeshData,
    values: List[Int],
    components: Int,
) -> Optional[List[Int]]:
    """Draco's `ComputeParallelogramPrediction`, from the stored values."""
    var opposite = data.table.opposite(corner)
    if opposite == NONE:
        return None
    ref map = data.order.vertex_values
    var o = map[data.table.vertex(opposite)]
    var n = map[data.table.vertex(data.table.next(opposite))]
    var r = map[data.table.vertex(data.table.previous(opposite))]
    if o >= p or n >= p or r >= p:
        return None
    var out = List[Int](capacity=components)
    for c in range(components):  # pragma: no branch
        out.append(
            to_int32(
                values[n * components + c]
                + values[r * components + c]
                - values[o * components + c]
            )
        )
    return out^


def _previous(values: List[Int], p: Int, components: Int) -> List[Int]:
    """The stored value before value `p`."""
    var out = List[Int](capacity=components)
    for c in range(components):  # pragma: no branch
        out.append(values[(p - 1) * components + c])
    return out^


struct _Scheme(Movable):
    """A prediction as its encoder runs: the corrections, and the data it
    writes after them."""

    var method: DracoPrediction
    var transform: _Transform
    var creases: List[List[Bool]]
    var orientations: List[Bool]
    var flips: RAnsBitEncoder

    def __init__(out self, method: DracoPrediction, var transform: _Transform):
        self.method = method
        self.transform = transform^
        self.creases = List[List[Bool]]()
        for _ in range(_MAX_PARALLELOGRAMS):  # pragma: no branch
            self.creases.append(List[Bool]())
        self.orientations = List[Bool]()
        self.flips = RAnsBitEncoder()

    def corrections(
        mut self,
        values: List[Int],
        components: Int,
        mesh: Optional[MeshData],
        positions: Optional[Positions],
    ) raises -> List[Int]:
        """Draco's `ComputeCorrectionValues`."""
        self.transform.init(values)
        var count = len(values) // components
        var out = List[Int](length=len(values), fill=0)
        if self.method == DRACO_DIFFERENCE:
            # A sequence has a point: the loop runs.
            for p in range(count):  # pragma: no branch
                var predicted = List[Int](length=components, fill=0)
                if p > 0:
                    predicted = _previous(values, p, components)
                self._store(out, values, p, components, predicted)
            return out^
        ref data = mesh.value()
        if self.method == DRACO_PARALLELOGRAM:
            # A sequence has a point: the loop runs.
            for p in range(count):  # pragma: no branch
                var predicted = List[Int](length=components, fill=0)
                if p > 0:
                    var one = _parallelogram(
                        p, data.order.value_corners[p], data, values, components
                    )
                    if Bool(one):
                        predicted = one.value().copy()
                    else:
                        predicted = _previous(values, p, components)
                self._store(out, values, p, components, predicted)
            return out^
        if self.method == DRACO_CONSTRAINED_MULTI_PARALLELOGRAM:
            self._constrained(out, values, components, data)
            return out^
        if self.method == DRACO_TEX_COORDS_PORTABLE:
            var p = count - 1
            while p >= 0:
                var predicted = self._tex_coord(
                    p, values, data, positions.value()
                )
                self._store(out, values, p, components, predicted)
                p -= 1
            return out^
        self._normals(out, values, data, positions.value())
        return out^

    def _store(
        self,
        mut out: List[Int],
        values: List[Int],
        p: Int,
        components: Int,
        predicted: List[Int],
    ):
        """Store the correction of value `p`."""
        var corr = self.transform.correct(values, p * components, predicted)
        for c in range(components):  # pragma: no branch
            out[p * components + c] = corr[c]

    def _constrained(
        mut self,
        mut out: List[Int],
        values: List[Int],
        components: Int,
        data: MeshData,
    ) raises:
        """Draco's `MeshPredictionSchemeConstrainedMultiParallelogramEncoder`:
        for each value, the mix of its parallelograms whose residuals the
        entropy estimate says cost the fewest bits."""
        var tracker = EntropyTracker()
        var used_totals: List[Int] = [0, 0, 0, 0]
        var totals: List[Int] = [0, 0, 0, 0]
        var p = len(data.order.value_corners) - 1
        while p > 0:
            var start = data.order.value_corners[p]
            var found = List[List[Int]]()
            var corner = start
            var first_pass = True
            while corner != NONE:
                var one = _parallelogram(p, corner, data, values, components)
                if Bool(one):
                    found.append(one.value().copy())
                    if len(found) == _MAX_PARALLELOGRAMS:
                        break
                if first_pass:
                    corner = data.table.swing_left(corner)
                else:
                    corner = data.table.swing_right(corner)
                if corner == start:
                    break
                if corner == NONE and first_pass:
                    first_pass = False
                    corner = data.table.swing_right(start)
            var n = len(found)
            var offset = p * components
            var previous = _previous(values, p, components)
            var best_value = previous.copy()
            var best = _error(tracker, previous, values, offset, components)
            if n > 0:
                totals[n - 1] += n
                best.bits += _overhead(used_totals[n - 1], totals[n - 1])
            var best_configuration = 0
            var best_used = 0
            for used in range(1, n + 1):
                var excluded = List[Bool](length=n, fill=True)
                # A mix uses one parallelogram or more: the loop runs.
                for j in range(used):  # pragma: no branch
                    excluded[j] = False
                while True:
                    var mix = List[Int](length=components, fill=0)
                    var configuration = 0
                    # A mix is of one parallelogram or more: the loop runs.
                    for j in range(n):  # pragma: no branch
                        if excluded[j]:
                            continue
                        for c in range(components):  # pragma: no branch
                            mix[c] = to_int32(mix[c] + found[j][c])
                        configuration |= 1 << j
                    for c in range(components):  # pragma: no branch
                        mix[c] = truncated_divide(mix[c], used)
                    var error = _error(tracker, mix, values, offset, components)
                    error.bits += _overhead(
                        used_totals[n - 1] + used, totals[n - 1]
                    )
                    if error.less(best):
                        best = error^
                        best_configuration = configuration
                        best_used = used
                        best_value = mix^
                    if not _next_permutation(excluded):
                        break
            if n > 0:
                used_totals[n - 1] += best_used
            tracker.push(best.symbols)
            for i in range(n):
                self.creases[n - 1].append(best_configuration & (1 << i) == 0)
            self._store(out, values, p, components, best_value)
            p -= 1
        self._store(
            out, values, 0, components, List[Int](length=components, fill=0)
        )

    def _tex_coord(
        mut self,
        p: Int,
        values: List[Int],
        data: MeshData,
        positions: Positions,
    ) raises -> List[Int]:
        """Draco's `MeshPredictionSchemeTexCoordsPortablePredictor` for the
        encoder, which picks the side of the edge nearer the value."""
        var corner = data.order.value_corners[p]
        ref table = data.table
        ref map = data.order.vertex_values
        var next = map[table.vertex(table.next(corner))]
        var prev = map[table.vertex(table.previous(corner))]
        if prev < p and next < p:
            var n_u = values[next * 2]
            var n_v = values[next * 2 + 1]
            var p_u = values[prev * 2]
            var p_v = values[prev * 2 + 1]
            if p_u == n_u and p_v == n_v:
                return [p_u, p_v]
            ref points = data.order.points
            var tip = positions.at(points[p])
            var next_pos = positions.at(points[next])
            var prev_pos = positions.at(points[prev])
            var pn = _sub(prev_pos, next_pos)
            var pn_norm2 = _dot(pn, pn)
            if pn_norm2 != 0:
                var cn = _sub(tip, next_pos)
                var cn_dot_pn = _dot(pn, cn)
                var pn_u = p_u - n_u
                var pn_v = p_v - n_v
                draco_require(
                    max(abs(n_u), abs(n_v)) <= _INT64_MAX // pn_norm2,
                    "a texture coordinate prediction overflows",
                )
                draco_require(
                    cn_dot_pn <= _INT64_MAX // max(abs(pn_u), abs(pn_v)),
                    "a texture coordinate prediction overflows",
                )
                var x_u = n_u * pn_norm2 + cn_dot_pn * pn_u
                var x_v = n_v * pn_norm2 + cn_dot_pn * pn_v
                var pn_max = max(max(abs(pn[0]), abs(pn[1])), abs(pn[2]))
                draco_require(
                    cn_dot_pn <= _INT64_MAX // pn_max,
                    "a texture coordinate prediction overflows",
                )
                var x_pos = List[Int](capacity=3)
                for k in range(3):  # pragma: no branch
                    x_pos.append(
                        next_pos[k]
                        + truncated_divide(cn_dot_pn * pn[k], pn_norm2)
                    )
                var cx = _sub(tip, x_pos)
                var cx_norm2 = _dot(cx, cx)
                var norm = _int_sqrt(UInt64(cx_norm2) * UInt64(pn_norm2))
                var cx_u = pn_v * norm
                var cx_v = -pn_u * norm
                var u0 = truncated_divide(x_u + cx_u, pn_norm2)
                var v0 = truncated_divide(x_v + cx_v, pn_norm2)
                var u1 = truncated_divide(x_u - cx_u, pn_norm2)
                var v1 = truncated_divide(x_v - cx_v, pn_norm2)
                var c_u = values[p * 2]
                var c_v = values[p * 2 + 1]
                var d0 = (c_u - u0) * (c_u - u0) + (c_v - v0) * (c_v - v0)
                var d1 = (c_u - u1) * (c_u - u1) + (c_v - v1) * (c_v - v1)
                if d0 < d1:
                    self.orientations.append(True)
                    return [to_int32(u0), to_int32(v0)]
                self.orientations.append(False)
                return [to_int32(u1), to_int32(v1)]
        var offset: Int
        if next < p:
            offset = next * 2
        elif p > 0:
            offset = (p - 1) * 2
        else:
            return [0, 0]
        return [values[offset], values[offset + 1]]

    def _normals(
        mut self,
        mut out: List[Int],
        values: List[Int],
        data: MeshData,
        positions: Positions,
    ) raises:
        """Draco's `MeshPredictionSchemeGeometricNormalEncoder` with the
        area-weighted predictor: the prediction or its opposite, whichever
        leaves the smaller correction."""
        var o = self.transform.octahedron.copy()
        ref table = data.table
        ref map = data.order.vertex_values
        ref points = data.order.points
        # A sequence has a point: the loop runs.
        for p in range(len(data.order.value_corners)):  # pragma: no branch
            var corner = data.order.value_corners[p]
            var center = positions.at(points[map[table.vertex(corner)]])
            var normal: List[Int] = [0, 0, 0]
            for c in table.corners_of(corner):  # pragma: no branch
                var next = positions.at(
                    points[map[table.vertex(table.next(c))]]
                )
                var prev = positions.at(
                    points[map[table.vertex(table.previous(c))]]
                )
                var cross = _cross(_sub(next, center), _sub(prev, center))
                for k in range(3):  # pragma: no branch
                    normal[k] += cross[k]
            var sum = _abs_sum(normal)
            var upper = 1 << 29
            if sum > upper:
                var quotient = sum // upper
                for k in range(3):  # pragma: no branch
                    normal[k] = truncated_divide(normal[k], quotient)
            var canonical = o.canonicalize_vector(
                to_int32(normal[0]), to_int32(normal[1]), to_int32(normal[2])
            )
            var pos = o.vector_to_coords(
                canonical[0], canonical[1], canonical[2]
            )
            var neg = o.vector_to_coords(
                -canonical[0], -canonical[1], -canonical[2]
            )
            var pos_corr = self.transform.correct(
                values, 2 * p, [pos[0], pos[1]]
            )
            var neg_corr = self.transform.correct(
                values, 2 * p, [neg[0], neg[1]]
            )
            var ps = o.mod_max(pos_corr[0])
            var pt = o.mod_max(pos_corr[1])
            var ns = o.mod_max(neg_corr[0])
            var nt = o.mod_max(neg_corr[1])
            if abs(ps) + abs(pt) < abs(ns) + abs(nt):
                self.flips.encode_bit(False)
                out[2 * p] = _positive(o, ps)
                out[2 * p + 1] = _positive(o, pt)
            else:
                self.flips.encode_bit(True)
                out[2 * p] = _positive(o, ns)
                out[2 * p + 1] = _positive(o, nt)

    def write(self, mut out: DracoWriter):
        """Draco's `EncodePredictionData`."""
        if self.method == DRACO_CONSTRAINED_MULTI_PARALLELOGRAM:
            for i in range(_MAX_PARALLELOGRAMS):  # pragma: no branch
                var used = i + 1
                ref flags = self.creases[i]
                out.varint(len(flags))
                if len(flags) == 0:
                    continue
                var bits = RAnsBitEncoder()
                var j = len(flags) - used
                while j >= 0:
                    for k in range(used):  # pragma: no branch
                        bits.encode_bit(flags[j + k])
                    j -= used
                bits.end(out)
        elif self.method == DRACO_TEX_COORDS_PORTABLE:
            out.u32(len(self.orientations))
            var bits = RAnsBitEncoder()
            var last = True
            for orientation in self.orientations:
                bits.encode_bit(orientation == last)
                last = orientation
            bits.end(out)
        self.transform.write(out)
        if self.method == DRACO_GEOMETRIC_NORMAL:
            self.flips.end(out)


struct _Error(Copyable, Movable):
    """Draco's `Error` of a prediction: its bits, then its residuals."""

    var bits: Int
    var residual: Int
    var symbols: List[Int]

    def __init__(out self, bits: Int, residual: Int, var symbols: List[Int]):
        self.bits = bits
        self.residual = residual
        self.symbols = symbols^

    def less(self, other: _Error) -> Bool:
        """Draco's `operator<`: fewer bits, then smaller residuals."""
        if self.bits != other.bits:
            return self.bits < other.bits
        return self.residual < other.residual


def _error(
    mut tracker: EntropyTracker,
    predicted: List[Int],
    values: List[Int],
    offset: Int,
    components: Int,
) raises -> _Error:
    """Draco's `ComputeError`: the bits the residuals would add, and
    their sum in size."""
    var residual = 0
    var symbols = List[Int](capacity=components)
    for c in range(components):  # pragma: no branch
        var dif = to_int32(predicted[c] - values[offset + c])
        residual += abs(dif)
        symbols.append(signed_to_symbol(dif))
    var data = tracker.peek(symbols)
    var bits = entropy_data_bits(data) + entropy_table_bits(data)
    return _Error(bits, residual, symbols^)


def _overhead(used: Int, total: Int) raises -> Int:
    """Draco's `ComputeOverheadBits`: the bits of the crease flags."""
    return Int(ceil(product(Float64(total), binary_entropy(total, used))))


def _next_permutation(mut flags: List[Bool]) -> Bool:
    """C++'s `std::next_permutation` on bools, `False` before `True`."""
    var n = len(flags)
    var i = n - 2
    while i >= 0 and not (not flags[i] and flags[i + 1]):
        i -= 1
    if i < 0:
        flags.reverse()
        return False
    var j = n - 1
    while flags[j] == False:
        j -= 1
    flags[i] = True
    flags[j] = False
    var a = i + 1
    var b = n - 1
    while a < b:
        var t = flags[a]
        flags[a] = flags[b]
        flags[b] = t
        a += 1
        b -= 1
    return True


def _sub(a: List[Int], b: List[Int]) -> List[Int]:
    """Subtract two three-component vectors."""
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def _dot(a: List[Int], b: List[Int]) -> Int:
    """The dot product of two three-component vectors."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(u: List[Int], v: List[Int]) -> List[Int]:
    """The cross product of two three-component vectors."""
    return [
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    ]


def _abs_sum(v: List[Int]) -> Int:
    """Draco's `VectorD::AbsSum`, which stops at the largest integer."""
    var sum = 0
    for k in range(3):  # pragma: no branch
        var next = abs(v[k])
        if next < 0 or sum > _INT64_MAX - next:
            return _INT64_MAX
        sum += next
    return sum


def _int_sqrt(number: UInt64) -> Int:
    """Draco's `IntSqrt`: the integer square root by Newton's method."""
    if number == 0:
        return 0
    var act = number
    var root = UInt64(1)
    while act >= 2:
        root *= 2
        act //= 4
    while True:
        root = (root + number // root) // 2
        if root * root <= number:
            break
    return Int(root)


def encode_integers(
    mut out: DracoWriter,
    values: List[Int],
    components: Int,
    method: DracoPrediction,
    normal_bits: Int,
    mesh: Optional[MeshData],
    positions: Optional[Positions],
    level: Int,
) raises:
    """Write the integers of an attribute, predicted and coded.

    Draco's `SequentialIntegerAttributeEncoder::EncodeValues`: the
    prediction and its transform, the corrections as symbols, then the
    prediction's data.

    Args:
        out: Where to write them.
        values: The integers, in their stored order.
        components: The integers of each value.
        method: The prediction that runs. A mesh prediction needs `mesh`;
            the texture coordinate and geometric normal predictions need
            `positions` too.
        normal_bits: The bits of each octahedron coordinate for normals,
            or zero for other attributes, which the wrap transform takes.
        mesh: The connectivity, for a mesh prediction.
        positions: The quantized positions, for a prediction that reads
            them.
        level: The compression level of the symbols, from 0 to 10.

    Raises:
        Error: If a prediction overflows, or the symbols cannot be coded,
            as Draco fails.
    """
    var kind = DRACO_WRAP
    if normal_bits > 0:
        kind = DRACO_OCTAHEDRON_CANONICALIZED
    var scheme = _Scheme(method, _Transform(kind, components, normal_bits))
    out.u8(method.value)
    out.u8(kind.value)
    var corrections = scheme.corrections(values, components, mesh, positions)
    if normal_bits == 0:
        # A sequence has a point: the loop runs.
        for i in range(len(corrections)):  # pragma: no branch
            corrections[i] = signed_to_symbol(corrections[i])
    out.u8(1)
    encode_symbols(out, corrections, components, level)
    scheme.write(out)
