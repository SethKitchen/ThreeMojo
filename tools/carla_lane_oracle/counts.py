# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Small source-only fixture/count derivation. No Mojo/native process is run."""
from fractions import Fraction as F
from pathlib import Path
import hashlib, json, math, os, xml.etree.ElementTree as ET
base=Path(__file__).resolve().parents[2]
root=Path(os.environ.get('CARLA_LANE_ORACLE_OUTPUT', str(base/'out/carla-lane-oracle')))
root.mkdir(parents=True, exist_ok=True)
xml=base/'assets/carla/town.xodr'
town=ET.parse(xml).getroot()
# The original 250 m workload, its stored binary64 stepping, and 1 m steps.
eps=10.0*2.220446049250313e-16
s=10.0*eps; first=s; spans=[]
while True:
    remaining=250.0-s-0.000001
    step=min(1.0,remaining)
    if step<0.000001:
        spans.append((first,s)); break
    s+=step-eps
    if s-first>100.0:
        spans.append((first,s)); first=s
# Independent circle sagitta: 2 R sin(k L / 4)^2. Alternating-series bounds
# x-x^3/6 <= sin(x) <= x on these positive small arguments use exact rationals.
k=F.from_float(0.000001); radius=F.from_float(1.0/0.000001)+F(7,4)
def sagitta(span):
    x=k*F.from_float(span)/4
    assert F(0)<x<F(1,10000)
    lower=2*radius*(x-x**3/6)**2
    upper=2*radius*x*x
    return {'lower_m':float(lower),'upper_m':float(upper)}
results=[]; total=0
for a,b in spans:
    span=b-a; whole=sagitta(span); half=sagitta(span/2)
    if whole['lower_m']>0.001:
        assert half['upper_m']<0.001
        leaves=2
    else:
        assert whole['upper_m']<0.001
        leaves=1
    results.append({'low_s':a,'high_s':b,'span':span,'whole_sagitta':whole,'half_sagitta':half,'leaves':leaves})
    total+=leaves
assert total==5
lanes=[]
for road in sorted(town.findall('road'),key=lambda r:int(r.get('id'))):
    sections=road.findall('lanes/laneSection')
    for section_index, section in enumerate(sections):
        start=float(section.get('s'));end=float(sections[section_index+1].get('s')) if section_index+1<len(sections) else float(road.get('length'))
        for lane in sorted(section.findall('./*/lane'),key=lambda l:int(l.get('id'))):
            if int(lane.get('id')):
                lanes.append({'road':int(road.get('id')),'section':section_index,'lane':int(lane.get('id')),'low_s':start,'high_s':end})
assert len(lanes)==26
road1=next(r for r in town.findall('road') if r.get('id')=='1')
section=road1.findall('lanes/laneSection')[1]
widths=section.find("right/lane[@id='-1']").findall('width')
assert [w.attrib for w in widths]==[{'sOffset':'0','a':'3.5','b':'0','c':'0','d':'0'},{'sOffset':'10','a':'3.5','b':'0.05','c':'0','d':'0'}]
rows=math.ceil((60-30)/2)+1
assert rows==16
out={'fixture_sha256':hashlib.sha256(xml.read_bytes()).hexdigest(),'native_execution':False,'gentle_base_spans':results,'gentle_leaf_count':total,'gentle_margin_note':'Circle bounds are geometric justification with large margins, not a Float64 expression-graph certificate. Native expected-count/control checks remain required.','town_lane_groups':lanes,'town_lane_group_count':len(lanes),'town_index_count':{'value':987,'basis':'Retained native candidate observation; not independently recomputed here. New tests pair it with parameter coverage and cached enclosure sanity checks.'},'mesh':{'section0_vertices':16,'section1_rows':rows,'section1_lane_vertices':2*rows,'section1_lane_triangles':2*(rows-1),'section1_vertices':4*2*rows,'road_vertices':16+4*2*rows,'section1_with_walls_vertices':6*2*rows,'joined_vertices':4+2*rows,'joined_triangles':2+2*(rows-1)+2,'appended_triangles':2+2*(rows-1)}}
(root/'count-derivation.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps({k:out[k] for k in ['gentle_base_spans','gentle_leaf_count','town_lane_group_count','mesh']},indent=2))
