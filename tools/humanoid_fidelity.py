# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Immutable canonical SI snapshots and explicit visual derivatives.

This boundary packages supplied canonical geometry; it does not reconstruct
anatomy from a visual mesh or certify the geometry. Keep the complete #289
report as evidence. No raw probe row is an engineering validity certificate.
The CLI uses local files only and never fetches or rehosts source assets.
"""
import argparse
from copy import deepcopy
from enum import Enum
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile

SCHEMA = 1


class Frame(Enum):
    """Named right-handed SI axis conventions; origins are supplied separately."""
    Y_UP = 'right-handed-y-up-x-right-z-anterior'
    Z_UP = 'right-handed-z-up-x-right-minus-y-anterior'

    def is_valid(self):
        """Return whether this is one of the two named frame conventions."""
        return self in (Frame.Y_UP, Frame.Z_UP)


IDENTITY = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
Y_TO_Z = ((1, 0, 0), (0, 0, -1), (0, 1, 0))
Z_TO_Y = ((1, 0, 0), (0, 0, 1), (0, -1, 0))


def finite(value):
    """Require a finite numeric SI value, excluding Boolean values."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError('an SI quantity must be finite and numeric')
    return value


def vector(value):
    """Validate a three-coordinate SI vector."""
    if not isinstance(value, (tuple, list)) or len(value) != 3:
        raise ValueError('a vector must contain three coordinates')
    return [finite(x) for x in value]


def rotation(value):
    """Require a proper orthonormal rotation, never a reflection or scale."""
    if not isinstance(value, (tuple, list)) or len(value) != 3:
        raise ValueError('a rotation must have three rows')
    rows = [vector(row) for row in value]
    for i in range(3):
        for j in range(3):
            if not math.isclose(sum(rows[i][k]*rows[j][k] for k in range(3)),
                                int(i == j), rel_tol=0, abs_tol=1e-12):
                raise ValueError('a rotation must be orthonormal')
    a, b, c = rows
    det = (a[0]*(b[1]*c[2]-b[2]*c[1]) - a[1]*(b[0]*c[2]-b[2]*c[0])
           + a[2]*(b[0]*c[1]-b[1]*c[0]))
    if not math.isclose(det, 1, rel_tol=0, abs_tol=1e-12):
        raise ValueError('a rotation must preserve handedness')
    return rows


def frame_rotation(source, target):
    """Return a named y-up/z-up coordinate adapter; both frames stay SI."""
    if not isinstance(source, Frame) or not isinstance(target, Frame):
        raise ValueError('source and target must be typed frames')
    if source == target:
        return IDENTITY
    return Y_TO_Z if source == Frame.Y_UP else Z_TO_Y


def transform_point(point_m, rotate, translation_m=(0, 0, 0)):
    """Apply a proper rotation and a translation in target-frame meters."""
    p, r, t = vector(point_m), rotation(rotate), vector(translation_m)
    result = [math.fsum(r[i][j]*p[j] for j in range(3))+t[i] for i in range(3)]
    return [finite(value) for value in result]


def transform_inertia(mass_kg, center_m, inertia_com_kg_m2, rotate,
                      translation_m=(0, 0, 0), reference_m=None):
    """Rotate the full COM tensor, then shift to the target-frame reference.

    Six entries are xx, yy, zz, xy, xz, yz with tensor signs, matching #289.
    The formula is R I R^T + m ((d dot d) Identity - d d^T), d = COM-reference.
    Omit reference_m to retain the tensor about the transformed COM. Never
    pass a tensor about another reference as if it were a COM tensor.
    """
    mass = finite(mass_kg)
    if mass < 0:
        raise ValueError('mass cannot be negative')
    if not isinstance(inertia_com_kg_m2, (tuple, list)) or len(inertia_com_kg_m2) != 6:
        raise ValueError('a symmetric inertia tensor needs six entries')
    xx, yy, zz, xy, xz, yz = [finite(x) for x in inertia_com_kg_m2]
    original = ((xx, xy, xz), (xy, yy, yz), (xz, yz, zz))
    r = rotation(rotate)
    center = transform_point(center_m, r, translation_m)
    reference = center[:] if reference_m is None else vector(reference_m)
    d = [a-b for a, b in zip(center, reference)]
    norm = math.fsum(x*x for x in d)
    result = [[math.fsum(r[i][k]*original[k][l]*r[j][l]
                         for k in range(3) for l in range(3))
               + mass*(norm*int(i == j)-d[i]*d[j]) for j in range(3)] for i in range(3)]
    tensor = [result[0][0], result[1][1], result[2][2],
              result[0][1], result[0][2], result[1][2]]
    for x in center + reference + tensor:
        finite(x)
    return {'mass_kg': mass, 'center_m': center, 'reference_m': reference,
            'inertia_kg_m2': tensor}


def adapt_part(part, source_frame, target_frame, translation_m=(0, 0, 0), reference_m=None,
               *, target_origin_label=None):
    """Copy geometry and COM properties into a coherent target frame.

    Existing part and property frames must match the declared source frame.
    Translation requires an explicit target-origin label. A shifted output
    tensor cannot be reused as a COM tensor for a later adaptation.
    """
    r = frame_rotation(source_frame, target_frame)
    translated = vector(translation_m)
    if not isinstance(part, dict) or part.get('frame') != source_frame.value:
        raise ValueError('part frame contradicts the declared source frame')
    origin = _label(part.get('origin_label'), 'part origin')
    if target_origin_label is None:
        if any(value != 0 for value in translated):
            raise ValueError('translation requires an explicit target origin')
        target_origin_label = origin
    _label(target_origin_label, 'target origin')
    physical = part.get('physical_properties')
    if physical is not None:
        if not isinstance(physical, dict) or physical.get('frame') != source_frame.value:
            raise ValueError('physical property frame contradicts the source frame')
        if physical.get('origin_label') != origin:
            raise ValueError('physical property origin contradicts the part origin')
        if physical.get('tensor_reference') != 'center-of-mass':
            raise ValueError('adaptation requires a source tensor about the COM')
    out = deepcopy(part)
    out['vertices_m'] = [transform_point(p, r, translated) for p in part['vertices_m']]
    out['frame'] = target_frame.value
    out['origin_label'] = target_origin_label
    out['source_frame'] = source_frame.value
    out['source_origin_label'] = origin
    out['translation_m'] = translated
    physical = out.get('physical_properties')
    if physical is not None:
        physical.update(transform_inertia(physical['mass_kg'], physical['center_m'],
                        physical['inertia_kg_m2'], r, translated, reference_m))
        physical['tensor_reference'] = ('center-of-mass' if reference_m is None
                                       else 'explicit-target-reference')
        physical['frame'] = target_frame.value
        physical['origin_label'] = target_origin_label
    return out


def canonical_bytes(value):
    """Return a stable finite JSON representation, suitable for SHA-256."""
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=True, allow_nan=False).encode('utf-8')


def digest(value):
    """Return the SHA-256 of the canonical JSON representation."""
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def _label(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{name} must be a nonempty label')
    return value


def _report(report):
    """Require the complete typed #289 envelope and its tensor convention.

    This validates structure and coordinate semantics, not anatomy or numerical
    convergence. The report itself remains the authority for those results.
    """
    if not isinstance(report, dict) or type(report.get('schema_version')) is not int or report['schema_version'] != 1:
        raise ValueError('a complete versioned canonical validity report is required')
    mappings = ('gate', 'build_provenance', 'source_file_sha256', 'spec', 'frame',
                'tensor_convention', 'controls', 'segments', 'composition',
                'diagnostics', 'diagnostic_limits', 'accounting', 'provenance_inventory')
    if not all(isinstance(report.get(key), dict) for key in mappings):
        raise ValueError('use the complete typed canonical validity report, not raw probe rows')
    if not all(isinstance(report.get(key), list) for key in ('follow_ups', 'geometry_findings')):
        raise ValueError('canonical validity report arrays are missing')
    for key in ('result_label', 'report_logic_sha256', 'inventory_sha256'):
        _label(report.get(key), key)
    if report['gate'].get('engineering_validated') is not False:
        raise ValueError('canonical report cannot grant engineering validity')
    if report['tensor_convention'] != {
        'order': ['xx', 'yy', 'zz', 'xy', 'xz', 'yz'],
        'reference': 'center of mass', 'off_diagonal': 'negative products of inertia',
    }:
        raise ValueError('unsupported canonical report tensor order, reference or sign')
    if report['frame'] != {
        'origin': 'tibiofemoral joint line', 'x': 'body-right', 'y': 'proximal', 'z': 'anterior',
    }:
        raise ValueError('unsupported canonical report coordinate frame')
    segments = report['segments']
    if set(segments) != {'thigh', 'shank', 'foot'}:
        raise ValueError('a complete canonical report needs all three limb segments')
    labels = report['accounting'].get('exclusive_density_precedence')
    if not isinstance(labels, list) or len(labels) != 7 or not all(isinstance(x, str) and x for x in labels) or len(set(labels)) != 7:
        raise ValueError('a canonical report needs its seven exclusive region labels')
    for segment, entry in segments.items():
        if not isinstance(entry, dict) or not isinstance(entry.get('sampling_sensitivity'), dict):
            raise ValueError('a segment must retain its sampling sensitivity report')
        grids = entry.get('grids')
        if not isinstance(grids, list) or len(grids) < 3:
            raise ValueError('a segment must retain at least three sampled grids')
        for row in grids:
            if not isinstance(row, dict) or row.get('record') != 'segment' or row.get('segment') != segment:
                raise ValueError('a sampled grid must retain its segment identity')
            for key in ('mass_kg', 'step_m', 'length_m'):
                if finite(row.get(key)) <= 0:
                    raise ValueError('sampled mass, grid step and length must be positive')
            for key in ('center_m', 'low_m', 'high_m'):
                vector(row.get(key))
            tensor = row.get('inertia_kg_m2')
            if not isinstance(tensor, list) or len(tensor) != 6:
                raise ValueError('a sampled grid must retain its full inertia tensor')
            for value in tensor:
                finite(value)
            regions = row.get('regions')
            if not isinstance(regions, dict) or set(regions) != set(labels):
                raise ValueError('a sampled grid must retain all accounting regions')
            for region in regions.values():
                if not isinstance(region, dict):
                    raise ValueError('a sampled region must retain its quantities')
                for key in ('mass_kg', 'volume_m3'):
                    if finite(region.get(key)) < 0:
                        raise ValueError('sampled region quantities cannot be negative')
    canonical_bytes(report)
    return report


def report_properties(report, segment, grid_index):
    """Copy one #289 segment's complete sampled properties, without recalculation.

    The tensor is about the COM in the report's leg frame. Preserve its frame
    and seven density-assignment labels. This does not establish correspondence
    to any separately supplied part mesh or authorize composition with it.
    """
    _report(report)
    if segment not in ('thigh', 'shank', 'foot'):
        raise ValueError('a report segment must be thigh, shank or foot')
    if type(grid_index) is not int or grid_index < 0:
        raise ValueError('a grid index must be a nonnegative integer')
    try:
        row = report['segments'][segment]['grids'][grid_index]
        result = {key: deepcopy(row[key]) for key in
                  ('mass_kg', 'center_m', 'inertia_kg_m2', 'regions', 'step_m')}
        result['frame'] = Frame.Y_UP.value
        result['origin_label'] = report['frame']['origin']
        result['source_report_frame'] = deepcopy(report['frame'])
    except (KeyError, IndexError, TypeError):
        raise ValueError('the complete segment/grid record is missing') from None
    result['tensor_reference'] = 'center-of-mass'
    result['source_report_record'] = f'segments/{segment}/grids/{grid_index}'
    return result


def validate_snapshot(snapshot):
    """Validate packaging and SI shape, without inferring anatomical validity.

    A part's physical_properties is explicit or null. Null remains unsupported;
    it is never replaced by visual volume or a guessed tissue density. Tissue
    labels are source labels, including #289's named accounting proxies.
    """
    if not isinstance(snapshot, dict):
        raise ValueError('a canonical snapshot must be an object')
    if type(snapshot.get('schema_version')) is not int or snapshot['schema_version'] != SCHEMA:
        raise ValueError('unsupported canonical snapshot schema')
    if snapshot.get('units') != {'length': 'meter', 'mass': 'kilogram', 'inertia': 'kilogram-meter-squared'}:
        raise ValueError('canonical snapshot quantities must use SI units')
    if snapshot.get('frame') != Frame.Y_UP.value:
        raise ValueError('canonical snapshots must retain the y-up source frame')
    vector(snapshot.get('origin_m'))
    _label(snapshot.get('origin_label'), 'source origin')
    _label(snapshot.get('source_revision'), 'source revision')
    if not isinstance(snapshot.get('canonical_inputs'), dict) or not snapshot['canonical_inputs']:
        raise ValueError('canonical SI inputs are required')
    if snapshot.get('engineering_validated') is not False:
        raise ValueError('a snapshot cannot certify engineering validity')
    _report(snapshot.get('canonical_validity_report'))
    parts = snapshot.get('parts')
    if not isinstance(parts, list) or not parts:
        raise ValueError('a snapshot needs explicit canonical parts')
    seen = set()
    for part in parts:
        if not isinstance(part, dict):
            raise ValueError('a canonical part must be an object')
        label = _label(part.get('part_id'), 'part id')
        if label in seen:
            raise ValueError('canonical part ids must be unique')
        seen.add(label)
        _label(part.get('tissue_label'), 'tissue label')
        if part.get('frame') != snapshot['frame']:
            raise ValueError('canonical part frame contradicts its snapshot frame')
        if part.get('origin_label') != snapshot['origin_label']:
            raise ValueError('canonical part origin contradicts its snapshot origin')
        vertices = part.get('vertices_m')
        indices = part.get('triangles')
        if not isinstance(vertices, list) or not vertices:
            raise ValueError('a canonical part needs SI vertices')
        for vertex in vertices:
            vector(vertex)
        if not isinstance(indices, list) or not indices:
            raise ValueError('a canonical part needs triangle topology')
        for face in indices:
            if not isinstance(face, list) or len(face) != 3:
                raise ValueError('a canonical triangle needs three indices')
            if any(type(i) is not int or i < 0 or i >= len(vertices) for i in face):
                raise ValueError('a canonical triangle index is outside its part')
        physical = part.get('physical_properties')
        if physical is not None:
            if not isinstance(physical, dict) or physical.get('tensor_reference') != 'center-of-mass':
                raise ValueError('canonical part tensors must be about the COM')
            if physical.get('frame') != part['frame']:
                raise ValueError('physical property frame contradicts its canonical part frame')
            if physical.get('origin_label') != part['origin_label']:
                raise ValueError('physical property origin contradicts its canonical part origin')
            transform_inertia(physical.get('mass_kg'), physical.get('center_m'),
                              physical.get('inertia_kg_m2'), IDENTITY)
            _label(physical.get('source_report_record'), 'physical source record')
    canonical_bytes(snapshot)
    return snapshot


def make_snapshot(canonical_inputs, source_revision, parts, report, origin_m=(0, 0, 0), *, origin_label):
    """Copy canonical inputs, explicit part meshes/properties and a complete report.

    The report is retained verbatim as JSON with no recalculation or narrowing.
    Empty report data is refused; use the complete schema-version-1 #289 report.
    Snapshot packaging does not assert that supplied meshes match that report.
    """
    _report(report)
    snapshot = {'schema_version': SCHEMA, 'units': {
        'length': 'meter', 'mass': 'kilogram', 'inertia': 'kilogram-meter-squared'},
        'frame': Frame.Y_UP.value, 'origin_m': vector(origin_m), 'origin_label': origin_label,
        'source_revision': source_revision, 'canonical_inputs': deepcopy(canonical_inputs),
        'parts': deepcopy(parts), 'canonical_validity_report': deepcopy(report),
        'engineering_validated': False,
        'scope': 'Supplied canonical part meshes and reported properties; no clinical calibration or visual correspondence.'}
    return deepcopy(validate_snapshot(snapshot))


def write_snapshot(path, snapshot):
    """Write an immutable snapshot; an existing path must have identical bytes."""
    validate_snapshot(snapshot)
    data = canonical_bytes(snapshot)
    path = Path(path)
    # Write a private sibling, then link it into place. A link fails when the
    # path exists, as exclusive creation does, but an interrupted write leaves
    # only the sibling, never a truncated snapshot at the versioned path.
    descriptor, temporary = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.link(temporary, path)
    except FileExistsError:
        if path.read_bytes() != data:
            raise ValueError('canonical snapshot is immutable; choose a new versioned path') from None
    finally:
        os.unlink(temporary)
    return hashlib.sha256(data).hexdigest()


def read_snapshot(path, expected_sha256):
    """Verify immutable bytes before exposing a canonical snapshot."""
    data = Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError('canonical snapshot content changed')
    return validate_snapshot(json.loads(data))


def visual_derivative(snapshot, visual_asset, recipe):
    """Bind a visual asset to immutable canonical data without replacing it.

    The visual byte hash detects external changes, unlike a recipe alone.
    Every new identity, expression, topology, source or transform needs a new
    recipe. No map is inferred from equal part names or realistic appearance.
    """
    validate_snapshot(snapshot)
    if not isinstance(recipe, dict) or not recipe:
        raise ValueError('a visual derivative needs an explicit recipe')
    return {'schema_version': SCHEMA, 'canonical_snapshot_sha256': digest(snapshot),
            'visual_asset_sha256': hashlib.sha256(Path(visual_asset).read_bytes()).hexdigest(),
            'recipe': deepcopy(recipe), 'recipe_sha256': digest(recipe),
            'engineering_use': False,
            'mappings': {name: 'unsupported' for name in
                         ('identity', 'expression_jaw', 'eyes', 'dental', 'skin_weights', 'lod')},
            'dental_representations': ['authored-canonical', 'scanned-expression']}


def validate_derivative(manifest, snapshot, visual_asset, recipe):
    """Refuse stale or edited recipes, assets, snapshots and capability flags."""
    expected = visual_derivative(snapshot, visual_asset, recipe)
    if canonical_bytes(manifest) != canonical_bytes(expected):
        raise ValueError('visual derivative is stale or altered; regenerate its provenance')


def main():
    """Validate a snapshot by its supplied SHA-256 without modifying it."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    try:
        read_snapshot(args.snapshot, args.sha256)
    except (ValueError, OSError) as error:
        parser.exit(2, f'Canonical snapshot validation failed: {error}\n')
    print('Canonical snapshot bytes and SI packaging verified; engineering use remains unsupported.')


if __name__ == '__main__':
    main()
