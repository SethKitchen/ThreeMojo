# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Construct DWA stream variants, then require the pinned native decoder.

Usage: python variants.py PATH/TO/reference PATH/TO/libOpenEXR-3_1.so DIR
The input files in DIR come from reference.cpp. Only trusted local fixtures
are passed to the native Huffman API. No variant uses the Mojo decoder.
"""
import ctypes
import pathlib
import struct
import subprocess
import sys
import zlib

reference, library, directory = sys.argv[1:]
root = pathlib.Path(directory)
lib = ctypes.CDLL(library)
unhuf = getattr(lib, "_ZN7Imf_3_113hufUncompressEPKciPti")
unhuf.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]

def header(data):
    at = 8
    attrs = []
    while data[at]:
        end = data.index(0, at)
        name = data[at:end].decode()
        at = end + 1
        end = data.index(0, at)
        kind = data[at:end].decode()
        at = end + 1
        length, = struct.unpack_from('<I', data, at)
        at += 4
        attrs.append((name, kind, data[at:at+length]))
        at += length
    return attrs, at + 1

def file_bytes(attrs, blocks):
    result = bytearray(struct.pack('<II', 20000630, 2))
    for name, kind, value in attrs:
        result += name.encode()+b'\0'+kind.encode()+b'\0'+struct.pack('<I',len(value))+value
    result += b'\0'
    at = len(result) + len(blocks)*8
    for _, block in blocks:
        result += struct.pack('<Q',at)
        at += 8 + len(block)
    for line, block in blocks:
        result += struct.pack('<iI',line,len(block))+block
    return result

def save(name, data):
    path = root / (name+'.exr')
    path.write_bytes(data)
    subprocess.run([reference,'decode',str(path),str(path)+'.rgba'],check=True)

for codec in [8,9]:
    data=(root / f'c{codec}_s0.exr').read_bytes()
    attrs, start=header(data)
    blocks_count=2
    blocks=[]
    for i in range(blocks_count):
        at,=struct.unpack_from('<Q',data,start+i*8)
        line,length=struct.unpack_from('<iI',data,at)
        blocks.append((line,data[at+8:at+8+length]))
    for variant in ['deflate','legacy0','legacy1','insensitive','rule_shadow']:
        converted=[]
        for line,block in blocks:
            # Last partial strips can be stored uncompressed.
            rows=min(32 if codec==8 else 256,(35 if codec==8 else 257)-line)
            if len(block)==rows*9*8:
                converted.append((line,block));continue
            fields=list(struct.unpack_from('<11Q',block))
            assert fields[0]==2
            rule_size,=struct.unpack_from('<H',block,88)
            rules=block[88:88+rule_size]
            at=88+rule_size
            unknown=block[at:at+fields[2]];at+=fields[2]
            ac=block[at:at+fields[3]];at+=fields[3]
            dc=block[at:at+fields[4]];at+=fields[4]
            rle=block[at:at+fields[5]]
            if variant in ['deflate','legacy0']:
                tokens=(ctypes.c_uint16*fields[8])()
                unhuf(ac,len(ac),tokens,len(tokens))
                tokens=list(tokens)
                if variant=='legacy0':
                    pos=1
                    for j,token in enumerate(tokens):
                        if token==0xff00:
                            remaining=64-pos
                            tokens[j]=0 if remaining==1 else 0xff00|remaining
                            pos=64
                        elif token>>8==0xff:pos+=token&255
                        else:pos+=1
                        assert pos<=64
                        if pos==64:pos=1
                ac=zlib.compress(struct.pack('<'+'H'*len(tokens),*tokens),9)
                fields[3]=len(ac);fields[10]=1
            if variant in ['legacy0','legacy1']:
                fields[0]=0 if variant=='legacy0' else 1
                rules=b''
            if variant=='rule_shadow':
                # Multiple matching rules preserve every assigned CSC slot.
                rules=struct.pack('<H',len(rules)+4)+rules[2:]+b'B\0\x14\x01'
            if variant=='insensitive':
                rules=bytearray(rules);offset=2
                while offset<len(rules):
                    end=rules.index(0,offset)
                    rules[offset:end]=rules[offset:end].lower()
                    rules[end+1]|=1
                    offset=end+3
            converted.append((line,struct.pack('<11Q',*fields)+rules+unknown+ac+dc+rle))
        save(f'c{codec}_{variant}',file_bytes(attrs,converted))
    # Pure UNKNOWN and pure RLE paths still use the supported Y output.
    for variant in ['unknown','rle','uppercase_rule','incomplete_csc','incomplete_rle']:
        w=h=16
        kind=1 if variant in ['rle','incomplete_rle'] else 2
        channel=b'Y\0'+struct.pack('<I4BII',kind,0,0,0,0,1,1)+b'\0'
        attrs2=[]
        for name,typ,value in attrs:
            if name=='channels':value=channel
            elif name in ['dataWindow','displayWindow']:value=struct.pack('<4i',0,0,w-1,h-1)
            attrs2.append((name,typ,value))
        values=[0.25+(i%4)*0.125 for i in range(w*h)]
        raw=struct.pack('<'+('f' if kind==2 else 'e')*len(values),*values)
        fields=[2,0,0,0,0,0,0,0,0,0,0]
        if kind==2:
            compressed=zlib.compress(raw)
            fields[1]=len(raw);fields[2]=len(compressed);rules=struct.pack('<H',2)
            if variant=='uppercase_rule':
                # The native reader folds candidates, not serialized rules.
                # This uppercase insensitive suffix therefore does not match.
                rules=struct.pack('<H',6)+b'Y\0\x05\x02'
            elif variant=='incomplete_csc':
                rules=struct.pack('<H',6)+b'Y\0\x10\x02'
        else:
            planar=raw[0::2]+raw[1::2]
            encoded=b''.join(bytes([256-len(planar[i:i+127])])+planar[i:i+127] for i in range(0,len(planar),127))
            compressed=zlib.compress(encoded)
            fields[5]=len(compressed);fields[6]=len(encoded);fields[7]=len(raw)
            rules=struct.pack('<H',6)+b'Y\0\x08\x01'
            if variant=='incomplete_rle':
                rules=struct.pack('<H',6)+b'Y\0\x18\x01'
        save(f'c{codec}_{variant}',file_bytes(attrs2,[(0,struct.pack('<11Q',*fields)+rules+compressed)]))
print('20 DWA variants accepted by OpenEXR 3.1.5')
