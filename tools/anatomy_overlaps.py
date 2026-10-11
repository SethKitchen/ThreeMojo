# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Localize and classify canonical sampled overlaps (#595). Evidence, never clearance.

The tool checks every legacy bone, knee and neighboring-spine pair at three
grid widths. It localizes each pair that #595 lists and each pair with a
sampled common interior at any width. A localization records the grid witness,
the box of common-interior cell centers and two local refinements around the
witness. A negative refined value is a point inside both canonical fields. A
nonnegative value does not prove clearance elsewhere. No acceptance threshold
is applied, because none is established.

Use --build once, then reuse the source-bound probe. Each probe execution
has the unchanged five-second runtime limit.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import anatomy_validity as av

ROOT = av.ROOT
TOOL = 'tools/anatomy_overlaps.py'
SCHEMA_VERSION = 1
STEPS_MM = (5.0, 3.0, 2.0)
ISSUE = 'https://github.com/SethKitchen/ThreeMojo/issues/595'
LEGACY_GROUPS = ('bones', 'knee', 'spine')

# The 36 pairs that #595 lists from the 5 mm canonical report of #289/#592.
ISSUE_595_PAIRS = (
    'canonical/bones/foot/talus|tibia',
    'canonical/bones/foot/calcaneus|foot/talus',
    'canonical/bones/foot/navicular|foot/talus',
    'canonical/bones/foot/calcaneus|foot/cuboid',
    'canonical/bones/foot/intermediate_cuneiform|foot/navicular',
    'canonical/bones/foot/cuboid|foot/lateral_cuneiform',
    'canonical/bones/foot/intermediate_cuneiform|foot/medial_cuneiform',
    'canonical/bones/foot/first_metatarsal|foot/medial_cuneiform',
    'canonical/bones/foot/medial_cuneiform|foot/second_metatarsal',
    'canonical/bones/foot/intermediate_cuneiform|foot/lateral_cuneiform',
    'canonical/bones/foot/intermediate_cuneiform|foot/second_metatarsal',
    'canonical/bones/foot/lateral_cuneiform|foot/third_metatarsal',
    'canonical/bones/foot/first_metatarsal|foot/second_metatarsal',
    'canonical/bones/foot/first_metatarsal|foot/hallux_proximal_phalanx',
    'canonical/bones/foot/second_metatarsal|foot/third_metatarsal',
    'canonical/bones/foot/second_metatarsal|foot/second_toe_proximal_phalanx',
    'canonical/bones/foot/third_metatarsal|foot/third_toe_proximal_phalanx',
    'canonical/bones/foot/hallux_distal_phalanx|foot/hallux_proximal_phalanx',
    'canonical/bones/foot/third_toe_middle_phalanx|foot/third_toe_proximal_phalanx',
    'canonical/bones/foot/fourth_toe_middle_phalanx|foot/fourth_toe_proximal_phalanx',
    'canonical/bones/foot/fifth_toe_middle_phalanx|foot/fifth_toe_proximal_phalanx',
    'canonical/knee/femur|knee/cartilage',
    'canonical/knee/femur|knee/medial',
    'canonical/knee/femur|knee/lateral',
    'canonical/knee/femur|knee/mcl',
    'canonical/knee/femur|knee/lcl',
    'canonical/knee/knee/cartilage|tibia',
    'canonical/knee/knee/medial|tibia',
    'canonical/knee/knee/mcl|tibia',
    'canonical/knee/knee/lcl|tibia',
    'canonical/knee/fibula|knee/lcl',
    'canonical/knee/knee/cartilage|patella',
    'canonical/knee/knee/cartilage|knee/medial',
    'canonical/knee/knee/mcl|knee/medial',
    'canonical/knee/knee/lateral|knee/lcl',
    'canonical/spine/cervical/2|cervical/3',
)

# Interface rules. Each one makes the later field give way to the earlier
# field, so the two share no interior. None of them is a volume allowance.
RULES = {
    'foot_articulation_precedence':
        'A foot bone gives way to each articulating foot bone before it in the '
        'segment accounting order.',
    'talus_yields_to_tibia': 'The talus gives way to the placed tibia.',
    'fibula_yields_to_tibia': 'The fibula gives way to the placed tibia.',
    'knee_tissue_precedence':
        'Knee tissues give way to the leg bones, then to the cartilage, then to '
        'the menisci, in that order.',
    'cervical_pillar_endplane_extent':
        'Each cervical articular pillar ends at its body endplane levels.',
}

# Classes of the observed common interiors. A class is a judgment about the
# authored representation. It is not a measured biological tolerance.
CLASSES = {
    'unintended_articular_interior':
        'Two bones meet at a joint. Real bones there are separated by articular '
        'surfaces; the template has no joint space. A common interior is a '
        'construction error.',
    'unintended_layer_interior':
        'A tissue layer lies on a bone or on another tissue. A common interior '
        'double-counts the same space.',
    'attachment_representation':
        'An authored ligament end or attached tissue lies at an attachment '
        'landmark inside the other field. The attachment is real anatomy; the '
        'shared volume is not. It becomes a zero-volume interface.',
    'unintended_path_interior':
        'A ligament path passes through a bone or tissue that it does not '
        'attach to at that place.',
}


CLASSIFICATION = {
    'canonical/bones/foot/talus|tibia': (
        'talus_yields_to_tibia', 'unintended_articular_interior',
        'Talocrural joint. The witness lies at the medial malleolus over the talar body.'),
    'canonical/bones/fibula|tibia': (
        'fibula_yields_to_tibia', 'unintended_articular_interior',
        'Proximal tibiofibular joint. Found at 3 and 2 mm only; the 5 mm grid missed it.'),
    'canonical/knee/femur|knee/cartilage': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The femoral cartilage lens extends into the condyles and the trochlea.'),
    'canonical/knee/knee/cartilage|tibia': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The tibial cartilage lens extends into the plateau.'),
    'canonical/knee/knee/cartilage|patella': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The patellar cartilage lens extends into the patella.'),
    'canonical/knee/femur|knee/medial': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The medial meniscus tube reaches into the medial femoral condyle.'),
    'canonical/knee/femur|knee/lateral': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The lateral meniscus tube reaches into the lateral femoral condyle.'),
    'canonical/knee/knee/medial|tibia': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The medial meniscus tube reaches into the tibial plateau.'),
    'canonical/knee/knee/cartilage|knee/medial': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'The medial meniscus and the plateau cartilage occupy the same space.'),
    'canonical/knee/knee/cartilage|knee/lateral': (
        'knee_tissue_precedence', 'unintended_layer_interior',
        'Found at 2 mm only. The lateral meniscus and the plateau cartilage occupy the same space.'),
    'canonical/knee/femur|knee/mcl': (
        'knee_tissue_precedence', 'attachment_representation',
        'The MCL femoral end lies at its authored epicondyle landmark inside the femur.'),
    'canonical/knee/femur|knee/lcl': (
        'knee_tissue_precedence', 'attachment_representation',
        'The LCL femoral end lies at its authored epicondyle landmark inside the femur.'),
    'canonical/knee/fibula|knee/lcl': (
        'knee_tissue_precedence', 'attachment_representation',
        'The LCL fibular end is authored at the fibular head center.'),
    'canonical/knee/knee/mcl|knee/medial': (
        'knee_tissue_precedence', 'attachment_representation',
        'The deep MCL attaches to the medial meniscus. The template has one MCL '
        'band and no deep layer, so the overlap is not a measured attachment volume.'),
    'canonical/knee/knee/mcl|tibia': (
        'knee_tissue_precedence', 'unintended_path_interior',
        'The witness lies near the joint line, far above the authored tibial attachment.'),
    'canonical/knee/knee/lcl|tibia': (
        'knee_tissue_precedence', 'unintended_path_interior',
        'The LCL does not attach to the tibia.'),
    'canonical/knee/knee/lateral|knee/lcl': (
        'knee_tissue_precedence', 'unintended_path_interior',
        'The LCL does not attach to the lateral meniscus.'),
    'canonical/knee/knee/cartilage|knee/mcl': (
        'knee_tissue_precedence', 'unintended_path_interior',
        'Found at 2 mm only. The MCL path passes through the medial cartilage lens.'),
    'canonical/knee/knee/cartilage|knee/lcl': (
        'knee_tissue_precedence', 'unintended_path_interior',
        'Found at 2 mm only. The LCL path passes through the lateral cartilage lens.'),
}
for _pair in ('calcaneus|foot/talus', 'navicular|foot/talus', 'calcaneus|foot/cuboid',
              'intermediate_cuneiform|foot/navicular', 'cuboid|foot/lateral_cuneiform',
              'intermediate_cuneiform|foot/medial_cuneiform',
              'first_metatarsal|foot/medial_cuneiform', 'medial_cuneiform|foot/second_metatarsal',
              'intermediate_cuneiform|foot/lateral_cuneiform',
              'intermediate_cuneiform|foot/second_metatarsal',
              'lateral_cuneiform|foot/third_metatarsal', 'first_metatarsal|foot/second_metatarsal',
              'first_metatarsal|foot/hallux_proximal_phalanx',
              'second_metatarsal|foot/third_metatarsal',
              'second_metatarsal|foot/second_toe_proximal_phalanx',
              'third_metatarsal|foot/third_toe_proximal_phalanx',
              'hallux_distal_phalanx|foot/hallux_proximal_phalanx',
              'third_toe_middle_phalanx|foot/third_toe_proximal_phalanx',
              'fourth_toe_middle_phalanx|foot/fourth_toe_proximal_phalanx',
              'fifth_toe_middle_phalanx|foot/fifth_toe_proximal_phalanx',
              'medial_cuneiform|foot/navicular', 'lateral_cuneiform|foot/navicular',
              'fourth_metatarsal|foot/lateral_cuneiform', 'fourth_metatarsal|foot/third_metatarsal',
              'fourth_metatarsal|foot/fourth_toe_proximal_phalanx',
              'fifth_metatarsal|foot/fifth_toe_proximal_phalanx',
              'second_toe_middle_phalanx|foot/second_toe_proximal_phalanx',
              'second_toe_distal_phalanx|foot/second_toe_middle_phalanx',
              'third_toe_distal_phalanx|foot/third_toe_middle_phalanx',
              'fourth_toe_distal_phalanx|foot/fourth_toe_middle_phalanx',
              'fifth_toe_distal_phalanx|foot/fifth_toe_middle_phalanx'):
    CLASSIFICATION['canonical/bones/foot/' + _pair] = (
        'foot_articulation_precedence', 'unintended_articular_interior',
        'Articulating foot bones.')
for _n in range(2, 7):
    CLASSIFICATION[f'canonical/spine/cervical/{_n}|cervical/{_n + 1}'] = (
        'cervical_pillar_endplane_extent', 'unintended_articular_interior',
        'Facet region. The rounded pillar ends crossed the disc space into the '
        'next pillar.')


def tool_sha256(root=ROOT):
    return hashlib.sha256((Path(root)/TOOL).read_bytes()).hexdigest()


def run_probe(probe, mode, part, step, spec):
    """Run one probe request under the five-second limit; parse JSON lines."""
    command = [str(probe), mode, part, str(step), str(spec['stature_m']), spec['sex'],
               spec['side'], spec['athleticism']]
    result = subprocess.run(command, check=True, text=True, capture_output=True,
                            timeout=5, cwd=ROOT)
    rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    av.finite_tree(rows)
    return rows


def legacy_pair_ids(catalog):
    """Return the complete legacy pair contract from the checked catalog."""
    expected = {group: set() for group in LEGACY_GROUPS}

    def add(group, first, second):
        names = sorted((first.replace(' ', '_'), second.replace(' ', '_')))
        expected[group].add('canonical/' + group + '/' + '|'.join(names))

    for index, first in enumerate(catalog):
        for second in catalog[index + 1:]:
            group = av.legacy_pair_group(first, second)
            if group:
                add(group, first['label'], second['label'])
    for region, indices in (('thoracolumbar', range(17)), ('cervical', range(2, 8))):
        for index in indices:
            body = f'{region}/{index}'
            disc = body + '/disc'
            add('spine', body, disc)
            if region == 'thoracolumbar' and index == 16:
                continue
            below = 'thoracolumbar/0' if region == 'cervical' and index == 7 else f'{region}/{index + 1}'
            add('spine', body, below)
            add('spine', below, disc)
    if {group: len(pairs) for group, pairs in expected.items()} != {'bones': 435, 'knee': 30, 'spine': 67}:
        raise ValueError('legacy pair catalog does not match the 532-pair contract')
    return expected


def sweep(probe, spec, catalog):
    """Return {pair_id: {step_mm: row}} for every legacy pair record."""
    found = {}
    expected = legacy_pair_ids(catalog)
    for step in STEPS_MM:
        groups = av.annotate_diagnostics(
            {mode: run_probe(probe, mode, 'none', step, spec) for mode in LEGACY_GROUPS})
        for group, rows in groups.items():
            observed = {row['pair_id'] for row in rows if row['record'] == 'pair'}
            if observed != expected[group]:
                raise ValueError(f'{group} diagnostic pair inventory differs at {step} mm')
            for row in rows:
                if row['record'] == 'pair':
                    entry = found.setdefault(row['pair_id'], {'group': group, 'rows': {}})
                    entry['rows'][step] = row
    if any(len(entry['rows']) != len(STEPS_MM) for entry in found.values()):
        raise ValueError('a legacy pair is missing at one grid width')
    return found


def witness_request(group, row, labels):
    """Return the probe mode and part that localize one legacy pair."""
    if group == 'spine':
        first, second = row['first'], row['second']
        region, _, number = first.partition('/')
        if (region not in ('cervical', 'thoracolumbar') or not number.isdigit()
                or second != f'{region}/{int(number) + 1}'):
            raise ValueError(f'no localization for spine pair {row["pair_id"]}')
        return 'spine-witness', first
    i, j = sorted((labels[row['first']], labels[row['second']]))
    return 'pairs', f'witness:{i}:{j}'


def check_witness(record, row):
    """The witness pass must repeat the diagnostic grid exactly."""
    for key in ('samples', 'overlap_samples', 'overlap_volume_m3'):
        if record[key] != row[key]:
            raise ValueError(f'witness pass changed {key}')
    if row['samples'] and record['signed_field_witness_m'] != row['signed_field_witness_m']:
        raise ValueError('witness pass changed the field witness')
    return record


def status(grids):
    """Name what the samples show, without a clearance claim."""
    sampled = any(grid['overlap_samples'] > 0 for grid in grids)
    refined = [grid['refined_field_witness_m'] for grid in grids
               if grid.get('refined_field_witness_m') is not None]
    if sampled or any(value < 0 for value in refined):
        return 'common_interior_found'
    return 'no_common_interior_sampled'


def build(probe, provenance, spec):
    catalog = av.validate_catalog(run_probe(probe, 'pairs', 'catalog', 5, spec))
    labels = {row['label']: row['index'] for row in catalog}
    found = sweep(probe, spec, catalog)
    missing = [pair for pair in ISSUE_595_PAIRS if pair not in found]
    if missing:
        raise ValueError(f'issue pairs are not in the legacy diagnostics: {missing}')
    tracked = sorted(set(ISSUE_595_PAIRS) | {
        pair for pair, entry in found.items()
        if any(row['overlap_samples'] > 0 for row in entry['rows'].values())})
    pairs = []
    for pair in tracked:
        if pair not in CLASSIFICATION:
            raise ValueError(f'unclassified sampled overlap: {pair}')
        entry = found[pair]
        grids = []
        for step in STEPS_MM:
            row = entry['rows'][step]
            mode, part = witness_request(entry['group'], row, labels)
            records = run_probe(probe, mode, part, step, spec)
            if len(records) != 1 or records[0].get('record') != 'witness':
                raise ValueError('witness probe returned the wrong record count')
            record = check_witness(records[0], row)
            record.pop('record')
            for key in ('first', 'second', 'first_id', 'second_id'):
                record.pop(key, None)
            grids.append(record)
        rule, kind, note = CLASSIFICATION[pair]
        pairs.append({'pair_id': pair, 'group': entry['group'],
                      'first': entry['rows'][STEPS_MM[0]]['first'],
                      'second': entry['rows'][STEPS_MM[0]]['second'],
                      'frame_id': entry['rows'][STEPS_MM[0]]['frame_id'],
                      'listed_in_issue_595': pair in ISSUE_595_PAIRS,
                      'classification': kind, 'interface_rule': rule, 'note': note,
                      'grids': grids, 'status': status(grids)})
    counts = {}
    for step in STEPS_MM:
        hits = [pair for pair, entry in found.items() if entry['rows'][step]['overlap_samples'] > 0]
        counts[str(step)] = {group: sum(1 for pair in hits if found[pair]['group'] == group)
                             for group in LEGACY_GROUPS}
    return {
        'schema_version': SCHEMA_VERSION, 'issue': ISSUE,
        'result_label': 'template geometry evidence; not clearance or biomechanical validation',
        'build_provenance': provenance, 'tool_sha256': tool_sha256(),
        'spec': spec, 'steps_mm': list(STEPS_MM),
        'checked_pairs_per_step': len(found),
        'pairs_with_sampled_common_interior': counts,
        'reproduction': 'python3 tools/anatomy_overlaps.py --build --output <file>',
        'interface_rules': RULES, 'classes': CLASSES,
        'pairs': pairs,
        'limits': [
            'A refined witness searches two cubes around the grid witness only. It is not a global minimum.',
            'A negative field value is a point inside both canonical fields. It is not a penetration depth.',
            'No sampled common interior does not prove clearance. Thin overlap can lie between samples.',
            'Field values are float32. Interfaces between differently placed frames are exact only to coordinate roundoff.',
            'Lower-limb tissue pairs from #596 are outside this localization. The template report retains their findings.',
            'No clinical, engineering or biological acceptance threshold is applied.'],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--mojo', default=str(ROOT/'.venv/bin/mojo'))
    parser.add_argument('--probe', type=Path, default=ROOT/'.cache/anatomy-probe')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    spec = {'stature_m': 1.8288, 'sex': 'male', 'side': 'right', 'athleticism': 'untoned'}
    try:
        probe = args.probe.resolve()
        provenance = av.prepare_probe(ROOT, probe, args.mojo, args.build)
        snapshot = av.source_snapshot(ROOT)
        metadata = probe.with_suffix(probe.suffix+'.provenance.json').read_bytes()
        tool_digest = tool_sha256()
        result = build(probe, provenance, spec)
        av.verify_report_inputs(ROOT, probe, provenance, snapshot, metadata)
        if result['tool_sha256'] != tool_digest or tool_sha256() != tool_digest:
            raise ValueError('overlap tool changed during execution; rerun before reporting')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError) as error:
        print(f'anatomy overlap localization failed: {error}', file=sys.stderr)
        return 1
    print(f'{args.output}: localized evidence; not clearance')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
