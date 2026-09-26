// Writes the VTK fixtures in this folder and reads each with three.js
// 0.180's VTKLoader, into vtk.json. Run it where `three` and
// `@xmldom/xmldom` are installed: xmldom stands in for the browser's
// DOMParser, which the XML reader needs.
import { writeFileSync } from 'node:fs';
import { DOMParser } from '@xmldom/xmldom';
import * as fflate from 'three/examples/jsm/libs/fflate.module.js';
import { VTKLoader } from 'three/examples/jsm/loaders/VTKLoader.js';

globalThis.DOMParser = DOMParser;

const files = {};
const pad = ( text ) => text.padEnd( 200, ' ' );

// Legacy ASCII: points three to a line and one to a line, a word line
// with three numbers, polygons and a strip, and a color and a normal for
// each point.
files[ 'ascii.vtk' ] = `# vtk DataFile Version 3.0
${pad( 'point colors and normals' )}
ASCII
DATASET POLYDATA
POINTS 6 float
0 0 0 1 0 0 1 1 0
0 1 0
2 0 0.5
2 1 -1.5e-1

POLYGONS 2 9
4 0 1 2 3
3 1 4 5
TRIANGLE_STRIPS 1 5
4 0 1 3 2
POINT_DATA 6
NORMALS Normals float
0 0 1 0 0 1 0 0 1
0 0 1 0 0 1 0 1 0
COLOR_SCALARS rgb 3
1 0 0 0 1 0 0 0 1
0.5 0.5 0.5 1 1 1 0.02 0.2 0.9
`;

// Legacy ASCII with a color for each triangle, which three.js spreads over
// the triangle's corners after decoding it twice.
files[ 'cells.vtk' ] = `# vtk DataFile Version 3.0
${pad( 'cell colors' )}
ASCII
DATASET POLYDATA
POINTS 4 float
0 0 0 1 0 0 1 1 0 0 1 0
POLYGONS 2 8
3 0 1 2
3 0 2 3
CELL_DATA 2
COLOR_SCALARS cell 3
0.8 0.2 0.1
0.1 0.6 0.3
`;

// Legacy ASCII quirks. A line that starts with a word keeps its first
// run and leaves the shared pattern's lastIndex after it, so the next line
// is read from there, or not at all when it is shorter. A cell that names
// more points than it gives reads point zero. Unicode spaces separate, and
// a control character ends a number.
files[ 'quirks.vtk' ] = `# vtk DataFile Version 3.0
${pad( 'quirks' )}
ASCII
DATASET POLYDATA
POINTS 9 float
x 1 2 3
10 20 30 40 50 60
y 4 5 6 7 8
1 2 3
-1 .5 2e+1 3 4 5
1e+3 -2e-1 7\u0001
5\u00a06\u30007 8\u16809\u200a10
11\u202f12\u205f13 14\u2028 15\ufeff16 17\u2029 18 19
POLYGONS 3 12
3 0 1
4 0 1 2 3 # a comment
2 0 1
TRIANGLE_STRIPS 1 3
1 4
POINT_DATA  9
COLOR_SCALARS aZ_9 4
COLOR_SCALARS aZ_9 35
0.1 0.2 0.3 0.04 0.5 0.9 1 1 1
0 0 0 0.2 0.2 0.2 0.3 0.3 0.3 0.4 0.4 0.4 0.5 0.5 0.5
NORMALS n float
0 0 1 0 0 1 0 0 1 0 0 1 0 0 1 0 0 1 0 0 1 0 1 0
`;

// Legacy binary: big-endian floats and ints.
{
	const head = ( text ) => Buffer.from( text, 'latin1' );
	const floats = ( values ) => {
		const b = Buffer.alloc( values.length * 4 );
		values.forEach( ( v, i ) => b.writeFloatBE( v, i * 4 ) );
		return b;
	};
	const ints = ( values ) => {
		const b = Buffer.alloc( values.length * 4 );
		values.forEach( ( v, i ) => b.writeInt32BE( v, i * 4 ) );
		return b;
	};
	const nl = Buffer.from( '\n' );
	files[ 'binary.vtk' ] = Buffer.concat( [
		head( '# vtk DataFile Version 3.0\n' + pad( 'binary' ) + '\nBINARY\nDATASET POLYDATA\nPOINTS 5 float\n' ),
		floats( [ 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0.5, 2, 0.25 ] ), nl,
		head( 'POLYGONS 2 9\n' ),
		ints( [ 4, 0, 1, 2, 3, 3, 2, 4, 3 ] ), nl,
		head( 'POINT_DATA 5\nNORMALS Normals float\n' ),
		floats( [ 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0 ] ),
	] );
}

// XML. Points, normals, polygons and strips in each encoding.
const points = [ 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 2, 0, 1 ];
const normals = [ 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0 ];
const polyConnectivity = [ 0, 1, 2, 3, 1, 4, 2 ];
const polyOffsets = [ 4, 7 ];
const stripConnectivity = [ 0, 1, 3, 2, 4 ];
const stripOffsets = [ 5 ];

function f32( values ) {
	return new Uint8Array( new Float32Array( values ).buffer );
}
function i32( values ) {
	return new Uint8Array( new Int32Array( values ).buffer );
}
function i64( values ) {
	const out = new Int32Array( values.length * 2 );
	values.forEach( ( v, i ) => { out[ 2 * i ] = v; out[ 2 * i + 1 ] = v < 0 ? - 1 : 0; } );
	return new Uint8Array( out.buffer );
}
function b64( bytes ) {
	return Buffer.from( bytes ).toString( 'base64' );
}
function u32( n ) {
	return new Uint8Array( new Uint32Array( [ n ] ).buffer );
}
function cat( ...parts ) {
	const out = new Uint8Array( parts.reduce( ( a, p ) => a + p.length, 0 ) );
	let at = 0;
	for ( const p of parts ) { out.set( p, at ); at += p.length; }
	return out;
}

function vtp( attrs, arrays, appended = '' ) {
	return `<?xml version="1.0"?>
<!-- ${ 'a VTK XML poly data file '.repeat( 10 ) } -->
<VTKFile type="PolyData" version="1.0" byte_order="LittleEndian" ${ attrs }>
  <PolyData>
    <Piece NumberOfPoints="5" NumberOfVerts="0" NumberOfLines="0" NumberOfStrips="1" NumberOfPolys="2">
      <PointData Normals="Normals">${ arrays.normals }</PointData>
      <Points>${ arrays.points }</Points>
      <Strips>${ arrays.strips }</Strips>
      <Polys>${ arrays.polys }</Polys>
    </Piece>
  </PolyData>${ appended }
</VTKFile>
`;
}

{
	const a = ( type, name, comps, values, extra = '' ) =>
		`<DataArray type="${ type }" Name="${ name }" ${ comps ? `NumberOfComponents="${ comps }"` : '' } format="ascii"${ extra }>
          ${ values.join( ' ' ) }
        </DataArray>`;
	files[ 'ascii.vtp' ] = vtp( 'header_type="UInt32"', {
		normals: a( 'Float32', 'Normals', 3, normals ),
		points: a( 'Float32', 'Points', 3, points ),
		strips: a( 'Int64', 'connectivity', 0, stripConnectivity ) + a( 'Int64', 'offsets', 0, stripOffsets ),
		polys: a( 'Int32', 'connectivity', 0, polyConnectivity ) + a( 'Int32', 'offsets', 0, polyOffsets ),
	} );
}

{
	// Two strips and no polygons. three.js reads every strip from the
	// start of the connectivity, and the second one's length from the
	// offsets' difference after its first point.
	const a = ( type, name, values ) =>
		`<DataArray type="${ type }" Name="${ name }" format="ascii">${ values.join( ' ' ) }</DataArray>`;
	files[ 'strips.vtp' ] = vtp( 'header_type="UInt64"', {
		normals: '',
		points: `<DataArray type="Float32" NumberOfComponents="3" format="ascii">${ points.join( ' ' ) }</DataArray>`,
		strips: a( 'Int32', 'connectivity', [ 0, 1, 3, 2, 4, 1, 2 ] ) + a( 'Int32', 'offsets', [ 4, 7 ] ),
		polys: '',
	} ).replace( 'NumberOfStrips="1" NumberOfPolys="2"', 'NumberOfStrips="2" NumberOfPolys="0"' );
}

{
	// Inline base64 with a UInt32 byte count before each array.
	const a = ( type, name, comps, bytes ) =>
		`<DataArray type="${ type }" Name="${ name }" ${ comps ? `NumberOfComponents="${ comps }"` : '' } format="binary">${ b64( cat( u32( bytes.length ), bytes ) ) }</DataArray>`;
	files[ 'binary.vtp' ] = vtp( 'header_type="UInt32"', {
		normals: a( 'Float32', 'Normals', 3, f32( normals ) ),
		points: a( 'Float32', 'Points', 3, f32( points ) ),
		strips: a( 'Int64', 'connectivity', 0, i64( stripConnectivity ) ) + a( 'Int64', 'offsets', 0, i64( stripOffsets ) ),
		polys: a( 'Int32', 'connectivity', 0, i32( polyConnectivity ) ) + a( 'Int32', 'offsets', 0, i32( polyOffsets ) ),
	} );
}

{
	// zlib blocks: a header of UInt32 block count, sizes, then each
	// compressed block, all in one base64 text.
	const a = ( type, name, comps, bytes, blockSize ) => {
		const blocks = [];
		for ( let at = 0; at < bytes.length; at += blockSize ) blocks.push( fflate.zlibSync( bytes.slice( at, at + blockSize ) ) );
		const last = bytes.length % blockSize;
		const header = cat( u32( blocks.length ), u32( blockSize ), u32( last ), ...blocks.map( ( b ) => u32( b.length ) ) );
		// three.js decodes the header and the blocks as one base64 text,
		// padding the header to a multiple of three bytes.
		const padded = cat( header, new Uint8Array( ( 3 - header.length % 3 ) % 3 ) );
		return `<DataArray type="${ type }" Name="${ name }" ${ comps ? `NumberOfComponents="${ comps }"` : '' } format="binary">${ b64( cat( padded, ...blocks ) ) }</DataArray>`;
	};
	files[ 'zlib.vtp' ] = vtp( 'header_type="UInt32" compressor="vtkZLibDataCompressor"', {
		normals: a( 'Float32', 'Normals', 3, f32( normals ), 24 ),
		points: a( 'Float32', 'Points', 3, f32( points ), 1000 ),
		strips: a( 'Int64', 'connectivity', 0, i64( stripConnectivity ), 16 ) + a( 'Int64', 'offsets', 0, i64( stripOffsets ), 64 ),
		polys: a( 'Int32', 'connectivity', 0, i32( polyConnectivity ), 12 ) + a( 'Int32', 'offsets', 0, i32( polyOffsets ), 64 ),
	} );
}

{
	// Appended base64: each array's offset into the text after `_`.
	const parts = [];
	let offset = 0;
	const a = ( type, name, comps, bytes ) => {
		const text = b64( cat( u32( bytes.length ), bytes ) );
		const tag = `<DataArray type="${ type }" Name="${ name }" ${ comps ? `NumberOfComponents="${ comps }"` : '' } format="appended" offset="${ offset }"/>`;
		parts.push( text );
		offset += text.length;
		return tag;
	};
	// In three.js's order: point data, points, strips, polys.
	const arrays = {
		normals: a( 'Float32', 'Normals', 3, f32( normals ) ),
		points: a( 'Float32', 'Points', 3, f32( points ) ),
		strips: a( 'Int32', 'connectivity', 0, i32( stripConnectivity ) ) + a( 'Int32', 'offsets', 0, i32( stripOffsets ) ),
		polys: a( 'Int32', 'connectivity', 0, i32( polyConnectivity ) ) + a( 'Int32', 'offsets', 0, i32( polyOffsets ) ),
	};
	files[ 'appended.vtp' ] = vtp( 'header_type="UInt32"', arrays,
		`\n  <AppendedData encoding="base64">\n   _${ parts.join( '' ) }\n  </AppendedData>` );
}

// XML edges, one file each, as three.js reads them.
const comment = `<!-- ${ 'an edge case of the VTK XML reader '.repeat( 8 ) } -->`;
const doc = ( attrs, body, tail = '' ) => `<?xml version="1.0"?>
${ comment }
<VTKFile type="PolyData"${ attrs }>
  <PolyData>${ body }</PolyData>${ tail }
</VTKFile>
`;
const url = ( bytes ) => b64( bytes ).replace( /\+/g, '-' ).replace( /\//g, '_' );

// No header_type: nothing is cut from a binary array. base64url, one and
// two `=`, and a character outside base64 read as zero.
files[ 'base64.vtp' ] = doc( ' version="1.0"', `
    <Piece NumberOfPoints="1" NumberOfPolys="1">
      <PointData Normals="N"><DataArray type="Float32" Name="N" NumberOfComponents="3" format="binary">${ b64( f32( [ 0.5 ] ) ) }</DataArray></PointData>
      <Points><DataArray type="Int32" NumberOfComponents="3" format="binary">${ url( i32( [ - 1, 16777215 ] ) ) }</DataArray></Points>
      <Polys>
        <DataArray type="Int32" Name="connectivity" format="binary">${ '*AAA' + b64( i32( [ 0, 0 ] ) ).slice( 4 ) }</DataArray>
        <DataArray type="Int32" Name="offsets" format="binary">${ b64( i32( [ 3 ] ) ) }</DataArray>
      </Polys>
    </Piece>` );

// Appended data whose offsets are not all numbers: a missing one starts at
// zero, a word reads zero, a negative one counts from the end, and the last
// runs to the end.
{
	const A = b64( cat( u32( 12 ), f32( [ 1, 2, 3 ] ) ) );
	const C = b64( cat( u32( 12 ), i32( [ 0, 0, 0 ] ) ) );
	const O = b64( cat( u32( 4 ), i32( [ 3 ] ) ) );
	const text = A + C + O;
	files[ 'offsets.vtp' ] = doc( ' header_type="UInt32"', `
    <Piece NumberOfPoints="1" NumberOfPolys="1">
      <CellData><DataArray type="Int32" Name="skipped" format="appended"/></CellData>
      <Points><DataArray type="Float32" NumberOfComponents="3" format="appended" offset="word"/></Points>
      <Polys><DataArray type="Int32" Name="connectivity" format="appended" offset="-${ C.length + O.length }"/><DataArray type="Int32" Name="offsets" format="appended" offset="${ A.length + C.length }"/></Polys>
    </Piece>`, `
  <AppendedData encoding="base64">_${ text }</AppendedData>` );
}

// UInt64 zlib headers: a block count whose fourth byte sets the sign bit
// is negative, so nothing is read; a count of zero reads nothing either.
files[ 'headers.vtp' ] = doc( ' header_type="UInt64" compressor="vtkZLibDataCompressor"', `
    <Piece NumberOfPoints="1" NumberOfPolys="1">
      <PointData Normals="Normals"><DataArray type="Float32" Name="Normals" NumberOfComponents="3" format="binary">${ b64( new Uint8Array( 24 ) ) }</DataArray></PointData>
      <Points><DataArray type="Float32" NumberOfComponents="3" format="binary">${ b64( cat( new Uint8Array( [ 0, 0, 0, 0x80, 0, 0, 0, 0 ] ), new Uint8Array( 16 ) ) ) }</DataArray></Points>
      <Polys><DataArray type="Int32" Name="connectivity" format="ascii">0 0 0</DataArray><DataArray type="Int32" Name="offsets" format="ascii">3</DataArray></Polys>
    </Piece>` );

const reference = {};
for ( const [ name, content ] of Object.entries( files ) ) {
	const bytes = typeof content === 'string' ? Buffer.from( content, 'utf8' ) : content;
	writeFileSync( name, bytes );
	const buffer = bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.length );
	const geometry = new VTKLoader().parse( buffer );
	const out = { index: geometry.index ? Array.from( geometry.index.array ) : null };
	for ( const key of [ 'position', 'normal', 'color' ] ) {
		const attribute = geometry.getAttribute( key );
		if ( attribute ) out[ key ] = Array.from( attribute.array );
	}
	reference[ name ] = out;
}
writeFileSync( 'vtk.json', JSON.stringify( reference ) );
