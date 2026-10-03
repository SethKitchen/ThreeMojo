# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Synthetic, real-rasterizer bake regressions. Require NumPy and Pillow.

Run explicitly with the pinned exporter test environment documented in
CARLA-assets. No CARLA release is needed. Only mesh simplification is
substituted; materials, textures, bake pixels and GLB packaging are real.
"""

from contextlib import ExitStack
import copy
import hashlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

import numpy
from PIL import Image

import build_towns as tool


def _load_glb(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from('<III', data)
    assert (magic, version, size) == (0x46546C67, 2, len(data))
    length, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4E4F534A
    gltf = json.loads(data[20:20 + length])
    binary_size, kind = struct.unpack_from('<II', data, 20 + length)
    assert kind == 0x004E4942
    blob = data[28 + length:]
    assert len(blob) == binary_size
    return gltf, blob


def _image(gltf, blob, material):
    texture = gltf['materials'][material]['pbrMetallicRoughness']['baseColorTexture']['index']
    image = gltf['images'][gltf['textures'][texture]['source']]
    view = gltf['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    with Image.open(io.BytesIO(blob[start:start + view['byteLength']])) as picture:
        return numpy.asarray(picture.convert('RGBA')).copy()


class TownBakeTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.raw = self.root / 'raw'
        self.maps = self.root / 'maps'
        self.layout = self.root / 'layout'
        self.output = self.root / 'packages'
        for path in (self.raw, self.maps, self.layout):
            path.mkdir()
        (self.maps / 'Fixture.xodr').write_text('<OpenDRIVE/>')
        for name, color in (('Red', (255, 0, 0)), ('Green', (0, 255, 0))):
            Image.new('RGB', (4, 4), color).save(self.raw / (name + '.png'))
            (self.raw / (name + '.mat')).write_text('Diffuse=' + name + '\n')
        self.meshes = ['/Game/Carla/Static/Building/Fixture',
                       '/Game/Carla/Static/Vegetation/Trees/Fixture']
        self.primitives = []
        for index, x in enumerate((-0.75, 0.75)):
            part = tool.cube()[0]
            part['positions'][:, 0] += x
            part['material'] = 'Own' + str(index)
            self.primitives.append(part)
        for mesh in self.meshes:
            self._write_mesh(mesh)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(mock.patch.multiple(
            tool, RAW=str(self.raw), MAPS=str(self.maps), LAYOUT=str(self.layout),
            OUT=str(self.output), STATS={}))
        self.simplify = self.stack.enter_context(mock.patch.object(
            tool, 'simplify', side_effect=lambda primitive, *args, **kwargs: primitive))
        self.weld = self.stack.enter_context(mock.patch.object(
            tool, 'simplify_welded', side_effect=lambda primitive, *args, **kwargs: primitive))

    def _write_mesh(self, mesh):
        path = self.raw.joinpath(*mesh[len('/Game/'):].split('/')).with_suffix('.gltf')
        path.parent.mkdir(parents=True, exist_ok=True)
        gltf = {'buffers': [{'uri': 'Fixture.bin'}], 'bufferViews': [], 'accessors': [],
                'materials': [{'name': p['material']} for p in self.primitives],
                'meshes': [{'primitives': []}]}
        blob = bytearray()
        for index, part in enumerate(self.primitives):
            primitive = {'material': index, 'attributes': {}}
            for field, attribute, width in (('positions', 'POSITION', 'VEC3'),
                                            ('normals', 'NORMAL', 'VEC3'),
                                            ('uvs', 'TEXCOORD_0', 'VEC2'),
                                            ('triangles', None, 'SCALAR')):
                values = part[field].astype('<u4' if attribute is None else '<f4')
                if attribute is None:
                    values = values.reshape(-1)
                gltf['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': values.nbytes})
                gltf['accessors'].append({'bufferView': len(gltf['bufferViews']) - 1,
                                         'componentType': 5125 if attribute is None else 5126,
                                         'count': len(values), 'type': width})
                if attribute is None:
                    primitive['indices'] = len(gltf['accessors']) - 1
                else:
                    primitive['attributes'][attribute] = len(gltf['accessors']) - 1
                blob.extend(values.tobytes())
            gltf['meshes'][0]['primitives'].append(primitive)
        path.write_text(json.dumps(gltf))
        path.with_suffix('.bin').write_bytes(blob)

    def _rows(self, overrides):
        rows = []
        for mesh in self.meshes:
            for index, materials in enumerate(overrides):
                rows.append({'visible': True, 'mesh': 'StaticMesh ' + mesh + '.Fixture',
                             'location': [index * 3200, 0, 0], 'rotation': [0, 0, 0], 'scale': [1, 1, 1],
                             'materials': ['MaterialInstanceConstant /Game/Fixture/' + n + '.' + n
                                           if n else None for n in materials]})
        (self.layout / 'Fixture.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in rows))

    def _build(self):
        with mock.patch.object(tool, 'baked_building', wraps=tool.baked_building) as buildings, \
                mock.patch.object(tool, 'impostor', wraps=tool.impostor) as trees:
            tool.build('Fixture', 512, 32)
        path = self.output / 'carla.town.fixture' / 'carla.town.fixture.glb'
        gltf, blob = _load_glb(path)
        return gltf, blob, path.read_bytes(), (buildings.call_count, trees.call_count)

    def _materials_by_node(self, gltf):
        result = {}
        for node in gltf['nodes']:
            primitive = gltf['meshes'][node['mesh']]['primitives'][0]
            result.setdefault(node['name'], []).append(primitive['material'])
        return result

    def test_two_component_colors_keep_near_and_far_appearance_and_share_duplicates(self):
        self._rows([['Red', 'Red'], ['Green', 'Green'], ['Red', 'Red']])
        gltf, blob, _, calls = self._build()
        by_node = self._materials_by_node(gltf)
        for kind in ('building', 'vegetation'):
            for lod in (0, 1):
                with self.subTest(kind=kind, lod=lod):
                    indices = [by_node[f'{kind}_{cell}_0_lod{lod}'][0] for cell in range(3)]
                    for material, channel in zip(indices[:2], (0, 1)):
                        pixels = _image(gltf, blob, material)
                        covered = pixels[:, :, 3] > 0
                        mean = pixels[covered, :3].mean(axis=0)
                        self.assertGreater(mean[channel], 80)
                        self.assertGreater(mean[channel] - mean[1 - channel], 70)
                    self.assertEqual(indices[0], indices[2])
                    self.assertNotEqual(indices[0], indices[1])
        self.assertEqual(calls, (2, 2))
        self.assertGreater(self.simplify.call_count, 0)
        self.assertGreater(self.weld.call_count, 0)

    def test_slot_order_stays_visible_in_near_geometry_and_far_pixels(self):
        self._rows([['Red', 'Green'], ['Green', 'Red'], ['Red', 'Green']])
        gltf, blob, _, calls = self._build()
        by_node = self._materials_by_node(gltf)
        for kind in ('building', 'vegetation'):
            with self.subTest(kind=kind):
                for cell in range(3):
                    for node in gltf['nodes']:
                        if node['name'] != f'{kind}_{cell}_0_lod0':
                            continue
                        primitive = gltf['meshes'][node['mesh']]['primitives'][0]
                        material = gltf['materials'][primitive['material']]['name']
                        accessor = gltf['accessors'][primitive['attributes']['POSITION']]
                        view = gltf['bufferViews'][accessor['bufferView']]
                        points = numpy.frombuffer(blob, '<f4', count=accessor['count'] * 3,
                                                  offset=view['byteOffset']).reshape(-1, 3)
                        left = (material == 'Red') == (cell != 1)
                        self.assertAlmostEqual(points[:, 0].mean() - cell * 32, -0.75 if left else 0.75)
                    material = by_node[f'{kind}_{cell}_0_lod1'][0]
                    pixels = _image(gltf, blob, material)
                    # The building's +z view follows two six-texel side views.
                    # The tree's left atlas half is its +z view, across x.
                    if kind == 'building':
                        left = pixels[1:5, 13:16, :3].mean(axis=(0, 1))
                        right = pixels[1:5, 23:26, :3].mean(axis=(0, 1))
                    else:
                        left = pixels[120:136, 43:59, :3].mean(axis=(0, 1))
                        right = pixels[120:136, 197:213, :3].mean(axis=(0, 1))
                    red_side, green_side = (left, right) if cell != 1 else (right, left)
                    self.assertGreater(red_side[0] - red_side[1], 70)
                    self.assertGreater(green_side[1] - green_side[0], 70)
        self.assertEqual(calls, (2, 2))

    def test_repeated_builds_are_byte_identical(self):
        self._rows([['Red', 'Green'], ['Green', 'Red'], ['Red', 'Green']])
        first = self._build()
        second = self._build()
        self.assertEqual(first[2], second[2])
        self.assertEqual(first[3], (2, 2))

    def test_hidden_first_slot_still_bakes_the_visible_slot(self):
        self._rows([[tool.GRID, 'Red'], [tool.GRID, 'Green'], [tool.GRID, tool.GRID]])
        gltf, blob, _, calls = self._build()
        self.assertEqual(calls, (2, 2))
        by_node = self._materials_by_node(gltf)
        for kind in ('building', 'vegetation'):
            for cell in (0, 1):
                self.assertIn(f'{kind}_{cell}_0_lod1', by_node)
            self.assertNotIn(f'{kind}_2_0_lod0', by_node)
            self.assertNotIn(f'{kind}_2_0_lod1', by_node)

    def test_atlas_names_cover_direct_bakes_and_changed_texture_bytes(self):
        tags = []
        for run, color in enumerate(((255, 0, 0), (0, 255, 0))):
            Image.new('RGB', (4, 4), color).save(self.raw / 'Red.png')
            folder = self.root / str(run)
            folder.mkdir()
            library = tool.Library(str(folder), 512)
            red, green = library.material('Red'), library.material('Green')
            parts = [(p, red) for p in self.primitives]
            other = [(p, green) for p in self.primitives]
            for bake in (tool.impostor, tool.baked_building):
                args = (24,) if bake is tool.baked_building else ()
                _, first = bake(parts, library, str(folder), 'mesh', *args)
                _, second = bake(other, library, str(folder), 'mesh', *args)
                names = [library.gltf['materials'][m]['name'] for m in (first, second)]
                self.assertNotEqual(*names)
                tags.append(names[0])
        self.assertNotEqual(tags[0], tags[2])
        self.assertNotEqual(tags[1], tags[3])

    def test_alpha_cutoff_and_factor_change_real_bake_pixels(self):
        folder = self.root / 'alpha'
        folder.mkdir()
        library = tool.Library(str(folder), 512)
        for cutoff in (0.2, 0.4):
            library.gltf['materials'].append({
                'name': 'cutout', 'alphaMode': 'MASK', 'alphaCutoff': cutoff,
                'pbrMetallicRoughness': {'baseColorFactor': [0.6, 0, 0, 0.3]}})
        for bake in (tool.impostor, tool.baked_building):
            with self.subTest(bake=bake.__name__):
                args = (24,) if bake is tool.baked_building else ()
                tags, pictures = [], []
                for material in (0, 1):
                    _, result = bake([(p, material) for p in self.primitives],
                                     library, str(folder), 'mesh', *args)
                    entry = library.gltf['materials'][result]
                    tags.append(entry['name'])
                    texture = entry['pbrMetallicRoughness']['baseColorTexture']['index']
                    image = library.gltf['images'][library.gltf['textures'][texture]['source']]
                    with Image.open(folder / image['uri']) as picture:
                        pictures.append(numpy.asarray(picture.convert('RGBA')).copy())
                self.assertNotEqual(*tags)
                self.assertGreater(pictures[0][:, :, 0].mean(), 40)
                self.assertEqual(pictures[1][:, :, :3].max(), 0)
                if bake is tool.impostor:
                    self.assertGreater(pictures[0][:, :, 3].max(), 0)
                    self.assertEqual(pictures[1][:, :, 3].max(), 0)

    def test_real_bakes_leave_cached_inputs_unchanged(self):
        folder = self.root / 'immutable'
        folder.mkdir()
        library = tool.Library(str(folder), 512)
        parts = [(p, library.material(n)) for p, n in zip(self.primitives, ('Red', 'Green'))]
        before_parts = copy.deepcopy(self.primitives)
        before_tables = copy.deepcopy(library.gltf)
        before_files = {image['uri']: (folder / image['uri']).read_bytes()
                        for image in library.gltf['images']}
        for bake, kind in ((tool.impostor, 'impostor'), (tool.baked_building, 'baked')):
            with self.subTest(kind=kind):
                target = 24 if kind == 'baked' else None
                tag = library._bake_tag('mesh', kind, parts, target)
                args = (target,) if kind == 'baked' else ()
                bake(parts, library, str(folder), 'mesh', *args)
                self.assertEqual(tag, library._bake_tag('mesh', kind, parts, target))
                for before, after in zip(before_parts, self.primitives):
                    self.assertEqual(before.keys(), after.keys())
                    for field in before:
                        numpy.testing.assert_array_equal(before[field], after[field])
                # The bakes append output entries but must not edit any
                # source entries or replace a packaged input texture.
                for table, entries in before_tables.items():
                    self.assertEqual(entries, library.gltf[table][:len(entries)])
                for uri, data in before_files.items():
                    self.assertEqual(data, (folder / uri).read_bytes())

    def _masked_materials(self):
        Image.new('RGB', (4, 4), 'red').save(self.raw / 'Shared.png')
        Image.new('L', (4, 4), 255).save(self.raw / 'MaskA.png')
        Image.new('L', (4, 4), 0).save(self.raw / 'MaskB.png')
        for material, mask in (('A', 'MaskA'), ('B', 'MaskB')):
            (self.raw / (material + '.mat')).write_text('Diffuse=Shared\nOpacity=' + mask + '\n')
            (self.raw / (material + '.props.txt')).write_text('BlendMode = BLEND_Masked\n')

    def _material_image_path(self, library, material):
        texture = library.gltf['materials'][material]['pbrMetallicRoughness']['baseColorTexture']['index']
        image = library.gltf['images'][library.gltf['textures'][texture]['source']]
        return Path(library.package.out_dir) / image['uri']

    def test_later_mask_material_cannot_overwrite_a_cached_input(self):
        self._masked_materials()
        folder = self.root / 'late-mask'
        folder.mkdir()
        library = tool.Library(str(folder), 512)
        first = library.material('A')
        parts = [(self.primitives[0], first)]
        tag = library._bake_tag('mesh', 'impostor', parts)
        path = self._material_image_path(library, first)
        before = path.read_bytes()
        second = library.material('B')
        self.assertEqual(before, path.read_bytes())
        self.assertNotEqual(path, self._material_image_path(library, second))
        self.assertEqual(tag, library._bake_tag('mesh', 'impostor', parts))

    def test_shared_color_mask_changes_real_bake_names_and_pixels(self):
        self._masked_materials()
        tags = {'baked': [], 'impostor': []}
        for run, alpha in enumerate((0, 255)):
            Image.new('L', (4, 4), alpha).save(self.raw / 'MaskB.png')
            folder = self.root / ('mask-build-' + str(run))
            folder.mkdir()
            library = tool.Library(str(folder), 512)
            first = library.material('A')
            for kind in tags:
                library._bake_tag('mesh', kind, [(self.primitives[0], first)], 12 if kind == 'baked' else None)
            second = library.material('B')
            parts = [(self.primitives[0], second)]
            for bake, kind in ((tool.impostor, 'impostor'), (tool.baked_building, 'baked')):
                args = (12,) if kind == 'baked' else ()
                _, material = bake(parts, library, str(folder), 'mesh', *args)
                tags[kind].append(library.gltf['materials'][material]['name'])
                with Image.open(self._material_image_path(library, material)) as picture:
                    pixels = numpy.asarray(picture.convert('RGBA')).copy()
                if alpha:
                    self.assertGreater(pixels[:, :, 0].max(), 100)
                else:
                    self.assertEqual(pixels[:, :, :3].max(), 0)
                if kind == 'impostor':
                    self.assertEqual(pixels[:, :, 3].max(), alpha)
        for kind in tags:
            with self.subTest(kind=kind):
                self.assertNotEqual(*tags[kind])

    def test_same_stem_texture_inputs_keep_distinct_packaged_pixels(self):
        sources = []
        for name, color in (('first', 'red'), ('second', 'green')):
            directory = self.root / name
            directory.mkdir()
            path = directory / 'Shared.png'
            Image.new('RGB', (4, 4), color).save(path)
            sources.append(str(path))
        for color in (False, True):
            with self.subTest(color=color):
                folder = self.root / ('ordinary-' + str(color))
                gltf = {}
                package = tool.fix.Package(gltf, str(folder), 512)
                first = package.texture(sources[0], color)
                first_uri = gltf['images'][gltf['textures'][first]['source']]['uri']
                before = (folder / first_uri).read_bytes()
                second = package.texture(sources[1], color)
                second_uri = gltf['images'][gltf['textures'][second]['source']]['uri']
                self.assertEqual(before, (folder / first_uri).read_bytes())
                self.assertNotEqual(first_uri, second_uri)
                self.assertEqual(first, package.texture(sources[0], color))
                other = {}
                copy_package = tool.fix.Package(other, str(folder / 'copy'), 512)
                copy_package.texture(sources[0], color)
                self.assertEqual(first_uri, other['images'][0]['uri'])

    def test_content_names_preserve_texture_encoding_and_neutralization(self):
        for neutral in (False, True):
            stem = 'bmw_logo' if neutral else 'ordinary'
            path = self.raw / (stem + '.png')
            original = Image.new('RGB', (4, 4), (192, 64, 16))
            original.paste((0, 128, 32), (2, 0, 4, 4))
            original.save(path)
            for color in (False, True):
                with self.subTest(neutral=neutral, color=color):
                    folder = self.root / (stem + str(color))
                    gltf = {}
                    package = tool.fix.Package(gltf, str(folder), 512)
                    package.texture(str(path), color)
                    uri = gltf['images'][0]['uri']
                    data = (folder / uri).read_bytes()
                    image_format = 'JPEG' if color or neutral else 'PNG'
                    expected = Image.new('RGB', (8, 8), (96, 96, 24)) if neutral else original
                    output = io.BytesIO()
                    expected.save(output, format=image_format, **({'quality': 88} if color else {'optimize': True}))
                    self.assertEqual(data, output.getvalue())
                    suffix = '.jpg' if image_format == 'JPEG' else '.png'
                    self.assertEqual(uri, 'textures/texture_' + hashlib.sha256(data).hexdigest() + suffix)

    def test_equal_mask_pixels_share_one_packaged_image(self):
        self._masked_materials()
        Image.new('L', (4, 4), 255).save(self.raw / 'MaskB.png')
        folder = self.root / 'same-mask'
        folder.mkdir()
        library = tool.Library(str(folder), 512)
        first = library.material('A')
        path = self._material_image_path(library, first)
        before = path.read_bytes()
        second = library.material('B')
        self.assertEqual(path, self._material_image_path(library, second))
        self.assertEqual(before, path.read_bytes())

    def test_geometry_and_settings_identity_uses_values_not_array_layout(self):
        folder = self.root / 'identity'
        folder.mkdir()
        library = tool.Library(str(folder), 512)
        material = library.material('Red')
        original = self.primitives[0]
        tag = library._bake_tag('mesh', 'baked', [(original, material)], 24)
        for field in ('positions', 'normals', 'uvs', 'triangles'):
            changed = copy.deepcopy(original)
            changed[field].flat[0] += 1
            self.assertNotEqual(tag, library._bake_tag('mesh', 'baked', [(changed, material)], 24))
        layout = {key: numpy.asfortranarray(value.astype('>i8' if key == 'triangles' else '>f8'))
                  if isinstance(value, numpy.ndarray) else value for key, value in original.items()}
        self.assertEqual(tag, library._bake_tag('mesh', 'baked', [(layout, material)], 24))
        self.assertNotEqual(tag, library._bake_tag('mesh', 'baked', [(original, material)], 8))
        with mock.patch.object(tool, 'BAKE_DENSITY', tool.BAKE_DENSITY + 1):
            self.assertNotEqual(tag, library._bake_tag('mesh', 'baked', [(original, material)], 24))

    def test_slot_fallbacks_remain_unchanged(self):
        row = {'materials': [None, 'MaterialInstanceDynamic /Game/Fixture/Runtime.Runtime']}
        self.assertEqual(tool.slot_materials(row, self.primitives), ['Own0', 'Own1'])
        self.assertEqual(tool.slot_materials({'materials': []}, self.primitives), ['Own0', 'Own1'])


if __name__ == '__main__':
    unittest.main()
